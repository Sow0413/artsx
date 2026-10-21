import XCTest
@testable import SurveyCore

final class SurveyListTests: XCTestCase {
    func testSurveyListKeepsTheCurrentModeAndDropsLevelShots() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let preview = shot("T1", work: "preview", at: now, project: "site")
        let older = shot("T1", work: "preview", at: now.addingTimeInterval(-60), project: "site")
        let rough = shot("T2", work: "rough", at: now, project: "site")
        let traverse = shot("T3", work: "traverse", at: now, project: "site")
        let boundary = shot("T4", work: "boundary", at: now, project: "site")
        let stakeout = shot("S1", work: "stakeout", at: now, project: "site")
        let level = shot("L1", work: "preview", at: now, project: "site", origin: SurveyList.levelOrigin)
        let legacy = shot("L2", work: "preview", at: now, project: "site")
        let otherSite = shot("X1", work: "traverse", at: now, project: "other")
        let legacyNilProject = shot("N1", work: "rough", at: now, project: nil)

        let groups = SurveyList.grouped(
            [preview, older, rough, traverse, boundary, stakeout, level, legacy, otherSite, legacyNilProject],
            groups: SurveyList.surveyGroups,
            bookKinds: ["L2": SurveyList.levelKind],
            projectID: "site"
        )

        XCTAssertEqual(groups.map(\.title), ["下見", "概略", "測量", "境界"])
        XCTAssertEqual(groups[0].rows.map(\.name), ["T1"])
        XCTAssertEqual(groups[0].rows[0].captured.timestamp, now)
        XCTAssertEqual(groups[1].rows.map(\.name), ["N1", "T2"])
        XCTAssertEqual(groups[2].rows.map(\.name), ["T3"])
        XCTAssertEqual(groups[3].rows.map(\.name), ["T4"])
        XCTAssertFalse(groups.flatMap(\.rows).contains { $0.name == "S1" || $0.name == "L1" || $0.name == "L2" || $0.name == "X1" })
    }

    func testBuildListOmitsSurveyAndLevelPoints() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let groups = SurveyList.grouped(
            [
                shot("S1", work: "stakeout", at: now, project: "site"),
                shot("A1", work: "asBuilt", at: now, project: "site"),
                shot("T1", work: "preview", at: now, project: "site"),
                shot("L1", work: "stakeout", at: now, project: "site", origin: SurveyList.levelOrigin)
            ],
            groups: SurveyList.buildGroups,
            bookKinds: [:],
            projectID: "site"
        )
        XCTAssertEqual(groups.map(\.title), ["丁張", "出来形"])
        XCTAssertEqual(groups.flatMap(\.rows).map(\.name), ["S1", "A1"])
    }

    func testTrashKeepsAPointForThirtyDays() {
        let deleted = Date(timeIntervalSince1970: 1_700_000_000)
        let item = TrashedPoint(name: "T1", deletedAt: deleted, payload: PointTrashPayload())
        XCTAssertFalse(item.isExpired(at: deleted.addingTimeInterval(29 * 24 * 60 * 60)))
        XCTAssertEqual(item.daysLeft(at: deleted), 30)
        XCTAssertEqual(item.daysLeft(at: deleted.addingTimeInterval(29 * 24 * 60 * 60)), 1)
        XCTAssertTrue(item.isExpired(at: deleted.addingTimeInterval(TrashedPoint.retention)))
        XCTAssertEqual(item.daysLeft(at: deleted.addingTimeInterval(31 * 24 * 60 * 60)), 0)
    }

    func testRetakeArchivesTheBookAndTrashRestoresIt() throws {
        let directory = try TestFiles.directory()
        defer { TestFiles.remove(directory) }
        let journal = FieldJournal(directory: directory)
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let observation = shot("K1", work: "traverse", at: when, project: "site")
        try journal.commit(observation)
        try journal.upsertBook(book("K1", height: 10, at: when))
        try journal.archiveBook(named: "K1", at: when)
        try journal.upsertBook(book("K1", height: 12.5, at: when.addingTimeInterval(60)))

        XCTAssertEqual(journal.bookEntry(named: "K1")?.ellipsoidalHeightMeters, 12.5)
        let history = journal.bookHistory(named: "K1")
        XCTAssertEqual(history.map { $0.entry.ellipsoidalHeightMeters }, [10])

        let removed = journal.removeBook(named: "K1")
        try journal.removeObservations(ids: [observation.id])
        let kept = TrashedPoint(
            name: "K1",
            deletedAt: when,
            payload: PointTrashPayload(observations: [observation], book: removed)
        )
        let expired = TrashedPoint(
            name: "OLD",
            deletedAt: when.addingTimeInterval(-31 * 24 * 60 * 60),
            payload: PointTrashPayload()
        )
        try journal.trash(kept)
        try journal.trash(expired)
        XCTAssertTrue(journal.observations(named: "K1").isEmpty)
        XCTAssertNil(journal.bookEntry(named: "K1"))

        let purged = journal.purgeTrash(at: when)
        XCTAssertEqual(purged.map(\.name), ["OLD"])
        XCTAssertEqual(journal.trashedPoints().map(\.name), ["K1"])

        let taken = try XCTUnwrap(journal.takeTrash(id: kept.id))
        XCTAssertTrue(journal.trashedPoints().isEmpty)
        XCTAssertEqual(journal.bookHistory(named: "K1").count, 1)
        try journal.commit(taken.payload.observations[0])
        try journal.upsertBook(try XCTUnwrap(taken.payload.book))
        XCTAssertEqual(journal.observations(named: "K1").map(\.id), [observation.id])
        XCTAssertEqual(journal.bookEntry(named: "K1")?.ellipsoidalHeightMeters, 12.5)
    }

    func testRecordListKeepsOneFilePerNameAndTrashHidesIt() throws {
        let root = try TestFiles.directory()
        defer { TestFiles.remove(root) }
        let early = Date(timeIntervalSince1970: 1_700_000_000)
        let later = early.addingTimeInterval(3600)
        try FieldRecordStore.write(file("P1", at: early), root: root, place: "日光")
        try FieldRecordStore.write(file("P1", at: later), root: root, place: "日光")
        try FieldRecordStore.write(file("P2", at: later), root: root, place: "日光")

        XCTAssertEqual(FieldRecordStore.points(in: root, place: "日光").map(\.name), ["P1", "P2"])
        let files = FieldRecordStore.files(named: "P1", in: root, place: "日光")
        XCTAssertEqual(files.count, 2)

        let id = UUID()
        let paths = files.enumerated().map { index, url in
            FieldRecordStore.relativePath(of: url, root: root)
        }
        for (index, url) in files.enumerated() {
            try FieldRecordStore.moveToTrash(url, id: id, index: index, root: root)
        }
        XCTAssertEqual(FieldRecordStore.points(in: root, place: "日光").map(\.name), ["P2"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: files[0].path))

        for (index, path) in paths.enumerated() {
            try FieldRecordStore.restoreTrashFile(id: id, index: index, root: root, relativePath: path)
        }
        XCTAssertEqual(FieldRecordStore.points(in: root, place: "日光").map(\.name), ["P1", "P2"])
        XCTAssertEqual(FieldRecordStore.files(named: "P1", in: root, place: "日光").count, 2)
        FieldRecordStore.removeTrashFolder(id: id, root: root)
    }

    private func shot(
        _ name: String,
        work: String,
        at date: Date,
        project: String?,
        origin: String? = nil
    ) -> FieldObservation {
        FieldObservation(
            name: name,
            workID: work,
            captured: GeodeticPosition(
                latitudeDegrees: 36.77,
                longitudeDegrees: 139.20,
                ellipsoidalHeightMeters: 40,
                horizontalAccuracyMeters: 0.02,
                verticalAccuracyMeters: 0.03,
                timestamp: date,
                stage: .iphone,
                fixQuality: .standalone,
                receiver: .iphoneGPS
            ),
            projectID: project,
            origin: origin
        )
    }

    private func book(_ name: String, height: Double, at date: Date) -> CoordinateBookEntry {
        CoordinateBookEntry(
            name: name,
            latitudeDegrees: 36.77,
            longitudeDegrees: 139.20,
            ellipsoidalHeightMeters: height,
            horizontalAccuracyMeters: 0.02,
            verticalAccuracyMeters: 0.03,
            satelliteCount: 8,
            fixDurationSeconds: 0,
            recordedAt: date,
            kind: "下見"
        )
    }

    private func file(_ name: String, at date: Date) -> FieldPointFile {
        FieldPointFile(
            name: name,
            latitude: 36.77,
            longitude: 139.20,
            ellipsoidalHeightMeters: 40,
            orthometricHeightMeters: 0,
            geoidModel: nil,
            horizontalAccuracyMeters: 1,
            verticalAccuracyMeters: 2,
            timestamp: date
        )
    }
}
