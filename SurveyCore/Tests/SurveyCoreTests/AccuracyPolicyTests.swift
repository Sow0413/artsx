import XCTest
@testable import SurveyCore

final class AccuracyPolicyTests: XCTestCase {
    func testStageNumbersStayStable() {
        XCTAssertEqual(PositionStage.iphone.rawValue, 0)
        XCTAssertEqual(PositionStage.clas.rawValue, 1)
        XCTAssertEqual(PositionStage.rtk.rawValue, 2)
        XCTAssertEqual(PositionStage.hybrid.rawValue, 3)
    }

    func testIPhonePreviewIsYellowWhenHeightMissesPreviewTolerance() {
        let reading = SimulatedPositionSource.iphonePreview().script[0]
        let badge = AccuracyPolicy.badge(for: reading)
        XCTAssertEqual(badge.tone, .yellow)
        XCTAssertEqual(badge.text, "iPhone GPS 約3m")
        XCTAssertTrue(badge.accessibilityText.hasPrefix("下見。段階0。iPhone GPS 約3m"))
        XCTAssertTrue(badge.guidance.contains("高さがあと300cm"))
        XCTAssertFalse(badge.isStakeoutGrade)
        XCTAssertEqual(reading.position?.frame, .wgs84ITRF)
    }

    func testIPhoneValueFollowsTheWorkRequirement() {
        let within = IPhonePosition.make(
            latitudeDegrees: 35.68123,
            longitudeDegrees: 139.76712,
            ellipsoidalHeightMeters: 12.4,
            horizontalAccuracyMeters: 3.2,
            verticalAccuracyMeters: 4,
            timestamp: PreviewClock.instant
        )
        let preview = AccuracyPolicy.badge(for: PositionReading(position: within, availability: .available), work: work("preview"))
        let stakeout = AccuracyPolicy.badge(for: PositionReading(position: within, availability: .available), work: work("stakeout"))
        XCTAssertEqual(preview.tone, .green)
        XCTAssertEqual(stakeout.tone, .red)
        XCTAssertFalse(preview.isStakeoutGrade)
        XCTAssertFalse(stakeout.isStakeoutGrade)
        XCTAssertFalse(within.isTrustedRTKFix)
        XCTAssertFalse(preview.text.hasPrefix("RTK Fix"))

        let invalid = [-1.0, Double.nan, Double.infinity]
        for accuracy in invalid {
            let position = IPhonePosition.make(
                latitudeDegrees: 35.68123,
                longitudeDegrees: 139.76712,
                ellipsoidalHeightMeters: 12.4,
                horizontalAccuracyMeters: accuracy,
                verticalAccuracyMeters: 4,
                timestamp: PreviewClock.instant
            )
            let badge = AccuracyPolicy.badge(for: PositionReading(position: position, availability: .available))
            XCTAssertEqual(badge.tone, .grey, "accuracy \(accuracy)")
            XCTAssertFalse(badge.isStakeoutGrade)
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
        XCTAssertEqual(badge.tone, .green)
        XCTAssertEqual(badge.text, "iPhone GPS 約2cm")
        XCTAssertFalse(badge.isStakeoutGrade)
    }

    func testCLASMeetsPreviewAndMissesStakeout() {
        let badge = AccuracyPolicy.badge(for: SimulatedPositionSource.clasPreview().script[0])
        XCTAssertEqual(badge.tone, .green)
        XCTAssertEqual(badge.text, "CLAS 約5cm")
        XCTAssertFalse(badge.isStakeoutGrade)
        let stakeout = AccuracyPolicy.badge(
            for: SimulatedPositionSource.clasPreview().script[0],
            work: work("stakeout")
        )
        XCTAssertEqual(stakeout.tone, .red)
    }

    func testCLASReportingRTKFixIsNotATrustedFix() {
        let position = samplePosition(accuracy: 0.05, verticalAccuracy: 0.05, stage: .clas, quality: .rtkFix, receiver: .clas)
        let badge = AccuracyPolicy.badge(for: PositionReading(position: position, availability: .available))
        XCTAssertEqual(badge.tone, .green)
        XCTAssertEqual(badge.text, "CLAS 約5cm")
        XCTAssertFalse(position.isTrustedRTKFix)
        XCTAssertFalse(badge.isStakeoutGrade)
    }

    func testRTKFloatMeetsPreviewButIsNotStakeoutGrade() {
        let position = samplePosition(accuracy: 0.2, verticalAccuracy: 0.2, stage: .rtk, quality: .float, receiver: .rtk)
        let badge = AccuracyPolicy.badge(for: PositionReading(position: position, availability: .available))
        XCTAssertEqual(badge.tone, .green)
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
        let fix = samplePosition(accuracy: 0.02, verticalAccuracy: 0.03, stage: .hybrid, quality: .rtkFix, receiver: .rtk)
        XCTAssertTrue(fix.isTrustedRTKFix)
        XCTAssertEqual(AccuracyPolicy.tone(for: fix), .green)
        let uwb = samplePosition(accuracy: 0.15, verticalAccuracy: 0.15, stage: .hybrid, quality: .standalone, receiver: .uwb)
        let badge = AccuracyPolicy.badge(for: PositionReading(position: uwb, availability: .available))
        XCTAssertEqual(badge.tone, .green)
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

    private func work(_ id: String) -> WorkRequirement {
        WorkCatalog.provisional.works.first { $0.id == id }!
    }
}
