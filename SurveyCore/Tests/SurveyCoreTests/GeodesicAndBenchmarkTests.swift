import XCTest
@testable import SurveyCore

final class GeodesicAndBenchmarkTests: XCTestCase {
    func testEquatorAndMeridianMatchIndependentLengths() {
        let quarter = GRS80.equatorialRadiusMeters * Double.pi / 2
        let equator = GRS80Geodesic.inverse(latitude1: 0, longitude1: 0, latitude2: 0, longitude2: 90)
        XCTAssertEqual(equator?.distanceMeters ?? -1, quarter, accuracy: 1e-4)
        XCTAssertEqual(equator?.azimuthDegrees ?? -1, 90, accuracy: 1e-8)

        let oneDegree = GRS80Geodesic.inverse(latitude1: 0, longitude1: 0, latitude2: 1, longitude2: 0)
        XCTAssertEqual(oneDegree?.distanceMeters ?? -1, meridianMeters(toLatitude: 1), accuracy: 1e-4)
        XCTAssertEqual(oneDegree?.azimuthDegrees ?? -1, 0, accuracy: 1e-8)

        let toPole = GRS80Geodesic.inverse(latitude1: 0, longitude1: 0, latitude2: 90, longitude2: 0)
        XCTAssertEqual(toPole?.distanceMeters ?? -1, meridianMeters(toLatitude: 90), accuracy: 1e-3)
        XCTAssertNil(GRS80Geodesic.inverse(latitude1: 0, longitude1: 0, latitude2: 0, longitude2: 180))
        XCTAssertEqual(
            GRS80Geodesic.inverse(latitude1: 35, longitude1: 139, latitude2: 35, longitude2: 139)?.distanceMeters ?? -1,
            0,
            accuracy: 1e-9
        )
    }

    func testDirectAndInverseRoundTripAtSurveyDistance() {
        let originLatitude = 35.658099222222
        let originLongitude = 139.741357472222
        let north = GRS80Geodesic.direct(
            latitude: originLatitude,
            longitude: originLongitude,
            azimuthDegrees: 0,
            distanceMeters: 10
        )
        let back = GRS80Geodesic.inverse(
            latitude1: originLatitude,
            longitude1: originLongitude,
            latitude2: north?.latitude ?? 0,
            longitude2: north?.longitude ?? 0
        )
        XCTAssertEqual(back?.distanceMeters ?? -1, 10, accuracy: 1e-6)
        XCTAssertEqual(back?.azimuthDegrees ?? -1, 0, accuracy: 1e-6)
        XCTAssertEqual(back?.northMeters ?? -1, 10, accuracy: 1e-6)
        XCTAssertEqual(back?.eastMeters ?? 99, 0, accuracy: 1e-6)

        let east = GRS80Geodesic.direct(
            latitude: originLatitude,
            longitude: originLongitude,
            azimuthDegrees: 90,
            distanceMeters: 25
        )
        let eastBack = GRS80Geodesic.inverse(
            latitude1: originLatitude,
            longitude1: originLongitude,
            latitude2: east?.latitude ?? 0,
            longitude2: east?.longitude ?? 0
        )
        XCTAssertEqual(eastBack?.distanceMeters ?? -1, 25, accuracy: 1e-4)
        XCTAssertEqual(eastBack?.azimuthDegrees ?? 0, 90, accuracy: 1e-4)
    }

    func testMeanOffsetSpreadAndOptimism() {
        let point = ControlPoint(
            id: "desk",
            name: "机上",
            kind: "見本",
            latitudeDegrees: 35.0,
            longitudeDegrees: 139.0,
            heightMeters: 10,
            heightKind: .ellipsoidal
        )
        let north = moved(point, east: 0, north: 10, height: 10, horizontal: 3, vertical: 0.5)
        let east = moved(point, east: 10, north: 0, height: 12, horizontal: 20, vertical: 0.5)
        let statistics = BenchmarkStatistics.make(point: point, samples: [north, east])
        XCTAssertEqual(statistics?.sampleCount, 2)
        XCTAssertEqual(statistics?.horizontalDifferenceMeters ?? -1, (50 as Double).squareRoot(), accuracy: 1e-4)
        XCTAssertEqual(statistics?.verticalDifferenceMeters ?? -99, 1, accuracy: 1e-6)
        XCTAssertEqual(statistics?.verticalComparison, .ellipsoidal)
        XCTAssertEqual(statistics?.horizontalStdMeters ?? -1, 10, accuracy: 1e-3)
        XCTAssertEqual(statistics?.horizontal95Meters ?? -1, (50 as Double).squareRoot(), accuracy: 1e-3)
        XCTAssertEqual(statistics?.meanReportedHorizontalMeters ?? -1, 11.5, accuracy: 1e-9)
        XCTAssertEqual(statistics?.horizontalOptimistic, false)
        XCTAssertEqual(statistics?.horizontalEpochsOutside, 1)
        XCTAssertEqual(statistics?.horizontal68Optimistic, true)
        XCTAssertEqual(statistics?.verticalOptimistic, true)
        XCTAssertEqual(
            BenchmarkText.horizontalOptimism(statistics!),
            "報告した水平精度の平均は 11.50m。実際のずれを包んでいます。"
        )
        XCTAssertTrue(BenchmarkText.verticalNote(statistics!).contains("楕円体高どうし"))

        let optimistic = BenchmarkStatistics.make(point: point, samples: [
            moved(point, east: 0, north: 8, height: 10, horizontal: 3, vertical: nil)
        ])
        XCTAssertEqual(optimistic?.horizontalOptimistic, true)
        XCTAssertEqual(optimistic?.horizontalStdMeters ?? -1, 0, accuracy: 1e-9)
        XCTAssertTrue(BenchmarkText.horizontalOptimism(optimistic!).contains("楽観的"))
    }

    func testOrthometricHeightIsNotJudged() {
        let point = ControlPoint(
            id: "bm",
            name: "水準",
            kind: "水準点",
            latitudeDegrees: 35,
            longitudeDegrees: 139,
            heightMeters: 24.39,
            heightKind: .orthometric
        )
        let sample = moved(point, east: 0, north: 0, height: 61, horizontal: 5, vertical: 1)
        let statistics = BenchmarkStatistics.make(point: point, samples: [sample])
        XCTAssertEqual(statistics?.verticalComparison, .orthometricUncorrected)
        XCTAssertEqual(statistics?.verticalDifferenceMeters ?? 0, 36.61, accuracy: 1e-9)
        XCTAssertNil(statistics?.verticalOptimistic)
        XCTAssertNil(statistics?.vertical68Optimistic)
        XCTAssertTrue(BenchmarkText.verticalNote(statistics!).contains("ジオイド"))
    }

    func testRecorderKeepsOneSamplePerSecondUntilDuration() {
        let point = ControlPoint(id: "a", name: "A,B", kind: "三角点", latitudeDegrees: 35, longitudeDegrees: 139, heightKind: .unspecified)
        let start = PreviewClock.instant
        var recorder = BenchmarkRecorder(point: point, plan: BenchmarkPlan(durationSeconds: 3), startedAt: start)
        let reading = PositionReading(position: samplePosition(), availability: .available)
        recorder.tick(reading: .waiting, now: start)
        XCTAssertEqual(recorder.samples.count, 0)
        recorder.tick(reading: reading, now: start)
        recorder.tick(reading: reading, now: start.addingTimeInterval(0.4))
        recorder.tick(reading: reading, now: start.addingTimeInterval(1))
        recorder.tick(reading: reading, now: start.addingTimeInterval(2))
        XCTAssertEqual(recorder.samples.count, 3)
        XCTAssertFalse(recorder.isFinished(at: start.addingTimeInterval(2.9)))
        XCTAssertTrue(recorder.isFinished(at: start.addingTimeInterval(3)))
        recorder.tick(reading: reading, now: start.addingTimeInterval(3))
        XCTAssertEqual(recorder.samples.count, 3)
        XCTAssertEqual(BenchmarkPlan.durationTitle(600), "10分")
        XCTAssertEqual(BenchmarkPlan(durationSeconds: 600).expectedCount, 600)

        let statistics = BenchmarkStatistics.make(point: point, samples: recorder.samples)
        let csv = BenchmarkCSV.render(recorder: recorder, statistics: statistics!)
        XCTAssertTrue(csv.hasPrefix("kind,point_id,point_name,"))
        XCTAssertTrue(csv.contains("\"A,B\""))
        XCTAssertEqual(csv.components(separatedBy: "\nsample,").count - 1, 3)
        XCTAssertTrue(csv.contains("2026-10-20T00:00:00"))
    }

    func testCatalogJSONAndCSVAndNearby() {
        let json = """
        {"source":"test","points":[{"id":"near","name":"近い","kind":"三角点","grade":"四等","latitudeDegrees":35.0001,"longitudeDegrees":139,"heightMeters":1.5,"heightKind":"ellipsoidal","sourceNote":"机上"}]}
        """.data(using: .utf8)!
        let decoded = try? ControlPointCatalog.loadJSON(json)
        XCTAssertEqual(decoded?.first?.grade, "四等")
        XCTAssertEqual(decoded?.first?.comparableEllipsoidalHeightMeters ?? -1, 1.5, accuracy: 1e-9)

        let csv = """
        id,name,kind,grade,latitude_deg,longitude_deg,height_m,height_kind,source_note
        far,遠い,三角点,,36.5,139,,"orthometric","注記"
        """
        let far = try? ControlPointCatalog.loadCSV(csv)
        XCTAssertEqual(far?.count, 1)
        XCTAssertNil(far?.first?.heightMeters)
        XCTAssertEqual(far?.first?.heightKind, .orthometric)

        let points = (decoded ?? []) + (far ?? [])
        let nearby = ControlPointCatalog.visible(points, userLatitude: 35, userLongitude: 139, bounds: nil, radiusMeters: 50_000)
        XCTAssertEqual(nearby.map(\.id), ["near"])
        let inView = ControlPointCatalog.visible(
            points,
            userLatitude: nil,
            userLongitude: nil,
            bounds: GeoBounds(south: 36, west: 138, north: 37, east: 140)
        )
        XCTAssertEqual(inView.map(\.id), ["far"])

        let bundled = sampleCatalogURL()
        let data = try? Data(contentsOf: bundled)
        let file = data.flatMap { try? JSONDecoder().decode(ControlPointFile.self, from: $0) }
        XCTAssertEqual(file?.points.count, 4)
        let origin = file?.points.first { $0.id == "jgd-origin" }
        XCTAssertEqual(origin?.latitudeDegrees ?? 0, 35.658099222222, accuracy: 1e-12)
        XCTAssertEqual(origin?.longitudeDegrees ?? 0, 139.741357472222, accuracy: 1e-12)
        XCTAssertEqual(file?.points.first { $0.id == "fuji-2" }?.heightMeters ?? 0, 3_775.56, accuracy: 1e-9)
    }

    private func moved(
        _ point: ControlPoint,
        east: Double,
        north: Double,
        height: Double,
        horizontal: Double,
        vertical: Double?
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
            loggedAt: PreviewClock.instant,
            position: samplePosition(
                latitude: place?.latitude ?? point.latitudeDegrees,
                longitude: place?.longitude ?? point.longitudeDegrees,
                height: height,
                accuracy: horizontal,
                verticalAccuracy: vertical
            )
        )
    }

    private func sampleCatalogURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SurveyApp/Resources/sample-control-points.json")
    }

    /// 子午線弧長。Vincenty とは別の級数で、テストの答えを固定しない。
    private func meridianMeters(toLatitude degrees: Double) -> Double {
        let a = GRS80.equatorialRadiusMeters
        let b = GRS80.polarRadiusMeters
        let n = (a - b) / (a + b)
        let n2 = n * n
        let n3 = n2 * n
        let n4 = n2 * n2
        let n5 = n4 * n
        let n6 = n3 * n3
        let arc = a / (1 + n) * (1 + n2 / 4 + n4 / 64 + n6 / 256)
        let phi = GeoMath.radians(fromDegrees: degrees)
        return arc * (
            phi
                - (1.5 * n - 9.0 / 16 * n3) * GeoMath.sine(2 * phi)
                + (15.0 / 16 * n2 - 15.0 / 32 * n4) * GeoMath.sine(4 * phi)
                - (35.0 / 48 * n3 - 105.0 / 256 * n5) * GeoMath.sine(6 * phi)
                + (315.0 / 512 * n4) * GeoMath.sine(8 * phi)
        )
    }
}
