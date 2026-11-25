import Foundation

/// fw 3.0 の 10 バイトフレームと、FFF1 に混ざる UBX / NMEA / 応答。
/// デバイスの設定は書かない。cmd 7、8、10、12、13〜15、23 以上、u-blox の CFG-RST は作らない。
public enum ViDocProtocol {
    public static let trailer = Data([0x3C, 0x3B, 0x3D, 0x01, 0x03, 0x02])

    /// 許可したコマンドだけ返す。新しい手順は 10 バイト、従来はトレーラ無しの 4 バイト。
    public static func frame(command: UInt8, payload: UInt8, trailed: Bool) -> Data? {
        guard allowed(command: command, payload: payload) else { return nil }
        let sum = UInt8(0x55) &+ command &+ payload
        var data = Data([0x55, command, payload, sum])
        if trailed { data.append(trailer) }
        return data
    }

    public static func switchFrame() -> Data? {
        frame(command: 0x16, payload: 0x01, trailed: true)
    }

    public static func versionFrame() -> Data? {
        frame(command: 0x00, payload: 0x01, trailed: true)
    }

    public enum IMU: UInt8 {
        case angle = 0x00
        case accel = 0x01
        case mag = 0x04
        case temp = 0x06
    }

    public static func imu(_ kind: IMU, trailed: Bool = true) -> Data? {
        frame(command: 0x0B, payload: kind.rawValue, trailed: trailed)
    }

    public enum LaserSpeed: UInt8 {
        case slow = 1
        case fast = 2
        case auto = 3
    }

    /// position は下 0、前 16。mode は 1 / 2 / 3。payload は秒。
    public static func range(down: Bool, speed: LaserSpeed, seconds: UInt8, trailed: Bool) -> Data? {
        let command = (down ? UInt8(0) : 16) | speed.rawValue
        return frame(command: command, payload: seconds, trailed: trailed)
    }

    public static func lightOn(down: Bool, trailed: Bool) -> Data? {
        frame(command: down ? 4 : 20, payload: 0, trailed: trailed)
    }

    /// 新しい手順は cmd 5 にトレーラを足して、下も前も消す。
    /// 従来はトレーラなしの 4 バイト。下は 5、前は 16+5。
    public static func lightOff(down: Bool = true, trailed: Bool) -> Data? {
        let command: UInt8 = trailed ? 5 : (down ? 5 : 21)
        return frame(command: command, payload: 0, trailed: trailed)
    }

    public static func laserStatus(trailed: Bool) -> Data? {
        frame(command: 9, payload: 0, trailed: trailed)
    }

    public static func checksum(of bytes: Data) -> UInt8 {
        bytes.reduce(0) { $0 &+ $1 }
    }

    public static func checksumMatches(_ frame: Data) -> Bool {
        guard frame.count >= 2, let last = frame.last else { return false }
        return checksum(of: frame.dropLast()) == last
    }

    private static func allowed(command: UInt8, payload: UInt8) -> Bool {
        switch command {
        case 0x00: return payload == 0x01
        case 1, 2, 3, 17, 18, 19: return (1...30).contains(payload)
        case 4, 5, 9, 20, 21: return payload == 0
        case 0x0B: return IMU(rawValue: payload) != nil
        case 0x16: return payload == 0x01
        default: return false
        }
    }
}

public enum ViDocBinaryExpect: Equatable, Sendable {
    case none
    case version
    case range
}

public enum ViDocReply: Equatable, Sendable {
    case version(label: String)
    case range(startMillimetres: Int, endMillimetres: Int, distanceMillimetres: Int, quality: Int)
    case angle(pitchDegrees: Double, rollDegrees: Double)
    case accel(x: Int, y: Int, z: Int)
    case gyro(x: Double, y: Double, z: Double)
    case gyroRaw(x: Int, y: Int, z: Int)
    case mag(x: Int, y: Int, z: Int)
    case temperature(celsius: Double)
    case calibration(raw: UInt8)
    case battery(percent: Int)
    case hardwareID(Data)
    case serial(Data)
    case laserStatus(raw: UInt8)
    case switched

    public static func decode(_ frame: Data, expect: ViDocBinaryExpect) -> ViDocReply? {
        guard ViDocProtocol.checksumMatches(frame) else { return nil }
        let type = frame[frame.startIndex]
        switch type {
        case 0x01 where frame.count == 8 && expect != .range:
            let sw0 = frame[frame.startIndex + 1]
            let sw1 = frame[frame.startIndex + 2]
            let sw2 = frame[frame.startIndex + 3]
            let build = frame[frame.startIndex + 4]
            let hw0 = frame[frame.startIndex + 5]
            let hw1 = frame[frame.startIndex + 6]
            return .version(label: "\(sw0).\(sw1).\(sw2) build \(build) hw \(hw0).\(hw1)")
        case 0x01 where frame.count == 10 && expect != .version:
            return .range(
                startMillimetres: int16BE(frame, 1),
                endMillimetres: int16BE(frame, 3),
                distanceMillimetres: uint16BE(frame, 5),
                quality: uint16BE(frame, 7)
            )
        case 0xB0 where frame.count == 10:
            return .angle(
                pitchDegrees: Double(floatLE(frame, 1)),
                rollDegrees: Double(floatLE(frame, 5))
            )
        case 0xB1 where frame.count == 8:
            return .accel(x: int16BE(frame, 1), y: int16BE(frame, 3), z: int16BE(frame, 5))
        case 0xB2 where frame.count == 14:
            return .gyro(
                x: Double(floatLE(frame, 1)),
                y: Double(floatLE(frame, 5)),
                z: Double(floatLE(frame, 9))
            )
        case 0xB3 where frame.count == 8:
            return .gyroRaw(x: int16BE(frame, 1), y: int16BE(frame, 3), z: int16BE(frame, 5))
        case 0xB4 where frame.count == 8:
            return .mag(x: int16BE(frame, 1), y: int16BE(frame, 3), z: int16BE(frame, 5))
        case 0xB6 where frame.count == 4:
            return .temperature(celsius: Double(int16BE(frame, 1)) / 10)
        case 0xB7 where frame.count == 3:
            return .calibration(raw: frame[frame.startIndex + 1])
        case 0x02 where frame.count == 3:
            return .battery(percent: Int(frame[frame.startIndex + 1]))
        case 0x03 where frame.count == 10:
            return .hardwareID(Data(frame.dropFirst().dropLast()))
        case 0x06 where frame.count == 9:
            return .serial(Data(frame.dropFirst().dropLast()))
        case 0x09 where frame.count == 3:
            return .laserStatus(raw: frame[frame.startIndex + 1])
        case 0x16 where frame.count == 3 && frame[frame.startIndex + 1] == 0x01:
            return .switched
        default:
            return nil
        }
    }

    private static func int16BE(_ data: Data, _ offset: Int) -> Int {
        let index = data.startIndex + offset
        let raw = UInt16(data[index]) << 8 | UInt16(data[index + 1])
        return Int(Int16(bitPattern: raw))
    }

    private static func uint16BE(_ data: Data, _ offset: Int) -> Int {
        let index = data.startIndex + offset
        return Int(UInt16(data[index]) << 8 | UInt16(data[index + 1]))
    }

    private static func floatLE(_ data: Data, _ offset: Int) -> Float {
        let index = data.startIndex + offset
        let bits = UInt32(data[index])
            | UInt32(data[index + 1]) << 8
            | UInt32(data[index + 2]) << 16
            | UInt32(data[index + 3]) << 24
        return Float(bitPattern: bits)
    }
}

public enum LaserRangeBatch {
    public static let replyLimit = 7

    /// 0〜600 は良好、601〜1000 は可。距離 0 と 0xFFFF、品質 1000 超、下 40 m 以上、前 20 m 以上は使わない。
    public static func usable(distanceMillimetres: Int, quality: Int, down: Bool) -> Bool {
        if distanceMillimetres == 0 || distanceMillimetres == 0xFFFF || quality > 1000 { return false }
        let meters = Double(distanceMillimetres) / 1000
        if down, meters >= 40 { return false }
        if !down, meters >= 20 { return false }
        if quality < 0 { return false }
        return quality <= 1000
    }

    /// 良好と可だけを残した距離の中央値（m）。無ければ nil（測れず）。
    public static func medianMeters(_ samples: [(distanceMillimetres: Int, quality: Int)], down: Bool) -> Double? {
        let kept = samples.compactMap { sample -> Double? in
            guard usable(distanceMillimetres: sample.distanceMillimetres, quality: sample.quality, down: down) else { return nil }
            return Double(sample.distanceMillimetres)
        }
        guard let median = TiltMath.median(kept) else { return nil }
        return median / 1000
    }
}

public struct ViDocGNSS: Equatable, Sendable {
    public var satelliteCount: Int?
    public var pdop: Double?
    public var hdop: Double?
    public var vdop: Double?

    public init() {}
}

public enum ViDocStreamEvent: Equatable, Sendable {
    case text(String)
    case reply(ViDocReply)
}

/// FFF1 をバイトのまま読む。UBX は長さフィールドで丸ごと飛ばし、NAV-PVT は止めない。
public struct ViDocStreamParser {
    public private(set) var gnss = ViDocGNSS()
    public var expect: ViDocBinaryExpect = .none
    public var onUBX: ((Data, UInt8, UInt8) -> Void)?
    private var buffer = Data()

    public init() {}

    public mutating func feed(_ data: Data) -> [ViDocStreamEvent] {
        guard !data.isEmpty else { return [] }
        buffer.append(data)
        var events: [ViDocStreamEvent] = []
        while !buffer.isEmpty {
            if buffer.count > 16_384 { buffer.removeFirst(buffer.count - 8_192) }
            switch next(&events) {
            case .again: continue
            case .wait: return events
            case .skip:
                buffer.removeFirst()
            }
        }
        return events
    }

    private enum Move { case again, wait, skip }

    private mutating func next(_ events: inout [ViDocStreamEvent]) -> Move {
        if let move = takeUBX() { return move }
        if let move = takeText(&events) { return move }
        if let move = takeReply(&events) { return move }
        return .skip
    }

    private mutating func takeUBX() -> Move? {
        guard buffer.count >= 2, buffer[buffer.startIndex] == 0xB5, buffer[buffer.startIndex + 1] == 0x62 else { return nil }
        guard buffer.count >= 6 else { return .wait }
        let length = Int(buffer[buffer.startIndex + 4]) | (Int(buffer[buffer.startIndex + 5]) << 8)
        guard length <= 2048 else {
            buffer.removeFirst()
            return .again
        }
        let total = 6 + length + 2
        guard buffer.count >= total else { return .wait }
        let frame = Data(buffer.prefix(total))
        guard Self.ubxChecksum(frame) else {
            // 同期語ごと捨てて、次の B5 62 を探す。1 バイトだけ戻すと 0x62 が文字として後続を飲む。
            buffer.removeFirst(min(2, buffer.count))
            return .again
        }
        rememberUBX(frame, payloadLength: length)
        onUBX?(frame, frame[frame.startIndex + 2], frame[frame.startIndex + 3])
        buffer.removeFirst(total)
        return .again
    }

    private mutating func rememberUBX(_ frame: Data, payloadLength: Int) {
        // クラス 0x01 の NAV-PVT / NAV-DOP を読むだけ。CFG は送らない。
        let klass = frame[frame.startIndex + 2]
        let id = frame[frame.startIndex + 3]
        let payload = frame.dropFirst(6).prefix(payloadLength)
        guard klass == 0x01 else { return }
        if id == 0x07, payload.count > 23 {
            gnss.satelliteCount = Int(payload[payload.startIndex + 23])
        }
        if id == 0x04, payload.count >= 14 {
            gnss.pdop = Self.u16LE(payload, 6) / 100
            gnss.vdop = Self.u16LE(payload, 10) / 100
            gnss.hdop = Self.u16LE(payload, 12) / 100
        }
    }

    private mutating func takeText(_ events: inout [ViDocStreamEvent]) -> Move? {
        let first = buffer[buffer.startIndex]
        let isDollar = first == 0x24
        let isSTX = first == 0x02
        let isPrintable = first >= 0x20 && first < 0x7F
        guard isDollar || isSTX || isPrintable else { return nil }
        if isSTX {
            guard buffer.count >= 4 else { return .wait }
            let fourth = buffer[buffer.startIndex + 3]
            let continues = fourth >= 0x20 && fourth < 0x7F && fourth != 0x24
            guard continues else { return nil }
        }
        if let end = buffer.firstIndex(where: { byte in
            byte == 0x0A || byte == 0x0D || (isSTX && byte == 0x03)
        }) {
            let chunk = Data(buffer[buffer.startIndex...end])
            buffer.removeSubrange(buffer.startIndex...end)
            if let extra = buffer.first, extra == 0x0A || extra == 0x0D { buffer.removeFirst() }
            if let text = String(data: chunk, encoding: .ascii)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                events.append(.text(text))
            }
            return .again
        }
        if buffer.count > 400 {
            buffer.removeFirst()
            return .again
        }
        return .wait
    }

    private mutating func takeReply(_ events: inout [ViDocStreamEvent]) -> Move? {
        let type = buffer[buffer.startIndex]
        let lengths = Self.lengths(for: type, expect: expect)
        guard let longest = lengths.max() else { return nil }
        for length in lengths where buffer.count >= length {
            let slice = Data(buffer.prefix(length))
            guard ViDocProtocol.checksumMatches(slice), let reply = ViDocReply.decode(slice, expect: expect) else { continue }
            buffer.removeFirst(length)
            events.append(.reply(reply))
            return .again
        }
        if buffer.count < longest { return .wait }
        return nil
    }

    private static func lengths(for type: UInt8, expect: ViDocBinaryExpect) -> [Int] {
        switch type {
        case 0x01:
            switch expect {
            case .version: return [8]
            case .range: return [10]
            case .none: return [8, 10]
            }
        case 0x02, 0x09, 0x16, 0xB7: return [3]
        case 0x03: return [10]
        case 0x06: return [9]
        case 0xB0: return [10]
        case 0xB1, 0xB3, 0xB4: return [8]
        case 0xB2: return [14]
        case 0xB6: return [4]
        default: return []
        }
    }

    private static func ubxChecksum(_ frame: Data) -> Bool {
        guard frame.count >= 8 else { return false }
        var ckA: UInt8 = 0
        var ckB: UInt8 = 0
        for byte in frame.dropFirst(2).dropLast(2) {
            ckA = ckA &+ byte
            ckB = ckB &+ ckA
        }
        return frame[frame.index(frame.endIndex, offsetBy: -2)] == ckA && frame[frame.index(frame.endIndex, offsetBy: -1)] == ckB
    }

    private static func u16LE(_ data: Data, _ offset: Int) -> Double {
        let index = data.startIndex + offset
        return Double(UInt16(data[index]) | UInt16(data[index + 1]) << 8)
    }
}

/// `nmea` のあと cmd 22 を 1 回送り、1 秒で 1 回だけやり直す。応答が無ければ従来モード。
public struct ViDocCommandPlan: Equatable, Sendable {
    public enum Mode: Equatable, Sendable { case probing, modern, legacy }
    public private(set) var mode: Mode = .probing
    public private(set) var expect: ViDocBinaryExpect = .none
    public private(set) var firmwareLabel: String?
    public private(set) var hasProbed = false
    public private(set) var lightIsOn = false
    public var observing = false
    /// true は下、false は前。点灯した側だけ測る。
    public private(set) var beamIsDown = true
    /// cmd 9 の応答。0 消灯、1 下、2 前。未受信は nil。
    public private(set) var reportedBeam: UInt8?
    public enum Lamp: Equatable, Sendable { case off, lower, front, ranging }
    public var lamp: Lamp {
        if phase == .range { return .ranging }
        if let reportedBeam {
            switch reportedBeam {
            case 1: return .lower
            case 2: return .front
            default: return .off
            }
        }
        if lightIsOn { return beamIsDown ? .lower : .front }
        return .off
    }
    public enum LaserReading: Equatable, Sendable {
        case meters(Double)
        case failed
    }
    private var pendingLaser: LaserReading?

    private var switchAttempt = 0
    private var deadline: TimeInterval?
    private var phase: Phase = .idle
    private var laserOffArmed = false
    private var rangingDown = true
    private var lightOnAt: TimeInterval?
    private var rangeHoldUntil: TimeInterval?
    private var heldRangeSeconds: UInt8?
    private struct RangeSample: Equatable, Sendable {
        var distanceMillimetres: Int
        var quality: Int
    }
    private var rangeSamples: [RangeSample] = []
    private var queuedSeconds: UInt8?
    private enum Phase: Equatable, Sendable { case idle, switchProbe, version, angle, accel, mag, temp, range }

    public init() {}

    public mutating func noteRestart() {
        self = ViDocCommandPlan()
    }

    public mutating func nmeaWasSent(at now: TimeInterval) -> [Data] {
        guard switchAttempt == 0 else { return [] }
        return beginSwitch(attempt: 1, at: now)
    }

    public mutating func tick(at now: TimeInterval) -> [Data] {
        let laser = serviceLaser(at: now)
        guard let deadline, now + 1e-9 >= deadline else { return laser }
        switch phase {
        case .switchProbe:
            if switchAttempt < 2 { return laser + beginSwitch(attempt: switchAttempt + 1, at: now) }
            mode = .legacy
            phase = .idle
            expect = .none
            self.deadline = nil
            return laser + takeQueuedLaser(at: now)
        case .version:
            return laser + sendAngle(at: now)
        case .angle: return laser + (observing ? sendAngle(at: now) : sendAccel(at: now))
        case .accel: return laser + sendMag(at: now)
        case .mag: return laser + sendTemp(at: now)
        case .temp: return laser + sendAngle(at: now)
        case .range: return laser + finishRange(at: now)
        case .idle:
            self.deadline = nil
            return laser
        }
    }

    /// 下向きの赤い点。測距は混ぜない。
    public mutating func lightDown(at now: TimeInterval) -> [Data] {
        light(down: true, at: now)
    }

    public mutating func lightFront(at now: TimeInterval) -> [Data] {
        light(down: false, at: now)
    }

    private mutating func light(down: Bool, at now: TimeInterval) -> [Data] {
        guard mode != .probing, let frame = ViDocProtocol.lightOn(down: down, trailed: mode == .modern) else { return [] }
        lightIsOn = true
        beamIsDown = down
        reportedBeam = down ? 1 : 2
        lightOnAt = now
        return [frame]
    }

    public mutating func receive(_ reply: ViDocReply, at now: TimeInterval) -> [Data] {
        switch reply {
        case .switched:
            mode = .modern
            return sendVersion(at: now)
        case .version(let label):
            firmwareLabel = label
            guard mode == .modern else { return [] }
            return sendAngle(at: now)
        case .angle where mode == .modern && phase != .range:
            return observing ? sendAngle(at: now) : sendAccel(at: now)
        case .accel where mode == .modern && phase != .range:
            return sendMag(at: now)
        case .mag where mode == .modern && phase != .range:
            return sendTemp(at: now)
        case .temperature where mode == .modern && phase != .range:
            return sendAngle(at: now)
        case .laserStatus(let raw):
            if raw <= 2 { reportedBeam = raw }
            return []
        case .range(_, _, let distance, let quality):
            guard phase == .range, laserOffArmed, rangeSamples.count < LaserRangeBatch.replyLimit else { return [] }
            rangeSamples.append(RangeSample(distanceMillimetres: distance, quality: quality))
            guard rangeSamples.count >= LaserRangeBatch.replyLimit else { return [] }
            return finishRange(at: now)
        default:
            return []
        }
    }

    public mutating func takeLaserReading() -> LaserReading? {
        defer { pendingLaser = nil }
        return pendingLaser
    }

    /// 点灯から 0.5 秒以上あとに、測距フレームだけを出す。点灯と測距を続けては出さない。
    public mutating func measureDown(seconds: UInt8, at now: TimeInterval) -> [Data] {
        measure(down: true, seconds: seconds, at: now)
    }

    public mutating func measureFront(seconds: UInt8, at now: TimeInterval) -> [Data] {
        measure(down: false, seconds: seconds, at: now)
    }

    private mutating func measure(down: Bool, seconds: UInt8, at now: TimeInterval) -> [Data] {
        let seconds = min(max(seconds, 1), 30)
        guard lightIsOn, beamIsDown == down else { return [] }
        guard mode != .probing else {
            queuedSeconds = seconds
            return []
        }
        return beginRangeIfReady(seconds: seconds, at: now)
    }

    private mutating func beginSwitch(attempt: Int, at now: TimeInterval) -> [Data] {
        guard let frame = ViDocProtocol.switchFrame() else { return [] }
        switchAttempt = attempt
        hasProbed = true
        phase = .switchProbe
        expect = .none
        deadline = now + 1
        return [frame]
    }

    private mutating func sendVersion(at now: TimeInterval) -> [Data] {
        guard mode == .modern, let frame = ViDocProtocol.versionFrame() else { return [] }
        phase = .version
        expect = .version
        deadline = now + 1
        return [frame]
    }

    private mutating func sendAngle(at now: TimeInterval) -> [Data] {
        guard mode == .modern, let frame = ViDocProtocol.imu(.angle) else { return [] }
        phase = .angle
        expect = .none
        deadline = now + 1
        return [frame]
    }

    private mutating func sendAccel(at now: TimeInterval) -> [Data] {
        guard let frame = ViDocProtocol.imu(.accel) else { return [] }
        phase = .accel
        deadline = now + 1
        return [frame]
    }

    private mutating func sendMag(at now: TimeInterval) -> [Data] {
        guard let frame = ViDocProtocol.imu(.mag) else { return [] }
        phase = .mag
        deadline = now + 1
        return [frame]
    }

    private mutating func sendTemp(at now: TimeInterval) -> [Data] {
        guard let frame = ViDocProtocol.imu(.temp) else { return [] }
        phase = .temp
        deadline = now + 1
        return [frame]
    }

    private mutating func takeQueuedLaser(at now: TimeInterval) -> [Data] {
        guard let seconds = queuedSeconds else { return [] }
        queuedSeconds = nil
        return beginRangeIfReady(seconds: seconds, at: now)
    }

    private mutating func beginRangeIfReady(seconds: UInt8, at now: TimeInterval) -> [Data] {
        guard lightIsOn, let lightOnAt else { return [] }
        if now + 1e-9 < lightOnAt + 0.5 {
            heldRangeSeconds = seconds
            rangeHoldUntil = lightOnAt + 0.5
            return []
        }
        heldRangeSeconds = nil
        rangeHoldUntil = nil
        return laserPair(seconds: seconds, at: now)
    }

    private mutating func serviceLaser(at now: TimeInterval) -> [Data] {
        if let hold = rangeHoldUntil, now + 1e-9 >= hold, let seconds = heldRangeSeconds, phase != .range {
            rangeHoldUntil = nil
            heldRangeSeconds = nil
            return laserPair(seconds: seconds, at: now)
        }
        if lightIsOn, phase != .range, let onAt = lightOnAt, now + 1e-9 >= onAt + 30 {
            return extinguish()
        }
        return []
    }

    private mutating func extinguish() -> [Data] {
        lightIsOn = false
        lightOnAt = nil
        reportedBeam = 0
        rangeHoldUntil = nil
        heldRangeSeconds = nil
        guard let off = ViDocProtocol.lightOff(down: beamIsDown, trailed: mode == .modern) else { return [] }
        return [off]
    }

    private mutating func laserPair(seconds: UInt8, at now: TimeInterval) -> [Data] {
        let trailed = mode == .modern
        guard let down = ViDocProtocol.range(down: beamIsDown, speed: .auto, seconds: seconds, trailed: trailed) else { return [] }
        phase = .range
        expect = .range
        laserOffArmed = true
        rangingDown = beamIsDown
        rangeSamples.removeAll(keepingCapacity: true)
        pendingLaser = nil
        queuedSeconds = nil
        deadline = now + Double(seconds) + 2
        return [down]
    }

    private mutating func finishRange(at now: TimeInterval) -> [Data] {
        let samples = rangeSamples.map { (distanceMillimetres: $0.distanceMillimetres, quality: $0.quality) }
        pendingLaser = LaserRangeBatch.medianMeters(samples, down: rangingDown).map(LaserReading.meters) ?? .failed
        rangeSamples.removeAll(keepingCapacity: false)
        return sendLaserOff(at: now)
    }

    private mutating func sendLaserOff(at now: TimeInterval) -> [Data] {
        guard laserOffArmed else {
            phase = .idle
            expect = .none
            deadline = nil
            return mode == .modern ? sendAngle(at: now) : []
        }
        laserOffArmed = false
        lightIsOn = false
        lightOnAt = nil
        reportedBeam = 0
        phase = .idle
        expect = .none
        deadline = nil
        let off = ViDocProtocol.lightOff(down: beamIsDown, trailed: mode == .modern)
        var frames = off.map { [$0] } ?? []
        if mode == .modern { frames.append(contentsOf: sendAngle(at: now)) }
        return frames
    }
}

public enum TiltMath {
    /// pitch と roll（度）から鉛直までの角。加速度が無いときの気泡。
    public static func fromPitchRoll(pitchDegrees: Double, rollDegrees: Double) -> Double {
        let pitch = pitchDegrees * .pi / 180
        let roll = rollDegrees * .pi / 180
        let cosine = min(1, max(-1, cos(pitch) * cos(roll)))
        return acos(cosine) * 180 / .pi
    }

    /// 加速度の |az| / |a|。16384 = 1 g の生値のままでも比は同じ。
    public static func fromAcceleration(x: Double, y: Double, z: Double) -> Double? {
        let magnitude = (x * x + y * y + z * z).squareRoot()
        guard magnitude > 0, x.isFinite, y.isFinite, z.isFinite else { return nil }
        let cosine = min(1, max(0, abs(z) / magnitude))
        return acos(cosine) * 180 / .pi
    }

    public struct Stats: Equatable, Sendable {
        public var median: Double
        public var mean: Double
        public var maximum: Double
    }

    public static func median(_ samples: [Double]) -> Double? {
        let sorted = samples.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    /// 中央値 ± 3×MAD の外を捨て、残りの平均と最大を返す。門は区間の中央値。
    public static func stats(_ samples: [Double]) -> Stats? {
        guard let center = median(samples) else { return nil }
        let deviations = samples.map { abs($0 - center) }
        let mad = median(deviations) ?? 0
        let limit = 3 * mad
        let kept = samples.filter { $0.isFinite && abs($0 - center) <= limit + 1e-9 }
        let used = kept.isEmpty ? [center] : kept
        let mean = used.reduce(0, +) / Double(used.count)
        let maximum = used.max() ?? center
        return Stats(median: center, mean: mean, maximum: maximum)
    }
}
