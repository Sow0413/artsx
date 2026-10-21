import XCTest
@testable import SurveyCore

final class DrawingFollowupTests: XCTestCase {
    func testSFCKeepsLayersAndPublicGeometry() throws {
        let document = try SFCParser.parse(Data(sampleSFC.utf8))
        XCTAssertTrue(document.codePage.contains("Ver3"))
        XCTAssertTrue(document.codePage.contains("UTF-8"))
        XCTAssertEqual(document.layers.map(\.name), ["D-BGD-TXT", "D-STR", "隠す"])
        XCTAssertEqual(document.layers[0].role, .background)
        XCTAssertEqual(document.layers[1].role, .design)
        XCTAssertFalse(document.layers[2].isVisible)
        XCTAssertEqual(document.unsupportedCounts["hatch_feature"], 1)
        XCTAssertEqual(document.unitWarning?.contains("公共座標"), true)

        let line = try first(.line(PlanarPoint(x: 0, y: 0), PlanarPoint(x: 30, y: 0)), in: document)
        XCTAssertEqual(line.layer, "D-BGD-TXT")
        XCTAssertEqual(line.color, DrawingColor(red: 1, green: 0, blue: 0))

        let polyline = document.entities.first { entity in
            if case .polyline = entity.primitive { return true }
            return false
        }
        guard case let .polyline(vertices, _, _) = polyline?.primitive else {
            return XCTFail("折線がない")
        }
        XCTAssertEqual(polyline?.layer, "D-STR")
        XCTAssertEqual(vertices, [
            PlanarPoint(x: 0, y: 0),
            PlanarPoint(x: 10, y: 0),
            PlanarPoint(x: 10, y: 5)
        ])

        XCTAssertTrue(document.entities.contains { entity in
            if case let .circle(_, radius) = entity.primitive { return abs(radius - 2) < 1e-9 }
            return false
        })
        let arc = document.entities.first { entity in
            if case .arc = entity.primitive { return true }
            return false
        }
        guard case let .arc(_, radius, start, end, display) = arc?.primitive else {
            return XCTFail("円弧がない")
        }
        XCTAssertEqual(radius, 10, accuracy: 1e-9)
        XCTAssertEqual(start, 90, accuracy: 1e-9)
        XCTAssertEqual(end, 0, accuracy: 1e-9)
        XCTAssertTrue(display.contains { $0.distance(to: PlanarPoint(x: -10, y: 0)) < 1 })
        XCTAssertFalse(display.contains { $0.distance(to: PlanarPoint(x: 7, y: 7)) < 0.5 })

        XCTAssertEqual(try label("杭", in: document), "杭")
        XCTAssertTrue(document.entities.contains { entity in
            if case let .point(point) = entity.primitive { return point == PlanarPoint(x: 8, y: 9) }
            return false
        })

        let hidden = document.settingRole(.background, visible: false)
        XCTAssertFalse(hidden.shows(.background))
        XCTAssertTrue(hidden.shows(.design))
        XCTAssertTrue(hidden.entities(in: hidden.bounds).contains { $0.layer == "D-STR" })
        XCTAssertFalse(hidden.entities(in: hidden.bounds).contains { $0.layer == "D-BGD-TXT" })
        let restored = hidden.settingLayer("D-BGD-TXT", visible: true)
        XCTAssertEqual(restored.layers.first { $0.name == "D-BGD-TXT" }?.role, .background)

        let version2 = try SFCParser.parse(Data(version2SFC.utf8))
        XCTAssertTrue(version2.codePage.contains("Ver2"))
        XCTAssertEqual(version2.entities.count, 1)

        let japanese = try SFCParser.parse(shiftJISFC())
        XCTAssertTrue(japanese.codePage.contains("Shift_JIS"))
        XCTAssertTrue(japanese.layers.contains { $0.name == "地形" && $0.role == .background })
        XCTAssertThrowsError(try SFCParser.parse(Data("ただの文章".utf8))) { error in
            XCTAssertEqual(error as? SFCError, .notSFC)
        }
    }

    func testHairlineWidthStaysPutAndContoursRecede() {
        XCTAssertEqual(DrawingStroke.screenPoints(weight: 1), 0.5, accuracy: 1e-9)
        XCTAssertEqual(DrawingStroke.screenPoints(weight: 8), 1, accuracy: 1e-9)
        XCTAssertEqual(DrawingStroke.screenPoints(weight: 100), 1, accuracy: 1e-9)
        XCTAssertGreaterThan(DrawingStroke.screenPoints(weight: 5), DrawingStroke.screenPoints(weight: 1))
        XCTAssertLessThanOrEqual(DrawingStroke.screenPoints(weight: 500), DrawingStroke.maximumPoints)

        let contour = DrawingEntity(
            id: 0,
            layer: "等高線",
            color: .white,
            primitive: .line(PlanarPoint(x: 0, y: 0), PlanarPoint(x: 80, y: 1)),
            bounds: DrawingBounds(minX: 0, minY: 0, maxX: 80, maxY: 1),
            lineWeight: 11
        )
        let design = DrawingEntity(
            id: 1,
            layer: "D-STR",
            color: DrawingColor(red: 1, green: 0, blue: 0),
            primitive: .line(PlanarPoint(x: 0, y: 10), PlanarPoint(x: 80, y: 12)),
            bounds: DrawingBounds(minX: 0, minY: 10, maxX: 80, maxY: 12),
            lineWeight: 1
        )
        let entities = [contour, design]
        let document = DrawingDocument(
            layers: [
                DrawingLayer(name: "等高線", color: .white, isVisible: true, role: .background),
                DrawingLayer(name: "D-STR", color: .white, isVisible: true, role: .design)
            ],
            entities: entities,
            bounds: DrawingBounds(minX: 0, minY: 0, maxX: 80, maxY: 12),
            unsupportedCounts: ["drawing_sheet_feature": 1, "sfig_org_feature": 2, "mystery_feature": 1],
            codePage: "test",
            unitWarning: "座標はミリメートルだったので、メートルに直しました。公共座標として読みました。",
            index: DrawingSpatialIndex(entities: entities)
        )
        let far = DrawingLOD.batch(document: document, view: document.bounds.padded(10), pointsPerUnit: 0.05)
        let near = DrawingLOD.batch(document: document, view: document.bounds.padded(10), pointsPerUnit: 30)
        XCTAssertEqual(far.strokes.map(\.width), near.strokes.map(\.width))
        XCTAssertEqual(far.strokes.count, 2)
        for stroke in far.strokes {
            XCTAssertGreaterThanOrEqual(stroke.width, DrawingStroke.minimumPoints)
            XCTAssertLessThanOrEqual(stroke.width, DrawingStroke.maximumPoints)
        }
        XCTAssertTrue(far.strokes.contains { $0.red == DrawingStroke.contour.red && $0.green == DrawingStroke.contour.green })
        XCTAssertTrue(far.strokes.contains { $0.red == 1 && $0.green == 0 && $0.blue == 0 })
        let counts = Dictionary(uniqueKeysWithValues: document.skippedElements.map { ($0.label, $0.count) })
        XCTAssertEqual(counts["図枠"], 1)
        XCTAssertEqual(counts["記号"], 2)
        XCTAssertEqual(counts["その他"], 1)
        XCTAssertFalse(document.skippedElements.contains { $0.label.contains("feature") })
        XCTAssertEqual(document.unitNote, "座標はミリメートルだったので、メートルに直しました。")

        var dense: [DrawingEntity] = []
        dense.reserveCapacity(3_000)
        for index in 0..<3_000 {
            let y = Double(index)
            dense.append(DrawingEntity(
                id: index,
                layer: "等高線",
                color: .white,
                primitive: .line(PlanarPoint(x: 0, y: y), PlanarPoint(x: 40, y: y)),
                bounds: DrawingBounds(minX: 0, minY: y, maxX: 40, maxY: y),
                lineWeight: 1
            ))
        }
        let crowd = DrawingDocument(
            layers: [DrawingLayer(name: "等高線", color: .white, isVisible: true, role: .background)],
            entities: dense,
            bounds: DrawingBounds(minX: 0, minY: 0, maxX: 40, maxY: 2_999),
            unsupportedCounts: [:],
            codePage: "test",
            unitWarning: nil,
            index: DrawingSpatialIndex(entities: dense)
        )
        let overview = DrawingLOD.batch(document: crowd, view: crowd.bounds, pointsPerUnit: 900 / 2_999)
        XCTAssertGreaterThan(overview.strokes.count, 0)
        XCTAssertLessThan(overview.strokes.count, dense.count / 2)
        XCTAssertLessThanOrEqual(overview.strokes.count, DrawingLOD.maxStrokes)
    }

    func testBackgroundMatchShiftAndMiss() throws {
        let same = square(origin: PlanarPoint(x: 0, y: 0), size: 20)
        let matched = BackgroundChecker.compare(drawing: same, reference: same, axis: .cadEastNorth)
        XCTAssertEqual(matched.outcome, .usableAsIs)
        XCTAssertTrue(matched.message.contains("座標あり・そのまま使える"))

        let moved = square(origin: PlanarPoint(x: 10, y: 0), size: 20)
        let shifted = BackgroundChecker.compare(drawing: same, reference: moved, axis: .cadEastNorth)
        guard case let .shifted(distance, azimuth, transform, rms) = shifted.outcome else {
            return XCTFail("ずれを出さなかった \(shifted.outcome)")
        }
        XCTAssertEqual(distance, 10, accuracy: 0.2)
        XCTAssertEqual(azimuth, 90, accuracy: 2)
        XCTAssertEqual(transform.translationEasting, 10, accuracy: 0.2)
        XCTAssertEqual(transform.translationNorthing, 0, accuracy: 0.2)
        XCTAssertLessThan(rms, 0.2)

        let elsewhere = square(origin: PlanarPoint(x: 800, y: 800), size: 20)
        let missed = BackgroundChecker.compare(drawing: same, reference: elsewhere, axis: .cadEastNorth)
        XCTAssertEqual(missed.outcome, .unmatched)
        XCTAssertTrue(missed.message.contains("合わない"))

        let document = try SFCParser.parse(Data(backgroundSFC.utf8))
        let reference = DrawingGeometry.backgroundPlaneSegments(document: document, axis: .cadEastNorth)
        let verdict = BackgroundChecker.judge(document: document, reference: reference, currentAxis: .surveyNorthEast)
        XCTAssertEqual(verdict.outcome, .usableAsIs)
        XCTAssertEqual(verdict.axis, .cadEastNorth)
        XCTAssertTrue(verdict.message.contains("X が東"))
    }

    func testVectorTileProjectsLineIntoTheZone() throws {
        let tile = TileMath.tileID(latitude: 36.01, longitude: 140.0, zoom: 16)
        let payload = vectorTile(name: "RdEdg", extent: 4096, from: (0, 0), to: (200, 0))
        let segments = GSIVectorTile.segments(protobuf: payload, tile: tile, zone: 9)
        let segment = try XCTUnwrap(segments.first)
        let origin = TileMath.unproject(tileX: tile.x, tileY: tile.y, zoom: tile.z, xFraction: 0, yFraction: 0)
        let plane = try XCTUnwrap(PlaneRectangular.forward(
            latitudeDegrees: origin.latitudeDegrees,
            longitudeDegrees: origin.longitudeDegrees,
            zone: 9
        ))
        XCTAssertEqual(segment.start.x, plane.eastingMeters, accuracy: 1e-3)
        XCTAssertEqual(segment.start.y, plane.northingMeters, accuracy: 1e-3)
        XCTAssertGreaterThan(segment.length, 1)

        let wide = GeoBounds(south: 35.0, west: 139.0, north: 35.08, east: 139.08)
        let tiles = GSIVectorTile.cappedTiles(covering: wide)
        XCTAssertLessThanOrEqual(tiles.count, 9)
        XCTAssertLessThan(tiles.first?.z ?? 16, 16)
        XCTAssertNotNil(GSIVectorTile.url(z: tile.z, x: tile.x, y: tile.y))
    }

    func testSnapAndStakeoutPrecision() throws {
        let document = try documentWithCrossAndPoint()
        let crossing = try XCTUnwrap(DrawingSnap.nearest(
            in: document,
            to: PlanarPoint(x: 1.2, y: 0.2),
            tolerance: 0.8
        ))
        XCTAssertEqual(crossing.kind, .intersection)
        XCTAssertEqual(crossing.point.x, 1, accuracy: 1e-6)
        XCTAssertEqual(crossing.point.y, 0, accuracy: 1e-6)

        let end = try XCTUnwrap(DrawingSnap.nearest(
            in: document,
            to: PlanarPoint(x: 0.05, y: 0.05),
            tolerance: 0.4
        ))
        XCTAssertEqual(end.kind, .endpoint)
        XCTAssertEqual(end.point, PlanarPoint(x: 0, y: 0))

        let point = try XCTUnwrap(DrawingSnap.nearest(
            in: document,
            to: PlanarPoint(x: 5.1, y: 5.05),
            tolerance: 0.4
        ))
        XCTAssertEqual(point.kind, .point)
        XCTAssertEqual(point.point, PlanarPoint(x: 5, y: 5))

        XCTAssertEqual(StakeoutPrecision.decide(.coordinateBook), .centimeters)
        XCTAssertEqual(StakeoutPrecision.decide(.mapGrade), .meters)
        XCTAssertEqual(StakeoutPrecision.decide(nil), .meters)
        XCTAssertEqual(StakeoutText.meters(1.234, precision: .centimeters), "1.23 m")
        XCTAssertEqual(StakeoutText.meters(1.234, precision: .meters), "1 m")
        XCTAssertEqual(StakeoutText.meters(1500, precision: .centimeters), "1.50 km")
        XCTAssertEqual(StakeoutText.meters(1500, precision: .meters), "1.5 km")
    }

    func testControlFixRestartsWhenFixDrops() throws {
        var session = ControlFixSession()
        let start = Date(timeIntervalSince1970: 10_000)
        session.observe(standalone(), at: start)
        XCTAssertFalse(session.canRecord)
        XCTAssertNil(session.record(at: start))

        session.observe(fix(satellites: 18), at: start)
        session.observe(fix(satellites: 18), at: start.addingTimeInterval(10))
        let saved = try XCTUnwrap(session.record(at: start.addingTimeInterval(10)))
        XCTAssertEqual(saved.fixDurationSeconds, 10, accuracy: 1e-9)
        XCTAssertEqual(saved.satelliteCount, 18)
        XCTAssertEqual(saved.epochCount, 2)
        XCTAssertEqual(saved.horizontalAccuracyMeters, 0.02, accuracy: 1e-9)

        session.observe(floated(), at: start.addingTimeInterval(11))
        XCTAssertTrue(session.restarted)
        XCTAssertFalse(session.canRecord)
        XCTAssertNil(session.record(at: start.addingTimeInterval(12)))

        session.observe(fix(satellites: 12), at: start.addingTimeInterval(20))
        let again = try XCTUnwrap(session.record(at: start.addingTimeInterval(25)))
        XCTAssertEqual(again.fixDurationSeconds, 5, accuracy: 1e-9)
        XCTAssertFalse(session.restarted)
        XCTAssertEqual(again.satelliteCount, 12)

        var phone = ControlFixSession()
        phone.observe(samplePosition(quality: .rtkFix, receiver: .iphoneGPS), at: start)
        XCTAssertFalse(phone.canRecord)

        var held = ControlFixSession()
        held.observe(fix(satellites: 9), at: start)
        XCTAssertTrue(held.canRecord)
        held.abort()
        XCTAssertTrue(held.restarted)
        XCTAssertFalse(held.canRecord)
        XCTAssertNil(held.record(at: start.addingTimeInterval(3)))
    }

    func testPointNamesSkipBookAndStayOnTheRecord() throws {
        XCTAssertEqual(PointNamer.nextName(prefix: "t", existing: []), "T1")
        XCTAssertEqual(PointNamer.nextName(prefix: "T", existing: ["T1", "T2"]), "T3")
        XCTAssertEqual(PointNamer.nextName(prefix: "T", existing: ["T1", "T3", "t2"]), "T4")
        XCTAssertEqual(PointNamer.nextName(prefix: "T", existing: ["T1", "T3"]), "T2")
        XCTAssertNil(PointNamer.nextName(prefix: "杭", existing: []))
        XCTAssertNil(PointNamer.nextName(prefix: "T1", existing: []))

        let root = try TestFiles.directory()
        defer { TestFiles.remove(root) }
        let project = try ProjectStore.create(name: "点名", at: root, now: Date(timeIntervalSince1970: 20))
        let note = try ProjectStore.addRecord(
            date: "2026-10-20",
            kind: "基準点",
            name: "本点",
            projectName: project.name,
            at: root,
            now: Date(timeIntervalSince1970: 21),
            pointPrefix: "T"
        )
        XCTAssertEqual(note.pointPrefix, "T")
        try ProjectStore.setRecordPrefix(folder: note.folderName, prefix: "K", projectName: project.name, at: root)
        let reread = try ProjectStore.recordNote(folder: note.folderName, projectName: project.name, at: root)
        XCTAssertEqual(reread.pointPrefix, "K")

        let entry = CoordinateBookEntry(
            name: "K1",
            latitudeDegrees: 36,
            longitudeDegrees: 140,
            ellipsoidalHeightMeters: 10,
            horizontalAccuracyMeters: 0.02,
            verticalAccuracyMeters: 0.03,
            satelliteCount: 16,
            fixDurationSeconds: 30,
            recordedAt: Date(timeIntervalSince1970: 22)
        )
        try ProjectStore.saveCoordinate(entry, projectName: project.name, at: root)
        XCTAssertTrue(ProjectStore.coordinateBookNames(projectName: project.name, at: root).contains("K1"))
        let next = PointNamer.nextName(
            prefix: reread.pointPrefix ?? "",
            existing: ProjectStore.coordinateBookNames(projectName: project.name, at: root)
        )
        XCTAssertEqual(next, "K2")

        var store = PointPrefixStore()
        store.activeKey = note.folderName
        store.prefixes[note.folderName] = "K"
        store.prefixes[PointPrefixStore.sharedKey] = "T"
        try store.save(to: root)
        let loaded = PointPrefixStore.load(from: root)
        XCTAssertEqual(loaded.prefix(for: note.folderName), "K")
        XCTAssertEqual(loaded.prefix(for: nil), "K")

        let old = #"{"id":"00000000-0000-0000-0000-000000000001","name":"小屋","workID":"preview","captured":{"latitudeDegrees":35.0,"longitudeDegrees":139.0,"horizontalAccuracyMeters":3.0,"timestamp":"2026-10-20T00:00:00Z","stage":0,"fixQuality":"standalone","receiver":"iphoneGPS","frame":"WGS84/ITRF"}}"#
        let decoded = try JSONDecoder.survey().decode(GeodeticPosition.self, from: Data(
            #"{"latitudeDegrees":35.0,"longitudeDegrees":139.0,"horizontalAccuracyMeters":3.0,"timestamp":"2026-10-20T00:00:00Z","stage":0,"fixQuality":"standalone","receiver":"iphoneGPS","frame":"WGS84/ITRF"}"#.utf8
        ))
        XCTAssertNil(decoded.satelliteCount)
        let observation = try JSONDecoder.survey().decode(FieldObservation.self, from: Data(old.utf8))
        XCTAssertNil(observation.fixDurationSeconds)
        XCTAssertEqual(observation.name, "小屋")

        let alignmentJSON = #"{"accuracyTag":"地図並み（m）","axis":"cadEastNorth","createdAt":"2026-10-20T00:00:00Z","drawingFileName":"a.dxf","lockScale":true,"name":"手","pairs":[],"residualsMeters":[],"rmsMeters":0.1,"transform":{"rotationDegrees":0,"scale":1,"translationEasting":1,"translationNorthing":2},"version":1,"zone":9}"#
        let alignment = try JSONDecoder.survey().decode(AlignmentRecord.self, from: Data(alignmentJSON.utf8))
        XCTAssertFalse(alignment.composesAxis)
        XCTAssertEqual(alignment.transform.translationEasting, 1, accuracy: 1e-9)
    }

    private func standalone() -> GeodeticPosition {
        samplePosition(accuracy: 3, stage: .iphone, quality: .standalone, receiver: .iphoneGPS)
    }

    private func floated() -> GeodeticPosition {
        samplePosition(accuracy: 0.2, stage: .rtk, quality: .float, receiver: .rtk)
    }

    private func fix(satellites: Int) -> GeodeticPosition {
        samplePosition(
            accuracy: 0.02,
            verticalAccuracy: 0.03,
            stage: .rtk,
            quality: .rtkFix,
            receiver: .rtk,
            satelliteCount: satellites
        )
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

    private func documentWithCrossAndPoint() throws -> DrawingDocument {
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        LINE
        8
        0
        10
        0
        20
        0
        11
        2
        21
        0
        0
        LINE
        8
        0
        10
        1
        20
        -1
        11
        1
        21
        1
        0
        POINT
        8
        0
        10
        5
        20
        5
        0
        ENDSEC
        0
        EOF
        """
        return try DXFParser.parse(Data(dxf.utf8))
    }

    private func first(_ primitive: DrawingPrimitive, in document: DrawingDocument) throws -> DrawingEntity {
        try XCTUnwrap(document.entities.first { $0.primitive == primitive })
    }

    private func label(_ string: String, in document: DrawingDocument) throws -> String {
        for entity in document.entities {
            if case let .text(_, value, _, _) = entity.primitive, value == string { return value }
        }
        throw XCTSkip("文字がない")
    }

    private func shiftJISFC() throws -> Data {
        func ascii(_ text: String) -> Data { Data(text.utf8) }
        let name = try XCTUnwrap("地形".data(using: .shiftJIS))
        return ascii("ISO-10303-21;\nHEADER;\nFILE_NAME('a','',(''),(''),'SCADEC_API_Ver2.0$$2.0','','');\nENDSEC;\nDATA;\n/*SXF\n#1=layer_feature('")
            + name
            + ascii("','1');\n#2=line_feature(1,1,1,1,0,0,5,0);\nSXF*/\nENDSEC;\nEND-ISO-10303-21;\n")
    }

    private func vectorTile(name: String, extent: Int, from: (Int, Int), to: (Int, Int)) -> Data {
        func varint(_ value: UInt64) -> Data {
            var data = Data()
            var rest = value
            while rest >= 0x80 {
                data.append(UInt8(rest & 0x7F) | 0x80)
                rest >>= 7
            }
            data.append(UInt8(rest))
            return data
        }
        func key(_ field: Int, _ wire: Int) -> Data { varint(UInt64((field << 3) | wire)) }
        func packed(_ field: Int, _ payload: Data) -> Data {
            key(field, 2) + varint(UInt64(payload.count)) + payload
        }
        func zigzag(_ value: Int) -> UInt64 { UInt64(bitPattern: Int64((value << 1) ^ (value >> 63))) }
        var geometry = Data()
        geometry.append(varint(UInt64((1 << 3) | 1)))
        geometry.append(varint(zigzag(from.0)))
        geometry.append(varint(zigzag(from.1)))
        geometry.append(varint(UInt64((1 << 3) | 2)))
        geometry.append(varint(zigzag(to.0 - from.0)))
        geometry.append(varint(zigzag(to.1 - from.1)))
        let feature = packed(4, geometry)
        var layer = Data()
        layer.append(packed(1, Data(name.utf8)))
        layer.append(packed(2, feature))
        layer.append(key(5, 0))
        layer.append(varint(UInt64(extent)))
        return packed(3, layer)
    }
}

private extension JSONDecoder {
    static func survey() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private let sampleSFC = """
ISO-10303-21;
HEADER;
FILE_NAME('sample.sfc','2026-10-20',(''),(''),'SCADEC_API_Ver3.30$$3.1','','');
ENDSEC;
DATA;
/*SXF
#1=layer_feature('D-BGD-TXT','1');
#2=layer_feature('D-STR','1');
#3=layer_feature('隠す','0');
#4=line_feature(1,2,1,1,0,0,30,0);
#5=polyline_feature(2,4,1,1,3,'(0,10,10)','(0,0,5)');
#6=circle_feature(2,3,1,1,5,5,2);
#7=arc_feature(2,5,1,1,0,0,10,1,0,90);
#8=text_string_feature(2,1,1,'杭',1,2,2.5,1,15);
#9=point_feature(2,1,1,1,8,9);
#10=hatch_feature(2,1,1);
SXF*/
ENDSEC;
END-ISO-10303-21;
"""

private let version2SFC = """
ISO-10303-21;
HEADER;
FILE_NAME('old.sfc','2026-10-20',(''),(''),'$$2.0','','');
ENDSEC;
DATA;
/*SXF
#1=layer_feature('D-STR','1');
#2=line_feature(1,1,1,1,0,0,1,1);
SXF*/
ENDSEC;
END-ISO-10303-21;
"""

private let backgroundSFC = """
ISO-10303-21;
HEADER;
FILE_NAME('bg.sfc','2026-10-20',(''),(''),'$$3.0','','');
ENDSEC;
DATA;
/*SXF
#1=layer_feature('D-BGD','1');
#2=layer_feature('D-STR','1');
#3=line_feature(1,1,1,1,0,0,40,0);
#4=line_feature(1,1,1,1,40,0,40,30);
#5=line_feature(1,1,1,1,40,30,0,30);
#6=line_feature(1,1,1,1,0,30,0,0);
#7=line_feature(2,2,1,1,5,5,15,8);
SXF*/
ENDSEC;
END-ISO-10303-21;
"""
