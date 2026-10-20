import Foundation

public struct ProjectDrawing: Codable, Equatable, Sendable {
    public var fileName: String
    public var importedAt: Date
    public var codePage: String
    public var unsupported: [String: Int]

    public init(fileName: String, importedAt: Date, codePage: String, unsupported: [String: Int]) {
        self.fileName = fileName
        self.importedAt = importedAt
        self.codePage = codePage
        self.unsupported = unsupported
    }
}

public struct SurveyProject: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var createdAt: Date
    public var zone: Int?
    public var axis: DrawingAxis
    public var drawings: [ProjectDrawing]

    public init(
        id: String = UUID().uuidString,
        name: String,
        createdAt: Date,
        zone: Int? = nil,
        axis: DrawingAxis = .cadEastNorth,
        drawings: [ProjectDrawing] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.zone = zone
        self.axis = axis
        self.drawings = drawings
    }
}

public struct ProjectRecordNote: Codable, Equatable, Sendable {
    public var date: String
    public var kind: String
    public var name: String
    public var createdAt: Date

    public init(date: String, kind: String, name: String, createdAt: Date) {
        self.date = date
        self.kind = kind
        self.name = name
        self.createdAt = createdAt
    }
}

public struct ConversionTag: Codable, Equatable, Sendable {
    public var fileName: String
    public var zone: Int?
    public var axis: DrawingAxis
    public var note: String

    public init(fileName: String, zone: Int?, axis: DrawingAxis, note: String) {
        self.fileName = fileName
        self.zone = zone
        self.axis = axis
        self.note = note
    }

    public static let keptOriginal = "受け取った DXF はそのまま残している。座標の読み方だけをこの札に書く。"
}

public enum ProjectStoreError: Error, Equatable, CustomStringConvertible {
    case emptyName
    case alreadyExists
    case missingProject
    case unreadable

    public var description: String {
        switch self {
        case .emptyName: return "名前を入れてください。"
        case .alreadyExists: return "同じ名前のプロジェクトがあります。"
        case .missingProject: return "プロジェクトが見つかりません。"
        case .unreadable: return "プロジェクトを読めませんでした。"
        }
    }
}

/// `ルート/プロジェクト名/` の下に、座標簿・記録・点群・設計・下敷き・出す を作る。
public enum ProjectStore {
    public static let childFolders = ["座標簿", "記録", "点群", "設計", "下敷き", "出す"]

    public static func create(name: String, at root: URL, now: Date = Date()) throws -> SurveyProject {
        guard let safe = safeComponent(name) else { throw ProjectStoreError.emptyName }
        let directory = root.appendingPathComponent(safe, isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) {
            throw ProjectStoreError.alreadyExists
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for folder in childFolders {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent(folder, isDirectory: true), withIntermediateDirectories: true)
        }
        let project = SurveyProject(name: safe, createdAt: now)
        try write(project, to: directory.appendingPathComponent("project.json"))
        return project
    }

    public static func list(at root: URL) throws -> [SurveyProject] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
        return try urls.compactMap { url in
            let json = url.appendingPathComponent("project.json")
            guard FileManager.default.fileExists(atPath: json.path) else { return nil }
            return try read(SurveyProject.self, from: json)
        }.sorted { $0.name < $1.name }
    }

    public static func save(_ project: SurveyProject, at root: URL) throws {
        let directory = try projectDirectory(project.name, at: root)
        try write(project, to: directory.appendingPathComponent("project.json"))
    }

    /// 受け取ったバイト列を設計フォルダへそのまま置く。中身は書き換えない。
    public static func importDXF(
        data: Data,
        fileName: String,
        into project: inout SurveyProject,
        at root: URL,
        codePage: String,
        unsupported: [String: Int],
        now: Date = Date()
    ) throws -> String {
        let directory = try projectDirectory(project.name, at: root)
        let design = directory.appendingPathComponent("設計", isDirectory: true)
        let stored = uniqueFileName(preferred: fileName, in: design)
        try data.write(to: design.appendingPathComponent(stored))
        project.drawings.append(ProjectDrawing(
            fileName: stored,
            importedAt: now,
            codePage: codePage,
            unsupported: unsupported
        ))
        try save(project, at: root)
        try writeZoneTag(for: stored, zone: project.zone, axis: project.axis, projectName: project.name, at: root)
        return stored
    }

    public static func originalDXF(fileName: String, projectName: String, at root: URL) throws -> Data {
        let directory = try projectDirectory(projectName, at: root)
        let url = directory.appendingPathComponent("設計", isDirectory: true).appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { throw ProjectStoreError.unreadable }
        return data
    }

    public static func writeZoneTag(for fileName: String, zone: Int?, axis: DrawingAxis, projectName: String, at root: URL) throws {
        let directory = try projectDirectory(projectName, at: root)
        let tag = ConversionTag(fileName: fileName, zone: zone, axis: axis, note: ConversionTag.keptOriginal)
        let base = (fileName as NSString).deletingPathExtension
        let url = directory
            .appendingPathComponent("設計", isDirectory: true)
            .appendingPathComponent("\(safeComponent(base) ?? "図面").変換.json")
        try write(tag, to: url)
    }

    public static func saveAlignment(_ record: AlignmentRecord, projectName: String, at root: URL) throws -> AlignmentRecord {
        guard let safe = safeComponent(record.name) else { throw ProjectStoreError.emptyName }
        let directory = try projectDirectory(projectName, at: root)
        let folder = directory
            .appendingPathComponent("設計", isDirectory: true)
            .appendingPathComponent("合わせ", isDirectory: true)
            .appendingPathComponent(safe, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let version = (try alignmentVersions(in: folder).max() ?? 0) + 1
        var stored = record
        stored.version = version
        stored.name = safe
        try write(stored, to: folder.appendingPathComponent("v\(version).json"))
        return stored
    }

    public static func alignments(projectName: String, at root: URL) throws -> [AlignmentRecord] {
        let directory = try projectDirectory(projectName, at: root)
        let folder = directory
            .appendingPathComponent("設計", isDirectory: true)
            .appendingPathComponent("合わせ", isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let names = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        var records: [AlignmentRecord] = []
        for name in names {
            let versions = try alignmentVersions(in: name)
            for version in versions {
                let url = name.appendingPathComponent("v\(version).json")
                if let record = try? read(AlignmentRecord.self, from: url) {
                    records.append(record)
                }
            }
        }
        return records.sorted { lhs, rhs in
            if lhs.name == rhs.name { return lhs.version < rhs.version }
            return lhs.name < rhs.name
        }
    }

    public static func addRecord(
        date: String,
        kind: String,
        name: String,
        projectName: String,
        at root: URL,
        now: Date = Date()
    ) throws -> ProjectRecordNote {
        guard let safeDate = safeComponent(date), let safeKind = safeComponent(kind), let safeName = safeComponent(name) else {
            throw ProjectStoreError.emptyName
        }
        let note = ProjectRecordNote(date: safeDate, kind: safeKind, name: safeName, createdAt: now)
        let directory = try projectDirectory(projectName, at: root)
        let folder = directory
            .appendingPathComponent("記録", isDirectory: true)
            .appendingPathComponent("\(safeDate)_\(safeKind)_\(safeName)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try write(note, to: folder.appendingPathComponent("record.json"))
        return note
    }

    public static func projectDirectory(_ name: String, at root: URL) throws -> URL {
        guard let safe = safeComponent(name) else { throw ProjectStoreError.emptyName }
        let directory = root.appendingPathComponent(safe, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { throw ProjectStoreError.missingProject }
        return directory
    }

    private static func alignmentVersions(in folder: URL) throws -> [Int] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).compactMap { url in
            let stem = url.deletingPathExtension().lastPathComponent
            guard stem.hasPrefix("v") else { return nil }
            return Int(stem.dropFirst())
        }
    }

    private static func uniqueFileName(preferred: String, in directory: URL) -> String {
        let cleaned = safeComponent(preferred) ?? "図面.dxf"
        let ext = (cleaned as NSString).pathExtension
        let base = (cleaned as NSString).deletingPathExtension
        var candidate = cleaned
        var number = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(base)-\(number)" : "\(base)-\(number).\(ext)"
            number += 1
        }
        return candidate
    }

    static func safeComponent(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "." || trimmed == ".." { return nil }
        let cleaned = String(trimmed.map { character in
            "/\\:?%*|\"<>".contains(character) ? "_" : character
        })
        if cleaned.isEmpty { return nil }
        return cleaned
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url)
    }

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: url)
        return try decoder.decode(type, from: data)
    }
}
