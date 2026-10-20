import Foundation

/// 同じ現場への救助要請。119 の代わりではない。
public struct SOSBeacon: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var at: Date
    public var deviceID: String
    public var name: String
    public var latitudeDegrees: Double?
    public var longitudeDegrees: Double?
    public var channelID: String
    public var active: Bool

    public init(
        id: UUID,
        at: Date,
        deviceID: String,
        name: String,
        latitudeDegrees: Double?,
        longitudeDegrees: Double?,
        channelID: String,
        active: Bool
    ) {
        self.id = id
        self.at = at
        self.deviceID = deviceID
        self.name = name
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.channelID = channelID
        self.active = active
    }
}

public struct SOSReply: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var at: Date
    public var beaconID: UUID
    public var fromDeviceID: String
    public var fromName: String
    public var toDeviceID: String
    public var channelID: String
    public var text: String

    public init(
        id: UUID = UUID(),
        at: Date,
        beaconID: UUID,
        fromDeviceID: String,
        fromName: String,
        toDeviceID: String,
        channelID: String,
        text: String = SOSCall.coming
    ) {
        self.id = id
        self.at = at
        self.beaconID = beaconID
        self.fromDeviceID = fromDeviceID
        self.fromName = fromName
        self.toDeviceID = toDeviceID
        self.channelID = channelID
        self.text = text
    }
}

public struct SOSPacket: Codable, Equatable, Sendable {
    public var beacon: SOSBeacon?
    public var reply: SOSReply?

    public init(beacon: SOSBeacon? = nil, reply: SOSReply? = nil) {
        self.beacon = beacon
        self.reply = reply
    }
}

public enum SOSPath: String, Equatable, Sendable {
    case relay
    case nearby

    /// 圏内は P510。圏外は近くの端末どうし。
    public static func choose(relayReachable: Bool) -> SOSPath {
        relayReachable ? .relay : .nearby
    }
}

public struct SOSPointer: Equatable, Sendable {
    public var name: String
    public var text: String
    public var relativeDegrees: Double?
    public var distanceMeters: Double?
    public var known: Bool
    public var sector: String

    public init(
        name: String,
        text: String,
        relativeDegrees: Double?,
        distanceMeters: Double?,
        known: Bool,
        sector: String
    ) {
        self.name = name
        self.text = text
        self.relativeDegrees = relativeDegrees
        self.distanceMeters = distanceMeters
        self.known = known
        self.sector = sector
    }
}

public struct SOSHeard: Equatable, Sendable {
    public var pointer: SOSPointer
    public var speak: Bool
    public var beacon: SOSBeacon

    public init(pointer: SOSPointer, speak: Bool, beacon: SOSBeacon) {
        self.pointer = pointer
        self.speak = speak
        self.beacon = beacon
    }
}

public enum SOSCall {
    public static let disclaimer = "このアプリは119通報の代わりではない"
    public static let emergencyHint = "iPhoneの緊急SOSは、サイドボタンと音量ボタンを押し続けます。"
    public static let criticalAlertNote = "マナーモードでも鳴らすには、AppleのCritical Alertsが必要です。この版にはその資格がありません。"
    public static let coming = "向かう"
    public static let sendInterval: TimeInterval = 2
    public static let repeatSeconds: TimeInterval = 15
    public static let staleSeconds: TimeInterval = CrewDesk.staleSeconds

    public static func pointer(
        name: String,
        latitude: Double?,
        longitude: Double?,
        sentAt: Date,
        selfLatitude: Double?,
        selfLongitude: Double?,
        courseDegrees: Double?,
        headingDegrees: Double?,
        facing: TalkFacing,
        now: Date
    ) -> SOSPointer {
        let who = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let unknown = SOSPointer(
            name: who,
            text: who.isEmpty ? "方向不明 SOS" : "方向不明 \(who) SOS",
            relativeDegrees: nil,
            distanceMeters: nil,
            known: false,
            sector: ""
        )
        guard !who.isEmpty,
              now.timeIntervalSince(sentAt) <= staleSeconds,
              let latitude, let longitude,
              let selfLatitude, let selfLongitude,
              latitude.isFinite, longitude.isFinite, selfLatitude.isFinite, selfLongitude.isFinite,
              abs(latitude) <= 90, abs(selfLatitude) <= 90,
              let inverse = GRS80Geodesic.inverse(
                latitude1: selfLatitude,
                longitude1: selfLongitude,
                latitude2: latitude,
                longitude2: longitude
              ),
              let aim = aim(courseDegrees: courseDegrees, headingDegrees: headingDegrees, facing: facing)
        else { return unknown }
        let turn = ThreatBearing.relative(targetAzimuthDegrees: inverse.azimuthDegrees, facingDegrees: aim)
        let meters = max(0, Int(inverse.distanceMeters.rounded()))
        let sector = ThreatBearing.sector(relativeDegrees: turn)
        return SOSPointer(
            name: who,
            text: "\(sector)\(meters)m \(who) SOS",
            relativeDegrees: turn,
            distanceMeters: inverse.distanceMeters,
            known: true,
            sector: sector
        )
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

public struct SOSSession: Equatable, Sendable {
    public private(set) var active = false
    public private(set) var beaconID: UUID?
    public private(set) var lastSentAt: Date?
    public private(set) var incidentOpened = false
    public var sendInterval: TimeInterval

    public init(sendInterval: TimeInterval = SOSCall.sendInterval) {
        self.sendInterval = sendInterval
    }

    @discardableResult
    public mutating func begin(at date: Date) -> UUID? {
        guard !active else { return nil }
        let id = UUID()
        active = true
        beaconID = id
        lastSentAt = nil
        incidentOpened = false
        return id
    }

    public mutating func allowSend(at date: Date) -> Bool {
        guard active, beaconID != nil else { return false }
        if let lastSentAt, date.timeIntervalSince(lastSentAt) < sendInterval { return false }
        lastSentAt = date
        return true
    }

    public mutating func end() {
        active = false
        lastSentAt = nil
    }

    public mutating func markIncidentOpened() {
        incidentOpened = true
    }
}

/// 受信した SOS と、音声を連打しない間隔。
public struct SOSBoard: Sendable {
    public private(set) var latest: [String: SOSBeacon] = [:]
    private var marks: [String: (sector: String, at: Date)] = [:]
    public var repeatSeconds: TimeInterval

    public init(repeatSeconds: TimeInterval = SOSCall.repeatSeconds) {
        self.repeatSeconds = repeatSeconds
    }

    public mutating func hear(
        _ beacon: SOSBeacon,
        selfLatitude: Double?,
        selfLongitude: Double?,
        courseDegrees: Double?,
        headingDegrees: Double?,
        facing: TalkFacing,
        now: Date
    ) -> SOSHeard {
        if !beacon.active {
            latest[beacon.deviceID] = nil
            marks[beacon.deviceID] = nil
            let pointer = SOSCall.pointer(
                name: beacon.name,
                latitude: nil,
                longitude: nil,
                sentAt: beacon.at,
                selfLatitude: nil,
                selfLongitude: nil,
                courseDegrees: nil,
                headingDegrees: nil,
                facing: facing,
                now: now
            )
            return SOSHeard(pointer: pointer, speak: false, beacon: beacon)
        }
        latest[beacon.deviceID] = beacon
        let pointer = SOSCall.pointer(
            name: beacon.name,
            latitude: beacon.latitudeDegrees,
            longitude: beacon.longitudeDegrees,
            sentAt: beacon.at,
            selfLatitude: selfLatitude,
            selfLongitude: selfLongitude,
            courseDegrees: courseDegrees,
            headingDegrees: headingDegrees,
            facing: facing,
            now: now
        )
        let speak: Bool
        if let mark = marks[beacon.deviceID],
           mark.sector == pointer.sector,
           now.timeIntervalSince(mark.at) < repeatSeconds {
            speak = false
        } else {
            speak = true
            marks[beacon.deviceID] = (pointer.sector, now)
        }
        return SOSHeard(pointer: pointer, speak: speak, beacon: beacon)
    }
}

public struct SOSDesk: Sendable {
    public private(set) var session = SOSSession()
    public private(set) var board = SOSBoard()
    public private(set) var helpers: [String] = []
    private var forwarded: Set<String> = []

    public init() {}

    @discardableResult
    public mutating func begin(at date: Date) -> UUID? {
        helpers = []
        return session.begin(at: date)
    }

    public mutating func beacon(
        deviceID: String,
        name: String,
        channelID: String,
        latitude: Double?,
        longitude: Double?,
        at date: Date
    ) -> SOSBeacon? {
        guard session.allowSend(at: date), let id = session.beaconID else { return nil }
        return SOSBeacon(
            id: id,
            at: date,
            deviceID: deviceID,
            name: name,
            latitudeDegrees: latitude,
            longitudeDegrees: longitude,
            channelID: channelID,
            active: true
        )
    }

    public mutating func end(
        deviceID: String,
        name: String,
        channelID: String,
        latitude: Double?,
        longitude: Double?,
        at date: Date
    ) -> SOSBeacon? {
        guard let id = session.beaconID else { return nil }
        session.end()
        return SOSBeacon(
            id: id,
            at: date,
            deviceID: deviceID,
            name: name,
            latitudeDegrees: latitude,
            longitudeDegrees: longitude,
            channelID: channelID,
            active: false
        )
    }

    public mutating func markIncidentOpened() {
        session.markIncidentOpened()
    }

    public mutating func hear(
        _ beacon: SOSBeacon,
        selfLatitude: Double?,
        selfLongitude: Double?,
        courseDegrees: Double?,
        headingDegrees: Double?,
        facing: TalkFacing,
        now: Date
    ) -> SOSHeard {
        board.hear(
            beacon,
            selfLatitude: selfLatitude,
            selfLongitude: selfLongitude,
            courseDegrees: courseDegrees,
            headingDegrees: headingDegrees,
            facing: facing,
            now: now
        )
    }

    /// 圏外で受け取った SOS を、圏内の端末が P510 へ一度だけ渡す。
    public mutating func shouldForward(_ beacon: SOSBeacon, arrived: SOSPath, relayReachable: Bool) -> Bool {
        guard beacon.active, arrived == .nearby, relayReachable else { return false }
        let key = "\(beacon.id.uuidString)|\(beacon.at.timeIntervalSince1970)"
        return forwarded.insert(key).inserted
    }

    public func reply(
        to beacon: SOSBeacon,
        fromDeviceID: String,
        fromName: String,
        at date: Date
    ) -> SOSReply {
        SOSReply(
            at: date,
            beaconID: beacon.id,
            fromDeviceID: fromDeviceID,
            fromName: fromName,
            toDeviceID: beacon.deviceID,
            channelID: beacon.channelID
        )
    }

    /// 自分宛の「向かう」だけを足す。同じ人は一度だけ。
    @discardableResult
    public mutating func hearReply(_ reply: SOSReply, selfDeviceID: String, beaconID: UUID?) -> Bool {
        guard let beaconID, reply.beaconID == beaconID, reply.toDeviceID == selfDeviceID else { return false }
        guard reply.text == SOSCall.coming else { return false }
        let name = reply.fromName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !helpers.contains(name) else { return false }
        helpers.append(name)
        return true
    }

    public var helperLine: String {
        helpers.map { "\($0)が向かっています" }.joined(separator: " ")
    }
}

public final class SOSRelay: @unchecked Sendable {
    public var isReachable: Bool
    public private(set) var sent: [SOSPacket] = []
    public private(set) var pending: [SOSPacket] = []

    public init(reachable: Bool) {
        self.isReachable = reachable
    }

    @discardableResult
    public func submit(_ packet: SOSPacket) -> RadioDelivery {
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
