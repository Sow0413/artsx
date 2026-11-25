import XCTest
@testable import SurveyCore

final class DrawingConditionTests: XCTestCase {
    func testVersionsCodePagesNewlinesAndBinary() throws {
        let r12 = try DXFParser.parse(Data(dxf(version: "AC1009", units: 6, body: "0\nLINE\n8\nROAD\n10\n0\n20\n0\n11\n1\n21\n0\n").utf8))
        XCTAssertEqual(r12.entities.count, 1)
        XCTAssertNil(DrawingReadiness.notice(r12))

        let modern = try DXFParser.parse(Data(dxf(version: "AC1032", units: 6, body: "0\nLINE\n8\n道路\n10\n0\n20\n0\n11\n1\n21\n0\n").utf8))
        XCTAssertEqual(modern.layers.map(\.name), ["道路"])

        let name = try XCTUnwrap("基準".data(using: .shiftJIS))
        let header = Data("0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1009\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n".utf8)
        let decoded = try DXFParser.parse(header + Data("0\nLINE\n8\n".utf8) + name + Data("\n10\n0\n20\n0\n11\n2\n21\n0\n0\nENDSEC\n0\nEOF\n".utf8))
        XCTAssertEqual(decoded.layers.first?.name, "基準")

        var bom = Data([0xEF, 0xBB, 0xBF])
        bom.append(Data(dxf(version: "AC1032", units: 6, body: "0\nTEXT\n8\n注記\n10\n1\n20\n1\n40\n1\n1\n伊良部\n").utf8))
        let bommed = try DXFParser.parse(bom)
        XCTAssertEqual(bommed.codePage, "UTF-8")
        XCTAssertTrue(strings(bommed).contains("伊良部"))

        let lf = try DXFParser.parse(Data(dxf(version: "AC1021", units: 6, body: "0\nLINE\n8\n線\n10\n1\n20\n2\n11\n3\n21\n4\n").utf8))
        XCTAssertEqual(lf.entities.count, 1)

        XCTAssertThrowsError(try DXFParser.parse(Data("AutoCAD Binary DXF\r\n".utf8) + Data([0x01, 0x02]))) { error in
            XCTAssertEqual(error as? DXFError, .binary)
            XCTAssertTrue(((error as? DXFError)?.description ?? "").contains("バイナリ"))
        }
    }

    func testBulgeInsertMtextUnitsZoneSwapEmptyAndOrigin() throws {
        let bulge = try DXFParser.parse(Data(dxf(
            version: "AC1021",
            units: 6,
            body: "0\nLWPOLYLINE\n8\n弧\n90\n2\n70\n0\n10\n0\n20\n0\n42\n1\n10\n10\n20\n0\n"
        ).utf8))
        guard case let .polyline(_, _, display) = bulge.entities.first?.primitive else {
            return XCTFail("バルジを読めない")
        }
        XCTAssertTrue(display.contains { abs($0.y) > 1 })

        let inserted = try DXFParser.parse(Data(blockDXF().utf8))
        guard case let .line(start, end) = inserted.entities.first?.primitive else {
            return XCTFail("INSERT を読めない")
        }
        XCTAssertEqual(start.distance(to: PlanarPoint(x: 10, y: 20)), 0, accuracy: 1e-6)
        XCTAssertEqual(end.distance(to: PlanarPoint(x: 10, y: 22)), 0, accuracy: 1e-6)

        let text = try DXFParser.parse(Data(dxf(
            version: "AC1021",
            units: 6,
            body: "0\nMTEXT\n8\n注記\n10\n0\n20\n0\n40\n2\n3\n図面\n1\n\\P基準点\n"
        ).utf8))
        XCTAssertTrue(strings(text).contains("図面\n基準点"))

        let mm = try DXFParser.parse(Data(dxf(version: "AC1015", units: 4, body: "0\nLINE\n8\n0\n10\n0\n20\n0\n11\n1000\n21\n0\n").utf8))
        XCTAssertEqual(mm.unitCode, 4)
        XCTAssertEqual(mm.metersPerUnit, 0.001)
        XCTAssertTrue(mm.unitWarning?.contains("ミリ") == true)
        let meters = try DXFParser.parse(Data(dxf(version: "AC1015", units: 6, body: "0\nLINE\n8\n0\n10\n0\n20\n0\n11\n1\n21\n0\n").utf8))
        XCTAssertNil(meters.unitWarning)
        XCTAssertEqual(meters.metersPerUnit, 1)

        let tokyo = try XCTUnwrap(PlaneRectangular.forward(latitudeDegrees: 35.681236, longitudeDegrees: 139.767125, zone: 9))
        let wrong = ZoneAdvisor.placement(
            drawingX: tokyo.eastingMeters,
            drawingY: tokyo.northingMeters,
            zone: 1,
            axis: .cadEastNorth,
            referenceLatitude: 35.681236,
            referenceLongitude: 139.767125,
            referenceName: "現在地"
        )
        XCTAssertNotNil(wrong.message)
        XCTAssertTrue(wrong.message?.contains("1系") == true)

        let swapped = ZoneAdvisor.placement(
            drawingX: tokyo.northingMeters,
            drawingY: tokyo.eastingMeters,
            zone: 9,
            axis: .cadEastNorth,
            referenceLatitude: 35.681236,
            referenceLongitude: 139.767125,
            referenceName: "現在地"
        )
        XCTAssertNotNil(swapped.message)
        XCTAssertTrue(swapped.message?.contains("X が北") == true)

        XCTAssertThrowsError(try DXFParser.parse(Data())) { error in
            XCTAssertEqual(error as? DXFError, .notDXF)
            XCTAssertTrue(((error as? DXFError)?.description ?? "").contains("形になっていません"))
        }

        let origin = try DXFParser.parse(Data(dxf(version: "AC1021", units: 6, body: "0\nLINE\n8\n0\n10\n0\n20\n0\n11\n0\n21\n0\n").utf8))
        XCTAssertEqual(DrawingReadiness.notice(origin), "座標がすべて原点です。位置を決められません。")
    }

    private func strings(_ document: DrawingDocument) -> [String] {
        document.entities.compactMap { entity in
            if case let .text(_, string, _, _) = entity.primitive { return string }
            return nil
        }
    }

    private func dxf(version: String, units: Int, body: String) -> String {
        """
        0
        SECTION
        2
        HEADER
        9
        $ACADVER
        1
        \(version)
        9
        $INSUNITS
        70
        \(units)
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        \(body)0
        ENDSEC
        0
        EOF

        """
    }

    private func blockDXF() -> String {
        """
        0
        SECTION
        2
        HEADER
        9
        $ACADVER
        1
        AC1021
        9
        $INSUNITS
        70
        6
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
        INSERT
        8
        0
        2
        MARK
        10
        10
        20
        20
        41
        2
        42
        2
        50
        90
        0
        ENDSEC
        0
        EOF

        """
    }
}
