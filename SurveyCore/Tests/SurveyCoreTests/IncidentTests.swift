import XCTest
@testable import SurveyCore

final class IncidentTests: XCTestCase {
    func testWindowKeepsSixtySecondsOnEitherSide() {
        let center = date(0)
        let samples = [
            sample("a", at: -61),
            sample("a", at: -60),
            sample("b", at: 0),
            sample("a", at: 60),
            sample("a", at: 61)
        ]
        let kept = IncidentBook.clip(samples, around: center)
        XCTAssertEqual(kept.map { $0.at.timeIntervalSince(center) }, [-60, 0, 60])
    }

    func testPartiesCarryStationFacingAndDistance() throws {
        let origin = try XCTUnwrap(PlaneRectangular.inverse(northingMeters: 0, eastingMeters: 0, zone: 9))
        let spot = try XCTUnwrap(PlaneRectangular.inverse(northingMeters: 3, eastingMeters: 465, zone: 9))
        let line = StationLine(
            name: "中心",
            zone: 9,
            intervalMeters: 20,
            originStation: 0,
            source: .polyline,
            vertices: [PlanarPoint(x: 0, y: 0), PlanarPoint(x: 500, y: 0)],
            chainageMeters: [0, 500]
        )
        let other = CrewFix(
            id: "worker",
            name: "作業員A",
            role: .worker,
            latitudeDegrees: spot.latitudeDegrees,
            longitudeDegrees: spot.longitudeDegrees,
            horizontalAccuracyMeters: 4,
            workRadiusMeters: nil,
            sentAt: date(0),
            courseDegrees: nil,
            headingDegrees: 10
        )
        let parties = IncidentParties.assemble(
            selfID: "machine",
            selfName: "この端末",
            selfRole: .machine,
            selfLatitude: origin.latitudeDegrees,
            selfLongitude: origin.longitudeDegrees,
            selfAccuracy: 3.2,
            selfCourse: 90,
            selfHeading: 0,
            selfRadius: 9,
            others: [other],
            stationLine: line
        )
        XCTAssertEqual(parties[0].stationText, "No.0+0.0m 中心")
        XCTAssertEqual(parties[0].facingSource, "進行")
        XCTAssertEqual(parties[0].facingDegrees ?? -1, 90, accuracy: 1e-9)
        XCTAssertNil(parties[0].distanceMeters)
        XCTAssertEqual(parties[1].stationText, "No.23+5.0m 左 3.0m")
        XCTAssertEqual(parties[1].facingSource, "方位")
        XCTAssertEqual(parties[1].distanceMeters ?? 0, 465, accuracy: 0.5)
    }

    func testRecordIsAppendOnlyAndTheReportIsJapanese() throws {
        let root = try TestFiles.directory()
        defer { TestFiles.remove(root) }
        let project = try ProjectStore.create(name: "国道", at: root, now: date(0))
        let opening = opening(at: date(0), trigger: .alarm)
        try IncidentBook.begin(opening, projectName: project.name, at: root)
        let folder = try IncidentBook.directory(incidentID: opening.id, projectName: project.name, at: root)
        XCTAssertTrue(folder.path.contains("記録簿/インシデント"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(IncidentBook.recordName).path))
        try IncidentBook.appendSample(sample("この端末", at: -30), incidentID: opening.id, projectName: project.name, at: root)
        try IncidentBook.appendSample(sample("作業員A", at: 40), incidentID: opening.id, projectName: project.name, at: root)
        try IncidentBook.attachPhoto(Data([1, 2, 3]), incidentID: opening.id, projectName: project.name, at: root)
        let openingBytes = try Data(contentsOf: folder.appendingPathComponent(IncidentBook.openingName))

        XCTAssertThrowsError(try IncidentBook.seal(incidentID: opening.id, projectName: project.name, at: root, now: date(59))) { error in
            XCTAssertEqual(error as? IncidentError, .tooEarly)
        }
        let record = try IncidentBook.seal(
            incidentID: opening.id,
            projectName: project.name,
            at: root,
            now: date(60),
            speeches: [IncidentSpeech(at: date(20), text: "右うしろ、人、15メートル")]
        )
        XCTAssertEqual(record.track.count, 2)
        XCTAssertEqual(record.photoFile, IncidentBook.photoName)
        XCTAssertEqual(record.work.kind, "下見")
        XCTAssertEqual(record.work.name, "起点")
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(IncidentBook.openingName)), openingBytes)

        let pdf = try Data(contentsOf: folder.appendingPathComponent(IncidentBook.pdfName))
        XCTAssertTrue(pdf.starts(with: Data("%PDF".utf8)))
        let text = String(decoding: pdf, as: UTF8.self)
        XCTAssertTrue(text.contains(utf16("ヒヤリハット報告書")))
        XCTAssertTrue(text.contains(codeUnits("下見")))
        XCTAssertTrue(text.contains(codeUnits("右うしろ、人、15メートル")))

        let drawing = try Data(contentsOf: folder.appendingPathComponent(IncidentBook.drawingName))
        let map = try Data(contentsOf: folder.appendingPathComponent(IncidentBook.mapName))
        XCTAssertTrue(drawing.starts(with: Data([137, 80, 78, 71, 13, 10, 26, 10])))
        XCTAssertNotEqual(drawing, map)
        let pixels = try XCTUnwrap(IncidentPNG.rgb(drawing))
        XCTAssertEqual(pixels.width, 160)
        let center = (80 * 160 + 80) * 3
        XCTAssertEqual(pixels.rgb[center], 239)

        XCTAssertThrowsError(try IncidentBook.seal(incidentID: opening.id, projectName: project.name, at: root, now: date(120))) { error in
            XCTAssertEqual(error as? IncidentError, .alreadySealed)
        }
        XCTAssertThrowsError(try IncidentBook.appendSample(sample("この端末", at: 10), incidentID: opening.id, projectName: project.name, at: root)) { error in
            XCTAssertEqual(error as? IncidentError, .alreadySealed)
        }
        XCTAssertThrowsError(try IncidentBook.attachVoice(Data([9]), incidentID: opening.id, projectName: project.name, at: root)) { error in
            XCTAssertEqual(error as? IncidentError, .alreadySealed)
        }
        XCTAssertThrowsError(try IncidentBook.begin(opening, projectName: project.name, at: root)) { error in
            XCTAssertEqual(error as? IncidentError, .alreadyExists)
        }
    }

    func testAlarmDoesNotRepeatWhileTheWindowIsOpen() throws {
        let root = try TestFiles.directory()
        defer { TestFiles.remove(root) }
        let project = try ProjectStore.create(name: "現場", at: root, now: date(0))
        let session = IncidentSession(relay: IncidentRelayStub(reachable: false))
        session.observe([sample("この端末", at: -20), sample("この端末", at: -70)], projectName: project.name, at: root)
        let first = try session.open(opening(at: date(0), trigger: .alarm), projectName: project.name, at: root)
        let second = try session.open(opening(at: date(2), trigger: .alarm), projectName: project.name, at: root)
        XCTAssertEqual(first, second)
        let manual = try session.open(opening(at: date(3), trigger: .manual), projectName: project.name, at: root)
        XCTAssertNotEqual(manual, first)
        session.observe([sample("作業員A", at: 30)], projectName: project.name, at: root)
        XCTAssertTrue(try session.closeDue(projectName: project.name, at: root, now: date(50)).isEmpty)
        let sealed = try session.closeDue(
            projectName: project.name,
            at: root,
            now: date(63),
            speeches: [IncidentSpeech(at: date(10), text: "重機に近づいています、左前")]
        )
        XCTAssertEqual(sealed.count, 2)
        let alarm = try XCTUnwrap(sealed.first { $0.record.trigger == .alarm }?.record)
        XCTAssertEqual(alarm.track.map(\.id), ["この端末", "作業員A"])
        XCTAssertEqual(alarm.speeches.map(\.text), ["重機に近づいています、左前"])
        XCTAssertEqual(sealed.map(\.delivery), [.pending, .pending])
        XCTAssertFalse(FileManager.default.fileExists(atPath: try sentURL(alarm.id, project: project.name, root: root).path))
    }

    func testRelaySendsOnceItIsReachable() throws {
        let root = try TestFiles.directory()
        defer { TestFiles.remove(root) }
        let project = try ProjectStore.create(name: "現場", at: root, now: date(0))
        let relay = IncidentRelayStub(reachable: false)
        let session = IncidentSession(relay: relay)
        _ = try session.open(opening(at: date(0), trigger: .manual), projectName: project.name, at: root)
        let pending = try session.closeDue(projectName: project.name, at: root, now: date(60))
        XCTAssertEqual(pending.map(\.delivery), [.pending])
        session.flush(projectName: project.name, at: root, now: date(70))
        XCTAssertTrue(relay.sent.isEmpty)
        relay.isReachable = true
        session.flush(projectName: project.name, at: root, now: date(80))
        XCTAssertEqual(relay.sent.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try sentURL(pending[0].record.id, project: project.name, root: root).path))
        session.flush(projectName: project.name, at: root, now: date(90))
        XCTAssertEqual(relay.sent.count, 1)
    }

    func testUnsealedIncidentResumesAfterRestart() throws {
        let root = try TestFiles.directory()
        defer { TestFiles.remove(root) }
        let project = try ProjectStore.create(name: "現場", at: root, now: date(0))
        let first = IncidentSession()
        let id = try first.open(opening(at: date(0), trigger: .alarm), projectName: project.name, at: root)
        first.observe([sample("この端末", at: 15)], projectName: project.name, at: root)
        let second = IncidentSession()
        second.restore(projectName: project.name, at: root)
        XCTAssertEqual(second.latestID, id)
        let again = try second.open(opening(at: date(5), trigger: .alarm), projectName: project.name, at: root)
        XCTAssertEqual(again, id)
        let sealed = try second.closeDue(projectName: project.name, at: root, now: date(60))
        XCTAssertEqual(sealed.first?.record.track.count, 1)
    }

    private func sentURL(_ id: UUID, project: String, root: URL) throws -> URL {
        try IncidentBook.directory(incidentID: id, projectName: project, at: root).appendingPathComponent(IncidentBook.sentName)
    }

    private func opening(at date: Date, trigger: IncidentTrigger) -> IncidentOpening {
        let id = trigger == .alarm ? UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")! : UUID()
        return IncidentOpening(
            id: id,
            projectID: "project",
            projectName: "現場",
            occurredAt: date,
            trigger: trigger,
            parties: [
                IncidentParty(
                    id: "この端末",
                    name: "この端末",
                    role: .machine,
                    latitudeDegrees: 36,
                    longitudeDegrees: 139.8333333333,
                    horizontalAccuracyMeters: 3.2,
                    stationText: "No.0+0.0m",
                    facingDegrees: 90,
                    facingSource: "進行",
                    distanceMeters: nil,
                    workRadiusMeters: 9
                )
            ],
            machineRadiusMeters: 9,
            work: IncidentWork(kind: "下見", name: "起点"),
            accuracyMeters: 3.2,
            stageLabel: "段階0",
            solutionLabel: "単独",
            speeches: [],
            radio: []
        )
    }

    private func sample(_ id: String, at seconds: TimeInterval) -> IncidentSample {
        IncidentSample(
            at: date(seconds),
            id: id,
            name: id,
            role: id == "この端末" ? .machine : .worker,
            latitudeDegrees: 36,
            longitudeDegrees: 139.8333333333,
            horizontalAccuracyMeters: 3
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + seconds)
    }

    private func utf16(_ text: String) -> String {
        "FEFF" + codeUnits(text)
    }

    private func codeUnits(_ text: String) -> String {
        text.utf16.reduce(into: "") { hex, unit in
            hex += String(format: "%04X", unit)
        }
    }
}
