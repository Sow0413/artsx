#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif
import Foundation

/// 落ちる直前の画面と、まだ点にしていない基準点の計測。
public struct FieldSession: Sendable, Equatable {
    public var tab: String
    public var projectName: String?
    public var workID: String?
    public var fixBeganAt: Date?
    public var fixEpochCount: Int
    public var fixRestarted: Bool
    public var fixPosition: GeodeticPosition?

    public init(
        tab: String = "map",
        projectName: String? = nil,
        workID: String? = nil,
        fixBeganAt: Date? = nil,
        fixEpochCount: Int = 0,
        fixRestarted: Bool = false,
        fixPosition: GeodeticPosition? = nil
    ) {
        self.tab = tab
        self.projectName = projectName
        self.workID = workID
        self.fixBeganAt = fixBeganAt
        self.fixEpochCount = fixEpochCount
        self.fixRestarted = fixRestarted
        self.fixPosition = fixPosition
    }

    public var controlFix: ControlFixSession {
        ControlFixSession(
            restoring: fixBeganAt,
            latest: fixPosition,
            epochCount: fixEpochCount,
            restarted: fixRestarted
        )
    }
}

/// 観測と現場の座標簿。変更はすぐコミットし、WAL に残す。通信は使わない。
public final class FieldJournal {
    public static let fileName = "現場.sqlite"
    public static let recentLimit = 80
    /// 起動で全件を展開したときに超えてはいけない、増分の目安。
    public static let restoreMegabytes = 64.0
    public static let largePointCount = 20_000

    private let directory: URL
    private var db: OpaquePointer?
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directory: URL) {
        self.directory = directory
        try? open()
    }

    deinit {
        close()
    }

    public static func exists(in directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path)
    }

    public func close() {
        lock.lock()
        sqlite3_close(db)
        db = nil
        lock.unlock()
    }

    public func journalMode() -> String {
        lock.lock()
        defer { lock.unlock() }
        return pragma("journal_mode")
    }

    @discardableResult
    public func commit(_ observation: FieldObservation) throws -> FieldObservation {
        try upsertObservation(observation)
        return observation
    }

    public func allObservations() -> [FieldObservation] {
        lock.lock()
        defer { lock.unlock() }
        return payloads("SELECT payload FROM observations ORDER BY recorded_at").compactMap(decodeObservation)
    }

    public func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return intQuery("SELECT count(*) FROM observations")
    }

    public func observations(named name: String) -> [FieldObservation] {
        lock.lock()
        defer { lock.unlock() }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM observations WHERE name = ? ORDER BY recorded_at", -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, name)
        return rows(statement).compactMap(decodeObservation)
    }

    public func names() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return stringSet("SELECT name FROM observations")
    }

    /// 画面に出す分だけ。残りは端末に置いたまま。
    public func recent() -> [FieldObservation] {
        lock.lock()
        defer { lock.unlock() }
        let sql = """
        SELECT payload FROM (
            SELECT payload, recorded_at FROM observations ORDER BY recorded_at DESC LIMIT \(Self.recentLimit)
        ) ORDER BY recorded_at ASC
        """
        return payloads(sql).compactMap(decodeObservation)
    }

    public func between(_ start: Date, and end: Date) -> [FieldObservation] {
        lock.lock()
        defer { lock.unlock() }
        var statement: OpaquePointer?
        let sql = "SELECT payload FROM observations WHERE recorded_at >= ? AND recorded_at <= ? ORDER BY recorded_at"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, end.timeIntervalSince1970)
        return rows(statement).compactMap(decodeObservation)
    }

    public func save(_ session: FieldSession) throws {
        lock.lock()
        defer { lock.unlock() }
        let sql = """
        INSERT INTO session (id, tab, project_name, work_id, fix_began, fix_epoch, fix_restarted, fix_position, updated_at)
        VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            tab=excluded.tab, project_name=excluded.project_name, work_id=excluded.work_id,
            fix_began=excluded.fix_began, fix_epoch=excluded.fix_epoch, fix_restarted=excluded.fix_restarted,
            fix_position=excluded.fix_position, updated_at=excluded.updated_at
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw ProjectStoreError.unreadable }
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, session.tab)
        bind(statement, 2, session.projectName)
        bind(statement, 3, session.workID)
        bind(statement, 4, session.fixBeganAt?.timeIntervalSince1970)
        sqlite3_bind_int(statement, 5, Int32(session.fixEpochCount))
        sqlite3_bind_int(statement, 6, session.fixRestarted ? 1 : 0)
        if let position = session.fixPosition, let data = try? encoder.encode(position) {
            bind(statement, 7, String(data: data, encoding: .utf8))
        } else {
            sqlite3_bind_null(statement, 7)
        }
        sqlite3_bind_double(statement, 8, Date().timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ProjectStoreError.unreadable }
    }

    public func session() -> FieldSession {
        lock.lock()
        defer { lock.unlock() }
        var statement: OpaquePointer?
        let sql = "SELECT tab, project_name, work_id, fix_began, fix_epoch, fix_restarted, fix_position FROM session WHERE id = 1"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return FieldSession() }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return FieldSession() }
        let began = sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
        let position = text(statement, 6).flatMap { decodePosition($0) }
        return FieldSession(
            tab: text(statement, 0) ?? "map",
            projectName: text(statement, 1),
            workID: text(statement, 2),
            fixBeganAt: began,
            fixEpochCount: Int(sqlite3_column_int(statement, 4)),
            fixRestarted: sqlite3_column_int(statement, 5) != 0,
            fixPosition: position
        )
    }

    public func upsertBook(_ entry: CoordinateBookEntry) throws {
        lock.lock()
        defer { lock.unlock() }
        let data = try encoder.encode(entry)
        guard let payload = String(data: data, encoding: .utf8) else { throw ProjectStoreError.unreadable }
        try writeBook(name: entry.name, payload: payload)
    }

    public func bookCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return intQuery("SELECT count(*) FROM book")
    }

    public func bookNames() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return stringSet("SELECT name FROM book")
    }

    public func bookEntries() -> [CoordinateBookEntry] {
        lock.lock()
        defer { lock.unlock() }
        return payloads("SELECT payload FROM book ORDER BY name").compactMap(decodeBook)
    }

    /// 点名の一部だけ読む。座標簿を全件展開しない。
    public func bookEntries(matching raw: String, limit: Int) -> [CoordinateBookEntry] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, limit > 0 else { return [] }
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        lock.lock()
        defer { lock.unlock() }
        let sql = "SELECT payload FROM book WHERE name LIKE ? ESCAPE '\\' ORDER BY name LIMIT ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, "%\(escaped)%")
        sqlite3_bind_int(statement, 2, Int32(min(limit, 100)))
        return rows(statement).compactMap(decodeBook)
    }

    public func bookEntry(named name: String) -> CoordinateBookEntry? {
        lock.lock()
        defer { lock.unlock() }
        return bookPayload(named: name).flatMap(decodeBook)
    }

    /// 今の座標簿の値を履歴に移す。取り直しの前に呼ぶ。点が無ければ何もしない。
    public func archiveBook(named name: String, at date: Date = Date()) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let payload = bookPayload(named: name) else { return }
        let sql = "INSERT INTO book_history (id, name, replaced_at, payload) VALUES (?, ?, ?, ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw ProjectStoreError.unreadable }
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, UUID().uuidString)
        bind(statement, 2, name)
        sqlite3_bind_double(statement, 3, date.timeIntervalSince1970)
        bind(statement, 4, payload)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ProjectStoreError.unreadable }
    }

    public func bookHistory(named name: String) -> [ArchivedBookEntry] {
        lock.lock()
        defer { lock.unlock() }
        let sql = "SELECT id, name, replaced_at, payload FROM book_history WHERE name = ? ORDER BY replaced_at DESC"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, name)
        var entries: [ArchivedBookEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = text(statement, 0), let id = UUID(uuidString: idText),
                  let storedName = text(statement, 1),
                  let payload = text(statement, 3),
                  let entry = decodeBook(payload) else { continue }
            entries.append(ArchivedBookEntry(
                id: id,
                name: storedName,
                replacedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                entry: entry
            ))
        }
        return entries
    }

    public func bookKinds(for names: [String]) -> [String: String] {
        var kinds: [String: String] = [:]
        for name in Set(names) {
            if let kind = bookEntry(named: name)?.kind {
                kinds[name] = kind
            }
        }
        return kinds
    }

    @discardableResult
    public func removeBook(named name: String) -> CoordinateBookEntry? {
        lock.lock()
        defer { lock.unlock() }
        guard let payload = bookPayload(named: name), let entry = decodeBook(payload) else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM book WHERE name = ?", -1, &statement, nil) == SQLITE_OK else { return nil }
        bind(statement, 1, name)
        let status = sqlite3_step(statement)
        sqlite3_finalize(statement)
        guard status == SQLITE_DONE else { return nil }
        return entry
    }

    public func removeObservations(ids: [UUID]) throws {
        lock.lock()
        defer { lock.unlock() }
        for id in ids {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM observations WHERE id = ?", -1, &statement, nil) == SQLITE_OK else {
                throw ProjectStoreError.unreadable
            }
            bind(statement, 1, id.uuidString)
            let status = sqlite3_step(statement)
            sqlite3_finalize(statement)
            guard status == SQLITE_DONE else { throw ProjectStoreError.unreadable }
        }
    }

    public func trash(_ item: TrashedPoint) throws {
        lock.lock()
        defer { lock.unlock() }
        let data = try encoder.encode(item.payload)
        guard let payload = String(data: data, encoding: .utf8) else { throw ProjectStoreError.unreadable }
        let sql = "INSERT INTO trash (id, name, deleted_at, payload) VALUES (?, ?, ?, ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw ProjectStoreError.unreadable }
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, item.id.uuidString)
        bind(statement, 2, item.name)
        sqlite3_bind_double(statement, 3, item.deletedAt.timeIntervalSince1970)
        bind(statement, 4, payload)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ProjectStoreError.unreadable }
    }

    public func trashedPoints() -> [TrashedPoint] {
        lock.lock()
        defer { lock.unlock() }
        return readTrash()
    }

    /// 行をゴミ箱から外して返す。復元する側が中身を戻す。
    public func takeTrash(id: UUID) -> TrashedPoint? {
        lock.lock()
        defer { lock.unlock() }
        guard let item = readTrash().first(where: { $0.id == id }) else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM trash WHERE id = ?", -1, &statement, nil) == SQLITE_OK else { return nil }
        bind(statement, 1, id.uuidString)
        let status = sqlite3_step(statement)
        sqlite3_finalize(statement)
        guard status == SQLITE_DONE else { return nil }
        return item
    }

    /// 30日を過ぎた行を消して返す。ファイルの削除は呼び出し側。
    public func purgeTrash(at now: Date) -> [TrashedPoint] {
        lock.lock()
        defer { lock.unlock() }
        let expired = readTrash().filter { $0.isExpired(at: now) }
        for item in expired {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM trash WHERE id = ?", -1, &statement, nil) == SQLITE_OK else { continue }
            bind(statement, 1, item.id.uuidString)
            _ = sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
        return expired
    }

    /// 古い JSON が残っていて SQLite が空のときだけ、一度取り込む。
    public func importLegacyIfNeeded() {
        if count() == 0 {
            let url = directory.appendingPathComponent(FieldObservationLog.fileName)
            if let data = try? Data(contentsOf: url),
               let log = try? JSONDecoder().decode(FieldObservationLog.self, from: data) {
                for observation in log.observations {
                    _ = try? commit(observation)
                }
            }
        }
        if bookCount() == 0 {
            let url = directory.appendingPathComponent(SiteCoordinateBook.fileName)
            guard let data = try? Data(contentsOf: url) else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let entries = (try? decoder.decode([CoordinateBookEntry].self, from: data)) ?? []
            for entry in entries {
                try? upsertBook(entry)
            }
        }
    }

    /// コミットする前に接続を捨てる。確定済みの行だけが残る。
    public func crashDuringInsert(_ observation: FieldObservation) {
        lock.lock()
        sqlite3_exec(db, "BEGIN", nil, nil, nil)
        if let data = try? encoder.encode(observation), let payload = String(data: data, encoding: .utf8) {
            var statement: OpaquePointer?
            let sql = "INSERT INTO observations (id, name, recorded_at, payload) VALUES (?, ?, ?, ?)"
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                bind(statement, 1, observation.id.uuidString)
                bind(statement, 2, observation.name)
                sqlite3_bind_double(statement, 3, observation.captured.timestamp.timeIntervalSince1970)
                bind(statement, 4, payload)
                _ = sqlite3_step(statement)
                sqlite3_finalize(statement)
            }
        }
        sqlite3_close(db)
        db = nil
        lock.unlock()
    }

    private func open() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let path = directory.appendingPathComponent(Self.fileName).path
        guard sqlite3_open(path, &handle) == SQLITE_OK, let handle else { throw ProjectStoreError.unreadable }
        db = handle
        try exec("PRAGMA journal_mode=WAL")
        try exec("PRAGMA synchronous=NORMAL")
        try exec("""
        CREATE TABLE IF NOT EXISTS observations (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            recorded_at REAL NOT NULL,
            payload TEXT NOT NULL
        )
        """)
        try exec("CREATE INDEX IF NOT EXISTS observations_time ON observations(recorded_at)")
        try exec("""
        CREATE TABLE IF NOT EXISTS book (
            name TEXT PRIMARY KEY,
            payload TEXT NOT NULL
        )
        """)
        try exec("""
        CREATE TABLE IF NOT EXISTS session (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            tab TEXT NOT NULL,
            project_name TEXT,
            work_id TEXT,
            fix_began REAL,
            fix_epoch INTEGER NOT NULL,
            fix_restarted INTEGER NOT NULL,
            fix_position TEXT,
            updated_at REAL NOT NULL
        )
        """)
        try exec("""
        CREATE TABLE IF NOT EXISTS book_history (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            replaced_at REAL NOT NULL,
            payload TEXT NOT NULL
        )
        """)
        try exec("CREATE INDEX IF NOT EXISTS book_history_name ON book_history(name, replaced_at)")
        try exec("""
        CREATE TABLE IF NOT EXISTS trash (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            deleted_at REAL NOT NULL,
            payload TEXT NOT NULL
        )
        """)
    }

    private func upsertObservation(_ observation: FieldObservation) throws {
        lock.lock()
        defer { lock.unlock() }
        let data = try encoder.encode(observation)
        guard let payload = String(data: data, encoding: .utf8) else { throw ProjectStoreError.unreadable }
        let sql = """
        INSERT INTO observations (id, name, recorded_at, payload) VALUES (?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET name=excluded.name, recorded_at=excluded.recorded_at, payload=excluded.payload
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw ProjectStoreError.unreadable }
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, observation.id.uuidString)
        bind(statement, 2, observation.name)
        sqlite3_bind_double(statement, 3, observation.captured.timestamp.timeIntervalSince1970)
        bind(statement, 4, payload)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ProjectStoreError.unreadable }
    }

    private func writeBook(name: String, payload: String) throws {
        let sql = """
        INSERT INTO book (name, payload) VALUES (?, ?)
        ON CONFLICT(name) DO UPDATE SET payload=excluded.payload
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw ProjectStoreError.unreadable }
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, name)
        bind(statement, 2, payload)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ProjectStoreError.unreadable }
    }

    private func pragma(_ name: String) -> String {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA \(name)", -1, &statement, nil) == SQLITE_OK else { return "" }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let raw = sqlite3_column_text(statement, 0) else { return "" }
        return String(cString: raw)
    }

    private func intQuery(_ sql: String) -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func stringSet(_ sql: String) -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var names: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = text(statement, 0) { names.insert(name) }
        }
        return names
    }

    private func payloads(_ sql: String) -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        return rows(statement)
    }

    private func rows(_ statement: OpaquePointer?) -> [String] {
        var values: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let value = text(statement, 0) { values.append(value) }
        }
        return values
    }

    private func decodeObservation(_ payload: String) -> FieldObservation? {
        guard let data = payload.data(using: .utf8) else { return nil }
        return try? decoder.decode(FieldObservation.self, from: data)
    }

    private func readTrash() -> [TrashedPoint] {
        let sql = "SELECT id, name, deleted_at, payload FROM trash ORDER BY deleted_at DESC"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var items: [TrashedPoint] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = text(statement, 0), let id = UUID(uuidString: idText),
                  let name = text(statement, 1),
                  let payload = text(statement, 3),
                  let data = payload.data(using: .utf8),
                  let body = try? decoder.decode(PointTrashPayload.self, from: data) else { continue }
            items.append(TrashedPoint(
                id: id,
                name: name,
                deletedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                payload: body
            ))
        }
        return items
    }

    private func bookPayload(named name: String) -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM book WHERE name = ?", -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, name)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return text(statement, 0)
    }

    private func decodeBook(_ payload: String) -> CoordinateBookEntry? {
        guard let data = payload.data(using: .utf8) else { return nil }
        return try? decoder.decode(CoordinateBookEntry.self, from: data)
    }

    private func decodePosition(_ payload: String) -> GeodeticPosition? {
        guard let data = payload.data(using: .utf8) else { return nil }
        return try? decoder.decode(GeodeticPosition.self, from: data)
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw ProjectStoreError.unreadable }
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: Double?) {
        if let value {
            sqlite3_bind_double(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL, let raw = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: raw)
    }
}

public enum ProcessFootprint {
    /// 今のプロセスが使っている物理メモリ。測れない環境は -1。
    public static func residentMegabytes() -> Double {
        guard let text = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8) else { return -1 }
        for line in text.split(separator: "\n") where line.hasPrefix("VmRSS:") {
            let numbers = line.split(separator: " ").compactMap { Double($0) }
            if let kilobytes = numbers.first { return kilobytes / 1024 }
        }
        return -1
    }
}
