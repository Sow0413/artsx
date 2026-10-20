import XCTest
@testable import SurveyCore

final class RadioTests: XCTestCase {
    func testProjectIsTheChannel() {
        let first = RadioChannel.project(id: "現場A", name: "北線")
        let again = RadioChannel.project(id: "現場A", name: "別名")
        let other = RadioChannel.project(id: "現場B", name: "北線")
        XCTAssertEqual(first.uuid, again.uuid)
        XCTAssertNotEqual(first.uuid, other.uuid)
        let existing = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        XCTAssertEqual(RadioChannel.project(id: existing.uuidString, name: "路線").uuid, existing)
    }

    func testRelayWinsAndNearbyCoversTheGap() {
        let relay = P510RelayStub(reachable: true)
        let nearby = NearbyMesh()
        let desk = desk(relay: relay, nearby: nearby)
        desk.join(channel)
        let begun = desk.beginTalking(at: date(1), station: stamp)
        XCTAssertEqual(begun?.path, .relay)
        XCTAssertEqual(relay.sent.map(\.kind), [.begin])
        XCTAssertTrue(nearby.sent.isEmpty)
        desk.addAudio(Data([1, 2, 3]), at: date(2))
        let ended = desk.endTalking(at: date(3))
        XCTAssertEqual(ended?.audioByteCount, 3)
        XCTAssertEqual(ended?.station, stamp)
        XCTAssertEqual(ended?.delivered, true)
        XCTAssertEqual(relay.sent.map(\.kind), [.begin, .audio, .end])

        relay.isReachable = false
        let local = desk.beginTalking(at: date(4), station: stamp)
        XCTAssertEqual(local?.path, .nearby)
        XCTAssertEqual(nearby.sent.map(\.kind), [.begin])
        _ = desk.endTalking(at: date(5))
    }

    func testBothPathsDownStillKeepTheUtterance() {
        let desk = desk(relay: P510RelayStub(reachable: false), nearby: NearbyMesh(reachable: false))
        desk.join(channel)
        let begun = desk.beginTalking(at: date(1), station: stamp)
        XCTAssertNil(begun?.path)
        XCTAssertEqual(begun?.delivered, false)
        let ended = desk.endTalking(at: date(2))
        XCTAssertEqual(ended?.delivered, false)
        XCTAssertEqual(desk.utterances.count, 1)
        XCTAssertEqual(desk.phase, .listening)
    }

    func testStationIsOptionalAndHalfDuplexBlocksTheButton() {
        let relay = P510RelayStub(reachable: true)
        let desk = desk(relay: relay, nearby: NearbyMesh(reachable: false))
        desk.attachStation = false
        desk.join(channel)
        let quiet = desk.beginTalking(at: date(1), station: stamp)
        XCTAssertNil(quiet?.station)
        XCTAssertNil(relay.sent.first?.station)
        _ = desk.endTalking(at: date(2))

        let other = RadioPacket(
            kind: .begin,
            utteranceID: UUID(),
            channel: channel,
            speaker: "相手",
            sentAt: date(3),
            station: stamp
        )
        desk.receive(other)
        XCTAssertEqual(desk.hearingSpeaker, "相手")
        XCTAssertNil(desk.beginTalking(at: date(4), station: nil))
        desk.receive(RadioPacket(
            kind: .end,
            utteranceID: other.utteranceID,
            channel: channel,
            speaker: "相手",
            sentAt: date(5),
            station: nil
        ))
        XCTAssertNil(desk.hearingSpeaker)
        XCTAssertEqual(desk.utterances.last?.station?.text, "No.23+5.0m 左 3.2m")
        XCTAssertNotNil(desk.beginTalking(at: date(6), station: nil))
    }

    func testNearbyPeersHearOnlyTheSameProject() {
        let leftMesh = NearbyMesh()
        let rightMesh = NearbyMesh()
        let strangerMesh = NearbyMesh()
        leftMesh.peers = [rightMesh, strangerMesh]
        let left = desk(relay: P510RelayStub(reachable: false), nearby: leftMesh)
        let right = desk(speaker: "右", relay: P510RelayStub(reachable: false), nearby: rightMesh)
        let stranger = desk(speaker: "別", relay: P510RelayStub(reachable: false), nearby: strangerMesh)
        left.join(channel)
        right.join(channel)
        stranger.join(RadioChannel.project(id: "別現場", name: "別"))
        _ = left.beginTalking(at: date(1), station: stamp)
        XCTAssertEqual(right.hearingSpeaker, "左")
        XCTAssertNil(stranger.hearingSpeaker)
        left.addAudio(Data([9, 9]), at: date(2))
        _ = left.endTalking(at: date(3))
        XCTAssertNil(right.hearingSpeaker)
        XCTAssertEqual(right.utterances.last?.station, stamp)
        XCTAssertEqual(right.utterances.last?.audioByteCount, 2)
        XCTAssertTrue(stranger.utterances.isEmpty)
    }

    func testUtteranceLogRoundTrips() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let project = try ProjectStore.create(name: "無線現場", at: root, now: date(0))
        let utterance = RadioUtterance(
            channel: channel,
            speaker: "左",
            startedAt: date(1),
            endedAt: date(2),
            path: .nearby,
            delivered: true,
            station: stamp,
            audioByteCount: 4,
            incoming: false
        )
        try RadioLog.append(utterance, projectName: project.name, at: root)
        let loaded = RadioLog.load(projectName: project.name, at: root)
        XCTAssertEqual(loaded, [utterance])
        XCTAssertTrue(RadioLog.load(projectName: "無い", at: root).isEmpty)
    }

    private let channel = RadioChannel.project(id: "現場A", name: "北線")
    private let stamp = RadioStationStamp(text: "No.23+5.0m 左 3.2m", latitudeDegrees: 35.1, longitudeDegrees: 139.2)

    private func desk(
        speaker: String = "左",
        relay: P510RelayStub,
        nearby: NearbyMesh
    ) -> RadioDesk {
        RadioDesk(speaker: speaker, relay: relay, nearby: nearby)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
