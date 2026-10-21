import XCTest
@testable import SurveyCore

final class CoordinateAndMapTests: XCTestCase {
    func testMockCoordinatesAndNotes() {
        let position = SimulatedPositionSource.iphonePreview().script[0].position!
        XCTAssertEqual(CoordinateText.latitude(35.68123), "35.68123")
        XCTAssertEqual(CoordinateText.longitude(139.76712), "139.76712")
        XCTAssertEqual(CoordinateText.ellipsoidalHeight(12.4), "楕円体高 12.4m")
        XCTAssertEqual(CoordinateText.ellipsoidalHeight(nil), "楕円体高 —")
        let line = CoordinateText.currentLocationLine(position)
        XCTAssertTrue(line.hasPrefix("35.68123, 139.76712"))
        XCTAssertTrue(line.contains("標高"))
        XCTAssertTrue(line.contains("楕円体高"))
        XCTAssertTrue(line.contains(JapanGeoid.modelName))
        XCTAssertEqual(CoordinateText.previewNote, "JGD2024・下見／概略用")
        XCTAssertEqual(CoordinateText.storageNote, "保持は WGS84/ITRF。変換は出口で一回")
        XCTAssertEqual(CoordinateText.accuracyMeters(3.2), "±3.2m")
        XCTAssertEqual(CoordinateText.accuracyMeters(0.05), "±5cm")
        XCTAssertEqual(CoordinateText.accuracyMeters(0.02), "±2cm")
        XCTAssertFalse(CoordinateText.latitude(-139.76712).contains(","))
    }

    func testDistanceAndViewportSpan() {
        let north = GeoDistance.meters(latitude1: 0, longitude1: 0, latitude2: 1, longitude2: 0)
        XCTAssertEqual(north, 111_194.9, accuracy: 1)
        XCTAssertEqual(GeoDistance.meters(latitude1: 35, longitude1: 139, latitude2: 35, longitude2: 139), 0, accuracy: 0.001)
        XCTAssertEqual(MapViewportPolicy.spanMeters(forHorizontalAccuracy: 3.2), 80, accuracy: 0.001)
        XCTAssertEqual(MapViewportPolicy.spanMeters(forHorizontalAccuracy: 100), 800, accuracy: 0.001)
        XCTAssertEqual(MapViewportPolicy.spanMeters(forHorizontalAccuracy: 2_000), 8_000, accuracy: 0.001)
        XCTAssertEqual(MapViewportPolicy.spanMeters(forHorizontalAccuracy: 0.02), 80, accuracy: 0.001)
        XCTAssertEqual(MapViewportPolicy.spanMeters(forHorizontalAccuracy: -1), 400, accuracy: 0.001)
    }

    func testFollowingViewportFramesThePoint() {
        let position = samplePosition(accuracy: 3.2)
        let viewport = MapViewportPolicy.following(position)
        XCTAssertEqual(viewport.centerLatitude, position.latitudeDegrees, accuracy: 1e-9)
        XCTAssertEqual(viewport.groundSpanMeters, 80, accuracy: 0.05)
        XCTAssertGreaterThan(viewport.longitudeDelta, viewport.latitudeDelta)
        XCTAssertTrue(viewport.bounds.contains(latitude: position.latitudeDegrees, longitude: position.longitudeDegrees))
    }

    func testCameraIgnoresSmallMoves() {
        var camera = MapCameraFollow()
        XCTAssertEqual(camera.viewport.centerLatitude, MapViewportPolicy.japanOverview.centerLatitude, accuracy: 0.001)
        let first = samplePosition(latitude: 35.68123, accuracy: 3.2)
        let locked = camera.update(for: first)
        XCTAssertEqual(locked.centerLatitude, 35.68123, accuracy: 1e-9)
        let nearby = samplePosition(latitude: 35.68123 + 0.00005, accuracy: 3.2)
        XCTAssertEqual(camera.update(for: nearby).centerLatitude, locked.centerLatitude, accuracy: 1e-12)
        let far = samplePosition(latitude: 35.68123 + 0.001, accuracy: 3.2)
        XCTAssertEqual(camera.update(for: far).centerLatitude, far.latitudeDegrees, accuracy: 1e-9)
    }

    func testCameraReframesWhenAccuracyChangesALot() {
        var camera = MapCameraFollow()
        _ = camera.update(for: samplePosition(accuracy: 3.2))
        let wider = samplePosition(accuracy: 20)
        let viewport = camera.update(for: wider)
        XCTAssertEqual(viewport.latitudeDelta, MapViewportPolicy.following(wider).latitudeDelta, accuracy: 1e-12)
        XCTAssertEqual(viewport.groundSpanMeters, 160, accuracy: 0.2)
    }

    func testZoomLevelFromLongitudeSpan() {
        XCTAssertEqual(MapZoom.level(longitudeDelta: 360, screenWidthPoints: 256), 0)
        XCTAssertEqual(MapZoom.level(longitudeDelta: 360.0 / 32_768.0, screenWidthPoints: 256), 15)
        XCTAssertEqual(MapZoom.level(longitudeDelta: 0, screenWidthPoints: 390), 0)
    }
}
