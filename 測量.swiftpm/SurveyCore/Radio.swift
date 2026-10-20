import Foundation

/// チャンネルはプロジェクト。同じ ID なら、どの端末でも同じ UUID になる。
public struct RadioChannel: Codable, Equatable, Sendable, Identifiable {
    public var projectID: String
    public var projectName: String
    public var uuid: UUID

    public var id: UUID { uuid }

    public init(projectID: String, projectName: String, uuid: UUID) {
        self.projectID = projectID
        self.projectName = projectName
        self.uuid = uuid
    }

    public static func project(id: String, name: String) -> RadioChannel {
        RadioChannel(projectID: id, projectName: name, uuid: RadioIdentity.uuid(for: id))
    }
}

public enum RadioIdentity {
    /// プロジェクト ID が UUID ならそれを使う。そうでなければ名前から決まる UUID にする。
    public static func uuid(for projectID: String) -> UUID {
        if let parsed = UUID(uuidString: projectID) {
            return parsed
        }
        var high: UInt64 = 0xcbf29ce484222325
        var low: UInt64 = 0x84222325cbf29ce4
        for byte in Data((projectID + "|survey-ptt").utf8) {
            high ^= UInt64(byte)
            high = high &* 0x100000001b3
            low ^= UInt64(byte)
            low = low &* 0xcbf29ce484222325
        }
        var bytes = bytes(of: high) + bytes(of: low)
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func bytes(of value: UInt64) -> [UInt8] {
        var copy = value.bigEndian
        return withUnsafeBytes(of: &copy) { Array($0) }
    }
}

/// 発話に添える測点。付けない発話では nil。
public struct RadioStationStamp: Codable, Equatable, Sendable {
    public var text: String
    public var latitudeDegrees: Double?
    public var longitudeDegrees: Double?

    public init(text: String, latitudeDegrees: Double?, longitudeDegrees: Double?) {
        self.text = text
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
    }
}

public enum RadioPath: String, Codable, Sendable {
    /// 現場の P510 に置く中継。今回はスタブ。
    case relay
    /// Wi-Fi か Bluetooth で、近くの端末どうし。
    case nearby
}

public enum RadioPhase: String, Codable, Sendable {
    case idle
    case listening
    case transmitting
}

public struct RadioPacket: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case begin
        case audio
        case end
    }

    public var kind: Kind
    public var utteranceID: UUID
    public var channel: RadioChannel
    public var speaker: String
    public var sentAt: Date
    public var station: RadioStationStamp?
    public var audio: Data?

    public init(
        kind: Kind,
        utteranceID: UUID,
        channel: RadioChannel,
        speaker: String,
        sentAt: Date,
        station: RadioStationStamp?,
        audio: Data? = nil
    ) {
        self.kind = kind
        self.utteranceID = utteranceID
        self.channel = channel
        self.speaker = speaker
        self.sentAt = sentAt
        self.station = station
        self.audio = audio
    }
}

public struct RadioUtterance: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var channel: RadioChannel
    public var speaker: String
    public var startedAt: Date
    public var endedAt: Date?
    public var path: RadioPath?
    public var delivered: Bool
    public var station: RadioStationStamp?
    public var audioByteCount: Int
    /// 自分が話した発話か、受け取った発話か。
    public var incoming: Bool

    public init(
        id: UUID = UUID(),
        channel: RadioChannel,
        speaker: String,
        startedAt: Date,
        endedAt: Date?,
        path: RadioPath?,
        delivered: Bool,
        station: RadioStationStamp?,
        audioByteCount: Int,
        incoming: Bool
    ) {
        self.id = id
        self.channel = channel
        self.speaker = speaker
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.path = path
        self.delivered = delivered
        self.station = station
        self.audioByteCount = audioByteCount
        self.incoming = incoming
    }
}

public enum RadioDelivery: Equatable, Sendable {
    case sent
    case unreachable
    case rejected(String)
}

/// 音声の通り道。P510 中継も、近くの端末も、この口に差す。
public protocol RadioLink: AnyObject {
    var path: RadioPath { get }
    var isReachable: Bool { get }
    var onReceive: ((RadioPacket) -> Void)? { get set }
    func send(_ packet: RadioPacket) -> RadioDelivery
}

/// P510 に置く中継の差し込み口。通信はしない。届いたパケットを覚えておく。
public final class P510RelayStub: RadioLink {
    public let path: RadioPath = .relay
    public var isReachable: Bool
    public var onReceive: ((RadioPacket) -> Void)?
    public private(set) var sent: [RadioPacket] = []
    public var onSend: ((RadioPacket) -> Void)?

    public init(reachable: Bool) {
        self.isReachable = reachable
    }

    public func send(_ packet: RadioPacket) -> RadioDelivery {
        guard isReachable else { return .unreachable }
        sent.append(packet)
        onSend?(packet)
        return .sent
    }
}

/// 同じチャンネルの相手だけに渡す、メモリ上の近距離網。実機の Multipeer はここへパケットを入れる。
public final class NearbyMesh: RadioLink {
    public let path: RadioPath = .nearby
    public var isReachable: Bool
    public var onReceive: ((RadioPacket) -> Void)?
    public var onSent: ((RadioPacket) -> Void)?
    public var peers: [NearbyMesh] = []
    public private(set) var sent: [RadioPacket] = []

    public init(reachable: Bool = true) {
        self.isReachable = reachable
    }

    public func send(_ packet: RadioPacket) -> RadioDelivery {
        guard isReachable else { return .unreachable }
        sent.append(packet)
        onSent?(packet)
        for peer in peers where peer.isReachable {
            peer.onReceive?(packet)
        }
        return .sent
    }
}

/// 半二重。中継が届くときは中継、届かないときは近くの端末。どちらも無理なら端末内の記録だけ。
public final class RadioDesk {
    public var speaker: String
    public var attachStation: Bool
    public private(set) var channel: RadioChannel?
    public private(set) var phase: RadioPhase = .idle
    public private(set) var utterances: [RadioUtterance] = []
    public private(set) var hearingSpeaker: String?
    /// 発話ごとの音声。上限を超えた分は捨てる。実機のマイクは未確認。
    public private(set) var audio: [UUID: Data] = [:]
    private let audioCap = 256 * 1024

    public let relay: any RadioLink
    public let nearby: any RadioLink
    /// 受け取った PCM。空間オーディオはアプリ側。未設定なら何もしない。
    public var onAudio: ((Data) -> Void)?
    private var live: RadioUtterance?
    private var hearing: RadioUtterance?

    public init(speaker: String, relay: any RadioLink, nearby: any RadioLink, attachStation: Bool = true) {
        self.speaker = speaker
        self.relay = relay
        self.nearby = nearby
        self.attachStation = attachStation
        relay.onReceive = { [weak self] packet in self?.receive(packet) }
        nearby.onReceive = { [weak self] packet in self?.receive(packet) }
    }

    public var activePath: RadioPath? {
        if relay.isReachable { return .relay }
        if nearby.isReachable { return .nearby }
        return nil
    }

    public func join(_ channel: RadioChannel) {
        self.channel = channel
        if phase != .transmitting {
            phase = .listening
        }
    }

    public func leave() {
        if phase == .transmitting {
            _ = endTalking(at: Date())
        }
        channel = nil
        phase = .idle
        hearing = nil
        hearingSpeaker = nil
    }

    /// 押し始め。相手の発話中は話さない。測点を添えない設定なら station は捨てる。
    @discardableResult
    public func beginTalking(at date: Date, station: RadioStationStamp?) -> RadioUtterance? {
        if let live { return live }
        guard phase != .idle, let channel else { return nil }
        guard hearing == nil else { return nil }
        let stamp = attachStation ? station : nil
        let path = activePath
        var utterance = RadioUtterance(
            channel: channel,
            speaker: speaker,
            startedAt: date,
            endedAt: nil,
            path: path,
            delivered: false,
            station: stamp,
            audioByteCount: 0,
            incoming: false
        )
        let packet = RadioPacket(
            kind: .begin,
            utteranceID: utterance.id,
            channel: channel,
            speaker: speaker,
            sentAt: date,
            station: stamp
        )
        utterance.delivered = deliver(packet, path: path)
        live = utterance
        phase = .transmitting
        return utterance
    }

    public func addAudio(_ data: Data, at date: Date) {
        guard var utterance = live, let path = utterance.path, !data.isEmpty else { return }
        utterance.audioByteCount += data.count
        rememberAudio(data, id: utterance.id)
        live = utterance
        let packet = RadioPacket(
            kind: .audio,
            utteranceID: utterance.id,
            channel: utterance.channel,
            speaker: speaker,
            sentAt: date,
            station: nil,
            audio: data
        )
        if deliver(packet, path: path) == false {
            utterance.delivered = false
            live = utterance
        }
    }

    @discardableResult
    public func endTalking(at date: Date) -> RadioUtterance? {
        guard var utterance = live else { return nil }
        utterance.endedAt = date
        let packet = RadioPacket(
            kind: .end,
            utteranceID: utterance.id,
            channel: utterance.channel,
            speaker: speaker,
            sentAt: date,
            station: nil
        )
        if deliver(packet, path: utterance.path) == false {
            utterance.delivered = false
        }
        utterances.append(utterance)
        live = nil
        phase = channel == nil ? .idle : .listening
        return utterance
    }

    public func receive(_ packet: RadioPacket) {
        guard packet.channel.uuid == channel?.uuid else { return }
        guard packet.speaker != speaker else { return }
        switch packet.kind {
        case .begin:
            let utterance = RadioUtterance(
                id: packet.utteranceID,
                channel: packet.channel,
                speaker: packet.speaker,
                startedAt: packet.sentAt,
                endedAt: nil,
                path: nil,
                delivered: true,
                station: packet.station,
                audioByteCount: 0,
                incoming: true
            )
            hearing = utterance
            hearingSpeaker = packet.speaker
        case .audio:
            guard var utterance = hearing, utterance.id == packet.utteranceID else { return }
            utterance.audioByteCount += packet.audio?.count ?? 0
            if let audio = packet.audio {
                rememberAudio(audio, id: utterance.id)
                onAudio?(audio)
            }
            hearing = utterance
        case .end:
            guard var utterance = hearing, utterance.id == packet.utteranceID else { return }
            utterance.endedAt = packet.sentAt
            utterances.append(utterance)
            hearing = nil
            hearingSpeaker = nil
        }
    }

    private func rememberAudio(_ data: Data, id: UUID) {
        var stored = audio[id] ?? Data()
        guard stored.count < audioCap else { return }
        let room = audioCap - stored.count
        stored.append(data.prefix(room))
        audio[id] = stored
    }

    @discardableResult
    private func deliver(_ packet: RadioPacket, path: RadioPath?) -> Bool {
        switch path {
        case .relay:
            return relay.send(packet) == .sent
        case .nearby:
            return nearby.send(packet) == .sent
        case nil:
            return false
        }
    }
}

/// 近距離の一本のセッションで、無線と位置の両方を運ぶ。
public struct LinkFrame: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case radio
        case crew
        case fall
        case sos
    }

    public var kind: Kind
    public var radio: RadioPacket?
    public var crew: CrewPacket?
    public var fall: FallNotice?
    public var sos: SOSPacket?

    public init(
        kind: Kind,
        radio: RadioPacket? = nil,
        crew: CrewPacket? = nil,
        fall: FallNotice? = nil,
        sos: SOSPacket? = nil
    ) {
        self.kind = kind
        self.radio = radio
        self.crew = crew
        self.fall = fall
        self.sos = sos
    }
}

public enum RadioLog {
    public static func append(_ utterance: RadioUtterance, projectName: String, at root: URL) throws {
        let directory = try ProjectStore.projectDirectory(projectName, at: root)
        let url = directory.appendingPathComponent("無線.json")
        var existing = load(projectName: projectName, at: root)
        existing.append(utterance)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(existing).write(to: url)
    }

    public static func load(projectName: String, at root: URL) -> [RadioUtterance] {
        guard let directory = try? ProjectStore.projectDirectory(projectName, at: root) else { return [] }
        let url = directory.appendingPathComponent("無線.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([RadioUtterance].self, from: data)) ?? []
    }
}
