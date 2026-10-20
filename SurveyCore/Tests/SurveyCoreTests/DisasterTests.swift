import XCTest
@testable import SurveyCore

final class DisasterTests: XCTestCase {
    func testTheBucketDropsExpiredLoopsAndStopsAtTheHopLimit() {
        let project = "field"
        let born = date(0)
        var origin = BucketDesk(selfID: "a")
        let made = BucketRelay.envelope(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            projectID: project,
            kind: .text,
            deviceID: "a",
            at: born,
            ttlSeconds: 10,
            hopLimit: 2,
            text: DisasterText(id: UUID(), at: born, author: "佐藤", body: "冠水")
        )
        let sent = origin.originate(made, now: born)
        XCTAssertEqual(sent?.hops, ["a"])

        var next = BucketDesk(selfID: "b")
        guard case .keep(let kept) = next.receive(sent!, now: date(3), projectID: project) else {
            return XCTFail("2ホップ目で止める")
        }
        XCTAssertEqual(kept.hops, ["a", "b"])
        XCTAssertEqual(kept.createdAt, born)
        XCTAssertEqual(next.receive(sent!, now: date(4), projectID: project), .drop(.seen))
        XCTAssertEqual(origin.receive(kept, now: date(4), projectID: project), .drop(.loop))
        XCTAssertEqual(next.receive(sent!, now: date(10), projectID: "other"), .drop(.otherProject))

        var late = BucketDesk(selfID: "c")
        XCTAssertEqual(late.receive(sent!, now: date(10), projectID: project), .drop(.expired))
        XCTAssertEqual(late.receive(BucketRelay.envelope(projectID: project, kind: .text, deviceID: "a", at: born, text: nil), now: date(1), projectID: project), .drop(.empty))
    }

    func testAMiddleHopForwardsWithoutExtendingTheLife() {
        let born = date(0)
        let envelope = BucketRelay.envelope(
            projectID: "field",
            kind: .position,
            deviceID: "a",
            at: born,
            ttlSeconds: 60,
            hopLimit: 6,
            position: DisasterPosition(deviceID: "a", name: "佐藤", at: born, latitudeDegrees: 36, longitudeDegrees: 139)
        )
        var middle = BucketDesk(selfID: "b")
        guard case .forward(let forwarded) = middle.receive(envelope, now: date(20), projectID: "field") else {
            return XCTFail("次へ渡す")
        }
        XCTAssertEqual(forwarded.hops, ["a", "b"])
        XCTAssertEqual(forwarded.createdAt, born)
        XCTAssertEqual(forwarded.ttlSeconds, 60)
        XCTAssertEqual(middle.forwardable(now: date(20)).map(\.id), [forwarded.id])
        XCTAssertTrue(middle.forwardable(now: date(60)).isEmpty)
    }

    func testPassageFollowsTheTrackAndBreaksWhenTheGapIsLarge() throws {
        let start = try XCTUnwrap(GRS80Geodesic.direct(latitude: 36, longitude: 139, azimuthDegrees: 0, distanceMeters: 0))
        let near = try XCTUnwrap(GRS80Geodesic.direct(latitude: start.latitude, longitude: start.longitude, azimuthDegrees: 0, distanceMeters: 24))
        let step = try XCTUnwrap(GRS80Geodesic.direct(latitude: start.latitude, longitude: start.longitude, azimuthDegrees: 0, distanceMeters: 30))
        let far = try XCTUnwrap(GRS80Geodesic.direct(latitude: start.latitude, longitude: start.longitude, azimuthDegrees: 0, distanceMeters: 200))
        let first = PassageSample(at: date(0), latitudeDegrees: start.latitude, longitudeDegrees: start.longitude, state: .open, author: "佐藤")
        XCTAssertFalse(PassageTrack.shouldSample(after: first, latitude: near.latitude, longitude: near.longitude, now: date(10), stepMeters: PassageTrack.stepMeters))
        XCTAssertTrue(PassageTrack.shouldSample(after: first, latitude: step.latitude, longitude: step.longitude, now: date(10), stepMeters: PassageTrack.stepMeters))
        XCTAssertTrue(PassageTrack.shouldSample(after: first, latitude: step.latitude, longitude: step.longitude, now: date(10), stepMeters: BatterySaver.passageStep(enabled: true)) == false)
        let second = PassageSample(at: date(30), latitudeDegrees: step.latitude, longitudeDegrees: step.longitude, state: .open, author: "佐藤")
        let blocked = PassageSample(at: date(40), latitudeDegrees: step.latitude, longitudeDegrees: step.longitude, state: .closed, author: "佐藤")
        let after = PassageSample(at: date(50), latitudeDegrees: far.latitude, longitudeDegrees: far.longitude, state: .open, author: "佐藤")
        let lines = PassageTrack.segments(from: [first, second, blocked, after])
        XCTAssertEqual(lines.map(\.state), [.open, .closed, .open])
        XCTAssertEqual(lines[0].points.count, 2)
        XCTAssertEqual(lines[1].points.count, 1)
        XCTAssertEqual(lines[2].points.count, 1)
        XCTAssertEqual(BatterySaver.shareInterval(enabled: true), 30)
        XCTAssertEqual(BatterySaver.shareInterval(enabled: false), 5)
        XCTAssertEqual(BatterySaver.relayInterval(enabled: true), 15)
    }

    func testAnOlderPositionDoesNotReplaceANewerOne() {
        var peers = DisasterPeers()
        let newer = DisasterPosition(deviceID: "a", name: "佐藤", at: date(20), latitudeDegrees: 36, longitudeDegrees: 139)
        let older = DisasterPosition(deviceID: "a", name: "佐藤", at: date(10), latitudeDegrees: 36.1, longitudeDegrees: 139)
        XCTAssertTrue(peers.note(newer))
        XCTAssertFalse(peers.note(older))
        XCTAssertEqual(peers.latest, [newer])
    }

    func testUplinkFlushesOnlyWhenThePathReturns() {
        var uplink = DisasterUplink()
        XCTAssertFalse(uplink.note(online: false))
        XCTAssertTrue(uplink.note(online: true))
        XCTAssertFalse(uplink.note(online: true))
        XCTAssertFalse(uplink.note(online: false))
        let relay = DisasterRelay(reachable: false)
        let batch = DisasterBatch(projectID: "p", texts: [DisasterText(at: date(0), author: "佐藤", body: "了解")])
        XCTAssertEqual(relay.submit(batch), .unreachable)
        relay.isReachable = true
        XCTAssertEqual(relay.submit(batch), .sent)
        XCTAssertEqual(relay.sent, [batch])
        XCTAssertEqual(relay.submit(DisasterBatch(projectID: "p")), .sent)
        XCTAssertEqual(relay.sent.count, 1)
    }

    func testRecordsStayAppendOnlyAndTheBriefListsTheSite() throws {
        let root = try TestFiles.directory()
        defer { TestFiles.remove(root) }
        let project = try ProjectStore.create(name: "現場", at: root, now: date(0))
        let photo = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let id = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let file = try DisasterBook.savePhoto(photo, id: id, projectName: project.name, at: root)
        let site = try DisasterEntry.site(
            id: id,
            at: date(0),
            kind: .roadCut,
            latitudeDegrees: 36,
            longitudeDegrees: 139,
            horizontalAccuracyMeters: 3.25,
            lengthMeters: 12.04,
            widthMeters: 4,
            heightMeters: nil,
            note: "北側",
            photoFile: file,
            author: "佐藤"
        )
        XCTAssertEqual(site.measure.lengthMeters, 12)
        XCTAssertTrue(try DisasterBook.appendSite(site, projectName: project.name, at: root))
        XCTAssertFalse(try DisasterBook.appendSite(site, projectName: project.name, at: root))
        let folder = try ProjectStore.projectDirectory(project.name, at: root)
            .appendingPathComponent("記録簿/災害")
        let original = try Data(contentsOf: folder.appendingPathComponent(DisasterBook.siteName))
        let passage = try XCTUnwrap(DisasterEntry.passage(at: date(5), latitudeDegrees: 36, longitudeDegrees: 139, state: .open, author: "佐藤"))
        XCTAssertTrue(try DisasterBook.appendPassage(passage, projectName: project.name, at: root))
        try DisasterBook.savePositions([
            DisasterPosition(deviceID: "a", name: "佐藤", at: date(6), latitudeDegrees: 36, longitudeDegrees: 139)
        ], projectName: project.name, at: root)
        var pending = DisasterBook.pending(projectID: project.id, projectName: project.name, at: root)
        XCTAssertEqual(pending.sites, [site])
        XCTAssertEqual(pending.passages, [passage])
        XCTAssertEqual(pending.positions.count, 1)
        let relay = DisasterRelay(reachable: true)
        XCTAssertEqual(relay.submit(pending), .sent)
        try DisasterBook.markSynced(pending, projectName: project.name, at: root)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(DisasterBook.siteName)), original)
        pending = DisasterBook.pending(projectID: project.id, projectName: project.name, at: root)
        XCTAssertTrue(pending.isEmpty)

        let lines = DisasterReport.situationLines([site], generatedAt: date(9))
        XCTAssertTrue(lines.contains(DisasterReport.situationNote))
        XCTAssertTrue(lines.contains { $0.contains("道路寸断") })
        XCTAssertTrue(lines.contains("緯度 36.00000000"))
        XCTAssertTrue(lines.contains("延長 12.0m"))
        XCTAssertTrue(lines.contains("高さ 未記録"))
        XCTAssertTrue(lines.contains("写真 \(file ?? "")"))
        let ledger = DisasterReport.ledgerLines([site], generatedAt: date(9)).joined(separator: "\n")
        XCTAssertTrue(ledger.contains(DisasterReport.ledgerTitle))
        XCTAssertTrue(ledger.contains("提出もしません"))
        let csv = DisasterReport.csv([site])
        XCTAssertTrue(csv.hasPrefix(DisasterReport.csvHeader))
        XCTAssertTrue(csv.contains("道路寸断,36.00000000,139.00000000,3.3,12.0,4.0,,"))
        let exported = try DisasterBook.export(projectName: project.name, at: root, generatedAt: date(9))
        let pdf = try Data(contentsOf: folder.appendingPathComponent("出す").appendingPathComponent(exported.pdf))
        XCTAssertTrue(pdf.starts(with: Data("%PDF".utf8)))
        XCTAssertTrue(pdfContains(pdf, DisasterReport.situationTitle))
        XCTAssertTrue(pdfContains(pdf, DisasterReport.situationNote))
        let ledgerPDF = try Data(contentsOf: folder.appendingPathComponent("出す/写真帳簿").appendingPathComponent(exported.ledger))
        XCTAssertTrue(pdfContains(ledgerPDF, DisasterReport.ledgerTitle))
        let copied = folder.appendingPathComponent("出す/写真帳簿").appendingPathComponent(file ?? "")
        XCTAssertEqual(try Data(contentsOf: copied), photo)
        XCTAssertThrowsError(try DisasterEntry.site(at: date(0), kind: .flood, latitudeDegrees: 36, longitudeDegrees: 139, horizontalAccuracyMeters: nil, lengthMeters: -1, widthMeters: nil, heightMeters: nil, note: "", photoFile: nil, author: "佐藤")) { error in
            XCTAssertEqual(error as? DisasterEntryError, .badMeasure)
        }
        XCTAssertThrowsError(try DisasterEntry.text(at: date(0), author: "佐藤", body: " \n "))
    }

    func testAnOldLinkFrameWithoutABucketStillDecodes() throws {
        let json = #"{"kind":"radio"}"#
        let frame = try JSONDecoder().decode(LinkFrame.self, from: Data(json.utf8))
        XCTAssertEqual(frame.kind, .radio)
        XCTAssertNil(frame.bucket)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + seconds)
    }

    private func pdfContains(_ pdf: Data, _ text: String) -> Bool {
        let hex = "FEFF" + text.utf16.reduce(into: "") { hex, unit in
            hex += String(format: "%04X", unit)
        }
        return pdf.range(of: Data(hex.utf8)) != nil
    }
}
