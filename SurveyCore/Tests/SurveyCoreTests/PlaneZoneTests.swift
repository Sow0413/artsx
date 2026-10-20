import XCTest
@testable import SurveyCore

final class PlaneZoneTests: XCTestCase {
    func testSinglePrefectureDecidesItsZone() {
        XCTAssertEqual(PlaneZoneCatalog.zones(forPrefecture: "神奈川"), [9])
        XCTAssertEqual(PlaneZoneCatalog.named("東京")?.zones, [9, 14, 18, 19])
        XCTAssertEqual(PlaneZoneCatalog.named("北海道")?.zones, [11, 12, 13])
        XCTAssertEqual(PlaneZoneCatalog.named("鹿児島県")?.zones, [1, 2])
        XCTAssertEqual(PlaneZoneCatalog.named("沖縄")?.zones, [15, 16, 17])
        XCTAssertEqual(PlaneZoneCatalog.prefectures.count, 47)
        XCTAssertTrue(PlaneZoneCatalog.named("茨城県")?.decidesZone == true)
        XCTAssertTrue(PlaneZoneCatalog.named("北海道")?.decidesZone == false)
    }

    func testIbarakiPicksZoneNineForThePublishedExample() throws {
        let latitude = 36 + 6.0 / 60 + 13.58925 / 3600
        let longitude = 140 + 5.0 / 60 + 16.27815 / 3600
        let plane = PlaneRectangular.forward(latitudeDegrees: latitude, longitudeDegrees: longitude, zone: 9)
        let east = try XCTUnwrap(plane).eastingMeters
        let north = try XCTUnwrap(plane).northingMeters
        let placement = PlanePlacementChooser.choose(
            x: east,
            y: north,
            prefecture: "茨城県",
            latitude: nil,
            longitude: nil
        )
        XCTAssertEqual(placement.decidedZone, 9)
        XCTAssertEqual(placement.zones, [9])
        XCTAssertTrue(placement.landings.contains { $0.zone == 9 && $0.axis == .cadEastNorth })
        XCTAssertTrue(placement.note.contains("茨城県"))
    }

    func testCurrentLocationNarrowsABorder() {
        let zones = PlaneZoneCatalog.zones(nearLatitude: 35.681236, longitude: 139.767125)
        XCTAssertTrue(zones.contains(9))
        XCTAssertFalse(zones.contains(1))
    }

    func testOldProjectJSONWithoutPrefectureStillLoads() throws {
        let json = """
        {"axis":"cadEastNorth","createdAt":"2026-10-20T00:00:00Z","drawings":[],"id":"p","name":"現場","zone":9}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(SurveyProject.self, from: json)
        XCTAssertNil(project.prefecture)
        XCTAssertEqual(project.zone, 9)
    }
}

final class SFCFeatureModeTests: XCTestCase {
    func testScadecFragmentScalesMillimetersAndKeepsEscapes() throws {
        let document = try SFCParser.parse(Data(scadecFragment.utf8))
        XCTAssertTrue(document.codePage.contains("Ver3"))
        XCTAssertEqual(document.layers.map(\.name), ["道路縁", "等高線"])
        XCTAssertEqual(document.layers.map(\.role), [.background, .background])
        XCTAssertEqual(document.entities.count, 3)
        XCTAssertEqual(document.unsupportedCounts["drawing_sheet_feature"], 1)
        XCTAssertEqual(document.unsupportedCounts["sfig_org_feature"], 1)
        XCTAssertNil(document.unsupportedCounts["text_string_feature"])
        XCTAssertTrue(document.unitWarning?.contains("ミリメートル") == true)

        guard case let .polyline(vertices, _, _) = document.entities[0].primitive else {
            return XCTFail("折線がない")
        }
        XCTAssertEqual(vertices[0].x, 38000, accuracy: 1e-6)
        XCTAssertEqual(vertices[0].y, -123700, accuracy: 1e-6)
        XCTAssertEqual(try label("120", in: document), "120")
        XCTAssertTrue(document.entities.contains { entity in
            if case let .point(point) = entity.primitive {
                return abs(point.x - 38005) < 1e-6 && abs(point.y + 123705) < 1e-6
            }
            return false
        })

        let placement = PlanePlacementChooser.choose(
            x: document.bounds.midX,
            y: document.bounds.midY,
            prefecture: nil,
            latitude: nil,
            longitude: nil
        )
        XCTAssertFalse(placement.landings.isEmpty)
        let narrowed = PlanePlacementChooser.choose(
            x: document.bounds.midX,
            y: document.bounds.midY,
            prefecture: "神奈川県",
            latitude: nil,
            longitude: nil
        )
        XCTAssertEqual(narrowed.decidedZone, 9)
        XCTAssertEqual(narrowed.zones, [9])
    }

    private func label(_ text: String, in document: DrawingDocument) throws -> String {
        for entity in document.entities {
            if case let .text(_, string, _, _) = entity.primitive, string == text { return string }
        }
        throw XCTSkip("文字 \(text) が無い")
    }
}

private let scadecFragment = """
ISO-10303-21;
HEADER;
FILE_DESCRIPTION(('SCADEC level2 feature_mode'),'2;1');
FILE_NAME('\\X2\\57FA76E4573056F330D730ED30B830A730AF30C8\\X0\\sample.sfc','2024-9-13T20:51:31',(''),(''),'SCADEC_API_Ver3.20','','');
FILE_SCHEMA(('ASSOCIATIVE_DRAUGHTING'));
ENDSEC;
DATA;
/*SXF
#10=polyline_feature('1','17','1','11','3','(38000000,38010000,38020000)','(-123700000,-123710000,-123720000)');
#20=text_string_feature('2','1','1',\\'120\\','38010000','-123710000','11900','12000','0','0','0','7','1');
#30=point_marker_feature('2','1','38005000','-123705000','1','0','1');
#40=drawing_sheet_feature(\\'基盤地図\\','9','1','924','538');
#50=layer_feature(\\'道路縁\\','1');
#60=layer_feature('等高線','1');
#70=sfig_org_feature(\\'$$SXF_FG_PCM\\','2');
SXF*/
ENDSEC;
END-ISO-10303-21;
"""
