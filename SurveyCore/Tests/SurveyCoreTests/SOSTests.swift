import XCTest
@testable import SurveyCore

final class SOSTests: XCTestCase {
    func testRightFrontOneHundredTwentyMeters() throws {
        let pointer = try announce(azimuth: 45, distance: 120, age: 2, heading: 0, course: 90, facing: .machine)
        XCTAssertEqual(pointer.text, "右まえ120m 佐藤 SOS")
        XCTAssertTrue(pointer.known)
        XCTAssertEqual(pointer.relativeDegrees ?? 999, 45, accuracy: 1)
        XCTAssertEqual(pointer.distanceMeters ?? 0, 120, accuracy: 0.5)
    }

    func testOperatorUsesTheMachineHeadingNotTheCourse() throws {
        let machine = try announce(azimuth: 45, distance: 120, age: 1, heading: 0, course: 225, facing: .machine)
        let own = try announce(azimuth: 45, distance: 120, age: 1, heading: 0, course: 225, facing: .own)
        XCTAssertEqual(machine.text, "右まえ120m 佐藤 SOS")
        XCTAssertEqual(own.sector, "うしろ")
    }

    func testStaleOrMissingPositionIsUnknown() throws {
        let stale = try announce(azimuth: 45, distance: 120, age: 31, heading: 0, course: nil, facing: .own)
        XCTAssertEqual(stale.text, "方向不明 佐藤 SOS")
        XCTAssertFalse(stale.known)
        let missing = SOSCall.pointer(
            name: "佐藤",
            latitude: nil,
            longitude: nil,
            sentAt: date(0),
            selfLatitude: 35.68,
            selfLongitude: 139.76,
            courseDegrees: 0,
            headingDegrees: 0,
            facing: .own,
            now: date(0)
        )
        XCTAssertEqual(missing.text, "方向不明 佐藤 SOS")
    }

    func testPositionKeepsFlowingButNotEveryInstant() {
        var desk = SOSDesk()
        let id = desk.begin(at: date(0))
        XCTAssertNotNil(id)
        XCTAssertNil(desk.begin(at: date(1)))
        let first = desk.beacon(deviceID: "self", name: "佐藤", channelID: "site", latitude: 35, longitude: 139, at: date(0))
        XCTAssertEqual(first?.active, true)
        XCTAssertNil(desk.beacon(deviceID: "self", name: "佐藤", channelID: "site", latitude: 35.1, longitude: 139, at: date(1)))
        let second = desk.beacon(deviceID: "self", name: "佐藤", channelID: "site", latitude: 35.2, longitude: 139, at: date(2))
        XCTAssertEqual(second?.latitudeDegrees, 35.2)
        XCTAssertEqual(second?.id, first?.id)
    }

    func testStoppingBeaconIsInactive() {
        var desk = SOSDesk()
        _ = desk.begin(at: date(0))
        let stop = desk.end(deviceID: "self", name: "佐藤", channelID: "site", latitude: 35, longitude: 139, at: date(3))
        XCTAssertEqual(stop?.active, false)
        XCTAssertNil(desk.beacon(deviceID: "self", name: "佐藤", channelID: "site", latitude: 35, longitude: 139, at: date(4)))
    }

    func testSpeechRepeatsOnANewSectorOrAfterTheGap() throws {
        var desk = SOSDesk()
        let origin = (latitude: 35.68, longitude: 139.76)
        let side = try placed(from: origin, azimuth: 45, distance: 120)
        let behind = try placed(from: origin, azimuth: 180, distance: 120)
        let first = beacon(side, at: date(0))
        let heard = desk.hear(first, selfLatitude: origin.latitude, selfLongitude: origin.longitude, courseDegrees: nil, headingDegrees: 0, facing: .own, now: date(0))
        XCTAssertTrue(heard.speak)
        XCTAssertEqual(heard.pointer.text, "右まえ120m 佐藤 SOS")
        let again = desk.hear(beacon(side, at: date(5)), selfLatitude: origin.latitude, selfLongitude: origin.longitude, courseDegrees: nil, headingDegrees: 0, facing: .own, now: date(5))
        XCTAssertFalse(again.speak)
        let turned = desk.hear(beacon(behind, at: date(6)), selfLatitude: origin.latitude, selfLongitude: origin.longitude, courseDegrees: nil, headingDegrees: 0, facing: .own, now: date(6))
        XCTAssertTrue(turned.speak)
        XCTAssertEqual(turned.pointer.sector, "うしろ")
        let later = desk.hear(beacon(behind, at: date(22)), selfLatitude: origin.latitude, selfLongitude: origin.longitude, courseDegrees: nil, headingDegrees: 0, facing: .own, now: date(22))
        XCTAssertTrue(later.speak)
    }

    func testOutOfRangeUsesNearbyAndInRangeUsesTheRelay() {
        XCTAssertEqual(SOSPath.choose(relayReachable: false), .nearby)
        XCTAssertEqual(SOSPath.choose(relayReachable: true), .relay)
    }

    func testANearbyBeaconIsForwardedOnceWhenTheRelayReturns() {
        var desk = SOSDesk()
        let note = beacon((latitude: 35, longitude: 139), at: date(0))
        XCTAssertFalse(desk.shouldForward(note, arrived: .nearby, relayReachable: false))
        XCTAssertTrue(desk.shouldForward(note, arrived: .nearby, relayReachable: true))
        XCTAssertFalse(desk.shouldForward(note, arrived: .nearby, relayReachable: true))
        XCTAssertFalse(desk.shouldForward(note, arrived: .relay, relayReachable: true))
        let relay = SOSRelay(reachable: false)
        XCTAssertEqual(relay.submit(SOSPacket(beacon: note)), .unreachable)
        relay.isReachable = true
        relay.flush()
        XCTAssertEqual(relay.sent.first?.beacon, note)
    }

    func testComingReplyReturnsToTheSenderOnly() {
        var desk = SOSDesk()
        let id = desk.begin(at: date(0))!
        let note = desk.beacon(deviceID: "sato", name: "佐藤", channelID: "site", latitude: 35, longitude: 139, at: date(0))!
        let reply = desk.reply(to: note, fromDeviceID: "tanaka", fromName: "田中", at: date(1))
        XCTAssertEqual(reply.text, "向かう")
        XCTAssertFalse(desk.hearReply(reply, selfDeviceID: "other", beaconID: id))
        XCTAssertTrue(desk.hearReply(reply, selfDeviceID: "sato", beaconID: id))
        XCTAssertFalse(desk.hearReply(reply, selfDeviceID: "sato", beaconID: id))
        XCTAssertEqual(desk.helperLine, "田中が向かっています")
    }

    func testTheReportSaysSOSAndNotACallTo119() {
        let record = IncidentRecord(
            id: UUID(),
            projectID: "project",
            projectName: "現場",
            occurredAt: date(0),
            sealedAt: date(60),
            trigger: .sos,
            parties: [],
            track: [],
            machineRadiusMeters: 9,
            work: IncidentWork(kind: "SOS", name: "SOS"),
            accuracyMeters: 4,
            stageLabel: "段階0",
            solutionLabel: "単独",
            speeches: [],
            radio: [],
            drawingFile: "図面.png",
            mapFile: "地図.png",
            photoFile: nil,
            voiceMemoFile: nil,
            notice: SafetyNotice.text
        )
        let lines = IncidentReport.lines(record)
        XCTAssertEqual(record.trigger.label, "SOS")
        XCTAssertTrue(lines.contains("作業 SOS SOS"))
        XCTAssertTrue(lines.contains(SOSCall.disclaimer))
        XCTAssertEqual(SOSCall.disclaimer, "このアプリは119通報の代わりではない")
    }

    func testLinkFrameCarriesTheBeacon() throws {
        let note = beacon((latitude: 36, longitude: 139), at: date(0))
        let frame = LinkFrame(kind: .sos, sos: SOSPacket(beacon: note))
        let data = try JSONEncoder().encode(frame)
        let decoded = try JSONDecoder().decode(LinkFrame.self, from: data)
        XCTAssertEqual(decoded.sos?.beacon, note)
    }

    private func announce(
        azimuth: Double,
        distance: Double,
        age: TimeInterval,
        heading: Double?,
        course: Double?,
        facing: TalkFacing
    ) throws -> SOSPointer {
        let origin = (latitude: 35.68, longitude: 139.76)
        let target = try placed(from: origin, azimuth: azimuth, distance: distance)
        return SOSCall.pointer(
            name: "佐藤",
            latitude: target.latitude,
            longitude: target.longitude,
            sentAt: date(-age),
            selfLatitude: origin.latitude,
            selfLongitude: origin.longitude,
            courseDegrees: course,
            headingDegrees: heading,
            facing: facing,
            now: date(0)
        )
    }

    private func placed(
        from origin: (latitude: Double, longitude: Double),
        azimuth: Double,
        distance: Double
    ) throws -> (latitude: Double, longitude: Double) {
        try XCTUnwrap(GRS80Geodesic.direct(
            latitude: origin.latitude,
            longitude: origin.longitude,
            azimuthDegrees: azimuth,
            distanceMeters: distance
        ))
    }

    private func beacon(_ point: (latitude: Double, longitude: Double), at: Date) -> SOSBeacon {
        SOSBeacon(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            at: at,
            deviceID: "sato",
            name: "佐藤",
            latitudeDegrees: point.latitude,
            longitudeDegrees: point.longitude,
            channelID: "site",
            active: true
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + seconds)
    }
}
