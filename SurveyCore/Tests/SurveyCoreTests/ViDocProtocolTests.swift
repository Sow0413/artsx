import XCTest
@testable import SurveyCore

final class ViDocProtocolTests: XCTestCase {
    func testFramesChecksumEndianAndForbiddenCommands() {
        let trailer = Data([0x3C, 0x3B, 0x3D, 0x01, 0x03, 0x02])
        XCTAssertEqual(ViDocProtocol.switchFrame(), Data([0x55, 0x16, 0x01, 0x6C]) + trailer)
        XCTAssertEqual(ViDocProtocol.versionFrame(), Data([0x55, 0x00, 0x01, 0x56]) + trailer)
        XCTAssertEqual(ViDocProtocol.imu(.angle), Data([0x55, 0x0B, 0x00, 0x60]) + trailer)
        XCTAssertEqual(ViDocProtocol.imu(.accel), Data([0x55, 0x0B, 0x01, 0x61]) + trailer)
        XCTAssertEqual(ViDocProtocol.imu(.mag), Data([0x55, 0x0B, 0x04, 0x64]) + trailer)
        XCTAssertEqual(ViDocProtocol.imu(.temp), Data([0x55, 0x0B, 0x06, 0x66]) + trailer)
        XCTAssertEqual(
            ViDocProtocol.range(down: false, speed: .auto, seconds: 5, trailed: true),
            Data([0x55, 0x13, 0x05, 0x6D]) + trailer
        )
        XCTAssertEqual(
            ViDocProtocol.range(down: true, speed: .auto, seconds: 5, trailed: false),
            Data([0x55, 0x03, 0x05, 0x5D])
        )
        XCTAssertEqual(ViDocProtocol.lightOn(down: true, trailed: true)?.count, 10)
        XCTAssertEqual(ViDocProtocol.lightOff(trailed: false)?.count, 4)
        for command: UInt8 in [7, 8, 10, 12, 13, 14, 15, 23, 0x0C] {
            XCTAssertNil(ViDocProtocol.frame(command: command, payload: 0, trailed: true))
            XCTAssertNil(ViDocProtocol.frame(command: command, payload: 1, trailed: false))
        }
        XCTAssertNil(ViDocProtocol.frame(command: 0x0B, payload: 0x02, trailed: true))
        XCTAssertNotEqual(ViDocProtocol.switchFrame()?.first, 0xB5)
        var outbound = ViDocOutbound()
        outbound.enqueueCommand(ViDocProtocol.switchFrame()!)
        XCTAssertEqual(outbound.nextWrite(maximumChunkBytes: 4)?.count, 10)
    }

    func testVersionRangeAndBannerDoNotCollide() {
        let version = Data([0x01, 0x03, 0x00, 0x00, 0x00, 0x01, 0x05, 0x0A])
        XCTAssertTrue(ViDocProtocol.checksumMatches(version))
        XCTAssertEqual(ViDocReply.decode(version, expect: .version), .version(label: "3.0.0 build 0 hw 1.5"))
        var range = Data([0x01, 0x00, 0x0A, 0x00, 0x14, 0x05, 0xDC, 0x00, 0x03])
        range.append(ViDocProtocol.checksum(of: range))
        XCTAssertEqual(
            ViDocReply.decode(range, expect: .range),
            .range(startMillimetres: 10, endMillimetres: 20, distanceMillimetres: 1500, quality: 3)
        )
        XCTAssertEqual(ViDocReply.decode(Data([0x02, 0x64, 0x66]), expect: .none), .battery(percent: 100))
        XCTAssertEqual(ViDocReply.decode(Data([0x16, 0x01, 0x17]), expect: .none), .switched)

        var pitch = Data([0xB0])
        pitch.append(floatLE(1.5))
        pitch.append(floatLE(-0.25))
        pitch.append(ViDocProtocol.checksum(of: pitch))
        guard case let .angle(parsedPitch, parsedRoll) = ViDocReply.decode(pitch, expect: .none) else {
            return XCTFail("角度を読めない")
        }
        XCTAssertEqual(parsedPitch, 1.5, accuracy: 1e-4)
        XCTAssertEqual(parsedRoll, -0.25, accuracy: 1e-4)

        var parser = ViDocStreamParser()
        let banner = Data([0x02]) + Data("df Ver_3.0.0.0".utf8) + Data([0x03, 0x0D, 0x0A])
        let text = parser.feed(banner)
        XCTAssertEqual(text, [.text("\u{02}df Ver_3.0.0.0\u{03}")])
        XCTAssertEqual(ViDocFirmware.version(in: "\u{02}df Ver_3.0.0.0\u{03}"), "3.0.0.0")

        var mixed = Data([0x02, 0x64, 0x66])
        mixed.append(ubxNavPVT(numSV: 24, newlineInside: true))
        mixed.append(Data("$GNGGA,1\r\n".utf8))
        mixed.append(version)
        let events = parser.feed(mixed)
        XCTAssertTrue(events.contains(.reply(.battery(percent: 100))))
        XCTAssertTrue(events.contains(.text("$GNGGA,1")))
        XCTAssertTrue(events.contains(.reply(.version(label: "3.0.0 build 0 hw 1.5"))))
        XCTAssertEqual(parser.gnss.satelliteCount, 24)

        var dop = ViDocStreamParser()
        _ = dop.feed(ubxNavDOP(pdop: 1.25, hdop: 0.8, vdop: 1.1))
        XCTAssertEqual(dop.gnss.pdop ?? 0, 1.25, accuracy: 1e-9)
        XCTAssertEqual(dop.gnss.hdop ?? 0, 0.8, accuracy: 1e-9)
        XCTAssertEqual(dop.gnss.vdop ?? 0, 1.1, accuracy: 1e-9)
    }

    func testSwitchRetryLegacyLaserAndMADGate() {
        var plan = ViDocCommandPlan()
        XCTAssertEqual(plan.nmeaWasSent(at: 0), [ViDocProtocol.switchFrame()!])
        XCTAssertEqual(plan.receive(.version(label: "3.0.0 build 0 hw 1.5"), at: 0.2), [])
        XCTAssertEqual(plan.mode, .probing)
        XCTAssertEqual(plan.receive(.battery(percent: 100), at: 0.3), [])
        XCTAssertEqual(plan.tick(at: 1), [ViDocProtocol.switchFrame()!])
        XCTAssertTrue(plan.tick(at: 2).isEmpty)
        XCTAssertEqual(plan.mode, .legacy)
        let legacy = plan.measureDown(seconds: 5, at: 3)
        XCTAssertEqual(legacy.map(\.count), [4, 4])
        XCTAssertEqual(legacy.last, Data([0x55, 0x03, 0x05, 0x5D]))
        let off = plan.receive(.range(startMillimetres: 0, endMillimetres: 0, distanceMillimetres: 1500, quality: 1), at: 8)
        XCTAssertEqual(off, [ViDocProtocol.lightOff(trailed: false)!])

        var modern = ViDocCommandPlan()
        _ = modern.nmeaWasSent(at: 0)
        XCTAssertEqual(modern.receive(.switched, at: 0.2), [ViDocProtocol.versionFrame()!])
        XCTAssertEqual(modern.mode, .modern)
        let angle = modern.receive(.version(label: "3.0.0 build 0 hw 1.5"), at: 0.4)
        XCTAssertEqual(angle, [ViDocProtocol.imu(.angle)!])
        XCTAssertEqual(modern.firmwareLabel, "3.0.0 build 0 hw 1.5")

        let stats = TiltMath.stats([0.20, 0.22, 0.21, 0.19, 0.90])
        XCTAssertEqual(stats?.median ?? 0, 0.21, accuracy: 1e-9)
        XCTAssertEqual(stats?.mean ?? 0, 0.205, accuracy: 1e-9)
        XCTAssertEqual(stats?.maximum ?? 0, 0.22, accuracy: 1e-9)
        XCTAssertTrue(PrecisionGate.tiltAllowsStart(degrees: stats?.median))
        XCTAssertFalse(PrecisionGate.tiltAllowsStart(degrees: 0.9))
        XCTAssertEqual(TiltMath.fromPitchRoll(pitchDegrees: 0, rollDegrees: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(TiltMath.fromAcceleration(x: 0, y: 0, z: 16384) ?? -1, 0, accuracy: 1e-6)
    }

    private func floatLE(_ value: Float) -> Data {
        var bits = value.bitPattern.littleEndian
        return Data(bytes: &bits, count: 4)
    }

    private func ubxNavPVT(numSV: UInt8, newlineInside: Bool) -> Data {
        var payload = Data(repeating: 0, count: 92)
        payload[23] = numSV
        if newlineInside { payload[40] = 0x0A }
        return ubx(class: 0x01, id: 0x07, payload: payload)
    }

    private func ubxNavDOP(pdop: Double, hdop: Double, vdop: Double) -> Data {
        var payload = Data(repeating: 0, count: 18)
        putU16(payload: &payload, offset: 6, value: UInt16((pdop * 100).rounded()))
        putU16(payload: &payload, offset: 10, value: UInt16((vdop * 100).rounded()))
        putU16(payload: &payload, offset: 12, value: UInt16((hdop * 100).rounded()))
        return ubx(class: 0x01, id: 0x04, payload: payload)
    }

    private func putU16(payload: inout Data, offset: Int, value: UInt16) {
        payload[offset] = UInt8(value & 0xFF)
        payload[offset + 1] = UInt8(value >> 8)
    }

    private func ubx(class klass: UInt8, id: UInt8, payload: Data) -> Data {
        var frame = Data([0xB5, 0x62, klass, id, UInt8(payload.count & 0xFF), UInt8(payload.count >> 8)])
        frame.append(payload)
        var ckA: UInt8 = 0
        var ckB: UInt8 = 0
        for byte in frame.dropFirst(2) {
            ckA = ckA &+ byte
            ckB = ckB &+ ckA
        }
        frame.append(ckA)
        frame.append(ckB)
        return frame
    }
}
