import XCTest
@testable import SurveyCore

final class CampaignTests: XCTestCase {
    func testThreeRoundsListTheMeansTheGapsAndTheOverallMean() {
        let point = deskPoint()
        let rounds = [
            round(1, point: point, east: 2, north: 0, height: 10.2),
            round(2, point: point, east: 2.1, north: 0.1, height: 10.25),
            round(3, point: point, east: 1.9, north: -0.1, height: 10.15)
        ]
        let comparison = CampaignComparison.make(point: point, rounds: rounds)
        XCTAssertEqual(comparison?.rounds.count, 3)
        XCTAssertEqual(comparison?.rounds[0].offset.horizontalMeters ?? -1, 2, accuracy: 1e-3)
        XCTAssertEqual(comparison?.rounds[0].offset.verticalMeters ?? -99, 0.2, accuracy: 1e-6)
        XCTAssertEqual(comparison?.gaps.count, 2)
        XCTAssertEqual(comparison?.gaps[0].horizontalMeters ?? -1, (0.02 as Double).squareRoot(), accuracy: 1e-3)
        XCTAssertEqual(comparison?.overall.eastMeters ?? -1, 2, accuracy: 1e-3)
        XCTAssertEqual(comparison?.overall.northMeters ?? 99, 0, accuracy: 1e-3)
        XCTAssertEqual(comparison?.overall.verticalMeters ?? -99, 0.2, accuracy: 1e-6)
        XCTAssertEqual(comparison?.horizontalScatterMeters ?? -1, (0.02 as Double).squareRoot(), accuracy: 1e-3)
        XCTAssertEqual(comparison?.aligned, true)
        XCTAssertEqual(CampaignText.roundLine(index: 1, offset: comparison!.rounds[0].offset), "1回目 水平 2.00m 高さ +0.20m")
        XCTAssertEqual(CampaignText.overallLine(comparison!.overall), "全体の平均 水平 2.00m 高さ +0.20m")
        XCTAssertTrue(CampaignText.scatterLine(horizontal: comparison!.horizontalScatterMeters, aligned: true).contains("そろっています"))
        XCTAssertNotNil(ControlCorrection.make(point: point, instrument: iphone, comparison: comparison!, acquiredAt: PreviewClock.instant))
    }

    func testScatteredRoundsAreNotACorrection() {
        let point = deskPoint()
        let rounds = [
            round(1, point: point, east: 3, north: 0, height: 10),
            round(2, point: point, east: -3, north: 0, height: 10)
        ]
        let comparison = CampaignComparison.make(point: point, rounds: rounds)
        XCTAssertEqual(comparison?.aligned, false)
        XCTAssertGreaterThan(comparison?.horizontalScatterMeters ?? 0, 2)
        XCTAssertNil(ControlCorrection.make(point: point, instrument: iphone, comparison: comparison!, acquiredAt: PreviewClock.instant))
        XCTAssertTrue(CampaignText.scatterLine(horizontal: comparison!.horizontalScatterMeters, aligned: false).contains("補正値にはしません"))
    }

    func testOneRoundHasNoReproducibility() {
        let point = deskPoint()
        let comparison = CampaignComparison.make(point: point, rounds: [round(1, point: point, east: 1, north: 0, height: 10)])
        XCTAssertEqual(comparison?.aligned, false)
        XCTAssertEqual(comparison?.gaps.count, 0)
    }

    func testCumulativeMeanSettlesWhenTheChangeStaysSmall() {
        let steady = curve([(0, 0), (60, 0), (120, 0)])
        XCTAssertEqual(ConvergenceCurve.settledElapsed(steady, policy: .provisional) ?? -1, 60, accuracy: 1e-9)
        XCTAssertEqual(CampaignText.settledLine(60), "1分で落ち着きました")
        XCTAssertEqual(CampaignText.settledLine(90), "1.5分で落ち着きました")
        XCTAssertEqual(CampaignText.settledLine(30), "30秒で落ち着きました")

        let late = curve([(0, 0), (60, 1), (120, 1), (180, 1)])
        XCTAssertEqual(ConvergenceCurve.settledElapsed(late, policy: .provisional) ?? -1, 120, accuracy: 1e-9)

        let heightLate = curve([(0, 0, 0), (60, 0, 1), (120, 0, 1), (180, 0, 1)])
        XCTAssertEqual(ConvergenceCurve.settledElapsed(heightLate, policy: .provisional) ?? -1, 120, accuracy: 1e-9)

        let stillMoving = curve([(0, 0), (60, 0), (120, 1)])
        XCTAssertNil(ConvergenceCurve.settledElapsed(stillMoving, policy: .provisional))
        XCTAssertEqual(CampaignText.settledLine(nil), "この回では落ち着きませんでした")
    }

    func testCurveUsesTheCumulativeMeanFromPlacement() {
        let point = deskPoint()
        let started = PreviewClock.instant
        let samples = [
            placed(point, east: 0, north: 4, height: 11, at: started),
            placed(point, east: 0, north: 0, height: 9, at: started.addingTimeInterval(60))
        ]
        let curve = ConvergenceCurve.make(point: point, startedAt: started, samples: samples)
        XCTAssertEqual(curve.count, 2)
        XCTAssertEqual(curve[0].elapsedSeconds, 0, accuracy: 1e-9)
        XCTAssertEqual(curve[0].northMeters, 4, accuracy: 1e-3)
        XCTAssertEqual(curve[1].elapsedSeconds, 60, accuracy: 1e-9)
        XCTAssertEqual(curve[1].northMeters, 2, accuracy: 1e-3)
        XCTAssertEqual(curve[1].verticalMeters ?? -99, 0, accuracy: 1e-6)
        XCTAssertNil(ConvergenceCurve.settledElapsed(curve, policy: .provisional))

        let held = [
            placed(point, east: 0, north: 4, height: 11, at: started),
            placed(point, east: 0, north: 4, height: 11, at: started.addingTimeInterval(60))
        ]
        let steady = ConvergenceCurve.make(point: point, startedAt: started, samples: held)
        XCTAssertEqual(ConvergenceCurve.settledElapsed(steady, policy: .provisional) ?? -1, 60, accuracy: 1e-6)
    }

    func testCorrectionIsSubtractedAndTurnsStale() throws {
        let point = deskPoint()
        let observed = placed(point, east: 10, north: 0, height: 12, at: PreviewClock.instant).position
        let correction = ControlCorrection(
            pointID: point.id,
            pointName: point.name,
            instrument: InstrumentState(observed),
            acquiredAt: PreviewClock.instant.addingTimeInterval(-90),
            eastMeters: 10,
            northMeters: 0,
            verticalMeters: 2,
            horizontalScatterMeters: 0.2,
            verticalScatterMeters: 0.3,
            roundCount: 3,
            active: true
        )
        let shifted = correction.subtracting(from: observed)
        let back = GRS80Geodesic.inverse(
            latitude1: point.latitudeDegrees,
            longitude1: point.longitudeDegrees,
            latitude2: shifted?.latitudeDegrees ?? 0,
            longitude2: shifted?.longitudeDegrees ?? 0
        )
        XCTAssertEqual(back?.distanceMeters ?? -1, 0, accuracy: 1e-3)
        XCTAssertEqual(shifted?.ellipsoidalHeightMeters ?? -1, 10, accuracy: 1e-9)
        XCTAssertEqual(observed.latitudeDegrees, placed(point, east: 10, north: 0, height: 12, at: PreviewClock.instant).position.latitudeDegrees, accuracy: 1e-12)

        let fresh = correction.age(at: PreviewClock.instant)
        XCTAssertEqual(fresh.elapsedMinutes, 1)
        XCTAssertFalse(fresh.stale)
        let stale = correction.age(at: correction.acquiredAt.addingTimeInterval(120 * 60))
        XCTAssertEqual(stale.elapsedMinutes, 120)
        XCTAssertTrue(stale.stale)
        XCTAssertFalse(correction.age(at: correction.acquiredAt.addingTimeInterval(119 * 60 + 59)).stale)

        let working = correction.workingPosition(from: observed, now: PreviewClock.instant)
        XCTAssertEqual(working?.horizontalAccuracyMeters ?? -1, 0.5, accuracy: 1e-12)
        XCTAssertEqual(working?.verticalAccuracyMeters ?? -1, 0.5, accuracy: 1e-12)
        XCTAssertNil(correction.workingPosition(from: observed, now: PreviewClock.instant.addingTimeInterval(120 * 60)))

        let directory = try TestFiles.directory()
        defer { TestFiles.remove(directory) }
        let store = CorrectionStore().saving(correction)
        try store.save(to: directory)
        XCTAssertEqual(CorrectionStore.load(from: directory).active?.eastMeters ?? -1, 10, accuracy: 1e-9)
    }

    func testFreshCorrectionChangesTheBadgeAndAStaleOneDoesNot() {
        let phone = samplePosition(accuracy: 3.2, verticalAccuracy: 4)
        let rough = work("rough")
        let now = PreviewClock.instant
        let reading = PositionReading(position: phone, availability: .available)
        let plain = AccuracyPolicy.badge(for: reading, work: rough, now: now)
        XCTAssertEqual(plain.tone, .red)

        let correction = ControlCorrection(
            pointID: "desk",
            pointName: "机上",
            instrument: InstrumentState(phone),
            acquiredAt: now.addingTimeInterval(-60),
            eastMeters: 3,
            northMeters: 0,
            verticalMeters: 1,
            horizontalScatterMeters: 0.2,
            verticalScatterMeters: 0.2,
            roundCount: 3,
            active: true
        )
        let corrected = AccuracyPolicy.badge(for: reading, work: rough, correction: correction, now: now)
        XCTAssertEqual(corrected.tone, .green)
        XCTAssertTrue(corrected.caution.contains("三角点補正"))
        XCTAssertFalse(corrected.isStakeoutGrade)
        XCTAssertEqual(
            AccuracyPolicy.badge(for: reading, work: work("stakeout"), correction: correction, now: now).tone,
            .red
        )

        let stale = AccuracyPolicy.badge(
            for: reading,
            work: rough,
            correction: aged(correction, by: 120 * 60),
            now: now
        )
        XCTAssertEqual(stale.tone, .red)
        XCTAssertFalse(stale.caution.contains("三角点補正"))

        var other = correction
        other.instrument = InstrumentState(receiver: .clas, stage: .clas, fixQuality: .clas)
        XCTAssertEqual(AccuracyPolicy.badge(for: reading, work: rough, correction: other, now: now).tone, .red)
    }

    func testReturnCheckKeepsBothTheApportionedCoordinateAndTheResurveyMark() {
        let start = ControlCorrection(
            pointID: "desk",
            pointName: "机上",
            instrument: iphone,
            acquiredAt: PreviewClock.instant,
            eastMeters: 0,
            northMeters: 0,
            verticalMeters: 0,
            horizontalScatterMeters: 0.1,
            verticalScatterMeters: 0.1,
            roundCount: 3,
            active: true
        )
        let close = ReturnCheck.compare(start: start, end: SessionOffset(eastMeters: 0.2, northMeters: 0, verticalMeters: 0.1))
        XCTAssertTrue(close.valid)
        XCTAssertEqual(close.horizontalDifferenceMeters, 0.2, accuracy: 1e-12)
        XCTAssertTrue(CampaignText.returnLine(close).contains("補正有効"))

        let open = ReturnCheck.compare(start: start, end: SessionOffset(eastMeters: 10, northMeters: 0, verticalMeters: 0.8))
        XCTAssertFalse(open.valid)
        XCTAssertTrue(CampaignText.returnLine(open).contains("要再測"))

        let point = deskPoint()
        let middle = placed(point, east: 0, north: 0, height: 10, at: PreviewClock.instant.addingTimeInterval(50)).position
        let before = placed(point, east: 0, north: 0, height: 10, at: PreviewClock.instant).position
        var other = middle
        other.receiver = .rtk
        other.stage = .rtk
        other.fixQuality = .rtkFix
        let observations = [
            FieldObservation(name: "前", workID: "preview", captured: before),
            FieldObservation(name: "途中", workID: "preview", captured: middle),
            FieldObservation(name: "別の機械", workID: "preview", captured: other)
        ]
        let end = SessionOffset(eastMeters: 10, northMeters: 0, verticalMeters: 0)
        let endAt = PreviewClock.instant.addingTimeInterval(100)
        let apportioned = ClosureAdjustmentMath.apportion(observations: observations, start: start, end: end, endAt: endAt)
        XCTAssertNil(apportioned[0].closureAdjustment)
        XCTAssertNil(apportioned[2].closureAdjustment)
        XCTAssertEqual(apportioned[1].captured, middle)
        XCTAssertEqual(apportioned[1].closureAdjustment?.fraction ?? -1, 0.5, accuracy: 1e-12)
        let moved = apportioned[1].closureAdjustment?.position
        let back = GRS80Geodesic.inverse(
            latitude1: point.latitudeDegrees,
            longitude1: point.longitudeDegrees,
            latitude2: moved?.latitudeDegrees ?? 0,
            longitude2: moved?.longitudeDegrees ?? 0
        )
        XCTAssertEqual(back?.eastMeters ?? 99, -5, accuracy: 1e-3)
        XCTAssertEqual(moved?.ellipsoidalHeightMeters ?? -1, 10, accuracy: 1e-6)

        let marked = ClosureAdjustmentMath.markResurvey(observations: apportioned, start: start, endAt: endAt)
        XCTAssertFalse(marked[0].needsResurvey)
        XCTAssertTrue(marked[1].needsResurvey)
        XCTAssertFalse(marked[2].needsResurvey)
        XCTAssertEqual(marked[1].captured, middle)
        XCTAssertNotNil(marked[1].closureAdjustment)
        XCTAssertFalse(observations[1].needsResurvey)
    }

    func testObservationJSONWithoutTheNewFieldsStillLoads() throws {
        let observation = FieldObservation(name: "小屋", workID: "preview", captured: samplePosition())
        let data = try JSONEncoder().encode(observation)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        var stripped = object ?? [:]
        stripped.removeValue(forKey: "needsResurvey")
        stripped.removeValue(forKey: "corrected")
        stripped.removeValue(forKey: "closureAdjustment")
        stripped.removeValue(forKey: "appliedCorrectionID")
        let encoded = try JSONSerialization.data(withJSONObject: stripped)
        let decoded = try JSONDecoder().decode(FieldObservation.self, from: encoded)
        XCTAssertFalse(decoded.needsResurvey)
        XCTAssertNil(decoded.corrected)
        XCTAssertNil(decoded.closureAdjustment)
        XCTAssertEqual(decoded.name, "小屋")
        XCTAssertEqual(decoded.captured.horizontalAccuracyMeters, observation.captured.horizontalAccuracyMeters, accuracy: 1e-9)
    }

    private func deskPoint() -> ControlPoint {
        ControlPoint(
            id: "desk",
            name: "机上",
            kind: "見本",
            latitudeDegrees: 35,
            longitudeDegrees: 139,
            heightMeters: 10,
            heightKind: .ellipsoidal
        )
    }

    private var iphone: InstrumentState {
        InstrumentState(receiver: .iphoneGPS, stage: .iphone, fixQuality: .standalone)
    }

    private func round(_ index: Int, point: ControlPoint, east: Double, north: Double, height: Double) -> BenchmarkRound {
        let started = PreviewClock.instant.addingTimeInterval(Double(index) * 10)
        let sample = placed(point, east: east, north: north, height: height, at: started)
        let statistics = BenchmarkStatistics.make(point: point, samples: [sample])!
        return BenchmarkRound(
            index: index,
            startedAt: started,
            samples: [sample],
            statistics: statistics,
            instrument: iphone
        )
    }

    private func placed(
        _ point: ControlPoint,
        east: Double,
        north: Double,
        height: Double,
        at time: Date
    ) -> BenchmarkSample {
        let distance = (east * east + north * north).squareRoot()
        let azimuth = distance == 0 ? 0 : GeoMath.degrees(fromRadians: GeoMath.arctangent(east, north))
        let place = GRS80Geodesic.direct(
            latitude: point.latitudeDegrees,
            longitude: point.longitudeDegrees,
            azimuthDegrees: azimuth,
            distanceMeters: distance
        )
        return BenchmarkSample(
            loggedAt: time,
            position: GeodeticPosition(
                latitudeDegrees: place?.latitude ?? point.latitudeDegrees,
                longitudeDegrees: place?.longitude ?? point.longitudeDegrees,
                ellipsoidalHeightMeters: height,
                horizontalAccuracyMeters: 3,
                verticalAccuracyMeters: 4,
                timestamp: time,
                stage: .iphone,
                fixQuality: .standalone,
                receiver: .iphoneGPS
            )
        )
    }

    private func curve(_ points: [(TimeInterval, Double)]) -> [ConvergenceSample] {
        points.map { point in
            ConvergenceSample(
                elapsedSeconds: point.0,
                eastMeters: point.1,
                northMeters: 0,
                horizontalMeters: abs(point.1),
                verticalMeters: nil
            )
        }
    }

    private func curve(_ points: [(TimeInterval, Double, Double)]) -> [ConvergenceSample] {
        points.map { point in
            ConvergenceSample(
                elapsedSeconds: point.0,
                eastMeters: point.1,
                northMeters: 0,
                horizontalMeters: abs(point.1),
                verticalMeters: point.2
            )
        }
    }

    private func work(_ id: String) -> WorkRequirement {
        WorkCatalog.provisional.works.first { $0.id == id }!
    }

    private func aged(_ correction: ControlCorrection, by seconds: TimeInterval) -> ControlCorrection {
        var copy = correction
        copy.acquiredAt = PreviewClock.instant.addingTimeInterval(-seconds)
        return copy
    }
}
