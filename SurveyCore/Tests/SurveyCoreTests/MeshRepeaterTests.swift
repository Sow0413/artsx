import XCTest
@testable import SurveyCore

final class MeshRepeaterTests: XCTestCase {
    func testSOSLeavesBeforeOlderVoiceAndAFullQueueKeepsTheSOS() {
        var desk = BucketDesk(selfID: "relay")
        let project = "field"
        let voice = BucketRelay.envelope(
            projectID: project,
            kind: .radio,
            deviceID: "relay",
            at: date(0),
            radio: radioPacket(at: date(0))
        )
        let sos = BucketRelay.envelope(
            projectID: project,
            kind: .sos,
            deviceID: "relay",
            at: date(5),
            sos: SOSPacket(beacon: SOSBeacon(
                id: UUID(),
                at: date(5),
                deviceID: "sato",
                name: "佐藤",
                latitudeDegrees: 36,
                longitudeDegrees: 139,
                channelID: project,
                active: true
            ))
        )
        XCTAssertNotNil(desk.originate(voice, now: date(0)))
        XCTAssertNotNil(desk.originate(sos, now: date(5)))
        XCTAssertEqual(desk.forwardable(now: date(6)).map(\.kind), [.sos, .radio])

        var crowded = BucketDesk(selfID: "relay")
        for index in 0..<BucketDesk.heldCap {
            let position = BucketRelay.envelope(
                projectID: project,
                kind: .position,
                deviceID: "relay",
                at: date(TimeInterval(index)),
                position: DisasterPosition(deviceID: "a", name: "佐藤", at: date(TimeInterval(index)), latitudeDegrees: 36, longitudeDegrees: 139)
            )
            XCTAssertNotNil(crowded.originate(position, now: date(TimeInterval(index))))
        }
        XCTAssertNotNil(crowded.originate(sos, now: date(80)))
        XCTAssertEqual(crowded.heldCount, BucketDesk.heldCap)
        XCTAssertEqual(crowded.forwardable(now: date(80)).first?.kind, .sos)
    }

    func testARepeatedVoiceIsDroppedAndALargeClipIsNotForwarded() {
        var desk = BucketDesk(selfID: "b")
        let packet = radioPacket(at: date(0))
        let envelope = BucketRelay.envelope(projectID: "field", kind: .radio, deviceID: "a", at: date(0), radio: packet)
        guard case .forward = desk.receive(envelope, now: date(1), projectID: "field") else {
            return XCTFail("最初は渡す")
        }
        XCTAssertEqual(desk.receive(envelope, now: date(2), projectID: "field"), .drop(.seen))
        var huge = packet
        huge.audio = Data(repeating: 1, count: BucketRelay.audioCap + 1)
        let fat = BucketRelay.envelope(projectID: "field", kind: .radio, deviceID: "a", at: date(3), radio: huge)
        XCTAssertEqual(desk.receive(fat, now: date(3), projectID: "field"), .drop(.tooBig))
        XCTAssertEqual(desk.receive(fat, now: date(4), projectID: "field"), .drop(.seen))
    }

    func testABeaconStopsAtTheNeighbor() {
        let beacon = RepeaterBeacon(
            deviceID: "a",
            name: "中継A",
            latitudeDegrees: 36,
            longitudeDegrees: 139,
            batteryPercent: 40,
            charging: false,
            at: date(0)
        )
        let envelope = BucketRelay.envelope(
            projectID: "field",
            kind: .beacon,
            deviceID: "a",
            at: date(0),
            hopLimit: 1,
            beacon: beacon
        )
        var next = BucketDesk(selfID: "b")
        guard case .keep(let kept) = next.receive(envelope, now: date(1), projectID: "field") else {
            return XCTFail("隣で止める")
        }
        XCTAssertEqual(kept.hops, ["a"])
        XCTAssertTrue(next.forwardable(now: date(1)).isEmpty)
    }

    func testLinkGradeFollowsTheLastHeardTime() {
        var board = RepeaterBoard()
        let beacon = RepeaterBeacon(
            deviceID: "a",
            name: "中継A",
            latitudeDegrees: 36,
            longitudeDegrees: 139,
            batteryPercent: 80,
            charging: true,
            at: date(0)
        )
        board.hear(beacon, now: date(10))
        XCTAssertEqual(board.links.first?.grade, .good)
        XCTAssertEqual(board.links.first?.batteryPercent, 80)
        board.age(now: date(30))
        XCTAssertEqual(board.links.first?.grade, .weak)
        board.age(now: date(90))
        XCTAssertEqual(board.links.first?.grade, .lost)
        let older = RepeaterBeacon(
            deviceID: "a", name: "中継A", latitudeDegrees: 36, longitudeDegrees: 139,
            batteryPercent: 1, charging: false, at: date(-5)
        )
        board.hear(older, now: date(91))
        XCTAssertEqual(board.links.first?.batteryPercent, 80)
    }

    func testLoRaTakesShortTextAndRefusesVoiceAndUncertifiedNodes() throws {
        XCTAssertEqual(LoRaPolicy.admitVoice(), .voice)
        XCTAssertEqual(
            LoRaPolicy.admit(kind: .text, name: "佐藤", text: "北が冠水", certified: false),
            .failure(.notCertified)
        )
        let admitted = try XCTUnwrap(LoRaPolicy.admit(kind: .sos, name: "佐藤", latitudeDegrees: 36, longitudeDegrees: 139, certified: true).get())
        XCTAssertTrue(admitted.line().hasPrefix("SVY1 SOS 佐藤 "))
        XCTAssertLessThanOrEqual(Data(admitted.line().utf8).count, LoRaPolicy.maxBytes)
        let long = String(repeating: "あ", count: 80)
        XCTAssertEqual(LoRaPolicy.admit(kind: .text, name: "佐藤", text: long, certified: true), .failure(.tooLong))

        var box = LoRaOutbox()
        let position = try XCTUnwrap(LoRaPolicy.admit(kind: .position, name: "佐藤", latitudeDegrees: 36, longitudeDegrees: 139, certified: true).get())
        XCTAssertTrue(box.add(position))
        XCTAssertTrue(box.add(admitted))
        XCTAssertFalse(box.add(admitted))
        XCTAssertEqual(box.next()?.kind, .sos)
        XCTAssertEqual(box.next()?.kind, .position)
    }

    func testMeshtasticTextRoundTripsAndPutsSOSAhead() {
        let message = LoRaMessage(kind: .sos, name: "佐藤", latitudeDegrees: 36, longitudeDegrees: 139)
        let encoded = MeshtasticCodec.encode(message)
        XCTAssertEqual(MeshtasticCodec.decodeText(encoded), message.line())
        XCTAssertEqual(MeshtasticCodec.priority(in: encoded), MeshtasticCodec.sosPriority)
        XCTAssertTrue(encoded.starts(with: Data([0x0A])))
        XCTAssertTrue(encoded.contains(Data([0x15, 0xFF, 0xFF, 0xFF, 0xFF])))
        let quiet = LoRaMessage(kind: .position, name: "佐藤", latitudeDegrees: 36, longitudeDegrees: 139)
        XCTAssertEqual(MeshtasticCodec.priority(in: MeshtasticCodec.encode(quiet)), MeshtasticCodec.positionPriority)
        XCTAssertNil(MeshtasticCodec.decodeText(Data([0x08, 0x01])))
    }

    func testTheForegroundConditionIsExplicit() {
        XCTAssertTrue(RepeaterPosture.condition.contains("前面"))
        XCTAssertTrue(RepeaterPosture.condition.contains("ロック"))
        XCTAssertTrue(RepeaterPosture.condition.contains("ホーム"))
        XCTAssertTrue(LoRaPolicy.voiceNote.contains("帯域"))
        XCTAssertTrue(LoRaPolicy.certifiedNote.contains("技適"))
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + seconds)
    }

    private func radioPacket(at date: Date) -> RadioPacket {
        RadioPacket(
            kind: .audio,
            utteranceID: UUID(),
            channel: RadioChannel(projectID: "field", projectName: "現場", uuid: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!),
            speaker: "佐藤",
            sentAt: date,
            station: nil,
            audio: Data([1, 2, 3, 4])
        )
    }
}
