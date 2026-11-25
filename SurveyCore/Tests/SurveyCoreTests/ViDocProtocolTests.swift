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
        XCTAssertEqual(ViDocProtocol.lightOff(trailed: false), Data([0x55, 0x05, 0x00, 0x5A]))
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

    func testRangeUsesUnsignedDistanceAndMedianOfGoodSamples() throws {
        var missed = Data([0x01, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x10])
        missed.append(ViDocProtocol.checksum(of: missed))
        guard case let .range(_, _, distance, quality) = try XCTUnwrap(ViDocReply.decode(missed, expect: .range)) else {
            return XCTFail("距離を読めない")
        }
        XCTAssertEqual(distance, 0xFFFF)
        XCTAssertEqual(quality, 0x0010)
        XCTAssertFalse(LaserRangeBatch.usable(distanceMillimetres: distance, quality: quality, down: true))
        XCTAssertFalse(LaserRangeBatch.usable(distanceMillimetres: 1_500, quality: 1100, down: true))
        XCTAssertFalse(LaserRangeBatch.usable(distanceMillimetres: 40_000, quality: 100, down: true))
        XCTAssertFalse(LaserRangeBatch.usable(distanceMillimetres: 20_000, quality: 100, down: false))
        XCTAssertTrue(LaserRangeBatch.usable(distanceMillimetres: 1_200, quality: 601, down: true))
        let median = LaserRangeBatch.medianMeters(
            [
                (distanceMillimetres: 1_000, quality: 100),
                (distanceMillimetres: 0xFFFF, quality: 10),
                (distanceMillimetres: 1_400, quality: 1100),
                (distanceMillimetres: 1_200, quality: 700),
                (distanceMillimetres: 1_600, quality: 200)
            ],
            down: true
        )
        XCTAssertEqual(median ?? 0, 1.2, accuracy: 1e-9)
        XCTAssertNil(LaserRangeBatch.medianMeters([(distanceMillimetres: 0xFFFF, quality: 1)], down: true))

        var modern = ViDocCommandPlan()
        _ = modern.nmeaWasSent(at: 0)
        _ = modern.receive(.switched, at: 0.1)
        _ = modern.lightDown(at: 0.4)
        XCTAssertEqual(modern.lamp, .aiming)
        let frame = modern.measureDown(seconds: 5, at: 1)
        XCTAssertEqual(modern.lamp, .ranging)
        let trailer = Data([0x3C, 0x3B, 0x3D, 0x01, 0x03, 0x02])
        XCTAssertEqual(frame, [Data([0x55, 0x03, 0x05, 0x5D]) + trailer])
        XCTAssertEqual(frame.first?.count, 10)
        XCTAssertNotEqual(frame.first?[1], 4)
        let samples = [1_000, 1_000, 1_200, 1_200, 1_200, 1_400, 1_400]
        for (index, distance) in samples.enumerated() {
            let replies = modern.receive(.range(startMillimetres: 0, endMillimetres: 0, distanceMillimetres: distance, quality: 10), at: 2)
            if index < samples.count - 1 {
                XCTAssertTrue(replies.isEmpty)
            } else {
                XCTAssertEqual(replies.first, ViDocProtocol.lightOff(trailed: true))
            }
        }
        XCTAssertEqual(modern.takeLaserReading(), .meters(1.2))
        XCTAssertEqual(modern.lamp, .off)
    }

    func testLegacyOffFollowsTheBeamAndRangeLimitsReject() {
        let trailer = Data([0x3C, 0x3B, 0x3D, 0x01, 0x03, 0x02])
        XCTAssertEqual(ViDocProtocol.lightOn(down: false, trailed: false), Data([0x55, 0x14, 0x00, 0x69]))
        XCTAssertEqual(ViDocProtocol.lightOn(down: false, trailed: true), Data([0x55, 0x14, 0x00, 0x69]) + trailer)
        XCTAssertEqual(ViDocProtocol.lightOff(down: true, trailed: false), Data([0x55, 0x05, 0x00, 0x5A]))
        XCTAssertEqual(ViDocProtocol.lightOff(down: false, trailed: false), Data([0x55, 0x15, 0x00, 0x6A]))
        XCTAssertEqual(ViDocProtocol.lightOff(down: true, trailed: true), Data([0x55, 0x05, 0x00, 0x5A]) + trailer)
        XCTAssertEqual(ViDocProtocol.lightOff(down: false, trailed: true), Data([0x55, 0x05, 0x00, 0x5A]) + trailer)
        XCTAssertFalse(LaserRangeBatch.usable(distanceMillimetres: 20_000, quality: 100, down: false))
        XCTAssertFalse(LaserRangeBatch.usable(distanceMillimetres: 40_000, quality: 100, down: true))
        XCTAssertTrue(LaserRangeBatch.usable(distanceMillimetres: 19_999, quality: 100, down: false))
        XCTAssertTrue(LaserRangeBatch.usable(distanceMillimetres: 39_999, quality: 100, down: true))
        XCTAssertNil(LaserRangeBatch.medianMeters([(distanceMillimetres: 20_000, quality: 100)], down: false))
        XCTAssertNil(LaserRangeBatch.medianMeters([(distanceMillimetres: 40_000, quality: 100)], down: true))

        var legacy = ViDocCommandPlan()
        _ = legacy.nmeaWasSent(at: 0)
        _ = legacy.tick(at: 1)
        _ = legacy.tick(at: 2)
        _ = legacy.lightFront(at: 10)
        XCTAssertEqual(legacy.tick(at: 40), [Data([0x55, 0x15, 0x00, 0x6A])])
    }

    func testLaserWaitsHalfASecondThenBlinksAndTurnsOffAfterThirty() {
        var plan = ViDocCommandPlan()
        _ = plan.nmeaWasSent(at: 0)
        _ = plan.tick(at: 1)
        _ = plan.tick(at: 2)
        XCTAssertEqual(plan.mode, .legacy)
        XCTAssertEqual(plan.measureDown(seconds: 5, at: 3), [])
        XCTAssertEqual(plan.lamp, .off)
        XCTAssertEqual(plan.lightDown(at: 10), [Data([0x55, 0x04, 0x00, 0x59])])
        XCTAssertEqual(plan.lamp, .aiming)
        XCTAssertEqual(plan.measureDown(seconds: 5, at: 10.49), [])
        XCTAssertEqual(plan.lamp, .aiming)
        XCTAssertEqual(plan.tick(at: 10.49), [])
        let ranged = plan.tick(at: 10.5)
        XCTAssertEqual(ranged, [Data([0x55, 0x03, 0x05, 0x5D])])
        XCTAssertEqual(plan.lamp, .ranging)
        XCTAssertFalse(ranged.contains { $0.dropFirst().first == 4 })

        var idle = ViDocCommandPlan()
        _ = idle.nmeaWasSent(at: 0)
        _ = idle.tick(at: 1)
        _ = idle.tick(at: 2)
        _ = idle.lightDown(at: 10)
        XCTAssertEqual(idle.tick(at: 39.9), [])
        XCTAssertEqual(idle.lamp, .aiming)
        XCTAssertEqual(idle.tick(at: 40), [Data([0x55, 0x05, 0x00, 0x5A])])
        XCTAssertEqual(idle.lamp, .off)
        XCTAssertEqual(idle.tick(at: 41), [])
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
        _ = plan.lightDown(at: 2.4)
        let legacy = plan.measureDown(seconds: 5, at: 3)
        XCTAssertEqual(legacy, [Data([0x55, 0x03, 0x05, 0x5D])])
        XCTAssertTrue(plan.receive(.range(startMillimetres: 0, endMillimetres: 0, distanceMillimetres: 1500, quality: 1), at: 4).isEmpty)
        let off = plan.tick(at: 10)
        XCTAssertEqual(off.first, ViDocProtocol.lightOff(trailed: false))
        XCTAssertEqual(plan.takeLaserReading(), .meters(1.5))

        var modern = ViDocCommandPlan()
        _ = modern.nmeaWasSent(at: 0)
        XCTAssertEqual(modern.receive(.switched, at: 0.2), [ViDocProtocol.versionFrame()!])
        XCTAssertEqual(modern.mode, .modern)
        let angle = modern.receive(.version(label: "3.0.0 build 0 hw 1.5"), at: 0.4)
        XCTAssertEqual(angle, [ViDocProtocol.imu(.angle)!])
        XCTAssertEqual(modern.firmwareLabel, "3.0.0 build 0 hw 1.5")
        modern.observing = true
        XCTAssertEqual(
            modern.receive(.angle(pitchDegrees: 0.1, rollDegrees: 0), at: 1).first,
            ViDocProtocol.imu(.angle)
        )
        modern.observing = false
        _ = modern.lightFront(at: 2)
        let front = modern.measureFront(seconds: 5, at: 2.5)
        let trailer = Data([0x3C, 0x3B, 0x3D, 0x01, 0x03, 0x02])
        XCTAssertEqual(front, [Data([0x55, 0x13, 0x05, 0x6D]) + trailer])

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
