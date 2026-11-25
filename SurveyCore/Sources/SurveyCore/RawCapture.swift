import Foundation

/// 観測中だけ RAM に書く。BBR、Flash、CFG-RST、CFG-CFG は作らない。
public enum UBXConfig {
    public static let rateMeasKey: UInt32 = 0x3021_0001
    public static let rawxUART1Key: UInt32 = 0x2091_02A5
    public static let sfrbxUART1Key: UInt32 = 0x2091_0232
    public static let valsetClass: UInt8 = 0x06
    public static let valsetID: UInt8 = 0x8A
    public static let valgetClass: UInt8 = 0x06
    public static let valgetID: UInt8 = 0x8B
    public static let ramLayerGet: UInt8 = 0x00
    public static let ramLayerSet: UInt8 = 0x01

    public struct Values: Equatable, Sendable {
        public var rateMeas: UInt16
        public var rawx: UInt8
        public var sfrbx: UInt8

        public init(rateMeas: UInt16, rawx: UInt8, sfrbx: UInt8) {
            self.rateMeas = rateMeas
            self.rawx = rawx
            self.sfrbx = sfrbx
        }
    }

    public static func frame(klass: UInt8, id: UInt8, payload: Data) -> Data {
        var body = Data([klass, id, UInt8(payload.count & 0xFF), UInt8((payload.count >> 8) & 0xFF)])
        body.append(payload)
        var sumA: UInt8 = 0
        var sumB: UInt8 = 0
        for byte in body {
            sumA = sumA &+ byte
            sumB = sumB &+ sumA
        }
        var frame = Data([0xB5, 0x62])
        frame.append(body)
        frame.append(sumA)
        frame.append(sumB)
        return frame
    }

    public static func valgetRAM() -> Data {
        var payload = Data([0x00, ramLayerGet, 0x00, 0x00])
        payload.append(key(rateMeasKey))
        payload.append(key(rawxUART1Key))
        payload.append(key(sfrbxUART1Key))
        return frame(klass: valgetClass, id: valgetID, payload: payload)
    }

    public static func valsetRAM(rateMeas: UInt16, rawx: UInt8, sfrbx: UInt8) -> Data {
        var payload = Data([0x00, ramLayerSet, 0x00, 0x00])
        payload.append(key(rateMeasKey))
        payload.append(UInt8(rateMeas & 0xFF))
        payload.append(UInt8((rateMeas >> 8) & 0xFF))
        payload.append(key(rawxUART1Key))
        payload.append(rawx)
        payload.append(key(sfrbxUART1Key))
        payload.append(sfrbx)
        return frame(klass: valsetClass, id: valsetID, payload: payload)
    }

    public static func enableRecording() -> Data {
        valsetRAM(rateMeas: 1000, rawx: 1, sfrbx: 1)
    }

    public static func key(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ])
    }

    public static func valueLength(_ key: UInt32) -> Int {
        switch (key >> 28) & 0x07 {
        case 0x01, 0x02: return 1
        case 0x03: return 2
        case 0x04: return 4
        case 0x05: return 8
        default: return 0
        }
    }

    /// CFG-VALGET の応答から3つの値を読む。足りなければ nil。
    public static func parseGet(_ payload: Data) -> Values? {
        guard payload.count >= 4 else { return nil }
        var index = 4
        var rate: UInt16?
        var rawx: UInt8?
        var sfrbx: UInt8?
        while index + 4 <= payload.count {
            let key = UInt32(payload[index])
                | UInt32(payload[index + 1]) << 8
                | UInt32(payload[index + 2]) << 16
                | UInt32(payload[index + 3]) << 24
            index += 4
            let length = valueLength(key)
            guard length > 0, index + length <= payload.count else { return nil }
            switch key {
            case rateMeasKey where length >= 2:
                rate = UInt16(payload[index]) | UInt16(payload[index + 1]) << 8
            case rawxUART1Key:
                rawx = payload[index]
            case sfrbxUART1Key:
                sfrbx = payload[index]
            default:
                break
            }
            index += length
        }
        guard let rate, let rawx, let sfrbx else { return nil }
        return Values(rateMeas: rate, rawx: rawx, sfrbx: sfrbx)
    }
}

/// VALGET → RAM の VALSET → 観測 → 元へ戻して VALGET で確かめる。戻しは3回まで。
public struct RawCaptureSession: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case reading
        case recording
        case restoring(Int)
        case verifying(Int)
        case finished
    }

    public private(set) var phase: Phase = .idle
    public private(set) var originals: UBXConfig.Values?
    public private(set) var restoreUnverified = false
    public let maxTries = 3

    public init() {}

    public mutating func begin() -> Data {
        originals = nil
        restoreUnverified = false
        phase = .reading
        return UBXConfig.valgetRAM()
    }

    /// 受信機の UBX を渡す。次に書くフレームがあれば返す。
    public mutating func onFrame(_ frame: Data) -> Data? {
        guard frame.count >= 8, frame[0] == 0xB5, frame[1] == 0x62 else { return nil }
        let klass = frame[2]
        let id = frame[3]
        let length = Int(frame[4]) | Int(frame[5]) << 8
        guard frame.count >= 6 + length else { return nil }
        let payload = frame.subdata(in: 6..<(6 + length))
        if klass == UBXConfig.valgetClass && id == UBXConfig.valgetID {
            return onGet(payload)
        }
        if klass == 0x05 && id == 0x01 {
            return onAck()
        }
        if klass == 0x05 && id == 0x00 {
            return onNak()
        }
        return nil
    }

    /// 観測の終わり。元の値が分かっていれば戻す VALSET。
    public mutating func end() -> Data? {
        guard let originals, phase == .recording || phase == .reading else {
            phase = .finished
            return nil
        }
        phase = .restoring(1)
        return UBXConfig.valsetRAM(rateMeas: originals.rateMeas, rawx: originals.rawx, sfrbx: originals.sfrbx)
    }

    private mutating func onGet(_ payload: Data) -> Data? {
        guard let values = UBXConfig.parseGet(payload) else { return nil }
        switch phase {
        case .reading:
            originals = values
            phase = .recording
            return UBXConfig.enableRecording()
        case .verifying(let attempt):
            if values == originals {
                restoreUnverified = false
                phase = .finished
                return nil
            }
            return failRestore(after: attempt)
        case .restoring(let attempt):
            if values == originals {
                restoreUnverified = false
                phase = .finished
                return nil
            }
            return failRestore(after: attempt)
        default:
            return nil
        }
    }

    private mutating func onAck() -> Data? {
        guard case .restoring(let attempt) = phase else { return nil }
        phase = .verifying(attempt)
        return UBXConfig.valgetRAM()
    }

    /// VALSET が拒否された。戻しの回数に数え、3 回で打ち切る。
    private mutating func onNak() -> Data? {
        guard case .restoring(let attempt) = phase else { return nil }
        return failRestore(after: attempt)
    }

    private mutating func failRestore(after attempt: Int) -> Data? {
        guard attempt < maxTries, let originals else {
            restoreUnverified = true
            phase = .finished
            return nil
        }
        phase = .restoring(attempt + 1)
        return UBXConfig.valsetRAM(rateMeas: originals.rateMeas, rawx: originals.rawx, sfrbx: originals.sfrbx)
    }
}

public struct RawObsSidecar: Codable, Equatable, Sendable {
    public var pointName: String
    public var fileName: String
    public var startedAt: String
    public var solution: String
    public var pdop: Double?
    public var hdop: Double?
    public var vdop: Double?
    public var tiltMedianDegrees: Double?
    public var tiltMeanDegrees: Double?
    public var tiltMaxDegrees: Double?
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var restoreNote: String?

    public init(
        pointName: String,
        fileName: String,
        startedAt: String,
        solution: String,
        pdop: Double?,
        hdop: Double?,
        vdop: Double?,
        tiltMedianDegrees: Double?,
        tiltMeanDegrees: Double?,
        tiltMaxDegrees: Double?,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        restoreNote: String?
    ) {
        self.pointName = pointName
        self.fileName = fileName
        self.startedAt = startedAt
        self.solution = solution
        self.pdop = pdop
        self.hdop = hdop
        self.vdop = vdop
        self.tiltMedianDegrees = tiltMedianDegrees
        self.tiltMeanDegrees = tiltMeanDegrees
        self.tiltMaxDegrees = tiltMaxDegrees
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.restoreNote = restoreNote
    }
}

public enum RawObsFile {
    public static let restoreUnverified = "戻し未確認"

    /// チェックサムが通った UBX を、拡張子 ubx のファイルの末尾へ足す。
    public static func append(_ frame: Data, base: URL) {
        let url = base.appendingPathExtension("ubx")
        if !FileManager.default.fileExists(atPath: url.path) {
            _ = FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: frame)
    }

    public static func baseName(point: String, started: Date) -> String {
        let safe = point.map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" { return character }
            return "_"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return "\(String(safe))_\(formatter.string(from: started))"
    }
}
