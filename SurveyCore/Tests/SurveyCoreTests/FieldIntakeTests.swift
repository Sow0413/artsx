import XCTest
@testable import SurveyCore

final class FieldIntakeTests: XCTestCase {
    func testSIMAImportKeepsOneHeightAndPlotsInZoneSeven() throws {
        let text = """
        G00,02,
        A01,1,BP,1000.000,-2000.000,12.340,
        A99,
        """
        let result = FieldIntake.read(data: Data(text.utf8), fileName: "a.sim", zone: 7, heightMap: nil)
        XCTAssertEqual(result.kind, .sima)
        XCTAssertFalse(result.needsHeightMap)
        let point = try XCTUnwrap(result.points.first)
        XCTAssertEqual(point.name, "BP")
        XCTAssertEqual(point.northingMeters, 1000, accuracy: 0.001)
        XCTAssertEqual(point.eastingMeters, -2000, accuracy: 0.001)
        XCTAssertEqual(point.heightMeters ?? 0, 12.34, accuracy: 0.001)
        XCTAssertNil(point.groundLevelMeters)
        XCTAssertNil(point.formationHeightMeters)
        XCTAssertEqual(point.zone, 7)
        XCTAssertGreaterThan(point.latitudeDegrees, 30)
        XCTAssertLessThan(point.latitudeDegrees, 40)
    }

    func testNameSuffixMergesGroundAndFormation() throws {
        let text = """
        A01,1,P1-GL,1000,-2000,10.500,
        A01,2,P1-FH,1000,-2000,12.300,
        """
        let result = FieldIntake.read(data: Data(text.utf8), fileName: "h.sima", zone: 7, heightMap: nil)
        XCTAssertEqual(result.points.count, 1)
        let point = try XCTUnwrap(result.points.first)
        XCTAssertEqual(point.name, "P1")
        XCTAssertEqual(point.groundLevelMeters ?? 0, 10.5, accuracy: 0.001)
        XCTAssertEqual(point.formationHeightMeters ?? 0, 12.3, accuracy: 0.001)
        let fill = CutFill.make(formation: point.formationHeightMeters, ground: point.groundLevelMeters)
        XCTAssertEqual(fill.word, "盛土")
        XCTAssertEqual(fill.differenceMeters ?? 0, 1.8, accuracy: 0.001)
        XCTAssertEqual(CutFill.make(formation: 10, ground: 12.3).word, "切土")
    }

    func testUnlabeledHeightColumnsWaitForAMap() throws {
        let text = "A01,1,P1,1000,-2000,10.5,12.3,\n"
        let waiting = FieldIntake.read(data: Data(text.utf8), fileName: "a.sima", zone: 7, heightMap: nil)
        XCTAssertTrue(waiting.needsHeightMap)
        XCTAssertEqual(waiting.columnCount, 2)
        XCTAssertTrue(waiting.points.isEmpty)
        let mapped = FieldIntake.read(
            data: Data(text.utf8),
            fileName: "a.sima",
            zone: 7,
            heightMap: HeightColumnMap(groundColumn: 0, formationColumn: 1)
        )
        let point = try XCTUnwrap(mapped.points.first)
        XCTAssertEqual(point.groundLevelMeters ?? 0, 10.5, accuracy: 0.001)
        XCTAssertEqual(point.formationHeightMeters ?? 0, 12.3, accuracy: 0.001)
        XCTAssertFalse(mapped.needsHeightMap)
    }

    func testLabeledHeightsDoNotAsk() throws {
        let text = "A01,1,P1,1000,-2000,10.5,GL,12.3,FH,\n"
        let result = FieldIntake.read(data: Data(text.utf8), fileName: "a.sima", zone: 7, heightMap: nil)
        XCTAssertFalse(result.needsHeightMap)
        let point = try XCTUnwrap(result.points.first)
        XCTAssertEqual(point.groundLevelMeters ?? 0, 10.5, accuracy: 0.001)
        XCTAssertEqual(point.formationHeightMeters ?? 0, 12.3, accuracy: 0.001)
    }

    func testCoordinateListReadsDecimalDMSAndHeader() throws {
        let decimal = FieldIntake.read(data: Data("A,35.0,137.2,1.5\n".utf8), fileName: "p.csv", zone: 7, heightMap: nil)
        XCTAssertEqual(decimal.kind, .list)
        XCTAssertEqual(decimal.points.first?.name, "A")
        XCTAssertEqual(decimal.points.first?.heightMeters ?? 0, 1.5, accuracy: 0.001)

        let dms = "B,35°40'52.4\"N,139°46'01.2\"E\n"
        let angled = FieldIntake.read(data: Data(dms.utf8), fileName: "p.txt", zone: 9, heightMap: nil)
        let point = try XCTUnwrap(angled.points.first)
        XCTAssertEqual(point.latitudeDegrees, 35 + 40.0 / 60 + 52.4 / 3600, accuracy: 1e-6)
        XCTAssertEqual(point.longitudeDegrees, 139 + 46.0 / 60 + 1.2 / 3600, accuracy: 1e-6)

        let headed = """
        name,lat,lon,GL,FH
        C,35.1,137.1,8.0,9.25
        """
        let named = FieldIntake.read(data: Data(headed.utf8), fileName: "p.csv", zone: 7, heightMap: nil)
        XCTAssertFalse(named.needsHeightMap)
        XCTAssertEqual(named.points.first?.groundLevelMeters ?? 0, 8, accuracy: 0.001)
        XCTAssertEqual(named.points.first?.formationHeightMeters ?? 0, 9.25, accuracy: 0.001)
        XCTAssertEqual(named.points.first?.mapLabel, "C 9.250")
    }

    func testPDFAndDXFAreNotCoordinateFiles() {
        XCTAssertEqual(FieldIntake.detect(data: Data("%PDF-1.4".utf8), fileName: "drawing.pdf"), .pdf)
        let dxf = "0\nSECTION\n2\nENTITIES\n"
        XCTAssertEqual(FieldIntake.detect(data: Data(dxf.utf8), fileName: "site.dxf"), .drawing)
    }

    func testSpanAgreesWithinToleranceAndFlagsAMiss() throws {
        let start = try XCTUnwrap(PlaneRectangular.inverse(northingMeters: 0, eastingMeters: 0, zone: 7))
        let end = try XCTUnwrap(PlaneRectangular.inverse(northingMeters: 0, eastingMeters: 10, zone: 7))
        let startPlane = try XCTUnwrap(PlaneRectangular.forward(latitudeDegrees: start.latitudeDegrees, longitudeDegrees: start.longitudeDegrees, zone: 7))
        let endPlane = try XCTUnwrap(PlaneRectangular.forward(latitudeDegrees: end.latitudeDegrees, longitudeDegrees: end.longitudeDegrees, zone: 7))
        let span = GeoMath.hypotenuse(startPlane.northingMeters - endPlane.northingMeters, startPlane.eastingMeters - endPlane.eastingMeters)
        let tight = AlignmentTolerance(millimeters: 20, denominator: 5000)
        let matching = [
            pair("A", drawingX: 0, drawingY: 0, start),
            pair("B", drawingX: span, drawingY: 0, end)
        ]
        let ok = try XCTUnwrap(AlignmentSpan.check(pairs: matching, zone: 7, tolerance: tight))
        XCTAssertEqual(ok.verdict, .ok)
        XCTAssertEqual(ok.differenceMillimeters, 0, accuracy: 0.05)

        let short = [
            pair("A", drawingX: 0, drawingY: 0, start),
            pair("B", drawingX: span - 1, drawingY: 0, end)
        ]
        let review = try XCTUnwrap(AlignmentSpan.check(pairs: short, zone: 7, tolerance: tight))
        XCTAssertEqual(review.verdict, .review)
        XCTAssertEqual(review.differenceMillimeters, 1000, accuracy: 1)
        XCTAssertTrue(review.ratioText.hasPrefix("1/"))
    }

    func testChangingZoneRereadsSIMAGrid() throws {
        let text = "A01,1,BP,1000,-2000,1,\n"
        let point = try XCTUnwrap(FieldIntake.read(data: Data(text.utf8), fileName: "a.sima", zone: 7, heightMap: nil).points.first)
        let moved = point.relocated(to: 8)
        XCTAssertEqual(moved.zone, 8)
        XCTAssertEqual(moved.northingMeters, point.northingMeters, accuracy: 0.001)
        XCTAssertEqual(moved.eastingMeters, point.eastingMeters, accuracy: 0.001)
        // VII と VIII は原点緯度がどちらも 36°なので、同じ北・東の緯度は変わらない。経度が動く。
        XCTAssertEqual(moved.latitudeDegrees, point.latitudeDegrees, accuracy: 1e-8)
        XCTAssertNotEqual(moved.longitudeDegrees, point.longitudeDegrees, accuracy: 1e-4)
        let shifted = point.relocated(to: 10)
        XCTAssertEqual(shifted.northingMeters, point.northingMeters, accuracy: 0.001)
        XCTAssertNotEqual(shifted.latitudeDegrees, point.latitudeDegrees, accuracy: 1e-4)
    }

    func testAlongLineSnapAndFreePoint() throws {
        let start = PlanarPoint(x: 0, y: 0)
        let end = PlanarPoint(x: 10, y: 0)
        let bounds = DrawingBounds(minX: 0, minY: -1, maxX: 10, maxY: 1)
        let entity = DrawingEntity(
            id: 0,
            layer: "0",
            color: DrawingColor(red: 0, green: 0, blue: 0),
            primitive: .line(start, end),
            bounds: bounds
        )
        let layer = DrawingLayer(name: "0", color: DrawingColor(red: 0, green: 0, blue: 0), isVisible: true)
        let document = DrawingDocument(
            layers: [layer],
            entities: [entity],
            bounds: bounds,
            unsupportedCounts: [:],
            codePage: "UTF-8",
            unitWarning: nil,
            index: DrawingSpatialIndex(entities: [entity])
        )
        let snapped = DrawingSnap.place(in: document, to: PlanarPoint(x: 5, y: 0.2), tolerance: 0.5, free: false)
        XCTAssertEqual(snapped.label, "線上")
        XCTAssertEqual(snapped.point.x, 5, accuracy: 0.001)
        XCTAssertEqual(snapped.point.y, 0, accuracy: 0.001)
        let free = DrawingSnap.place(in: document, to: PlanarPoint(x: 5, y: 0.2), tolerance: 0.5, free: true)
        XCTAssertEqual(free.label, "任意")
        XCTAssertEqual(free.point.y, 0.2, accuracy: 0.001)
    }

    func testPointsRoundTripInTheProject() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try ProjectStore.create(name: "現場", at: root)
        let point = FieldPoint(
            id: "BP",
            name: "BP",
            northingMeters: 1,
            eastingMeters: 2,
            zone: 7,
            latitudeDegrees: 35,
            longitudeDegrees: 137,
            formationHeightMeters: 3,
            origin: .sima,
            anchor: .grid
        )
        try FieldPointStore.save([point], projectName: project.name, at: root)
        let loaded = FieldPointStore.load(projectName: project.name, at: root)
        XCTAssertEqual(loaded, [point])
    }

    private func pair(
        _ label: String,
        drawingX: Double,
        drawingY: Double,
        _ geo: (latitudeDegrees: Double, longitudeDegrees: Double)
    ) -> AlignmentPair {
        AlignmentPair(
            drawingX: drawingX,
            drawingY: drawingY,
            latitudeDegrees: geo.latitudeDegrees,
            longitudeDegrees: geo.longitudeDegrees,
            kind: .coordinateBook,
            label: label
        )
    }
}
