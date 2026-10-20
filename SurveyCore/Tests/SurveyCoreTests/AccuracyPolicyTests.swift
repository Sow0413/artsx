import XCTest
@testable import SurveyCore

final class AccuracyPolicyTests: XCTestCase {
    func testStageNumbersStayStable() {
        XCTAssertEqual(PositionStage.iphone.rawValue, 0)
        XCTAssertEqual(PositionStage.clas.rawValue, 1)
        XCTAssertEqual(PositionStage.rtk.rawValue, 2)
        XCTAssertEqual(PositionStage.hybrid.rawValue, 3)
    }

    func testIPhonePreviewIsAmberAndNotStakeout() {
        let reading = SimulatedPositionSource.iphonePreview().script[0]
        let badge = AccuracyPolicy.badge(for: reading)
        XCTAssertEqual(badge.tone, .amber)
        XCTAssertEqual(badge.text, "iPhone GPS 約3m")
        XCTAssertEqual(badge.accessibilityText, "段階0。iPhone GPS 約3m")
        XCTAssertFalse(badge.isStakeoutGrade)
        XCTAssertEqual(reading.position?.frame, .wgs84ITRF)
    }

    func testIPhoneNeverTurnsGreenAcrossAccuracies() {
        let accuracies = [-1.0, 0, 0.01, 0.02, 0.05, 1, 3.2, 50, 5_000, Double.nan, Double.infinity]
        for accuracy in accuracies {
            let position = IPhonePosition.make(
                latitudeDegrees: 35.68123,
                longitudeDegrees: 139.76712,
                ellipsoidalHeightMeters: 12.4,
                horizontalAccuracyMeters: accuracy,
                verticalAccuracyMeters: 4,
                timestamp: PreviewClock.instant
            )
            let badge = AccuracyPolicy.badge(for: PositionReading(position: position, availability: .available))
            XCTAssertNotEqual(badge.tone, .green, "accuracy \(accuracy)")
            XCTAssertFalse(badge.isStakeoutGrade)
            XCTAssertFalse(position.isTrustedRTKFix)
            XCTAssertFalse(badge.text.hasPrefix("RTK Fix"))
        }
    }

    func testSpoofedRTKFixOnIPhoneStaysAmber() {
        var spoof = IPhonePosition.make(
            latitudeDegrees: 35.68,
            longitudeDegrees: 139.76,
            ellipsoidalHeightMeters: 10,
            horizontalAccuracyMeters: 0.02,
            verticalAccuracyMeters: 0.05,
            timestamp: PreviewClock.instant
        )
        spoof.stage = .rtk
        spoof.fixQuality = .rtkFix
        XCTAssertEqual(spoof.receiver, .iphoneGPS)
        XCTAssertFalse(spoof.isTrustedRTKFix)
        let badge = AccuracyPolicy.badge(for: PositionReading(position: spoof, availability: .available))
        XCTAssertEqual(badge.tone, .amber)
        XCTAssertEqual(badge.text, "iPhone GPS 約2cm")
        XCTAssertFalse(badge.isStakeoutGrade)
    }

    func testCLASStaysAmber() {
        let badge = AccuracyPolicy.badge(for: SimulatedPositionSource.clasPreview().script[0])
        XCTAssertEqual(badge.tone, .amber)
        XCTAssertEqual(badge.text, "CLAS 約5cm")
        XCTAssertFalse(badge.isStakeoutGrade)
    }

    func testCLASReportingRTKFixIsNotGreen() {
        let position = samplePosition(accuracy: 0.05, stage: .clas, quality: .rtkFix, receiver: .clas)
        let badge = AccuracyPolicy.badge(for: PositionReading(position: position, availability: .available))
        XCTAssertEqual(badge.tone, .amber)
        XCTAssertEqual(badge.text, "CLAS 約5cm")
        XCTAssertFalse(position.isTrustedRTKFix)
    }

    func testRTKFloatIsAmber() {
        let position = samplePosition(accuracy: 0.2, stage: .rtk, quality: .float, receiver: .rtk)
        let badge = AccuracyPolicy.badge(for: PositionReading(position: position, availability: .available))
        XCTAssertEqual(badge.tone, .amber)
        XCTAssertEqual(badge.text, "RTK Float 約20cm")
        XCTAssertFalse(badge.isStakeoutGrade)
    }

    func testRTKFixIsGreen() {
        let badge = AccuracyPolicy.badge(for: SimulatedPositionSource.rtkFixPreview().script[0])
        XCTAssertEqual(badge.tone, .green)
        XCTAssertEqual(badge.text, "RTK Fix 2cm")
        XCTAssertTrue(badge.isStakeoutGrade)
        XCTAssertEqual(AccuracyPolicy.tone(for: badgePosition()), .green)
    }

    func testHybridRTKFixIsGreenAndUWBIsNot() {
        let fix = samplePosition(accuracy: 0.02, stage: .hybrid, quality: .rtkFix, receiver: .rtk)
        XCTAssertTrue(fix.isTrustedRTKFix)
        XCTAssertEqual(AccuracyPolicy.tone(for: fix), .green)
        let uwb = samplePosition(accuracy: 0.15, stage: .hybrid, quality: .standalone, receiver: .uwb)
        let badge = AccuracyPolicy.badge(for: PositionReading(position: uwb, availability: .available))
        XCTAssertEqual(badge.tone, .amber)
        XCTAssertEqual(badge.text, "併用 約15cm")
        XCTAssertFalse(badge.isStakeoutGrade)
    }

    func testInvalidAccuracyAndAvailability() {
        let invalid = samplePosition(accuracy: -1)
        let badge = AccuracyPolicy.badge(for: PositionReading(position: invalid, availability: .available))
        XCTAssertEqual(badge.tone, .grey)
        XCTAssertEqual(badge.text, "精度不明")
        XCTAssertEqual(AccuracyPolicy.badge(for: .waiting).text, "位置を取得中")
        XCTAssertEqual(
            AccuracyPolicy.badge(for: PositionReading(position: nil, availability: .denied)).text,
            "位置情報を許可してください"
        )
        XCTAssertEqual(
            AccuracyPolicy.badge(for: PositionReading(position: nil, availability: .unavailable)).tone,
            .grey
        )
    }

    func testMagnitudeLabels() {
        XCTAssertEqual(AccuracyFormat.label(meters: 3.2, approximate: true), "約3m")
        XCTAssertEqual(AccuracyFormat.label(meters: 12.6, approximate: true), "約13m")
        XCTAssertEqual(AccuracyFormat.label(meters: 2.5, approximate: true), "約3m")
        XCTAssertEqual(AccuracyFormat.label(meters: 0.8, approximate: true), "約80cm")
        XCTAssertEqual(AccuracyFormat.label(meters: 0.05, approximate: true), "約5cm")
        XCTAssertEqual(AccuracyFormat.label(meters: 0.02, approximate: false), "2cm")
    }

    func testPositionRoundTripsAndKeepsFrame() throws {
        let position = samplePosition()
        let data = try JSONEncoder().encode(position)
        let decoded = try JSONDecoder().decode(GeodeticPosition.self, from: data)
        XCTAssertEqual(decoded, position)
        XCTAssertEqual(decoded.frame, .wgs84ITRF)
    }

    private func badgePosition() -> GeodeticPosition {
        SimulatedPositionSource.rtkFixPreview().script[0].position!
    }
}
