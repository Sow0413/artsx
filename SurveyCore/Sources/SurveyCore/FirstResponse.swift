import Foundation

/// 現場に置いてある応急の場所。地図の矢印に使う。
public enum AidPointKind: String, Codable, Sendable, Equatable, CaseIterable {
    case aed
    case stretcher
    case kit
    case hospital
    case entrance

    public var label: String {
        switch self {
        case .aed: return "AED"
        case .stretcher: return "担架"
        case .kit: return "救急箱"
        case .hospital: return "病院"
        case .entrance: return "進入口"
        }
    }
}

public struct AidPoint: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: AidPointKind
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var note: String

    public init(id: String = UUID().uuidString, kind: AidPointKind, latitudeDegrees: Double, longitudeDegrees: Double, note: String = "") {
        self.id = id
        self.kind = kind
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.note = note
    }
}

public struct AidContact: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var phone: String

    public init(id: String = UUID().uuidString, name: String, phone: String) {
        self.id = id
        self.name = name
        self.phone = phone
    }
}

/// プロジェクトに残す、初動のための現場情報。
public struct SiteAid: Codable, Equatable, Sendable {
    public var address: String
    public var landmark: String
    public var ambulanceEntrance: String
    public var hospitalName: String
    public var contacts: [AidContact]
    public var points: [AidPoint]

    public init(
        address: String = "",
        landmark: String = "",
        ambulanceEntrance: String = "",
        hospitalName: String = "",
        contacts: [AidContact] = [],
        points: [AidPoint] = []
    ) {
        self.address = address
        self.landmark = landmark
        self.ambulanceEntrance = ambulanceEntrance
        self.hospitalName = hospitalName
        self.contacts = contacts
        self.points = points
    }

    public static let empty = SiteAid()

    public var isBlank: Bool {
        address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && landmark.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && ambulanceEntrance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hospitalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && contacts.isEmpty
            && points.isEmpty
    }
}

/// 見るだけの三項目。手当の手順は持たない。
public enum AidCheck: String, Codable, Sendable, Equatable, CaseIterable {
    case conscious
    case breathing
    case bleeding

    public var title: String {
        switch self {
        case .conscious: return "意識"
        case .breathing: return "呼吸"
        case .bleeding: return "出血"
        }
    }

    public var prompt: String {
        switch self {
        case .conscious: return "意識：呼びかけに答えますか"
        case .breathing: return "呼吸：普段どおりの息をしていますか"
        case .bleeding: return "出血：止まらない出血がありますか"
        }
    }
}

public struct AidChecklist: Codable, Equatable, Sendable {
    public var conscious: Bool?
    public var breathing: Bool?
    public var bleeding: Bool?
    public var consciousAt: Date?
    public var breathingAt: Date?
    public var bleedingAt: Date?

    public init(
        conscious: Bool? = nil,
        breathing: Bool? = nil,
        bleeding: Bool? = nil,
        consciousAt: Date? = nil,
        breathingAt: Date? = nil,
        bleedingAt: Date? = nil
    ) {
        self.conscious = conscious
        self.breathing = breathing
        self.bleeding = bleeding
        self.consciousAt = consciousAt
        self.breathingAt = breathingAt
        self.bleedingAt = bleedingAt
    }

    public static let note = "見るだけのメモです。手当の手順ではありません。119の指示に従ってください。"

    public func answer(_ item: AidCheck) -> Bool? {
        switch item {
        case .conscious: return conscious
        case .breathing: return breathing
        case .bleeding: return bleeding
        }
    }

    public func answeredAt(_ item: AidCheck) -> Date? {
        switch item {
        case .conscious: return consciousAt
        case .breathing: return breathingAt
        case .bleeding: return bleedingAt
        }
    }
}

public struct AidStamp: Codable, Equatable, Sendable {
    public var at: Date
    public var text: String

    public init(at: Date, text: String) {
        self.at = at
        self.text = text
    }
}

public struct FirstPeer: Equatable, Sendable {
    public var id: String
    public var name: String
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var sentAt: Date
    public var courseDegrees: Double?
    public var headingDegrees: Double?

    public init(
        id: String,
        name: String,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        sentAt: Date,
        courseDegrees: Double? = nil,
        headingDegrees: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.sentAt = sentAt
        self.courseDegrees = courseDegrees
        self.headingDegrees = headingDegrees
    }
}

public struct FirstPick: Equatable, Sendable {
    public var id: String
    public var name: String
    public var distanceMeters: Double

    public init(id: String, name: String, distanceMeters: Double) {
        self.id = id
        self.name = name
        self.distanceMeters = distanceMeters
    }
}

public struct FirstEpisode: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var trigger: IncidentTrigger
    public var victimID: String
    public var victimName: String
    public var latitudeDegrees: Double?
    public var longitudeDegrees: Double?
    public var channelID: String
    public var openedAt: Date
    public var updatedAt: Date
    public var nearestID: String?
    public var nearestName: String?
    public var nearestMeters: Double?
    public var nearestAcceptedAt: Date?
    public var greeterID: String?
    public var greeterName: String?
    public var greeterAcceptedAt: Date?
    public var checklist: AidChecklist
    public var readoutAt: Date?
    public var callAt: Date?
    public var stamps: [AidStamp]
    public var active: Bool

    public init(
        id: UUID = UUID(),
        trigger: IncidentTrigger,
        victimID: String,
        victimName: String,
        latitudeDegrees: Double?,
        longitudeDegrees: Double?,
        channelID: String,
        openedAt: Date,
        updatedAt: Date,
        nearestID: String? = nil,
        nearestName: String? = nil,
        nearestMeters: Double? = nil,
        nearestAcceptedAt: Date? = nil,
        greeterID: String? = nil,
        greeterName: String? = nil,
        greeterAcceptedAt: Date? = nil,
        checklist: AidChecklist = AidChecklist(),
        readoutAt: Date? = nil,
        callAt: Date? = nil,
        stamps: [AidStamp] = [],
        active: Bool = true
    ) {
        self.id = id
        self.trigger = trigger
        self.victimID = victimID
        self.victimName = victimName
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.channelID = channelID
        self.openedAt = openedAt
        self.updatedAt = updatedAt
        self.nearestID = nearestID
        self.nearestName = nearestName
        self.nearestMeters = nearestMeters
        self.nearestAcceptedAt = nearestAcceptedAt
        self.greeterID = greeterID
        self.greeterName = greeterName
        self.greeterAcceptedAt = greeterAcceptedAt
        self.checklist = checklist
        self.readoutAt = readoutAt
        self.callAt = callAt
        self.stamps = stamps
        self.active = active
    }
}

public struct AidPacket: Codable, Equatable, Sendable {
    public var episode: FirstEpisode

    public init(episode: FirstEpisode) {
        self.episode = episode
    }
}

public struct FirstView: Equatable, Sendable {
    public var headline: String
    public var progress: String
    public var isNearest: Bool
    public var nearestOpen: Bool
    public var isGreeter: Bool
    public var greeterOpen: Bool
    public var checklist: AidChecklist

    public init(
        headline: String,
        progress: String,
        isNearest: Bool,
        nearestOpen: Bool,
        isGreeter: Bool,
        greeterOpen: Bool,
        checklist: AidChecklist
    ) {
        self.headline = headline
        self.progress = progress
        self.isNearest = isNearest
        self.nearestOpen = nearestOpen
        self.isGreeter = isGreeter
        self.greeterOpen = greeterOpen
        self.checklist = checklist
    }
}

public struct AidArrow: Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: AidPointKind
    public var text: String
    public var relativeDegrees: Double?
    public var distanceMeters: Double?
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var known: Bool

    public init(
        id: String,
        kind: AidPointKind,
        text: String,
        relativeDegrees: Double?,
        distanceMeters: Double?,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        known: Bool
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.relativeDegrees = relativeDegrees
        self.distanceMeters = distanceMeters
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.known = known
    }
}

public enum FirstPicker {
    /// 本人を除き、30秒以内の位置だけ。同じ距離は名前、その次は id。
    public static func nearest(
        victimID: String,
        latitude: Double,
        longitude: Double,
        peers: [FirstPeer],
        now: Date,
        staleSeconds: TimeInterval = CrewDesk.staleSeconds
    ) -> FirstPick? {
        guard latitude.isFinite, longitude.isFinite, abs(latitude) <= 90 else { return nil }
        let ranked = peers.compactMap { peer -> (FirstPeer, Double)? in
            let name = peer.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard peer.id != victimID, !name.isEmpty else { return nil }
            guard now.timeIntervalSince(peer.sentAt) <= staleSeconds else { return nil }
            guard peer.latitudeDegrees.isFinite, peer.longitudeDegrees.isFinite, abs(peer.latitudeDegrees) <= 90 else { return nil }
            guard let inverse = GRS80Geodesic.inverse(
                latitude1: latitude,
                longitude1: longitude,
                latitude2: peer.latitudeDegrees,
                longitude2: peer.longitudeDegrees
            ) else { return nil }
            return (peer, inverse.distanceMeters)
        }.sorted { left, right in
            if left.1 != right.1 { return left.1 < right.1 }
            let leftName = left.0.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let rightName = right.0.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if leftName != rightName { return leftName < rightName }
            return left.0.id < right.0.id
        }
        guard let first = ranked.first else { return nil }
        return FirstPick(id: first.0.id, name: first.0.name.trimmingCharacters(in: .whitespacesAndNewlines), distanceMeters: first.1)
    }
}

public enum FirstCall {
    public static let cardNote = "初動のメモです。119通報の代わりではありません。"
    public static let recordNote = "初動はメモです。119通報の代わりではありません。"

    public static func nearestLine(distanceMeters: Double?, relativeDegrees: Double?) -> String {
        guard let distanceMeters, distanceMeters.isFinite, let relativeDegrees, relativeDegrees.isFinite else {
            return "あなたが最寄り 方向不明"
        }
        let meters = max(0, Int(distanceMeters.rounded()))
        let sector = ThreatBearing.sector(relativeDegrees: relativeDegrees)
        return "あなたが最寄り \(sector)\(meters)m"
    }

    public static func progress(_ episode: FirstEpisode) -> String {
        var parts: [String] = []
        if let name = episode.nearestName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            parts.append(episode.nearestAcceptedAt == nil ? "\(name)が最寄りです" : "\(name)が担当です")
        } else {
            parts.append("最寄りはいません")
        }
        if let name = episode.greeterName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            parts.append(episode.greeterAcceptedAt == nil ? "\(name)が救急車の迎えです" : "\(name)が救急車を迎えます")
        }
        return parts.joined(separator: "。")
    }

    public static func view(
        episode: FirstEpisode,
        selfID: String,
        selfLatitude: Double?,
        selfLongitude: Double?,
        courseDegrees: Double?,
        headingDegrees: Double?,
        facing: TalkFacing
    ) -> FirstView {
        let shared = progress(episode)
        let isNearest = episode.nearestID == selfID
        let nearestOpen = isNearest && episode.nearestAcceptedAt == nil
        let isGreeter = episode.greeterID == selfID
        let greeterOpen = isGreeter && episode.greeterAcceptedAt == nil
        var headline = shared
        if nearestOpen {
            let aim = bearing(
                latitude: episode.latitudeDegrees,
                longitude: episode.longitudeDegrees,
                selfLatitude: selfLatitude,
                selfLongitude: selfLongitude,
                courseDegrees: courseDegrees,
                headingDegrees: headingDegrees,
                facing: facing
            )
            headline = nearestLine(distanceMeters: aim?.meters, relativeDegrees: aim?.relative)
        } else if isNearest {
            headline = "担当はあなたです"
        } else if greeterOpen {
            headline = "救急車を迎えてください"
        }
        return FirstView(
            headline: headline,
            progress: shared,
            isNearest: isNearest,
            nearestOpen: nearestOpen,
            isGreeter: isGreeter,
            greeterOpen: greeterOpen,
            checklist: episode.checklist
        )
    }

    public static func arrows(
        points: [AidPoint],
        selfLatitude: Double?,
        selfLongitude: Double?,
        courseDegrees: Double?,
        headingDegrees: Double?,
        facing: TalkFacing
    ) -> [AidArrow] {
        let order: [AidPointKind] = [.aed, .stretcher, .kit, .entrance, .hospital]
        return points.sorted { left, right in
            let leftRank = order.firstIndex(of: left.kind) ?? order.count
            let rightRank = order.firstIndex(of: right.kind) ?? order.count
            if leftRank != rightRank { return leftRank < rightRank }
            return left.id < right.id
        }.map { point in
            let aim = bearing(
                latitude: point.latitudeDegrees,
                longitude: point.longitudeDegrees,
                selfLatitude: selfLatitude,
                selfLongitude: selfLongitude,
                courseDegrees: courseDegrees,
                headingDegrees: headingDegrees,
                facing: facing
            )
            let text: String
            if let aim {
                let meters = max(0, Int(aim.meters.rounded()))
                let sector = ThreatBearing.sector(relativeDegrees: aim.relative)
                text = "\(sector)\(meters)m \(point.kind.label)"
            } else {
                text = "方向不明 \(point.kind.label)"
            }
            return AidArrow(
                id: point.id,
                kind: point.kind,
                text: text,
                relativeDegrees: aim?.relative,
                distanceMeters: aim?.meters,
                latitudeDegrees: point.latitudeDegrees,
                longitudeDegrees: point.longitudeDegrees,
                known: aim != nil
            )
        }
    }

    static func bearing(
        latitude: Double?,
        longitude: Double?,
        selfLatitude: Double?,
        selfLongitude: Double?,
        courseDegrees: Double?,
        headingDegrees: Double?,
        facing: TalkFacing
    ) -> (meters: Double, relative: Double)? {
        guard let latitude, let longitude, let selfLatitude, let selfLongitude,
              latitude.isFinite, longitude.isFinite, selfLatitude.isFinite, selfLongitude.isFinite,
              abs(latitude) <= 90, abs(selfLatitude) <= 90,
              let inverse = GRS80Geodesic.inverse(
                latitude1: selfLatitude,
                longitude1: selfLongitude,
                latitude2: latitude,
                longitude2: longitude
              ),
              let aim = aim(courseDegrees: courseDegrees, headingDegrees: headingDegrees, facing: facing)
        else { return nil }
        let turn = ThreatBearing.relative(targetAzimuthDegrees: inverse.azimuthDegrees, facingDegrees: aim)
        return (inverse.distanceMeters, turn)
    }

    private static func aim(courseDegrees: Double?, headingDegrees: Double?, facing: TalkFacing) -> Double? {
        switch facing {
        case .own:
            return ThreatBearing.facing(courseDegrees: courseDegrees, headingDegrees: headingDegrees)?.degrees
        case .machine:
            if let headingDegrees, headingDegrees.isFinite { return headingDegrees }
            if let courseDegrees, courseDegrees.isFinite { return courseDegrees }
            return nil
        }
    }
}

public enum Readout119 {
    public static let idleNote = "電話はここではかけません。発信は本人が行います。"

    public static func lines(site: SiteAid, latitude: Double?, longitude: Double?) -> [String] {
        var lines = [
            "現場の住所",
            filled(site.address),
            "緯度経度",
            coordinate(latitude, longitude),
            "目印",
            filled(site.landmark),
            "救急車の進入口",
            filled(site.ambulanceEntrance),
            "最寄り救急病院",
            filled(site.hospitalName)
        ]
        lines.append("緊急連絡先")
        let people = site.contacts.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !$0.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if people.isEmpty {
            lines.append("未登録")
        } else {
            for person in people {
                let name = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let phone = person.phone.trimmingCharacters(in: .whitespacesAndNewlines)
                lines.append([name, phone].filter { !$0.isEmpty }.joined(separator: " "))
            }
        }
        return lines
    }

    public static func speech(site: SiteAid, latitude: Double?, longitude: Double?) -> String {
        let rows = lines(site: site, latitude: latitude, longitude: longitude)
        var spoken: [String] = []
        var index = 0
        while index + 1 < rows.count {
            spoken.append("\(rows[index])、\(rows[index + 1])")
            index += 2
        }
        return spoken.joined(separator: "。")
    }

    private static func filled(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未登録" : trimmed
    }

    private static func coordinate(_ latitude: Double?, _ longitude: Double?) -> String {
        guard let latitude, let longitude, latitude.isFinite, longitude.isFinite else { return "未登録" }
        return String(format: "緯度 %.8f 経度 %.8f", latitude, longitude)
    }
}

public struct FirstDesk {
    public private(set) var episode: FirstEpisode?
    public private(set) var originated = false
    private var forwarded: Set<String> = []

    public init() {}

    public mutating func begin(
        trigger: IncidentTrigger,
        victimID: String,
        victimName: String,
        latitude: Double,
        longitude: Double,
        channelID: String,
        peers: [FirstPeer],
        at: Date
    ) -> FirstEpisode? {
        guard trigger == .sos || trigger == .fall else { return nil }
        guard episode?.active != true else { return nil }
        let name = victimName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !victimID.isEmpty, !name.isEmpty, !channelID.isEmpty else { return nil }
        let pick = FirstPicker.nearest(victimID: victimID, latitude: latitude, longitude: longitude, peers: peers, now: at)
        var stamps = [AidStamp(at: at, text: "初動開始")]
        if let pick {
            let meters = max(0, Int(pick.distanceMeters.rounded()))
            stamps.append(AidStamp(at: at, text: "最寄り \(pick.name) \(meters)m"))
        } else {
            stamps.append(AidStamp(at: at, text: "最寄りはいません"))
        }
        let opened = FirstEpisode(
            trigger: trigger,
            victimID: victimID,
            victimName: name,
            latitudeDegrees: latitude,
            longitudeDegrees: longitude,
            channelID: channelID,
            openedAt: at,
            updatedAt: at,
            nearestID: pick?.id,
            nearestName: pick?.name,
            nearestMeters: pick?.distanceMeters,
            stamps: stamps
        )
        episode = opened
        originated = true
        return opened
    }

    public mutating func acceptNearest(deviceID: String, at: Date) -> FirstEpisode? {
        guard var current = episode, current.active, current.nearestAcceptedAt == nil else { return nil }
        guard current.nearestID == deviceID, let name = current.nearestName, !name.isEmpty else { return nil }
        current.nearestAcceptedAt = at
        current.updatedAt = at
        current.stamps.append(AidStamp(at: at, text: "担当確定 \(name)"))
        episode = current
        return current
    }

    public mutating func assignGreeter(id: String, name: String, at: Date) -> FirstEpisode? {
        guard var current = episode, current.active, current.greeterAcceptedAt == nil else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id != current.victimID, !trimmed.isEmpty else { return nil }
        guard current.greeterID != id else { return nil }
        current.greeterID = id
        current.greeterName = trimmed
        current.updatedAt = at
        current.stamps.append(AidStamp(at: at, text: "迎え割り当て \(trimmed)"))
        episode = current
        return current
    }

    public mutating func acceptGreeter(deviceID: String, at: Date) -> FirstEpisode? {
        guard var current = episode, current.active, current.greeterAcceptedAt == nil else { return nil }
        guard current.greeterID == deviceID, let name = current.greeterName, !name.isEmpty else { return nil }
        current.greeterAcceptedAt = at
        current.updatedAt = at
        current.stamps.append(AidStamp(at: at, text: "迎え確定 \(name)"))
        episode = current
        return current
    }

    public mutating func setCheck(_ item: AidCheck, answer: Bool, at: Date) -> FirstEpisode? {
        guard var current = episode, current.active else { return nil }
        switch item {
        case .conscious:
            current.checklist.conscious = answer
            current.checklist.consciousAt = at
        case .breathing:
            current.checklist.breathing = answer
            current.checklist.breathingAt = at
        case .bleeding:
            current.checklist.bleeding = answer
            current.checklist.bleedingAt = at
        }
        current.updatedAt = at
        current.stamps.append(AidStamp(at: at, text: "\(item.title) \(answer ? "はい" : "いいえ")"))
        episode = current
        return current
    }

    public mutating func noteReadout(at: Date) -> FirstEpisode? {
        guard var current = episode, current.active, current.readoutAt == nil else { return nil }
        current.readoutAt = at
        current.updatedAt = at
        current.stamps.append(AidStamp(at: at, text: "119の読み上げ"))
        episode = current
        return current
    }

    public mutating func noteCall(at: Date) -> FirstEpisode? {
        guard var current = episode, current.active, current.callAt == nil else { return nil }
        current.callAt = at
        current.updatedAt = at
        current.stamps.append(AidStamp(at: at, text: "119の発信操作"))
        episode = current
        return current
    }

    public mutating func end(at: Date) -> FirstEpisode? {
        guard var current = episode, current.active else { return nil }
        current.active = false
        current.updatedAt = at
        current.stamps.append(AidStamp(at: at, text: "初動を閉じました"))
        episode = current
        originated = false
        return current
    }

    /// 新しい方だけを採用する。
    public mutating func hear(_ incoming: FirstEpisode) -> Bool {
        if let current = episode, incoming.updatedAt <= current.updatedAt { return false }
        let wasOrigin = originated && episode?.id == incoming.id
        episode = incoming
        originated = wasOrigin
        if !incoming.active { originated = false }
        return true
    }

    public mutating func shouldForward(_ incoming: FirstEpisode, arrived: SOSPath, relayReachable: Bool) -> Bool {
        guard incoming.active, arrived == .nearby, relayReachable else { return false }
        let key = "\(incoming.id.uuidString)|\(incoming.updatedAt.timeIntervalSince1970)"
        if forwarded.contains(key) { return false }
        forwarded.insert(key)
        return true
    }
}

public final class AidRelay: @unchecked Sendable {
    public var isReachable: Bool
    public private(set) var sent: [AidPacket] = []
    public private(set) var pending: [AidPacket] = []

    public init(reachable: Bool) {
        self.isReachable = reachable
    }

    @discardableResult
    public func submit(_ packet: AidPacket) -> RadioDelivery {
        guard isReachable else {
            pending.append(packet)
            return .unreachable
        }
        sent.append(packet)
        return .sent
    }

    public func flush() {
        guard isReachable else { return }
        sent.append(contentsOf: pending)
        pending.removeAll()
    }
}
