import XCTest
@testable import SurveyCore

final class StabilityTests: XCTestCase {
    func testForceQuitRestoresTheScreenAndTheOpenFix() throws {
        let directory = try TestFiles.directory()
        defer { TestFiles.remove(directory) }
        let began = Date().addingTimeInterval(-40)
        let position = fixPosition(at: began.addingTimeInterval(40))
        var journal = FieldJournal(directory: directory)
        let kept = try journal.commit(observation(name: "T1", at: began))
        try journal.save(FieldSession(
            tab: "measure",
            projectName: "北線",
            workID: "boundary",
            fixBeganAt: began,
            fixEpochCount: 12,
            fixRestarted: false,
            fixPosition: position
        ))
        XCTAssertEqual(journal.journalMode(), "wal")
        journal.close()
        journal = FieldJournal(directory: directory)
        let session = journal.session()
        XCTAssertEqual(session.tab, "measure")
        XCTAssertEqual(session.projectName, "北線")
        XCTAssertEqual(session.workID, "boundary")
        XCTAssertEqual(session.fixEpochCount, 12)
        XCTAssertEqual(session.fixPosition?.latitudeDegrees ?? 0, position.latitudeDegrees, accuracy: 1e-9)
        let restored = session.controlFix
        let seconds = restored.continuousSeconds(at: Date()) ?? 0
        XCTAssertGreaterThan(seconds, 30)
        XCTAssertEqual(journal.count(), 1)
        XCTAssertEqual(journal.names(), [kept.name])
        XCTAssertEqual(journal.recent().map(\.name), ["T1"])
    }

    func testUncommittedObservationIsDroppedAndTheCommittedOneStays() throws {
        let directory = try TestFiles.directory()
        defer { TestFiles.remove(directory) }
        let journal = FieldJournal(directory: directory)
        try journal.commit(observation(name: "T1", at: Date()))
        journal.crashDuringInsert(observation(name: "T2", at: Date()))
        let again = FieldJournal(directory: directory)
        XCTAssertEqual(again.names(), ["T1"])
        XCTAssertEqual(again.journalMode(), "wal")
    }

    func testCoordinateBookCommitSurvivesReopen() throws {
        let root = try TestFiles.directory()
        defer { TestFiles.remove(root) }
        let project = try ProjectStore.create(name: "北線", at: root)
        let entry = CoordinateBookEntry(
            name: "K1",
            latitudeDegrees: 35.0,
            longitudeDegrees: 139.0,
            ellipsoidalHeightMeters: 10,
            horizontalAccuracyMeters: 0.02,
            verticalAccuracyMeters: 0.03,
            satelliteCount: 12,
            fixDurationSeconds: 8,
            recordedAt: Date(),
            kind: "基準点",
            source: "観測"
        )
        try ProjectStore.saveCoordinate(entry, projectName: project.name, at: root)
        let directory = root.appendingPathComponent(project.name, isDirectory: true)
        XCTAssertEqual(CoordinateBookStore.journalMode(projectDirectory: directory), "wal")
        XCTAssertEqual(CoordinateBookStore.count(projectDirectory: directory), 1)
        XCTAssertTrue(CoordinateBookStore.names(projectDirectory: directory).contains("K1"))

        let site = FieldJournal(directory: directory)
        try site.upsertBook(entry)
        site.close()
        let reopened = FieldJournal(directory: directory)
        XCTAssertEqual(reopened.bookCount(), 1)
        XCTAssertEqual(reopened.journalMode(), "wal")
        XCTAssertEqual(SiteCoordinateBook.load(from: directory).map(\.name), ["K1"])
    }

    func testLargeJournalRestoreStaysUnderTheMemoryCeiling() throws {
        let directory = try TestFiles.directory()
        defer { TestFiles.remove(directory) }
        let journal = FieldJournal(directory: directory)
        let started = Date()
        for index in 0..<FieldJournal.largePointCount {
            try journal.commit(observation(name: "P\(index)", at: started.addingTimeInterval(Double(index))))
        }
        try journal.save(FieldSession(tab: "drawing", projectName: "長い現場", fixEpochCount: 3, fixRestarted: true))
        journal.close()
        let before = ProcessFootprint.residentMegabytes()
        let again = FieldJournal(directory: directory)
        let session = again.session()
        let shown = again.recent()
        let after = ProcessFootprint.residentMegabytes()
        print(String(format: "SURVEY BENCH 大規模復帰 %.1fMB / 目標 %.1fMB 以内 点 %d 表示 %d", after - before, FieldJournal.restoreMegabytes, again.count(), shown.count))
        XCTAssertEqual(again.count(), FieldJournal.largePointCount)
        XCTAssertEqual(session.tab, "drawing")
        XCTAssertEqual(session.projectName, "長い現場")
        XCTAssertLessThanOrEqual(shown.count, FieldJournal.recentLimit)
        XCTAssertGreaterThan(shown.count, 0)
        guard before >= 0, after >= 0 else {
            throw XCTSkip("メモリを測れない")
        }
        XCTAssertLessThanOrEqual(after - before, FieldJournal.restoreMegabytes)
    }

    func testDisconnectDoesNotBlockAndThenReconnects() {
        let radio = ScriptedGNSSRadio()
        let link = GNSSLink(radio: radio, retryDelay: 0.05)
        let live = expectation(description: "live")
        link.onState = { state in
            if state == .live { live.fulfill() }
        }
        link.resume()
        wait(for: [live], timeout: 2)

        let again = expectation(description: "reconnected")
        var sawDrop = false
        link.onState = { state in
            if state == .reconnecting { sawDrop = true }
            if state == .live, sawDrop { again.fulfill() }
        }
        let started = Date()
        radio.drop()
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.05)
        wait(for: [again], timeout: 2)
        XCTAssertGreaterThanOrEqual(radio.starts, 2)
        XCTAssertEqual(link.state, .live)
    }

    private func observation(name: String, at date: Date) -> FieldObservation {
        FieldObservation(name: name, workID: "stakeout", captured: fixPosition(at: date))
    }

    private func fixPosition(at date: Date) -> GeodeticPosition {
        GeodeticPosition(
            latitudeDegrees: 35.6,
            longitudeDegrees: 139.7,
            ellipsoidalHeightMeters: 40,
            horizontalAccuracyMeters: 0.02,
            verticalAccuracyMeters: 0.03,
            timestamp: date,
            stage: .rtk,
            fixQuality: .rtkFix,
            receiver: .rtk
        )
    }
}

private final class ScriptedGNSSRadio: GNSSRadio {
    var hasSavedDevice = true
    var onConnect: (() -> Void)?
    var onDrop: (() -> Void)?
    var onDiscover: ((GNSSChoice) -> Void)?
    var starts = 0

    func start() {
        starts += 1
        onConnect?()
    }

    func scan() {}

    func connect(_ id: String) {
        onConnect?()
    }

    func stop() {}

    func drop() {
        onDrop?()
    }
}
