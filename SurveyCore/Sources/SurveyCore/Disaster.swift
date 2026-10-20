import Foundation

/// 災害派遣で残す被災の種類。
public enum DisasterKind: String, Codable, CaseIterable, Sendable {
    case collapse
    case flood
    case roadCut
    case bridge
    case sediment
    case other

    public var label: String {
        switch self {
        case .collapse: return "崩落"
        case .flood: return "冠水"
        case .roadCut: return "道路寸断"
        case .bridge: return "橋梁損傷"
        case .sediment: return "土砂"
        case .other: return "その他"
        }
    }
}

/// 延長・幅・高さ。メートル。未計測は nil。
public struct DisasterMeasure: Codable, Equatable, Sendable {
    public var lengthMeters: Double?
    public var widthMeters: Double?
    public var heightMeters: Double?

    public init(lengthMeters: Double? = nil, widthMeters: Double? = nil, heightMeters: Double? = nil) {
        self.lengthMeters = lengthMeters
        self.widthMeters = widthMeters
        self.heightMeters = heightMeters
    }
}

public struct DisasterSite: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var at: Date
    public var kind: DisasterKind
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var horizontalAccuracyMeters: Double?
    public var measure: DisasterMeasure
    public var note: String
    public var photoFile: String?
    public var author: String

    public init(
        id: UUID = UUID(),
        at: Date,
        kind: DisasterKind,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        horizontalAccuracyMeters: Double? = nil,
        measure: DisasterMeasure = DisasterMeasure(),
        note: String = "",
        photoFile: String? = nil,
        author: String
    ) {
        self.id = id
        self.at = at
        self.kind = kind
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.measure = measure
        self.note = note
        self.photoFile = photoFile
        self.author = author
    }
}

public enum PassageState: String, Codable, Sendable {
    case open
    case closed

    public var label: String {
        switch self {
        case .open: return "通れる"
        case .closed: return "通れない"
        }
    }
}

public struct PassageSample: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var at: Date
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var state: PassageState
    public var author: String

    public init(
        id: UUID = UUID(),
        at: Date,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        state: PassageState,
        author: String
    ) {
        self.id = id
        self.at = at
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.state = state
        self.author = author
    }
}

public struct PassagePoint: Equatable, Sendable {
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double

    public init(latitudeDegrees: Double, longitudeDegrees: Double) {
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
    }
}

public struct PassageSegment: Equatable, Sendable {
    public var author: String
    public var state: PassageState
    public var points: [PassagePoint]

    public init(author: String, state: PassageState, points: [PassagePoint]) {
        self.author = author
        self.state = state
        self.points = points
    }
}

public struct DisasterText: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var at: Date
    public var author: String
    public var body: String

    public init(id: UUID = UUID(), at: Date, author: String, body: String) {
        self.id = id
        self.at = at
        self.author = author
        self.body = body
    }
}

public struct DisasterPosition: Codable, Equatable, Sendable {
    public var deviceID: String
    public var name: String
    public var at: Date
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var horizontalAccuracyMeters: Double?

    public init(
        deviceID: String,
        name: String,
        at: Date,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        horizontalAccuracyMeters: Double? = nil
    ) {
        self.deviceID = deviceID
        self.name = name
        self.at = at
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
    }
}

public enum DisasterEntryError: Error, Equatable {
    case missingPlace
    case badMeasure
    case emptyText
}

public enum DisasterEntry {
    public static let noteLimit = 120
    public static let textLimit = 80

    public static func site(
        id: UUID = UUID(),
        at: Date,
        kind: DisasterKind,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        horizontalAccuracyMeters: Double?,
        lengthMeters: Double?,
        widthMeters: Double?,
        heightMeters: Double?,
        note: String,
        photoFile: String?,
        author: String
    ) throws -> DisasterSite {
        guard placeOK(latitudeDegrees, longitudeDegrees) else { throw DisasterEntryError.missingPlace }
        let measure = DisasterMeasure(
            lengthMeters: try meters(lengthMeters),
            widthMeters: try meters(widthMeters),
            heightMeters: try meters(heightMeters)
        )
        let who = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !who.isEmpty else { throw DisasterEntryError.emptyText }
        return DisasterSite(
            id: id,
            at: at,
            kind: kind,
            latitudeDegrees: latitudeDegrees,
            longitudeDegrees: longitudeDegrees,
            horizontalAccuracyMeters: accuracy(horizontalAccuracyMeters),
            measure: measure,
            note: clip(note, limit: noteLimit),
            photoFile: photoFile,
            author: who
        )
    }

    public static func text(id: UUID = UUID(), at: Date, author: String, body: String) throws -> DisasterText {
        let who = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !who.isEmpty, !message.isEmpty, !message.contains("\n") else { throw DisasterEntryError.emptyText }
        return DisasterText(id: id, at: at, author: who, body: clip(message, limit: textLimit))
    }

    public static func passage(
        id: UUID = UUID(),
        at: Date,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        state: PassageState,
        author: String
    ) -> PassageSample? {
        let who = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard placeOK(latitudeDegrees, longitudeDegrees), !who.isEmpty else { return nil }
        return PassageSample(
            id: id,
            at: at,
            latitudeDegrees: latitudeDegrees,
            longitudeDegrees: longitudeDegrees,
            state: state,
            author: who
        )
    }

    public static func position(
        deviceID: String,
        name: String,
        at: Date,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        horizontalAccuracyMeters: Double?
    ) -> DisasterPosition? {
        let id = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let who = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !who.isEmpty, placeOK(latitudeDegrees, longitudeDegrees) else { return nil }
        return DisasterPosition(
            deviceID: id,
            name: who,
            at: at,
            latitudeDegrees: latitudeDegrees,
            longitudeDegrees: longitudeDegrees,
            horizontalAccuracyMeters: accuracy(horizontalAccuracyMeters)
        )
    }

    private static func meters(_ value: Double?) throws -> Double? {
        guard let value else { return nil }
        guard value.isFinite, value >= 0, value <= 10_000 else { throw DisasterEntryError.badMeasure }
        return MachineReach.roundTenths(value)
    }

    private static func accuracy(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return MachineReach.roundTenths(value)
    }

    private static func placeOK(_ latitude: Double, _ longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180
    }

    private static func clip(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= limit { return trimmed }
        return String(trimmed.prefix(limit))
    }
}

/// 動いた跡は通れる。止まった地点は通れない。間隔が空いたら線を切る。
public enum PassageTrack {
    public static let stepMeters = 25.0
    public static let breakMeters = 150.0
    public static let breakSeconds: TimeInterval = 15 * 60

    public static func shouldSample(
        after previous: PassageSample?,
        latitude: Double,
        longitude: Double,
        now: Date,
        stepMeters: Double
    ) -> Bool {
        guard let previous else { return true }
        guard now >= previous.at else { return false }
        guard let distance = meters(previous, latitude: latitude, longitude: longitude) else { return false }
        return distance >= stepMeters
    }

    public static func segments(from samples: [PassageSample]) -> [PassageSegment] {
        let authors = Set(samples.map(\.author))
        var result: [PassageSegment] = []
        for author in authors.sorted() {
            let rows = samples.filter { $0.author == author }.sorted { $0.at < $1.at }
            var open: [PassagePoint] = []
            var openAt: Date?
            func flushOpen() {
                if !open.isEmpty {
                    result.append(PassageSegment(author: author, state: .open, points: open))
                    open = []
                    openAt = nil
                }
            }
            for sample in rows {
                let point = PassagePoint(latitudeDegrees: sample.latitudeDegrees, longitudeDegrees: sample.longitudeDegrees)
                if sample.state == .closed {
                    flushOpen()
                    result.append(PassageSegment(author: author, state: .closed, points: [point]))
                    continue
                }
                if let last = open.last, let openAt {
                    let gap = sample.at.timeIntervalSince(openAt)
                    let distance = meters(last, latitude: point.latitudeDegrees, longitude: point.longitudeDegrees) ?? .infinity
                    if gap > breakSeconds || distance > breakMeters {
                        flushOpen()
                    }
                }
                open.append(point)
                openAt = sample.at
            }
            flushOpen()
        }
        return result
    }

    private static func meters(_ sample: PassageSample, latitude: Double, longitude: Double) -> Double? {
        GRS80Geodesic.inverse(
            latitude1: sample.latitudeDegrees,
            longitude1: sample.longitudeDegrees,
            latitude2: latitude,
            longitude2: longitude
        )?.distanceMeters
    }

    private static func meters(_ point: PassagePoint, latitude: Double, longitude: Double) -> Double? {
        GRS80Geodesic.inverse(
            latitude1: point.latitudeDegrees,
            longitude1: point.longitudeDegrees,
            latitude2: latitude,
            longitude2: longitude
        )?.distanceMeters
    }
}

/// 電池を伸ばす。位置の間隔を広げ、画面は眠らせ、地図の追加保存は止める。
public enum BatterySaver {
    public static let activeShareSeconds: TimeInterval = 5
    public static let shareSeconds: TimeInterval = 30
    public static let activeRelaySeconds: TimeInterval = 2
    public static let relaySeconds: TimeInterval = 15
    public static let activePassageStepMeters = PassageTrack.stepMeters
    public static let passageStepMeters = 80.0
    public static let note = "位置の送信を30秒に延ばし、画面の常時点灯をやめ、地図の追加保存を止めます。"

    public static func shareInterval(enabled: Bool) -> TimeInterval {
        enabled ? shareSeconds : activeShareSeconds
    }

    public static func relayInterval(enabled: Bool) -> TimeInterval {
        enabled ? relaySeconds : activeRelaySeconds
    }

    public static func passageStep(enabled: Bool) -> Double {
        enabled ? passageStepMeters : activePassageStepMeters
    }
}

public enum BucketKind: String, Codable, Sendable {
    case position
    case sos
    case text
    case site
    case passage
    case radio
    case beacon

    /// 小さいほど先に送る。SOS が最優先。
    public var relayRank: Int {
        switch self {
        case .sos: return 0
        case .radio: return 1
        case .text: return 2
        case .beacon: return 3
        case .position: return 4
        case .site: return 5
        case .passage: return 6
        }
    }
}

public enum BucketDrop: String, Equatable, Sendable {
    case otherProject
    case expired
    case seen
    case loop
    case empty
    case tooBig
}

public enum BucketDecision: Equatable, Sendable {
    case forward(BucketEnvelope)
    case keep(BucketEnvelope)
    case drop(BucketDrop)
}

/// 近くの端末を経由する一通。存在時間は作った時刻からで、中継では延ばさない。
public struct BucketEnvelope: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var projectID: String
    public var kind: BucketKind
    public var createdAt: Date
    public var ttlSeconds: TimeInterval
    public var hopLimit: Int
    public var hops: [String]
    public var position: DisasterPosition?
    public var sos: SOSPacket?
    public var text: DisasterText?
    public var site: DisasterSite?
    public var passage: PassageSample?
    public var radio: RadioPacket?
    public var beacon: RepeaterBeacon?

    public init(
        id: UUID,
        projectID: String,
        kind: BucketKind,
        createdAt: Date,
        ttlSeconds: TimeInterval,
        hopLimit: Int,
        hops: [String],
        position: DisasterPosition? = nil,
        sos: SOSPacket? = nil,
        text: DisasterText? = nil,
        site: DisasterSite? = nil,
        passage: PassageSample? = nil,
        radio: RadioPacket? = nil,
        beacon: RepeaterBeacon? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.kind = kind
        self.createdAt = createdAt
        self.ttlSeconds = ttlSeconds
        self.hopLimit = hopLimit
        self.hops = hops
        self.position = position
        self.sos = sos
        self.text = text
        self.site = site
        self.passage = passage
        self.radio = radio
        self.beacon = beacon
    }
}

public enum BucketRelay {
    public static let hopLimit = 6
    public static let audioCap = 4096

    public static func ttl(for kind: BucketKind) -> TimeInterval {
        switch kind {
        case .position: return 10 * 60
        case .sos: return 60 * 60
        case .text: return 6 * 60 * 60
        case .site, .passage: return 24 * 60 * 60
        case .radio: return 2 * 60
        case .beacon: return 2 * 60
        }
    }

    public static func envelope(
        id: UUID = UUID(),
        projectID: String,
        kind: BucketKind,
        deviceID: String,
        at: Date,
        ttlSeconds: TimeInterval? = nil,
        hopLimit: Int = BucketRelay.hopLimit,
        position: DisasterPosition? = nil,
        sos: SOSPacket? = nil,
        text: DisasterText? = nil,
        site: DisasterSite? = nil,
        passage: PassageSample? = nil,
        radio: RadioPacket? = nil,
        beacon: RepeaterBeacon? = nil
    ) -> BucketEnvelope {
        BucketEnvelope(
            id: id,
            projectID: projectID,
            kind: kind,
            createdAt: at,
            ttlSeconds: ttlSeconds ?? ttl(for: kind),
            hopLimit: max(1, hopLimit),
            hops: [deviceID],
            position: position,
            sos: sos,
            text: text,
            site: site,
            passage: passage,
            radio: radio,
            beacon: beacon
        )
    }
}

/// 見た封筒は覚え、ホップ上限まで次の端末へ渡す。
public struct BucketDesk: Sendable {
    public var selfID: String
    public static let seenCap = 400
    public static let heldCap = 80
    private var seen: [UUID] = []
    private var held: [BucketEnvelope] = []

    public init(selfID: String) {
        self.selfID = selfID
    }

    public var heldCount: Int { held.count }

    public mutating func originate(_ envelope: BucketEnvelope, now: Date) -> BucketEnvelope? {
        guard !selfID.isEmpty, envelope.hops == [selfID], envelope.carriesPayload else { return nil }
        if seen.contains(envelope.id) { return nil }
        remember(envelope.id)
        hold(envelope, now: now)
        return envelope
    }

    public mutating func receive(_ envelope: BucketEnvelope, now: Date, projectID: String) -> BucketDecision {
        guard !selfID.isEmpty else { return .drop(.empty) }
        guard envelope.projectID == projectID else { return .drop(.otherProject) }
        guard envelope.ttlSeconds > 0, now.timeIntervalSince(envelope.createdAt) < envelope.ttlSeconds else {
            return .drop(.expired)
        }
        guard envelope.carriesPayload else { return .drop(.empty) }
        if envelope.hops.contains(selfID) { return .drop(.loop) }
        if seen.contains(envelope.id) { return .drop(.seen) }
        if let audio = envelope.radio?.audio, audio.count > BucketRelay.audioCap {
            remember(envelope.id)
            return .drop(.tooBig)
        }
        remember(envelope.id)
        if envelope.hops.count >= envelope.hopLimit {
            return .keep(envelope)
        }
        var next = envelope
        next.hops.append(selfID)
        if next.hops.count >= next.hopLimit {
            return .keep(next)
        }
        hold(next, now: now)
        return .forward(next)
    }

    public mutating func forwardable(now: Date) -> [BucketEnvelope] {
        prune(now: now)
        return held
            .filter { $0.hops.count < $0.hopLimit && now.timeIntervalSince($0.createdAt) < $0.ttlSeconds }
            .sorted { lhs, rhs in
                if lhs.kind.relayRank != rhs.kind.relayRank { return lhs.kind.relayRank < rhs.kind.relayRank }
                return lhs.createdAt < rhs.createdAt
            }
    }

    private mutating func remember(_ id: UUID) {
        seen.removeAll { $0 == id }
        seen.append(id)
        if seen.count > Self.seenCap {
            seen.removeFirst(seen.count - Self.seenCap)
        }
    }

    private mutating func hold(_ envelope: BucketEnvelope, now: Date) {
        held.removeAll { $0.id == envelope.id }
        held.append(envelope)
        prune(now: now)
        while held.count > Self.heldCap {
            guard let index = held.indices.min(by: { Self.dropFirst(held[$0], held[$1]) }) else { break }
            held.remove(at: index)
        }
    }

    /// 先に捨てる方を true。優先度が低いもの、同じなら古いもの。
    private static func dropFirst(_ lhs: BucketEnvelope, _ rhs: BucketEnvelope) -> Bool {
        if lhs.kind.relayRank != rhs.kind.relayRank { return lhs.kind.relayRank > rhs.kind.relayRank }
        return lhs.createdAt < rhs.createdAt
    }

    private mutating func prune(now: Date) {
        held.removeAll { now.timeIntervalSince($0.createdAt) >= $0.ttlSeconds }
    }
}

extension BucketEnvelope {
    var carriesPayload: Bool {
        switch kind {
        case .position:
            return position != nil
        case .sos:
            return sos?.beacon != nil || sos?.reply != nil
        case .text:
            let body = text?.body.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !body.isEmpty
        case .site:
            return site != nil
        case .passage:
            return passage != nil
        case .radio:
            return radio != nil
        case .beacon:
            return beacon != nil
        }
    }
}

public struct DisasterPeers: Sendable {
    public private(set) var latest: [DisasterPosition] = []

    public init() {}

    @discardableResult
    public mutating func note(_ position: DisasterPosition) -> Bool {
        if let index = latest.firstIndex(where: { $0.deviceID == position.deviceID }) {
            guard position.at >= latest[index].at else { return false }
            latest[index] = position
            return true
        }
        latest.append(position)
        return true
    }
}

public struct DisasterBatch: Codable, Equatable, Sendable {
    public var projectID: String
    public var sites: [DisasterSite]
    public var passages: [PassageSample]
    public var texts: [DisasterText]
    public var positions: [DisasterPosition]

    public init(
        projectID: String,
        sites: [DisasterSite] = [],
        passages: [PassageSample] = [],
        texts: [DisasterText] = [],
        positions: [DisasterPosition] = []
    ) {
        self.projectID = projectID
        self.sites = sites
        self.passages = passages
        self.texts = texts
        self.positions = positions
    }

    public var isEmpty: Bool {
        sites.isEmpty && passages.isEmpty && texts.isEmpty && positions.isEmpty
    }

    public var count: Int {
        sites.count + passages.count + texts.count + positions.count
    }
}

/// 通信が戻った印。衛星回線も、P510 まで届く経路なら同じ印にする。
public struct DisasterUplink: Equatable, Sendable {
    public private(set) var online: Bool

    public init(online: Bool = false) {
        self.online = online
    }

    /// オフからオンに変わったときだけ true。
    public mutating func note(online next: Bool) -> Bool {
        let rose = next && !online
        online = next
        return rose
    }
}

public final class DisasterRelay: @unchecked Sendable {
    public var isReachable: Bool
    public private(set) var sent: [DisasterBatch] = []

    public init(reachable: Bool) {
        self.isReachable = reachable
    }

    @discardableResult
    public func submit(_ batch: DisasterBatch) -> RadioDelivery {
        if batch.isEmpty { return .sent }
        guard isReachable else { return .unreachable }
        sent.append(batch)
        return .sent
    }
}

public struct DisasterSettings: Codable, Equatable, Sendable {
    public var mode: Bool
    public var batterySaver: Bool

    public init(mode: Bool = false, batterySaver: Bool = false) {
        self.mode = mode
        self.batterySaver = batterySaver
    }
}

struct DisasterSyncMark: Codable, Equatable {
    var siteIDs: [UUID]
    var passageIDs: [UUID]
    var textIDs: [UUID]
    var positionAt: [String: Date]

    static let empty = DisasterSyncMark(siteIDs: [], passageIDs: [], textIDs: [], positionAt: [:])
}

public enum DisasterReport {
    public static let situationTitle = "被災状況報告"
    public static let situationNote = "このPDFは現場の控えです。官庁の様式は作らず、提出もしません。"
    public static let ledgerTitle = "災害査定用の写真帳簿"
    public static let ledgerNote = "この帳簿は災害査定へ転記するための写真と位置の控えです。査定の様式そのものは作らず、提出もしません。"
    public static let csvHeader = "日時,種類,緯度,経度,水平精度m,延長m,幅m,高さm,記録者,メモ,写真"

    public static func situationLines(_ sites: [DisasterSite], generatedAt: Date) -> [String] {
        var lines = [
            situationTitle,
            situationNote,
            "生成時刻 \(clock(generatedAt))",
            "件数 \(sites.count)"
        ]
        if sites.isEmpty {
            lines.append("被災箇所はまだありません。")
            return lines
        }
        for site in sites.sorted(by: { $0.at < $1.at }) {
            lines.append(contentsOf: block(site))
        }
        return lines
    }

    public static func ledgerLines(_ sites: [DisasterSite], generatedAt: Date) -> [String] {
        var lines = [
            ledgerTitle,
            ledgerNote,
            "生成時刻 \(clock(generatedAt))",
            "写真のファイルは、このPDFと同じフォルダに置きます。"
        ]
        let rows = sites.sorted(by: { $0.at < $1.at })
        if rows.isEmpty {
            lines.append("写真はまだありません。")
            return lines
        }
        for (index, site) in rows.enumerated() {
            lines.append("\(index + 1). \(site.kind.label) \(clock(site.at))")
            lines.append(contentsOf: block(site).dropFirst())
        }
        return lines
    }

    public static func situationPDF(_ sites: [DisasterSite], generatedAt: Date) -> Data {
        IncidentPDF.pages(lines: situationLines(sites, generatedAt: generatedAt))
    }

    public static func ledgerPDF(_ sites: [DisasterSite], generatedAt: Date) -> Data {
        IncidentPDF.pages(lines: ledgerLines(sites, generatedAt: generatedAt))
    }

    public static func csv(_ sites: [DisasterSite]) -> String {
        var lines = [csvHeader]
        for site in sites.sorted(by: { $0.at < $1.at }) {
            let fields = [
                clock(site.at),
                site.kind.label,
                coordinate(site.latitudeDegrees),
                coordinate(site.longitudeDegrees),
                site.horizontalAccuracyMeters.map(tenths) ?? "",
                site.measure.lengthMeters.map(tenths) ?? "",
                site.measure.widthMeters.map(tenths) ?? "",
                site.measure.heightMeters.map(tenths) ?? "",
                site.author,
                site.note,
                site.photoFile ?? ""
            ]
            lines.append(fields.map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func block(_ site: DisasterSite) -> [String] {
        [
            "\(clock(site.at)) \(site.kind.label) \(site.author)",
            "緯度 \(coordinate(site.latitudeDegrees))",
            "経度 \(coordinate(site.longitudeDegrees))",
            "延長 \(meters(site.measure.lengthMeters))",
            "幅 \(meters(site.measure.widthMeters))",
            "高さ \(meters(site.measure.heightMeters))",
            "メモ \(site.note.isEmpty ? "なし" : site.note)",
            "写真 \(site.photoFile ?? "なし")"
        ]
    }

    private static func meters(_ value: Double?) -> String {
        value.map { "\(tenths($0))m" } ?? "未記録"
    }

    private static func tenths(_ meters: Double) -> String {
        String(format: "%.1f", MachineReach.roundTenths(meters))
    }

    private static func coordinate(_ degrees: Double) -> String {
        String(format: "%.8f", degrees)
    }

    private static func csvField(_ text: String) -> String {
        if text.contains(",") || text.contains("\"") || text.contains("\n") {
            return "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return text
    }

    static func clock(_ date: Date) -> String {
        stamp.string(from: date)
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

public enum DisasterBook {
    public static let folderName = "災害"
    public static let siteName = "箇所.jsonl"
    public static let passageName = "通行.jsonl"
    public static let textName = "文.jsonl"
    public static let positionName = "位置.json"
    public static let syncName = "同期.json"
    public static let settingsName = "設定.json"
    public static let photoFolder = "写真"
    public static let exportFolder = "出す"
    public static let situationPDFName = "被災状況.pdf"
    public static let situationCSVName = "被災状況.csv"
    public static let ledgerFolder = "写真帳簿"
    public static let ledgerPDFName = "写真帳簿.pdf"

    public static func loadSettings(projectName: String, at root: URL) -> DisasterSettings {
        guard let directory = try? folder(projectName: projectName, at: root, create: false) else {
            return DisasterSettings()
        }
        return read(DisasterSettings.self, from: directory.appendingPathComponent(settingsName)) ?? DisasterSettings()
    }

    public static func saveSettings(_ settings: DisasterSettings, projectName: String, at root: URL) throws {
        let directory = try folder(projectName: projectName, at: root, create: true)
        try write(settings, to: directory.appendingPathComponent(settingsName))
    }

    @discardableResult
    public static func appendSite(_ site: DisasterSite, projectName: String, at root: URL) throws -> Bool {
        try append(site, name: siteName, projectName: projectName, at: root)
    }

    @discardableResult
    public static func appendPassage(_ sample: PassageSample, projectName: String, at root: URL) throws -> Bool {
        try append(sample, name: passageName, projectName: projectName, at: root)
    }

    @discardableResult
    public static func appendText(_ text: DisasterText, projectName: String, at root: URL) throws -> Bool {
        try append(text, name: textName, projectName: projectName, at: root)
    }

    public static func savePhoto(_ data: Data, id: UUID, projectName: String, at root: URL) throws -> String? {
        guard !data.isEmpty else { return nil }
        let directory = try folder(projectName: projectName, at: root, create: true)
            .appendingPathComponent(photoFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "\(id.uuidString).jpg"
        let url = directory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            try data.write(to: url, options: .atomic)
        }
        return name
    }

    public static func loadSites(projectName: String, at root: URL) -> [DisasterSite] {
        loadLines(DisasterSite.self, name: siteName, projectName: projectName, at: root)
    }

    public static func loadPassages(projectName: String, at root: URL) -> [PassageSample] {
        loadLines(PassageSample.self, name: passageName, projectName: projectName, at: root)
    }

    public static func loadTexts(projectName: String, at root: URL) -> [DisasterText] {
        loadLines(DisasterText.self, name: textName, projectName: projectName, at: root)
    }

    public static func savePositions(_ positions: [DisasterPosition], projectName: String, at root: URL) throws {
        let directory = try folder(projectName: projectName, at: root, create: true)
        try write(positions, to: directory.appendingPathComponent(positionName))
    }

    public static func loadPositions(projectName: String, at root: URL) -> [DisasterPosition] {
        guard let directory = try? folder(projectName: projectName, at: root, create: false) else { return [] }
        return read([DisasterPosition].self, from: directory.appendingPathComponent(positionName)) ?? []
    }

    public static func pending(projectID: String, projectName: String, at root: URL) -> DisasterBatch {
        let mark = loadMark(projectName: projectName, at: root)
        let sites = loadSites(projectName: projectName, at: root).filter { !mark.siteIDs.contains($0.id) }
        let passages = loadPassages(projectName: projectName, at: root).filter { !mark.passageIDs.contains($0.id) }
        let texts = loadTexts(projectName: projectName, at: root).filter { !mark.textIDs.contains($0.id) }
        let positions = loadPositions(projectName: projectName, at: root).filter { position in
            guard let sent = mark.positionAt[position.deviceID] else { return true }
            return position.at > sent
        }
        return DisasterBatch(projectID: projectID, sites: sites, passages: passages, texts: texts, positions: positions)
    }

    public static func markSynced(_ batch: DisasterBatch, projectName: String, at root: URL) throws {
        var mark = loadMark(projectName: projectName, at: root)
        for site in batch.sites where !mark.siteIDs.contains(site.id) {
            mark.siteIDs.append(site.id)
        }
        for sample in batch.passages where !mark.passageIDs.contains(sample.id) {
            mark.passageIDs.append(sample.id)
        }
        for text in batch.texts where !mark.textIDs.contains(text.id) {
            mark.textIDs.append(text.id)
        }
        for position in batch.positions {
            if let sent = mark.positionAt[position.deviceID], sent >= position.at { continue }
            mark.positionAt[position.deviceID] = position.at
        }
        let directory = try folder(projectName: projectName, at: root, create: true)
        try write(mark, to: directory.appendingPathComponent(syncName))
    }

    public struct DisasterExport: Equatable, Sendable {
        public var pdf: String
        public var csv: String
        public var ledger: String
    }

    public static func export(projectName: String, at root: URL, generatedAt: Date) throws -> DisasterExport {
        let sites = loadSites(projectName: projectName, at: root)
        let directory = try folder(projectName: projectName, at: root, create: true)
            .appendingPathComponent(exportFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pdfURL = directory.appendingPathComponent(situationPDFName)
        let csvURL = directory.appendingPathComponent(situationCSVName)
        try DisasterReport.situationPDF(sites, generatedAt: generatedAt).write(to: pdfURL, options: .atomic)
        try Data(DisasterReport.csv(sites).utf8).write(to: csvURL, options: .atomic)
        let ledger = directory.appendingPathComponent(ledgerFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: ledger, withIntermediateDirectories: true)
        try DisasterReport.ledgerPDF(sites, generatedAt: generatedAt).write(to: ledger.appendingPathComponent(ledgerPDFName), options: .atomic)
        let photos = directory.deletingLastPathComponent().appendingPathComponent(photoFolder, isDirectory: true)
        for site in sites {
            guard let name = site.photoFile else { continue }
            let source = photos.appendingPathComponent(name)
            let target = ledger.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: source, to: target)
        }
        return DisasterExport(pdf: situationPDFName, csv: situationCSVName, ledger: ledgerPDFName)
    }

    @discardableResult
    private static func append<T: Codable & Identifiable>(_ value: T, name: String, projectName: String, at root: URL) throws -> Bool where T.ID == UUID {
        let directory = try folder(projectName: projectName, at: root, create: true)
        let url = directory.appendingPathComponent(name)
        let existing = loadLines(T.self, name: name, projectName: projectName, at: root)
        if existing.contains(where: { $0.id == value.id }) { return false }
        var line = try DisasterCoder.encode(value)
        line.append(0x0A)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url)
        }
        return true
    }

    private static func loadLines<T: Decodable>(_ type: T.Type, name: String, projectName: String, at root: URL) -> [T] {
        guard let directory = try? folder(projectName: projectName, at: root, create: false) else { return [] }
        let url = directory.appendingPathComponent(name)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? DisasterCoder.decoder.decode(T.self, from: data)
        }
    }

    private static func loadMark(projectName: String, at root: URL) -> DisasterSyncMark {
        guard let directory = try? folder(projectName: projectName, at: root, create: false) else { return .empty }
        return read(DisasterSyncMark.self, from: directory.appendingPathComponent(syncName)) ?? .empty
    }

    private static func folder(projectName: String, at root: URL, create: Bool) throws -> URL {
        let project = try ProjectStore.projectDirectory(projectName, at: root)
        let directory = project.appendingPathComponent("記録簿", isDirectory: true).appendingPathComponent(folderName, isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = DisasterCoder.encoder
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? DisasterCoder.decoder.decode(T.self, from: data)
    }
}

enum DisasterCoder {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }
}
