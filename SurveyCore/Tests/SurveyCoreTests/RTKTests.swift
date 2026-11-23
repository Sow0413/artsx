import XCTest
@testable import SurveyCore

final class RTKTests: XCTestCase {
    func testGGAFixConvertsDegreesAndEstimatesAccuracy() {
        var parser = NMEAParser()
        let epoch = parser.consume("$GNGGA,092750.000,3541.0000,N,13945.0000,E,4,12,0.9,40.5,M,36.7,M,2.0,1234*5A")
        XCTAssertEqual(epoch?.latitudeDegrees ?? -1, 35 + 41.0 / 60.0, accuracy: 1e-7)
        XCTAssertEqual(epoch?.longitudeDegrees ?? -1, 139.75, accuracy: 1e-7)
        XCTAssertEqual(epoch?.ellipsoidalHeightMeters ?? -1, 77.2, accuracy: 1e-6)
        XCTAssertEqual(epoch?.fixQuality, .rtkFix)
        XCTAssertEqual(epoch?.stage, .rtk)
        XCTAssertEqual(epoch?.satelliteCount, 12)
        XCTAssertEqual(epoch?.correctionAgeSeconds ?? -1, 2, accuracy: 1e-9)
        XCTAssertEqual(epoch?.stationID, "1234")
        XCTAssertEqual(epoch?.horizontalAccuracyMeters ?? -1, 0.009, accuracy: 1e-6)
        XCTAssertEqual(epoch?.verticalAccuracyMeters ?? -1, 0.0162, accuracy: 1e-6)
        XCTAssertEqual(epoch?.sentence.hasPrefix("$GNGGA"), true)
        XCTAssertEqual(epoch?.sentence.contains("*"), true)
    }

    func testGSTAndGSAApplyOnTheNextGGA() {
        var parser = NMEAParser()
        XCTAssertNil(parser.consume("$GNGST,092750.000,0.02,0.01,0.01,0,0.006,0.008,0.015*00"))
        XCTAssertNil(parser.consume("$GNGSA,A,3,01,02,03,04,05,06,07,08,09,10,11,12,1.4,0.9,1.1*00"))
        XCTAssertEqual(parser.pdop ?? -1, 1.4, accuracy: 1e-9)
        let epoch = parser.consume("$GNGGA,092751.000,3541.0000,S,13945.0000,W,5,9,1.0,10,M,36,M,1.5,9*00")
        XCTAssertEqual(epoch?.latitudeDegrees ?? 0, -(35 + 41.0 / 60.0), accuracy: 1e-7)
        XCTAssertEqual(epoch?.longitudeDegrees ?? 0, -139.75, accuracy: 1e-7)
        XCTAssertEqual(epoch?.fixQuality, .float)
        XCTAssertEqual(epoch?.stage, .rtk)
        XCTAssertEqual(epoch?.pdop ?? -1, 1.4, accuracy: 1e-9)
        XCTAssertEqual(epoch?.horizontalAccuracyMeters ?? -1, 0.01, accuracy: 1e-6)
        XCTAssertEqual(epoch?.verticalAccuracyMeters ?? -1, 0.015, accuracy: 1e-6)
    }

    func testQualityWordsAndEmptyAge() {
        var parser = NMEAParser()
        let dgps = parser.consume("$GNGGA,092750.000,3540.0000,N,13940.0000,E,2,8,1.0,1,M,36,M,0.5,42*00")
        XCTAssertEqual(dgps?.fixQuality, .dgps)
        XCTAssertEqual(dgps?.stage, .iphone)
        let alone = parser.consume("$GNGGA,092750.000,3540.0000,N,13940.0000,E,1,8,1.2,10.0,M,36.0,M,,*00")
        XCTAssertEqual(alone?.fixQuality, .standalone)
        XCTAssertNil(alone?.correctionAgeSeconds)
        XCTAssertEqual(alone?.stationID, "")
        XCTAssertEqual(alone?.horizontalAccuracyMeters ?? -1, 1.8, accuracy: 1e-6)
        XCTAssertNil(parser.consume("not nmea"))
        XCTAssertNil(parser.consume("$GNGGA,short"))
    }

    func testDGPSLabelStaysOffIPhone() {
        let external = samplePosition(accuracy: 1.2, verticalAccuracy: 2, quality: .dgps, receiver: .rtk)
        XCTAssertEqual(external.solutionLabel, "DGPS")
        let badge = AccuracyPolicy.badge(for: PositionReading(position: external, availability: .available))
        XCTAssertEqual(badge.solutionLabel, "DGPS")
        XCTAssertTrue(badge.text.hasPrefix("DGPS　"))
        var phone = external
        phone.receiver = .iphoneGPS
        XCTAssertEqual(phone.solutionLabel, "単独")
        XCTAssertEqual(FixQualityLabel.of(.dgps, receiver: "RTK"), "DGPS")
        XCTAssertEqual(FixQualityLabel.of(.dgps, receiver: "iPhone"), "単独")
    }

    func testSettingsRoundTripOmitsPassword() throws {
        let directory = try TestFiles.directory()
        defer { TestFiles.remove(directory) }
        let settings = RTKSettings(correctionsEnabled: false, host: "d-gnss.jp", port: 2101, mountpoint: .rrsg, user: "field-user")
        RTKSettingsStore.save(settings, to: directory)
        let loaded = RTKSettingsStore.load(from: directory)
        XCTAssertEqual(loaded, settings)
        let raw = try Data(contentsOf: RTKSettingsStore.fileURL(in: directory))
        let text = String(decoding: raw, as: UTF8.self)
        XCTAssertFalse(text.localizedCaseInsensitiveContains("password"))
        XCTAssertTrue(text.contains("field-user"))
        let poisoned = #"{"correctionsEnabled":true,"host":"d-gnss.jp","port":2101,"mountpoint":"RRSGD2024","user":"abc","password":"should-not-load"}"#
        let decoded = try JSONDecoder().decode(RTKSettings.self, from: Data(poisoned.utf8))
        XCTAssertEqual(decoded.user, "abc")
        XCTAssertEqual(decoded.mountpoint, .rrsgd2024)
        let encoded = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("password"))
        XCTAssertFalse(encoded.contains("should-not-load"))
        XCTAssertTrue(RTKMountpoint.rrsgd2024.datum2024)
        XCTAssertFalse(RTKMountpoint.rrsgd.datum2024)
        XCTAssertEqual(RTKSettingsStore.load(from: directory.appendingPathComponent("missing", isDirectory: true)).user, "")
    }

    func testStaleMountTextDoesNotOverrideThePicker() {
        XCTAssertEqual(RTKMountSelection.send(pickerShown: "RRSGD2024", typed: "docomo"), "RRSGD2024")
        XCTAssertEqual(RTKMountSelection.send(pickerShown: "docomo", typed: "docomo"), "docomo")
        XCTAssertEqual(RTKMountSelection.send(pickerShown: "RRSGD2024", typed: ""), "RRSGD2024")
        XCTAssertEqual(RTKMountSelection.send(pickerShown: "RRSGD2024", typed: "  RRSGD2024  "), "RRSGD2024")

        var settings = RTKSettings(mountpoint: .rrsgd2024, customMount: "docomo")
        let shown = RTKMountSelection.send(pickerShown: settings.mountpoint.rawValue, typed: "docomo")
        settings.select(shown: shown)
        XCTAssertEqual(settings.activeMount, "RRSGD2024")
        XCTAssertNil(settings.customMount)

        settings.select(shown: "docomo")
        XCTAssertEqual(settings.activeMount, "docomo")
        XCTAssertEqual(settings.customMount, "docomo")
        settings.select(shown: "RRSGD2024")
        XCTAssertEqual(settings.mountpoint, .rrsgd2024)
        XCTAssertNil(settings.customMount)
        XCTAssertEqual(settings.activeMount, "RRSGD2024")
    }
}
