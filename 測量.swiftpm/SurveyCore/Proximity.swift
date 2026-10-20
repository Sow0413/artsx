import Foundation

/// 画面に常に出す。接近の表示は安全確認の代わりではない。
public enum SafetyNotice {
    public static let text = "補助。安全確認の代わりではない"
}

public enum CrewRole: String, Codable, Sendable, Equatable, CaseIterable {
    case machine
    case worker

    public var label: String {
        switch self {
        case .machine: return "重機"
        case .worker: return "作業員"
        }
    }
}

public enum ProximityLevel: String, Codable, Sendable, Equatable {
    case clear
    case caution
    case alarm

    public var rank: Int {
        switch self {
        case .clear: return 0
        case .caution: return 1
        case .alarm: return 2
        }
    }
}

/// UWB で測った、ある相手までの距離。新しいものだけを GNSS より優先する。
public struct CrewRange: Codable, Equatable, Sendable {
    public var peerID: String
    public var distanceMeters: Double
    public var measuredAt: Date

    public init(peerID: String, distanceMeters: Double, measuredAt: Date) {
        self.peerID = peerID
        self.distanceMeters = distanceMeters
        self.measuredAt = measuredAt
    }
}

public enum CrewRangeKind: String, Codable, Sendable, Equatable {
    case gnss
    case uwb
}

public struct CrewFix: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var role: CrewRole
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var horizontalAccuracyMeters: Double
    public var workRadiusMeters: Double?
    public var sentAt: Date
    public var ranges: [CrewRange]

    public init(
        id: String,
        name: String,
        role: CrewRole,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        horizontalAccuracyMeters: Double,
        workRadiusMeters: Double?,
        sentAt: Date,
        ranges: [CrewRange] = []
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.workRadiusMeters = workRadiusMeters
        self.sentAt = sentAt
        self.ranges = ranges
    }
}

public struct CrewPacket: Codable, Equatable, Sendable {
    public var projectID: String
    public var fix: CrewFix
    /// Nearby Interaction の発見トークン。無い端末は nil。
    public var uwbToken: Data?

    public init(projectID: String, fix: CrewFix, uwbToken: Data? = nil) {
        self.projectID = projectID
        self.fix = fix
        self.uwbToken = uwbToken
    }
}

public struct ProximityLimits: Codable, Equatable, Sendable {
    public static let defaultCautionMeters = 50.0
    public static let defaultMarginMeters = 5.0

    public var cautionMeters: Double
    public var marginMeters: Double

    public init(cautionMeters: Double, marginMeters: Double) {
        self.cautionMeters = cautionMeters
        self.marginMeters = marginMeters
    }

    public static let standard = ProximityLimits(cautionMeters: defaultCautionMeters, marginMeters: defaultMarginMeters)

    /// 0 以下や数値でない設定は既定に戻す。余裕 0 は、半径そのもので警報にする。
    public static func resolved(caution: Double?, margin: Double?) -> ProximityLimits {
        let cautionMeters = caution.flatMap { $0.isFinite && $0 >= 1 ? $0 : nil } ?? defaultCautionMeters
        let marginMeters = margin.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? defaultMarginMeters
        return ProximityLimits(cautionMeters: cautionMeters, marginMeters: marginMeters)
    }
}

public struct ProximityHit: Equatable, Sendable {
    public var other: CrewFix
    public var distanceMeters: Double
    public var level: ProximityLevel
    public var alarmRadiusMeters: Double?
    public var rangeKind: CrewRangeKind

    public init(
        other: CrewFix,
        distanceMeters: Double,
        level: ProximityLevel,
        alarmRadiusMeters: Double?,
        rangeKind: CrewRangeKind
    ) {
        self.other = other
        self.distanceMeters = distanceMeters
        self.level = level
        self.alarmRadiusMeters = alarmRadiusMeters
        self.rangeKind = rangeKind
    }
}

public struct ProximityEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var projectID: String
    public var level: ProximityLevel
    public var startedAt: Date
    public var endedAt: Date?
    public var selfID: String
    public var selfRole: CrewRole
    public var otherID: String
    public var otherName: String
    public var otherRole: CrewRole
    public var enteredMeters: Double
    public var closestMeters: Double
    public var alarmRadiusMeters: Double?
    public var rangeKind: CrewRangeKind

    public init(
        id: UUID = UUID(),
        projectID: String,
        level: ProximityLevel,
        startedAt: Date,
        endedAt: Date?,
        selfID: String,
        selfRole: CrewRole,
        otherID: String,
        otherName: String,
        otherRole: CrewRole,
        enteredMeters: Double,
        closestMeters: Double,
        alarmRadiusMeters: Double?,
        rangeKind: CrewRangeKind
    ) {
        self.id = id
        self.projectID = projectID
        self.level = level
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.selfID = selfID
        self.selfRole = selfRole
        self.otherID = otherID
        self.otherName = otherName
        self.otherRole = otherRole
        self.enteredMeters = enteredMeters
        self.closestMeters = closestMeters
        self.alarmRadiusMeters = alarmRadiusMeters
        self.rangeKind = rangeKind
    }
}

public struct CrewMark: Equatable, Sendable {
    public var id: String
    public var name: String
    public var role: CrewRole
    public var eastMeters: Double
    public var northMeters: Double
    public var workRadiusMeters: Double?
    public var level: ProximityLevel

    public init(
        id: String,
        name: String,
        role: CrewRole,
        eastMeters: Double,
        northMeters: Double,
        workRadiusMeters: Double?,
        level: ProximityLevel
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.eastMeters = eastMeters
        self.northMeters = northMeters
        self.workRadiusMeters = workRadiusMeters
        self.level = level
    }
}

public protocol CrewTransport: AnyObject {
    var path: RadioPath { get }
    var isReachable: Bool { get }
    var onReceive: ((CrewPacket) -> Void)? { get set }
    func send(_ packet: CrewPacket) -> RadioDelivery
}

public final class CrewRelayStub: CrewTransport {
    public let path: RadioPath = .relay
    public var isReachable: Bool
    public var onReceive: ((CrewPacket) -> Void)?
    public private(set) var sent: [CrewPacket] = []

    public init(reachable: Bool) {
        self.isReachable = reachable
    }

    public func send(_ packet: CrewPacket) -> RadioDelivery {
        guard isReachable else { return .unreachable }
        sent.append(packet)
        return .sent
    }
}

public final class CrewMesh: CrewTransport {
    public let path: RadioPath = .nearby
    public var isReachable: Bool
    public var onReceive: ((CrewPacket) -> Void)?
    public var onSent: ((CrewPacket) -> Void)?
    public var peers: [CrewMesh] = []
    public private(set) var sent: [CrewPacket] = []

    public init(reachable: Bool = true) {
        self.isReachable = reachable
    }

    public func send(_ packet: CrewPacket) -> RadioDelivery {
        guard isReachable else { return .unreachable }
        sent.append(packet)
        onSent?(packet)
        for peer in peers where peer.isReachable {
            peer.onReceive?(packet)
        }
        return .sent
    }
}

public enum ProximityJudge {
    public static let uwbFreshSeconds: TimeInterval = 5

    /// 人が重機の作業半径＋余裕に入っているときの半径。重機どうし、人どうしでは nil。
    public static func alarmRadius(selfFix: CrewFix, other: CrewFix, marginMeters: Double) -> Double? {
        guard marginMeters.isFinite, marginMeters >= 0 else { return nil }
        let machine: CrewFix
        if selfFix.role == .machine, other.role == .worker {
            machine = selfFix
        } else if selfFix.role == .worker, other.role == .machine {
            machine = other
        } else {
            return nil
        }
        guard let radius = machine.workRadiusMeters, radius.isFinite, radius > 0 else { return nil }
        return radius + marginMeters
    }

    /// UWB の距離があればそれを使う。無ければ GNSS。
    public static func separation(_ lhs: CrewFix, _ rhs: CrewFix, now: Date) -> (meters: Double, kind: CrewRangeKind)? {
        let ranges = lhs.ranges.filter { $0.peerID == rhs.id } + rhs.ranges.filter { $0.peerID == lhs.id }
        let fresh = ranges.filter {
            $0.distanceMeters.isFinite && $0.distanceMeters >= 0 && now.timeIntervalSince($0.measuredAt) <= uwbFreshSeconds
        }
        if let nearest = fresh.map(\.distanceMeters).min() {
            return (nearest, .uwb)
        }
        guard let inverse = GRS80Geodesic.inverse(
            latitude1: lhs.latitudeDegrees,
            longitude1: lhs.longitudeDegrees,
            latitude2: rhs.latitudeDegrees,
            longitude2: rhs.longitudeDegrees
        ) else { return nil }
        return (inverse.distanceMeters, .gnss)
    }

    public static func hit(selfFix: CrewFix, other: CrewFix, limits: ProximityLimits, now: Date) -> ProximityHit? {
        guard let separation = separation(selfFix, other, now: now) else { return nil }
        let alarm = alarmRadius(selfFix: selfFix, other: other, marginMeters: limits.marginMeters)
        let level: ProximityLevel
        if let alarm, separation.meters <= alarm {
            level = .alarm
        } else if separation.meters <= limits.cautionMeters {
            level = .caution
        } else {
            level = .clear
        }
        return ProximityHit(
            other: other,
            distanceMeters: separation.meters,
            level: level,
            alarmRadiusMeters: alarm,
            rangeKind: separation.kind
        )
    }
}

public enum CrewPlot {
    public static func marks(origin: CrewFix, hits: [ProximityHit]) -> [CrewMark] {
        hits.compactMap { hit in
            guard let inverse = GRS80Geodesic.inverse(
                latitude1: origin.latitudeDegrees,
                longitude1: origin.longitudeDegrees,
                latitude2: hit.other.latitudeDegrees,
                longitude2: hit.other.longitudeDegrees
            ) else { return nil }
            var east = inverse.eastMeters
            var north = inverse.northMeters
            if hit.rangeKind == .uwb, inverse.distanceMeters > 0.5 {
                let scale = hit.distanceMeters / inverse.distanceMeters
                east *= scale
                north *= scale
            }
            return CrewMark(
                id: hit.other.id,
                name: hit.other.name,
                role: hit.other.role,
                eastMeters: east,
                northMeters: north,
                workRadiusMeters: hit.other.workRadiusMeters,
                level: hit.level
            )
        }
    }
}

/// 同じプロジェクトの位置。中継が届くときは中継、届かないときは近くの端末。
public final class CrewDesk {
    public static let staleSeconds: TimeInterval = 30

    public var deviceID: String
    public var name: String
    public var role: CrewRole
    public var limits: ProximityLimits
    public private(set) var projectID: String?
    public private(set) var others: [CrewFix] = []
    public private(set) var hits: [ProximityHit] = []
    public private(set) var events: [ProximityEvent] = []
    public private(set) var ranges: [CrewRange] = []
    public private(set) var selfFix: CrewFix?

    public let relay: any CrewTransport
    public let nearby: any CrewTransport
    private var open: [String: ProximityEvent] = [:]
    private var lastSelf: CrewFix?

    public init(
        deviceID: String,
        name: String,
        role: CrewRole,
        relay: any CrewTransport,
        nearby: any CrewTransport,
        limits: ProximityLimits = .standard
    ) {
        self.deviceID = deviceID
        self.name = name
        self.role = role
        self.relay = relay
        self.nearby = nearby
        self.limits = limits
        relay.onReceive = { [weak self] packet in self?.receive(packet, now: packet.fix.sentAt) }
        nearby.onReceive = { [weak self] packet in self?.receive(packet, now: packet.fix.sentAt) }
    }

    public var activePath: RadioPath? {
        if relay.isReachable { return .relay }
        if nearby.isReachable { return .nearby }
        return nil
    }

    public var worst: ProximityLevel {
        hits.map(\.level).max { $0.rank < $1.rank } ?? .clear
    }

    public func join(projectID: String) {
        if self.projectID != projectID {
            others = []
            hits = []
            closeAll(at: Date())
        }
        self.projectID = projectID
    }

    public func leave(at date: Date) {
        projectID = nil
        others = []
        hits = []
        closeAll(at: date)
    }

    @discardableResult
    public func publish(_ fix: CrewFix, uwbToken: Data? = nil) -> RadioPath? {
        var outgoing = fix
        outgoing.ranges = ranges
        lastSelf = outgoing
        selfFix = outgoing
        guard let projectID else { return nil }
        let packet = CrewPacket(projectID: projectID, fix: outgoing, uwbToken: uwbToken)
        switch activePath {
        case .relay:
            return relay.send(packet) == .sent ? .relay : nil
        case .nearby:
            return nearby.send(packet) == .sent ? .nearby : nil
        case nil:
            return nil
        }
    }

    public func receive(_ packet: CrewPacket, now: Date) {
        guard packet.projectID == projectID else { return }
        guard packet.fix.id != deviceID else { return }
        others.removeAll { $0.id == packet.fix.id }
        others.append(packet.fix)
        if let selfFix = lastSelf {
            evaluate(selfFix: selfFix, now: now)
        }
    }

    public func noteRange(peerID: String, distanceMeters: Double, at date: Date) {
        ranges.removeAll { $0.peerID == peerID }
        ranges.append(CrewRange(peerID: peerID, distanceMeters: distanceMeters, measuredAt: date))
        guard var selfFix = lastSelf else { return }
        selfFix.ranges = ranges
        lastSelf = selfFix
        evaluate(selfFix: selfFix, now: date)
    }

    public func evaluate(selfFix: CrewFix, now: Date) {
        var kept = selfFix
        kept.ranges = ranges
        lastSelf = kept
        self.selfFix = kept
        others.removeAll { now.timeIntervalSince($0.sentAt) > Self.staleSeconds }
        let present = Set(others.map(\.id))
        for identifier in open.keys where !present.contains(identifier) {
            if let event = open[identifier] {
                close(event, at: now)
            }
        }
        hits = others.compactMap { other in
            guard let hit = ProximityJudge.hit(selfFix: kept, other: other, limits: limits, now: now) else { return nil }
            track(hit, projectID: projectID ?? "", selfFix: kept, now: now)
            return hit
        }.sorted { $0.distanceMeters < $1.distanceMeters }
    }

    public func remember(_ events: [ProximityEvent]) {
        self.events = events.map { event in
            var copy = event
            if copy.endedAt == nil {
                copy.endedAt = copy.startedAt
            }
            return copy
        }
        open = [:]
    }

    private func track(_ hit: ProximityHit, projectID: String, selfFix: CrewFix, now: Date) {
        if hit.level == .clear {
            if let event = open[hit.other.id] {
                close(event, at: now)
            }
            return
        }
        if var event = open[hit.other.id], event.level == hit.level {
            event.closestMeters = min(event.closestMeters, hit.distanceMeters)
            event.otherName = hit.other.name
            event.rangeKind = hit.rangeKind
            open[hit.other.id] = event
            upsert(event)
            return
        }
        if let event = open[hit.other.id] {
            close(event, at: now)
        }
        let event = ProximityEvent(
            projectID: projectID,
            level: hit.level,
            startedAt: now,
            endedAt: nil,
            selfID: selfFix.id,
            selfRole: selfFix.role,
            otherID: hit.other.id,
            otherName: hit.other.name,
            otherRole: hit.other.role,
            enteredMeters: hit.distanceMeters,
            closestMeters: hit.distanceMeters,
            alarmRadiusMeters: hit.alarmRadiusMeters,
            rangeKind: hit.rangeKind
        )
        open[hit.other.id] = event
        upsert(event)
    }

    private func close(_ event: ProximityEvent, at date: Date) {
        var done = event
        done.endedAt = date
        open[event.otherID] = nil
        upsert(done)
    }

    private func closeAll(at date: Date) {
        for event in open.values {
            close(event, at: date)
        }
    }

    private func upsert(_ event: ProximityEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
        } else {
            events.append(event)
        }
    }
}

public struct CrewIdentity: Codable, Equatable, Sendable {
    public var deviceID: String
    public var name: String
    public var role: CrewRole

    public init(deviceID: String, name: String, role: CrewRole) {
        self.deviceID = deviceID
        self.name = name
        self.role = role
    }
}

public enum CrewIdentityStore {
    public static func load(projectName: String, at root: URL) -> CrewIdentity {
        guard let directory = try? ProjectStore.projectDirectory(projectName, at: root) else {
            return CrewIdentity(deviceID: UUID().uuidString, name: "この端末", role: .worker)
        }
        let url = directory.appendingPathComponent("この端末.json")
        if let data = try? Data(contentsOf: url),
           let identity = try? JSONDecoder().decode(CrewIdentity.self, from: data) {
            return identity
        }
        let created = CrewIdentity(deviceID: UUID().uuidString, name: "この端末", role: .worker)
        try? save(created, projectName: projectName, at: root)
        return created
    }

    public static func save(_ identity: CrewIdentity, projectName: String, at root: URL) throws {
        let directory = try ProjectStore.projectDirectory(projectName, at: root)
        let url = directory.appendingPathComponent("この端末.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(identity).write(to: url)
    }
}

public enum ProximityLog {
    public static func save(_ events: [ProximityEvent], projectName: String, at root: URL) throws {
        let directory = try ProjectStore.projectDirectory(projectName, at: root)
        let url = directory.appendingPathComponent("接近.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(events).write(to: url)
    }

    public static func load(projectName: String, at root: URL) -> [ProximityEvent] {
        guard let directory = try? ProjectStore.projectDirectory(projectName, at: root) else { return [] }
        let url = directory.appendingPathComponent("接近.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ProximityEvent].self, from: data)) ?? []
    }
}

/// Apple Watch へ渡す振動の合図。実機の送信は未確認。
public enum WatchCue: String, Codable, Sendable {
    case caution
    case alarm
    case clear

    public init(_ level: ProximityLevel) {
        switch level {
        case .clear: self = .clear
        case .caution: self = .caution
        case .alarm: self = .alarm
        }
    }
}
