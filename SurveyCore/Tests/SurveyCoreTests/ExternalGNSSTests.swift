import XCTest
@testable import SurveyCore

final class ExternalGNSSTests: XCTestCase {
    func testGGARoundTripKeepsFixHeightAndSatellites() {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let gga = NMEA.gga(
            latitudeDegrees: 36.77450,
            longitudeDegrees: 139.20081,
            quality: 4,
            satellites: 18,
            hdop: 0.6,
            orthometricMeters: 945.8,
            geoidSeparationMeters: 43.2,
            ageSeconds: 2,
            station: "0012",
            at: when
        )
        let gstBody = "GNGST,092750.00,1.0,0.01,0.01,0,0.008,0.006,0.012"
        let gst = "$\(gstBody)*\(NMEA.checksum(gstBody))"
        let rmcBody = "GNRMC,092750.00,A,3646.4700,N,13912.0486,E,0.1,90.0,210326,,,A"
        let rmc = "$\(rmcBody)*\(NMEA.checksum(rmcBody))"
        let position = NMEA.position(from: [rmc, gst, gga], at: when)
        XCTAssertEqual(position?.fixQuality, .rtkFix)
        XCTAssertEqual(position?.receiver, .rtk)
        XCTAssertEqual(position?.stage, .rtk)
        XCTAssertEqual(position?.latitudeDegrees ?? 0, 36.77450, accuracy: 1e-6)
        XCTAssertEqual(position?.longitudeDegrees ?? 0, 139.20081, accuracy: 1e-6)
        XCTAssertEqual(position?.meanSeaLevelMeters ?? 0, 945.8, accuracy: 0.001)
        XCTAssertEqual(position?.ellipsoidalHeightMeters ?? 0, 989.0, accuracy: 0.001)
        XCTAssertEqual(position?.satelliteCount, 18)
        XCTAssertEqual(position?.correctionAgeSeconds ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(position?.courseDegrees ?? 0, 90, accuracy: 0.001)
        XCTAssertEqual(position?.solutionLabel, "FIX")
        XCTAssertEqual(position?.horizontalAccuracyMeters ?? 0, (0.008 * 0.008 + 0.006 * 0.006).squareRoot(), accuracy: 1e-9)
        XCTAssertNil(NMEA.parse("$GNGGA,broken*00"))
    }

    func testDGPSFloatAndNoFixMapToThePillWords() {
        XCTAssertEqual(NMEA.fixQuality(2), .dgps)
        XCTAssertEqual(NMEA.fixQuality(5), .float)
        XCTAssertEqual(NMEA.fixQuality(0), .none)
        let dgps = samplePosition(accuracy: 0.4, stage: .iphone, quality: .dgps, receiver: .rtk, satelliteCount: 14, correctionAgeSeconds: 3)
        XCTAssertEqual(dgps.solutionLabel, "DGPS")
        XCTAssertEqual(AccuracyFormat.statusLine(for: dgps), "DGPS ±40cm 補正3秒 衛星14")
        let float = samplePosition(accuracy: 0.2, stage: .rtk, quality: .float, receiver: .rtk, satelliteCount: 20, correctionAgeSeconds: 1)
        XCTAssertEqual(AccuracyFormat.statusLine(for: float), "FLOAT ±20cm 補正1秒 衛星20")
        XCTAssertEqual(AccuracyFormat.statusLine(for: samplePosition()), "単独 推定±3m")
        XCTAssertEqual(AccuracyFormat.statusLine(for: samplePosition(accuracy: 2)), "単独 推定±2m")
        XCTAssertFalse(AccuracyFormat.statusLine(for: float).contains("推定"))
    }

    func testReceiverGapDoesNotUseTheReceiverHeightAsTheSurveyHeight() {
        let line = NMEA.receiverGapLine(receiverOrthometricMeters: 945.8, gsiOrthometricMeters: 945.326)
        XCTAssertEqual(line, "受信機との差 -0.5m")
        XCTAssertNil(NMEA.receiverGapLine(receiverOrthometricMeters: .nan, gsiOrthometricMeters: 1))
    }

    func testGNSPreciseReportsCLASAndRTKModeDoesNot() {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let gga = NMEA.gga(
            latitudeDegrees: 36.77450,
            longitudeDegrees: 139.20081,
            quality: 4,
            satellites: 18,
            hdop: 0.6,
            orthometricMeters: 945.8,
            geoidSeparationMeters: 43.2,
            ageSeconds: 2,
            station: "",
            at: when
        )
        let precise = "GNGNS,092750.00,3646.4700,N,13912.0486,E,PPP,18,0.6,945.8,43.2,,"
        let clas = NMEA.position(from: [gga, "$\(precise)*\(NMEA.checksum(precise))"], at: when)
        XCTAssertEqual(clas?.fixQuality, .clas)
        XCTAssertEqual(clas?.receiver, .clas)
        XCTAssertEqual(clas?.stage, .clas)
        XCTAssertEqual(clas?.solutionLabel, "CLAS")
        let rtk = "GNGNS,092750.00,3646.4700,N,13912.0486,E,RRR,18,0.6,945.8,43.2,,"
        let fix = NMEA.position(from: [gga, "$\(rtk)*\(NMEA.checksum(rtk))"], at: when)
        XCTAssertEqual(fix?.fixQuality, .rtkFix)
        XCTAssertEqual(fix?.solutionLabel, "FIX")
    }

    func testDroggerFirmwareQueryAndCLASCommand() {
        XCTAssertEqual(DroggerLink.sentence(DroggerLink.firmwareQueryBody), "$PBIZ,query,fwver*1B\r\n")
        XCTAssertEqual(DroggerLink.sentence(DroggerLink.clasBody), "$PBIZ,gnss,1,1,1,1,0,1,1,1,1*38\r\n")
        let ble = DroggerLink.sentence("PBIZR,query,fwver,60,001122,334455,667788,1,4.4.2,")
        XCTAssertEqual(DroggerLink.firmware(in: ble), DroggerLink.Firmware(version: "4.4.2", ble: true))
        XCTAssertTrue(DroggerLink.isAtLeast("4.4.2"))
        XCTAssertTrue(DroggerLink.isAtLeast("4.4.10"))
        XCTAssertFalse(DroggerLink.isAtLeast("4.3.14"))
        let spp = DroggerLink.sentence("PBIZR,query,fwver,60,001122,334455,667788,0,4.5.0,")
        XCTAssertEqual(DroggerLink.firmware(in: spp)?.ble, false)
        XCTAssertNil(DroggerLink.firmware(in: "$PBIZR,query,fwver,1*00"))
    }

    func testNTRIPHeaderKeepsThePasswordOutOfTheOtherLines() {
        let account = NTRIPAccount(host: "caster.example", port: 2101, mountpoint: "/VRS", user: "captain", version: .v2)
        let header = NTRIPRequest.header(account: account, password: "secret", gga: "$GNGGA,000000.00,0000.0000,N,00000.0000,E,1,08,1.0,0.00,M,0.00,M,,*00")
        XCTAssertTrue(header.hasPrefix("GET /VRS HTTP/1.1\r\n"))
        XCTAssertTrue(header.contains("Ntrip-Version: Ntrip/2.0"))
        XCTAssertTrue(header.contains("Host: caster.example:2101"))
        XCTAssertTrue(header.contains("Ntrip-GGA: $GNGGA"))
        let token = Data("captain:secret".utf8).base64EncodedString()
        XCTAssertTrue(header.contains("Authorization: Basic \(token)"))
        XCTAssertFalse(header.contains("\r\nsecret"))
        let v1 = NTRIPRequest.header(account: NTRIPAccount(host: "caster.example", port: 2101, mountpoint: "VRS", user: "captain", version: .v1), password: "secret", gga: nil)
        XCTAssertTrue(v1.hasPrefix("GET /VRS HTTP/1.0\r\n"))
        XCTAssertFalse(v1.contains("Ntrip-GGA"))
        XCTAssertFalse(NTRIPRequest.shouldSendGGA(last: Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 9)))
        XCTAssertTrue(NTRIPRequest.shouldSendGGA(last: Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 10)))
        XCTAssertEqual(NTRIPRequest.ggaInterval, 10)
        XCTAssertEqual(DocomoCaster.host, "d-gnss.jp")
        XCTAssertEqual(DocomoCaster.port, 2101)
        XCTAssertEqual(DocomoCaster.mountpoint, "RRSGD2024")
    }

    func testRTCMFramesSurviveTheHTTPHeadAndABadByte() {
        let payload = Data([0x00, 0x64])
        let frame = RTCM3.frame(payload: payload)
        XCTAssertEqual(RTCM3.crc(Data("123456789".utf8)), 0xCDE703)
        var stream = Data("ICY 200 OK\r\n\r\n".utf8)
        stream.append(0x00)
        stream.append(frame)
        stream.append(0xD3)
        let intake = NTRIPStream.consume(stream)
        XCTAssertEqual(intake.status, 200)
        XCTAssertEqual(intake.failed, false)
        XCTAssertEqual(intake.frames, [frame])
        XCTAssertEqual(intake.pending, Data([0xD3]))
        let denied = NTRIPStream.consume(Data("HTTP/1.0 401 Unauthorized\r\n\r\n".utf8))
        XCTAssertEqual(denied.status, 401)
        XCTAssertTrue(denied.failed)
        XCTAssertTrue(denied.frames.isEmpty)
    }

    func testFallbackUsesDocomoThenCLASThenSingle() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let phone = PositionReading(position: samplePosition(), availability: .available)
        let fix = samplePosition(accuracy: 0.02, stage: .rtk, quality: .rtkFix, receiver: .rtk, satelliteCount: 22, correctionAgeSeconds: 1)
        let receiver = PositionReading(position: fix, availability: .available)
        let live = ExternalPosition.choose(
            iphone: phone,
            receiver: receiver,
            receiverAt: now,
            correctionAt: now,
            now: now,
            previous: .phone
        )
        XCTAssertEqual(live.tier, .docomo)
        XCTAssertTrue(live.usingReceiver)
        XCTAssertEqual(live.reading.position?.fixQuality, .rtkFix)
        XCTAssertNil(live.notice)
        let dropped = ExternalPosition.choose(
            iphone: phone,
            receiver: receiver,
            receiverAt: now,
            correctionAt: now.addingTimeInterval(-11),
            now: now,
            previous: .docomo
        )
        XCTAssertEqual(dropped.tier, .single)
        XCTAssertEqual(dropped.reading.position?.fixQuality, .standalone)
        XCTAssertEqual(dropped.reading.position?.receiver, .rtk)
        XCTAssertEqual(dropped.reading.position?.solutionLabel, "単独")
        XCTAssertEqual(dropped.notice, "補正が切れました。単独測位です。")
        let clasFix = samplePosition(accuracy: 0.05, stage: .clas, quality: .clas, receiver: .clas)
        let clas = ExternalPosition.choose(
            iphone: phone,
            receiver: PositionReading(position: clasFix, availability: .available),
            receiverAt: now,
            correctionAt: now.addingTimeInterval(-11),
            now: now,
            previous: .docomo
        )
        XCTAssertEqual(clas.tier, .clas)
        XCTAssertEqual(clas.reading.position?.solutionLabel, "CLAS")
        XCTAssertEqual(clas.notice, "CLASに切り替えました。")
        let silent = ExternalPosition.choose(
            iphone: phone,
            receiver: nil,
            receiverAt: nil,
            correctionAt: nil,
            now: now,
            previous: .docomo
        )
        XCTAssertEqual(silent.tier, .phone)
        XCTAssertEqual(silent.reading.position?.receiver, .iphoneGPS)
        XCTAssertEqual(silent.notice, "受信機が切れました。iPhoneの測位に戻しました。")
    }

    func testRecordingKeepsTheSolutionTag() {
        let floated = samplePosition(accuracy: 0.2, stage: .rtk, quality: .float, receiver: .rtk)
        XCTAssertFalse(ExternalFix.blocksRecording(workID: "stakeout", position: floated))
        XCTAssertFalse(ExternalFix.blocksRecording(workID: "asBuilt", position: nil))
        XCTAssertFalse(ExternalFix.blocksRecording(workID: "preview", position: samplePosition()))
        XCTAssertEqual(floated.solutionLabel, "FLOAT")
        XCTAssertEqual(samplePosition().solutionLabel, "単独")
        let fix = samplePosition(accuracy: 0.02, verticalAccuracy: 0.02, stage: .rtk, quality: .rtkFix, receiver: .rtk)
        XCTAssertTrue(fix.isTrustedRTKFix)
        XCTAssertEqual(fix.solutionLabel, "FIX")
    }

    func testRTCMLineCountsChunksAndLatency() {
        var meter = RTCMMeter()
        let start = Date(timeIntervalSince1970: 0)
        meter.note(bytes: 2048, chunks: 4, latencySeconds: 0.035, at: start)
        XCTAssertEqual(meter.line(now: start), "RTCM 2.0KB/s 4分割 遅延 35ms")
        let pieces = BLEMTU.split(Data(repeating: 0xD3, count: 50), maximumWriteLength: 23)
        XCTAssertEqual(pieces.map(\.count), [23, 23, 4])
        XCTAssertEqual(BLEMTU.split(Data(repeating: 1, count: 10), maximumWriteLength: 8).count, 1)
        XCTAssertTrue(BLEMTU.split(Data(), maximumWriteLength: 20).isEmpty)
    }
}
