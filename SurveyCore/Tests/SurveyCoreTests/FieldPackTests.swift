import XCTest
@testable import SurveyCore

final class FieldPackTests: XCTestCase {
    func testMetaEPSG6674OverridesZone9And16() {
        let meta = DrawingSidecar(epsg: 6674, axis: "EN", unit: "m")
        for stale in [9, 16] {
            let decision = FieldPackPlacement.resolve(
                sidecar: meta,
                x: stale == 9 ? -18_344 : 0,
                y: stale == 16 ? -155_290 : 0,
                latitude: nil,
                longitude: nil,
                prefecture: nil
            )
            XCTAssertEqual(decision.zone, 6, "初期の \(stale) 系を残している")
            XCTAssertEqual(decision.epsg, 6674)
            XCTAssertEqual(decision.axis, .cadEastNorth)
        }
        XCTAssertEqual(SiteDXF.zone(forEPSG: 6674), 6)
        XCTAssertEqual(PlaneZoneCatalog.nearestZone(latitude: 34.6, longitude: 135.8), 6)
        XCTAssertEqual(SiteDXF.zone, 16)
    }

    func testGPSPicksZone6AndDoesNotKeep9Or16() throws {
        let projected = try XCTUnwrap(VIPack.plane())
        let pyprojEast = -18344.214405668823
        let pyprojNorth = -155290.82320803934
        XCTAssertEqual(projected.easting, pyprojEast, accuracy: 0.05)
        XCTAssertEqual(projected.northing, pyprojNorth, accuracy: 0.05)
        let back = try XCTUnwrap(PlaneRectangular.inverse(
            northingMeters: pyprojNorth,
            eastingMeters: pyprojEast,
            zone: 6
        ))
        XCTAssertEqual(back.latitudeDegrees, 34.6, accuracy: 1e-5)
        XCTAssertEqual(back.longitudeDegrees, 135.8, accuracy: 1e-5)

        for stale in [9, 16] {
            let decided = FieldPackPlacement.zoneForPlane(
                northing: pyprojNorth,
                easting: pyprojEast,
                latitude: 34.6,
                longitude: 135.8,
                trustedZone: stale
            )
            XCTAssertEqual(decided.zone, 6, "\(stale) 系のまま")
        }
        let undecided = FieldPackPlacement.zoneForPlane(
            northing: pyprojNorth,
            easting: pyprojEast,
            latitude: nil,
            longitude: nil,
            trustedZone: nil
        )
        XCTAssertNil(undecided.zone)
        XCTAssertEqual(undecided.choices, Array(1...19))
        let fromMeta = FieldPackPlacement.zoneForPlane(
            northing: pyprojNorth,
            easting: pyprojEast,
            latitude: nil,
            longitude: nil,
            trustedZone: 6
        )
        XCTAssertEqual(fromMeta.zone, 6)
    }

    func testSIMAZone6DropsOrthometricHeight() throws {
        let north = -155290.823
        let east = -18344.214
        var lines = ["G00,02,"]
        for index in 1...4 {
            lines.append(String(format: "A01,%d,P%02d,%.3f,%.3f,%.3f,", index, index, north + Double(index), east, 400 + Double(index)))
        }
        let data = Data(lines.joined(separator: "\n").utf8)
        let sample = try XCTUnwrap(CoordinateExchange.firstPlane(data: data, filename: "control.sima"))
        let zone = FieldPackPlacement.zoneForPlane(
            northing: sample.northing,
            easting: sample.easting,
            latitude: 34.6,
            longitude: 135.8,
            trustedZone: 9
        ).zone
        XCTAssertEqual(zone, 6)
        let entries = CoordinateExchange.parse(data: data, filename: "control.sima", zone: zone ?? 0)
        XCTAssertEqual(entries.count, 4)
        XCTAssertNil(entries[0].ellipsoidalHeightMeters)
        let back = try XCTUnwrap(PlaneRectangular.forward(
            latitudeDegrees: entries[0].latitudeDegrees,
            longitudeDegrees: entries[0].longitudeDegrees,
            zone: 6
        ))
        XCTAssertEqual(back.northingMeters, north + 1, accuracy: 0.05)
        XCTAssertEqual(back.eastingMeters, east, accuracy: 0.05)
        let here = samplePosition(latitude: 34.6, longitude: 135.8, height: 80, quality: .rtkFix, receiver: .rtk)
        let guide = try XCTUnwrap(BasicStakeout.guide(from: here, to: entries[0], zone: 6))
        XCTAssertNil(guide.heightMeters)
        XCTAssertTrue(guide.line.contains("高さは未確認"))
    }

    func testControlCSVKeepsThirtyFourPointsAndOrthometricHeight() throws {
        let text = try XCTUnwrap(String(data: VIPack.csv, encoding: .utf8))
        let points = try ControlPointCatalog.loadCSV(text)
        XCTAssertEqual(points.count, 34)
        XCTAssertEqual(points[0].name, "T4-15'")
        let bomPoints = try ControlPointCatalog.loadCSV("\u{FEFF}" + text.replacingOccurrences(of: "\n", with: "\r\n"))
        XCTAssertEqual(bomPoints.first?.name, "T4-15'")
        XCTAssertEqual(bomPoints.count, 34)
        let shift = try XCTUnwrap(text.data(using: .shiftJIS))
        let shiftPoints = try ControlPointCatalog.loadCSVData(shift)
        XCTAssertEqual(shiftPoints.first?.name, "T4-15'")
        XCTAssertEqual(shiftPoints.count, 34)
        XCTAssertEqual(points[0].id, "T4-15'")
        XCTAssertNil(points[0].heightMeters)
        XCTAssertEqual(points[0].latitudeDegrees, VIPack.latitude, accuracy: 1e-9)
        XCTAssertEqual(points[0].longitudeDegrees, VIPack.longitude, accuracy: 1e-9)
        XCTAssertEqual(points[0].heightKind, .orthometric)
        XCTAssertNil(points[0].comparableEllipsoidalHeightMeters)
        let document = try DXFParser.parse(VIPack.dxf)
        XCTAssertEqual(document.entities.count, 3)
        XCTAssertEqual(SiteDXF.controlNames(in: document), ["T4-15'"])
        XCTAssertTrue(document.layers.contains { $0.name == "測設_基準点" })
        let meta = try XCTUnwrap(DrawingSidecar.load(VIPack.meta))
        XCTAssertEqual(meta.zone, 6)
        let decision = FieldPackPlacement.resolve(
            sidecar: meta,
            x: document.bounds.midX,
            y: document.bounds.midY,
            latitude: nil,
            longitude: nil,
            prefecture: nil
        )
        XCTAssertEqual(decision.zone, 6)
        XCTAssertNotEqual(decision.zone, 9)
        XCTAssertNotEqual(decision.zone, 16)
        let overlay = DrawingPlacement.overlay(
            document: document,
            zone: decision.zone ?? 0,
            axis: .cadEastNorth,
            transform: nil
        )
        XCTAssertFalse(overlay.paths.isEmpty)
        let corner = try XCTUnwrap(overlay.paths.first?.coordinates.first)
        XCTAssertEqual(corner.latitudeDegrees, VIPack.latitude, accuracy: 0.002)
        XCTAssertEqual(corner.longitudeDegrees, VIPack.longitude, accuracy: 0.002)
        let sima = try XCTUnwrap(String(data: VIPack.sima, encoding: .utf8))
        XCTAssertTrue(sima.contains("A01,1,S01,"))
        let entries = CoordinateExchange.parse(data: VIPack.sima, filename: "points.sima", zone: 6)
        XCTAssertEqual(entries.count, 4)
        XCTAssertNil(entries[0].ellipsoidalHeightMeters)
        let restored = try XCTUnwrap(PlaneRectangular.forward(
            latitudeDegrees: entries[0].latitudeDegrees,
            longitudeDegrees: entries[0].longitudeDegrees,
            zone: 6
        ))
        let origin = try XCTUnwrap(VIPack.plane())
        XCTAssertEqual(restored.northingMeters, origin.northing + 8, accuracy: 0.05)
        XCTAssertEqual(restored.eastingMeters, origin.easting + 6, accuracy: 0.05)
        let names = DrawingSidecarNames.candidates(forDXF: VIPack.dxfFileName)
        XCTAssertEqual(names[0], VIPack.dxfFileName + ".meta.json")
        XCTAssertEqual(names[1], "20231101市道計画平面図_VI系_軽量.meta.json")
        XCTAssertEqual(
            DrawingSidecarNames.match(dxfName: VIPack.dxfFileName, metaNames: [names[1], names[0]]),
            names[0]
        )
        XCTAssertEqual(meta.transform?.status, "合成")
        XCTAssertEqual(meta.transform?.version, "1")
        XCTAssertEqual(meta.transform?.pairCount, 4)
        XCTAssertEqual(meta.transform?.rmsMillimetres ?? -1, 0, accuracy: 1e-9)
    }
}
