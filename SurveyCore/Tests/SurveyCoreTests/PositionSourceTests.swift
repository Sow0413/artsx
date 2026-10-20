import XCTest
@testable import SurveyCore

final class PositionSourceTests: XCTestCase {
    func testSimulatedScriptPlaysOnceInOrder() async {
        let first = PositionReading(position: samplePosition(latitude: 35), availability: .available)
        let second = PositionReading(position: samplePosition(latitude: 36), availability: .available)
        let source = SimulatedPositionSource(script: [first, second], receiver: .iphoneGPS, stage: .iphone)
        var iterator = source.readings.makeAsyncIterator()
        source.start()
        source.start()
        let readFirst = await iterator.next()
        let readSecond = await iterator.next()
        let sentinel = PositionReading(position: nil, availability: .unavailable)
        source.emit(sentinel)
        let readThird = await iterator.next()
        XCTAssertEqual(readFirst, first)
        XCTAssertEqual(readSecond, second)
        XCTAssertEqual(readThird, sentinel)
        XCTAssertEqual(source.stage, .iphone)
        XCTAssertEqual(source.receiver, .iphoneGPS)
    }

    func testIPhoneFactoryIsStageZero() {
        let position = IPhonePosition.make(
            latitudeDegrees: 35.0,
            longitudeDegrees: 139.0,
            ellipsoidalHeightMeters: nil,
            horizontalAccuracyMeters: 4,
            verticalAccuracyMeters: nil,
            timestamp: PreviewClock.instant
        )
        XCTAssertEqual(position.stage, .iphone)
        XCTAssertEqual(position.fixQuality, .standalone)
        XCTAssertEqual(position.receiver, .iphoneGPS)
        XCTAssertEqual(position.frame, .wgs84ITRF)
        XCTAssertNil(position.ellipsoidalHeightMeters)
    }
}
