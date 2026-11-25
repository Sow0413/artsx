import XCTest
@testable import SurveyCore

final class RawCaptureTests: XCTestCase {
    func testValgetAndValsetFramesMatchTheRAMOnlyBytes() {
        XCTAssertEqual(
            UBXConfig.valgetRAM(),
            Data([
                0xB5, 0x62, 0x06, 0x8B, 0x10, 0x00,
                0x00, 0x00, 0x00, 0x00,
                0x01, 0x00, 0x21, 0x30,
                0xA5, 0x02, 0x91, 0x20,
                0x32, 0x02, 0x91, 0x20,
                0x30, 0x3B
            ])
        )
        XCTAssertEqual(
            UBXConfig.enableRecording(),
            Data([
                0xB5, 0x62, 0x06, 0x8A, 0x14, 0x00,
                0x00, 0x01, 0x00, 0x00,
                0x01, 0x00, 0x21, 0x30, 0xE8, 0x03,
                0xA5, 0x02, 0x91, 0x20, 0x01,
                0x32, 0x02, 0x91, 0x20, 0x01,
                0x21, 0xF8
            ])
        )
        XCTAssertEqual(
            UBXConfig.valsetRAM(rateMeas: 143, rawx: 0, sfrbx: 0),
            Data([
                0xB5, 0x62, 0x06, 0x8A, 0x14, 0x00,
                0x00, 0x01, 0x00, 0x00,
                0x01, 0x00, 0x21, 0x30, 0x8F, 0x00,
                0xA5, 0x02, 0x91, 0x20, 0x00,
                0x32, 0x02, 0x91, 0x20, 0x00,
                0xC3, 0xA4
            ])
        )
        XCTAssertNotEqual(UBXConfig.enableRecording()[2], 0x04)
        XCTAssertNotEqual(UBXConfig.enableRecording()[3], 0x09)
        XCTAssertEqual(UBXConfig.enableRecording()[7], 0x01)
    }

    func testRestoreRetriesThreeTimesThenMarksUnverified() {
        var session = RawCaptureSession()
        XCTAssertEqual(session.begin(), UBXConfig.valgetRAM())
        let originals = valget(rate: 143, rawx: 0, sfrbx: 0)
        XCTAssertEqual(session.onFrame(originals), UBXConfig.enableRecording())
        XCTAssertEqual(session.originals, UBXConfig.Values(rateMeas: 143, rawx: 0, sfrbx: 0))
        XCTAssertEqual(session.phase, .recording)

        let restore = UBXConfig.valsetRAM(rateMeas: 143, rawx: 0, sfrbx: 0)
        XCTAssertEqual(session.end(), restore)
        XCTAssertEqual(session.onFrame(ack()), UBXConfig.valgetRAM())
        XCTAssertEqual(session.onFrame(valget(rate: 1000, rawx: 1, sfrbx: 1)), restore)
        XCTAssertEqual(session.onFrame(ack()), UBXConfig.valgetRAM())
        XCTAssertEqual(session.onFrame(valget(rate: 1000, rawx: 1, sfrbx: 1)), restore)
        XCTAssertEqual(session.onFrame(ack()), UBXConfig.valgetRAM())
        XCTAssertNil(session.onFrame(valget(rate: 1000, rawx: 1, sfrbx: 1)))
        XCTAssertTrue(session.restoreUnverified)
        XCTAssertEqual(session.phase, .finished)

        var again = RawCaptureSession()
        _ = again.begin()
        _ = again.onFrame(originals)
        _ = again.end()
        _ = again.onFrame(ack())
        XCTAssertNil(again.onFrame(valget(rate: 143, rawx: 0, sfrbx: 0)))
        XCTAssertFalse(again.restoreUnverified)
    }

    private func ack() -> Data {
        UBXConfig.frame(klass: 0x05, id: 0x01, payload: Data([0x06, 0x8A]))
    }

    private func valget(rate: UInt16, rawx: UInt8, sfrbx: UInt8) -> Data {
        var payload = Data([0x00, 0x00, 0x00, 0x00])
        payload.append(UBXConfig.key(UBXConfig.rateMeasKey))
        payload.append(UInt8(rate & 0xFF))
        payload.append(UInt8((rate >> 8) & 0xFF))
        payload.append(UBXConfig.key(UBXConfig.rawxUART1Key))
        payload.append(rawx)
        payload.append(UBXConfig.key(UBXConfig.sfrbxUART1Key))
        payload.append(sfrbx)
        return UBXConfig.frame(klass: 0x06, id: 0x8B, payload: payload)
    }
}
