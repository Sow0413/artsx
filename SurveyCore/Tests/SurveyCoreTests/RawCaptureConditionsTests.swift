import XCTest
@testable import SurveyCore

final class RawCaptureConditionsTests: XCTestCase {
    func testOtherOriginalsAreRestoredExactly() {
        var session = RawCaptureSession()
        var writes: [Data] = [session.begin()]
        writes.append(session.onFrame(valget(rate: 200, rawx: 1, sfrbx: 0))!)
        XCTAssertEqual(session.phase, .arming)
        XCTAssertNil(session.onFrame(ack(accepted: true)))
        XCTAssertTrue(session.isRecording)
        let restore = session.stopForStakeout()
        writes.append(restore!)
        XCTAssertEqual(restore, UBXConfig.valsetRAM(rateMeas: 200, rawx: 1, sfrbx: 0))
        XCTAssertFalse(session.isRecording)
        writes.append(session.onFrame(ack(accepted: true))!)
        XCTAssertNil(session.onFrame(valget(rate: 200, rawx: 1, sfrbx: 0)))
        XCTAssertFalse(session.needsRestore)
        assertSafe(writes)
    }

    func testNakOrTimeoutOnStartDoesNotRecordOrChangeSettings() {
        var nak = RawCaptureSession()
        var writes: [Data] = [nak.begin()]
        writes.append(nak.onFrame(valget(rate: 143, rawx: 0, sfrbx: 0))!)
        XCTAssertNil(nak.onFrame(ack(accepted: false)))
        XCTAssertFalse(nak.isRecording)
        XCTAssertNil(nak.valuesToPersist())
        XCTAssertEqual(nak.phase, .finished)

        var unread = RawCaptureSession()
        writes.append(unread.begin())
        XCTAssertNil(unread.onFrame(ack(accepted: false)))
        XCTAssertNil(unread.timedOut())
        XCTAssertFalse(unread.isRecording)

        var timeout = RawCaptureSession()
        writes.append(timeout.begin())
        XCTAssertNil(timeout.timedOut())
        XCTAssertEqual(timeout.phase, .finished)
        XCTAssertNil(timeout.valuesToPersist())

        var late = RawCaptureSession()
        writes.append(late.begin())
        writes.append(late.onFrame(valget(rate: 200, rawx: 1, sfrbx: 0))!)
        let back = late.timedOut()
        writes.append(back!)
        XCTAssertEqual(back, UBXConfig.valsetRAM(rateMeas: 200, rawx: 1, sfrbx: 0))
        XCTAssertFalse(late.isRecording)
        assertSafe(writes)
    }

    func testDisconnectAndRelaunchRestoreThePendingOriginals() throws {
        var session = RawCaptureSession()
        _ = session.begin()
        _ = session.onFrame(valget(rate: 200, rawx: 1, sfrbx: 0))
        _ = session.onFrame(ack(accepted: true))
        let pending = try XCTUnwrap(session.valuesToPersist())
        XCTAssertEqual(pending, UBXConfig.Values(rateMeas: 200, rawx: 1, sfrbx: 0))

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("raw-pending-\(UUID().uuidString)", isDirectory: true)
        try RawPendingRestore.save(pending, in: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let loaded = try XCTUnwrap(RawPendingRestore.load(in: folder))

        var resumed = RawCaptureSession()
        let read = resumed.resume(pending: loaded)
        XCTAssertEqual(read, UBXConfig.valgetRAM())
        let changed = resumed.onFrame(valget(rate: 1000, rawx: 1, sfrbx: 1))
        XCTAssertEqual(changed, UBXConfig.valsetRAM(rateMeas: 200, rawx: 1, sfrbx: 0))
        _ = resumed.onFrame(ack(accepted: true))
        XCTAssertNil(resumed.onFrame(valget(rate: 200, rawx: 1, sfrbx: 0)))
        XCTAssertFalse(resumed.needsRestore)
        RawPendingRestore.clear(in: folder)
        XCTAssertNil(RawPendingRestore.load(in: folder))
        assertSafe([read, changed!])

        try RawPendingRestore.save(loaded, in: folder)
        var killed = RawCaptureSession()
        _ = killed.resume(pending: RawPendingRestore.load(in: folder)!)
        XCTAssertNil(killed.onFrame(valget(rate: 200, rawx: 1, sfrbx: 0)))
        XCTAssertEqual(killed.phase, .finished)
    }

    func testChunkSizesAndSplitSyncKeepMixedFrames() {
        let pvt = nav(klass: 0x01, id: 0x07, payload: Data(repeating: 0x00, count: 92))
        let rawx = nav(klass: 0x02, id: 0x15, payload: rawxPayload(measurements: 0))
        let nmea = Data("$GNGGA,1*00\r\n".utf8)
        let stream = nmea + pvt + rawx + nmea
        for size in [20, 185, 244] {
            var parser = ViDocStreamParser()
            var got: [Data] = []
            parser.onUBX = { frame, _, _ in got.append(frame) }
            var offset = 0
            while offset < stream.count {
                let end = min(offset + size, stream.count)
                _ = parser.feed(stream.subdata(in: offset..<end))
                offset = end
            }
            XCTAssertEqual(got, [pvt, rawx], "MTU \(size)")
            XCTAssertEqual(parser.pendingByteCount, 0)
        }

        var split = ViDocStreamParser()
        var frames: [Data] = []
        split.onUBX = { frame, _, _ in frames.append(frame) }
        _ = split.feed(Data([0xB5]))
        XCTAssertEqual(split.pendingByteCount, 1)
        _ = split.feed(pvt.dropFirst())
        XCTAssertEqual(frames, [pvt])
        XCTAssertEqual(split.pendingByteCount, 0)
    }

    func testNineHundredEpochsKeepEveryFrame() throws {
        let rawx = nav(klass: 0x02, id: 0x15, payload: rawxPayload(measurements: 0))
        var sfrbxPayload = Data(repeating: 0x3C, count: 900)
        sfrbxPayload[0] = 0
        let sfrbx = nav(klass: 0x02, id: 0x13, payload: sfrbxPayload)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("raw-long-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let base = root.appendingPathComponent("long")
        var parser = ViDocStreamParser()
        var rawxCount = 0
        var sfrbxCount = 0
        parser.onUBX = { frame, klass, id in
            RawObsFile.append(frame, base: base)
            if klass == 0x02 && id == 0x15 { rawxCount += 1 }
            if klass == 0x02 && id == 0x13 { sfrbxCount += 1 }
        }
        for _ in 0..<900 {
            _ = parser.feed(rawx)
            _ = parser.feed(sfrbx)
            XCTAssertEqual(parser.pendingByteCount, 0)
        }
        let file = try Data(contentsOf: base.appendingPathExtension("ubx"))
        XCTAssertEqual(rawxCount, 900)
        XCTAssertEqual(sfrbxCount, 900)
        XCTAssertEqual(file.count, 900 * (rawx.count + sfrbx.count))
        XCTAssertEqual(rawx[rawx.firstIndex(of: 0x02)! + 1], 0x15)
    }

    func testStakeoutStopsRecordingAndRestoresImmediately() {
        var session = RawCaptureSession()
        var writes: [Data] = [session.begin()]
        writes.append(session.onFrame(valget(rate: 143, rawx: 0, sfrbx: 0))!)
        _ = session.onFrame(ack(accepted: true))
        XCTAssertTrue(session.isRecording)
        let restore = session.stopForStakeout()
        writes.append(restore!)
        XCTAssertFalse(session.isRecording)
        XCTAssertEqual(restore, UBXConfig.valsetRAM(rateMeas: 143, rawx: 0, sfrbx: 0))
        XCTAssertEqual(session.phase, .restoring(1))
        assertSafe(writes)
    }

    private func assertSafe(_ commands: [Data], file: StaticString = #file, line: UInt = #line) {
        for command in commands {
            XCTAssertNil(RawCommandAudit.violation(in: command), RawCommandAudit.violation(in: command) ?? "", file: file, line: line)
        }
    }

    private func ack(accepted: Bool) -> Data {
        UBXConfig.frame(klass: 0x05, id: accepted ? 0x01 : 0x00, payload: Data([0x06, 0x8A]))
    }

    private func valget(rate: UInt16, rawx: UInt8, sfrbx: UInt8) -> Data {
        var payload = Data([0x00, 0x00, 0x00, 0x00])
        payload.append(UBXConfig.key(UBXConfig.rateMeasKey))
        payload.append(contentsOf: [UInt8(rate & 0xFF), UInt8(rate >> 8)])
        payload.append(UBXConfig.key(UBXConfig.rawxUART1Key))
        payload.append(rawx)
        payload.append(UBXConfig.key(UBXConfig.sfrbxUART1Key))
        payload.append(sfrbx)
        return UBXConfig.frame(klass: 0x06, id: 0x8B, payload: payload)
    }

    private func nav(klass: UInt8, id: UInt8, payload: Data) -> Data {
        UBXConfig.frame(klass: klass, id: id, payload: payload)
    }

    private func rawxPayload(measurements: UInt8) -> Data {
        var payload = Data(repeating: 0x00, count: 16)
        payload[11] = measurements
        return payload
    }
}
