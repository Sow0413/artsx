import Foundation

/// NTRIP の要求と応答。ソケットは持たないので、Linux のテストから偽 caster に投げられる。
public enum NTRIPDialect: String, Sendable, Equatable {
    case v1
    case v2
}

public enum NTRIPReply: Equatable, Sendable {
    case stream
    case sourcetable
    case unauthorized
    case missingMount
    case unavailable
    case other(Int)

    public var message: String {
        switch self {
        case .stream: return "補正受信中"
        case .sourcetable: return "マウント一覧"
        case .unauthorized: return "IDまたはパスワードが違います（401）"
        case .missingMount: return "マウントポイントがありません（404）"
        case .unavailable: return "同じIDが別の機器で接続中か、一時的に混雑しています。少し待って再接続してください"
        case .other(let code): return "NTRIP が拒否しました（\(code)）"
        }
    }

    /// 404 の状態行には、実際に送ったマウント名を付ける。
    public func statusLine(mount: String) -> String {
        let name = mount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .missingMount = self, !name.isEmpty else { return message }
        return "\(message) \(name)"
    }
}

public struct NTRIPWire: Equatable, Sendable {
    public var bytes: Data
    /// 認証の中身は *** に伏せた、ログ用の文面。
    public var log: String

    public init(bytes: Data, log: String) {
        self.bytes = bytes
        self.log = log
    }
}

public struct NTRIPHeader: Equatable, Sendable {
    public var reply: NTRIPReply
    public var statusLine: String
    public var chunked: Bool
    public var body: Data

    public init(reply: NTRIPReply, statusLine: String, chunked: Bool, body: Data) {
        self.reply = reply
        self.statusLine = statusLine
        self.chunked = chunked
        self.body = body
    }
}

public enum NTRIPExchange {
    public static let userAgent = "NTRIP artsx/1.1"
    /// 応答のあとに送る間隔。5秒以下。既定は2秒。
    public static let ggaIntervalSeconds: TimeInterval = 2

    public static func request(
        host: String,
        mount: String?,
        user: String,
        password: String,
        dialect: NTRIPDialect,
        gga: String?
    ) -> NTRIPWire {
        let path = mount.map { $0.isEmpty ? "/" : "/\($0)" } ?? "/"
        let version = dialect == .v1 ? "HTTP/1.0" : "HTTP/1.1"
        var lines = ["GET \(path) \(version)"]
        if dialect == .v2 {
            lines.append("Host: \(host)")
            lines.append("Ntrip-Version: Ntrip/2.0")
        }
        lines.append("User-Agent: \(userAgent)")
        lines.append("Authorization: Basic \(basicToken(user: user, password: password))")
        lines.append("Accept: */*")
        lines.append("Connection: close")
        var wire = lines.joined(separator: "\r\n") + "\r\n\r\n"
        if let gga, !gga.isEmpty {
            wire += gga.hasSuffix("\r\n") ? gga : gga + "\r\n"
        }
        var masked = lines
        if let index = masked.firstIndex(where: { $0.hasPrefix("Authorization:") }) {
            masked[index] = "Authorization: Basic ***"
        }
        let log = masked.joined(separator: "\r\n") + "\r\n\r\n" + (gga.map { ($0.hasSuffix("\r\n") ? $0 : $0 + "\r\n") } ?? "")
        return NTRIPWire(bytes: Data(wire.utf8), log: log)
    }

    public static func basicToken(user: String, password: String) -> String {
        Data("\(user):\(password)".utf8).base64EncodedString()
    }

    /// ヘッダが揃うまで nil。ICY 200 OK だけの応答も境目にする。
    public static func parseHeader(_ data: Data) -> NTRIPHeader? {
        let separator = Data("\r\n\r\n".utf8)
        let split: Data.Index
        let headData: Data
        let body: Data
        if let range = data.range(of: separator) {
            split = range.upperBound
            headData = data.subdata(in: data.startIndex..<range.lowerBound)
            body = data.subdata(in: split..<data.endIndex)
        } else if let range = data.range(of: Data("ICY 200 OK\r\n".utf8)) {
            headData = data.subdata(in: data.startIndex..<range.lowerBound)
            body = data.subdata(in: range.upperBound..<data.endIndex)
        } else {
            return nil
        }
        let head = String(data: headData, encoding: .ascii) ?? ""
        let status = head.split(whereSeparator: \.isNewline).first.map(String.init) ?? head
        let folded = head.lowercased()
        let chunked = folded.contains("transfer-encoding:") && folded.contains("chunked")
        return NTRIPHeader(reply: classify(status), statusLine: status, chunked: chunked, body: body)
    }

    public static func classify(_ statusLine: String) -> NTRIPReply {
        let line = statusLine.uppercased()
        if line.contains("SOURCETABLE") { return .sourcetable }
        if line.contains("ICY") && line.contains("200") { return .stream }
        if let code = httpCode(line) {
            switch code {
            case 200: return .stream
            case 401: return .unauthorized
            case 404: return .missingMount
            case 503: return .unavailable
            default: return .other(code)
            }
        }
        return .other(0)
    }

    public static func mounts(in sourcetable: String) -> [String] {
        sourcetable.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.uppercased().hasPrefix("STR;") else { return nil }
            let fields = line.split(separator: ";", omittingEmptySubsequences: false)
            guard fields.count > 1 else { return nil }
            let name = String(fields[1])
            return name.isEmpty ? nil : name
        }
    }

    /// 現在地から $GPGGA を作る。チェックサム付き。
    public static func gpgga(
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        ellipsoidalHeightMeters: Double?,
        at date: Date = Date()
    ) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)
        let time = String(format: "%02d%02d%02d.00", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        let lat = coordinate(latitudeDegrees, latitude: true)
        let lon = coordinate(longitudeDegrees, latitude: false)
        let height = ellipsoidalHeightMeters.map { String(format: "%.1f", $0) } ?? ""
        let body = "GPGGA,\(time),\(lat.value),\(lat.hemisphere),\(lon.value),\(lon.hemisphere),1,08,1.0,\(height),M,0.0,M,,"
        return "$\(body)*\(checksum(body))"
    }

    public static func checksum(_ body: String) -> String {
        var value: UInt8 = 0
        for byte in body.utf8 { value ^= byte }
        return String(format: "%02X", value)
    }

    private static func httpCode(_ line: String) -> Int? {
        let parts = line.split(separator: " ")
        guard parts.count >= 2, let code = Int(parts[1]) else { return nil }
        return code
    }

    private static func coordinate(_ degrees: Double, latitude: Bool) -> (value: String, hemisphere: String) {
        let hemisphere: String
        if latitude {
            hemisphere = degrees < 0 ? "S" : "N"
        } else {
            hemisphere = degrees < 0 ? "W" : "E"
        }
        let absolute = abs(degrees)
        let whole = Int(absolute)
        let minutes = (absolute - Double(whole)) * 60
        if latitude {
            return (String(format: "%02d%07.4f", whole, minutes), hemisphere)
        }
        return (String(format: "%03d%07.4f", whole, minutes), hemisphere)
    }
}

/// HTTP/1.1 の chunked 本体を、届いた分だけ RTCM に戻す。
public struct NTRIPChunkDecoder: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func feed(_ data: Data) -> Data {
        buffer.append(data)
        var output = Data()
        let newline = Data("\r\n".utf8)
        while let range = buffer.range(of: newline) {
            let sizeText = String(data: buffer.subdata(in: buffer.startIndex..<range.lowerBound), encoding: .ascii) ?? ""
            let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16) ?? -1
            guard size >= 0 else {
                buffer.removeAll(keepingCapacity: false)
                break
            }
            let payloadStart = range.upperBound
            let needed = size + 2
            guard buffer.distance(from: payloadStart, to: buffer.endIndex) >= needed else { break }
            let payloadEnd = buffer.index(payloadStart, offsetBy: size)
            if size > 0 { output.append(buffer.subdata(in: payloadStart..<payloadEnd)) }
            buffer.removeSubrange(buffer.startIndex..<buffer.index(payloadEnd, offsetBy: 2))
            if size == 0 { break }
        }
        return output
    }
}

/// FFF2 へ書く開始列と、RTCM の切り方。
/// 電源投入と再接続のたびに `start` を書き、FFF1 の準備完了を待ってから `nmea` を書く。
public enum ViDocLink {
    /// 裸の ASCII `start` と CR LF。`<STX>start<ETX>` ではない。
    public static let startCommand = Data([0x73, 0x74, 0x61, 0x72, 0x74, 0x0D, 0x0A])
    /// `<STX>nmea<ETX>`。`ready` のあとに書く。
    public static let nmeaCommand = Data([0x02, 0x6E, 0x6D, 0x65, 0x61, 0x03])
    public static let nmeaStartCommand = nmeaCommand
    /// `ready` が来なければ、この秒数で `nmea` に進む。
    public static let readyWaitSeconds: TimeInterval = 1
    /// `nmea` のあと、待機文が続き $G が来なければ start を送り直すまでの秒。
    public static let nmeaWaitSeconds: TimeInterval = 3
    /// start の再送は 3 回まで。
    public static let maxStartRetries = 3

    public static func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{0002}", with: "")
            .replacingOccurrences(of: "\u{0003}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 行のどこかに ASCII の `ready` があれば準備完了。大文字の READY や版数・電池だけでは違う。
    public static func isReadyText(_ text: String) -> Bool {
        normalized(text).contains("ready")
    }

    public static func isNMEA(_ text: String) -> Bool {
        normalized(text).hasPrefix("$G")
    }

    /// 待機のままの文。版数、電池、wait。NMEA と ready は含まない。
    public static func isWaitLine(_ text: String) -> Bool {
        let line = normalized(text)
        if line.isEmpty || line.contains("ready") || line.hasPrefix("$") { return false }
        if line.contains("Ver_") { return true }
        let lower = line.lowercased()
        if lower.contains("wait") || lower.contains("battery") || lower.contains("batt") || line.contains("電池") {
            return true
        }
        let digits = lower.prefix { $0.isNumber }
        guard !digits.isEmpty else { return false }
        let rest = lower.dropFirst(digits.count).drop { $0 == " " }
        return rest.first == "%"
    }
    /// 244 バイト連続書きは RTCM の 6 割以上を落とす。180 を上限にする。
    public static let maxChunkBytes = 180
    public static let minimumChunkBytes = 20
    /// チャンク間隔。10〜15 ms。既定は 12 ms。
    public static let rtcmChunkIntervalMs = 12

    public static func chunkSize(maximumWriteLength: Int) -> Int {
        min(maxChunkBytes, max(minimumChunkBytes, maximumWriteLength))
    }

    public static func rtcmChunks(_ data: Data, maximumWriteLength: Int) -> [Data] {
        let size = chunkSize(maximumWriteLength: maximumWriteLength)
        guard !data.isEmpty else { return [] }
        var chunks: [Data] = []
        var offset = 0
        while offset < data.count {
            let end = min(offset + size, data.count)
            chunks.append(data.subdata(in: offset..<end))
            offset = end
        }
        return chunks
    }
}

/// `start\r\n` のあと `ready` だけを待ち、それから `nmea`。BLE は切らない。
public struct ViDocBoot: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case needStart
        case waitingForReady(since: TimeInterval, attempt: Int)
        case waitingForNMEA(since: TimeInterval, attempt: Int, sawWait: Bool)
        case streaming
    }

    public private(set) var phase: Phase = .needStart
    public var readyWait: TimeInterval
    public var nmeaWait: TimeInterval
    public var maxRetries: Int

    public init(
        readyWait: TimeInterval = ViDocLink.readyWaitSeconds,
        nmeaWait: TimeInterval = ViDocLink.nmeaWaitSeconds,
        maxRetries: Int = ViDocLink.maxStartRetries
    ) {
        self.readyWait = readyWait
        self.nmeaWait = nmeaWait
        self.maxRetries = maxRetries
    }

    public mutating func onConnect(at now: TimeInterval) -> Data {
        phase = .waitingForReady(since: now, attempt: 0)
        return ViDocLink.startCommand
    }

    /// 書くコマンドがあれば返す。BLE の切断はしない。
    public mutating func onNotify(_ text: String, at now: TimeInterval) -> Data? {
        if ViDocLink.isNMEA(text) {
            phase = .streaming
            return nil
        }
        if ViDocLink.isReadyText(text) {
            guard case .waitingForReady(_, let attempt) = phase else { return nil }
            phase = .waitingForNMEA(since: now, attempt: attempt, sawWait: false)
            return ViDocLink.nmeaCommand
        }
        guard ViDocLink.isWaitLine(text) else { return nil }
        switch phase {
        case .streaming:
            phase = .waitingForReady(since: now, attempt: 0)
            return ViDocLink.startCommand
        case .waitingForNMEA(let since, let attempt, _):
            phase = .waitingForNMEA(since: since, attempt: attempt, sawWait: true)
            return resendIfDue(at: now)
        case .waitingForReady, .needStart:
            return nil
        }
    }

    public mutating func onTick(at now: TimeInterval) -> Data? {
        if case .waitingForReady(let since, let attempt) = phase, now - since + 1e-9 >= readyWait {
            phase = .waitingForNMEA(since: now, attempt: attempt, sawWait: false)
            return ViDocLink.nmeaCommand
        }
        return resendIfDue(at: now)
    }

    private mutating func resendIfDue(at now: TimeInterval) -> Data? {
        guard case .waitingForNMEA(let since, let attempt, let sawWait) = phase else { return nil }
        guard sawWait, now - since + 1e-9 >= nmeaWait, attempt < maxRetries else { return nil }
        phase = .waitingForReady(since: now, attempt: attempt + 1)
        return ViDocLink.startCommand
    }
}

/// 機器コマンドは1回の書き込みのまま、RTCM チャンクのあいだに出す。
public struct ViDocOutbound: Sendable {
    public private(set) var commands: [Data] = []
    public var corrections = RTCMOutboundBuffer()

    public init() {}

    public mutating func enqueueCommand(_ command: Data) {
        guard !command.isEmpty else { return }
        commands.append(command)
    }

    public mutating func clearCommands() {
        commands.removeAll(keepingCapacity: false)
    }

    public mutating func nextWrite(maximumChunkBytes: Int) -> Data? {
        if !commands.isEmpty { return commands.removeFirst() }
        return corrections.nextChunk(maximumBytes: maximumChunkBytes)
    }
}

/// 連続書きを避け、次のチャンクを出してよいかを時刻と送信口の空きで決める。
public struct RTCMWriteSchedule: Equatable, Sendable {
    public var intervalMs: Int
    public private(set) var nextAllowed: TimeInterval

    public init(intervalMs: Int = ViDocLink.rtcmChunkIntervalMs, nextAllowed: TimeInterval = -.infinity) {
        self.intervalMs = intervalMs
        self.nextAllowed = nextAllowed
    }

    public func allows(at now: TimeInterval, transportReady: Bool) -> Bool {
        transportReady && now + 1e-9 >= nextAllowed
    }

    public func advanced(afterSendingAt now: TimeInterval) -> RTCMWriteSchedule {
        var copy = self
        copy.nextAllowed = now + Double(intervalMs) / 1_000
        return copy
    }
}

/// 届いた RTCM を順に貯める。上限を超えたら、フレームの途中ではなく古い文ごと捨てる。
public struct RTCMOutboundBuffer: Sendable {
    public static let capBytes = 16 * 1024
    private struct Stamped {
        var at: TimeInterval
        var data: Data
    }

    private var frames: [Stamped] = []
    private var partial = Data()
    private var partialAt: TimeInterval = 0
    private var frontIsPartial = false

    public init() {}

    public var bufferedBytes: Int { frames.reduce(0) { $0 + $1.data.count } }

    public mutating func append(_ data: Data, at now: TimeInterval = 0) {
        guard !data.isEmpty else { return }
        if partial.isEmpty { partialAt = now }
        partial.append(data)
        while let frame = nextFrame() {
            frames.append(Stamped(at: now, data: frame))
        }
        trimToCap()
    }

    /// 再接続のとき、指定より古い文を捨てる。今送っている途中の文は残す。
    public mutating func dropOlder(than age: TimeInterval, now: TimeInterval) {
        if frontIsPartial, let head = frames.first {
            frames = [head] + frames.dropFirst().filter { now - $0.at <= age }
        } else {
            frames.removeAll { now - $0.at > age }
        }
        if !partial.isEmpty, now - partialAt > age {
            partial.removeAll(keepingCapacity: false)
        }
    }

    public mutating func nextChunk(maximumBytes: Int) -> Data? {
        guard maximumBytes > 0, !frames.isEmpty else { return nil }
        var first = frames[0].data
        let count = min(maximumBytes, first.count)
        let chunk = Data(first.prefix(count))
        first.removeFirst(count)
        if first.isEmpty {
            frames.removeFirst()
            frontIsPartial = false
        } else {
            frames[0].data = first
            frontIsPartial = true
        }
        return chunk
    }

    private mutating func nextFrame() -> Data? {
        while partial.count >= 3 {
            if partial[partial.startIndex] != 0xD3 {
                partial.removeFirst()
                continue
            }
            let high = Int(partial[partial.index(partial.startIndex, offsetBy: 1)] & 0x03)
            let low = Int(partial[partial.index(partial.startIndex, offsetBy: 2)])
            let length = (high << 8) | low
            let total = length + 6
            guard partial.count >= total else { return nil }
            let frame = Data(partial.prefix(total))
            partial.removeFirst(total)
            return frame
        }
        return nil
    }

    private mutating func trimToCap() {
        while bufferedBytes > Self.capBytes, !frames.isEmpty {
            if frames.count == 1, frontIsPartial { break }
            if frontIsPartial, frames.count > 1 {
                frames.remove(at: 1)
            } else {
                frames.removeFirst()
                frontIsPartial = false
            }
        }
        if partial.count > Self.capBytes {
            partial.removeAll(keepingCapacity: false)
        }
    }
}

/// ViDoc の広告を拾うか。iOS は localName を落とすことが多い。GATT は FFF0、広告の Service Data は FFE1、製造者は Minew 0x0639。
public enum ViDocDiscovery {
    public static let serviceUUID = "FFF0"
    public static let advertisementServiceDataUUID = "FFE1"
    public static let minewCompanyID: UInt16 = 0x0639

    public static func matches(
        localName: String,
        serviceUUIDs: [String] = [],
        overflowServiceUUIDs: [String] = [],
        serviceDataUUIDs: [String] = [],
        manufacturerData: Data? = nil
    ) -> Bool {
        if companyID(manufacturerData) == minewCompanyID { return true }
        let advertised = (serviceUUIDs + overflowServiceUUIDs + serviceDataUUIDs).map(normalize)
        if advertised.contains(advertisementServiceDataUUID) || advertised.contains(serviceUUID) { return true }
        let name = localName.lowercased()
        return ["vigram", "vidoc", "vida"].contains { name.contains($0) }
    }

    public static func companyID(_ data: Data?) -> UInt16? {
        guard let data, data.count >= 2 else { return nil }
        return UInt16(data[data.startIndex]) | (UInt16(data[data.startIndex + 1]) << 8)
    }

    private static func normalize(_ uuid: String) -> String {
        let hex = uuid.replacingOccurrences(of: "-", with: "").uppercased()
        if hex.count >= 8, hex.hasPrefix("0000") {
            return String(hex.dropFirst(4).prefix(4))
        }
        return String(hex.suffix(4))
    }
}
