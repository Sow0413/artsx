import Foundation

/// ヒヤリハットの記録。確定した `記録.json` と報告書は書き換えない。足せるのは、確定前の軌跡と添付だけ。
public enum IncidentTrigger: String, Codable, Sendable, Equatable {
    case alarm
    case manual
    case fall
    case sos

    public var label: String {
        switch self {
        case .alarm: return "接近警報"
        case .manual: return "ヒヤリ"
        case .fall: return "転倒検知"
        case .sos: return "SOS"
        }
    }
}

public struct IncidentSample: Codable, Equatable, Sendable {
    public var at: Date
    public var id: String
    public var name: String
    public var role: CrewRole
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var horizontalAccuracyMeters: Double
    public var courseDegrees: Double?
    public var headingDegrees: Double?

    public init(
        at: Date,
        id: String,
        name: String,
        role: CrewRole,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        horizontalAccuracyMeters: Double,
        courseDegrees: Double? = nil,
        headingDegrees: Double? = nil
    ) {
        self.at = at
        self.id = id
        self.name = name
        self.role = role
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.courseDegrees = courseDegrees
        self.headingDegrees = headingDegrees
    }
}

public struct IncidentParty: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var role: CrewRole
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var horizontalAccuracyMeters: Double
    public var stationText: String
    public var facingDegrees: Double?
    public var facingSource: String
    public var distanceMeters: Double?
    public var workRadiusMeters: Double?

    public init(
        id: String,
        name: String,
        role: CrewRole,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        horizontalAccuracyMeters: Double,
        stationText: String,
        facingDegrees: Double?,
        facingSource: String,
        distanceMeters: Double?,
        workRadiusMeters: Double?
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.stationText = stationText
        self.facingDegrees = facingDegrees
        self.facingSource = facingSource
        self.distanceMeters = distanceMeters
        self.workRadiusMeters = workRadiusMeters
    }
}

public struct IncidentSpeech: Codable, Equatable, Sendable {
    public var at: Date
    public var text: String

    public init(at: Date, text: String) {
        self.at = at
        self.text = text
    }
}

public struct IncidentRadioClip: Codable, Equatable, Sendable {
    public var id: UUID
    public var speaker: String
    public var startedAt: Date
    public var endedAt: Date?
    public var stationText: String?
    public var audioByteCount: Int
    public var audioFile: String?
    public var delivered: Bool

    public init(
        id: UUID,
        speaker: String,
        startedAt: Date,
        endedAt: Date?,
        stationText: String?,
        audioByteCount: Int,
        audioFile: String? = nil,
        delivered: Bool
    ) {
        self.id = id
        self.speaker = speaker
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.stationText = stationText
        self.audioByteCount = audioByteCount
        self.audioFile = audioFile
        self.delivered = delivered
    }
}

public struct IncidentWork: Codable, Equatable, Sendable {
    public var kind: String
    public var name: String

    public init(kind: String, name: String) {
        self.kind = kind
        self.name = name
    }
}

/// 図面の切り出しに重ねる線。メートル。東が正、北が正。原点はこの端末。
public struct IncidentStroke: Codable, Equatable, Sendable {
    public var eastMeters: [Double]
    public var northMeters: [Double]

    public init(eastMeters: [Double], northMeters: [Double]) {
        self.eastMeters = eastMeters
        self.northMeters = northMeters
    }
}

public struct IncidentOpening: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var projectID: String
    public var projectName: String
    public var occurredAt: Date
    public var trigger: IncidentTrigger
    public var parties: [IncidentParty]
    public var machineRadiusMeters: Double
    public var work: IncidentWork
    public var accuracyMeters: Double?
    public var stageLabel: String
    public var solutionLabel: String
    public var speeches: [IncidentSpeech]
    public var radio: [IncidentRadioClip]
    public var strokes: [IncidentStroke]
    public var notice: String
    /// そのときの天候。無い記録は nil。
    public var weather: String?

    public init(
        id: UUID = UUID(),
        projectID: String,
        projectName: String,
        occurredAt: Date,
        trigger: IncidentTrigger,
        parties: [IncidentParty],
        machineRadiusMeters: Double,
        work: IncidentWork,
        accuracyMeters: Double?,
        stageLabel: String,
        solutionLabel: String,
        speeches: [IncidentSpeech],
        radio: [IncidentRadioClip],
        strokes: [IncidentStroke] = [],
        notice: String = SafetyNotice.text,
        weather: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.projectName = projectName
        self.occurredAt = occurredAt
        self.trigger = trigger
        self.parties = parties
        self.machineRadiusMeters = machineRadiusMeters
        self.work = work
        self.accuracyMeters = accuracyMeters
        self.stageLabel = stageLabel
        self.solutionLabel = solutionLabel
        self.speeches = speeches
        self.radio = radio
        self.strokes = strokes
        self.notice = notice
        self.weather = weather
    }
}

public struct IncidentRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var projectID: String
    public var projectName: String
    public var occurredAt: Date
    public var sealedAt: Date
    public var trigger: IncidentTrigger
    public var parties: [IncidentParty]
    public var track: [IncidentSample]
    public var machineRadiusMeters: Double
    public var work: IncidentWork
    public var accuracyMeters: Double?
    public var stageLabel: String
    public var solutionLabel: String
    public var speeches: [IncidentSpeech]
    public var radio: [IncidentRadioClip]
    public var drawingFile: String
    public var mapFile: String
    public var photoFile: String?
    public var voiceMemoFile: String?
    public var notice: String
    public var weather: String?

    public init(
        id: UUID,
        projectID: String,
        projectName: String,
        occurredAt: Date,
        sealedAt: Date,
        trigger: IncidentTrigger,
        parties: [IncidentParty],
        track: [IncidentSample],
        machineRadiusMeters: Double,
        work: IncidentWork,
        accuracyMeters: Double?,
        stageLabel: String,
        solutionLabel: String,
        speeches: [IncidentSpeech],
        radio: [IncidentRadioClip],
        drawingFile: String,
        mapFile: String,
        photoFile: String?,
        voiceMemoFile: String?,
        notice: String,
        weather: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.projectName = projectName
        self.occurredAt = occurredAt
        self.sealedAt = sealedAt
        self.trigger = trigger
        self.parties = parties
        self.track = track
        self.machineRadiusMeters = machineRadiusMeters
        self.work = work
        self.accuracyMeters = accuracyMeters
        self.stageLabel = stageLabel
        self.solutionLabel = solutionLabel
        self.speeches = speeches
        self.radio = radio
        self.drawingFile = drawingFile
        self.mapFile = mapFile
        self.photoFile = photoFile
        self.voiceMemoFile = voiceMemoFile
        self.notice = notice
        self.weather = weather
    }
}

public enum IncidentError: Error, Equatable, CustomStringConvertible {
    case missingProject
    case alreadyExists
    case alreadySealed
    case tooEarly
    case missingOpening

    public var description: String {
        switch self {
        case .missingProject: return "プロジェクトが見つかりません。"
        case .alreadyExists: return "同じインシデントがすでにあります。"
        case .alreadySealed: return "確定した記録は変えられません。"
        case .tooEarly: return "前後60秒が揃うまで確定しません。"
        case .missingOpening: return "インシデントの開始が見つかりません。"
        }
    }
}

public enum IncidentDelivery: String, Codable, Equatable, Sendable {
    case sent
    case pending
}

public struct IncidentHandoff: Codable, Equatable, Sendable {
    public var recordID: UUID
    public var projectID: String
    public var projectName: String
    public var occurredAt: Date
    public var pdfName: String

    public init(recordID: UUID, projectID: String, projectName: String, occurredAt: Date, pdfName: String) {
        self.recordID = recordID
        self.projectID = projectID
        self.projectName = projectName
        self.occurredAt = occurredAt
        self.pdfName = pdfName
    }
}

/// P510 へ渡す口。サーバーは動かさない。届く印が無いときは控えに残す。
public final class IncidentRelayStub {
    public var isReachable: Bool
    public private(set) var sent: [IncidentHandoff] = []
    public private(set) var pending: [IncidentHandoff] = []

    public init(reachable: Bool) {
        self.isReachable = reachable
    }

    public func submit(_ handoff: IncidentHandoff) -> IncidentDelivery {
        if sent.contains(where: { $0.recordID == handoff.recordID }) { return .sent }
        if isReachable {
            sent.append(handoff)
            pending.removeAll { $0.recordID == handoff.recordID }
            return .sent
        }
        if !pending.contains(where: { $0.recordID == handoff.recordID }) {
            pending.append(handoff)
        }
        return .pending
    }
}

public struct IncidentSealResult: Equatable, Sendable {
    public var record: IncidentRecord
    public var delivery: IncidentDelivery

    public init(record: IncidentRecord, delivery: IncidentDelivery) {
        self.record = record
        self.delivery = delivery
    }
}

public enum IncidentParties {
    public static func assemble(
        selfID: String,
        selfName: String,
        selfRole: CrewRole,
        selfLatitude: Double,
        selfLongitude: Double,
        selfAccuracy: Double,
        selfCourse: Double?,
        selfHeading: Double?,
        selfRadius: Double?,
        others: [CrewFix],
        distances: [String: Double] = [:],
        stationLine: StationLine?
    ) -> [IncidentParty] {
        var parties = [
            party(
                id: selfID,
                name: selfName,
                role: selfRole,
                latitude: selfLatitude,
                longitude: selfLongitude,
                accuracy: selfAccuracy,
                course: selfCourse,
                heading: selfHeading,
                distance: nil,
                radius: selfRole == .machine ? selfRadius : nil,
                stationLine: stationLine
            )
        ]
        for other in others where other.id != selfID {
            let distance = distances[other.id] ?? meters(
                fromLatitude: selfLatitude,
                fromLongitude: selfLongitude,
                toLatitude: other.latitudeDegrees,
                toLongitude: other.longitudeDegrees
            )
            parties.append(party(
                id: other.id,
                name: other.name,
                role: other.role,
                latitude: other.latitudeDegrees,
                longitude: other.longitudeDegrees,
                accuracy: other.horizontalAccuracyMeters,
                course: other.courseDegrees,
                heading: other.headingDegrees,
                distance: distance,
                radius: other.workRadiusMeters,
                stationLine: stationLine
            ))
        }
        return parties
    }

    public static func meters(fromLatitude: Double, fromLongitude: Double, toLatitude: Double, toLongitude: Double) -> Double? {
        GRS80Geodesic.inverse(
            latitude1: fromLatitude,
            longitude1: fromLongitude,
            latitude2: toLatitude,
            longitude2: toLongitude
        )?.distanceMeters
    }

    private static func party(
        id: String,
        name: String,
        role: CrewRole,
        latitude: Double,
        longitude: Double,
        accuracy: Double,
        course: Double?,
        heading: Double?,
        distance: Double?,
        radius: Double?,
        stationLine: StationLine?
    ) -> IncidentParty {
        let facing = facing(course: course, heading: heading)
        let station = stationLine?.locate(latitudeDegrees: latitude, longitudeDegrees: longitude)?.line ?? "中心線がありません"
        return IncidentParty(
            id: id,
            name: name,
            role: role,
            latitudeDegrees: latitude,
            longitudeDegrees: longitude,
            horizontalAccuracyMeters: accuracy,
            stationText: station,
            facingDegrees: facing.degrees,
            facingSource: facing.source,
            distanceMeters: distance,
            workRadiusMeters: radius
        )
    }

    static func facing(course: Double?, heading: Double?) -> (degrees: Double?, source: String) {
        if let course, course.isFinite { return (course, "進行") }
        if let heading, heading.isFinite { return (heading, "方位") }
        return (nil, "向きなし")
    }
}

public enum IncidentBook {
    public static let beforeSeconds: TimeInterval = 60
    public static let afterSeconds: TimeInterval = 60
    public static let openingName = "開始.json"
    public static let trackName = "軌跡.jsonl"
    public static let recordName = "記録.json"
    public static let pdfName = "ヒヤリハット報告書.pdf"
    public static let drawingName = "図面.png"
    public static let mapName = "地図.png"
    public static let photoName = "添付写真.png"
    public static let voiceName = "音声メモ.caf"
    public static let sentName = "送信済.json"

    public static func clip(_ samples: [IncidentSample], around: Date, before: TimeInterval = beforeSeconds, after: TimeInterval = afterSeconds) -> [IncidentSample] {
        let unique = deduped(samples)
        return unique.filter { sample in
            let delta = sample.at.timeIntervalSince(around)
            return delta >= -before && delta <= after
        }
    }

    public static func contains(_ sample: IncidentSample, around: Date) -> Bool {
        let delta = sample.at.timeIntervalSince(around)
        return delta >= -beforeSeconds && delta <= afterSeconds
    }

    public static func begin(_ opening: IncidentOpening, projectName: String, at root: URL) throws {
        let directory = try incidentDirectory(opening.id, projectName: projectName, at: root, create: true)
        let url = directory.appendingPathComponent(openingName)
        if FileManager.default.fileExists(atPath: url.path) || FileManager.default.fileExists(atPath: directory.appendingPathComponent(recordName).path) {
            throw IncidentError.alreadyExists
        }
        try encode(opening, to: url)
    }

    public static func appendSample(_ sample: IncidentSample, incidentID: UUID, projectName: String, at root: URL) throws {
        let directory = try incidentDirectory(incidentID, projectName: projectName, at: root, create: false)
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent(recordName).path) {
            throw IncidentError.alreadySealed
        }
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(openingName).path) else {
            throw IncidentError.missingOpening
        }
        let url = directory.appendingPathComponent(trackName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var line = try encoder.encode(sample)
        line.append(0x0A)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url)
        }
    }

    public static func attachPhoto(_ data: Data, incidentID: UUID, projectName: String, at root: URL) throws {
        try attach(data, name: photoName, incidentID: incidentID, projectName: projectName, at: root)
    }

    public static func attachVoice(_ data: Data, incidentID: UUID, projectName: String, at root: URL) throws {
        try attach(data, name: voiceName, incidentID: incidentID, projectName: projectName, at: root)
    }

    /// 開始から60秒以上たっていれば、記録と報告書を一度だけ書く。
    public static func seal(
        incidentID: UUID,
        projectName: String,
        at root: URL,
        now: Date,
        extraSamples: [IncidentSample] = [],
        speeches: [IncidentSpeech] = [],
        radio: [IncidentRadioClip] = [],
        audio: [UUID: Data] = [:]
    ) throws -> IncidentRecord {
        let directory = try incidentDirectory(incidentID, projectName: projectName, at: root, create: false)
        let recordURL = directory.appendingPathComponent(recordName)
        if FileManager.default.fileExists(atPath: recordURL.path) {
            throw IncidentError.alreadySealed
        }
        let opening = try loadOpening(in: directory)
        guard now.timeIntervalSince(opening.occurredAt) >= afterSeconds else {
            throw IncidentError.tooEarly
        }
        let origin = opening.parties.first
        let track = clip(readTrack(in: directory) + extraSamples, around: opening.occurredAt)
        let drawing = IncidentPNG.drawing(
            parties: opening.parties,
            track: track,
            radiusMeters: opening.machineRadiusMeters,
            strokes: opening.strokes,
            originLatitude: origin?.latitudeDegrees ?? 0,
            originLongitude: origin?.longitudeDegrees ?? 0
        )
        let map = IncidentPNG.map(
            parties: opening.parties,
            track: track,
            originLatitude: origin?.latitudeDegrees ?? 0,
            originLongitude: origin?.longitudeDegrees ?? 0
        )
        try drawing.write(to: directory.appendingPathComponent(drawingName))
        try map.write(to: directory.appendingPathComponent(mapName))
        var clips = mergeRadio(opening.radio, radio)
        for index in clips.indices {
            guard let data = audio[clips[index].id], !data.isEmpty else { continue }
            let name = "無線-\(clips[index].id.uuidString).pcm"
            let url = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) {
                try data.write(to: url)
            }
            clips[index].audioFile = name
        }
        let photo = FileManager.default.fileExists(atPath: directory.appendingPathComponent(photoName).path) ? photoName : nil
        let voice = FileManager.default.fileExists(atPath: directory.appendingPathComponent(voiceName).path) ? voiceName : nil
        let record = IncidentRecord(
            id: opening.id,
            projectID: opening.projectID,
            projectName: opening.projectName,
            occurredAt: opening.occurredAt,
            sealedAt: now,
            trigger: opening.trigger,
            parties: opening.parties,
            track: track,
            machineRadiusMeters: opening.machineRadiusMeters,
            work: opening.work,
            accuracyMeters: opening.accuracyMeters,
            stageLabel: opening.stageLabel,
            solutionLabel: opening.solutionLabel,
            speeches: mergeSpeech(opening.speeches, speeches, around: opening.occurredAt),
            radio: clips,
            drawingFile: drawingName,
            mapFile: mapName,
            photoFile: photo,
            voiceMemoFile: voice,
            notice: opening.notice,
            weather: opening.weather
        )
        try encode(record, to: recordURL)
        try IncidentReport.pdf(record).write(to: directory.appendingPathComponent(pdfName))
        return record
    }

    public static func loadOpening(incidentID: UUID, projectName: String, at root: URL) throws -> IncidentOpening {
        let directory = try incidentDirectory(incidentID, projectName: projectName, at: root, create: false)
        return try loadOpening(in: directory)
    }

    public static func load(incidentID: UUID, projectName: String, at root: URL) throws -> IncidentRecord {
        let directory = try incidentDirectory(incidentID, projectName: projectName, at: root, create: false)
        let url = directory.appendingPathComponent(recordName)
        guard let data = try? Data(contentsOf: url) else { throw IncidentError.missingOpening }
        let decoder = decoder()
        return try decoder.decode(IncidentRecord.self, from: data)
    }

    public static func sealed(projectName: String, at root: URL) -> [IncidentRecord] {
        guard let parent = try? parentDirectory(projectName: projectName, at: root, create: false) else { return [] }
        guard let urls = try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) else { return [] }
        let decoder = decoder()
        return urls.compactMap { url in
            let recordURL = url.appendingPathComponent(recordName)
            guard let data = try? Data(contentsOf: recordURL) else { return nil }
            return try? decoder.decode(IncidentRecord.self, from: data)
        }
    }

    public static func unsealed(projectName: String, at root: URL) -> [IncidentOpening] {
        guard let parent = try? parentDirectory(projectName: projectName, at: root, create: false) else { return [] }
        guard let urls = try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return urls.compactMap { url in
            let record = url.appendingPathComponent(recordName)
            let opening = url.appendingPathComponent(openingName)
            guard !FileManager.default.fileExists(atPath: record.path),
                  let data = try? Data(contentsOf: opening) else { return nil }
            return try? decoder().decode(IncidentOpening.self, from: data)
        }
    }

    public static func unsent(projectName: String, at root: URL) -> [IncidentHandoff] {
        guard let parent = try? parentDirectory(projectName: projectName, at: root, create: false) else { return [] }
        guard let urls = try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) else { return [] }
        return urls.compactMap { url in
            let recordURL = url.appendingPathComponent(recordName)
            let sentURL = url.appendingPathComponent(sentName)
            guard FileManager.default.fileExists(atPath: recordURL.path),
                  !FileManager.default.fileExists(atPath: sentURL.path),
                  let data = try? Data(contentsOf: recordURL),
                  let record = try? decoder().decode(IncidentRecord.self, from: data) else { return nil }
            return IncidentHandoff(
                recordID: record.id,
                projectID: record.projectID,
                projectName: record.projectName,
                occurredAt: record.occurredAt,
                pdfName: pdfName
            )
        }
    }

    public static func markSent(_ handoff: IncidentHandoff, projectName: String, at root: URL, now: Date) throws {
        let directory = try incidentDirectory(handoff.recordID, projectName: projectName, at: root, create: false)
        let url = directory.appendingPathComponent(sentName)
        if FileManager.default.fileExists(atPath: url.path) { return }
        let mark = IncidentSent(recordID: handoff.recordID, sentAt: now)
        try encode(mark, to: url)
    }

    public static func directory(incidentID: UUID, projectName: String, at root: URL) throws -> URL {
        try incidentDirectory(incidentID, projectName: projectName, at: root, create: false)
    }

    static func deduped(_ samples: [IncidentSample]) -> [IncidentSample] {
        var seen: Set<String> = []
        var kept: [IncidentSample] = []
        for sample in samples.sorted(by: { $0.at < $1.at }) {
            let key = "\(sample.id)|\(sample.at.timeIntervalSince1970)"
            if seen.insert(key).inserted {
                kept.append(sample)
            }
        }
        return kept
    }

    private static func attach(_ data: Data, name: String, incidentID: UUID, projectName: String, at root: URL) throws {
        guard !data.isEmpty else { return }
        let directory = try incidentDirectory(incidentID, projectName: projectName, at: root, create: false)
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent(recordName).path) {
            throw IncidentError.alreadySealed
        }
        let url = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            throw IncidentError.alreadySealed
        }
        try data.write(to: url)
    }

    private static func loadOpening(in directory: URL) throws -> IncidentOpening {
        let url = directory.appendingPathComponent(openingName)
        guard let data = try? Data(contentsOf: url) else { throw IncidentError.missingOpening }
        return try decoder().decode(IncidentOpening.self, from: data)
    }

    private static func readTrack(in directory: URL) -> [IncidentSample] {
        let url = directory.appendingPathComponent(trackName)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = decoder()
        return text.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(IncidentSample.self, from: data)
        }
    }

    private static func mergeSpeech(_ opening: [IncidentSpeech], _ extra: [IncidentSpeech], around: Date) -> [IncidentSpeech] {
        var merged = opening
        for speech in extra where containsSpeech(speech, around: around) {
            if !merged.contains(where: { $0.at == speech.at && $0.text == speech.text }) {
                merged.append(speech)
            }
        }
        return merged.sorted { $0.at < $1.at }
    }

    private static func containsSpeech(_ speech: IncidentSpeech, around: Date) -> Bool {
        let delta = speech.at.timeIntervalSince(around)
        return delta >= -beforeSeconds && delta <= afterSeconds
    }

    private static func mergeRadio(_ opening: [IncidentRadioClip], _ extra: [IncidentRadioClip]) -> [IncidentRadioClip] {
        var merged = opening
        for clip in extra where !merged.contains(where: { $0.id == clip.id }) {
            merged.append(clip)
        }
        return merged.sorted { $0.startedAt < $1.startedAt }
    }

    private static func parentDirectory(projectName: String, at root: URL, create: Bool) throws -> URL {
        let project = try ProjectStore.projectDirectory(projectName, at: root)
        let folder = project.appendingPathComponent("記録簿", isDirectory: true).appendingPathComponent("インシデント", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    private static func incidentDirectory(_ id: UUID, projectName: String, at root: URL, create: Bool) throws -> URL {
        let parent = try parentDirectory(projectName: projectName, at: root, create: create)
        let directory = parent.appendingPathComponent(id.uuidString, isDirectory: true)
        if create {
            if FileManager.default.fileExists(atPath: directory.path) {
                throw IncidentError.alreadyExists
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } else if !FileManager.default.fileExists(atPath: directory.path) {
            throw IncidentError.missingOpening
        }
        return directory
    }

    private static func encode<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url)
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

struct IncidentSent: Codable, Equatable {
    var recordID: UUID
    var sentAt: Date
}

/// 開始してから60秒後に一度だけ確定する。警報が鳴り続けても、開いているあいだは増やさない。
public final class IncidentSession {
    public let relay: IncidentRelayStub
    public private(set) var open: [UUID: IncidentOpening] = [:]
    private var samples: [IncidentSample] = []
    private var alarmID: UUID?

    public init(relay: IncidentRelayStub = IncidentRelayStub(reachable: false)) {
        self.relay = relay
    }

    public var latestID: UUID? {
        open.max { $0.value.occurredAt < $1.value.occurredAt }?.key
    }

    public func observe(_ batch: [IncidentSample], projectName: String, at root: URL) {
        samples.append(contentsOf: batch)
        prune(now: batch.map(\.at).max() ?? Date())
        for opening in open.values {
            for sample in batch where IncidentBook.contains(sample, around: opening.occurredAt) {
                try? IncidentBook.appendSample(sample, incidentID: opening.id, projectName: projectName, at: root)
            }
        }
    }

    /// 警報は、未確定のものがあればそれを返す。ヒヤリは毎回新しい記録を始める。
    @discardableResult
    public func open(_ opening: IncidentOpening, projectName: String, at root: URL) throws -> UUID {
        if opening.trigger == .alarm, let alarmID, open[alarmID] != nil {
            return alarmID
        }
        try IncidentBook.begin(opening, projectName: projectName, at: root)
        open[opening.id] = opening
        if opening.trigger == .alarm {
            alarmID = opening.id
        }
        for sample in samples where IncidentBook.contains(sample, around: opening.occurredAt) {
            try? IncidentBook.appendSample(sample, incidentID: opening.id, projectName: projectName, at: root)
        }
        return opening.id
    }

    public func restore(projectName: String, at root: URL) {
        for opening in IncidentBook.unsealed(projectName: projectName, at: root) {
            open[opening.id] = opening
            if opening.trigger == .alarm {
                alarmID = opening.id
            }
        }
    }

    public func attachPhoto(_ data: Data, projectName: String, at root: URL) throws {
        guard let id = latestID else { throw IncidentError.missingOpening }
        try IncidentBook.attachPhoto(data, incidentID: id, projectName: projectName, at: root)
    }

    public func attachVoice(_ data: Data, projectName: String, at root: URL) throws {
        guard let id = latestID else { throw IncidentError.missingOpening }
        try IncidentBook.attachVoice(data, incidentID: id, projectName: projectName, at: root)
    }

    public func closeDue(
        projectName: String,
        at root: URL,
        now: Date,
        speeches: [IncidentSpeech] = [],
        radio: [IncidentRadioClip] = [],
        audio: [UUID: Data] = [:]
    ) throws -> [IncidentSealResult] {
        var results: [IncidentSealResult] = []
        let due = open.values.filter { now.timeIntervalSince($0.occurredAt) >= IncidentBook.afterSeconds }
        for opening in due {
            let record = try IncidentBook.seal(
                incidentID: opening.id,
                projectName: projectName,
                at: root,
                now: now,
                speeches: speeches,
                radio: radio,
                audio: audio
            )
            let handoff = IncidentHandoff(
                recordID: record.id,
                projectID: record.projectID,
                projectName: record.projectName,
                occurredAt: record.occurredAt,
                pdfName: IncidentBook.pdfName
            )
            let delivery = relay.submit(handoff)
            if delivery == .sent {
                try? IncidentBook.markSent(handoff, projectName: projectName, at: root, now: now)
            }
            open[opening.id] = nil
            if alarmID == opening.id {
                alarmID = nil
            }
            results.append(IncidentSealResult(record: record, delivery: delivery))
        }
        return results
    }

    public func flush(projectName: String, at root: URL, now: Date) {
        guard relay.isReachable else { return }
        for handoff in IncidentBook.unsent(projectName: projectName, at: root) {
            if relay.submit(handoff) == .sent {
                try? IncidentBook.markSent(handoff, projectName: projectName, at: root, now: now)
            }
        }
    }

    private func prune(now: Date) {
        let openFrom = open.values.map { $0.occurredAt.addingTimeInterval(-IncidentBook.beforeSeconds) }.min()
        let horizon = min(openFrom ?? now, now.addingTimeInterval(-(IncidentBook.beforeSeconds + 10)))
        samples.removeAll { $0.at < horizon }
    }
}

enum IncidentReport {
    static let title = "ヒヤリハット報告書"

    static func pdf(_ record: IncidentRecord) -> Data {
        IncidentPDF.pages(lines: lines(record))
    }

    static func lines(_ record: IncidentRecord) -> [String] {
        var lines = [
            title,
            record.notice
        ]
        if record.trigger == .fall, !record.notice.contains(FallCall.disclaimer) {
            lines.append(FallCall.disclaimer)
        }
        if record.trigger == .sos, !record.notice.contains(SOSCall.disclaimer) {
            lines.append(SOSCall.disclaimer)
        }
        lines.append(contentsOf: [
            "日時 \(stamp.string(from: record.occurredAt))",
            "きっかけ \(record.trigger.label)",
            "プロジェクト \(record.projectName)",
            "作業 \(record.work.kind) \(record.work.name)",
            "作業半径 \(tenths(record.machineRadiusMeters))m",
            "精度 \(record.accuracyMeters.map { tenths($0) + "m" } ?? "—") \(record.stageLabel) \(record.solutionLabel)",
            "関係者"
        ])
        for party in record.parties {
            let facing: String
            if let degrees = party.facingDegrees {
                facing = "\(party.facingSource) \(Int(degrees.rounded()))度"
            } else {
                facing = party.facingSource
            }
            let distance = party.distanceMeters.map { tenths($0) + "m" } ?? "—"
            lines.append("\(party.name)（\(party.role.label)） \(coordinate(party.latitudeDegrees)) \(coordinate(party.longitudeDegrees))")
            lines.append("測点 \(party.stationText) 向き \(facing) 距離 \(distance) 精度 \(tenths(party.horizontalAccuracyMeters))m")
        }
        lines.append("軌跡 前後60秒 \(record.track.count)点")
        for sample in record.track.prefix(12) {
            lines.append("\(stamp.string(from: sample.at)) \(sample.name) \(coordinate(sample.latitudeDegrees)) \(coordinate(sample.longitudeDegrees))")
        }
        if record.track.count > 12 {
            lines.append("残りは記録.json")
        }
        lines.append("読み上げ")
        if record.speeches.isEmpty {
            lines.append("なし")
        } else {
            for speech in record.speeches {
                lines.append("\(stamp.string(from: speech.at)) \(speech.text)")
            }
        }
        lines.append("無線")
        if record.radio.isEmpty {
            lines.append("なし")
        } else {
            for clip in record.radio {
                let station = clip.stationText.map { "測点 \($0)" } ?? "測点なし"
                let audio = clip.audioFile == nil ? "音声 \(clip.audioByteCount)バイト" : "音声ファイルあり"
                let delivered = clip.delivered ? "届いた" : "届いていない"
                lines.append("\(clip.speaker) \(station) \(audio) \(delivered)")
            }
        }
        lines.append("図面 \(record.drawingFile)")
        lines.append("地図 \(record.mapFile)")
        lines.append("写真 \(record.photoFile ?? "なし")")
        lines.append("音声メモ \(record.voiceMemoFile ?? "なし")")
        lines.append("この記録は追記のみです。中身は変えられません。")
        return lines
    }

    private static func tenths(_ meters: Double) -> String {
        String(format: "%.1f", MachineReach.roundTenths(meters))
    }

    private static func coordinate(_ degrees: Double) -> String {
        String(format: "%.8f", degrees)
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

enum IncidentPDF {
    static func pages(lines: [String]) -> Data {
        let wrapped = lines.flatMap { wrap($0) }
        let chunks = stride(from: 0, to: max(wrapped.count, 1), by: 44).map { start -> [String] in
            let end = min(start + 44, wrapped.count)
            return start < wrapped.count ? Array(wrapped[start..<end]) : [" "]
        }
        var objects: [String] = []
        var kids: [String] = []
        let fontStart = 3
        for index in chunks.indices {
            let pageNumber = 6 + index * 2
            let contentNumber = pageNumber + 1
            kids.append("\(pageNumber) 0 R")
            objects.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents \(contentNumber) 0 R /Resources << /Font << /F1 \(fontStart) 0 R /F2 \(fontStart + 1) 0 R >> >> >>")
            objects.append(stream(chunks[index]))
        }
        let pageCount = chunks.count
        let head = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [\(kids.joined(separator: " "))] /Count \(pageCount) >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Type /Font /Subtype /Type0 /BaseFont /HeiseiKakuGo-W5 /Encoding /UniJIS-UTF16-H /DescendantFonts [5 0 R] >>",
            "<< /Type /Font /Subtype /CIDFontType0 /BaseFont /HeiseiKakuGo-W5 /CIDSystemInfo << /Registry (Adobe) /Ordering (Japan1) /Supplement 2 >> >>"
        ]
        let all = head + objects
        var body = Data("%PDF-1.4\n".utf8)
        var offsets: [Int] = [0]
        for (index, object) in all.enumerated() {
            offsets.append(body.count)
            body.append(Data("\(index + 1) 0 obj\n\(object)\nendobj\n".utf8))
        }
        let xref = body.count
        var table = "xref\n0 \(all.count + 1)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() {
            table += String(format: "%010d 00000 n \n", offset)
        }
        body.append(Data(table.utf8))
        body.append(Data("trailer << /Size \(all.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
        return body
    }

    private static func stream(_ lines: [String]) -> String {
        var commands = ""
        var y = 800
        var font = ""
        for line in lines {
            let japanese = !line.utf8.allSatisfy { $0 < 128 }
            let next = japanese ? "F2" : "F1"
            if next != font {
                if !commands.isEmpty { commands += "ET\n" }
                commands += "BT\n/\(next) 11 Tf\n40 \(y) Td\n"
                font = next
            }
            if japanese {
                commands += "<\(utf16(line))> Tj\n0 -16 Td\n"
            } else {
                commands += "(\(escaped(line))) Tj\n0 -16 Td\n"
            }
            y -= 16
        }
        if !commands.isEmpty { commands += "ET\n" }
        return "<< /Length \(Data(commands.utf8).count) >>\nstream\n\(commands)endstream"
    }

    private static func wrap(_ line: String) -> [String] {
        let limit = line.utf8.allSatisfy { $0 < 128 } ? 90 : 42
        if line.isEmpty { return [" "] }
        if line.count <= limit { return [line] }
        var parts: [String] = []
        var rest = Substring(line)
        while !rest.isEmpty {
            let end = rest.index(rest.startIndex, offsetBy: limit, limitedBy: rest.endIndex) ?? rest.endIndex
            parts.append(String(rest[..<end]))
            rest = rest[end...]
        }
        return parts
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
    }

    private static func utf16(_ text: String) -> String {
        var hex = "FEFF"
        for unit in text.utf16 {
            hex += String(format: "%04X", unit)
        }
        return hex
    }
}

enum IncidentPNG {
    static let width = 160
    static let height = 160

    static func drawing(
        parties: [IncidentParty],
        track: [IncidentSample],
        radiusMeters: Double,
        strokes: [IncidentStroke],
        originLatitude: Double,
        originLongitude: Double
    ) -> Data {
        raster(
            parties: parties,
            track: track,
            radiusMeters: radiusMeters,
            strokes: strokes,
            originLatitude: originLatitude,
            originLongitude: originLongitude,
            background: (18, 22, 28),
            drawRadius: true
        )
    }

    static func map(
        parties: [IncidentParty],
        track: [IncidentSample],
        originLatitude: Double,
        originLongitude: Double
    ) -> Data {
        raster(
            parties: parties,
            track: track,
            radiusMeters: 0,
            strokes: [],
            originLatitude: originLatitude,
            originLongitude: originLongitude,
            background: (12, 36, 28),
            drawRadius: false
        )
    }

    static func rgb(_ data: Data) -> (width: Int, height: Int, rgb: [UInt8])? {
        let bytes = [UInt8](data)
        let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        guard bytes.starts(with: signature) else { return nil }
        var index = 8
        var width = 0
        var height = 0
        var idat = Data()
        while index + 8 <= bytes.count {
            let length = Int(bytes[index]) << 24 | Int(bytes[index + 1]) << 16 | Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            let type = String(bytes: bytes[(index + 4)..<(index + 8)], encoding: .ascii) ?? ""
            let start = index + 8
            guard start + length <= bytes.count else { return nil }
            let chunk = bytes[start..<(start + length)]
            if type == "IHDR", chunk.count >= 8 {
                width = chunk.prefix(4).reduce(0) { $0 << 8 | Int($1) }
                height = chunk.dropFirst(4).prefix(4).reduce(0) { $0 << 8 | Int($1) }
            } else if type == "IDAT" {
                idat.append(contentsOf: chunk)
            } else if type == "IEND" {
                break
            }
            index = start + length + 4
        }
        guard width > 0, height > 0, let inflated = inflateStored([UInt8](idat)) else { return nil }
        let stride = 1 + width * 3
        guard inflated.count >= height * stride else { return nil }
        var rgb: [UInt8] = []
        rgb.reserveCapacity(width * height * 3)
        for row in 0..<height {
            let start = row * stride + 1
            rgb.append(contentsOf: inflated[start..<(start + width * 3)])
        }
        return (width, height, rgb)
    }

    private static func raster(
        parties: [IncidentParty],
        track: [IncidentSample],
        radiusMeters: Double,
        strokes: [IncidentStroke],
        originLatitude: Double,
        originLongitude: Double,
        background: (UInt8, UInt8, UInt8),
        drawRadius: Bool
    ) -> Data {
        var points: [(east: Double, north: Double)] = [(0, 0)]
        for party in parties {
            points.append(local(latitude: party.latitudeDegrees, longitude: party.longitudeDegrees, originLatitude: originLatitude, originLongitude: originLongitude))
        }
        for sample in track {
            points.append(local(latitude: sample.latitudeDegrees, longitude: sample.longitudeDegrees, originLatitude: originLatitude, originLongitude: originLongitude))
        }
        var span = max(radiusMeters * 2.4, 20)
        for point in points {
            span = max(span, abs(point.east) * 2.4, abs(point.north) * 2.4)
        }
        span = min(span, 240)
        var pixels = [UInt8](repeating: 0, count: width * height * 3)
        for index in 0..<(width * height) {
            pixels[index * 3] = background.0
            pixels[index * 3 + 1] = background.1
            pixels[index * 3 + 2] = background.2
        }
        func plot(_ east: Double, _ north: Double, color: (UInt8, UInt8, UInt8), radius: Int) {
            let pixel = pixel(east: east, north: north, span: span)
            for dy in -radius...radius {
                for dx in -radius...radius where dx * dx + dy * dy <= radius * radius {
                    set(pixel.x + dx, pixel.y + dy, color, pixels: &pixels)
                }
            }
        }
        if drawRadius, radiusMeters > 0 {
            let pixelRadius = max(2, Int((radiusMeters / span) * Double(width)))
            let center = pixel(east: 0, north: 0, span: span)
            circle(center.x, center.y, pixelRadius, color: (232, 168, 48), pixels: &pixels)
        }
        for stroke in strokes {
            let count = min(stroke.eastMeters.count, stroke.northMeters.count)
            guard count >= 2 else { continue }
            for index in 1..<count {
                let from = (stroke.eastMeters[index - 1], stroke.northMeters[index - 1])
                let to = (stroke.eastMeters[index], stroke.northMeters[index])
                let near = max(max(abs(from.0), abs(from.1)), max(abs(to.0), abs(to.1))) < span * 1.2
                guard near else { continue }
                let start = pixel(east: from.0, north: from.1, span: span)
                let end = pixel(east: to.0, north: to.1, span: span)
                line(start.x, start.y, end.x, end.y, color: (120, 170, 210), pixels: &pixels)
            }
        }
        for sample in track {
            let point = local(latitude: sample.latitudeDegrees, longitude: sample.longitudeDegrees, originLatitude: originLatitude, originLongitude: originLongitude)
            plot(point.east, point.north, color: (150, 156, 164), radius: 1)
        }
        for party in parties {
            let point = local(latitude: party.latitudeDegrees, longitude: party.longitudeDegrees, originLatitude: originLatitude, originLongitude: originLongitude)
            let color: (UInt8, UInt8, UInt8) = party.role == .machine ? (239, 68, 68) : (245, 196, 32)
            plot(point.east, point.north, color: color, radius: 4)
        }
        if !drawRadius {
            let north = pixel(east: 0, north: span * 0.35, span: span)
            let origin = pixel(east: 0, north: 0, span: span)
            line(origin.x, origin.y, north.x, north.y, color: (230, 236, 232), pixels: &pixels)
        }
        return encode(pixels)
    }

    private static func local(latitude: Double, longitude: Double, originLatitude: Double, originLongitude: Double) -> (east: Double, north: Double) {
        let north = (latitude - originLatitude) * 111_320
        let east = (longitude - originLongitude) * 111_320 * cos(originLatitude * .pi / 180)
        return (east, north)
    }

    private static func pixel(east: Double, north: Double, span: Double) -> (x: Int, y: Int) {
        let x = Int(((east / span) + 0.5) * Double(width - 1))
        let y = Int((0.5 - (north / span)) * Double(height - 1))
        return (x, y)
    }

    private static func set(_ x: Int, _ y: Int, _ color: (UInt8, UInt8, UInt8), pixels: inout [UInt8]) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let index = (y * width + x) * 3
        pixels[index] = color.0
        pixels[index + 1] = color.1
        pixels[index + 2] = color.2
    }

    private static func circle(_ cx: Int, _ cy: Int, _ radius: Int, color: (UInt8, UInt8, UInt8), pixels: inout [UInt8]) {
        var x = radius
        var y = 0
        var decision = 1 - x
        while y <= x {
            set(cx + x, cy + y, color, pixels: &pixels)
            set(cx + y, cy + x, color, pixels: &pixels)
            set(cx - y, cy + x, color, pixels: &pixels)
            set(cx - x, cy + y, color, pixels: &pixels)
            set(cx - x, cy - y, color, pixels: &pixels)
            set(cx - y, cy - x, color, pixels: &pixels)
            set(cx + y, cy - x, color, pixels: &pixels)
            set(cx + x, cy - y, color, pixels: &pixels)
            y += 1
            if decision <= 0 {
                decision += 2 * y + 1
            } else {
                x -= 1
                decision += 2 * (y - x) + 1
            }
        }
    }

    private static func line(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, color: (UInt8, UInt8, UInt8), pixels: inout [UInt8]) {
        var x = x0
        var y = y0
        let dx = abs(x1 - x0)
        let dy = -abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1
        let sy = y0 < y1 ? 1 : -1
        var error = dx + dy
        while true {
            set(x, y, color, pixels: &pixels)
            if x == x1, y == y1 { break }
            let twice = 2 * error
            if twice >= dy {
                error += dy
                x += sx
            }
            if twice <= dx {
                error += dx
                y += sy
            }
        }
    }

    private static func encode(_ rgb: [UInt8]) -> Data {
        var raw: [UInt8] = []
        raw.reserveCapacity(height * (1 + width * 3))
        for row in 0..<height {
            raw.append(0)
            let start = row * width * 3
            raw.append(contentsOf: rgb[start..<(start + width * 3)])
        }
        let compressed = zlibStore(raw)
        var png = Data([137, 80, 78, 71, 13, 10, 26, 10])
        var ihdr = Data()
        ihdr.append(contentsOf: be(UInt32(width)))
        ihdr.append(contentsOf: be(UInt32(height)))
        ihdr.append(contentsOf: [8, 2, 0, 0, 0])
        png.append(chunk("IHDR", ihdr))
        png.append(chunk("IDAT", Data(compressed)))
        png.append(chunk("IEND", Data()))
        return png
    }

    private static func chunk(_ type: String, _ data: Data) -> Data {
        var body = Data(type.utf8)
        body.append(data)
        var out = Data(be(UInt32(data.count)))
        out.append(body)
        out.append(contentsOf: be(crc32([UInt8](body))))
        return out
    }

    private static func be(_ value: UInt32) -> [UInt8] {
        [UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
    }

    private static func zlibStore(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0x78, 0x01]
        var offset = 0
        while offset < data.count {
            let chunk = min(data.count - offset, 65535)
            let last = offset + chunk == data.count
            out.append(last ? 1 : 0)
            out.append(UInt8(chunk & 0xff))
            out.append(UInt8((chunk >> 8) & 0xff))
            let nlen = chunk ^ 0xffff
            out.append(UInt8(nlen & 0xff))
            out.append(UInt8((nlen >> 8) & 0xff))
            out.append(contentsOf: data[offset..<(offset + chunk)])
            offset += chunk
        }
        let sum = adler32(data)
        out.append(UInt8((sum >> 24) & 0xff))
        out.append(UInt8((sum >> 16) & 0xff))
        out.append(UInt8((sum >> 8) & 0xff))
        out.append(UInt8(sum & 0xff))
        return out
    }

    private static func inflateStored(_ zlib: [UInt8]) -> [UInt8]? {
        guard zlib.count > 6 else { return nil }
        var index = 2
        var out: [UInt8] = []
        while index + 5 <= zlib.count {
            let header = zlib[index]
            let last = header & 1
            let kind = (header >> 1) & 3
            guard kind == 0 else { return nil }
            index += 1
            let length = Int(zlib[index]) | (Int(zlib[index + 1]) << 8)
            index += 4
            guard index + length <= zlib.count else { return nil }
            out.append(contentsOf: zlib[index..<(index + length)])
            index += length
            if last == 1 { break }
        }
        return out
    }

    private static func adler32(_ data: [UInt8]) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return (b << 16) | a
    }

    private static func crc32(_ data: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                let mask = (crc & 1) * 0xedb8_8320
                crc = (crc >> 1) ^ mask
            }
        }
        return crc ^ 0xffff_ffff
    }
}
