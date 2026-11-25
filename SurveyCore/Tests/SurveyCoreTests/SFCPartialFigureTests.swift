import XCTest
@testable import SurveyCore

final class SFCPartialFigureTests: XCTestCase {
    func testLocalPartialFigureStaysInMetersAndMatchesNames() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("drawings_test/7_local_origin_mm_sfig.sfc")
        let survey = try SFCParser.open(Data(contentsOf: url))
        let main = try XCTUnwrap(survey.figures.first { $0.name == "G0" })
        XCTAssertTrue(main.isOn)
        XCTAssertEqual(main.scale, "1/1000")
        XCTAssertGreaterThanOrEqual(survey.document.bounds.minX, -180.01)
        XCTAssertLessThanOrEqual(survey.document.bounds.maxX, 162.01)
        XCTAssertGreaterThanOrEqual(survey.document.bounds.minY, -180.01)
        XCTAssertLessThanOrEqual(survey.document.bounds.maxY, 162.01)
        XCTAssertLessThan(survey.document.bounds.minX, -100)
        XCTAssertGreaterThan(survey.document.bounds.maxX, 100)
        let texts = survey.document.entities.compactMap { entity -> String? in
            if case let .text(_, string, _, _) = entity.primitive { return string }
            return nil
        }
        XCTAssertFalse(texts.contains { $0.contains("拡大") })
        XCTAssertFalse(texts.contains { $0.contains("41080") })
        XCTAssertTrue(texts.contains("T-1"))
        XCTAssertEqual(survey.figures.first { $0.name == "G1" }?.isOn, false)
        XCTAssertEqual(survey.figures.first { $0.name == "G1" }?.scale, "1/200")
        XCTAssertEqual(survey.figures.first { $0.name == "GE" }?.isOn, false)
        XCTAssertTrue(survey.placementNote.contains("位置合わせが必要"))
        XCTAssertFalse(survey.placementNote.contains("公共座標として読みました"))

        XCTAssertEqual(survey.book.count, 4)
        XCTAssertEqual(survey.book.first?.zone, 2)
        let fit = try XCTUnwrap(SFCPointFit.align(document: survey.document, book: survey.book))
        XCTAssertEqual(fit.rmsMeters, 0, accuracy: 1e-6)
        XCTAssertEqual(fit.transform.translationEasting, -40900, accuracy: 1e-4)
        XCTAssertEqual(fit.transform.translationNorthing, 2400, accuracy: 1e-4)
        let csv = try String(contentsOf: url.deletingLastPathComponent().appendingPathComponent("7_local_origin_mm_sfig_points.csv"), encoding: .utf8)
        for line in csv.split(separator: "\n").dropFirst() {
            let columns = line.split(separator: ",").map(String.init)
            let name = columns[0]
            let north = Double(columns[1])!
            let east = Double(columns[2])!
            let marker = try XCTUnwrap(survey.document.entities.compactMap { entity -> PlanarPoint? in
                guard case let .text(origin, string, _, _) = entity.primitive, string == name else { return nil }
                let points = survey.document.entities.compactMap { item -> PlanarPoint? in
                    if case let .point(point) = item.primitive { return point }
                    return nil
                }
                return points.min { origin.distance(to: $0) < origin.distance(to: $1) }
            }.first)
            let placed = fit.transform.apply(marker)
            XCTAssertEqual(placed.x, east, accuracy: 1e-4, name)
            XCTAssertEqual(placed.y, north, accuracy: 1e-4, name)
        }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sfig-place-\(UUID().uuidString)", isDirectory: true)
        let record = SFCPlacementRecord(
            fileName: "7_local_origin_mm_sfig.sfc",
            enabled: survey.figures.filter(\.isOn).map(\.name),
            eastingOrigin: fit.transform.translationEasting,
            northingOrigin: fit.transform.translationNorthing,
            rmsMeters: fit.rmsMeters
        )
        try SFCPlacementStore.save(record, in: folder)
        let loaded = try XCTUnwrap(SFCPlacementStore.load(fileName: record.fileName, in: folder))
        XCTAssertEqual(loaded.enabled, ["G0"])
        XCTAssertEqual(loaded.eastingOrigin ?? 0, -40900, accuracy: 1e-4)
        try? FileManager.default.removeItem(at: folder)
    }
}
