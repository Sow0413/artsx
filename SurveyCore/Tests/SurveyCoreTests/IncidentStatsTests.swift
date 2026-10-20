import XCTest
@testable import SurveyCore

final class IncidentStatsTests: XCTestCase {
    func testTimeBandsFollowTokyoHours() {
        XCTAssertEqual(IncidentTimeBand.of(tokyo(2026, 10, 20, 4)).rawValue, "深夜")
        XCTAssertEqual(IncidentTimeBand.of(tokyo(2026, 10, 20, 5)).rawValue, "早朝")
        XCTAssertEqual(IncidentTimeBand.of(tokyo(2026, 10, 20, 7, 59)).rawValue, "早朝")
        XCTAssertEqual(IncidentTimeBand.of(tokyo(2026, 10, 20, 8)).rawValue, "午前")
        XCTAssertEqual(IncidentTimeBand.of(tokyo(2026, 10, 20, 12)).rawValue, "午後")
        XCTAssertEqual(IncidentTimeBand.of(tokyo(2026, 10, 20, 17)).rawValue, "夕方")
        XCTAssertEqual(IncidentTimeBand.of(tokyo(2026, 10, 20, 19)).rawValue, "夜間")
    }

    func testRowsUseTheSharedColumnsAndCanDropNames() throws {
        var project = SurveyProject(name: "国道", createdAt: tokyo(2026, 10, 1, 0), machinePreset: "20t", machineRadiusMeters: 9, weather: "晴れ")
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
            notice: SafetyNotice.text,
            weather: "雨"
        )
        let near = ProximityEvent(
            projectID: project.id,
            level: .caution,
            startedAt: tokyo(2026, 10, 20, 15),
            endedAt: nil,
            selfID: "self",
            selfRole: .machine,
            otherID: "other",
            otherName: "佐藤",
            otherRole: .worker,
            enteredMeters: 40,
            closestMeters: 38.2,
            alarmRadiusMeters: nil,
            rangeKind: .gnss,
            latitudeDegrees: 36.001,
            longitudeDegrees: 139.8
        )
        let rows = IncidentStats.rows(project: project, incidents: [incident], proximity: [near, clearEvent()], anonymize: true)
        XCTAssertEqual(rows.map(\.source), ["incident", "proximity"])
        XCTAssertEqual(rows[0].workKind, "下見")
        XCTAssertEqual(rows[0].timeBand, "午前")
        XCTAssertEqual(rows[0].weather, "雨")
        XCTAssertEqual(rows[0].distanceMeters ?? 0, 12.4, accuracy: 0.01)
        XCTAssertEqual(rows[0].machineKind, "20t")
        XCTAssertEqual(rows[0].role, "重機×作業員")
        XCTAssertEqual(rows[0].party, "重機×作業員")
        XCTAssertEqual(rows[1].workKind, "不明")
        XCTAssertEqual(rows[1].timeBand, "午後")
        XCTAssertEqual(rows[1].weather, "晴れ")
        XCTAssertEqual(rows[1].level, "注意")
        let text = IncidentStats.csv(rows)
        XCTAssertTrue(text.hasPrefix(IncidentStatRow.columns.joined(separator: ",")))
        XCTAssertFalse(text.contains("田中"))
        XCTAssertFalse(text.contains("佐藤"))
        XCTAssertEqual(IncidentStats.countsByWork(rows).map { "\($0.key):\($0.count)" }, ["下見:1", "不明:1"])
        XCTAssertEqual(IncidentStats.countsByTime(rows).map(\.key), ["午前", "午後"])

        let named = IncidentStats.rows(project: project, incidents: [incident], proximity: [], anonymize: false)
        XCTAssertTrue(named[0].party.contains("田中"))
    }

    func testHeatMergesPointsInsideOneCell() {
        let near = [
            point(36.00000, 139.80000),
            point(36.00008, 139.80000)
        ]
        let cells = IncidentStats.heat(near)
        XCTAssertEqual(cells.count, 1)
        XCTAssertEqual(cells[0].count, 2)

        let far = [point(36.00000, 139.80000), point(36.00080, 139.80000)]
        XCTAssertEqual(IncidentStats.heat(far).count, 2)
        XCTAssertTrue(IncidentStats.heat([blankPoint()]).isEmpty)
    }

    func testCSVRoundTripKeepsTheSchemaAndDoesNotRewriteTheIncident() throws {
        let root = try TestFiles.directory()
        defer { TestFiles.remove(root) }
        var project = try ProjectStore.create(name: "現場", at: root, now: tokyo(2026, 10, 1, 0))
        project.machinePreset = "20t"
        project.weather = "曇り"
        try ProjectStore.save(project, at: root)
        var opening = IncidentOpening(
            projectID: project.id,
            projectName: project.name,
            occurredAt: tokyo(2026, 10, 20, 10),
            trigger: .alarm,
            parties: [
                IncidentParty(
                    id: "self", name: "この端末", role: .worker,
                    latitudeDegrees: 36, longitudeDegrees: 139.8,
                    horizontalAccuracyMeters: 3, stationText: "中心線がありません",
                    facingDegrees: nil, facingSource: "向きなし",
                    distanceMeters: nil, workRadiusMeters: nil
                )
            ],
            machineRadiusMeters: 9,
            work: IncidentWork(kind: "丁張", name: "法肩"),
            accuracyMeters: 3,
            stageLabel: "段階0",
            solutionLabel: "単独",
            speeches: [],
            radio: [],
            weather: "曇り"
        )
        opening.id = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        try IncidentBook.begin(opening, projectName: project.name, at: root)
        _ = try IncidentBook.seal(incidentID: opening.id, projectName: project.name, at: root, now: tokyo(2026, 10, 20, 10).addingTimeInterval(60))
        let before = try Data(contentsOf: IncidentBook.directory(incidentID: opening.id, projectName: project.name, at: root).appendingPathComponent(IncidentBook.recordName))
        let rows = IncidentStats.load(project: project, at: root, anonymize: true)
        let url = try IncidentStats.writeCSV(rows, projectName: project.name, at: root)
        XCTAssertTrue(url.path.contains("記録簿/統計.csv"))
        let after = try Data(contentsOf: IncidentBook.directory(incidentID: opening.id, projectName: project.name, at: root).appendingPathComponent(IncidentBook.recordName))
        XCTAssertEqual(before, after)
        XCTAssertEqual(rows.first?.workKind, "丁張")
        XCTAssertEqual(rows.first?.weather, "曇り")
        XCTAssertEqual(rows.first?.schema, "incident-stat/1")
    }

    private func point(_ latitude: Double, _ longitude: Double) -> IncidentStatRow {
        IncidentStatRow(
            source: "incident", recordID: UUID().uuidString, projectID: "p", projectName: "現場",
            occurredAt: tokyo(2026, 10, 20, 9), workKind: "下見", timeBand: "午前", weather: "不明",
            distanceMeters: 10, machineKind: "20t", role: "作業員",
            latitudeDegrees: latitude, longitudeDegrees: longitude, level: "ヒヤリ", party: "作業員"
        )
    }

    private func blankPoint() -> IncidentStatRow {
        var row = point(0, 0)
        row.latitudeDegrees = nil
        row.longitudeDegrees = nil
        return row
    }

    private func clearEvent() -> ProximityEvent {
        ProximityEvent(
            projectID: "site-1", level: .clear, startedAt: tokyo(2026, 10, 20, 11), endedAt: nil,
            selfID: "self", selfRole: .machine, otherID: "x", otherName: "誰か", otherRole: .worker,
            enteredMeters: 80, closestMeters: 80, alarmRadiusMeters: nil, rangeKind: .gnss
        )
    }

    private func tokyo(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = IncidentStats.tokyo
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
