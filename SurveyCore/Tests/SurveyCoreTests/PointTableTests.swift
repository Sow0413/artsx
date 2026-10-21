import XCTest
@testable import SurveyCore

final class PointTableTests: XCTestCase {
    func testCommaHeaderReadsDecimalAndKeepsABadRow() throws {
        let text = """
        点名,緯度,経度,標高
        A,35.0,139.0,10.5
        B,ここ,139.1
        C,35.2,139.2,11
        """
        let table = try read(text, zone: 9)
        XCTAssertEqual(table.encodingName, "UTF-8")
        XCTAssertEqual(table.delimiter, .comma)
        XCTAssertTrue(table.hasHeader)
        XCTAssertEqual(table.roles.prefix(4), [.name, .latitude, .longitude, .height])
        XCTAssertEqual(table.kind, .geographic)
        XCTAssertNil(table.axisWarning)
        let outcome = PointTableReader.assess(table, zone: 9)
        XCTAssertEqual(outcome.points.map(\.name), ["A", "C"])
        XCTAssertEqual(outcome.points[0].latitudeDegrees, 35, accuracy: 1e-9)
        XCTAssertEqual(outcome.points[0].longitudeDegrees, 139, accuracy: 1e-9)
        XCTAssertEqual(outcome.points[0].heightMeters ?? 0, 10.5, accuracy: 1e-9)
        XCTAssertEqual(outcome.points[0].groundLevelMeters ?? 0, 10.5, accuracy: 1e-9)
        XCTAssertEqual(outcome.points[0].origin, .list)
        XCTAssertEqual(outcome.points[0].anchor, .geographic)
        XCTAssertEqual(outcome.issues.count, 1)
        XCTAssertEqual(outcome.issues[0].row, 2)
        XCTAssertTrue(outcome.issues[0].message.contains("緯度"))
    }

    func testTabSpaceAndDMS() throws {
        let tabbed = "name\tlat\tlon\tGL\tFH\nC\t35.1\t137.1\t8.0\t9.25\n"
        let tab = try read(tabbed, zone: 7)
        XCTAssertEqual(tab.delimiter, .tab)
        XCTAssertEqual(tab.roles, [.name, .latitude, .longitude, .ground, .formation])
        let point = try XCTUnwrap(PointTableReader.assess(tab, zone: 7).points.first)
        XCTAssertEqual(point.groundLevelMeters ?? 0, 8, accuracy: 1e-9)
        XCTAssertEqual(point.formationHeightMeters ?? 0, 9.25, accuracy: 1e-9)

        let spaced = "A 35.0 139.2 10\nB 35.1 139.3 11\n"
        let space = try read(spaced, zone: 9)
        XCTAssertEqual(space.delimiter, .space)
        XCTAssertFalse(space.hasHeader)
        XCTAssertEqual(PointTableReader.assess(space, zone: 9).points.map(\.name), ["A", "B"])

        let dms = "B,35°40'52.4\"N,139°46'01.2\"E\n"
        let angled = try XCTUnwrap(PointTableReader.assess(try read(dms, zone: 9), zone: 9).points.first)
        XCTAssertEqual(angled.latitudeDegrees, 35 + 40.0 / 60 + 52.4 / 3600, accuracy: 1e-6)
        XCTAssertEqual(angled.longitudeDegrees, 139 + 46.0 / 60 + 1.2 / 3600, accuracy: 1e-6)
    }

    func testPlaneXYUsesNorthingAsXAndWarnsWhenSwapped() throws {
        let text = """
        点名,X,Y,標高
        P1,-123868.15,39019.37,50.2
        """
        let table = try read(text, zone: 6)
        XCTAssertEqual(table.kind, .plane)
        XCTAssertEqual(table.roles.prefix(4), [.name, .northing, .easting, .height])
        XCTAssertNil(table.axisWarning)
        let point = try XCTUnwrap(PointTableReader.assess(table, zone: 6).points.first)
        XCTAssertEqual(point.anchor, .grid)
        XCTAssertEqual(point.northingMeters, -123868.15, accuracy: 0.01)
        XCTAssertEqual(point.eastingMeters, 39019.37, accuracy: 0.01)
        XCTAssertEqual(point.latitudeDegrees, 34.8827, accuracy: 0.01)
        XCTAssertEqual(point.longitudeDegrees, 136.4269, accuracy: 0.01)
        XCTAssertEqual(FieldIntake.detect(data: Data(text.utf8), fileName: "plane.csv"), .list)

        let swapped = """
        点名,X,Y
        P1,39019.37,-123868.15
        """
        let wrong = try read(swapped, zone: 6)
        XCTAssertEqual(wrong.roles[1], .northing)
        XCTAssertEqual(wrong.roles[2], .easting)
        XCTAssertEqual(wrong.axisWarning, PointTableReader.axisWarningText)
        let kept = try XCTUnwrap(PointTableReader.assess(wrong, zone: 6).points.first)
        XCTAssertEqual(kept.northingMeters, 39019.37, accuracy: 0.01)
        XCTAssertEqual(kept.eastingMeters, -123868.15, accuracy: 0.01)
    }

    func testShiftJISHeaderAndRememberedRoles() throws {
        let bytes: [UInt8] = [
            147, 95, 150, 188, 44, 136, 220, 147, 120, 44, 140, 111, 147, 120, 44, 149, 87, 141, 130, 10,
            65, 44, 51, 53, 46, 48, 44, 49, 51, 57, 46, 50, 44, 49, 48, 46, 53, 10
        ]
        let table = try XCTUnwrap(PointTableReader.read(data: Data(bytes), fileName: "sjis.csv"))
        XCTAssertEqual(table.encodingName, "Shift_JIS")
        XCTAssertEqual(table.roles.prefix(4), [.name, .latitude, .longitude, .height])
        let evaluated = PointTableReader.evaluate(table, zone: 9)
        let point = try XCTUnwrap(PointTableReader.assess(evaluated, zone: 9).points.first)
        XCTAssertEqual(point.name, "A")
        XCTAssertEqual(point.latitudeDegrees, 35, accuracy: 1e-9)
        XCTAssertEqual(point.heightMeters ?? 0, 10.5, accuracy: 1e-9)
        XCTAssertEqual(FieldIntake.detect(data: Data(bytes), fileName: "sjis.csv"), .list)

        var remembered = try read("memo,35.0,139.2,K1\n", zone: 9)
        remembered.roles = [.note, .latitude, .longitude, .name]
        remembered.hasHeader = false
        let mapped = PointTableReader.evaluate(remembered, zone: 9)
        let named = try XCTUnwrap(PointTableReader.assess(mapped, zone: 9).points.first)
        XCTAssertEqual(named.name, "K1")
        XCTAssertEqual(named.snapLabel, "memo")
        XCTAssertEqual(named.latitudeDegrees, 35, accuracy: 1e-9)
    }

    func testRepairsOCRTrapsWithoutTouchingNames() {
        XCTAssertEqual(PointTextRepair.number("1O.5") ?? 0, 10.5, accuracy: 1e-9)
        XCTAssertEqual(PointTextRepair.number("l23") ?? 0, 123, accuracy: 1e-9)
        XCTAssertEqual(PointTextRepair.number("36,77450") ?? 0, 36.77450, accuracy: 1e-9)
        XCTAssertEqual(PointTextRepair.number("−123868.15") ?? 0, -123868.15, accuracy: 1e-9)
        XCTAssertEqual(PointTextRepair.number("1,234.5") ?? 0, 1234.5, accuracy: 1e-9)
        XCTAssertEqual(PointTextRepair.number("３５．０") ?? 0, 35, accuracy: 1e-9)
        XCTAssertEqual(PointTextRepair.repair("K-1"), "K-1")
        XCTAssertEqual(PointTextRepair.repair("NO1"), "NO1")
    }

    func testPaperBoxesBecomeEditableCells() throws {
        let boxes = [
            PaperTextBox(text: "A", confidence: 0.95, minX: 0.1, maxX: 0.2, midY: 0.8, height: 0.03),
            PaperTextBox(text: "35.O", confidence: 0.4, minX: 0.3, maxX: 0.45, midY: 0.8, height: 0.03),
            PaperTextBox(text: "139.2", confidence: 0.9, minX: 0.5, maxX: 0.7, midY: 0.81, height: 0.03),
            PaperTextBox(text: "B,35.1,139.3", confidence: 0.5, minX: 0.1, maxX: 0.7, midY: 0.6, height: 0.03)
        ]
        let cells = PointTableReader.cells(from: boxes)
        XCTAssertEqual(cells.count, 2)
        XCTAssertEqual(cells[0].map(\.text), ["A", "35.0", "139.2"])
        XCTAssertTrue(cells[0][1].isLowConfidence)
        XCTAssertFalse(cells[0][0].isLowConfidence)
        XCTAssertEqual(cells[1].map(\.text), ["B", "35.1", "139.3"])
        let table = try XCTUnwrap(PointTableReader.table(from: cells, fileName: "用紙"))
        XCTAssertEqual(table.encodingName, "用紙")
        let points = PointTableReader.assess(table, zone: 9).points
        XCTAssertEqual(points.map(\.name), ["A", "B"])
        XCTAssertEqual(points[0].latitudeDegrees, 35, accuracy: 1e-9)
    }

    func testQuotedCommaAndTwoHeightsStayVisible() throws {
        let quoted = "\"A,1\",35.0,139.0\n"
        let named = try XCTUnwrap(PointTableReader.assess(try read(quoted, zone: 9), zone: 9).points.first)
        XCTAssertEqual(named.name, "A,1")

        let heights = "A,35.0,139.0,10.5,12.3\n"
        let table = try read(heights, zone: 9)
        XCTAssertEqual(table.roles.suffix(2), [.ground, .formation])
        let point = try XCTUnwrap(PointTableReader.assess(table, zone: 9).points.first)
        XCTAssertEqual(point.groundLevelMeters ?? 0, 10.5, accuracy: 1e-9)
        XCTAssertEqual(point.formationHeightMeters ?? 0, 12.3, accuracy: 1e-9)
        XCTAssertEqual(point.name, "A")
    }

    func testPointNameSequenceAndProjectMap() throws {
        XCTAssertEqual(PointNameSequence.next(after: ""), "1")
        XCTAssertEqual(PointNameSequence.next(after: "K-1"), "K-2")
        XCTAssertEqual(PointNameSequence.next(after: "009"), "010")
        XCTAssertEqual(PointNameSequence.next(after: "BP"), "BP2")

        let map = PointColumnMap(roles: [.name, .latitude, .longitude], hasHeader: true)
        var project = SurveyProject(id: "p", name: "現場", createdAt: Date(timeIntervalSince1970: 0), zone: 9, pointColumnMap: map)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        project = try decoder.decode(SurveyProject.self, from: data)
        XCTAssertEqual(project.pointColumnMap, map)

        let old = """
        {"axis":"cadEastNorth","createdAt":"2026-10-20T00:00:00Z","drawings":[],"id":"p","name":"現場","zone":9}
        """.data(using: .utf8)!
        let legacy = try decoder.decode(SurveyProject.self, from: old)
        XCTAssertNil(legacy.pointColumnMap)
        XCTAssertEqual(legacy.zone, 9)
    }

    private func read(_ text: String, zone: Int) throws -> PointTable {
        let table = try XCTUnwrap(PointTableReader.read(text: text, encodingName: "UTF-8", fileName: "p.csv"))
        return PointTableReader.evaluate(table, zone: zone)
    }
}
