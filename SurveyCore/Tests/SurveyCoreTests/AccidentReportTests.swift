import XCTest
@testable import SurveyCore

final class AccidentReportTests: XCTestCase {
    func testSHA256MatchesTheKnownVectors() {
        XCTAssertEqual(SHA256.hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256.hex(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testTheBriefListsTheTimelineTheSiteAndTheRadio() {
        let document = AccidentReport.document(
            sample(),
            notes: [],
            names: .shown,
            integrity: AccidentIntegrity(recordHash: "abc", storedHash: "abc", recordStatus: "一致", appendixStatus: "追記なし", tipHash: nil),
            generatedAt: date(90)
        )
        let lines = document.narrative + document.summary
        XCTAssertTrue(lines.contains("発生 \(AccidentReport.clock(date(0)))"))
        XCTAssertTrue(lines.contains("検知 SOS \(AccidentReport.clock(date(0)))"))
        XCTAssertTrue(lines.contains { $0.hasPrefix("警報 ") && $0.contains("近い") })
        XCTAssertTrue(lines.contains("駆けつけ \(AccidentReport.clock(date(4))) 担当確定 佐藤"))
        XCTAssertTrue(lines.contains("通報 \(AccidentReport.clock(date(7))) 119の発信操作"))
        XCTAssertTrue(lines.contains("救急到着 未記録"))
        XCTAssertTrue(lines.contains("緯度 36.00000000"))
        XCTAssertTrue(lines.contains("経度 139.00000000"))
        XCTAssertTrue(lines.contains("住所 東京都港区1-2"))
        XCTAssertTrue(lines.contains("作業 床掘 北側"))
        XCTAssertTrue(lines.contains("作業半径 9.0m"))
        XCTAssertTrue(lines.contains("天候 晴れ"))
        XCTAssertTrue(lines.contains("音声あり \(AccidentReport.clock(date(2))) から \(AccidentReport.clock(date(3))) 佐藤"))
        XCTAssertEqual(AccidentReport.priorTrack(sample()).map { $0.at.timeIntervalSince(date(0)) }, [-60, 0])
        XCTAssertTrue(lines.contains("直前60秒の軌跡 2点"))
        XCTAssertTrue(document.summary.contains(AccidentReport.formNote))
        XCTAssertTrue(document.summary.contains(AccidentReport.missingFields))
        XCTAssertTrue(AccidentReport.formNote.contains("提出もしません"))
        XCTAssertEqual(document.snapshotPNG.prefix(8), Data([137, 80, 78, 71, 13, 10, 26, 10]))
    }

    func testAnonymousHidesTheNameAndShownKeepsIt() {
        let integrity = AccidentIntegrity(recordHash: "abc", storedHash: "abc", recordStatus: "一致", appendixStatus: "追記なし", tipHash: nil)
        let shown = AccidentReport.document(sample(), notes: [], names: .shown, integrity: integrity, generatedAt: date(90))
        let hidden = AccidentReport.document(sample(), notes: [], names: .anonymous, integrity: integrity, generatedAt: date(90))
        XCTAssertTrue((shown.narrative + shown.summary).contains { $0.contains("佐藤") })
        let masked = (hidden.narrative + hidden.summary).joined(separator: "\n")
        XCTAssertFalse(masked.contains("佐藤"))
        XCTAssertTrue(masked.contains("関係者1"))
        XCTAssertTrue(masked.contains("対応表はこの文書に残しません"))
        XCTAssertTrue(masked.contains("東京都港区1-2"))
    }

    func testSealHashDetectsAChangeAndTheAppendixOnlyGrows() throws {
        let root = try TestFiles.directory()
        defer { TestFiles.remove(root) }
        let project = try ProjectStore.create(name: "現場", at: root, now: date(0))
        let session = IncidentSession()
        let opening = sampleOpening()
        let id = try session.open(opening, projectName: project.name, at: root)
        _ = try session.closeDue(projectName: project.name, at: root, now: date(70))
        let folder = try IncidentBook.directory(incidentID: id, projectName: project.name, at: root)
        let recordURL = folder.appendingPathComponent(IncidentBook.recordName)
        let original = try Data(contentsOf: recordURL)
        let stored = try String(contentsOf: folder.appendingPathComponent(IncidentBook.hashName), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(stored, SHA256.hex(original))

        let exported = try AccidentBook.export(incidentID: id, projectName: project.name, at: root, names: .shown, generatedAt: date(80))
        XCTAssertEqual(exported.status, "一致")
        XCTAssertEqual(try Data(contentsOf: recordURL), original)
        let pdf = try Data(contentsOf: folder.appendingPathComponent(IncidentBook.explanationDirectory).appendingPathComponent(exported.fileName))
        XCTAssertTrue(pdf.starts(with: Data("%PDF".utf8)))
        XCTAssertTrue(pdfContains(pdf, "対外説明"))
        XCTAssertTrue(pdfContains(pdf, "照合 一致"))
        XCTAssertTrue(pdfContainsFragment(pdf, String(exported.hash.prefix(16))))
        XCTAssertTrue(pdfContains(pdf, "労働者死傷病報告に使う項目"))
        XCTAssertTrue(pdfContains(pdf, "生成時刻 \(AccidentReport.clock(date(80)))"))
        XCTAssertTrue(pdfContainsFragment(pdf, "佐藤"))
        XCTAssertTrue(pdf.contains(Data([239, 68, 68])))

        let note = try AccidentBook.append(text: "救急到着", at: date(4.9), incidentID: id, projectName: project.name, root: root)
        XCTAssertEqual(try Data(contentsOf: recordURL), original)
        XCTAssertEqual(note.at, date(4))
        var intact = AccidentBook.judge(recordBytes: original, storedHash: stored, notes: AccidentBook.loadNotes(in: folder))
        XCTAssertEqual(intact.recordStatus, "一致")
        XCTAssertEqual(intact.appendixStatus, "つながっている")
        let withArrival = AccidentReport.document(
            try JSONDecoder.incident.decode(IncidentRecord.self, from: original),
            notes: AccidentBook.loadNotes(in: folder),
            names: .shown,
            integrity: intact,
            generatedAt: date(90)
        )
        XCTAssertTrue(withArrival.narrative.contains("救急到着 \(AccidentReport.clock(date(4)))"))

        let noteURL = folder.appendingPathComponent(IncidentBook.noteName)
        var brokenText = try String(contentsOf: noteURL, encoding: .utf8)
        brokenText = brokenText.replacingOccurrences(of: note.hash, with: String(repeating: "0", count: 64))
        try Data(brokenText.utf8).write(to: noteURL)
        intact = AccidentBook.judge(recordBytes: original, storedHash: stored, notes: AccidentBook.loadNotes(in: folder))
        XCTAssertEqual(intact.appendixStatus, "切れている")

        var tampered = String(decoding: original, as: UTF8.self)
        tampered = tampered.replacingOccurrences(of: "3.25", with: "9.99")
        try Data(tampered.utf8).write(to: recordURL)
        let changed = try AccidentBook.export(incidentID: id, projectName: project.name, at: root, names: .anonymous, generatedAt: date(100))
        XCTAssertEqual(changed.status, "不一致")
        let changedPDF = try Data(contentsOf: folder.appendingPathComponent(IncidentBook.explanationDirectory).appendingPathComponent(changed.fileName))
        XCTAssertTrue(pdfContains(changedPDF, "照合 不一致"))
        XCTAssertFalse(pdfContainsFragment(changedPDF, "佐藤"))

        try FileManager.default.removeItem(at: folder.appendingPathComponent(IncidentBook.hashName))
        let missing = try AccidentBook.export(incidentID: id, projectName: project.name, at: root, names: .shown, generatedAt: date(110))
        XCTAssertEqual(missing.status, "照合用ハッシュが無い")
    }

    private func sample() -> IncidentRecord {
        IncidentRecord(
            id: UUID(),
            projectID: "project",
            projectName: "国道現場",
            occurredAt: date(0),
            sealedAt: date(70),
            trigger: .sos,
            parties: [
                IncidentParty(
                    id: "sato",
                    name: "佐藤",
                    role: .machine,
                    latitudeDegrees: 36,
                    longitudeDegrees: 139,
                    horizontalAccuracyMeters: 3.25,
                    stationText: "No.0+0.0m",
                    facingDegrees: 0,
                    facingSource: "方位",
                    distanceMeters: nil,
                    workRadiusMeters: 9
                )
            ],
            track: [
                sampleTrack("佐藤", at: -61),
                sampleTrack("佐藤", at: -60),
                sampleTrack("佐藤", at: 0),
                sampleTrack("佐藤", at: 1)
            ],
            machineRadiusMeters: 9,
            work: IncidentWork(kind: "床掘", name: "北側"),
            accuracyMeters: 3.25,
            stageLabel: "段階0",
            solutionLabel: "単独",
            speeches: [IncidentSpeech(at: date(1), text: "警報 近い")],
            radio: [
                IncidentRadioClip(
                    id: UUID(),
                    speaker: "佐藤",
                    startedAt: date(2),
                    endedAt: date(3),
                    stationText: nil,
                    audioByteCount: 12,
                    delivered: true
                )
            ],
            drawingFile: "図面.png",
            mapFile: "地図.png",
            photoFile: nil,
            voiceMemoFile: nil,
            notice: SOSCall.disclaimer,
            weather: "晴れ",
            aidLog: [
                AidStamp(at: date(4), text: "担当確定 佐藤"),
                AidStamp(at: date(7), text: "119の発信操作")
            ],
            address: "東京都港区1-2"
        )
    }

    private func sampleOpening() -> IncidentOpening {
        let record = sample()
        return IncidentOpening(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            projectID: record.projectID,
            projectName: record.projectName,
            occurredAt: record.occurredAt,
            trigger: record.trigger,
            parties: record.parties,
            machineRadiusMeters: record.machineRadiusMeters,
            work: record.work,
            accuracyMeters: record.accuracyMeters,
            stageLabel: record.stageLabel,
            solutionLabel: record.solutionLabel,
            speeches: record.speeches,
            radio: record.radio,
            notice: record.notice,
            weather: record.weather,
            aidLog: record.aidLog,
            address: record.address
        )
    }

    private func sampleTrack(_ name: String, at seconds: TimeInterval) -> IncidentSample {
        IncidentSample(
            at: date(seconds),
            id: "sato",
            name: name,
            role: .machine,
            latitudeDegrees: 36,
            longitudeDegrees: 139,
            horizontalAccuracyMeters: 3.25
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + seconds)
    }

    private func pdfContains(_ pdf: Data, _ text: String) -> Bool {
        pdf.range(of: Data(utf16(text).utf8)) != nil
    }

    private func pdfContainsFragment(_ pdf: Data, _ text: String) -> Bool {
        let hex = text.utf16.reduce(into: "") { hex, unit in
            hex += String(format: "%04X", unit)
        }
        return pdf.range(of: Data(hex.utf8)) != nil
    }

    private func utf16(_ text: String) -> String {
        "FEFF" + text.utf16.reduce(into: "") { hex, unit in
            hex += String(format: "%04X", unit)
        }
    }
}
