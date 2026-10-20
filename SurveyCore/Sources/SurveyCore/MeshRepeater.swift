import Foundation

/// 中継専用の端末を、前面に置いたまま動かす条件。
public enum RepeaterPosture {
    public static let condition = "中継は、このアプリが前面にあるあいだだけ動きます。画面は黒くして明るさを下げます。ロックすると iOS がアプリを止めるので、自動ロックは切ります。ホームへ戻すか、他のアプリに切り替えると中継は止まり、戻すと再開します。再起動したあとは、アプリを開き直してください。"
    public static let powerNote = "画面を暗くし、音声はスピーカーで再生せず、次の端末へ渡すだけにします。"
    public static let sosNote = "SOS を最優先で渡します。この中継は119通報の代わりではありません。"
}

public struct RepeaterInstall: Codable, Equatable, Sendable {
    public var deviceID: String
    public var name: String
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var at: Date

    public init(deviceID: String, name: String, latitudeDegrees: Double, longitudeDegrees: Double, at: Date) {
        self.deviceID = deviceID
        self.name = name
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.at = at
    }
}

public struct RepeaterBeacon: Codable, Equatable, Sendable {
    public var deviceID: String
    public var name: String
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var batteryPercent: Int?
    public var charging: Bool
    public var at: Date

    public init(
        deviceID: String,
        name: String,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        batteryPercent: Int?,
        charging: Bool,
        at: Date
    ) {
        self.deviceID = deviceID
        self.name = name
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.batteryPercent = batteryPercent
        self.charging = charging
        self.at = at
    }
}

public enum LinkGrade: String, Codable, Sendable {
    case good
    case weak
    case lost

    public var label: String {
        switch self {
        case .good: return "良い"
        case .weak: return "弱い"
        case .lost: return "切れ"
        }
    }
}

public struct RepeaterLink: Equatable, Sendable, Identifiable {
    public var id: String { peerID }
    public var peerID: String
    public var name: String
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var batteryPercent: Int?
    public var charging: Bool
    public var heardAt: Date
    public var grade: LinkGrade

    public init(
        peerID: String,
        name: String,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        batteryPercent: Int?,
        charging: Bool,
        heardAt: Date,
        grade: LinkGrade
    ) {
        self.peerID = peerID
        self.name = name
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.batteryPercent = batteryPercent
        self.charging = charging
        self.heardAt = heardAt
        self.grade = grade
    }
}

/// 隣接中継との接続。電波強度そのものではなく、最後に届いた時刻で見る。
public enum RepeaterQuality {
    public static let goodSeconds: TimeInterval = 15
    public static let weakSeconds: TimeInterval = 60

    public static func grade(lastHeard: Date, now: Date) -> LinkGrade {
        let age = now.timeIntervalSince(lastHeard)
        if age < goodSeconds { return .good }
        if age < weakSeconds { return .weak }
        return .lost
    }
}

public struct RepeaterBoard: Sendable {
    public private(set) var links: [RepeaterLink] = []

    public init() {}

    public mutating func hear(_ beacon: RepeaterBeacon, now: Date) {
        let grade = RepeaterQuality.grade(lastHeard: beacon.at, now: now)
        let link = RepeaterLink(
            peerID: beacon.deviceID,
            name: beacon.name,
            latitudeDegrees: beacon.latitudeDegrees,
            longitudeDegrees: beacon.longitudeDegrees,
            batteryPercent: beacon.batteryPercent,
            charging: beacon.charging,
            heardAt: beacon.at,
            grade: grade
        )
        if let index = links.firstIndex(where: { $0.peerID == beacon.deviceID }) {
            guard beacon.at >= links[index].heardAt else { return }
            links[index] = link
        } else {
            links.append(link)
        }
    }

    public mutating func age(now: Date) {
        for index in links.indices {
            links[index].grade = RepeaterQuality.grade(lastHeard: links[index].heardAt, now: now)
        }
    }
}

public struct RepeaterRecord: Codable, Equatable, Sendable {
    public var mode: Bool
    public var certified: Bool
    public var install: RepeaterInstall?

    public init(mode: Bool = false, certified: Bool = false, install: RepeaterInstall? = nil) {
        self.mode = mode
        self.certified = certified
        self.install = install
    }
}

public enum RepeaterBook {
    public static let folderName = "中継"
    public static let recordName = "設置.json"

    public static func load(projectName: String, at root: URL) -> RepeaterRecord {
        guard let directory = try? ProjectStore.projectDirectory(projectName, at: root) else { return RepeaterRecord() }
        let url = directory
            .appendingPathComponent("記録簿", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(recordName)
        guard let data = try? Data(contentsOf: url) else { return RepeaterRecord() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(RepeaterRecord.self, from: data)) ?? RepeaterRecord()
    }

    public static func save(_ record: RepeaterRecord, projectName: String, at root: URL) throws {
        let project = try ProjectStore.projectDirectory(projectName, at: root)
        let directory = project
            .appendingPathComponent("記録簿", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(to: directory.appendingPathComponent(recordName), options: .atomic)
    }
}

public enum LoRaReject: String, Error, Equatable, Sendable {
    case voice
    case tooLong
    case notCertified
    case empty
}

/// 数kmのLoRaに載せる短い文。音声は載せない。
public struct LoRaMessage: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case sos = "SOS"
        case position = "POS"
        case text = "TXT"
    }

    public var id: UUID
    public var kind: Kind
    public var name: String
    public var latitudeDegrees: Double?
    public var longitudeDegrees: Double?
    public var text: String?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        name: String,
        latitudeDegrees: Double? = nil,
        longitudeDegrees: Double? = nil,
        text: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.text = text
    }

    public func line() -> String {
        let who = LoRaPolicy.clipName(name)
        switch kind {
        case .sos, .position:
            let lat = LoRaPolicy.coordinate(latitudeDegrees)
            let lon = LoRaPolicy.coordinate(longitudeDegrees)
            return "SVY1 \(kind.rawValue) \(who) \(lat) \(lon)"
        case .text:
            return "SVY1 TXT \(who) \(LoRaPolicy.clipText(text ?? ""))"
        }
    }
}

public enum LoRaPolicy {
    public static let voiceNote = "音声はLoRaでは送れません。帯域が足りません。"
    public static let certifiedNote = "日本の920MHz帯で技適を取ったノードだけを使ってください。技適の無いモジュールには送りません。"
    public static let maxBytes = 80
    public static let textLimit = 40
    public static let hopLimit = 3

    public static func admit(
        kind: LoRaMessage.Kind,
        name: String,
        latitudeDegrees: Double? = nil,
        longitudeDegrees: Double? = nil,
        text: String? = nil,
        certified: Bool
    ) -> Result<LoRaMessage, LoRaReject> {
        guard certified else { return .failure(.notCertified) }
        let who = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !who.isEmpty else { return .failure(.empty) }
        if kind == .text {
            let body = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !body.isEmpty, !body.contains("\n") else { return .failure(.empty) }
        }
        let message = LoRaMessage(kind: kind, name: who, latitudeDegrees: latitudeDegrees, longitudeDegrees: longitudeDegrees, text: text)
        guard Data(message.line().utf8).count <= maxBytes else { return .failure(.tooLong) }
        return .success(message)
    }

    public static func admitVoice() -> LoRaReject { .voice }

    static func clipName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
        if trimmed.count <= 12 { return trimmed }
        return String(trimmed.prefix(12))
    }

    static func clipText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        if trimmed.count <= textLimit { return trimmed }
        return String(trimmed.prefix(textLimit))
    }

    static func coordinate(_ degrees: Double?) -> String {
        guard let degrees, degrees.isFinite else { return "-" }
        return String(format: "%.5f", degrees)
    }
}

/// Meshtastic の ToRadio / FromRadio のうち、文字ポートだけを読む。
public enum MeshtasticCodec {
    public static let serviceUUID = "6BA1B218-15A8-461F-9FA8-5DCAE273EAFD"
    public static let toRadioUUID = "F75C76D2-129E-4DAD-A1DD-7866124401E7"
    public static let fromRadioUUID = "2C55E69E-4993-11ED-B878-0242AC120002"
    public static let fromNumUUID = "ED9DA18C-A800-4F66-A670-AA7547E34453"
    public static let textPort: UInt64 = 1
    public static let sosPriority: UInt64 = 110
    public static let textPriority: UInt64 = 64
    public static let positionPriority: UInt64 = 10
    public static let broadcast: UInt32 = 0xFFFF_FFFF

    public static func encode(_ message: LoRaMessage) -> Data {
        let payload = Data(message.line().utf8)
        var data = Proto.fieldVarint(1, textPort)
        data.append(Proto.fieldBytes(2, payload))
        var packet = Proto.fieldFixed32(2, broadcast)
        packet.append(Proto.fieldBytes(4, data))
        packet.append(Proto.fieldFixed32(6, messageID(message.id)))
        packet.append(Proto.fieldVarint(9, UInt64(LoRaPolicy.hopLimit)))
        packet.append(Proto.fieldVarint(11, priority(message.kind)))
        return Proto.fieldBytes(1, packet)
    }

    public static func decodeText(_ bytes: Data) -> String? {
        guard let packet = Proto.child(bytes, field: 2) ?? Proto.child(bytes, field: 1) else { return nil }
        let body = Proto.child(packet, field: 4) ?? packet
        guard Proto.varint(body, field: 1) == textPort else { return nil }
        guard let payload = Proto.child(body, field: 2), let text = String(data: payload, encoding: .utf8) else { return nil }
        return text.hasPrefix("SVY1 ") ? text : nil
    }

    public static func priority(in bytes: Data) -> UInt64? {
        let packet = Proto.child(bytes, field: 1) ?? bytes
        return Proto.varint(packet, field: 11)
    }

    private static func priority(_ kind: LoRaMessage.Kind) -> UInt64 {
        switch kind {
        case .sos: return sosPriority
        case .text: return textPriority
        case .position: return positionPriority
        }
    }

    private static func messageID(_ id: UUID) -> UInt32 {
        let bytes = id.uuid
        return UInt32(bytes.0) | (UInt32(bytes.1) << 8) | (UInt32(bytes.2) << 16) | (UInt32(bytes.3) << 24)
    }
}

public struct LoRaOutbox: Sendable {
    private var waiting: [LoRaMessage] = []
    private var seen: [UUID] = []

    public init() {}

    public var count: Int { waiting.count }

    public mutating func add(_ message: LoRaMessage) -> Bool {
        guard !seen.contains(message.id) else { return false }
        guard Data(message.line().utf8).count <= LoRaPolicy.maxBytes else { return false }
        seen.append(message.id)
        if seen.count > 200 { seen.removeFirst(seen.count - 200) }
        waiting.append(message)
        return true
    }

    public mutating func next() -> LoRaMessage? {
        guard !waiting.isEmpty else { return nil }
        let index = waiting.indices.min { lhs, rhs in
            let left = rank(waiting[lhs].kind)
            let right = rank(waiting[rhs].kind)
            if left != right { return left < right }
            return lhs < rhs
        }
        guard let index else { return nil }
        return waiting.remove(at: index)
    }

    private func rank(_ kind: LoRaMessage.Kind) -> Int {
        switch kind {
        case .sos: return 0
        case .text: return 1
        case .position: return 2
        }
    }
}

enum Proto {
    static func fieldVarint(_ field: Int, _ value: UInt64) -> Data {
        var data = Data([key(field, wire: 0)])
        data.append(varint(value))
        return data
    }

    static func fieldFixed32(_ field: Int, _ value: UInt32) -> Data {
        var data = Data([key(field, wire: 5)])
        data.append(contentsOf: [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ])
        return data
    }

    static func fieldBytes(_ field: Int, _ value: Data) -> Data {
        var data = Data([key(field, wire: 2)])
        data.append(varint(UInt64(value.count)))
        data.append(value)
        return data
    }

    static func child(_ data: Data, field: Int) -> Data? {
        var index = 0
        let bytes = [UInt8](data)
        while index < bytes.count {
            guard let (tag, next) = readVarint(bytes, index) else { return nil }
            index = next
            let number = Int(tag >> 3)
            let wire = tag & 0x07
            if wire == 2 {
                guard let (length, after) = readVarint(bytes, index) else { return nil }
                let size = Int(length)
                guard after + size <= bytes.count else { return nil }
                if number == field {
                    return Data(bytes[after..<(after + size)])
                }
                index = after + size
            } else if wire == 0 {
                guard let (_, after) = readVarint(bytes, index) else { return nil }
                index = after
            } else if wire == 5 {
                guard index + 4 <= bytes.count else { return nil }
                index += 4
            } else if wire == 1 {
                guard index + 8 <= bytes.count else { return nil }
                index += 8
            } else {
                return nil
            }
        }
        return nil
    }

    static func varint(_ data: Data, field: Int) -> UInt64? {
        var index = 0
        let bytes = [UInt8](data)
        while index < bytes.count {
            guard let (tag, next) = readVarint(bytes, index) else { return nil }
            index = next
            let number = Int(tag >> 3)
            let wire = tag & 0x07
            if wire == 0 {
                guard let (value, after) = readVarint(bytes, index) else { return nil }
                if number == field { return value }
                index = after
            } else if wire == 2 {
                guard let (length, after) = readVarint(bytes, index) else { return nil }
                index = after + Int(length)
            } else if wire == 5 {
                index += 4
            } else if wire == 1 {
                index += 8
            } else {
                return nil
            }
        }
        return nil
    }

    private static func key(_ field: Int, wire: UInt8) -> UInt8 {
        UInt8((field << 3) | Int(wire))
    }

    private static func varint(_ value: UInt64) -> Data {
        var rest = value
        var data = Data()
        repeat {
            var byte = UInt8(rest & 0x7F)
            rest >>= 7
            if rest != 0 { byte |= 0x80 }
            data.append(byte)
        } while rest != 0
        return data
    }

    private static func readVarint(_ bytes: [UInt8], _ start: Int) -> (UInt64, Int)? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        var index = start
        while index < bytes.count, shift <= 63 {
            let byte = bytes[index]
            index += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return (value, index) }
            shift += 7
        }
        return nil
    }
}
