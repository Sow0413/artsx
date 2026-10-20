import XCTest
@testable import SurveyCore

final class LocationPrivacyTests: XCTestCase {
    func testShareOnlyInsideTheFenceAndTheWorkday() {
        let fence = SiteFence(latitudeDegrees: 35.681236, longitudeDegrees: 139.767125, radiusMeters: 300)
        let hours = WorkHours(startHour: 8, endHour: 17)
        let morning = tokyo(2026, 10, 20, 9, 0)
        XCTAssertEqual(
            LocationPrivacy.gate(
                hasFix: true,
                latitude: fence.latitudeDegrees,
                longitude: fence.longitudeDegrees,
                at: morning,
                fence: fence,
                hours: hours,
                paused: false
            ),
            .sharing
        )
        XCTAssertEqual(
            LocationPrivacy.gate(
                hasFix: true,
                latitude: fence.latitudeDegrees + 0.01,
                longitude: fence.longitudeDegrees,
                at: morning,
                fence: fence,
                hours: hours,
                paused: false
            ),
            .outsideFence
        )
        XCTAssertEqual(
            LocationPrivacy.gate(
                hasFix: true,
                latitude: fence.latitudeDegrees,
                longitude: fence.longitudeDegrees,
                at: tokyo(2026, 10, 20, 17, 0),
                fence: fence,
                hours: hours,
                paused: false
            ),
            .outsideHours
        )
        XCTAssertEqual(
            LocationPrivacy.gate(
                hasFix: true,
                latitude: fence.latitudeDegrees + 0.01,
                longitude: fence.longitudeDegrees,
                at: tokyo(2026, 10, 20, 20, 0),
                fence: fence,
                hours: hours,
                paused: false
            ),
            .outsideFence
        )
    }

    func testPauseAndMissingSetupStopSharing() {
        let fence = SiteFence(latitudeDegrees: 35.681236, longitudeDegrees: 139.767125, radiusMeters: 300)
        let hours = WorkHours(startHour: 8, endHour: 17)
        let morning = tokyo(2026, 10, 20, 8, 0)
        XCTAssertEqual(
            LocationPrivacy.gate(
                hasFix: true,
                latitude: fence.latitudeDegrees,
                longitude: fence.longitudeDegrees,
                at: morning,
                fence: fence,
                hours: hours,
                paused: true
            ),
            .paused
        )
        XCTAssertEqual(
            LocationPrivacy.gate(hasFix: true, latitude: 35, longitude: 139, at: morning, fence: nil, hours: hours, paused: false),
            .unset
        )
        XCTAssertEqual(
            LocationPrivacy.gate(hasFix: true, latitude: 35, longitude: 139, at: morning, fence: fence, hours: nil, paused: false),
            .unset
        )
        XCTAssertEqual(
            LocationPrivacy.gate(hasFix: false, latitude: 0, longitude: 0, at: morning, fence: fence, hours: hours, paused: false),
            .noFix
        )
        XCTAssertTrue(hours.contains(morning))
        XCTAssertFalse(hours.contains(tokyo(2026, 10, 20, 7, 59)))
        XCTAssertFalse(WorkHours(startHour: 17, endHour: 8).contains(morning))
        XCTAssertFalse(SiteFence(latitudeDegrees: 35, longitudeDegrees: 139, radiusMeters: 0).contains(latitude: 35, longitude: 139))
        XCTAssertFalse(SiteFence(latitudeDegrees: 35, longitudeDegrees: 139, radiusMeters: -10).contains(latitude: 35, longitude: 139))
    }

    func testTermsRejectAttendanceAndEvaluation() {
        XCTAssertEqual(LocationPrivacy.terms, "位置の共有は、同じ現場の安全のためです。勤怠管理にも、人事評価にも使いません。")
        XCTAssertTrue(LocationPrivacy.terms.contains("勤怠"))
        XCTAssertTrue(LocationPrivacy.terms.contains("人事評価"))
        XCTAssertTrue(LocationPrivacy.safetyNote.contains("SOS"))
        XCTAssertTrue(LocationPrivacy.safetyNote.contains("転倒"))
        XCTAssertTrue(LocationPrivacy.trackNote.contains("60"))
        XCTAssertTrue(LocationPrivacy.trackNote.contains("P510"))
        XCTAssertTrue(LocationPrivacy.audienceNote.contains("つながっている"))
        XCTAssertEqual(LocationPrivacy.radiusMeters(10), 50)
        XCTAssertEqual(LocationPrivacy.radiusMeters(9000), 5000)
        XCTAssertEqual(LocationPrivacy.radiusMeters(.nan), 300)
    }

    func testViewersAreEmptyUntilSharing() {
        let peers = [
            ShareViewer(id: "2", name: "田中", role: "重機"),
            ShareViewer(id: "1", name: "佐藤", role: "作業員")
        ]
        XCTAssertEqual(LocationPrivacy.viewers(sharing: false, peers: peers), [])
        XCTAssertEqual(LocationPrivacy.viewers(sharing: true, peers: peers).map(\.name), ["佐藤", "田中"])
    }

    func testOldProjectJSONOmitsTheFenceAndHours() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let project = SurveyProject(name: "現場", createdAt: tokyo(2026, 10, 20, 8))
        let data = try encoder.encode(project)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["siteFence"])
        XCTAssertNil(object["workHours"])
        var stripped = object
        stripped.removeValue(forKey: "siteFence")
        stripped.removeValue(forKey: "workHours")
        let old = try JSONSerialization.data(withJSONObject: stripped)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacy = try decoder.decode(SurveyProject.self, from: old)
        XCTAssertNil(legacy.siteFence)
        XCTAssertNil(legacy.workHours)
        XCTAssertEqual(legacy.name, "現場")
    }

    func testFenceAndHoursRoundTrip() throws {
        var project = SurveyProject(name: "現場", createdAt: tokyo(2026, 10, 20, 8))
        project.siteFence = SiteFence(latitudeDegrees: 35.68, longitudeDegrees: 139.76, radiusMeters: 300)
        project.workHours = WorkHours(startHour: 8, endHour: 17)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode(SurveyProject.self, from: encoder.encode(project))
        XCTAssertEqual(loaded.siteFence?.radiusMeters, 300)
        XCTAssertEqual(loaded.workHours, WorkHours(startHour: 8, endHour: 17))
    }

    func testQuietDayDoesNotWriteATrack() throws {
        let root = try TestFiles.directory()
        defer { TestFiles.remove(root) }
        let project = try ProjectStore.create(name: "現場", at: root, now: date(0))
        let session = IncidentSession()
        session.observe([sample("静", at: 0)], projectName: project.name, at: root)
        XCTAssertFalse(trackExists(under: root))
    }

    func testIncidentFreezesOnlyTheLastMinute() throws {
        let root = try TestFiles.directory()
        defer { TestFiles.remove(root) }
        let project = try ProjectStore.create(name: "現場", at: root, now: date(0))
        let session = IncidentSession()
        session.observe([
            sample("古い", at: 0),
            sample("新しい", at: 30)
        ], projectName: project.name, at: root)
        XCTAssertFalse(trackExists(under: root))
        session.observe([sample("今", at: 90)], projectName: project.name, at: root)
        let id = try session.open(opening(at: date(90)), projectName: project.name, at: root)
        let url = try IncidentBook.directory(incidentID: id, projectName: project.name, at: root)
            .appendingPathComponent(IncidentBook.trackName)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("古い"))
        XCTAssertTrue(text.contains("新しい"))
        XCTAssertTrue(text.contains("今"))
    }

    func testOpenIncidentKeepsTheMinuteBeforeTheEvent() throws {
        let root = try TestFiles.directory()
        defer { TestFiles.remove(root) }
        let project = try ProjectStore.create(name: "現場", at: root, now: date(0))
        let session = IncidentSession()
        session.observe([sample("直前", at: -50)], projectName: project.name, at: root)
        let id = try session.open(opening(at: date(0)), projectName: project.name, at: root)
        session.observe([sample("あと", at: 200)], projectName: project.name, at: root)
        let url = try IncidentBook.directory(incidentID: id, projectName: project.name, at: root)
            .appendingPathComponent(IncidentBook.trackName)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("直前"))
        XCTAssertFalse(text.contains("あと"))
    }

    func testHiyariStatsAreAnonymousByRole() {
        XCTAssertTrue(IncidentStats.anonymizeByDefault)
        var project = SurveyProject(name: "国道", createdAt: tokyo(2026, 10, 1, 0))
        project.id = "site-1"
        let incident = IncidentRecord(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            projectID: project.id,
            projectName: project.name,
            occurredAt: tokyo(2026, 10, 20, 9, 15),
            sealedAt: tokyo(2026, 10, 20, 9, 16),
            trigger: .manual,
            parties: [
                IncidentParty(
                    id: "self", name: "田中", role: .machine,
                    latitudeDegrees: 36, longitudeDegrees: 139.8,
                    horizontalAccuracyMeters: 3, stationText: "No.1",
                    facingDegrees: 90, facingSource: "進行",
                    distanceMeters: nil, workRadiusMeters: 9
                ),
                IncidentParty(
                    id: "other", name: "佐藤", role: .worker,
                    latitudeDegrees: 36.0001, longitudeDegrees: 139.8,
                    horizontalAccuracyMeters: 4, stationText: "No.1",
                    facingDegrees: nil, facingSource: "向きなし",
                    distanceMeters: 12.4, workRadiusMeters: nil
                )
            ],
            track: [],
            machineRadiusMeters: 9,
            work: IncidentWork(kind: "下見", name: "起点"),
            accuracyMeters: 3,
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
        let rows = IncidentStats.rows(
            project: project,
            incidents: [incident],
            proximity: [],
            anonymize: IncidentStats.anonymizeByDefault
        )
        XCTAssertEqual(rows.first?.party, "重機×作業員")
        let csv = IncidentStats.csv(rows)
        XCTAssertFalse(csv.contains("田中"))
        XCTAssertFalse(csv.contains("佐藤"))
    }

    private func trackExists(under root: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return false }
        for case let url as URL in enumerator where url.lastPathComponent == IncidentBook.trackName {
            return true
        }
        return false
    }

    private func opening(at date: Date) -> IncidentOpening {
        IncidentOpening(
            id: UUID(),
            projectID: "project",
            projectName: "現場",
            occurredAt: date,
            trigger: .manual,
            parties: [
                IncidentParty(
                    id: "この端末",
                    name: "この端末",
                    role: .worker,
                    latitudeDegrees: 36,
                    longitudeDegrees: 139.8,
                    horizontalAccuracyMeters: 3,
                    stationText: "No.0",
                    facingDegrees: nil,
                    facingSource: "向きなし",
                    distanceMeters: nil,
                    workRadiusMeters: nil
                )
            ],
            machineRadiusMeters: 9,
            work: IncidentWork(kind: "下見", name: "起点"),
            accuracyMeters: 3,
            stageLabel: "段階0",
            solutionLabel: "単独",
            speeches: [],
            radio: []
        )
    }

    private func sample(_ name: String, at seconds: TimeInterval) -> IncidentSample {
        IncidentSample(
            at: date(seconds),
            id: name,
            name: name,
            role: .worker,
            latitudeDegrees: 36,
            longitudeDegrees: 139.8,
            horizontalAccuracyMeters: 3
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + seconds)
    }

    private func tokyo(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = LocationPrivacy.tokyo
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
