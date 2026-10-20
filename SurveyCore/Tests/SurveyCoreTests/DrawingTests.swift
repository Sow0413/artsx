import XCTest
@testable import SurveyCore

final class DrawingTests: XCTestCase {
    func testZoneOriginsAndPublishedZoneNineExample() {
        for zone in 1...19 {
            let origin = PlaneRectangular.zone(zone)!
            let projected = PlaneRectangular.forward(
                latitudeDegrees: origin.originLatitudeDegrees,
                longitudeDegrees: origin.originLongitudeDegrees,
                zone: zone
            )
            XCTAssertEqual(projected?.northingMeters ?? 99, 0, accuracy: 1e-4, "\(zone)系の原点 X")
            XCTAssertEqual(projected?.eastingMeters ?? 99, 0, accuracy: 1e-4, "\(zone)系の原点 Y")
        }

        // 測量計算サイトの入力例に近い IX系の点。
        // 国土地理院が公開している n 級数で計算し、別式のレッドファーン横メルカトルとも 0.001 mm 以内で一致する。
        let latitude = 36 + 6.0 / 60 + 13.58925 / 3600
        let longitude = 140 + 5.0 / 60 + 16.27815 / 3600
        let plane = PlaneRectangular.forward(latitudeDegrees: latitude, longitudeDegrees: longitude, zone: 9)
        XCTAssertEqual(plane?.northingMeters ?? 0, 11_543.688321, accuracy: 0.001)
        XCTAssertEqual(plane?.eastingMeters ?? 0, 22_916.243554, accuracy: 0.001)

        let back = PlaneRectangular.inverse(
            northingMeters: plane!.northingMeters,
            eastingMeters: plane!.eastingMeters,
            zone: 9
        )
        XCTAssertEqual(back?.latitudeDegrees ?? 0, latitude, accuracy: 1e-9)
        XCTAssertEqual(back?.longitudeDegrees ?? 0, longitude, accuracy: 1e-9)

        let tokyo = PlaneRectangular.forward(latitudeDegrees: 35.681236, longitudeDegrees: 139.767125, zone: 9)
        XCTAssertEqual(tokyo?.northingMeters ?? 0, -35_363.237745, accuracy: 0.001)
        XCTAssertEqual(tokyo?.eastingMeters ?? 0, -5_992.919570, accuracy: 0.001)
        XCTAssertNil(PlaneRectangular.forward(latitudeDegrees: 35, longitudeDegrees: 139, zone: 0))
    }

    func testSimilarityLockScaleAndResiduals() {
        let rotated = SimilaritySolver.fit([
            (PlanarPoint(x: 0, y: 0), PlanarPoint(x: 5, y: 5)),
            (PlanarPoint(x: 10, y: 0), PlanarPoint(x: 5, y: 15))
        ], lockScale: false)
        XCTAssertEqual(rotated?.transform.scale ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(rotated?.transform.rotationDegrees ?? 0, 90, accuracy: 1e-6)
        XCTAssertEqual(rotated?.transform.translationEasting ?? 0, 5, accuracy: 1e-6)
        XCTAssertEqual(rotated?.transform.translationNorthing ?? 0, 5, accuracy: 1e-6)
        XCTAssertEqual(rotated?.rmsMeters ?? 1, 0, accuracy: 1e-6)

        let locked = SimilaritySolver.fit([
            (PlanarPoint(x: 0, y: 0), PlanarPoint(x: 0, y: 0)),
            (PlanarPoint(x: 2, y: 0), PlanarPoint(x: 4, y: 0))
        ], lockScale: true)
        XCTAssertEqual(locked?.transform.scale ?? 0, 1, accuracy: 1e-12)
        XCTAssertEqual(locked?.residualsMeters.count, 2)
        XCTAssertGreaterThan(locked?.rmsMeters ?? 0, 0.5)

        let free = SimilaritySolver.fit([
            (PlanarPoint(x: 0, y: 0), PlanarPoint(x: 0, y: 0)),
            (PlanarPoint(x: 2, y: 0), PlanarPoint(x: 4, y: 0))
        ], lockScale: false)
        XCTAssertEqual(free?.transform.scale ?? 0, 2, accuracy: 1e-9)
        XCTAssertEqual(free?.rmsMeters ?? 1, 0, accuracy: 1e-6)

        let three = SimilaritySolver.fit([
            (PlanarPoint(x: 0, y: 0), PlanarPoint(x: 0, y: 0)),
            (PlanarPoint(x: 10, y: 0), PlanarPoint(x: 10, y: 0)),
            (PlanarPoint(x: 0, y: 10), PlanarPoint(x: 0, y: 12))
        ], lockScale: true)
        XCTAssertEqual(three?.residualsMeters.count, 3)
        XCTAssertGreaterThan(three?.residualsMeters.max() ?? 0, 0.5)
        XCTAssertNil(SimilaritySolver.fit([(PlanarPoint(x: 0, y: 0), PlanarPoint(x: 1, y: 1))], lockScale: false))
    }

    func testZoneSuggestionAndWrongZoneWarning() {
        let origin = PlaneRectangular.inverse(northingMeters: 200, eastingMeters: 100, zone: 9)!
        let next = PlaneRectangular.inverse(northingMeters: 200, eastingMeters: 110, zone: 9)!
        let suggestion = ZoneAdvisor.suggest(pairs: [
            (drawingX: 100, drawingY: 200, latitude: origin.latitudeDegrees, longitude: origin.longitudeDegrees),
            (drawingX: 110, drawingY: 200, latitude: next.latitudeDegrees, longitude: next.longitudeDegrees)
        ])
        XCTAssertTrue(suggestion.matchesDrawingNumbers)
        XCTAssertEqual(suggestion.fromDrawingNumbers.first?.zone, 9)
        XCTAssertEqual(suggestion.fromDrawingNumbers.first?.axis, .cadEastNorth)
        XCTAssertLessThan(suggestion.fromDrawingNumbers.first?.rmsMeters ?? 99, 0.05)
        XCTAssertFalse(suggestion.fromDrawingNumbers.contains { $0.zone == 8 && $0.matchesNumbers })
        XCTAssertEqual(suggestion.forThisPlace.first?.zone, 9)

        let tokyo = PlaneRectangular.forward(latitudeDegrees: 35.681236, longitudeDegrees: 139.767125, zone: 9)!
        let warning = ZoneAdvisor.placement(
            drawingX: tokyo.eastingMeters,
            drawingY: tokyo.northingMeters,
            zone: 1,
            axis: .cadEastNorth,
            referenceLatitude: 35.681236,
            referenceLongitude: 139.767125,
            referenceName: "現在地"
        )
        XCTAssertNotNil(warning.message)
        XCTAssertGreaterThan(warning.distanceMeters, 20_000)
        XCTAssertTrue(warning.candidates.contains { $0.zone == 9 && $0.axis == .cadEastNorth })

        let quiet = ZoneAdvisor.placement(
            drawingX: tokyo.eastingMeters,
            drawingY: tokyo.northingMeters,
            zone: 9,
            axis: .cadEastNorth,
            referenceLatitude: 35.681236,
            referenceLongitude: 139.767125,
            referenceName: "現在地"
        )
        XCTAssertNil(quiet.message)
        XCTAssertLessThan(quiet.distanceMeters, 1)
    }

    func testLocalDrawingDoesNotPretendToMatchAZone() {
        let suggestion = ZoneAdvisor.suggest(pairs: [
            (drawingX: 0, drawingY: 0, latitude: 35.681236, longitude: 139.767125),
            (drawingX: 10, drawingY: 0, latitude: 35.681236, longitude: 139.7673)
        ])
        XCTAssertFalse(suggestion.matchesDrawingNumbers)
        XCTAssertEqual(suggestion.forThisPlace.first?.zone, 9)
    }

    func testICPTranslatesSegments() {
        let source = square(origin: PlanarPoint(x: 0, y: 0), size: 10)
        let target = square(origin: PlanarPoint(x: 20, y: -5), size: 10)
        let result = ICP2D.align(ICP2DRequest(
            source: source,
            target: target,
            initial: .identity,
            lockScale: true,
            outlierMeters: 40
        ))
        XCTAssertEqual(result?.transform.translationEasting ?? 0, 20, accuracy: 0.05)
        XCTAssertEqual(result?.transform.translationNorthing ?? 0, -5, accuracy: 0.05)
        XCTAssertEqual(result?.transform.rotationDegrees ?? 9, 0, accuracy: 0.05)
        XCTAssertLessThan(result?.rmsMeters ?? 1, 0.05)
        XCTAssertGreaterThan(result?.iterations ?? 0, 0)
    }

    func testDXFEntitiesShiftJISAndIndex() throws {
        let document = try DXFParser.parse(Data(sampleDXF.utf8))
        XCTAssertEqual(document.codePage, "UTF-8")
        XCTAssertEqual(document.unitWarning?.contains("ミリ"), true)
        XCTAssertEqual(document.unsupportedCounts["SPLINE"], 1)
        XCTAssertEqual(document.unsupportedCounts["HATCH"], 1)
        XCTAssertEqual(document.layers.first { $0.name == "境界" }?.color, DrawingColor.aci(1))

        let line = try entity(.line(PlanarPoint(x: 0, y: 0), PlanarPoint(x: 10, y: 0)), in: document)
        XCTAssertEqual(line.color, DrawingColor.aci(5))
        XCTAssertEqual(try text("基準", in: document), "基準")
        XCTAssertEqual(try text("あいう", in: document), "あいう")
        XCTAssertTrue(document.entities.contains { entity in
            if case let .point(point) = entity.primitive { return point == PlanarPoint(x: 3, y: 4) }
            return false
        })
        XCTAssertTrue(document.entities.contains { entity in
            if case let .circle(_, radius) = entity.primitive { return abs(radius - 1.5) < 1e-9 }
            return false
        })
        XCTAssertTrue(document.entities.contains { entity in
            if case let .line(start, end) = entity.primitive {
                return start.distance(to: PlanarPoint(x: 100, y: 200)) < 1e-6
                    && end.distance(to: PlanarPoint(x: 102, y: 200)) < 1e-6
            }
            return false
        })

        let bulge = document.entities.compactMap { entity -> [PlanarPoint]? in
            if case let .polyline(_, _, display) = entity.primitive { return display }
            return nil
        }.first
        XCTAssertTrue(bulge?.contains { $0.distance(to: PlanarPoint(x: 1, y: -1)) < 0.15 } == true)

        let hit = document.nearestVertex(to: PlanarPoint(x: 10.1, y: 0.1), tolerance: 0.5)
        XCTAssertEqual(hit?.point, PlanarPoint(x: 10, y: 0))
        let missed = document.entities(in: DrawingBounds(minX: 5_000, minY: 5_000, maxX: 5_010, maxY: 5_010))
        XCTAssertTrue(missed.isEmpty)

        let japanese = try DXFParser.parse(shiftJISDXF())
        XCTAssertTrue(japanese.codePage.uppercased().contains("932") || japanese.codePage.contains("Shift"))
        XCTAssertTrue(japanese.layers.contains { $0.name == "図面" })
        XCTAssertEqual(try text("杭", in: japanese), "杭")

        let hidden = japanese.settingLayer("図面", visible: false)
        XCTAssertTrue(hidden.entities(in: hidden.bounds).isEmpty)
        XCTAssertThrowsError(try DXFParser.parse(Data("AutoCAD Binary DXF\r\n".utf8))) { error in
            XCTAssertEqual(error as? DXFError, .binary)
        }
    }

    func testPlacementUsesOneConversion() throws {
        let document = try DXFParser.parse(Data(sampleDXF.utf8))
        let overlay = DrawingPlacement.overlay(document: document, zone: 9, axis: .cadEastNorth, transform: nil)
        XCTAssertFalse(overlay.paths.isEmpty)
        let origin = try XCTUnwrap(DrawingPlacement.geographic(PlanarPoint(x: 0, y: 0), zone: 9, axis: .cadEastNorth, transform: nil))
        let zoneOrigin = PlaneRectangular.zone(9)!
        XCTAssertEqual(origin.latitudeDegrees, zoneOrigin.originLatitudeDegrees, accuracy: 1e-8)
        XCTAssertEqual(origin.longitudeDegrees, zoneOrigin.originLongitudeDegrees, accuracy: 1e-8)

        let here = PlaneRectangular.inverse(northingMeters: 0, eastingMeters: 0, zone: 9)!
        let user = try XCTUnwrap(DrawingPlacement.user(
            latitudeDegrees: here.latitudeDegrees,
            longitudeDegrees: here.longitudeDegrees,
            horizontalAccuracyMeters: 3,
            zone: 9,
            axis: .cadEastNorth,
            transform: nil
        ))
        XCTAssertEqual(user.point.x, 0, accuracy: 1e-4)
        XCTAssertEqual(user.point.y, 0, accuracy: 1e-4)
        XCTAssertEqual(user.accuracyRadius, 3, accuracy: 1e-9)

        let there = PlaneRectangular.inverse(northingMeters: 0, eastingMeters: 25, zone: 9)!
        let pairs = [
            AlignmentPair(drawingX: 0, drawingY: 0, latitudeDegrees: here.latitudeDegrees, longitudeDegrees: here.longitudeDegrees, kind: .map, label: "A"),
            AlignmentPair(drawingX: 5, drawingY: 0, latitudeDegrees: there.latitudeDegrees, longitudeDegrees: there.longitudeDegrees, kind: .gnss, label: "B")
        ]
        let fit = try XCTUnwrap(AlignmentSolver.fit(pairs: pairs, zone: 9, lockScale: false))
        XCTAssertEqual(fit.transform.scale, 5, accuracy: 0.01)
        XCTAssertEqual(AlignmentAccuracy.decide(pairs.map(\.kind)), .mapGrade)
        XCTAssertEqual(AlignmentAccuracy.mapGrade.notice, AlignmentAccuracy.stakeoutNotice)
        XCTAssertNil(AlignmentAccuracy.decide([.coordinateBook, .coordinateBook]).notice)

        let inspect = DrawingPlacement.inspect(
            point: PlanarPoint(x: 10, y: 0),
            zone: 9,
            axis: .cadEastNorth,
            transform: nil,
            fromLatitude: here.latitudeDegrees,
            fromLongitude: here.longitudeDegrees
        )
        XCTAssertEqual(inspect.eastingMeters ?? 0, 10, accuracy: 1e-6)
        XCTAssertEqual(inspect.northingMeters ?? 0, 0, accuracy: 1e-6)
        XCTAssertEqual(inspect.distanceMeters ?? 0, 10, accuracy: 0.05)
        XCTAssertEqual(inspect.azimuthDegrees ?? 0, 90, accuracy: 0.2)
    }

    func testProjectKeepsOriginalDXFAndVersionsAlignment() throws {
        let root = try TestFiles.directory()
        defer { TestFiles.remove(root) }
        let created = try ProjectStore.create(name: "城南", at: root, now: Date(timeIntervalSince1970: 1_700_000_000))
        let directory = try ProjectStore.projectDirectory(created.name, at: root)
        for folder in ProjectStore.childFolders {
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(folder).path, isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("project.json").path))

        var project = created
        let original = Data([0x00, 0xFF, 0x90, 0x7D, 0x41])
        let stored = try ProjectStore.importDXF(
            data: original,
            fileName: "設計図.dxf",
            into: &project,
            at: root,
            codePage: "ANSI_932",
            unsupported: ["SPLINE": 2]
        )
        XCTAssertEqual(try ProjectStore.originalDXF(fileName: stored, projectName: project.name, at: root), original)
        XCTAssertEqual(project.drawings.first?.unsupported["SPLINE"], 2)

        let record = AlignmentRecord(
            name: "手合わせ",
            version: 0,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            zone: 9,
            axis: .cadEastNorth,
            lockScale: false,
            transform: .identity,
            pairs: [],
            residualsMeters: [0.2, 0.4],
            rmsMeters: 0.3,
            accuracyTag: .mapGrade,
            stakeoutNotice: AlignmentAccuracy.stakeoutNotice,
            drawingFileName: stored
        )
        let first = try ProjectStore.saveAlignment(record, projectName: project.name, at: root)
        let second = try ProjectStore.saveAlignment(record, projectName: project.name, at: root)
        XCTAssertEqual(first.version, 1)
        XCTAssertEqual(second.version, 2)
        XCTAssertEqual(try ProjectStore.alignments(projectName: project.name, at: root).map(\.version), [1, 2])
        XCTAssertEqual(try ProjectStore.originalDXF(fileName: stored, projectName: project.name, at: root), original)

        let note = try ProjectStore.addRecord(date: "2026-10-20", kind: "下見", name: "起点", projectName: project.name, at: root)
        let recordURL = directory
            .appendingPathComponent("記録/\(note.date)_\(note.kind)_\(note.name)/record.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordURL.path))
        XCTAssertEqual(try ProjectStore.list(at: root).map(\.name), ["城南"])
        XCTAssertThrowsError(try ProjectStore.create(name: "城南", at: root)) { error in
            XCTAssertEqual(error as? ProjectStoreError, .alreadyExists)
        }
    }

    private func square(origin: PlanarPoint, size: Double) -> [Segment2D] {
        let a = origin
        let b = PlanarPoint(x: origin.x + size, y: origin.y)
        let c = PlanarPoint(x: origin.x + size, y: origin.y + size)
        let d = PlanarPoint(x: origin.x, y: origin.y + size)
        return [
            Segment2D(start: a, end: b),
            Segment2D(start: b, end: c),
            Segment2D(start: c, end: d),
            Segment2D(start: d, end: a)
        ]
    }

    private func entity(_ match: DrawingPrimitive, in document: DrawingDocument) throws -> DrawingEntity {
        try XCTUnwrap(document.entities.first { $0.primitive == match })
    }

    private func text(_ string: String, in document: DrawingDocument) throws -> String {
        for entity in document.entities {
            if case let .text(_, value, _, _) = entity.primitive, value == string { return value }
        }
        XCTFail("missing \(string)")
        return ""
    }

    private func shiftJISDXF() throws -> Data {
        func ascii(_ text: String) -> Data { Data(text.utf8) }
        let name = try XCTUnwrap("図面".data(using: .shiftJIS))
        let label = try XCTUnwrap("杭".data(using: .shiftJIS))
        let newline = Data([0x0A])
        return ascii("0\nSECTION\n2\nHEADER\n9\n$DWGCODEPAGE\n3\nANSI_932\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n0\nTEXT\n8\n")
            + name + newline
            + ascii("10\n0\n20\n0\n40\n1\n1\n")
            + label + newline
            + ascii("0\nENDSEC\n0\nEOF\n")
    }
}

private let sampleDXF = """
0
SECTION
2
HEADER
9
$DWGCODEPAGE
3
UTF-8
9
$INSUNITS
70
4
0
ENDSEC
0
SECTION
2
TABLES
0
TABLE
2
LAYER
0
LAYER
2
境界
70
0
62
1
0
ENDTAB
0
ENDSEC
0
SECTION
2
BLOCKS
0
BLOCK
2
MARK
10
0
20
0
0
LINE
8
0
10
0
20
0
11
1
21
0
0
ENDBLK
0
ENDSEC
0
SECTION
2
ENTITIES
0
LINE
8
境界
62
5
10
0
20
0
11
10
21
0
0
LWPOLYLINE
8
境界
90
3
70
0
10
0
20
0
42
1
10
2
20
0
10
2
20
2
0
CIRCLE
8
境界
10
5
20
5
40
1.5
420
255
0
ARC
8
境界
10
0
20
0
40
2
50
0
51
90
0
TEXT
8
境界
10
1
20
1
40
0.5
1
基準
50
0
0
MTEXT
8
境界
10
2
20
2
40
0.4
3
あ
1
いう
0
POINT
8
境界
10
3
20
4
0
INSERT
8
境界
2
MARK
10
100
20
200
41
2
50
0
0
SPLINE
8
境界
0
HATCH
8
境界
0
ENDSEC
0
EOF
"""
