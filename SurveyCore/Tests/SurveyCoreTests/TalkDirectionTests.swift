import XCTest
@testable import SurveyCore

final class TalkDirectionTests: XCTestCase {
    func testMachineFacingSaysLeftFrontEightyMeters() throws {
        let pointer = try pointer(facing: .machine, age: 5, course: 90, heading: 0)
        XCTAssertEqual(pointer.text, "左まえ 80m 田中")
        XCTAssertTrue(pointer.known)
        XCTAssertEqual(pointer.reference, "重機")
        XCTAssertEqual(pointer.relativeDegrees ?? 999, -30, accuracy: 1)
        XCTAssertEqual(pointer.distanceMeters ?? 0, 80, accuracy: 0.5)
    }

    func testOwnFacingUsesCourseBeforeTheCompass() throws {
        let pointer = try pointer(facing: .own, age: 5, course: 90, heading: 0)
        XCTAssertEqual(pointer.text, "左うしろ 80m 田中")
        XCTAssertEqual(pointer.reference, "進行")
    }

    func testMachineFallsBackToCourseWhenTheHeadingIsMissing() throws {
        let pointer = try pointer(facing: .machine, age: 5, course: 0, heading: nil)
        XCTAssertEqual(pointer.text, "左まえ 80m 田中")
        XCTAssertEqual(pointer.reference, "進行")
    }

    func testStaleOrMissingPositionIsUnknown() throws {
        let stale = try pointer(facing: .machine, age: 31, course: 0, heading: 0)
        XCTAssertEqual(stale.text, "方向不明 田中")
        XCTAssertFalse(stale.known)
        XCTAssertNil(stale.relativeDegrees)

        let missing = TalkDirection.pointer(
            speaker: "田中",
            fixes: [],
            selfLatitude: 35.68,
            selfLongitude: 139.76,
            courseDegrees: 0,
            headingDegrees: 0,
            facing: .own,
            now: date(0)
        )
        XCTAssertEqual(missing.text, "方向不明 田中")

        let noSelf = try pointer(facing: .own, age: 1, course: 0, heading: 0, includeSelf: false)
        XCTAssertEqual(noSelf.text, "方向不明 田中")
    }

    func testNoFacingIsUnknownEvenWhenTheFixIsFresh() throws {
        let pointer = try pointer(facing: .machine, age: 1, course: nil, heading: nil)
        XCTAssertEqual(pointer.text, "方向不明 田中")
        XCTAssertFalse(pointer.known)
    }

    func testTheNewestFixWinsWhenNamesRepeat() throws {
        let origin = (latitude: 35.68, longitude: 139.76)
        let ahead = try XCTUnwrap(GRS80Geodesic.direct(
            latitude: origin.latitude,
            longitude: origin.longitude,
            azimuthDegrees: 0,
            distanceMeters: 40
        ))
        let side = try XCTUnwrap(GRS80Geodesic.direct(
            latitude: origin.latitude,
            longitude: origin.longitude,
            azimuthDegrees: 330,
            distanceMeters: 80
        ))
        let pointer = TalkDirection.pointer(
            speaker: "田中",
            fixes: [
                fix("田中", latitude: ahead.latitude, longitude: ahead.longitude, at: date(-20)),
                fix("田中", latitude: side.latitude, longitude: side.longitude, at: date(-2))
            ],
            selfLatitude: origin.latitude,
            selfLongitude: origin.longitude,
            courseDegrees: nil,
            headingDegrees: 0,
            facing: .machine,
            now: date(0)
        )
        XCTAssertEqual(pointer.text, "左まえ 80m 田中")
    }

    func testSpacePutsFrontAheadAndRightToTheRight() {
        let front = TalkDirection.space(relativeDegrees: 0, distanceMeters: 80)
        XCTAssertEqual(front.x, 0, accuracy: 0.001)
        XCTAssertEqual(front.y, 0)
        XCTAssertLessThan(front.z, 0)

        let right = TalkDirection.space(relativeDegrees: 90, distanceMeters: 80)
        XCTAssertGreaterThan(right.x, 0)
        XCTAssertEqual(right.z, 0, accuracy: 0.001)

        let leftFront = TalkDirection.space(relativeDegrees: -45, distanceMeters: 80)
        XCTAssertLessThan(leftFront.x, 0)
        XCTAssertLessThan(leftFront.z, 0)

        let near = TalkDirection.space(relativeDegrees: 0, distanceMeters: 10)
        let far = TalkDirection.space(relativeDegrees: 0, distanceMeters: 400)
        XCTAssertLessThan(abs(near.z), abs(far.z))
    }

    private func pointer(
        facing: TalkFacing,
        age: TimeInterval,
        course: Double?,
        heading: Double?,
        includeSelf: Bool = true
    ) throws -> TalkPointer {
        let origin = (latitude: 35.68, longitude: 139.76)
        let target = try XCTUnwrap(GRS80Geodesic.direct(
            latitude: origin.latitude,
            longitude: origin.longitude,
            azimuthDegrees: 330,
            distanceMeters: 80
        ))
        return TalkDirection.pointer(
            speaker: "田中",
            fixes: [fix("田中", latitude: target.latitude, longitude: target.longitude, at: date(-age))],
            selfLatitude: includeSelf ? origin.latitude : nil,
            selfLongitude: includeSelf ? origin.longitude : nil,
            courseDegrees: course,
            headingDegrees: heading,
            facing: facing,
            now: date(0)
        )
    }

    private func fix(_ name: String, latitude: Double, longitude: Double, at: Date) -> CrewFix {
        CrewFix(
            id: name,
            name: name,
            role: .worker,
            latitudeDegrees: latitude,
            longitudeDegrees: longitude,
            horizontalAccuracyMeters: 4,
            workRadiusMeters: nil,
            sentAt: at
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + seconds)
    }
}
