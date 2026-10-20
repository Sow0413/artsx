import XCTest
@testable import SurveyCore

/// 大きい現場の時間。毎回、SURVEY BENCH の行を出す。
final class PerformanceTests: XCTestCase {
    func testSyntheticSiteStaysInsideTheBudgets() throws {
        let data = syntheticDXF(columns: 400, rows: 380)
        print("SYNTH bytes \(data.count)")
        XCTAssertGreaterThanOrEqual(data.count, SurveyBudget.drawingBytes)
        var document = DrawingDocument(
            layers: [],
            entities: [],
            bounds: .empty,
            unsupportedCounts: [:],
            codePage: "",
            unitWarning: nil,
            index: DrawingSpatialIndex(entities: [])
        )
        let parsed = try SurveyBench.measure("合成DXF解析", budget: 120_000) {
            document = try DrawingImport.load(data, fileName: "site.dxf")
        }
        _ = parsed
        let span = max(document.bounds.width, document.bounds.height)
        print("SYNTH entities \(document.entities.count) span \(span)m")
        XCTAssertGreaterThanOrEqual(span, SurveyBudget.siteMeters)
        XCTAssertGreaterThan(document.entities.count, DrawingLOD.maxStrokes)

        let center = PlanarPoint(x: document.bounds.midX, y: document.bounds.midY)
        var snap: DrawingSnapHit?
        let snapMs = SurveyBench.measure("合成スナップ", budget: SurveyBudget.queryMilliseconds) {
            snap = DrawingSnap.nearest(in: document, to: center, tolerance: 2)
        }
        XCTAssertNotNil(snap)
        XCTAssertLessThanOrEqual(snapMs, SurveyBudget.queryMilliseconds)

        let overviewScale = 900 / max(span, 1)
        var overviewStrokes = 0
        let overviewMs = SurveyBench.measure("合成全体フレーム", budget: SurveyBudget.frameMilliseconds) {
            overviewStrokes = DrawingLOD.batch(document: document, view: document.bounds, pointsPerUnit: overviewScale).strokes.count
        }
        print("SYNTH overview strokes \(overviewStrokes)")
        XCTAssertGreaterThan(overviewStrokes, 0)
        XCTAssertLessThanOrEqual(overviewStrokes, DrawingLOD.maxStrokes)
        XCTAssertLessThanOrEqual(overviewMs, SurveyBudget.frameMilliseconds)

        let zoomed = window(around: center, meters: 80)
        let zoomScale = 900 / max(zoomed.width, 1)
        var zoomStrokes = 0
        let zoomMs = SurveyBench.measure("合成拡大フレーム", budget: SurveyBudget.frameMilliseconds) {
            zoomStrokes = DrawingLOD.batch(document: document, view: zoomed, pointsPerUnit: zoomScale).strokes.count
        }
        print("SYNTH zoom strokes \(zoomStrokes)")
        XCTAssertGreaterThan(zoomStrokes, 0)
        XCTAssertLessThanOrEqual(zoomMs, SurveyBudget.frameMilliseconds)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("survey-bench-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try ProjectStore.create(name: "長い現場", at: root)
        let directory = root.appendingPathComponent(project.name, isDirectory: true)
        let entries = book(count: SurveyBudget.bookPoints)
        let inserted = try SurveyBench.measure("座標簿5万点の書込", budget: 120_000) {
            try ProjectStore.saveCoordinates(entries, projectName: project.name, at: root)
        }
        _ = inserted
        let opened = SurveyBench.measure("既存の座標簿を開く", budget: SurveyBudget.operableMilliseconds) {
            XCTAssertEqual(CoordinateBookStore.count(projectDirectory: directory), SurveyBudget.bookPoints)
        }
        XCTAssertLessThanOrEqual(opened, SurveyBudget.operableMilliseconds)

        let selective = CoordinateBookQuery(
            namePrefix: "K0123",
            bounds: GeoBounds(south: 35.00115, west: 139.00295, north: 35.00125, east: 139.00315)
        )
        var matched = 0
        let filtered = SurveyBench.measure("座標簿の絞り込み", budget: SurveyBudget.queryMilliseconds) {
            matched = ProjectStore.filteredCoordinates(
                projectName: project.name,
                at: root,
                query: selective,
                observations: [],
                known: [],
                siteBook: []
            ).count
        }
        XCTAssertEqual(matched, 2)
        XCTAssertLessThanOrEqual(filtered, SurveyBudget.queryMilliseconds)

        var listed = 0
        let screen = SurveyBench.measure("座標簿の一覧", budget: SurveyBudget.queryMilliseconds) {
            let preview = ProjectStore.coordinateBookPreview(
                projectName: project.name,
                at: root,
                query: CoordinateBookQuery(),
                observations: [],
                known: [],
                siteBook: []
            )
            listed = preview.sample.count
            XCTAssertEqual(preview.count, SurveyBudget.bookPoints)
        }
        XCTAssertEqual(listed, 8)
        XCTAssertLessThanOrEqual(screen, SurveyBudget.queryMilliseconds)
    }

    func testCaptainSFCReportsTimes() throws {
        let data = try captainSFC()
        print("CAPTAIN bytes \(data.count)")
        var document = DrawingDocument(
            layers: [],
            entities: [],
            bounds: .empty,
            unsupportedCounts: [:],
            codePage: "",
            unitWarning: nil,
            index: DrawingSpatialIndex(entities: [])
        )
        try SurveyBench.measure("実SFC解析", budget: 120_000) {
            document = try DrawingImport.load(data, fileName: "captain-site.sfc")
        }
        let span = max(document.bounds.width, document.bounds.height)
        print("CAPTAIN entities \(document.entities.count) span \(span)")
        XCTAssertFalse(document.entities.isEmpty)
        XCTAssertFalse(document.bounds.isEmpty)

        let center = PlanarPoint(x: document.bounds.midX, y: document.bounds.midY)
        let tolerance = max(2, span * 0.002)
        let snapMs = SurveyBench.measure("実SFCスナップ", budget: SurveyBudget.queryMilliseconds) {
            _ = DrawingSnap.nearest(in: document, to: center, tolerance: tolerance)
        }
        XCTAssertLessThanOrEqual(snapMs, SurveyBudget.queryMilliseconds)

        let overviewScale = 900 / max(span, 1)
        let overviewMs = SurveyBench.measure("実SFC全体フレーム", budget: SurveyBudget.frameMilliseconds) {
            _ = DrawingLOD.batch(document: document, view: document.bounds, pointsPerUnit: overviewScale)
        }
        XCTAssertLessThanOrEqual(overviewMs, SurveyBudget.frameMilliseconds)

        let zoomed = window(around: center, meters: min(80, max(span * 0.25, 1)))
        let zoomScale = 900 / max(zoomed.width, 1)
        let zoomMs = SurveyBench.measure("実SFC拡大フレーム", budget: SurveyBudget.frameMilliseconds) {
            _ = DrawingLOD.batch(document: document, view: zoomed, pointsPerUnit: zoomScale)
        }
        XCTAssertLessThanOrEqual(zoomMs, SurveyBudget.frameMilliseconds)
    }

    private func window(around center: PlanarPoint, meters: Double) -> DrawingBounds {
        let half = meters / 2
        return DrawingBounds(minX: center.x - half, minY: center.y - half, maxX: center.x + half, maxY: center.y + half)
    }

    private func syntheticDXF(columns: Int, rows: Int) -> Data {
        var data = Data()
        data.reserveCapacity(9_500_000)
        func add(_ line: String) {
            data.append(contentsOf: line.utf8)
            data.append(10)
        }
        add("0")
        add("SECTION")
        add("2")
        add("ENTITIES")
        for row in 0..<rows {
            let y = Double(row) * 1.6
            for column in 0..<columns {
                let x = Double(column) * 3
                add("0")
                add("LINE")
                add("8")
                add("0")
                add("10")
                add(String(format: "%.3f", x))
                add("20")
                add(String(format: "%.3f", y))
                add("11")
                add(String(format: "%.3f", x + 2.5))
                add("21")
                add(String(format: "%.3f", y + 0.4))
            }
        }
        add("0")
        add("ENDSEC")
        add("0")
        add("EOF")
        return data
    }

    private func book(count: Int) -> [CoordinateBookEntry] {
        let recorded = Date(timeIntervalSince1970: 1_760_000_000)
        return (0..<count).map { index in
            CoordinateBookEntry(
                name: String(format: "K%05d", index),
                latitudeDegrees: 35 + Double(index / 100) * 0.0001,
                longitudeDegrees: 139 + Double(index % 100) * 0.0001,
                ellipsoidalHeightMeters: 40,
                horizontalAccuracyMeters: 0.02,
                verticalAccuracyMeters: 0.03,
                satelliteCount: 12,
                fixDurationSeconds: 1,
                recordedAt: recorded,
                kind: "測点",
                source: "観測",
                stage: .rtk,
                solution: .rtkFix
            )
        }
    }

    private func captainSFC() throws -> Data {
        let beside = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/captain-site.sfc")
        if let data = try? Data(contentsOf: beside), !data.isEmpty { return data }
        let upload = URL(fileURLWithPath: "/home/ubuntu/.cursor/projects/workspace/uploads/ec487e3498fffba09f465c5596c63f3daa23862b25e96390a3dd775e71039ce6_c6f1.sfc")
        if let data = try? Data(contentsOf: upload), !data.isEmpty { return data }
        throw XCTSkip("captain の SFC が無い")
    }
}
