#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif
import Foundation

/// 座標簿は端末の SQLite。通信は使わない。名前、種類、出典、段階、日付、緯度経度に索引を置く。
public enum CoordinateBookStore {
    public static let fileName = "book.sqlite"

    public static func fileURL(projectDirectory: URL) -> URL {
        projectDirectory.appendingPathComponent("座標簿", isDirectory: true).appendingPathComponent(fileName)
    }

    public static func exists(projectDirectory: URL) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(projectDirectory: projectDirectory).path)
    }

    /// 強制終了のあとでも、コミット済みの行は WAL に残る。
    public static func journalMode(projectDirectory: URL) -> String {
        guard exists(projectDirectory: projectDirectory), let db = try? open(projectDirectory) else { return "" }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA journal_mode", -1, &statement, nil) == SQLITE_OK else { return "" }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let raw = sqlite3_column_text(statement, 0) else { return "" }
        return String(cString: raw)
    }

    public static func upsert(_ entries: [CoordinateBookEntry], projectDirectory: URL) throws {
        guard !entries.isEmpty else { return }
        let db = try open(projectDirectory)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else { throw ProjectStoreError.unreadable }
        defer { sqlite3_finalize(statement) }
        try exec(db, "BEGIN")
        for entry in entries {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bind(entry, to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                throw ProjectStoreError.unreadable
            }
        }
        try exec(db, "COMMIT")
    }

    public static func names(projectDirectory: URL) -> Set<String> {
        guard exists(projectDirectory: projectDirectory), let db = try? open(projectDirectory) else { return [] }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name FROM points", -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var names: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = text(statement, 0) { names.insert(name) }
        }
        return names
    }

    public static func count(projectDirectory: URL) -> Int {
        guard exists(projectDirectory: projectDirectory), let db = try? open(projectDirectory) else { return 0 }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT count(*) FROM points", -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    public static func entries(projectDirectory: URL) -> [CoordinateBookEntry] {
        filter(CoordinateBookQuery(), projectDirectory: projectDirectory)
    }

    public static func filter(_ query: CoordinateBookQuery, projectDirectory: URL, limit: Int? = nil) -> [CoordinateBookEntry] {
        guard exists(projectDirectory: projectDirectory), let db = try? open(projectDirectory) else { return [] }
        defer { sqlite3_close(db) }
        let clause = whereClause(query)
        var sql = "SELECT \(columns) FROM points\(clause.sql) ORDER BY name"
        var binds = clause.binds
        if let limit, limit > 0 {
            sql += " LIMIT ?"
            binds.append(.int(limit))
        }
        return readRows(db, sql: sql, binds: binds)
    }

    public static func matchCount(_ query: CoordinateBookQuery, projectDirectory: URL) -> Int {
        guard exists(projectDirectory: projectDirectory), let db = try? open(projectDirectory) else { return 0 }
        defer { sqlite3_close(db) }
        let clause = whereClause(query)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT count(*) FROM points\(clause.sql)", -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }
        bind(clause.binds, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    /// 同じ絞り込みに、この名前の行が残っているか。
    public static func matches(name: String, query: CoordinateBookQuery, projectDirectory: URL) -> Bool {
        guard exists(projectDirectory: projectDirectory), let db = try? open(projectDirectory) else { return false }
        defer { sqlite3_close(db) }
        let clause = whereClause(query)
        var statement: OpaquePointer?
        let sql = "SELECT 1 FROM points\(clause.sql) AND name = ? LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        var binds = clause.binds
        binds.append(.text(name))
        bind(binds, to: statement)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private enum SQLValue {
        case text(String)
        case int(Int)
        case double(Double)
    }

    private static let columns = "name, latitude, longitude, height, horizontal, vertical, satellites, duration, recorded_at, recorded_day, kind, source, stage, solution, pdop, correction_age, correction_source, epochs, receiver, satellite_note"
    private static let insertSQL = """
    INSERT INTO points (\(columns), name_key) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ON CONFLICT(name) DO UPDATE SET
        latitude=excluded.latitude, longitude=excluded.longitude, height=excluded.height,
        horizontal=excluded.horizontal, vertical=excluded.vertical, satellites=excluded.satellites,
        duration=excluded.duration, recorded_at=excluded.recorded_at, recorded_day=excluded.recorded_day,
        kind=excluded.kind, source=excluded.source, stage=excluded.stage, solution=excluded.solution,
        pdop=excluded.pdop, correction_age=excluded.correction_age, correction_source=excluded.correction_source,
        epochs=excluded.epochs, receiver=excluded.receiver, satellite_note=excluded.satellite_note,
        name_key=excluded.name_key
    """

    private static func open(_ projectDirectory: URL) throws -> OpaquePointer? {
        let folder = projectDirectory.appendingPathComponent("座標簿", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var db: OpaquePointer?
        let path = fileURL(projectDirectory: projectDirectory).path
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else { throw ProjectStoreError.unreadable }
        try exec(db, "PRAGMA journal_mode=WAL")
        try exec(db, "PRAGMA synchronous=NORMAL")
        try exec(db, """
        CREATE TABLE IF NOT EXISTS points (
            name TEXT PRIMARY KEY,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            height REAL,
            horizontal REAL NOT NULL,
            vertical REAL,
            satellites INTEGER,
            duration REAL NOT NULL,
            recorded_at REAL NOT NULL,
            recorded_day TEXT NOT NULL,
            kind TEXT,
            source TEXT,
            stage INTEGER,
            solution TEXT,
            pdop REAL,
            correction_age REAL,
            correction_source TEXT,
            epochs INTEGER,
            receiver TEXT,
            satellite_note TEXT,
            name_key TEXT NOT NULL DEFAULT ''
        )
        """)
        try exec(db, "CREATE INDEX IF NOT EXISTS points_name_key ON points(name_key)")
        try exec(db, "CREATE INDEX IF NOT EXISTS points_kind ON points(kind)")
        try exec(db, "CREATE INDEX IF NOT EXISTS points_source ON points(source)")
        try exec(db, "CREATE INDEX IF NOT EXISTS points_stage ON points(stage)")
        try exec(db, "CREATE INDEX IF NOT EXISTS points_day ON points(recorded_day)")
        try exec(db, "CREATE INDEX IF NOT EXISTS points_lat_lon ON points(latitude, longitude)")
        return db
    }

    private static func whereClause(_ query: CoordinateBookQuery) -> (sql: String, binds: [SQLValue]) {
        var sql = " WHERE 1=1"
        var binds: [SQLValue] = []
        let prefix = query.namePrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prefix.isEmpty {
            sql += " AND name_key LIKE ? ESCAPE '\\'"
            binds.append(.text(likePrefix(prefix.uppercased())))
        }
        let kind = query.kind.trimmingCharacters(in: .whitespacesAndNewlines)
        if !kind.isEmpty {
            sql += " AND kind = ?"
            binds.append(.text(kind))
        }
        let source = query.source.trimmingCharacters(in: .whitespacesAndNewlines)
        if !source.isEmpty {
            sql += " AND source = ?"
            binds.append(.text(source))
        }
        if let stage = query.minimumStage {
            sql += " AND stage >= ?"
            binds.append(.int(stage.rawValue))
        }
        if let accuracy = query.maximumHorizontalMeters {
            sql += " AND source != '既知点' AND horizontal <= ?"
            binds.append(.double(accuracy))
        }
        if let day = query.importedDay, !day.isEmpty {
            sql += " AND recorded_day = ?"
            binds.append(.text(day))
        }
        if let bounds = query.bounds {
            sql += " AND latitude >= ? AND latitude <= ? AND longitude >= ? AND longitude <= ?"
            binds.append(.double(bounds.south))
            binds.append(.double(bounds.north))
            binds.append(.double(bounds.west))
            binds.append(.double(bounds.east))
        }
        return (sql, binds)
    }

    private static func readRows(_ db: OpaquePointer?, sql: String, binds: [SQLValue]) -> [CoordinateBookEntry] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(binds, to: statement)
        var rows: [CoordinateBookEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let entry = read(statement) { rows.append(entry) }
        }
        return rows
    }

    private static func bind(_ values: [SQLValue], to statement: OpaquePointer?) {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case let .text(text):
                bind(statement, index, text)
            case let .int(value):
                sqlite3_bind_int(statement, index, Int32(value))
            case let .double(value):
                sqlite3_bind_double(statement, index, value)
            }
        }
    }

    private static func bind(_ entry: CoordinateBookEntry, to statement: OpaquePointer?) {
        bind(statement, 1, entry.name)
        sqlite3_bind_double(statement, 2, entry.latitudeDegrees)
        sqlite3_bind_double(statement, 3, entry.longitudeDegrees)
        bind(statement, 4, entry.ellipsoidalHeightMeters)
        sqlite3_bind_double(statement, 5, entry.horizontalAccuracyMeters)
        bind(statement, 6, entry.verticalAccuracyMeters)
        bind(statement, 7, entry.satelliteCount)
        sqlite3_bind_double(statement, 8, entry.fixDurationSeconds)
        sqlite3_bind_double(statement, 9, entry.recordedAt.timeIntervalSince1970)
        bind(statement, 10, CoordinateBookQuery.day(of: entry.recordedAt))
        bind(statement, 11, entry.kind)
        bind(statement, 12, entry.source)
        bind(statement, 13, entry.stage?.rawValue)
        bind(statement, 14, entry.solution?.rawValue)
        bind(statement, 15, entry.pdop)
        bind(statement, 16, entry.correctionAgeSeconds)
        bind(statement, 17, entry.correctionSource)
        bind(statement, 18, entry.epochCount)
        bind(statement, 19, entry.receiverLabel)
        bind(statement, 20, entry.satelliteNote)
        bind(statement, 21, entry.name.uppercased())
    }

    private static func read(_ statement: OpaquePointer?) -> CoordinateBookEntry? {
        guard let name = text(statement, 0) else { return nil }
        let stage = sqlite3_column_type(statement, 12) == SQLITE_NULL ? nil : PositionStage(rawValue: Int(sqlite3_column_int(statement, 12)))
        let solution = text(statement, 13).flatMap(FixQuality.init(rawValue:))
        return CoordinateBookEntry(
            name: name,
            latitudeDegrees: sqlite3_column_double(statement, 1),
            longitudeDegrees: sqlite3_column_double(statement, 2),
            ellipsoidalHeightMeters: optionalDouble(statement, 3),
            horizontalAccuracyMeters: sqlite3_column_double(statement, 4),
            verticalAccuracyMeters: optionalDouble(statement, 5),
            satelliteCount: optionalInt(statement, 6),
            fixDurationSeconds: sqlite3_column_double(statement, 7),
            recordedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 8)),
            kind: text(statement, 10),
            source: text(statement, 11),
            stage: stage,
            solution: solution,
            pdop: optionalDouble(statement, 14),
            correctionAgeSeconds: optionalDouble(statement, 15),
            correctionSource: text(statement, 16),
            epochCount: optionalInt(statement, 17),
            receiverLabel: text(statement, 18),
            satelliteNote: text(statement, 19)
        )
    }

    private static func exec(_ db: OpaquePointer?, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw ProjectStoreError.unreadable }
    }

    private static func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private static func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: Double?) {
        if let value {
            sqlite3_bind_double(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private static func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: Int?) {
        if let value {
            sqlite3_bind_int(statement, index, Int32(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private static func text(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL, let raw = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: raw)
    }

    private static func optionalDouble(_ statement: OpaquePointer?, _ index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, index)
    }

    private static func optionalInt(_ statement: OpaquePointer?, _ index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int(statement, index))
    }

    private static func likePrefix(_ prefix: String) -> String {
        var escaped = ""
        for character in prefix {
            if character == "\\" || character == "%" || character == "_" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped + "%"
    }
}
