import XCTest
@testable import SurveyCore

final class GSIElevationTests: XCTestCase {
    func testLineShowsTheGeoidHeightDifference() {
        let close = GSIElevationText.line(demMeters: 945.8, gnssMeters: 946.2)
        XCTAssertEqual(close?.prefix, "地理院 945.8m")
        XCTAssertEqual(close?.difference, "（差 +0.4m）")
        XCTAssertEqual(close?.highlightDifference, false)
        XCTAssertEqual(close?.spoken, "地理院 945.8m（差 +0.4m）")

        let high = GSIElevationText.line(demMeters: 940.0, gnssMeters: 946.2)
        XCTAssertEqual(high?.difference, "（差 +6.2m）")
        XCTAssertEqual(high?.highlightDifference, true)

        let low = GSIElevationText.line(demMeters: 952.0, gnssMeters: 946.2)
        XCTAssertEqual(low?.difference, "（差 -5.8m）")
        XCTAssertEqual(low?.highlightDifference, true)

        let boundary = GSIElevationText.line(demMeters: 941.2, gnssMeters: 946.2)
        XCTAssertEqual(boundary?.difference, "（差 +5.0m）")
        XCTAssertEqual(boundary?.highlightDifference, false)

        XCTAssertEqual(GSIElevationText.line(demMeters: 945.8, gnssMeters: nil)?.spoken, "地理院 945.8m")
        XCTAssertNil(GSIElevationText.line(demMeters: .nan, gnssMeters: 1))
    }

    func testParseDropsTheNoDataSentinel() throws {
        let found = Data(#"{"elevation":945.8,"hsrc":"10m（標高）"}"#.utf8)
        XCTAssertEqual(GSIElevationAPI.parse(found), 945.8)
        let whole = Data(#"{"elevation":937,"hsrc":"1m（レーザ）"}"#.utf8)
        XCTAssertEqual(GSIElevationAPI.parse(whole), 937)
        let text = Data(#"{"elevation":"12.5","hsrc":"5m"}"#.utf8)
        XCTAssertEqual(GSIElevationAPI.parse(text), 12.5)
        let missing = Data(#"{"elevation":"-----","hsrc":"-----"}"#.utf8)
        XCTAssertNil(GSIElevationAPI.parse(missing))
        XCTAssertNil(GSIElevationAPI.parse(Data("not json".utf8)))
    }

    func testURLUsesTheElevationAPI() throws {
        let url = try XCTUnwrap(GSIElevationAPI.url(latitudeDegrees: 36.77450, longitudeDegrees: 139.20081))
        XCTAssertEqual(url.host, "cyberjapandata2.gsi.go.jp")
        XCTAssertEqual(url.path, "/general/dem/scripts/getelevation.php")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "lat" }?.value, "36.774500")
        XCTAssertEqual(items.first { $0.name == "lon" }?.value, "139.200810")
        XCTAssertEqual(items.first { $0.name == "outtype" }?.value, "JSON")
        XCTAssertNil(GSIElevationAPI.url(latitudeDegrees: 120, longitudeDegrees: 0))
    }

    func testRequestsWaitForTenMetersOrThirtySeconds() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let origin = (latitude: 36.77450, longitude: 139.20081)
        XCTAssertTrue(GSIElevationPolicy.shouldRequest(last: nil, latitudeDegrees: origin.latitude, longitudeDegrees: origin.longitude, now: start))
        let last = GSIElevationPolicy.Fix(latitudeDegrees: origin.latitude, longitudeDegrees: origin.longitude, at: start)
        let near = try shift(origin, meters: 9)
        let far = try shift(origin, meters: 11)
        XCTAssertFalse(GSIElevationPolicy.shouldRequest(last: last, latitudeDegrees: near.latitude, longitudeDegrees: near.longitude, now: start.addingTimeInterval(29)))
        XCTAssertTrue(GSIElevationPolicy.shouldRequest(last: last, latitudeDegrees: far.latitude, longitudeDegrees: far.longitude, now: start.addingTimeInterval(1)))
        XCTAssertTrue(GSIElevationPolicy.shouldRequest(last: last, latitudeDegrees: origin.latitude, longitudeDegrees: origin.longitude, now: start.addingTimeInterval(30)))
    }

    func testCacheReusesARecentNearbySample() throws {
        var cache = GSIElevationCache()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let origin = (latitude: 36.77450, longitude: 139.20081)
        cache.remember(GSIElevationCache.Entry(
            latitudeDegrees: origin.latitude,
            longitudeDegrees: origin.longitude,
            meters: 945.8,
            fetchedAt: start
        ))
        let near = try shift(origin, meters: 9)
        let far = try shift(origin, meters: 11)
        XCTAssertEqual(cache.fresh(latitudeDegrees: near.latitude, longitudeDegrees: near.longitude, now: start.addingTimeInterval(10))?.meters, 945.8)
        XCTAssertNil(cache.fresh(latitudeDegrees: far.latitude, longitudeDegrees: far.longitude, now: start.addingTimeInterval(10)))
        XCTAssertNil(cache.fresh(latitudeDegrees: origin.latitude, longitudeDegrees: origin.longitude, now: start.addingTimeInterval(30)))
        cache.noteRequest(latitudeDegrees: origin.latitude, longitudeDegrees: origin.longitude, at: start)
        XCTAssertFalse(cache.shouldRequest(latitudeDegrees: near.latitude, longitudeDegrees: near.longitude, now: start.addingTimeInterval(10)))
    }

    private func shift(_ origin: (latitude: Double, longitude: Double), meters: Double) throws -> (latitude: Double, longitude: Double) {
        try XCTUnwrap(GRS80Geodesic.direct(
            latitude: origin.latitude,
            longitude: origin.longitude,
            azimuthDegrees: 0,
            distanceMeters: meters
        ))
    }
}
