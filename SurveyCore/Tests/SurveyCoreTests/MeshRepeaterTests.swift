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

    func testEveryPhoneForwardsTrafficThatIsNotAddressedToIt() {
        XCTAssertEqual(
            MeshDuty.choice(
                addressedTo: "佐藤", selfID: "田中", kind: .text, hops: 1, hopLimit: 6,
                batteryPercent: 80, charging: false, presence: .active
            ),
            .forward
        )
        XCTAssertEqual(
            MeshDuty.choice(
                addressedTo: "田中", selfID: "田中", kind: .text, hops: 1, hopLimit: 6,
                batteryPercent: 80, charging: false, presence: .active
            ),
            .forward
        )
        XCTAssertEqual(
            MeshDuty.choice(
                addressedTo: "佐藤", selfID: "田中", kind: .position, hops: 6, hopLimit: 6,
                batteryPercent: 90, charging: false, presence: .active
            ),
            .keep
        )
    }

    func testALowBatteryPhoneRelaysOnlyUrgentKinds() {
        XCTAssertFalse(MeshDuty.sparing(batteryPercent: 20, charging: false))
        XCTAssertTrue(MeshDuty.sparing(batteryPercent: 19, charging: false))
        XCTAssertFalse(MeshDuty.sparing(batteryPercent: 5, charging: true))
        XCTAssertFalse(MeshDuty.sparing(batteryPercent: nil, charging: false))
        for kind in [BucketKind.sos, .radio, .text] {
            XCTAssertEqual(
                MeshDuty.choice(
                    addressedTo: nil, selfID: "a", kind: kind, hops: 1, hopLimit: 6,
                    batteryPercent: 10, charging: false, presence: .active
                ),
                .forward
            )
        }
        for kind in [BucketKind.position, .site, .passage] {
            XCTAssertEqual(
                MeshDuty.choice(
                    addressedTo: "ほか", selfID: "a", kind: kind, hops: 1, hopLimit: 6,
                    batteryPercent: 10, charging: false, presence: .active
                ),
                .spare
            )
        }
        XCTAssertEqual(
            MeshDuty.choice(
                addressedTo: "ほか", selfID: "a", kind: .position, hops: 1, hopLimit: 6,
                batteryPercent: 5, charging: true, presence: .active
            ),
            .forward
        )
        XCTAssertEqual(MeshDuty.relayInterval(batteryPercent: 10, charging: false, saver: false), MeshDuty.sparingRelaySeconds)
        XCTAssertEqual(MeshDuty.relayInterval(batteryPercent: 10, charging: true, saver: false), BatterySaver.relayInterval(enabled: false))
        XCTAssertEqual(MeshDuty.relayInterval(batteryPercent: 80, charging: false, saver: true), BatterySaver.relayInterval(enabled: true))
    }

    func testRelayStopsOutsideTheForeground() {
        XCTAssertEqual(
            MeshDuty.choice(
                addressedTo: nil, selfID: "a", kind: .sos, hops: 0, hopLimit: 6,
                batteryPercent: 100, charging: true, presence: .background
            ),
            .stopped
        )
        XCTAssertEqual(
            MeshDuty.choice(
                addressedTo: nil, selfID: "a", kind: .sos, hops: 0, hopLimit: 6,
                batteryPercent: 100, charging: false, presence: .inactive
            ),
            .stopped
        )
        XCTAssertTrue(MeshDuty.relaying(.active))
        XCTAssertFalse(MeshDuty.relaying(.background))
        XCTAssertEqual(MeshDuty.stoppedLabel, "中継停止中")
        XCTAssertTrue(MeshDuty.locationBackgroundNote.contains("位置情報"))
        XCTAssertTrue(MeshDuty.locationBackgroundNote.contains("維持しません"))
        XCTAssertTrue(MeshDuty.pttStandbyNote.contains("PTT"))
        XCTAssertTrue(MeshDuty.everyoneNote.contains("自分宛て"))
        XCTAssertTrue(MeshDuty.everyoneNote.contains("見通し"))
        XCTAssertTrue(MeshDuty.rangeNote.contains("見通せ"))
    }

    func testTheSameVoiceGetsOneEnvelopeID() {
        let packet = radioPacket(at: date(3))
        let first = MeshDuty.radioEnvelopeID(packet)
        XCTAssertEqual(first, MeshDuty.radioEnvelopeID(packet))
        var changed = packet
        changed.audio = Data([9])
        XCTAssertNotEqual(first, MeshDuty.radioEnvelopeID(changed))
        var desk = BucketDesk(selfID: "b")
        let heard = BucketRelay.envelope(id: first, projectID: "field", kind: .radio, deviceID: "a", at: date(3), radio: packet)
        guard case .forward = desk.receive(heard, now: date(4), projectID: "field") else {
            return XCTFail("先に受けた")
        }
        let again = BucketRelay.envelope(id: first, projectID: "field", kind: .radio, deviceID: "b", at: date(4), radio: packet)
        XCTAssertNil(desk.originate(again, now: date(4)))
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
