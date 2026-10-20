import XCTest
@testable import SurveyCore

final class RelativeHeightTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testZeroAddsTheVisualChangeAndIgnoresOrthometric() {
        var track = RelativeTrack()
        let zero = track.align(name: " BM1 ", knownHeight: 10, visualUp: 1.2, visualX: 0, visualZ: 0, baro: 0.4, at: start)
        XCTAssertEqual(zero?.name, "BM1")
        XCTAssertEqual(zero?.knownHeightMeters, 10)
        let fix = track.consume(sample(at: 2, visualUp: 1.32, visualX: 0, visualZ: 0, baro: 0.4))
        XCTAssertEqual(fix?.heightMeters ?? 0, 10.12, accuracy: 1e-12)
        XCTAssertEqual(fix?.channel, .visual)
        XCTAssertEqual(fix?.deltaMeters ?? 0, 0.12, accuracy: 1e-12)
        XCTAssertNil(track.align(name: "  ", knownHeight: 10, visualUp: 0, visualX: 0, visualZ: 0, baro: nil, at: start))

        let orthometric = ControlPoint(
            id: "o", name: "標高だけ", kind: "水準点",
            latitudeDegrees: 35, longitudeDegrees: 139,
            heightMeters: 20, heightKind: .orthometric
        )
        XCTAssertNil(KnownHeightPick.control(orthometric))
        let ellipsoidal = ControlPoint(
            id: "e", name: "BM1", kind: "水準点",
            latitudeDegrees: 35, longitudeDegrees: 139,
            ellipsoidalHeightMeters: 42.5, heightKind: .ellipsoidal
        )
        XCTAssertEqual(KnownHeightPick.control(ellipsoidal)?.heightMeters, 42.5)
        var book = sampleEntry(name: "K1", height: 12.5)
        XCTAssertEqual(KnownHeightPick.book(book)?.source, .book)
        book.ellipsoidalHeightMeters = nil
        XCTAssertNil(KnownHeightPick.book(book))
    }

    func testLimitedBlendAndLostFallsBackToBarometer() {
        let blended = RelativeHeight.solve(
            knownHeight: 10, visualDelta: 0.10, baroDelta: 0, inertialDelta: 1,
            elapsedSeconds: 0, traveledMeters: 0, quality: .limited,
            gnssEllipsoidal: nil, gnssTrustedFix: false, gnssVerticalAccuracy: nil, poleMeters: nil
        )
        XCTAssertEqual(blended?.channel, .visualBaro)
        XCTAssertEqual(blended?.heightMeters ?? 0, 10.07, accuracy: 1e-12)

        let lost = RelativeHeight.solve(
            knownHeight: 10, visualDelta: 5, baroDelta: 0.03, inertialDelta: 1,
            elapsedSeconds: 0, traveledMeters: 0, quality: .lost,
            gnssEllipsoidal: nil, gnssTrustedFix: false, gnssVerticalAccuracy: nil, poleMeters: nil
        )
        XCTAssertEqual(lost?.channel, .barometer)
        XCTAssertEqual(lost?.heightMeters ?? 0, 10.03, accuracy: 1e-12)
        XCTAssertEqual(lost?.needsRealign, true)

        let imu = RelativeHeight.solve(
            knownHeight: 10, visualDelta: nil, baroDelta: nil, inertialDelta: 0.02,
            elapsedSeconds: 0, traveledMeters: 0, quality: .normal,
            gnssEllipsoidal: nil, gnssTrustedFix: false, gnssVerticalAccuracy: nil, poleMeters: nil
        )
        XCTAssertEqual(imu?.channel, .inertial)
        XCTAssertEqual(imu?.heightMeters ?? 0, 10.02, accuracy: 1e-12)
    }

    func testRTKFixBeatsTheRelativeTrack() {
        let fix = RelativeHeight.solve(
            knownHeight: 10, visualDelta: 5, baroDelta: 4, inertialDelta: 3,
            elapsedSeconds: 30, traveledMeters: 40, quality: .normal,
            gnssEllipsoidal: 25.5, gnssTrustedFix: true, gnssVerticalAccuracy: 0.015, poleMeters: 2
        )
        XCTAssertEqual(fix?.channel, .gnssFix)
        XCTAssertEqual(fix?.heightMeters ?? 0, 23.5, accuracy: 1e-12)
        XCTAssertEqual(fix?.needsRealign, false)
        XCTAssertEqual(fix?.sigmaMeters ?? 0, 0.015, accuracy: 1e-12)
        XCTAssertTrue(RelativeHeight.usesReceiverStage(.gnssFix))
        XCTAssertFalse(RelativeHeight.usesReceiverStage(.visual))
        XCTAssertTrue(RelativeHeight.canRecord(fix!))

        let ignored = RelativeHeight.solve(
            knownHeight: 10, visualDelta: 0.01, baroDelta: nil, inertialDelta: nil,
            elapsedSeconds: 0, traveledMeters: 0, quality: .normal,
            gnssEllipsoidal: 99, gnssTrustedFix: false, gnssVerticalAccuracy: 0.01, poleMeters: nil
        )
        XCTAssertEqual(ignored?.channel, .visual)
        XCTAssertEqual(ignored?.heightMeters ?? 0, 10.01, accuracy: 1e-12)
    }

    func testErrorGrowsWithTimeDistanceQualityAndDisagreement() {
        let fresh = sigma(elapsed: 0, traveled: 0, quality: .normal, visual: 0, baro: 0)
        let later = sigma(elapsed: 10, traveled: 0, quality: .normal, visual: 0, baro: 0)
        let farther = sigma(elapsed: 10, traveled: 5, quality: .normal, visual: 0, baro: 0)
        let rough = sigma(elapsed: 10, traveled: 0, quality: .limited, visual: 0, baro: nil)
        XCTAssertLessThan(fresh, later)
        XCTAssertLessThan(later, farther)
        XCTAssertEqual(later * RelativeHeight.limitedFactor, rough, accuracy: 1e-12)

        let edge = sigma(elapsed: 20, traveled: 0, quality: .normal, visual: 0, baro: nil)
        XCTAssertEqual(edge, RelativeHeight.realignMeters, accuracy: 1e-12)
        XCTAssertEqual(needs(elapsed: 20, traveled: 0), false)
        XCTAssertEqual(needs(elapsed: 21, traveled: 0), true)
        let split = RelativeHeight.solve(
            knownHeight: 10, visualDelta: 0.05, baroDelta: 0, inertialDelta: nil,
            elapsedSeconds: 0, traveledMeters: 0, quality: .normal,
            gnssEllipsoidal: nil, gnssTrustedFix: false, gnssVerticalAccuracy: nil, poleMeters: nil
        )
        XCTAssertGreaterThan(split?.sigmaMeters ?? 0, RelativeHeight.realignMeters)
        XCTAssertEqual(split?.needsRealign, true)
        XCTAssertEqual(RelativeHeight.realignWord, "合わせ直して")
        let badge = RelativeHeight.badge(for: split!)
        XCTAssertEqual(badge.isStakeoutGrade, false)
        XCTAssertTrue(badge.accessibilityText.contains("相対"))
        XCTAssertTrue(badge.accessibilityText.contains("合わせ直して"))
        XCTAssertEqual(RelativeBadge.stageLabel, "相対")
        XCTAssertFalse(RelativeHeight.canRecord(split!))
        print("SURVEY RELATIVE 合わせ直して")
    }

    func testTravelAndInertialIntegration() {
        var track = RelativeTrack()
        XCTAssertNotNil(track.align(name: "BM1", knownHeight: 8, visualUp: 0, visualX: 0, visualZ: 0, baro: nil, at: start))
        _ = track.consume(sample(at: 1, visualUp: 0, visualX: 3, visualZ: 4))
        XCTAssertEqual(track.traveledMeters, 5, accuracy: 1e-12)
        _ = track.consume(sample(at: 2, visualUp: 0.01, visualX: 3, visualZ: 4))
        XCTAssertEqual(track.traveledMeters, 5, accuracy: 1e-12)

        var inertial = InertialVertical()
        inertial.integrate(upAcceleration: 1, at: start)
        inertial.integrate(upAcceleration: 1, at: start.addingTimeInterval(0.1))
        XCTAssertEqual(inertial.velocity, 0.1, accuracy: 1e-6)
        XCTAssertEqual(inertial.displacement, 0.01, accuracy: 1e-6)
        inertial.integrate(upAcceleration: 1, at: start.addingTimeInterval(5))
        XCTAssertEqual(inertial.velocity, 0, accuracy: 1e-12)
        XCTAssertEqual(inertial.displacement, 0.01, accuracy: 1e-6)

        let up = RelativeHeight.upAcceleration(userX: 0, userY: 1, userZ: 0, gravityX: 0, gravityY: -1, gravityZ: 0)
        XCTAssertEqual(up ?? 0, RelativeHeight.standardGravity, accuracy: 1e-12)
        XCTAssertNil(RelativeHeight.upAcceleration(userX: 0, userY: 0, userZ: 0, gravityX: 0, gravityY: 0, gravityZ: 0))
    }

    func testBookLookupKeepsOnlyNamedHeights() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("relative-\(UUID().uuidString)", isDirectory: true)
        let journal = FieldJournal(directory: directory)
        try journal.upsertBook(sampleEntry(name: "K12", height: 12.5))
        try journal.upsertBook(sampleEntry(name: "T9", height: nil))
        let found = journal.bookEntries(matching: "K1", limit: 20).compactMap(KnownHeightPick.book)
        XCTAssertEqual(found.map(\.name), ["K12"])
        XCTAssertEqual(found.first?.heightMeters, 12.5)
        XCTAssertTrue(journal.bookEntries(matching: " ", limit: 20).isEmpty)
        try? FileManager.default.removeItem(at: directory)
    }

    private func sample(at offset: TimeInterval, visualUp: Double, visualX: Double, visualZ: Double, baro: Double? = nil) -> RelativeSample {
        RelativeSample(
            at: start.addingTimeInterval(offset),
            visualUp: visualUp,
            visualX: visualX,
            visualZ: visualZ,
            baro: baro,
            quality: .normal
        )
    }

    private func sigma(elapsed: Double, traveled: Double, quality: RelativeQuality, visual: Double?, baro: Double?) -> Double {
        RelativeHeight.solve(
            knownHeight: 10, visualDelta: visual, baroDelta: baro, inertialDelta: nil,
            elapsedSeconds: elapsed, traveledMeters: traveled, quality: quality,
            gnssEllipsoidal: nil, gnssTrustedFix: false, gnssVerticalAccuracy: nil, poleMeters: nil
        )?.sigmaMeters ?? -1
    }

    private func needs(elapsed: Double, traveled: Double) -> Bool {
        RelativeHeight.solve(
            knownHeight: 10, visualDelta: 0, baroDelta: nil, inertialDelta: nil,
            elapsedSeconds: elapsed, traveledMeters: traveled, quality: .normal,
            gnssEllipsoidal: nil, gnssTrustedFix: false, gnssVerticalAccuracy: nil, poleMeters: nil
        )?.needsRealign ?? true
    }

    private func sampleEntry(name: String, height: Double?) -> CoordinateBookEntry {
        CoordinateBookEntry(
            name: name,
            latitudeDegrees: 35,
            longitudeDegrees: 139,
            ellipsoidalHeightMeters: height,
            horizontalAccuracyMeters: 1,
            verticalAccuracyMeters: 2,
            satelliteCount: nil,
            fixDurationSeconds: 0,
            recordedAt: start
        )
    }
}
