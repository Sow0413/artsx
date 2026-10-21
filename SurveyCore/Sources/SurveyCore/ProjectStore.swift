import Foundation

public struct ProjectDrawing: Codable, Equatable, Sendable {
    public var fileName: String
    public var importedAt: Date
    public var codePage: String
    public var unsupported: [String: Int]
    /// 一覧に出す名前。空ならファイル名。
    public var displayName: String? = nil
    public var prefecture: String? = nil
    public var area: String? = nil
    public var zone: Int? = nil

    public init(
        fileName: String,
        importedAt: Date,
        codePage: String,
        unsupported: [String: Int],
        displayName: String? = nil,
        prefecture: String? = nil,
        area: String? = nil,
        zone: Int? = nil
    ) {
        self.fileName = fileName
        self.importedAt = importedAt
        self.codePage = codePage
        self.unsupported = unsupported
        self.displayName = displayName
        self.prefecture = prefecture
        self.area = area
        self.zone = zone
    }

    public var title: String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fileName : trimmed
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
    /// 系が分かれる県の区域。一つの系の県は nil。
    public var area: String?
    /// 系を手で指定した。県から決めたときは false。
    public var manualZone: Bool?
    /// 作業半径の機種。手入力のときは nil。
    public var machinePreset: String?
    /// 作業半径。メートル。無い古いプロジェクトは nil。
    public var machineRadiusMeters: Double?
    /// 地盤または機体から目までの高さ。既定は画面側で 2.0m。
    public var eyeHeightMeters: Double?
    public var sightDatum: SightDatum?
    /// 端末を目の高さで持つ。false のとき、端末の高さに視線高を足す。
    public var phoneAtEyes: Bool?
    /// 測点間隔。無いときは 20m。
    public var stationIntervalMeters: Double?
    /// 中心線の始点の測点番号。無いときは 0。
    public var stationOrigin: Int?
    /// 追加距離を張った中心線。将来の位置共有でも、この値を渡せば測点を出せる。
    public var stationLine: StationLine?
    /// 接近の注意を出す距離。無いときは 50m。
    public var cautionMeters: Double?
    /// 作業半径に足す余裕。iPhone の誤差分。無いときは 5m。
    public var proximityMarginMeters: Double?
    /// 声をかける位置。作業半径に足すメートル。無いときは 10m。
    public var approachLeadMeters: Double?
    /// 同じ相手への読み上げを繰り返すまでの秒。無いときは 30秒。
    public var approachRepeatSeconds: Double?
    /// 現場の天候。集計の列に使う。測っていないときは nil。
    public var weather: String?
    /// AED、担架、救急箱、住所、連絡先。古いプロジェクトは nil。
    public var siteAid: SiteAid?
    /// 位置を共有してよい範囲。無いプロジェクトは共有しない。
    public var siteFence: SiteFence?
    /// 位置を共有してよい時間。無いプロジェクトは共有しない。
    public var workHours: WorkHours?
    /// 記録の場所名。プロジェクトがあるときは projects/<名前>/記録/ の下に置く。
    public var place: String?
    /// 現場の日付。YYYY-MM-DD。無いときは作成日。
    public var workDate: String?
    /// 2点合わせの距離差の許容。ミリ。無いときは 20。
    public var alignToleranceMillimeters: Double?
    /// 距離差の比の分母。1/N の N。無いときは 5000。
    public var alignToleranceDenominator: Double?
    /// 座標 CSV の列の役割。同じ列数の次のファイルに使う。
    public var pointColumnMap: PointColumnMap?

    public init(
        id: String = UUID().uuidString,
        name: String,
        createdAt: Date,
        zone: Int? = nil,
        axis: DrawingAxis = .cadEastNorth,
        drawings: [ProjectDrawing] = [],
        prefecture: String? = nil,
        area: String? = nil,
        manualZone: Bool? = nil,
        machinePreset: String? = nil,
        machineRadiusMeters: Double? = nil,
        eyeHeightMeters: Double? = nil,
        sightDatum: SightDatum? = nil,
        phoneAtEyes: Bool? = nil,
        stationIntervalMeters: Double? = nil,
        stationOrigin: Int? = nil,
        stationLine: StationLine? = nil,
        cautionMeters: Double? = nil,
        proximityMarginMeters: Double? = nil,
        approachLeadMeters: Double? = nil,
        approachRepeatSeconds: Double? = nil,
        weather: String? = nil,
        siteAid: SiteAid? = nil,
        siteFence: SiteFence? = nil,
        workHours: WorkHours? = nil,
        place: String? = nil,
        workDate: String? = nil,
        alignToleranceMillimeters: Double? = nil,
        alignToleranceDenominator: Double? = nil,
        pointColumnMap: PointColumnMap? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.zone = zone
        self.axis = axis
        self.drawings = drawings
        self.prefecture = prefecture
        self.area = area
        self.manualZone = manualZone
        self.machinePreset = machinePreset
        self.machineRadiusMeters = machineRadiusMeters
        self.eyeHeightMeters = eyeHeightMeters
        self.sightDatum = sightDatum
        self.phoneAtEyes = phoneAtEyes
        self.stationIntervalMeters = stationIntervalMeters
        self.stationOrigin = stationOrigin
        self.stationLine = stationLine
        self.cautionMeters = cautionMeters
        self.proximityMarginMeters = proximityMarginMeters
        self.approachLeadMeters = approachLeadMeters
        self.approachRepeatSeconds = approachRepeatSeconds
        self.weather = weather
        self.siteAid = siteAid
        self.siteFence = siteFence
        self.workHours = workHours
        self.place = place
        self.workDate = workDate
        self.alignToleranceMillimeters = alignToleranceMillimeters
        self.alignToleranceDenominator = alignToleranceDenominator
        self.pointColumnMap = pointColumnMap
    }

    public var listDate: String {
        if let workDate {
            let trimmed = workDate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return FieldRecordStore.dayFolder(createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, zone, axis, drawings, prefecture, area, manualZone
        case machinePreset, machineRadiusMeters, eyeHeightMeters, sightDatum, phoneAtEyes
        case stationIntervalMeters, stationOrigin, stationLine
        case cautionMeters, proximityMarginMeters, approachLeadMeters, approachRepeatSeconds, weather
        case siteAid, siteFence, workHours, place, workDate
        case alignToleranceMillimeters, alignToleranceDenominator, pointColumnMap
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
        area = try container.decodeIfPresent(String.self, forKey: .area)
        manualZone = try container.decodeIfPresent(Bool.self, forKey: .manualZone)
        machinePreset = try container.decodeIfPresent(String.self, forKey: .machinePreset)
        machineRadiusMeters = try container.decodeIfPresent(Double.self, forKey: .machineRadiusMeters)
        eyeHeightMeters = try container.decodeIfPresent(Double.self, forKey: .eyeHeightMeters)
        sightDatum = try container.decodeIfPresent(SightDatum.self, forKey: .sightDatum)
        phoneAtEyes = try container.decodeIfPresent(Bool.self, forKey: .phoneAtEyes)
        stationIntervalMeters = try container.decodeIfPresent(Double.self, forKey: .stationIntervalMeters)
        stationOrigin = try container.decodeIfPresent(Int.self, forKey: .stationOrigin)
        stationLine = try container.decodeIfPresent(StationLine.self, forKey: .stationLine)
        cautionMeters = try container.decodeIfPresent(Double.self, forKey: .cautionMeters)
        proximityMarginMeters = try container.decodeIfPresent(Double.self, forKey: .proximityMarginMeters)
        approachLeadMeters = try container.decodeIfPresent(Double.self, forKey: .approachLeadMeters)
        approachRepeatSeconds = try container.decodeIfPresent(Double.self, forKey: .approachRepeatSeconds)
        weather = try container.decodeIfPresent(String.self, forKey: .weather)
        siteAid = try container.decodeIfPresent(SiteAid.self, forKey: .siteAid)
        siteFence = try container.decodeIfPresent(SiteFence.self, forKey: .siteFence)
        workHours = try container.decodeIfPresent(WorkHours.self, forKey: .workHours)
        place = try container.decodeIfPresent(String.self, forKey: .place)
        workDate = try container.decodeIfPresent(String.self, forKey: .workDate)
        alignToleranceMillimeters = try container.decodeIfPresent(Double.self, forKey: .alignToleranceMillimeters)
        alignToleranceDenominator = try container.decodeIfPresent(Double.self, forKey: .alignToleranceDenominator)
        pointColumnMap = try container.decodeIfPresent(PointColumnMap.self, forKey: .pointColumnMap)
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
        try container.encodeIfPresent(area, forKey: .area)
        try container.encodeIfPresent(manualZone, forKey: .manualZone)
        try container.encodeIfPresent(machinePreset, forKey: .machinePreset)
        try container.encodeIfPresent(machineRadiusMeters, forKey: .machineRadiusMeters)
        try container.encodeIfPresent(eyeHeightMeters, forKey: .eyeHeightMeters)
        try container.encodeIfPresent(sightDatum, forKey: .sightDatum)
        try container.encodeIfPresent(phoneAtEyes, forKey: .phoneAtEyes)
        try container.encodeIfPresent(stationIntervalMeters, forKey: .stationIntervalMeters)
        try container.encodeIfPresent(stationOrigin, forKey: .stationOrigin)
        try container.encodeIfPresent(stationLine, forKey: .stationLine)
        try container.encodeIfPresent(cautionMeters, forKey: .cautionMeters)
        try container.encodeIfPresent(proximityMarginMeters, forKey: .proximityMarginMeters)
        try container.encodeIfPresent(approachLeadMeters, forKey: .approachLeadMeters)
        try container.encodeIfPresent(approachRepeatSeconds, forKey: .approachRepeatSeconds)
        try container.encodeIfPresent(weather, forKey: .weather)
        try container.encodeIfPresent(siteAid, forKey: .siteAid)
        try container.encodeIfPresent(siteFence, forKey: .siteFence)
        try container.encodeIfPresent(workHours, forKey: .workHours)
        try container.encodeIfPresent(place, forKey: .place)
        try container.encodeIfPresent(workDate, forKey: .workDate)
        try container.encodeIfPresent(alignToleranceMillimeters, forKey: .alignToleranceMillimeters)
        try container.encodeIfPresent(alignToleranceDenominator, forKey: .alignToleranceDenominator)
        try container.encodeIfPresent(pointColumnMap, forKey: .pointColumnMap)
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

public struct CoordinateBookPreview: Sendable, Equatable {
    public var count: Int
    public var sample: [CoordinateBookEntry]

    public init(count: Int, sample: [CoordinateBookEntry]) {
        self.count = count
        self.sample = sample
    }
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
    /// 標高。観測点はジオイドを引いた値。既知点は入れず、成果の高さを ellipsoidalHeightMeters に置く。
    public var orthometricHeightMeters: Double?
    public var geoidUndulationMeters: Double?
    public var geoidModel: String?
    public var phoneAverage: PhoneAverageStamp?
    public var knownShift: KnownShiftStamp?

    public var id: String { name }

    /// 出す・SIMA に書く高さ。観測は標高、既知点は入っている成果。
    public var deliveredHeightMeters: Double? {
        orthometricHeightMeters ?? ellipsoidalHeightMeters
    }

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
        satelliteNote: String? = nil,
        orthometricHeightMeters: Double? = nil,
        geoidUndulationMeters: Double? = nil,
        geoidModel: String? = nil,
        phoneAverage: PhoneAverageStamp? = nil,
        knownShift: KnownShiftStamp? = nil
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
        self.orthometricHeightMeters = orthometricHeightMeters
        self.geoidUndulationMeters = geoidUndulationMeters
        self.geoidModel = geoidModel
        self.phoneAverage = phoneAverage
        self.knownShift = knownShift
    }
}

public enum ProjectStoreError: Error, Equatable, CustomStringConvertible {
    case emptyName
    case alreadyExists
    case missingProject
    case unreadable
    case drawingExists

    public var description: String {
        switch self {
        case .emptyName: return "名前を入れてください。"
        case .alreadyExists: return "同じ名前のプロジェクトがあります。"
        case .missingProject: return "プロジェクトが見つかりません。"
        case .unreadable: return "プロジェクトを読めませんでした。"
        case .drawingExists: return "同じ名前の図面があります。"
        }
    }
}

/// 現場か図面を30日残す。期限を過ぎたものは消す。
public struct ProjectTrashItem: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case project
        case drawing
    }

    public static let retention: TimeInterval = 30 * 24 * 60 * 60

    public var id: String
    public var kind: Kind
    public var name: String
    public var deletedAt: Date
    public var projectID: String?
    public var projectName: String?
    public var fileName: String?
    public var drawing: ProjectDrawing?

    public init(
        id: String = UUID().uuidString,
        kind: Kind,
        name: String,
        deletedAt: Date,
        projectID: String? = nil,
        projectName: String? = nil,
        fileName: String? = nil,
        drawing: ProjectDrawing? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.deletedAt = deletedAt
        self.projectID = projectID
        self.projectName = projectName
        self.fileName = fileName
        self.drawing = drawing
    }

    public func isExpired(at now: Date) -> Bool {
        now.timeIntervalSince(deletedAt) >= Self.retention
    }

    public func daysLeft(at now: Date) -> Int {
        let remaining = Self.retention - now.timeIntervalSince(deletedAt)
        if remaining <= 0 { return 0 }
        return Int(ceil(remaining / (24 * 60 * 60)))
    }
}

/// `Documents/projects/プロジェクト名/` の下に、図面・SIMA・出力・記録を置く。
public enum ProjectStore {
    public static let drawingFolder = "図面"
    public static let simaFolder = "SIMA"
    public static let exportFolderName = "出力"
    public static let legacyDrawingFolder = "設計"
    public static let legacyExportFolder = "出す"
    public static let childFolders = ["座標簿", "記録", "点群", "図面", "SIMA", "下敷き", "出力"]

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
        let urls = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return try urls.compactMap { url in
            if url.lastPathComponent == trashFolderName || url.lastPathComponent.hasPrefix(".") { return nil }
            let json = url.appendingPathComponent("project.json")
            guard FileManager.default.fileExists(atPath: json.path) else { return nil }
            return try read(SurveyProject.self, from: json)
        }.sorted { $0.name < $1.name }
    }

    public static func rename(_ project: inout SurveyProject, to rawName: String, at root: URL) throws {
        guard let safe = safeComponent(rawName) else { throw ProjectStoreError.emptyName }
        let from = try projectDirectory(project.name, at: root)
        if safe != project.name {
            let destination = root.appendingPathComponent(safe, isDirectory: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                throw ProjectStoreError.alreadyExists
            }
            try FileManager.default.moveItem(at: from, to: destination)
            project.name = safe
        }
        try save(project, at: root)
    }

    public static func save(_ project: SurveyProject, at root: URL) throws {
        let directory = try projectDirectory(project.name, at: root)
        try write(project, to: directory.appendingPathComponent("project.json"))
    }

    public static let trashFolderName = ".Trash"
    public static let legacyTrashFolderName = ".trash"

    /// 現場のフォルダごとゴミ箱へ移す。30日で消える。
    public static func trashProject(_ project: SurveyProject, at root: URL, now: Date = Date()) throws -> ProjectTrashItem {
        let source = try projectDirectory(project.name, at: root)
        let item = ProjectTrashItem(
            kind: .project,
            name: project.name,
            deletedAt: now,
            projectID: project.id,
            projectName: project.name
        )
        let folder = trashDirectory(item.id, at: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let body = folder.appendingPathComponent("body", isDirectory: true)
        do {
            try FileManager.default.moveItem(at: source, to: body)
            try write(item, to: folder.appendingPathComponent("meta.json"))
        } catch {
            if FileManager.default.fileExists(atPath: body.path),
               !FileManager.default.fileExists(atPath: source.path) {
                try? FileManager.default.moveItem(at: body, to: source)
            }
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return item
    }

    /// 図面ファイルと変換の札をゴミ箱へ移し、現場の一覧から外す。
    public static func trashDrawing(
        fileName: String,
        in project: inout SurveyProject,
        at root: URL,
        now: Date = Date()
    ) throws -> ProjectTrashItem {
        guard let index = project.drawings.firstIndex(where: { $0.fileName == fileName }) else {
            throw ProjectStoreError.unreadable
        }
        let drawing = project.drawings[index]
        let directory = try projectDirectory(project.name, at: root)
        let design = preparedFolder(drawingFolder, legacy: legacyDrawingFolder, in: directory)
        let source = design.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: source.path) else { throw ProjectStoreError.unreadable }
        let item = ProjectTrashItem(
            kind: .drawing,
            name: drawing.title,
            deletedAt: now,
            projectID: project.id,
            projectName: project.name,
            fileName: fileName,
            drawing: drawing
        )
        let folder = trashDirectory(item.id, at: root)
        let body = folder.appendingPathComponent("body", isDirectory: true)
        try FileManager.default.createDirectory(at: body, withIntermediateDirectories: true)
        do {
            try FileManager.default.moveItem(at: source, to: body.appendingPathComponent(fileName))
            let tagName = conversionTagName(for: fileName)
            let tag = design.appendingPathComponent(tagName)
            if FileManager.default.fileExists(atPath: tag.path) {
                try FileManager.default.moveItem(at: tag, to: body.appendingPathComponent(tagName))
            }
            try moveAlignments(named: fileName, from: design, to: body)
            try write(item, to: folder.appendingPathComponent("meta.json"))
        } catch {
            try? restoreMovedDrawing(fileName: fileName, body: body, design: design)
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        project.drawings.remove(at: index)
        do {
            try save(project, at: root)
        } catch {
            project.drawings.insert(drawing, at: index)
            try? restoreMovedDrawing(fileName: fileName, body: body, design: design)
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return item
    }

    public static func listTrash(at root: URL) throws -> [ProjectTrashItem] {
        var items: [ProjectTrashItem] = []
        var seen: Set<String> = []
        for name in [trashFolderName, legacyTrashFolderName] {
            let folder = root.appendingPathComponent(name, isDirectory: true)
            guard FileManager.default.fileExists(atPath: folder.path) else { continue }
            let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            for url in urls {
                guard let item = try? read(ProjectTrashItem.self, from: url.appendingPathComponent("meta.json")) else { continue }
                if seen.insert(item.id).inserted {
                    items.append(item)
                }
            }
        }
        return items.sorted { $0.deletedAt > $1.deletedAt }
    }

    public static func purgeTrash(at root: URL, now: Date = Date()) {
        guard let items = try? listTrash(at: root) else { return }
        for item in items where item.isExpired(at: now) {
            try? FileManager.default.removeItem(at: trashDirectory(item.id, at: root))
        }
    }

    @discardableResult
    public static func restoreTrash(id: String, at root: URL) throws -> ProjectTrashItem {
        let folder = trashDirectory(id, at: root)
        let meta = folder.appendingPathComponent("meta.json")
        guard FileManager.default.fileExists(atPath: meta.path) else { throw ProjectStoreError.missingProject }
        let item = try read(ProjectTrashItem.self, from: meta)
        let body = folder.appendingPathComponent("body", isDirectory: true)
        switch item.kind {
        case .project:
            let dest = root.appendingPathComponent(item.name, isDirectory: true)
            if FileManager.default.fileExists(atPath: resolved(dest)) {
                throw ProjectStoreError.alreadyExists
            }
            try FileManager.default.moveItem(at: body, to: dest)
        case .drawing:
            guard let projectID = item.projectID, let fileName = item.fileName,
                  var project = try list(at: root).first(where: { $0.id == projectID }) else {
                throw ProjectStoreError.missingProject
            }
            let directory = try projectDirectory(project.name, at: root)
            let design = preparedFolder(drawingFolder, legacy: legacyDrawingFolder, in: directory)
            let dest = design.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: resolved(dest)) {
                throw ProjectStoreError.drawingExists
            }
            try FileManager.default.moveItem(at: body.appendingPathComponent(fileName), to: dest)
            let tagName = conversionTagName(for: fileName)
            let tag = body.appendingPathComponent(tagName)
            if FileManager.default.fileExists(atPath: tag.path) {
                let tagDest = design.appendingPathComponent(tagName)
                if FileManager.default.fileExists(atPath: tagDest.path) {
                    try? FileManager.default.removeItem(at: tagDest)
                }
                try FileManager.default.moveItem(at: tag, to: tagDest)
            }
            try moveAlignmentsBack(from: body, to: design)
            if let drawing = item.drawing, !project.drawings.contains(where: { $0.fileName == fileName }) {
                project.drawings.append(drawing)
            }
            try save(project, at: root)
        }
        try? FileManager.default.removeItem(at: folder)
        return item
    }

    /// 受け取ったバイト列を図面フォルダへそのまま置く。中身は書き換えない。
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
        let design = preparedFolder(drawingFolder, legacy: legacyDrawingFolder, in: directory)
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

    /// SIMA の原本を SIMA フォルダへそのまま置く。中身は書き換えない。
    @discardableResult
    public static func importSIMA(
        data: Data,
        fileName: String,
        projectName: String,
        at root: URL
    ) throws -> String {
        try importOriginal(data: data, fileName: fileName, folder: simaFolder, projectName: projectName, at: root)
    }

    public static func originalDXF(fileName: String, projectName: String, at root: URL) throws -> Data {
        let directory = try projectDirectory(projectName, at: root)
        let folder = preparedFolder(drawingFolder, legacy: legacyDrawingFolder, in: directory)
        let url = folder.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { throw ProjectStoreError.unreadable }
        return data
    }

    public static func writeZoneTag(for fileName: String, zone: Int?, axis: DrawingAxis, projectName: String, at root: URL) throws {
        let directory = try projectDirectory(projectName, at: root)
        let tag = ConversionTag(fileName: fileName, zone: zone, axis: axis, note: ConversionTag.keptOriginal)
        let base = (fileName as NSString).deletingPathExtension
        let url = preparedFolder(drawingFolder, legacy: legacyDrawingFolder, in: directory)
            .appendingPathComponent("\(safeComponent(base) ?? "図面").変換.json")
        try write(tag, to: url)
    }

    public static func saveAlignment(_ record: AlignmentRecord, projectName: String, at root: URL) throws -> AlignmentRecord {
        guard let safe = safeComponent(record.name) else { throw ProjectStoreError.emptyName }
        let directory = try projectDirectory(projectName, at: root)
        let folder = preparedFolder(drawingFolder, legacy: legacyDrawingFolder, in: directory)
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
        let folder = preparedFolder(drawingFolder, legacy: legacyDrawingFolder, in: directory)
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

    /// 座標簿へ1点を足す。SQLite の同じ名前は上書きする。元の図面ファイルは触らない。
    public static func saveCoordinate(_ entry: CoordinateBookEntry, projectName: String, at root: URL) throws {
        try saveCoordinates([entry], projectName: projectName, at: root)
    }

    public static func saveCoordinates(_ entries: [CoordinateBookEntry], projectName: String, at root: URL) throws {
        let directory = try projectDirectory(projectName, at: root)
        try CoordinateBookStore.upsert(entries, projectDirectory: directory)
    }

    public static func coordinateBookEntries(projectName: String, at root: URL) -> [CoordinateBookEntry] {
        guard let directory = try? projectDirectory(projectName, at: root) else { return [] }
        if CoordinateBookStore.exists(projectDirectory: directory) {
            return CoordinateBookStore.entries(projectDirectory: directory)
        }
        return jsonCoordinateEntries(in: directory)
    }

    public static func coordinateBookNames(projectName: String, at root: URL) -> Set<String> {
        guard let directory = try? projectDirectory(projectName, at: root) else { return [] }
        if CoordinateBookStore.exists(projectDirectory: directory) {
            return CoordinateBookStore.names(projectDirectory: directory)
        }
        return Set(jsonCoordinateEntries(in: directory).map(\.name))
    }

    /// 保存済みの座標簿は SQLite で絞る。観測と既知点は件数が小さいのでメモリで足す。
    public static func filteredCoordinates(
        projectName: String,
        at root: URL,
        query: CoordinateBookQuery,
        observations: [FieldObservation],
        known: [ControlPoint],
        siteBook: [CoordinateBookEntry]
    ) -> [CoordinateBookEntry] {
        guard let directory = try? projectDirectory(projectName, at: root) else {
            return CoordinateBookQuery.apply(
                CoordinateBookIndex.collect(book: siteBook, observations: observations, known: known),
                query: query
            )
        }
        let stored = CoordinateBookStore.exists(projectDirectory: directory)
            ? CoordinateBookStore.filter(query, projectDirectory: directory)
            : CoordinateBookQuery.apply(jsonCoordinateEntries(in: directory), query: query)
        let extras = CoordinateBookQuery.apply(
            CoordinateBookIndex.collect(book: siteBook, observations: observations, known: known),
            query: query
        )
        var byName: [String: CoordinateBookEntry] = [:]
        for entry in extras { byName[entry.name] = entry }
        for entry in stored { byName[entry.name] = entry }
        return byName.values.sorted { $0.name < $1.name }
    }

    /// 画面に出す分だけ。全件は読み出さない。
    public static func coordinateBookPreview(
        projectName: String,
        at root: URL,
        query: CoordinateBookQuery,
        observations: [FieldObservation],
        known: [ControlPoint],
        siteBook: [CoordinateBookEntry],
        sampleLimit: Int = 8
    ) -> CoordinateBookPreview {
        let extras = CoordinateBookQuery.apply(
            CoordinateBookIndex.collect(book: siteBook, observations: observations, known: known),
            query: query
        )
        guard let directory = try? projectDirectory(projectName, at: root) else {
            return CoordinateBookPreview(count: extras.count, sample: Array(extras.prefix(sampleLimit)))
        }
        if !CoordinateBookStore.exists(projectDirectory: directory) {
            let stored = CoordinateBookQuery.apply(jsonCoordinateEntries(in: directory), query: query)
            var byName: [String: CoordinateBookEntry] = [:]
            for entry in extras { byName[entry.name] = entry }
            for entry in stored { byName[entry.name] = entry }
            let merged = byName.values.sorted { $0.name < $1.name }
            return CoordinateBookPreview(count: merged.count, sample: Array(merged.prefix(sampleLimit)))
        }
        let storedCount = CoordinateBookStore.matchCount(query, projectDirectory: directory)
        let storedSample = CoordinateBookStore.filter(query, projectDirectory: directory, limit: sampleLimit)
        var byName: [String: CoordinateBookEntry] = [:]
        for entry in storedSample { byName[entry.name] = entry }
        var count = storedCount
        for entry in extras {
            if CoordinateBookStore.matches(name: entry.name, query: query, projectDirectory: directory) { continue }
            count += 1
            byName[entry.name] = entry
        }
        let sample = byName.values.sorted { $0.name < $1.name }
        return CoordinateBookPreview(count: count, sample: Array(sample.prefix(sampleLimit)))
    }

    private static func jsonCoordinateEntries(in directory: URL) -> [CoordinateBookEntry] {
        let folder = directory.appendingPathComponent("座標簿", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return urls.compactMap { url in
            guard url.pathExtension.lowercased() == "json" else { return nil }
            return try? read(CoordinateBookEntry.self, from: url)
        }.sorted { $0.name < $1.name }
    }

    public static func exportDirectory(projectName: String, at root: URL) throws -> URL {
        let directory = try projectDirectory(projectName, at: root)
        return preparedFolder(exportFolderName, legacy: legacyExportFolder, in: directory)
    }

    /// Application Support の旧 `プロジェクト` を Documents/projects へ移す。図面と出力のフォルダ名も揃える。
    public static func migrateProjects(from legacyRoot: URL, to root: URL) {
        let manager = FileManager.default
        try? manager.createDirectory(at: root, withIntermediateDirectories: true)
        if manager.fileExists(atPath: legacyRoot.path),
           let children = try? manager.contentsOfDirectory(at: legacyRoot, includingPropertiesForKeys: nil) {
            for child in children {
                let name = child.lastPathComponent
                if name == trashFolderName || name == legacyTrashFolderName || name.hasPrefix(".") { continue }
                guard manager.fileExists(atPath: child.appendingPathComponent("project.json").path) else { continue }
                let dest = root.appendingPathComponent(name, isDirectory: true)
                if manager.fileExists(atPath: dest.path) { continue }
                try? manager.moveItem(at: child, to: dest)
            }
            moveTrashContents(from: legacyRoot, to: root)
        }
        if let children = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for child in children where !child.lastPathComponent.hasPrefix(".") {
                adoptLegacyFolders(in: child)
            }
        }
    }

    private static func trashDirectory(_ id: String, at root: URL) -> URL {
        for name in [trashFolderName, legacyTrashFolderName] {
            let existing = root.appendingPathComponent(name, isDirectory: true).appendingPathComponent(id, isDirectory: true)
            if FileManager.default.fileExists(atPath: existing.path) { return existing }
        }
        return root.appendingPathComponent(trashFolderName, isDirectory: true).appendingPathComponent(id, isDirectory: true)
    }

    private static func conversionTagName(for fileName: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
        return "\(safeComponent(base) ?? "図面").変換.json"
    }

    /// macOS の一時ディレクトリは `/var` から `/private/var` へのリンクになる。存在確認の前に解く。
    private static func resolved(_ url: URL) -> String {
        url.resolvingSymlinksInPath().path
    }

    private static func moveAlignments(named fileName: String, from design: URL, to body: URL) throws {
        let source = design.appendingPathComponent("合わせ", isDirectory: true)
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let folders = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        for folder in folders {
            guard alignmentMatches(fileName, in: folder) else { continue }
            let destRoot = body.appendingPathComponent("合わせ", isDirectory: true)
            try FileManager.default.createDirectory(at: destRoot, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: folder, to: destRoot.appendingPathComponent(folder.lastPathComponent, isDirectory: true))
        }
    }

    private static func moveAlignmentsBack(from body: URL, to design: URL) throws {
        let source = body.appendingPathComponent("合わせ", isDirectory: true)
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let destRoot = design.appendingPathComponent("合わせ", isDirectory: true)
        try FileManager.default.createDirectory(at: destRoot, withIntermediateDirectories: true)
        let folders = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        for folder in folders {
            let dest = destRoot.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
            if FileManager.default.fileExists(atPath: dest.path) { continue }
            try FileManager.default.moveItem(at: folder, to: dest)
        }
    }

    private static func alignmentMatches(_ fileName: String, in folder: URL) -> Bool {
        guard let versions = try? alignmentVersions(in: folder), let latest = versions.max() else { return false }
        let url = folder.appendingPathComponent("v\(latest).json")
        guard let record = try? read(AlignmentRecord.self, from: url) else { return false }
        return record.drawingFileName == fileName
    }

    private static func restoreMovedDrawing(fileName: String, body: URL, design: URL) throws {
        let moved = body.appendingPathComponent(fileName)
        let dest = design.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: moved.path), !FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.moveItem(at: moved, to: dest)
        }
        let tagName = conversionTagName(for: fileName)
        let tag = body.appendingPathComponent(tagName)
        let tagDest = design.appendingPathComponent(tagName)
        if FileManager.default.fileExists(atPath: tag.path), !FileManager.default.fileExists(atPath: tagDest.path) {
            try FileManager.default.moveItem(at: tag, to: tagDest)
        }
        try moveAlignmentsBack(from: body, to: design)
    }

    public static func projectDirectory(_ name: String, at root: URL) throws -> URL {
        guard let safe = safeComponent(name) else { throw ProjectStoreError.emptyName }
        let directory = root.appendingPathComponent(safe, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { throw ProjectStoreError.missingProject }
        adoptLegacyFolders(in: directory)
        return directory
    }

    @discardableResult
    private static func importOriginal(
        data: Data,
        fileName: String,
        folder folderName: String,
        projectName: String,
        at root: URL
    ) throws -> String {
        let directory = try projectDirectory(projectName, at: root)
        let folder = preparedFolder(folderName, legacy: nil, in: directory)
        let stored = uniqueFileName(preferred: fileName, in: folder)
        try data.write(to: folder.appendingPathComponent(stored))
        return stored
    }

    private static func preparedFolder(_ name: String, legacy: String?, in directory: URL) -> URL {
        if let legacy {
            let old = directory.appendingPathComponent(legacy, isDirectory: true)
            let current = directory.appendingPathComponent(name, isDirectory: true)
            moveContents(from: old, to: current)
        }
        let folder = directory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func adoptLegacyFolders(in directory: URL) {
        moveContents(
            from: directory.appendingPathComponent(legacyDrawingFolder, isDirectory: true),
            to: directory.appendingPathComponent(drawingFolder, isDirectory: true)
        )
        moveContents(
            from: directory.appendingPathComponent(legacyExportFolder, isDirectory: true),
            to: directory.appendingPathComponent(exportFolderName, isDirectory: true)
        )
        try? FileManager.default.createDirectory(
            at: directory.appendingPathComponent(simaFolder, isDirectory: true),
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: directory.appendingPathComponent(exportFolderName, isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private static func moveContents(from source: URL, to destination: URL) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: source.path) else { return }
        try? manager.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let items = try? manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { return }
        for item in items {
            let dest = destination.appendingPathComponent(item.lastPathComponent)
            if manager.fileExists(atPath: dest.path) { continue }
            try? manager.moveItem(at: item, to: dest)
        }
        if let left = try? manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil), left.isEmpty {
            try? manager.removeItem(at: source)
        }
    }

    private static func moveTrashContents(from legacyRoot: URL, to root: URL) {
        for name in [trashFolderName, legacyTrashFolderName] {
            let source = legacyRoot.appendingPathComponent(name, isDirectory: true)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let destination = root.appendingPathComponent(trashFolderName, isDirectory: true)
            moveContents(from: source, to: destination)
        }
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
