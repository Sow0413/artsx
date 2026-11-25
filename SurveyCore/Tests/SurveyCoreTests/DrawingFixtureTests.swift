import XCTest
@testable import SurveyCore

final class DrawingFixtureTests: XCTestCase {
    func testIrabuXVIKeepsJapaneseAndHonorsEPSG6684() throws {
        let document = try DXFParser.parse(fixture("1_irabu_xvi_utf8.dxf"))
        let meta = try XCTUnwrap(DrawingSidecar.load(fixture("1_irabu_xvi_utf8.dxf.meta.json")))
        XCTAssertEqual(meta.epsg, 6684)
        XCTAssertEqual(meta.unit, "m")
        XCTAssertEqual(meta.zone, 16)
        XCTAssertEqual(meta.drawingAxis, .cadEastNorth)
        XCTAssertEqual(document.entities.count, 10)
        XCTAssertEqual(
            Set(document.layers.map(\.name)),
            ["中心線", "用地境界", "構造物", "測設_基準点", "注記"]
        )
        XCTAssertFalse(document.layers.contains { $0.name.contains("\u{FFFD}") || $0.name.contains("?") })
        let texts = strings(in: document)
        XCTAssertEqual(Set(texts.filter { $0.hasPrefix("IRB-") }), ["IRB-1", "IRB-2", "IRB-3"])
        XCTAssertTrue(texts.contains { $0.contains("伊良部") })
        let points = self.points(on: "測設_基準点", in: document)
        let places = [
            (24.8379671, 125.1939067),
            (24.8379497, 125.1960829),
            (24.8390416, 125.1950052)
        ]
        for place in places {
            assertOnPlane(points, latitude: place.0, longitude: place.1, zone: meta.zone ?? 0)
        }
    }

    func testNagoyaCP932KeepsJapaneseNames() throws {
        let document = try DXFParser.parse(fixture("2_nagoya_vii_ac1021_ansi932.dxf"))
        XCTAssertEqual(
            Set(document.layers.map(\.name)),
            ["道路中心線", "建物", "基準点", "注記"]
        )
        let texts = strings(in: document)
        XCTAssertTrue(texts.contains("基準点１"))
        XCTAssertTrue(texts.contains("基準点２"))
        XCTAssertTrue(texts.contains("境界杭Ａ"))
        XCTAssertTrue(texts.contains { $0.contains("ひらがな") && $0.contains("カタカナ") })
        let points = self.points(on: "基準点", in: document)
        let places = [
            (35.1853183, 136.8983418),
            (35.1853212, 136.8996594),
            (35.1861310, 136.8989979)
        ]
        for place in places {
            assertOnPlane(points, latitude: place.0, longitude: place.1, zone: 7)
        }
    }

    func testLocalMillimetresWarnAndScaleToMeters() throws {
        let document = try DXFParser.parse(fixture("3_site_local_mm.dxf"))
        XCTAssertEqual(document.entities.count, 8)
        XCTAssertEqual(document.unitCode, 4)
        XCTAssertEqual(document.metersPerUnit, 0.001)
        XCTAssertTrue(document.unitWarning?.contains("ミリ") == true)
        let scaled = points(on: "points", in: document).map {
            PlanarPoint(x: $0.x * document.metersPerUnit, y: $0.y * document.metersPerUnit)
        }
        XCTAssertTrue(scaled.contains { $0.distance(to: PlanarPoint(x: 0, y: 0)) < 1e-6 })
        XCTAssertTrue(scaled.contains { $0.distance(to: PlanarPoint(x: 50, y: 0)) < 1e-6 })
        XCTAssertTrue(scaled.contains { $0.distance(to: PlanarPoint(x: 50, y: 30)) < 1e-6 })
    }

    func testHeavyDrawingLoadsCappedAndKeepsCorners() throws {
        let started = Date()
        let document = try DXFParser.parse(HeavyDrawingFixture.makeDXF())
        let overlay = DrawingPlacement.overlay(
            document: document,
            zone: HeavyDrawingFixture.zone,
            axis: .cadEastNorth,
            transform: nil
        )
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual(document.entities.count, HeavyDrawingFixture.lineCount)
        XCTAssertTrue(overlay.capped)
        XCTAssertLessThan(elapsed, 60, "150,000 本の読み込みが 60 秒を超えた")
        XCTAssertEqual(document.bounds.minX, HeavyDrawingFixture.southWest.x, accuracy: 1e-6)
        XCTAssertEqual(document.bounds.minY, HeavyDrawingFixture.southWest.y, accuracy: 1e-6)
        XCTAssertEqual(document.bounds.maxX, HeavyDrawingFixture.northEast.x, accuracy: 1e-6)
        XCTAssertEqual(document.bounds.maxY, HeavyDrawingFixture.northEast.y, accuracy: 1e-6)
        assertOnPlane(
            [HeavyDrawingFixture.southWest],
            latitude: HeavyDrawingFixture.southWestLatitude,
            longitude: HeavyDrawingFixture.southWestLongitude,
            zone: HeavyDrawingFixture.zone
        )
        assertOnPlane(
            [HeavyDrawingFixture.northEast],
            latitude: HeavyDrawingFixture.northEastLatitude,
            longitude: HeavyDrawingFixture.northEastLongitude,
            zone: HeavyDrawingFixture.zone
        )
    }

    func testBrokenDXFReportsACleanError() throws {
        XCTAssertThrowsError(try DXFParser.parse(fixture("6_broken.dxf"))) { error in
            XCTAssertEqual(error as? DXFError, .truncated)
            XCTAssertEqual((error as? DXFError)?.description, "DXF が途中で切れています。")
        }
    }

    func testKameyamaSFCSkipsUntilTheFileArrives() throws {
        let url = fixtureURL("4_kameyama_vi_basemap.sfc")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("4_kameyama_vi_basemap.sfc はまだ無い")
        }
        let document = try SFCParser.parse(Data(contentsOf: url))
        XCTAssertFalse(document.entities.isEmpty)
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: fixtureURL(name))
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("drawings_test")
            .appendingPathComponent(name)
    }

    private func strings(in document: DrawingDocument) -> [String] {
        document.entities.compactMap { entity in
            if case let .text(_, string, _, _) = entity.primitive { return string }
            return nil
        }
    }

    private func points(on layer: String, in document: DrawingDocument) -> [PlanarPoint] {
        document.entities.compactMap { entity in
            guard entity.layer == layer, case let .point(point) = entity.primitive else { return nil }
            return point
        }
    }

    private func assertOnPlane(_ points: [PlanarPoint], latitude: Double, longitude: Double, zone: Int) {
        let plane = PlaneRectangular.forward(latitudeDegrees: latitude, longitudeDegrees: longitude, zone: zone)
        let east = plane?.eastingMeters ?? .greatestFiniteMagnitude
        let north = plane?.northingMeters ?? .greatestFiniteMagnitude
        let best = points.map { hypot($0.x - east, $0.y - north) }.min() ?? .greatestFiniteMagnitude
        XCTAssertLessThan(best, 0.01, "緯度 \(latitude) 経度 \(longitude) との差 \(best) m")
    }
}
