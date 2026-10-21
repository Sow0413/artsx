import XCTest
@testable import SurveyCore

final class DrawingBaseMapTests: XCTestCase {
    private let kameyama = PlanarPoint(x: 39019, y: -123868)

    func testCaptainWindowLandsOnKameyamaTiles() throws {
        let geo = try XCTUnwrap(DrawingPlacement.geographic(
            kameyama,
            zone: 6,
            axis: .cadEastNorth,
            transform: nil
        ))
        XCTAssertEqual(geo.latitudeDegrees, 34.88, accuracy: 0.02)
        XCTAssertEqual(geo.longitudeDegrees, 136.43, accuracy: 0.02)

        let frames = DrawingBaseMap.frames(
            viewCorners: square(center: kameyama, span: 200),
            zone: 6,
            axis: .cadEastNorth,
            transform: nil,
            composesAxis: false,
            style: .gsiStandard,
            pointsPerUnit: 0.2
        )
        XCTAssertFalse(frames.isEmpty)
        XCTAssertTrue(frames.allSatisfy { $0.tile.style == .gsiStandard })
        XCTAssertTrue(frames.contains { TileMath.bounds(of: $0.tile).contains(latitude: geo.latitudeDegrees, longitude: geo.longitudeDegrees) })

        let frame = try XCTUnwrap(frames.first {
            TileMath.bounds(of: $0.tile).contains(latitude: geo.latitudeDegrees, longitude: geo.longitudeDegrees)
        })
        let back = try XCTUnwrap(DrawingPlacement.geographic(
            frame.northWest,
            zone: 6,
            axis: .cadEastNorth,
            transform: nil
        ))
        let bounds = TileMath.bounds(of: frame.tile)
        XCTAssertEqual(back.latitudeDegrees, bounds.north, accuracy: 1e-6)
        XCTAssertEqual(back.longitudeDegrees, bounds.west, accuracy: 1e-6)

        let expected = DrawingBaseMap.zoom(
            latitudeDegrees: geo.latitudeDegrees,
            metersPerPixel: DrawingBaseMap.metersPerPixel(scale: 1, pointsPerUnit: 0.2),
            style: .gsiStandard
        )
        XCTAssertEqual(Set(frames.map(\.tile.z)), [expected])
    }

    func testCloserZoomUsesADeeperTile() {
        let wide = zoom(pointsPerUnit: 0.05, style: .gsiStandard)
        let close = zoom(pointsPerUnit: 2, style: .gsiStandard)
        XCTAssertGreaterThan(close, wide)
        XCTAssertLessThanOrEqual(close, 18)
        XCTAssertGreaterThanOrEqual(wide, 0)
    }

    func testPaleAndPhotoStayInsideTheirSourceRange() {
        XCTAssertGreaterThanOrEqual(zoom(pointsPerUnit: 0.0001, style: .gsiPale), 5)
        XCTAssertLessThanOrEqual(zoom(pointsPerUnit: 50, style: .gsiPhoto), 18)
        XCTAssertGreaterThanOrEqual(zoom(pointsPerUnit: 0.0001, style: .gsiPhoto), 2)
        let paleFloor = DrawingBaseMap.zoom(latitudeDegrees: 34.88, metersPerPixel: 50_000, style: .gsiPale)
        XCTAssertEqual(paleFloor, 5)
    }

    func testAlignedLocalOriginGetsTheKameyamaMap() throws {
        let shift = Similarity2D(
            scale: 1,
            rotationDegrees: 0,
            translationEasting: kameyama.x,
            translationNorthing: kameyama.y
        )
        let frames = DrawingBaseMap.frames(
            viewCorners: square(center: PlanarPoint(x: 0, y: 0), span: 160),
            zone: 6,
            axis: .cadEastNorth,
            transform: shift,
            composesAxis: false,
            style: .gsiStandard,
            pointsPerUnit: 0.5
        )
        let placed = try XCTUnwrap(DrawingPlacement.geographic(
            PlanarPoint(x: 0, y: 0),
            zone: 6,
            axis: .cadEastNorth,
            transform: shift,
            composesAxis: false
        ))
        let direct = try XCTUnwrap(DrawingPlacement.geographic(
            kameyama,
            zone: 6,
            axis: .cadEastNorth,
            transform: nil
        ))
        XCTAssertEqual(placed.latitudeDegrees, direct.latitudeDegrees, accuracy: 1e-6)
        XCTAssertEqual(placed.longitudeDegrees, direct.longitudeDegrees, accuracy: 1e-6)
        XCTAssertTrue(frames.contains {
            TileMath.bounds(of: $0.tile).contains(latitude: placed.latitudeDegrees, longitude: placed.longitudeDegrees)
        })
    }

    func testTooManyTilesKeepTheCenterAndDropTheRest() throws {
        let frames = DrawingBaseMap.frames(
            viewCorners: square(center: kameyama, span: 400_000),
            zone: 6,
            axis: .cadEastNorth,
            transform: nil,
            composesAxis: false,
            style: .gsiPale,
            pointsPerUnit: 4,
            maxTiles: 4
        )
        XCTAssertLessThanOrEqual(frames.count, 4)
        XCTAssertFalse(frames.isEmpty)
        let geo = try XCTUnwrap(DrawingPlacement.geographic(
            kameyama,
            zone: 6,
            axis: .cadEastNorth,
            transform: nil
        ))
        XCTAssertTrue(frames.contains {
            TileMath.bounds(of: $0.tile).contains(latitude: geo.latitudeDegrees, longitude: geo.longitudeDegrees)
        })
        let ordered = frames.map(\.tile)
        let sorted = ordered.sorted { $0.y < $1.y || ($0.y == $1.y && $0.x < $1.x) }
        XCTAssertEqual(ordered, sorted)
    }

    func testEmptyViewHasNoTiles() {
        let frames = DrawingBaseMap.frames(
            viewCorners: [],
            zone: 6,
            axis: .cadEastNorth,
            transform: nil,
            composesAxis: false,
            style: .gsiStandard,
            pointsPerUnit: 1
        )
        XCTAssertTrue(frames.isEmpty)
    }

    private func zoom(pointsPerUnit: Double, style: BaseMapStyle) -> Int {
        let frames = DrawingBaseMap.frames(
            viewCorners: square(center: kameyama, span: 200),
            zone: 6,
            axis: .cadEastNorth,
            transform: nil,
            composesAxis: false,
            style: style,
            pointsPerUnit: pointsPerUnit
        )
        return frames.map(\.tile.z).max() ?? -1
    }

    private func square(center: PlanarPoint, span: Double) -> [PlanarPoint] {
        let half = span / 2
        return [
            PlanarPoint(x: center.x - half, y: center.y - half),
            PlanarPoint(x: center.x + half, y: center.y - half),
            PlanarPoint(x: center.x - half, y: center.y + half),
            PlanarPoint(x: center.x + half, y: center.y + half)
        ]
    }
}
