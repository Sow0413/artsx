import Foundation

/// NTRIP の要求と、返ってきた RTCM3。パスワードは Authorization を組み立てる引数だけで、文には残さない。
public enum NTRIPVersion: String, Codable, Sendable, Equatable, Hashable {
    case v1
    case v2
}

public struct NTRIPAccount: Equatable, Sendable {
    public var host: String
    public var port: Int
    public var mountpoint: String
    public var user: String
    public var version: NTRIPVersion

    public init(host: String, port: Int, mountpoint: String, user: String, version: NTRIPVersion) {
        self.host = host
        self.port = port
        self.mountpoint = mountpoint
        self.user = user
        self.version = version
    }

    public var isComplete: Bool {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let mount = mountpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = user.trimmingCharacters(in: .whitespacesAndNewlines)
        return !host.isEmpty && !mount.isEmpty && !user.isEmpty && port > 0 && port <= 65535
            && !host.contains("\n") && !host.contains("\r")
            && !mount.contains("\n") && !mount.contains("\r")
            && !user.contains("\n") && !user.contains("\r")
    }
}

/// docomo 高精度GNSS。RRS は最寄り局を選ぶマウントポイント。同じ ID は何台でも同時に使える。パスワードは持たない。
public enum DocomoCaster {
    public static let host = "d-gnss.jp"
    public static let port = 2101
    public static let mountpoint = "RRSGD2024"
}

public enum NTRIPRequest {
    /// docomo は GGA を 10 秒ごと。1 秒より長く、という案内に合わせる。
    public static let ggaInterval: TimeInterval = 10

    public static func shouldSendGGA(last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= ggaInterval
    }

    /// パスワードは Basic の中だけ。呼び出し側は結果をログに出さない。
    public static func header(account: NTRIPAccount, password: String, gga: String?) -> String {
        let host = oneLine(account.host)
        let user = oneLine(account.user)
        let mount = oneLine(account.mountpoint).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let token = Data("\(user):\(oneLine(password))".utf8).base64EncodedString()
        switch account.version {
        case .v1:
            return [
                "GET /\(mount) HTTP/1.0",
                "User-Agent: NTRIP artsx/1.0",
                "Accept: */*",
                "Authorization: Basic \(token)",
                "",
                ""
            ].joined(separator: "\r\n")
        case .v2:
            var lines = [
                "GET /\(mount) HTTP/1.1",
                "Host: \(host):\(account.port)",
                "Ntrip-Version: Ntrip/2.0",
                "User-Agent: NTRIP artsx/1.0",
                "Authorization: Basic \(token)"
            ]
            if let gga, gga.hasPrefix("$"), !gga.contains("\r"), !gga.contains("\n") {
                lines.append("Ntrip-GGA: \(gga)")
            }
            lines.append("")
            lines.append("")
            return lines.joined(separator: "\r\n")
        }
    }

    private static func oneLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct NTRIPIntake: Equatable, Sendable {
    public var status: Int?
    public var failed: Bool
    public var frames: [Data]
    public var pending: Data

    public init(status: Int?, failed: Bool, frames: [Data], pending: Data) {
        self.status = status
        self.failed = failed
        self.frames = frames
        self.pending = pending
    }
}

public enum NTRIPStream {
    /// HTTP の頭が終わるまで RTCM は出さない。401 やソース表は失敗。
    public static func consume(_ buffer: Data) -> NTRIPIntake {
        let marker = Data([0x0d, 0x0a, 0x0d, 0x0a])
        guard let range = buffer.range(of: marker) else {
            if buffer.count > 8192 {
                return NTRIPIntake(status: nil, failed: true, frames: [], pending: Data())
            }
            return NTRIPIntake(status: nil, failed: false, frames: [], pending: buffer)
        }
        let header = buffer.subdata(in: 0..<range.lowerBound)
        let text = String(decoding: header, as: UTF8.self)
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let upper = first.uppercased()
        if upper.contains("SOURCETABLE") {
            return NTRIPIntake(status: nil, failed: true, frames: [], pending: Data())
        }
        let status = statusCode(upper)
        guard status == 200 else {
            return NTRIPIntake(status: status, failed: true, frames: [], pending: Data())
        }
        let body = buffer.subdata(in: range.upperBound..<buffer.endIndex)
        let split = RTCM3.frames(in: body)
        return NTRIPIntake(status: 200, failed: false, frames: split.frames, pending: split.remainder)
    }

    private static func statusCode(_ line: String) -> Int? {
        if line.contains("401") { return 401 }
        if line.contains("404") { return 404 }
        if line.contains("200") { return 200 }
        return nil
    }
}

public enum RTCM3 {
    public static func crc(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0
        for byte in data {
            crc ^= UInt32(byte) << 16
            for _ in 0..<8 {
                crc <<= 1
                if crc & 0x1000000 != 0 {
                    crc ^= 0x1864CFB
                }
            }
        }
        return crc & 0xFFFFFF
    }

    public static func frame(payload: Data) -> Data {
        let length = payload.count
        var data = Data([
            0xD3,
            UInt8((length >> 8) & 0x03),
            UInt8(length & 0xFF)
        ])
        data.append(payload)
        let check = crc(data)
        data.append(UInt8((check >> 16) & 0xFF))
        data.append(UInt8((check >> 8) & 0xFF))
        data.append(UInt8(check & 0xFF))
        return data
    }

    /// 先頭のごみは捨て、CRC が合った枠だけ返す。余りは次の受信に残す。
    public static func frames(in data: Data) -> (frames: [Data], remainder: Data) {
        var frames: [Data] = []
        var index = 0
        let bytes = [UInt8](data)
        while index < bytes.count {
            guard let start = bytes[index...].firstIndex(of: 0xD3) else {
                return (frames, Data())
            }
            if start > index {
                index = start
            }
            if bytes.count - index < 6 {
                break
            }
            let length = (Int(bytes[index + 1] & 0x03) << 8) | Int(bytes[index + 2])
            let total = 3 + length + 3
            if length > 1023 || bytes.count - index < total {
                if length > 1023 {
                    index += 1
                    continue
                }
                break
            }
            let slice = Data(bytes[index..<(index + total)])
            let body = slice.prefix(3 + length)
            let expected = crc(Data(body))
            let given = (UInt32(slice[slice.count - 3]) << 16)
                | (UInt32(slice[slice.count - 2]) << 8)
                | UInt32(slice[slice.count - 1])
            if expected == given {
                frames.append(slice)
                index += total
            } else {
                index += 1
            }
        }
        return (frames, Data(bytes[index...]))
    }
}

/// docomo の RTK、受信機が報告した CLAS、単独、iPhone の順。
public enum PositioningTier: Equatable, Sendable {
    case docomo
    case clas
    case single
    case phone
}

public struct ExternalPositionChoice: Equatable, Sendable {
    public var reading: PositionReading
    public var tier: PositioningTier
    public var notice: String?

    public init(reading: PositionReading, tier: PositioningTier, notice: String?) {
        self.reading = reading
        self.tier = tier
        self.notice = notice
    }

    public var usingReceiver: Bool { tier != .phone }
}

public enum ExternalPosition {
    public static let receiverFreshSeconds: TimeInterval = 3
    public static let correctionFreshSeconds: TimeInterval = 10

    public static func choose(
        iphone: PositionReading,
        receiver: PositionReading?,
        receiverAt: Date?,
        correctionAt: Date?,
        now: Date,
        previous: PositioningTier
    ) -> ExternalPositionChoice {
        let receiverOK = receiver?.position?.isPlottable == true
            && fresh(receiverAt, now: now, limit: receiverFreshSeconds)
        let correctionsOK = fresh(correctionAt, now: now, limit: correctionFreshSeconds)
        let reported = receiver?.position
        let rtk = reported?.fixQuality == .rtkFix || reported?.fixQuality == .float
        let clas = reported?.fixQuality == .clas || reported?.receiver == .clas
        let tier: PositioningTier
        let reading: PositionReading
        if receiverOK, correctionsOK, rtk, let receiver {
            tier = .docomo
            reading = receiver
        } else if receiverOK, clas, let receiver {
            tier = .clas
            reading = receiver
        } else if receiverOK, let receiver, let position = receiver.position {
            tier = .single
            reading = PositionReading(position: single(position), availability: receiver.availability)
        } else {
            tier = .phone
            reading = iphone
        }
        return ExternalPositionChoice(
            reading: reading,
            tier: tier,
            notice: notice(from: previous, to: tier)
        )
    }

    /// FIX のまま補正が切れた点は、単独としてタグする。
    static func single(_ position: GeodeticPosition) -> GeodeticPosition {
        var copy = position
        switch copy.fixQuality {
        case .rtkFix, .float, .clas:
            copy.fixQuality = .standalone
            copy.stage = .iphone
            copy.correctionAgeSeconds = nil
        case .standalone, .dgps, .none:
            break
        }
        return copy
    }

    private static func notice(from previous: PositioningTier, to tier: PositioningTier) -> String? {
        guard previous != tier else { return nil }
        switch tier {
        case .clas:
            return previous == .docomo ? "CLASに切り替えました。" : nil
        case .single:
            switch previous {
            case .docomo: return "補正が切れました。単独測位です。"
            case .clas: return "単独測位です。"
            case .phone, .single: return nil
            }
        case .phone:
            return "受信機が切れました。iPhoneの測位に戻しました。"
        case .docomo:
            return nil
        }
    }

    private static func fresh(_ date: Date?, now: Date, limit: TimeInterval) -> Bool {
        guard let date else { return false }
        return now.timeIntervalSince(date) <= limit
    }
}

public enum ExternalFix {
    /// FIX でなくても記録は止めない。解の文字は点に残す。
    public static func blocksRecording(workID: String, position: GeodeticPosition?) -> Bool {
        _ = (workID, position)
        return false
    }
}

/// BLE へ書いた RTCM の量と、届いてから書き終わるまでの時間。中身は残さない。
public struct RTCMMeter: Equatable, Sendable {
    public struct Sample: Equatable, Sendable {
        public var at: Date
        public var bytes: Int
        public var chunks: Int
        public var latencySeconds: Double

        public init(at: Date, bytes: Int, chunks: Int, latencySeconds: Double) {
            self.at = at
            self.bytes = bytes
            self.chunks = chunks
            self.latencySeconds = latencySeconds
        }
    }

    public static let windowSeconds: TimeInterval = 10
    public private(set) var samples: [Sample]

    public init(samples: [Sample] = []) {
        self.samples = samples
    }

    public mutating func note(bytes: Int, chunks: Int, latencySeconds: Double, at date: Date) {
        samples.append(Sample(at: date, bytes: bytes, chunks: chunks, latencySeconds: latencySeconds))
        let cutoff = date.addingTimeInterval(-Self.windowSeconds)
        samples.removeAll { $0.at < cutoff }
    }

    public func line(now: Date) -> String {
        let cutoff = now.addingTimeInterval(-Self.windowSeconds)
        let recent = samples.filter { $0.at >= cutoff }
        let bytes = recent.reduce(0) { $0 + $1.bytes }
        let chunks = recent.reduce(0) { $0 + $1.chunks }
        let span = max(now.timeIntervalSince(recent.first?.at ?? now), 1)
        let kb = Double(bytes) / span / 1024
        let rate = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), kb)
        let delay = recent.last.map { " 遅延 \(Int(($0.latencySeconds * 1000).rounded()))ms" } ?? ""
        return "RTCM \(rate)KB/s \(chunks)分割\(delay)"
    }
}

public enum BLEMTU {
    /// ATT の書き込み長で切る。20 バイト未満にはしない。
    public static func split(_ data: Data, maximumWriteLength: Int) -> [Data] {
        let limit = max(20, maximumWriteLength)
        if data.isEmpty { return [] }
        var pieces: [Data] = []
        var offset = 0
        while offset < data.count {
            let end = min(offset + limit, data.count)
            pieces.append(data.subdata(in: offset..<end))
            offset = end
        }
        return pieces
    }
}
