import XCTest
@testable import SurveyCore

final class RawCaptureTests: XCTestCase {
    func testValgetAndValsetFramesMatchTheRAMOnlyBytes() {
        XCTAssertEqual(
            UBXConfig.valgetRAM(),
            Data([
                0xB5, 0x62, 0x06, 0x8B, 0x10, 0x00,
                0x00, 0x00, 0x00, 0x00,
                0x01, 0x00, 0x21, 0x30,
                0xA5, 0x02, 0x91, 0x20,
                0x32, 0x02, 0x91, 0x20,
                0x30, 0x3B
            ])
        )
        XCTAssertEqual(
            UBXConfig.enableRecording(),
            Data([
                0xB5, 0x62, 0x06, 0x8A, 0x14, 0x00,
                0x00, 0x01, 0x00, 0x00,
                0x01, 0x00, 0x21, 0x30, 0xE8, 0x03,
                0xA5, 0x02, 0x91, 0x20, 0x01,
                0x32, 0x02, 0x91, 0x20, 0x01,
                0x21, 0xF8
            ])
        )
        XCTAssertEqual(
            UBXConfig.valsetRAM(rateMeas: 143, rawx: 0, sfrbx: 0),
            Data([
                0xB5, 0x62, 0x06, 0x8A, 0x14, 0x00,
                0x00, 0x01, 0x00, 0x00,
                0x01, 0x00, 0x21, 0x30, 0x8F, 0x00,
                0xA5, 0x02, 0x91, 0x20, 0x00,
                0x32, 0x02, 0x91, 0x20, 0x00,
                0xC3, 0xA4
            ])
        )
        XCTAssertNotEqual(UBXConfig.enableRecording()[2], 0x04)
        XCTAssertNotEqual(UBXConfig.enableRecording()[3], 0x09)
        XCTAssertEqual(UBXConfig.enableRecording()[7], 0x01)
    }

    func testRestoreRetriesThreeTimesThenMarksUnverified() {
        var session = RawCaptureSession()
        XCTAssertEqual(session.begin(), UBXConfig.valgetRAM())
        let originals = valget(rate: 143, rawx: 0, sfrbx: 0)
        XCTAssertEqual(session.onFrame(originals), UBXConfig.enableRecording())
        XCTAssertEqual(session.originals, UBXConfig.Values(rateMeas: 143, rawx: 0, sfrbx: 0))
        XCTAssertEqual(session.phase, .recording)

        let restore = UBXConfig.valsetRAM(rateMeas: 143, rawx: 0, sfrbx: 0)
        XCTAssertEqual(session.end(), restore)
        XCTAssertEqual(session.onFrame(ack()), UBXConfig.valgetRAM())
        XCTAssertEqual(session.onFrame(valget(rate: 1000, rawx: 1, sfrbx: 1)), restore)
        XCTAssertEqual(session.onFrame(ack()), UBXConfig.valgetRAM())
        XCTAssertEqual(session.onFrame(valget(rate: 1000, rawx: 1, sfrbx: 1)), restore)
        XCTAssertEqual(session.onFrame(ack()), UBXConfig.valgetRAM())
        XCTAssertNil(session.onFrame(valget(rate: 1000, rawx: 1, sfrbx: 1)))
        XCTAssertTrue(session.restoreUnverified)
        XCTAssertEqual(session.phase, .finished)

        var again = RawCaptureSession()
        _ = again.begin()
        _ = again.onFrame(originals)
        _ = again.end()
        _ = again.onFrame(ack())
        XCTAssertNil(again.onFrame(valget(rate: 143, rawx: 0, sfrbx: 0)))
        XCTAssertFalse(again.restoreUnverified)
    }

    func testFFF1ChunksKeepOnlyValidUBXFrames() throws {
        let pvt = nav(klass: 0x01, id: 0x07, payload: pvtPayload(numSV: 12))
        let dop = nav(klass: 0x01, id: 0x04, payload: dopPayload(pdop: 1.5, hdop: 0.8, vdop: 1.1))
        let rawx = nav(klass: 0x02, id: 0x15, payload: Data(repeating: 0x11, count: 48))
        let rawx2 = nav(klass: 0x02, id: 0x15, payload: Data(repeating: 0x12, count: 24))
        let sfrbx = nav(klass: 0x02, id: 0x13, payload: Data(repeating: 0x21, count: 16))
        var bad = nav(klass: 0x13, id: 0x00, payload: Data(repeating: 0x00, count: 4))
        bad[bad.count - 1] ^= 0xFF
        let truncated = Data([0xB5, 0x62, 0x02, 0x15, 0x20, 0x00]) + Data(repeating: 0x01, count: 8)
        let zeroRange = Data([0x01, 0x00, 0x6F, 0x02, 0x6F, 0x00, 0x00, 0x03, 0xDE, 0xC2])
        let normalRange = Data([0x01, 0x00, 0x70, 0x02, 0x6D, 0x03, 0xDE, 0x01, 0x66, 0x28])
        let valid = [pvt, dop, rawx, sfrbx, rawx2, pvt]
        var stream = Data()
        stream.append(Data("$GNGGA,1,3506.936,N,13654.126,E,1,08,1.0,10.0,M,0.0,M,,*00\r\n".utf8))
        stream.append(pvt)
        stream.append(zeroRange)
        stream.append(dop)
        stream.append(rawx)
        stream.append(bad)
        stream.append(Data("$GNRMC,1,A*00\r\n".utf8))
        stream.append(sfrbx)
        stream.append(normalRange)
        stream.append(rawx2)
        stream.append(pvt)
        stream.append(truncated)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("raw-fff1-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let base = root.appendingPathComponent("T1_20261125T000000Z")
        var parser = ViDocStreamParser()
        parser.expect = .range
        var counts: [UInt16: Int] = [:]
        parser.onUBX = { frame, klass, id in
            RawObsFile.append(frame, base: base)
            counts[UInt16(klass) << 8 | UInt16(id), default: 0] += 1
        }
        var ranges: [(Int, Int)] = []
        for chunk in notifyChunks(stream) {
            for event in parser.feed(chunk) {
                if case let .reply(.range(_, _, distance, quality)) = event {
                    ranges.append((distance, quality))
                }
            }
        }
        let file = try Data(contentsOf: base.appendingPathExtension("ubx"))
        XCTAssertEqual(file, Data(valid.joined()))
        XCTAssertEqual(counts[0x0107], 2)
        XCTAssertEqual(counts[0x0104], 1)
        XCTAssertEqual(counts[0x0215], 2)
        XCTAssertEqual(counts[0x0213], 1)
        XCTAssertEqual(counts.values.reduce(0, +), valid.count)
        XCTAssertEqual(parser.gnss.satelliteCount, 12)
        XCTAssertEqual(parser.gnss.pdop ?? 0, 1.5, accuracy: 1e-9)
        XCTAssertEqual(parser.gnss.hdop ?? 0, 0.8, accuracy: 1e-9)
        XCTAssertEqual(parser.gnss.vdop ?? 0, 1.1, accuracy: 1e-9)
        XCTAssertEqual(ranges.map(\.0), [0, 990])
        XCTAssertEqual(ranges.map(\.1), [990, 358])
        XCTAssertFalse(LaserRangeBatch.usable(distanceMillimetres: 0, quality: 990, down: true))
        XCTAssertEqual(
            LaserRangeBatch.medianMeters([(distanceMillimetres: 0, quality: 990), (distanceMillimetres: 990, quality: 358)], down: true) ?? 0,
            0.990,
            accuracy: 1e-9
        )
        XCTAssertNil(LaserRangeBatch.medianMeters([(distanceMillimetres: 0, quality: 990)], down: true))
    }

    func testValgetValsetAckBytesRestore143OrMarkUnverified() {
        let box = CaptureBox()
        XCTAssertEqual(box.session.begin(), UBXConfig.valgetRAM())
        box.feed(chunks: notifyChunks(valget(rate: 143, rawx: 0, sfrbx: 0)))
        XCTAssertEqual(box.outgoing, [UBXConfig.enableRecording()])
        XCTAssertEqual(box.session.originals, UBXConfig.Values(rateMeas: 143, rawx: 0, sfrbx: 0))
        let restore = UBXConfig.valsetRAM(rateMeas: 143, rawx: 0, sfrbx: 0)
        XCTAssertEqual(box.session.end(), restore)
        box.outgoing.removeAll()
        box.feed(chunks: notifyChunks(ack(id: 0x01)))
        XCTAssertEqual(box.outgoing, [UBXConfig.valgetRAM()])
        box.outgoing.removeAll()
        box.feed(chunks: notifyChunks(valget(rate: 143, rawx: 0, sfrbx: 0)))
        XCTAssertTrue(box.outgoing.isEmpty)
        XCTAssertFalse(box.session.restoreUnverified)
        XCTAssertEqual(box.session.phase, .finished)

        let failed = CaptureBox()
        _ = failed.session.begin()
        failed.feed(chunks: notifyChunks(valget(rate: 143, rawx: 0, sfrbx: 0)))
        XCTAssertEqual(failed.session.end(), restore)
        failed.outgoing.removeAll()
        failed.feed(chunks: notifyChunks(ack(id: 0x00)))
        XCTAssertEqual(failed.outgoing, [restore])
        failed.outgoing.removeAll()
        failed.feed(chunks: notifyChunks(ack(id: 0x00)))
        XCTAssertEqual(failed.outgoing, [restore])
        failed.outgoing.removeAll()
        failed.feed(chunks: notifyChunks(ack(id: 0x00)))
        XCTAssertTrue(failed.outgoing.isEmpty)
        XCTAssertTrue(failed.session.restoreUnverified)
        XCTAssertEqual(failed.session.phase, .finished)
        XCTAssertEqual(RawObsFile.restoreUnverified, "戻し未確認")
        XCTAssertEqual(UBXConfig.enableRecording()[2], 0x06)
        XCTAssertEqual(UBXConfig.enableRecording()[3], 0x8A)
        XCTAssertEqual(UBXConfig.enableRecording()[7], 0x01)
        XCTAssertNotEqual(UBXConfig.valgetRAM()[2], 0x04)
        XCTAssertNotEqual(restore[2], 0x09)
    }

    private func ack() -> Data {
        UBXConfig.frame(klass: 0x05, id: 0x01, payload: Data([0x06, 0x8A]))
    }

    private func notifyChunks(_ data: Data) -> [Data] {
        var chunks: [Data] = []
        var offset = 0
        var wide = false
        while offset < data.count {
            let size = min(wide ? 182 : 20, data.count - offset)
            chunks.append(data.subdata(in: offset..<(offset + size)))
            offset += size
            wide.toggle()
        }
        return chunks
    }

    private func nav(klass: UInt8, id: UInt8, payload: Data) -> Data {
        UBXConfig.frame(klass: klass, id: id, payload: payload)
    }

    private func pvtPayload(numSV: UInt8) -> Data {
        var payload = Data(repeating: 0x00, count: 92)
        payload[23] = numSV
        return payload
    }

    private func dopPayload(pdop: Double, hdop: Double, vdop: Double) -> Data {
        var payload = Data(repeating: 0x00, count: 18)
        put(UInt16((pdop * 100).rounded()), at: 6, into: &payload)
        put(UInt16((vdop * 100).rounded()), at: 10, into: &payload)
        put(UInt16((hdop * 100).rounded()), at: 12, into: &payload)
        return payload
    }

    private func put(_ value: UInt16, at offset: Int, into payload: inout Data) {
        payload[offset] = UInt8(value & 0xFF)
        payload[offset + 1] = UInt8(value >> 8)
    }

    private func ack(id: UInt8) -> Data {
        UBXConfig.frame(klass: 0x05, id: id, payload: Data([0x06, 0x8A]))
    }

    private func valget(rate: UInt16, rawx: UInt8, sfrbx: UInt8) -> Data {
        var payload = Data([0x00, 0x00, 0x00, 0x00])
        payload.append(UBXConfig.key(UBXConfig.rateMeasKey))
        payload.append(UInt8(rate & 0xFF))
        payload.append(UInt8((rate >> 8) & 0xFF))
        payload.append(UBXConfig.key(UBXConfig.rawxUART1Key))
        payload.append(rawx)
        payload.append(UBXConfig.key(UBXConfig.sfrbxUART1Key))
        payload.append(sfrbx)
        return UBXConfig.frame(klass: 0x06, id: 0x8B, payload: payload)
    }
}

private final class CaptureBox {
    var session = RawCaptureSession()
    var outgoing: [Data] = []
    private var parser = ViDocStreamParser()

    func feed(chunks: [Data]) {
        parser.onUBX = { [weak self] frame, _, _ in
            guard let self else { return }
            if let next = self.session.onFrame(frame) {
                self.outgoing.append(next)
            }
        }
        for chunk in chunks {
            _ = parser.feed(chunk)
        }
    }
}
