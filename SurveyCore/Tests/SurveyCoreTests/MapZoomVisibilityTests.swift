import XCTest
@testable import SurveyCore

final class MapZoomVisibilityTests: XCTestCase {
    func testOverzoomStaysInsideTheProviderAndCropsARealPiece() {
        let same = MapTileOverzoom.resolve(z: 16, x: 100, y: 40)
        XCTAssertEqual(same.source.z, 16)
        XCTAssertEqual(same.cropSize, 256)
        XCTAssertFalse(same.usesParent)

        let deeper = MapTileOverzoom.resolve(z: 20, x: 16, y: 8)
        XCTAssertEqual(deeper.source.z, MapTileOverzoom.providerMaxZoom)
        XCTAssertEqual(deeper.source.x, 16 >> 2)
        XCTAssertEqual(deeper.source.y, 8 >> 2)
        XCTAssertEqual(deeper.cropSize, 64)
        XCTAssertGreaterThanOrEqual(deeper.cropX, 0)
        XCTAssertLessThanOrEqual(deeper.cropX + deeper.cropSize, 256)

        let maxed = MapTileOverzoom.resolve(z: 22, x: 63, y: 15)
        XCTAssertEqual(maxed.source.z, 18)
        XCTAssertEqual(maxed.source.x, 63 >> 4)
        XCTAssertEqual(maxed.source.y, 15 >> 4)
        XCTAssertEqual(maxed.cropSize, 16)
        XCTAssertLessThanOrEqual(maxed.cropX + maxed.cropSize, 256)
        XCTAssertLessThanOrEqual(maxed.cropY + maxed.cropSize, 256)

        let pastTheCamera = MapTileOverzoom.resolve(z: 24, x: 255, y: 63)
        XCTAssertEqual(pastTheCamera.source.z, MapTileOverzoom.providerMaxZoom)
        XCTAssertEqual(pastTheCamera.source.x, 255 >> 6)
        XCTAssertEqual(pastTheCamera.source.y, 63 >> 6)
        XCTAssertGreaterThan(pastTheCamera.cropSize, 0)
        XCTAssertLessThanOrEqual(pastTheCamera.cropX + pastTheCamera.cropSize, 256)
    }

    func testAlignedDrawingAndTilesStayVisibleFromZoom5Through22() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("drawings_test/7_local_origin_mm_sfig.sfc")
        let survey = try SFCParser.open(Data(contentsOf: url))
        let fit = try XCTUnwrap(SFCPointFit.align(document: survey.document, book: survey.book))
        let overlay = DrawingPlacement.overlay(
            document: survey.document,
            zone: 2,
            axis: .cadEastNorth,
            transform: fit.transform
        )
        XCTAssertFalse(overlay.paths.isEmpty)
        let center = PlanarPoint(x: survey.document.bounds.midX, y: survey.document.bounds.midY)
        let anchor = try XCTUnwrap(marker("T-1", in: survey.document))
        let placed = try XCTUnwrap(DrawingPlacement.geographic(
            anchor,
            zone: 2,
            axis: .cadEastNorth,
            transform: fit.transform
        ))

        for zoom in 5...MapTileOverzoom.appMaxZoom {
            let tile = TileMath.tileID(
                latitude: placed.latitudeDegrees,
                longitude: placed.longitudeDegrees,
                zoom: zoom
            )
            let resolved = MapTileOverzoom.resolve(z: tile.z, x: tile.x, y: tile.y)
            XCTAssertLessThanOrEqual(resolved.source.z, MapTileOverzoom.providerMaxZoom, "z\(zoom)")
            XCTAssertGreaterThan(resolved.cropSize, 0, "z\(zoom)")
            XCTAssertLessThanOrEqual(resolved.source.z, 18)

            let span = groundSpan(zoom: zoom, latitude: placed.latitudeDegrees)
            let view = DrawingBounds(
                minX: center.x - span / 2,
                minY: center.y - span / 2,
                maxX: center.x + span / 2,
                maxY: center.y + span / 2
            )
            let batch = DrawingLOD.batch(document: survey.document, view: view, pointsPerUnit: 400 / max(span, 1e-6))
            XCTAssertFalse(batch.strokes.isEmpty && batch.points.isEmpty, "z\(zoom) で図が空")

            let aroundPoint = DrawingBounds(
                minX: anchor.x - max(span, 30) / 2,
                minY: anchor.y - max(span, 30) / 2,
                maxX: anchor.x + max(span, 30) / 2,
                maxY: anchor.y + max(span, 30) / 2
            )
            let near = DrawingLOD.batch(document: survey.document, view: aroundPoint, pointsPerUnit: 400 / max(span, 1e-6))
            XCTAssertFalse(near.points.isEmpty, "z\(zoom) で点が見えない")
            XCTAssertFalse(near.strokes.isEmpty, "z\(zoom) で線が見えない")
        }
    }

    private func groundSpan(zoom: Int, latitude: Double) -> Double {
        let longitude = MapZoom.longitudeDelta(forZoom: zoom, screenWidthPoints: 400)
        let cosine = max(0.2, abs(cos(latitude * .pi / 180)))
        return longitude * 111_320 * cosine
    }

    private func marker(_ name: String, in document: DrawingDocument) -> PlanarPoint? {
        guard let label = document.entities.first(where: { entity in
            if case let .text(_, string, _, _) = entity.primitive { return string == name }
            return false
        }), case let .text(origin, _, _, _) = label.primitive else { return nil }
        let points = document.entities.compactMap { entity -> PlanarPoint? in
            if case let .point(point) = entity.primitive { return point }
            return nil
        }
        return points.min { origin.distance(to: $0) < origin.distance(to: $1) }
    }
}
