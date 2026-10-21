import XCTest
@testable import SurveyCore

final class BatterTests: XCTestCase {
    func testToleranceDefaultsToFiveMillimeters() {
        XCTAssertEqual(BatterMath.defaultToleranceMeters, 0.005)
        XCTAssertEqual(BatterSettings().toleranceMeters, 0.005)
        let json = Data("{\"offsetMeters\":0.5,\"slope\":0}".utf8)
        let decoded = try? JSONDecoder().decode(BatterSettings.self, from: json)
        XCTAssertEqual(decoded?.toleranceMeters, 0.005)
        XCTAssertEqual(decoded?.offsetMeters, 0.5)
        XCTAssertEqual(decoded?.source, .poleTip)
    }

    func testOffsetAndSlopeChangeTheTarget() {
        let flat = BatterMath.targetHeight(design: 10, offset: 0.50, slope: 0, alongMeters: 0)
        XCTAssertEqual(flat ?? 0, 10.50, accuracy: 1e-12)
        let graded = BatterMath.targetHeight(design: 10, offset: 0.50, slope: 0.02, alongMeters: 10)
        XCTAssertEqual(graded ?? 0, 10.70, accuracy: 1e-12)
        let note = BatterMath.targetNote(design: 10, offset: 0.50, slope: 0, alongMeters: 0)
        XCTAssertEqual(note, "目標 10.500m（計画 10.000、オフセット +0.500、勾配 +0.000）")

        let origin = (latitude: 35.0, longitude: 139.0)
        let east = GRS80Geodesic.direct(latitude: origin.latitude, longitude: origin.longitude, azimuthDegrees: 90, distanceMeters: 10)
        let along = BatterMath.alongMeters(
            hereLatitude: east?.latitude ?? 0,
            hereLongitude: east?.longitude ?? 0,
            originLatitude: origin.latitude,
            originLongitude: origin.longitude,
            azimuthDegrees: 90
        )
        XCTAssertEqual(along ?? 0, 10, accuracy: 0.01)
        let back = BatterMath.alongMeters(
            hereLatitude: east?.latitude ?? 0,
            hereLongitude: east?.longitude ?? 0,
            originLatitude: origin.latitude,
            originLongitude: origin.longitude,
            azimuthDegrees: 270
        )
        XCTAssertEqual(back ?? 0, -10, accuracy: 0.01)
        XCTAssertNil(BatterMath.targetHeight(design: .nan, offset: 0.5, slope: 0, alongMeters: 0))
    }

    func testDirectionColorsAndTwelveCentimeterPhrase() {
        XCTAssertEqual(BatterMath.move(deltaMeters: 0.12, toleranceMeters: 0.005), .lower)
        XCTAssertEqual(BatterMath.move(deltaMeters: -0.12, toleranceMeters: 0.005), .raise)
        XCTAssertEqual(BatterMath.move(deltaMeters: 0.005, toleranceMeters: 0.005), .within)
        XCTAssertEqual(BatterMath.move(deltaMeters: -0.005, toleranceMeters: 0.005), .within)
        XCTAssertEqual(BatterMath.move(deltaMeters: 0.006, toleranceMeters: 0.005), .lower)
        XCTAssertEqual(BatterMath.ink(.raise), .blue)
        XCTAssertEqual(BatterMath.ink(.lower), .red)
        XCTAssertEqual(BatterMath.ink(.within), .green)
        XCTAssertEqual(BatterMath.arrow(.raise), "↑")
        XCTAssertEqual(BatterMath.arrow(.lower), "↓")
        XCTAssertEqual(BatterMath.phrase(deltaMeters: 0.12, toleranceMeters: 0.005), "あと12cm下げ")
        XCTAssertEqual(BatterMath.phrase(deltaMeters: -0.12, toleranceMeters: 0.005), "あと12cm上げ")
        XCTAssertEqual(BatterMath.phrase(deltaMeters: 0.002, toleranceMeters: 0.005), "許容内")
        XCTAssertEqual(BatterMath.phrase(deltaMeters: 0.006, toleranceMeters: 0.005), "あと6mm下げ")
        XCTAssertGreaterThan(BatterMath.gaugeFraction(deltaMeters: 0.12), 0.5)
        XCTAssertLessThan(BatterMath.gaugeFraction(deltaMeters: -0.12), 0.5)
        print("SURVEY BATTER あと12cm下げ")
    }

    func testSpeechIntervalShrinksAsTheErrorShrinks() {
        let near = BatterMath.speechInterval(remainingMeters: 0.02)
        let mid = BatterMath.speechInterval(remainingMeters: 0.12)
        let far = BatterMath.speechInterval(remainingMeters: 0.80)
        XCTAssertLessThan(near, mid)
        XCTAssertLessThan(mid, far)
        XCTAssertEqual(BatterMath.speechInterval(remainingMeters: 0), BatterMath.nearSpeechSeconds)
        XCTAssertEqual(BatterMath.speechInterval(remainingMeters: 5), BatterMath.farSpeechSeconds)
        XCTAssertEqual(BatterMath.speechInterval(remainingMeters: .nan), BatterMath.farSpeechSeconds)
    }

    func testPoleTipAndCrosshairLineStaySeparate() {
        XCTAssertEqual(BatterMath.poleTip(deviceEllipsoidal: 12, poleMeters: 2) ?? 0, 10, accuracy: 1e-12)
        XCTAssertNil(BatterMath.poleTip(deviceEllipsoidal: 12, poleMeters: nil))
        XCTAssertNil(BatterMath.poleTip(deviceEllipsoidal: 12, poleMeters: 0))
        let line = BatterMath.crosshairLine(ground: 10, eye: 1.60)
        XCTAssertEqual(line ?? 0, 11.60, accuracy: 1e-12)
        XCTAssertNotEqual(line, BatterMath.poleTip(deviceEllipsoidal: 12, poleMeters: 2))
        XCTAssertTrue(BatterMath.acceptsCrosshair(isLevel: true))
        XCTAssertFalse(BatterMath.acceptsCrosshair(isLevel: false))
        XCTAssertFalse(BatterMath.acceptsCrosshair(isLevel: nil))
        XCTAssertNil(BatterMath.crosshairLine(ground: 10, eye: 0))
    }

    func testKindStageAndGuideLabel() {
        XCTAssertEqual(BatterMath.kind, "丁張")
        let iphone = BatterMath.record(measured: 10.5, stage: .iphone, receiver: .iphoneGPS)
        XCTAssertEqual(iphone?.kind, "丁張")
        XCTAssertEqual(iphone?.stage, .iphone)
        XCTAssertEqual(iphone?.guide, true)
        XCTAssertEqual(BatterMath.guideWord, "目安")
        XCTAssertTrue(BatterMath.showsGuide(stage: .iphone, receiver: .iphoneGPS))
        XCTAssertFalse(BatterMath.showsGuide(stage: .rtk, receiver: .rtk))
        XCTAssertFalse(BatterMath.showsGuide(stage: .iphone, receiver: .rtk))

        let position = IPhonePosition.make(
            latitudeDegrees: 35,
            longitudeDegrees: 139,
            ellipsoidalHeightMeters: iphone?.heightMeters,
            horizontalAccuracyMeters: 5,
            verticalAccuracyMeters: 8,
            timestamp: Date()
        )
        let badge = AccuracyPolicy.badge(
            for: PositionReading(position: position, availability: .available),
            operatingStage: .iphone
        )
        XCTAssertTrue(badge.isPhoneSelfEstimate)
        XCTAssertTrue(badge.accessibilityText.contains(AccuracyFormat.phoneEstimateNote))
        XCTAssertFalse(badge.accessibilityText.contains("段階0"))
        XCTAssertFalse(badge.isStakeoutGrade)
        XCTAssertFalse(position.isTrustedRTKFix)

        let observation = FieldObservation(
            name: "T1",
            workID: "stakeout",
            captured: position,
            condition: ObservationCondition.snapshot(position: position, stage: .iphone, durationSeconds: nil, epochCount: nil)
        )
        let entry = CoordinateBookIndex.entry(from: observation, kind: BatterMath.kind)
        XCTAssertEqual(entry.kind, "丁張")
        XCTAssertEqual(entry.ellipsoidalHeightMeters ?? 0, 10.5, accuracy: 1e-12)
        XCTAssertNil(observation.condition?.stature)
        XCTAssertEqual(entry.stage, .iphone)
    }

    func testPlanTextAndSettingsStayOffStature() {
        XCTAssertEqual(
            BatterMath.planText(distanceMeters: 12.4, azimuthDegrees: 90, precision: .meters),
            "現在地から 12 m、北から時計回り 90.0°"
        )
        XCTAssertEqual(
            BatterMath.planText(distanceMeters: nil, azimuthDegrees: nil, precision: .meters),
            "平面の目標が無いので、高さだけ出します。"
        )
        let name = "batter-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = BatterSettings(offsetMeters: 0.50, slope: 0.02, slopeAzimuthDegrees: 90, toleranceMeters: 0.005, source: .crosshair)
        settings.save(to: defaults)
        let loaded = BatterSettings.load(from: defaults)
        XCTAssertEqual(loaded.offsetMeters, 0.50, accuracy: 1e-12)
        XCTAssertEqual(loaded.slope, 0.02, accuracy: 1e-12)
        XCTAssertEqual(loaded.slopeAzimuthDegrees ?? 0, 90, accuracy: 1e-12)
        XCTAssertEqual(loaded.source, .crosshair)
        XCTAssertNotEqual(BatterSettings.storageKey, PoleHeight.storageKey)
        XCTAssertNotEqual(BatterSettings.storageKey, StatureProfile.storageKey)
        XCTAssertNil(PoleHeight.load(from: defaults).meters)
    }
}
