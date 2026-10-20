import XCTest
@testable import SurveyCore

final class OperatorStationTests: XCTestCase {
    func testStationAndLeftOffsetUseTwentyMeterPoints() {
        let line = [PlanarPoint(x: 0, y: 0), PlanarPoint(x: 500, y: 0)]
        let guide = OperatorStation.guide(point: PlanarPoint(x: 465, y: 3), alignment: line)
        XCTAssertEqual(guide?.line, "No.23+5.0m 左 3.0m")
        XCTAssertEqual(guide?.alongMeters ?? 0, 465, accuracy: 1e-6)
        XCTAssertEqual(guide?.offsetMeters ?? 0, 3, accuracy: 1e-6)
        XCTAssertEqual(guide?.forwardAzimuthDegrees ?? -1, 90, accuracy: 1e-6)
    }

    func testRightOffsetAndEndsOfTheLine() {
        let line = [PlanarPoint(x: 0, y: 0), PlanarPoint(x: 100, y: 0)]
        XCTAssertEqual(
            OperatorStation.guide(point: PlanarPoint(x: 40, y: -2.6), alignment: line)?.line,
            "No.2+0.0m 右 2.6m"
        )
        XCTAssertEqual(
            OperatorStation.guide(point: PlanarPoint(x: -12, y: 0.2), alignment: line)?.line,
            "起点の手前 12.0m 左 0.2m"
        )
        XCTAssertEqual(
            OperatorStation.guide(point: PlanarPoint(x: 108, y: -0.4), alignment: line)?.line,
            "終点の先 8.0m 右 0.4m"
        )
    }

    func testArrowUsesTravelDirectionThenCompass() {
        let moving = OperatorStation.arrow(courseDegrees: 90, headingDegrees: 0, centerlineAzimuth: 90)
        XCTAssertEqual(moving?.source, "進行")
        XCTAssertEqual(moving?.relativeDegrees ?? 9, 0, accuracy: 1e-9)

        let turned = OperatorStation.arrow(courseDegrees: nil, headingDegrees: 0, centerlineAzimuth: 90)
        XCTAssertEqual(turned?.source, "方位")
        XCTAssertEqual(turned?.relativeDegrees ?? 0, -90, accuracy: 1e-9)

        let wrapped = OperatorStation.relative(device: 10, centerline: 350)
        XCTAssertEqual(wrapped, 20, accuracy: 1e-9)
        XCTAssertNil(OperatorStation.arrow(courseDegrees: nil, headingDegrees: nil, centerlineAzimuth: 0))
    }

    func testDropUsesTenthsAndKeepsThePhoneReading() {
        let phone = OperatorStation.height(ellipsoidalMeters: 25.84, designMeters: 25)
        XCTAssertEqual(phone.text, "下がり 0.8m")
        XCTAssertEqual(phone.note, "参考")
        XCTAssertTrue(phone.isReference)
        XCTAssertEqual(phone.meters ?? 0, 0.8, accuracy: 1e-9)

        let absolute = OperatorStation.height(ellipsoidalMeters: 24.14, designMeters: nil)
        XCTAssertEqual(absolute.text, "24.1m")
        XCTAssertEqual(absolute.note, "参考")

        let above = OperatorStation.height(ellipsoidalMeters: 24.14, designMeters: 25)
        XCTAssertEqual(above.text, "上がり 0.9m")

        let onDatum = OperatorStation.height(
            ellipsoidalMeters: 23.2,
            designMeters: 25,
            eyeHeightMeters: 2,
            phoneAtEyes: false
        )
        XCTAssertEqual(onDatum.text, "下がり 0.2m")

        let level = OperatorStation.height(ellipsoidalMeters: 25, designMeters: 25)
        XCTAssertEqual(level.text, "下がり 0.0m")

        let eyeLevel = OperatorStation.height(ellipsoidalMeters: 25.84, designMeters: 25, sightDropMeters: 0)
        XCTAssertEqual(eyeLevel.text, "下がり 0.8m")
        let tilted = OperatorStation.height(ellipsoidalMeters: 25.84, designMeters: 25, sightDropMeters: 0.175)
        XCTAssertEqual(tilted.text, "下がり 1.0m")
        let ignored = OperatorStation.height(
            ellipsoidalMeters: 23.2,
            designMeters: 25,
            eyeHeightMeters: 2,
            phoneAtEyes: false,
            sightDropMeters: 0.175
        )
        XCTAssertEqual(ignored.text, "下がり 0.2m")

        let missing = OperatorStation.height(ellipsoidalMeters: nil, designMeters: 25)
        XCTAssertEqual(missing.text, "—")
        XCTAssertFalse(missing.isReference)
    }

    func testOldPositionJSONOmitsCourseAndHeading() throws {
        let json = """
        {"ellipsoidalHeightMeters":1,"fixQuality":"standalone","frame":"WGS84/ITRF","horizontalAccuracyMeters":3,"latitudeDegrees":35,"longitudeDegrees":139,"receiver":"iphoneGPS","stage":0,"timestamp":0,"verticalAccuracyMeters":5}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let position = try decoder.decode(GeodeticPosition.self, from: json)
        XCTAssertNil(position.courseDegrees)
        XCTAssertNil(position.headingDegrees)
        XCTAssertEqual(position.latitudeDegrees, 35)
    }
}

final class MachineReachTests: XCTestCase {
    func testOutsideInsideAndOnTheRadiusUseTenths() {
        let outside = MachineReach.call(distanceMeters: 12.3, radiusMeters: 9)
        XCTAssertEqual(outside?.text, "目標まで 12.3m（半径外 3.3m）")
        XCTAssertEqual(outside?.coverage, .outside)
        XCTAssertEqual(outside?.gapMeters ?? 0, 3.3, accuracy: 1e-9)

        let inside = MachineReach.call(distanceMeters: 6, radiusMeters: 9)
        XCTAssertEqual(inside?.text, "目標まで 6.0m（半径内 3.0m）")
        XCTAssertEqual(inside?.coverage, .inside)

        let edge = MachineReach.call(distanceMeters: 9.04, radiusMeters: 9)
        XCTAssertEqual(edge?.text, "目標まで 9.0m（半径上）")
        XCTAssertEqual(edge?.coverage, .onRadius)

        XCTAssertEqual(MachineCatalog.named("20t")?.radiusMeters, 9)
        XCTAssertEqual(MachineCatalog.presets.count, 7)
    }

    func testExcavationCoverageUsesTheCircle() {
        let center = PlanarPoint(x: 0, y: 0)
        let inside = MachineReach.coverage(
            of: [PlanarPoint(x: 1, y: 1), PlanarPoint(x: 2, y: 1), PlanarPoint(x: 2, y: 2), PlanarPoint(x: 1, y: 1)],
            closed: false,
            center: center,
            radius: 9
        )
        XCTAssertEqual(inside, .inside)

        let crossing = MachineReach.coverage(
            of: [PlanarPoint(x: 0, y: 0), PlanarPoint(x: 20, y: 0)],
            closed: false,
            center: center,
            radius: 9
        )
        XCTAssertEqual(crossing, .partial)

        let beyond = MachineReach.coverage(
            of: [PlanarPoint(x: 12, y: 0), PlanarPoint(x: 20, y: 4)],
            closed: false,
            center: center,
            radius: 9
        )
        XCTAssertEqual(beyond, .outside)
        XCTAssertEqual(MachineReach.worst([.inside, .partial, .outside]), .outside)
    }

    func testProjectJSONKeepsTheRadiusAndLoadsOlderFiles() throws {
        let older = """
        {"axis":"cadEastNorth","createdAt":"2026-10-20T00:00:00Z","drawings":[],"id":"p","name":"現場","zone":9}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode(SurveyProject.self, from: older)
        XCTAssertNil(loaded.machineRadiusMeters)
        XCTAssertNil(loaded.machinePreset)
        XCTAssertNil(loaded.eyeHeightMeters)
        XCTAssertNil(loaded.phoneAtEyes)

        var project = loaded
        project.machinePreset = "20t"
        project.machineRadiusMeters = 9
        project.eyeHeightMeters = 2
        project.sightDatum = .ground
        project.phoneAtEyes = true
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)
        let saved = try decoder.decode(SurveyProject.self, from: data)
        XCTAssertEqual(saved.machinePreset, "20t")
        XCTAssertEqual(saved.machineRadiusMeters, 9)
        XCTAssertEqual(saved.eyeHeightMeters, 2)
        XCTAssertEqual(saved.sightDatum, .ground)
        XCTAssertEqual(saved.phoneAtEyes, true)
        XCTAssertEqual(saved.prefecture, loaded.prefecture)
    }
}

final class StationLineTests: XCTestCase {
    func testTenthsAndAShiftedOrigin() {
        let line = [PlanarPoint(x: 0, y: 0), PlanarPoint(x: 1000, y: 0)]
        let here = OperatorStation.guide(point: PlanarPoint(x: 465, y: 3.2), alignment: line)
        XCTAssertEqual(here?.line, "No.23+5.0m 左 3.2m")

        let shifted = OperatorStation.guide(
            point: PlanarPoint(x: 5, y: -1.24),
            alignment: line,
            interval: 20,
            originStation: 10
        )
        XCTAssertEqual(shifted?.line, "No.10+5.0m 右 1.2m")

        let wide = OperatorStation.guide(
            point: PlanarPoint(x: 250, y: 0),
            alignment: line,
            interval: 100,
            originStation: 0
        )
        XCTAssertEqual(wide?.line, "No.2+50.0m 中心")

        let rolled = OperatorStation.guide(point: PlanarPoint(x: 479.96, y: 0), alignment: line)
        XCTAssertEqual(rolled?.line, "No.24+0.0m 中心")
    }

    func testNamesBecomeChainageAndIgnorePlainPointNames() {
        XCTAssertEqual(StationName.chainageMeters(in: "No.23+5.2", interval: 20), 465.2)
        XCTAssertEqual(StationName.chainageMeters(in: "No.23", interval: 20), 460)
        XCTAssertEqual(StationName.chainageMeters(in: "23+5", interval: 20), 465)
        XCTAssertEqual(StationName.chainageMeters(in: "Ｎｏ．２３＋５", interval: 20) ?? -1, 465, accuracy: 1e-6)
        XCTAssertNil(StationName.chainageMeters(in: "T1", interval: 20))
        XCTAssertNil(StationName.chainageMeters(in: "120", interval: 20))
    }

    func testNamedPointsStampChainageEvenWhenTheGeometryIsShort() {
        let anchors = [
            StationAnchor(name: "No.0", point: PlanarPoint(x: 0, y: 0)),
            StationAnchor(name: "No.50", point: PlanarPoint(x: 980, y: 0))
        ]
        let line = StationLine.namedPoints(anchors: anchors, zone: 9, intervalMeters: 20, originStation: 0)
        let middle = line?.locate(PlanarPoint(x: 490, y: 3.2))
        XCTAssertEqual(middle?.line, "No.25+0.0m 左 3.2m")
        XCTAssertEqual(line?.chainageMeters.last ?? 0, 1000, accuracy: 1e-6)
    }

    func testTheSamePacketGivesTheSameStationOnAnotherPhone() throws {
        let built = try XCTUnwrap(StationLine.polyline(
            vertices: [PlanarPoint(x: 0, y: 0), PlanarPoint(x: 1000, y: 0)],
            zone: 9,
            intervalMeters: 20,
            originStation: 0,
            anchors: [StationAnchor(name: "No.0", point: PlanarPoint(x: 0, y: 0)), StationAnchor(name: "No.23+5", point: PlanarPoint(x: 465, y: 1))]
        ))
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let shared = try decoder.decode(StationLine.self, from: encoder.encode(built))
        let local = built.locate(PlanarPoint(x: 465, y: 3.2))?.line
        let remote = shared.locate(PlanarPoint(x: 465, y: 3.2))?.line
        XCTAssertEqual(local, remote)
        XCTAssertEqual(remote, "No.23+5.0m 左 3.2m")

        var project = SurveyProject(name: "路線", createdAt: Date(timeIntervalSince1970: 0), zone: 9)
        project.stationLine = shared
        project.stationIntervalMeters = 20
        project.stationOrigin = 0
        let projectEncoder = JSONEncoder()
        projectEncoder.dateEncodingStrategy = .iso8601
        let projectDecoder = JSONDecoder()
        projectDecoder.dateDecodingStrategy = .iso8601
        let loaded = try projectDecoder.decode(SurveyProject.self, from: projectEncoder.encode(project))
        XCTAssertEqual(loaded.stationLine?.locate(PlanarPoint(x: 200, y: 0))?.line, built.locate(PlanarPoint(x: 200, y: 0))?.line)

        let older = """
        {"axis":"cadEastNorth","createdAt":"2026-10-20T00:00:00Z","drawings":[],"id":"p","name":"現場","zone":9}
        """.data(using: .utf8)!
        let plain = try projectDecoder.decode(SurveyProject.self, from: older)
        XCTAssertNil(plain.stationLine)
        XCTAssertNil(plain.stationIntervalMeters)
    }
}
