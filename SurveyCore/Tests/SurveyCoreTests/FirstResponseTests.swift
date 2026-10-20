import XCTest
@testable import SurveyCore

final class FirstResponseTests: XCTestCase {
    func testNearestPersonIsTheFreshCloserOne() throws {
        let victim = (latitude: 35.68, longitude: 139.76)
        let sato = try placed(from: victim, azimuth: 225, distance: 40)
        let tanaka = try placed(from: victim, azimuth: 225, distance: 90)
        let closerButStale = try placed(from: victim, azimuth: 10, distance: 8)
        let pick = FirstPicker.nearest(
            victimID: "victim",
            latitude: victim.latitude,
            longitude: victim.longitude,
            peers: [
                peer("victim", "本人", victim, at: 0),
                peer("stale", "近い人", closerButStale, at: -31),
                peer("tanaka", "田中", tanaka, at: -2),
                peer("sato", "佐藤", sato, at: -1)
            ],
            now: date(0)
        )
        let found = try XCTUnwrap(pick)
        XCTAssertEqual(found.id, "sato")
        XCTAssertEqual(found.distanceMeters, 40, accuracy: 0.5)
    }

    func testTheNearestPersonHearsRightFrontFortyMeters() throws {
        let sato = (latitude: 35.68, longitude: 139.76)
        let victim = try placed(from: sato, azimuth: 45, distance: 40)
        var desk = FirstDesk()
        let opened = try XCTUnwrap(desk.begin(
            trigger: .sos,
            victimID: "victim",
            victimName: "鈴木",
            latitude: victim.latitude,
            longitude: victim.longitude,
            channelID: "site",
            peers: [peer("sato", "佐藤", sato, at: 0), peer("tanaka", "田中", try placed(from: victim, azimuth: 90, distance: 200), at: 0)],
            at: date(0)
        ))
        XCTAssertEqual(opened.nearestID, "sato")
        let mine = FirstCall.view(
            episode: opened,
            selfID: "sato",
            selfLatitude: sato.latitude,
            selfLongitude: sato.longitude,
            courseDegrees: nil,
            headingDegrees: 0,
            facing: .own
        )
        XCTAssertEqual(mine.headline, "あなたが最寄り 右まえ40m")
        XCTAssertTrue(mine.nearestOpen)
        XCTAssertEqual(mine.progress, "佐藤が最寄りです")
        let machine = FirstCall.view(
            episode: opened,
            selfID: "sato",
            selfLatitude: sato.latitude,
            selfLongitude: sato.longitude,
            courseDegrees: 225,
            headingDegrees: 0,
            facing: .machine
        )
        XCTAssertEqual(machine.headline, "あなたが最寄り 右まえ40m")
        let turned = FirstCall.view(
            episode: opened,
            selfID: "sato",
            selfLatitude: sato.latitude,
            selfLongitude: sato.longitude,
            courseDegrees: 225,
            headingDegrees: 0,
            facing: .own
        )
        XCTAssertEqual(turned.headline, "あなたが最寄り うしろ40m")
        let lost = FirstCall.view(
            episode: opened,
            selfID: "sato",
            selfLatitude: sato.latitude,
            selfLongitude: sato.longitude,
            courseDegrees: nil,
            headingDegrees: nil,
            facing: .own
        )
        XCTAssertEqual(lost.headline, "あなたが最寄り 方向不明")
    }

    func testAcceptingLocksTheNearestAndSharesTheStatus() throws {
        var desk = try opened()
        XCTAssertNil(desk.acceptNearest(deviceID: "tanaka", at: date(1)))
        let accepted = try XCTUnwrap(desk.acceptNearest(deviceID: "sato", at: date(2)))
        XCTAssertEqual(accepted.nearestAcceptedAt, date(2))
        XCTAssertNil(desk.acceptNearest(deviceID: "sato", at: date(3)))
        XCTAssertEqual(FirstCall.progress(accepted), "佐藤が担当です")
        let other = FirstCall.view(
            episode: accepted,
            selfID: "tanaka",
            selfLatitude: nil,
            selfLongitude: nil,
            courseDegrees: nil,
            headingDegrees: nil,
            facing: .own
        )
        XCTAssertEqual(other.headline, "佐藤が担当です")
        XCTAssertFalse(other.isNearest)
        XCTAssertEqual(accepted.stamps.map(\.text), ["初動開始", "最寄り 佐藤 40m", "担当確定 佐藤"])
    }

    func testGreeterIsAssignedAndThenConfirmed() throws {
        var desk = try opened()
        XCTAssertNil(desk.assignGreeter(id: "victim", name: "鈴木", at: date(1)))
        let assigned = try XCTUnwrap(desk.assignGreeter(id: "tanaka", name: "田中", at: date(2)))
        XCTAssertEqual(FirstCall.progress(assigned), "佐藤が最寄りです。田中が救急車の迎えです")
        XCTAssertNil(desk.acceptGreeter(deviceID: "sato", at: date(3)))
        let confirmed = try XCTUnwrap(desk.acceptGreeter(deviceID: "tanaka", at: date(4)))
        XCTAssertEqual(FirstCall.progress(confirmed), "佐藤が最寄りです。田中が救急車を迎えます")
        XCTAssertNil(desk.assignGreeter(id: "sato", name: "佐藤", at: date(5)))
        let mine = FirstCall.view(
            episode: assigned,
            selfID: "tanaka",
            selfLatitude: nil,
            selfLongitude: nil,
            courseDegrees: nil,
            headingDegrees: nil,
            facing: .own
        )
        XCTAssertTrue(mine.greeterOpen)
        XCTAssertEqual(mine.headline, "救急車を迎えてください")
    }

    func testChecklistIsOnlyTheThreeGeneralQuestions() throws {
        var desk = try opened()
        let marked = try XCTUnwrap(desk.setCheck(.conscious, answer: true, at: date(3)))
        XCTAssertEqual(marked.checklist.conscious, true)
        XCTAssertEqual(marked.checklist.consciousAt, date(3))
        XCTAssertEqual(marked.stamps.last?.text, "意識 はい")
        XCTAssertEqual(AidCheck.allCases.map(\.prompt), [
            "意識：呼びかけに答えますか",
            "呼吸：普段どおりの息をしていますか",
            "出血：止まらない出血がありますか"
        ])
        XCTAssertEqual(AidChecklist.note, "見るだけのメモです。手当の手順ではありません。119の指示に従ってください。")
        XCTAssertFalse(AidChecklist.note.contains("胸骨"))
        XCTAssertFalse(AidCheck.bleeding.prompt.contains("圧迫"))
    }

    func testReadoutListsTheSiteAndDoesNotDial() {
        let site = SiteAid(
            address: "東京都港区1-2",
            landmark: "青い門",
            ambulanceEntrance: "北の通用口",
            hospitalName: "港病院",
            contacts: [AidContact(name: "現場責任者", phone: "0312345678")]
        )
        let lines = Readout119.lines(site: site, latitude: 35.68, longitude: 139.76)
        XCTAssertTrue(lines.contains("東京都港区1-2"))
        XCTAssertTrue(lines.contains("緯度 35.68000000 経度 139.76000000"))
        XCTAssertTrue(lines.contains("青い門"))
        XCTAssertTrue(lines.contains("北の通用口"))
        XCTAssertTrue(lines.contains("港病院"))
        XCTAssertTrue(lines.contains("現場責任者 0312345678"))
        let empty = Readout119.lines(site: .empty, latitude: nil, longitude: nil)
        XCTAssertTrue(empty.contains("未登録"))
        let speech = Readout119.speech(site: site, latitude: 35.68, longitude: 139.76)
        XCTAssertTrue(speech.contains("現場の住所、東京都港区1-2"))
        XCTAssertFalse(speech.contains("tel:"))
        XCTAssertEqual(Readout119.idleNote, "電話はここではかけません。発信は本人が行います。")
    }

    func testCallAndReadoutTimesAreStampedOnce() throws {
        var desk = try opened()
        let readout = try XCTUnwrap(desk.noteReadout(at: date(5)))
        XCTAssertEqual(readout.readoutAt, date(5))
        XCTAssertNil(desk.noteReadout(at: date(6)))
        let call = try XCTUnwrap(desk.noteCall(at: date(7)))
        XCTAssertEqual(call.callAt, date(7))
        XCTAssertNil(desk.noteCall(at: date(8)))
        XCTAssertTrue(call.stamps.map(\.text).contains("119の読み上げ"))
        XCTAssertTrue(call.stamps.map(\.text).contains("119の発信操作"))
    }

    func testAidArrowUsesTheSameSectors() throws {
        let here = (latitude: 35.68, longitude: 139.76)
        let aed = try placed(from: here, azimuth: 45, distance: 40)
        let arrows = FirstCall.arrows(
            points: [AidPoint(id: "aed", kind: .aed, latitudeDegrees: aed.latitude, longitudeDegrees: aed.longitude)],
            selfLatitude: here.latitude,
            selfLongitude: here.longitude,
            courseDegrees: nil,
            headingDegrees: 0,
            facing: .own
        )
        XCTAssertEqual(arrows.first?.text, "右まえ40m AED")
        XCTAssertEqual(arrows.first?.known, true)
    }

    func testIncidentKeepsTheFirstResponseTimes() throws {
        let root = try TestFiles.directory()
        defer { TestFiles.remove(root) }
        let project = try ProjectStore.create(name: "現場", at: root, now: date(0))
        let session = IncidentSession()
        var opening = opening(at: date(0))
        let id = try session.open(opening, projectName: project.name, at: root)
        try session.noteAid(AidStamp(at: date(2), text: "初動開始"), incidentID: id, projectName: project.name, at: root)
        try session.noteAid(AidStamp(at: date(4), text: "担当確定 佐藤"), incidentID: id, projectName: project.name, at: root)
        try session.noteAid(AidStamp(at: date(4), text: "担当確定 佐藤"), incidentID: id, projectName: project.name, at: root)
        let sealed = try session.closeDue(projectName: project.name, at: root, now: date(70))
        let record = try XCTUnwrap(sealed.first?.record)
        let lines = IncidentReport.lines(record)
        XCTAssertTrue(lines.contains(FirstCall.recordNote))
        XCTAssertTrue(lines.contains { $0.hasSuffix("初動開始") })
        XCTAssertTrue(lines.contains { $0.hasSuffix("担当確定 佐藤") })
        XCTAssertEqual(record.aidLog?.map(\.text), ["初動開始", "担当確定 佐藤"])
        XCTAssertThrowsError(try session.noteAid(AidStamp(at: date(80), text: "あとから"), incidentID: id, projectName: project.name, at: root)) { error in
            XCTAssertEqual(error as? IncidentError, .missingOpening)
        }
        opening.id = id
        XCTAssertThrowsError(try IncidentBook.replaceOpening(opening, projectName: project.name, at: root)) { error in
            XCTAssertEqual(error as? IncidentError, .alreadySealed)
        }
    }

    func testOldProjectJSONStillLoadsWithoutSiteAid() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var project = SurveyProject(name: "現場", createdAt: date(0))
        project.siteAid = SiteAid(address: "東京都港区1-2", hospitalName: "港病院")
        let data = try encoder.encode(project)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode(SurveyProject.self, from: data)
        XCTAssertEqual(loaded.siteAid?.address, "東京都港区1-2")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var stripped = object
        stripped.removeValue(forKey: "siteAid")
        let old = try JSONSerialization.data(withJSONObject: stripped)
        let legacy = try decoder.decode(SurveyProject.self, from: old)
        XCTAssertNil(legacy.siteAid)
        XCTAssertEqual(legacy.name, "現場")
    }

    func testLinkFrameCarriesTheEpisode() throws {
        let desk = try opened()
        let episode = try XCTUnwrap(desk.episode)
        let frame = LinkFrame(kind: .aid, aid: AidPacket(episode: episode))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(frame)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(LinkFrame.self, from: data)
        XCTAssertEqual(back.kind, .aid)
        XCTAssertEqual(back.aid?.episode.nearestName, "佐藤")
    }

    func testANearbyEpisodeIsForwardedOnce() throws {
        var desk = FirstDesk()
        let episode = try XCTUnwrap(opened().episode)
        XCTAssertFalse(desk.shouldForward(episode, arrived: .relay, relayReachable: true))
        XCTAssertFalse(desk.shouldForward(episode, arrived: .nearby, relayReachable: false))
        XCTAssertTrue(desk.shouldForward(episode, arrived: .nearby, relayReachable: true))
        XCTAssertFalse(desk.shouldForward(episode, arrived: .nearby, relayReachable: true))
    }

    private func opened() throws -> FirstDesk {
        let victim = (latitude: 35.68, longitude: 139.76)
        let sato = try placed(from: victim, azimuth: 225, distance: 40)
        var desk = FirstDesk()
        _ = desk.begin(
            trigger: .fall,
            victimID: "victim",
            victimName: "鈴木",
            latitude: victim.latitude,
            longitude: victim.longitude,
            channelID: "site",
            peers: [peer("sato", "佐藤", sato, at: 0)],
            at: date(0)
        )
        return desk
    }

    private func opening(at date: Date) -> IncidentOpening {
        IncidentOpening(
            projectID: "project",
            projectName: "現場",
            occurredAt: date,
            trigger: .sos,
            parties: [],
            machineRadiusMeters: 9,
            work: IncidentWork(kind: "SOS", name: "SOS"),
            accuracyMeters: 4,
            stageLabel: "段階0",
            solutionLabel: "単独",
            speeches: [],
            radio: []
        )
    }

    private func peer(_ id: String, _ name: String, _ point: (latitude: Double, longitude: Double), at seconds: TimeInterval) -> FirstPeer {
        FirstPeer(
            id: id,
            name: name,
            latitudeDegrees: point.latitude,
            longitudeDegrees: point.longitude,
            sentAt: date(seconds)
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

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + seconds)
    }
}
