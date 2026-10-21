import XCTest
@testable import SurveyCore

final class PhoneAccuracyTests: XCTestCase {
    func testOutlierUsesTwiceTheMedianAndKeepsTheBoundary() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            sample(0, accuracy: 2, at: start),
            sample(0, accuracy: 2, at: start.addingTimeInterval(1)),
            sample(0, accuracy: 2, at: start.addingTimeInterval(2)),
            sample(0, accuracy: 4, at: start.addingTimeInterval(3)),
            sample(10, accuracy: 5, at: start.addingTimeInterval(4))
        ]
        let result = PhoneAverage.summarize(samples, startedAt: start, endedAt: start.addingTimeInterval(30))
        XCTAssertEqual(result?.sampleCount, 4)
        XCTAssertEqual(result?.discardedCount, 1)
        XCTAssertEqual(result?.latitudeDegrees ?? 0, 36, accuracy: 1e-8)
        XCTAssertEqual(result?.durationSeconds, 30)
        XCTAssertEqual(result?.stamp.label, PhoneAccuracyLabel.average)
        XCTAssertTrue(result?.stamp.label.contains("RTKではありません") == true)
    }

    func testMeanAndSpreadOfAnEastPair() throws {
        let origin = try XCTUnwrap(GRS80Geodesic.direct(
            latitude: 36,
            longitude: 139,
            azimuthDegrees: 90,
            distanceMeters: 10
        ))
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            PhoneFixSample(
                latitudeDegrees: 36, longitudeDegrees: 139,
                ellipsoidalHeightMeters: 100, orthometricHeightMeters: 50,
                horizontalAccuracyMeters: 3, verticalAccuracyMeters: 4, timestamp: start
            ),
            PhoneFixSample(
                latitudeDegrees: origin.latitude, longitudeDegrees: origin.longitude,
                ellipsoidalHeightMeters: 102, orthometricHeightMeters: 52,
                horizontalAccuracyMeters: 3, verticalAccuracyMeters: 4,
                timestamp: start.addingTimeInterval(1)
            )
        ]
        let result = try XCTUnwrap(PhoneAverage.summarize(samples, startedAt: start, endedAt: start.addingTimeInterval(2)))
        let back = try XCTUnwrap(PhoneOffset.meters(
            fromLatitude: 36, fromLongitude: 139,
            toLatitude: result.latitudeDegrees, toLongitude: result.longitudeDegrees
        ))
        XCTAssertEqual(back.east, 5, accuracy: 0.02)
        XCTAssertEqual(back.north, 0, accuracy: 0.02)
        XCTAssertEqual(result.horizontalStdMeters, 7.071, accuracy: 0.05)
        XCTAssertEqual(result.verticalStdMeters ?? 0, 1.414, accuracy: 0.01)
        XCTAssertEqual(result.orthometricHeightMeters ?? 0, 51, accuracy: 1e-6)
        XCTAssertEqual(result.meanHorizontalAccuracyMeters, 3, accuracy: 1e-6)
    }

    func testNegativeAccuracyDoesNotMoveTheMedian() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            sample(0, accuracy: -1, at: start),
            sample(0, accuracy: 2, at: start.addingTimeInterval(1)),
            sample(0, accuracy: 2, at: start.addingTimeInterval(2))
        ]
        let result = PhoneAverage.summarize(samples, startedAt: start, endedAt: start.addingTimeInterval(3))
        XCTAssertEqual(result?.sampleCount, 2)
        XCTAssertEqual(result?.discardedCount, 1)
    }

    func testLiveLineCountsDownAndShowsSpread() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var run = PhoneAverageRun(startedAt: start, limit: 30, purpose: .record)
        run = run.adding(sample(0, accuracy: 3, at: start))
        run = run.adding(sample(0, accuracy: 3, at: start))
        XCTAssertEqual(run.samples.count, 1)
        XCTAssertFalse(run.isFinished(at: start.addingTimeInterval(29)))
        XCTAssertTrue(run.isFinished(at: start.addingTimeInterval(30)))
        XCTAssertTrue(run.line(at: start.addingTimeInterval(6)).contains("残り0:24"))
        XCTAssertTrue(run.line(at: start.addingTimeInterval(6)).contains("ばらつき"))
        let manual = PhoneAverageRun(startedAt: start, limit: nil, purpose: .record)
        XCTAssertTrue(manual.line(at: start.addingTimeInterval(65)).contains("1:05"))
        XCTAssertFalse(manual.isFinished(at: start.addingTimeInterval(600)))
    }

    func testKnownShiftRemovesTheSameEastAndHeight() throws {
        let moved = try XCTUnwrap(GRS80Geodesic.direct(
            latitude: 36, longitude: 139, azimuthDegrees: 90, distanceMeters: 10
        ))
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let mean = PhoneAverageResult(
            latitudeDegrees: moved.latitude,
            longitudeDegrees: moved.longitude,
            ellipsoidalHeightMeters: 110,
            orthometricHeightMeters: 101.5,
            meanHorizontalAccuracyMeters: 3,
            sampleCount: 8,
            discardedCount: 1,
            horizontalStdMeters: 1.2,
            verticalStdMeters: 0.4,
            durationSeconds: 30
        )
        let anchor = KnownAnchor(id: "k1", name: "K1", latitudeDegrees: 36, longitudeDegrees: 139, heightMeters: 100)
        let shift = try XCTUnwrap(KnownPointShift.calibrate(projectID: "job", anchor: anchor, mean: mean, at: start))
        XCTAssertEqual(shift.eastMeters, 10, accuracy: 0.02)
        XCTAssertEqual(shift.northMeters, 0, accuracy: 0.02)
        XCTAssertEqual(shift.heightMeters ?? 0, 1.5, accuracy: 1e-6)
        XCTAssertTrue(shift.deltaText.contains("dE +10.00"))
        XCTAssertTrue(shift.deltaText.contains("dH +1.50"))

        var later = samplePosition(latitude: moved.latitude, longitude: moved.longitude, height: 112, receiver: .iphoneGPS)
        later.meanSeaLevelMeters = 103
        let applied = try XCTUnwrap(shift.applied(to: later, at: start.addingTimeInterval(60)))
        XCTAssertEqual(applied.position.latitudeDegrees, 36, accuracy: 1e-7)
        XCTAssertEqual(applied.position.longitudeDegrees, 139, accuracy: 1e-7)
        XCTAssertEqual(applied.position.ellipsoidalHeightMeters ?? 0, 110.5, accuracy: 1e-6)
        XCTAssertEqual(applied.position.meanSeaLevelMeters ?? 0, 101.5, accuracy: 1e-6)
        XCTAssertEqual(applied.position.fixQuality, .standalone)
        XCTAssertEqual(applied.position.receiver, .iphoneGPS)
        XCTAssertEqual(applied.stamp.sourceName, "K1")
        XCTAssertEqual(applied.stamp.rawLatitudeDegrees, later.latitudeDegrees, accuracy: 1e-9)
        XCTAssertTrue(applied.stamp.label.contains("RTKではありません"))
        XCTAssertTrue(applied.stamp.label.contains("丁張はFIX"))
    }

    func testShiftStaysOffForAReceiverAndWhenDisabled() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var shift = KnownPointShift(
            projectID: "job",
            sourceName: "K1",
            sourceLatitude: 36,
            sourceLongitude: 139,
            sourceHeightMeters: 100,
            eastMeters: 10,
            northMeters: 0,
            heightMeters: 1,
            calibratedAt: start,
            sampleCount: 4,
            horizontalStdMeters: 1,
            durationSeconds: 30
        )
        let phone = samplePosition(latitude: 36, longitude: 139, receiver: .iphoneGPS)
        let radio = samplePosition(latitude: 36, longitude: 139, stage: .rtk, quality: .rtkFix, receiver: .rtk)
        XCTAssertNotNil(shift.applied(to: phone, at: start))
        XCTAssertNil(shift.applied(to: radio, at: start))
        shift.enabled = false
        XCTAssertNil(shift.applied(to: phone, at: start))
    }

    func testWarnsAtThirtyMinutesOrTwoHundredMeters() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let shift = KnownPointShift(
            projectID: "job",
            sourceName: "K1",
            sourceLatitude: 36,
            sourceLongitude: 139,
            sourceHeightMeters: nil,
            eastMeters: 1,
            northMeters: 0,
            heightMeters: nil,
            calibratedAt: start,
            sampleCount: 4,
            horizontalStdMeters: 1,
            durationSeconds: 30
        )
        let away = try XCTUnwrap(GRS80Geodesic.direct(
            latitude: 36, longitude: 139, azimuthDegrees: 0, distanceMeters: 200
        ))
        let near = try XCTUnwrap(GRS80Geodesic.direct(
            latitude: 36, longitude: 139, azimuthDegrees: 0, distanceMeters: 199
        ))
        XCTAssertFalse(shift.isStale(at: start.addingTimeInterval(30 * 60 - 1), latitude: 36, longitude: 139))
        XCTAssertTrue(shift.isStale(at: start.addingTimeInterval(30 * 60), latitude: 36, longitude: 139))
        XCTAssertFalse(shift.isStale(at: start.addingTimeInterval(10), latitude: near.latitude, longitude: near.longitude))
        XCTAssertTrue(shift.isStale(at: start.addingTimeInterval(10), latitude: away.latitude, longitude: away.longitude))
        XCTAssertTrue(shift.statusLine(at: start.addingTimeInterval(31 * 60), latitude: 36, longitude: 139).contains("確認"))
        XCTAssertTrue(shift.statusLine(at: start.addingTimeInterval(12 * 60), latitude: 36, longitude: 139).contains("12分"))
    }

    func testOldRecordsDecodeWithoutTheNewFields() throws {
        let observation = FieldObservation(
            name: "P1",
            workID: "traverse",
            captured: samplePosition()
        )
        let data = try JSONEncoder().encode(observation)
        let decoded = try JSONDecoder().decode(FieldObservation.self, from: data)
        XCTAssertNil(decoded.phoneAverage)
        XCTAssertNil(decoded.knownShift)
        let file = FieldPointFile(
            name: "P1",
            latitude: 36,
            longitude: 139,
            ellipsoidalHeightMeters: 10,
            horizontalAccuracyMeters: 3,
            verticalAccuracyMeters: 4,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let fileData = try JSONEncoder().encode(file)
        let fileDecoded = try JSONDecoder().decode(FieldPointFile.self, from: fileData)
        XCTAssertNil(fileDecoded.phoneAverage)
        XCTAssertNil(fileDecoded.knownShift)
    }

    private func sample(_ east: Double, accuracy: Double, at date: Date) -> PhoneFixSample {
        let moved = GRS80Geodesic.direct(latitude: 36, longitude: 139, azimuthDegrees: 90, distanceMeters: east)
            ?? (latitude: 36, longitude: 139)
        return PhoneFixSample(
            latitudeDegrees: moved.latitude,
            longitudeDegrees: moved.longitude,
            ellipsoidalHeightMeters: 40,
            orthometricHeightMeters: 0,
            horizontalAccuracyMeters: accuracy,
            verticalAccuracyMeters: 5,
            timestamp: date
        )
    }
}
