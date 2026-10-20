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
    /// 先に選んだ都道府県。無い古いプロジェクトは nil。
    public var prefecture: String?
    /// 作業半径の機種。手入力のときは nil。
    public var machinePreset: String?
    /// 作業半径。メートル。無い古いプロジェクトは nil。
    public var machineRadiusMeters: Double?
    /// 地盤または機体から目までの高さ。既定は画面側で 2.0m。
    public var eyeHeightMeters: Double?
    public var sightDatum: SightDatum?
    /// 端末を目の高さで持つ。false のとき、端末の高さに視線高を足す。
    public var phoneAtEyes: Bool?

    public init(
        id: String = UUID().uuidString,
        name: String,
        createdAt: Date,
        zone: Int? = nil,
        axis: DrawingAxis = .cadEastNorth,
        drawings: [ProjectDrawing] = [],
        prefecture: String? = nil,
        machinePreset: String? = nil,
        machineRadiusMeters: Double? = nil,
        eyeHeightMeters: Double? = nil,
        sightDatum: SightDatum? = nil,
        phoneAtEyes: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.zone = zone
        self.axis = axis
        self.drawings = drawings
        self.prefecture = prefecture
        self.machinePreset = machinePreset
        self.machineRadiusMeters = machineRadiusMeters
        self.eyeHeightMeters = eyeHeightMeters
        self.sightDatum = sightDatum
        self.phoneAtEyes = phoneAtEyes
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, zone, axis, drawings, prefecture
        case machinePreset, machineRadiusMeters, eyeHeightMeters, sightDatum, phoneAtEyes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        zone = try container.decodeIfPresent(Int.self, forKey: .zone)
        axis = try container.decodeIfPresent(DrawingAxis.self, forKey: .axis) ?? .cadEastNorth
        drawings = try container.decodeIfPresent([ProjectDrawing].self, forKey: .drawings) ?? []
        prefecture = try container.decodeIfPresent(String.self, forKey: .prefecture)
        machinePreset = try container.decodeIfPresent(String.self, forKey: .machinePreset)
        machineRadiusMeters = try container.decodeIfPresent(Double.self, forKey: .machineRadiusMeters)
        eyeHeightMeters = try container.decodeIfPresent(Double.self, forKey: .eyeHeightMeters)
        sightDatum = try container.decodeIfPresent(SightDatum.self, forKey: .sightDatum)
        phoneAtEyes = try container.decodeIfPresent(Bool.self, forKey: .phoneAtEyes)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(zone, forKey: .zone)
        try container.encode(axis, forKey: .axis)
        try container.encode(drawings, forKey: .drawings)
        try container.encodeIfPresent(prefecture, forKey: .prefecture)
        try container.encodeIfPresent(machinePreset, forKey: .machinePreset)
        try container.encodeIfPresent(machineRadiusMeters, forKey: .machineRadiusMeters)
        try container.encodeIfPresent(eyeHeightMeters, forKey: .eyeHeightMeters)
        try container.encodeIfPresent(sightDatum, forKey: .sightDatum)
        try container.encodeIfPresent(phoneAtEyes, forKey: .phoneAtEyes)
    }
}

public struct ProjectRecordNote: Codable, Equatable, Sendable {
    public var date: String
    public var kind: String
    public var name: String
    public var createdAt: Date
    /// この記録で点名の頭に使うアルファベット。無い記録は nil。
    public var pointPrefix: String?

    public init(date: String, kind: String, name: String, createdAt: Date, pointPrefix: String? = nil) {
        self.date = date
        self.kind = kind
        self.name = name
        self.createdAt = createdAt
        self.pointPrefix = pointPrefix
    }

    public var folderName: String { "\(date)_\(kind)_\(name)" }
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

    public static let keptOriginal = "受け取った図面ファイルはそのまま残している。座標の読み方だけをこの札に書く。"
}

/// 基準点として座標簿に残す1点。点名の連番は、この名前を飛ばす。
public struct CoordinateBookEntry: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var ellipsoidalHeightMeters: Double?
    public var horizontalAccuracyMeters: Double
    public var verticalAccuracyMeters: Double?
    public var satelliteCount: Int?
    public var fixDurationSeconds: TimeInterval
    public var recordedAt: Date
    public var kind: String?
    public var source: String?
    public var stage: PositionStage?
    public var solution: FixQuality?
    public var pdop: Double?
    public var correctionAgeSeconds: Double?
    public var correctionSource: String?
    public var epochCount: Int?
    public var receiverLabel: String?
    public var satelliteNote: String?

    public var id: String { name }

    public init(
        name: String,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        ellipsoidalHeightMeters: Double?,
        horizontalAccuracyMeters: Double,
        verticalAccuracyMeters: Double?,
        satelliteCount: Int?,
        fixDurationSeconds: TimeInterval,
        recordedAt: Date,
        kind: String? = nil,
        source: String? = nil,
        stage: PositionStage? = nil,
        solution: FixQuality? = nil,
        pdop: Double? = nil,
        correctionAgeSeconds: Double? = nil,
        correctionSource: String? = nil,
        epochCount: Int? = nil,
        receiverLabel: String? = nil,
        satelliteNote: String? = nil
    ) {
        self.name = name
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.ellipsoidalHeightMeters = ellipsoidalHeightMeters
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.verticalAccuracyMeters = verticalAccuracyMeters
        self.satelliteCount = satelliteCount
        self.fixDurationSeconds = fixDurationSeconds
        self.recordedAt = recordedAt
        self.kind = kind
        self.source = source
        self.stage = stage
        self.solution = solution
        self.pdop = pdop
        self.correctionAgeSeconds = correctionAgeSeconds
        self.correctionSource = correctionSource
        self.epochCount = epochCount
        self.receiverLabel = receiverLabel
        self.satelliteNote = satelliteNote
    }
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
        now: Date = Date(),
        pointPrefix: String? = nil
    ) throws -> ProjectRecordNote {
        guard let safeDate = safeComponent(date), let safeKind = safeComponent(kind), let safeName = safeComponent(name) else {
            throw ProjectStoreError.emptyName
        }
        let note = ProjectRecordNote(
            date: safeDate,
            kind: safeKind,
            name: safeName,
            createdAt: now,
            pointPrefix: pointPrefix
        )
        let directory = try projectDirectory(projectName, at: root)
        let folder = directory
            .appendingPathComponent("記録", isDirectory: true)
            .appendingPathComponent(note.folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try write(note, to: folder.appendingPathComponent("record.json"))
        return note
    }

    public static func setRecordPrefix(
        folder: String,
        prefix: String?,
        projectName: String,
        at root: URL
    ) throws {
        guard let safeFolder = safeComponent(folder) else { throw ProjectStoreError.emptyName }
        let directory = try projectDirectory(projectName, at: root)
        let url = directory
            .appendingPathComponent("記録", isDirectory: true)
            .appendingPathComponent(safeFolder, isDirectory: true)
            .appendingPathComponent("record.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw ProjectStoreError.missingProject }
        var note = try read(ProjectRecordNote.self, from: url)
        note.pointPrefix = prefix
        try write(note, to: url)
    }

    public static func recordNote(folder: String, projectName: String, at root: URL) throws -> ProjectRecordNote {
        guard let safeFolder = safeComponent(folder) else { throw ProjectStoreError.emptyName }
        let directory = try projectDirectory(projectName, at: root)
        let url = directory
            .appendingPathComponent("記録", isDirectory: true)
            .appendingPathComponent(safeFolder, isDirectory: true)
            .appendingPathComponent("record.json")
        return try read(ProjectRecordNote.self, from: url)
    }

    /// 座標簿へ1点を足す。同じ名前のファイルは上書きしない。元の図面ファイルは触らない。
    public static func saveCoordinate(_ entry: CoordinateBookEntry, projectName: String, at root: URL) throws {
        guard let safe = safeComponent(entry.name) else { throw ProjectStoreError.emptyName }
        let directory = try projectDirectory(projectName, at: root)
        let folder = directory.appendingPathComponent("座標簿", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var file = "\(safe).json"
        var number = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(file).path) {
            file = "\(safe)-\(number).json"
            number += 1
        }
        try write(entry, to: folder.appendingPathComponent(file))
    }

    public static func coordinateBookEntries(projectName: String, at root: URL) -> [CoordinateBookEntry] {
        guard let directory = try? projectDirectory(projectName, at: root) else { return [] }
        let folder = directory.appendingPathComponent("座標簿", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return urls.compactMap { url in
            guard url.pathExtension.lowercased() == "json" else { return nil }
            return try? read(CoordinateBookEntry.self, from: url)
        }.sorted { $0.name < $1.name }
    }

    public static func coordinateBookNames(projectName: String, at root: URL) -> Set<String> {
        Set(coordinateBookEntries(projectName: projectName, at: root).map(\.name))
    }

    public static func exportDirectory(projectName: String, at root: URL) throws -> URL {
        let directory = try projectDirectory(projectName, at: root)
        let folder = directory.appendingPathComponent("出す", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
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
