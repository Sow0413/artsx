import Foundation

/// 転倒と強い衝撃。確定したあと周囲へ知らせる。緊急通報の代わりではない。
public enum FallKind: String, Codable, Sendable, Equatable {
    case fall
    case impact

    public var label: String {
        switch self {
        case .fall: return "転倒"
        case .impact: return "衝撃"
        }
    }
}

public enum FallPhase: String, Sendable, Equatable {
    case idle
    case confirmingStill
    case awaitingCancel
    case confirmed
    case cancelled
}

public enum FallSignal: Sendable, Equatable {
    /// 静止が続いた。本人が取り消せる。
    case awaitingCancel(FallKind)
    /// 取り消されなかった。
    case confirmed(FallKind)
    case cancelled
}

/// 加速度の閾値と、誤検知を落とすための静止時間。取り消しは10秒で固定。
public struct FallLimits: Codable, Equatable, Sendable {
    public var impactG: Double
    public var freefallG: Double
    public var stillG: Double
    public var stillSeconds: TimeInterval
    public var cancelSeconds: TimeInterval
    public var freefallLeadSeconds: TimeInterval
    public var quietSeconds: TimeInterval
    public var sampleGapSeconds: TimeInterval

    public static let defaultImpactG = 3.0
    public static let defaultFreefallG = 0.4
    public static let defaultStillG = 0.35
    public static let defaultStillSeconds: TimeInterval = 2
    public static let defaultCancelSeconds: TimeInterval = 10
    public static let defaultFreefallLeadSeconds: TimeInterval = 1.5
    public static let defaultQuietSeconds: TimeInterval = 60
    public static let defaultSampleGapSeconds: TimeInterval = 0.5

    public static let standard = FallLimits(
        impactG: defaultImpactG,
        freefallG: defaultFreefallG,
        stillG: defaultStillG,
        stillSeconds: defaultStillSeconds,
        cancelSeconds: defaultCancelSeconds,
        freefallLeadSeconds: defaultFreefallLeadSeconds,
        quietSeconds: defaultQuietSeconds,
        sampleGapSeconds: defaultSampleGapSeconds
    )

    public init(
        impactG: Double,
        freefallG: Double,
        stillG: Double,
        stillSeconds: TimeInterval,
        cancelSeconds: TimeInterval,
        freefallLeadSeconds: TimeInterval,
        quietSeconds: TimeInterval,
        sampleGapSeconds: TimeInterval
    ) {
        self.impactG = impactG
        self.freefallG = freefallG
        self.stillG = stillG
        self.stillSeconds = stillSeconds
        self.cancelSeconds = cancelSeconds
        self.freefallLeadSeconds = freefallLeadSeconds
        self.quietSeconds = quietSeconds
        self.sampleGapSeconds = sampleGapSeconds
    }

    public static func resolved(
        impactG: Double? = nil,
        freefallG: Double? = nil,
        stillG: Double? = nil,
        stillSeconds: Double? = nil,
        freefallLeadSeconds: Double? = nil,
        quietSeconds: Double? = nil,
        sampleGapSeconds: Double? = nil
    ) -> FallLimits {
        let impact = clamp(impactG, min: 1.5, max: 8, fallback: defaultImpactG)
        var still = clamp(stillG, min: 0.15, max: 1.2, fallback: defaultStillG)
        if still >= impact {
            still = min(defaultStillG, impact * 0.5)
        }
        return FallLimits(
            impactG: impact,
            freefallG: clamp(freefallG, min: 0.15, max: 0.8, fallback: defaultFreefallG),
            stillG: still,
            stillSeconds: clamp(stillSeconds, min: 1, max: 5, fallback: defaultStillSeconds),
            cancelSeconds: defaultCancelSeconds,
            freefallLeadSeconds: clamp(freefallLeadSeconds, min: 0.5, max: 3, fallback: defaultFreefallLeadSeconds),
            quietSeconds: clamp(quietSeconds, min: 0, max: 180, fallback: defaultQuietSeconds),
            sampleGapSeconds: clamp(sampleGapSeconds, min: 0.2, max: 1, fallback: defaultSampleGapSeconds)
        )
    }

    private static func clamp(_ value: Double?, min lower: Double, max upper: Double, fallback: Double) -> Double {
        guard let value, value.isFinite else { return fallback }
        if value < lower { return lower }
        if value > upper { return upper }
        return value
    }
}

/// 重力を除いた加速度と、重力を含む加速度。単位は g。
public struct FallSample: Equatable, Sendable {
    public var at: Date
    public var userG: Double
    public var totalG: Double?

    public init(at: Date, userG: Double, totalG: Double? = nil) {
        self.at = at
        self.userG = userG
        self.totalG = totalG
    }
}

public struct FallSnapshot: Equatable, Sendable {
    public var phase: FallPhase
    public var kind: FallKind?
    public var cancelRemaining: TimeInterval?

    public init(phase: FallPhase, kind: FallKind?, cancelRemaining: TimeInterval?) {
        self.phase = phase
        self.kind = kind
        self.cancelRemaining = cancelRemaining
    }
}

/// 衝撃のあと静止が続き、10秒取り消されなければ確定する。サンプルの時刻は外から渡す。
public struct FallDetector: Sendable {
    public private(set) var limits: FallLimits
    public private(set) var phase: FallPhase = .idle
    public private(set) var kind: FallKind?
    private var freefallAt: Date?
    private var stillSince: Date?
    private var lastQuietAt: Date?
    private var cancelDeadline: Date?
    private var quietUntil: Date?
    private var lastSampleAt: Date?

    public init(limits: FallLimits = .standard) {
        self.limits = limits
    }

    public mutating func updateLimits(_ limits: FallLimits) {
        self.limits = limits
    }

    public func snapshot(at date: Date) -> FallSnapshot {
        let remaining: TimeInterval?
        if phase == .awaitingCancel, let cancelDeadline {
            remaining = max(0, cancelDeadline.timeIntervalSince(date))
        } else {
            remaining = nil
        }
        return FallSnapshot(phase: phase, kind: kind, cancelRemaining: remaining)
    }

    @discardableResult
    public mutating func ingest(_ sample: FallSample) -> FallSignal? {
        guard sample.userG.isFinite, sample.at.timeIntervalSince1970.isFinite else { return nil }
        if let lastSampleAt, sample.at < lastSampleAt { return nil }
        lastSampleAt = sample.at
        if let total = sample.totalG, total.isFinite, total <= limits.freefallG {
            freefallAt = sample.at
        }
        if phase == .awaitingCancel {
            return tick(at: sample.at)
        }
        if let quietUntil, sample.at < quietUntil {
            return nil
        }
        guard isImpact(sample) || phase == .confirmingStill else { return nil }
        if isImpact(sample) {
            beginStillness(at: sample.at)
            return nil
        }
        guard sample.userG <= limits.stillG else {
            abandon()
            return nil
        }
        return noteStill(at: sample.at)
    }

    /// 時計がすでに静止まで見た転倒。`immediate` は、本人が時計側で転倒を認めたとき。
    @discardableResult
    public mutating func noteExternal(kind: FallKind, detectedAt: Date, now: Date, immediate: Bool) -> FallSignal? {
        guard detectedAt.timeIntervalSince1970.isFinite, now.timeIntervalSince1970.isFinite else { return nil }
        if phase == .awaitingCancel {
            guard immediate else { return nil }
            return finish(at: now, kind: kind)
        }
        if !immediate, let quietUntil, now < quietUntil {
            return nil
        }
        let deadline = detectedAt.addingTimeInterval(limits.cancelSeconds)
        if immediate || now >= deadline {
            return finish(at: now, kind: kind)
        }
        return beginCancel(kind: kind, deadline: deadline)
    }

    @discardableResult
    public mutating func cancel(at date: Date) -> FallSignal? {
        guard phase == .awaitingCancel else { return nil }
        if let cancelDeadline, date >= cancelDeadline {
            return finish(at: date, kind: kind ?? .fall)
        }
        phase = .cancelled
        cancelDeadline = nil
        quietUntil = date.addingTimeInterval(limits.quietSeconds)
        kind = nil
        return .cancelled
    }

    @discardableResult
    public mutating func tick(at date: Date) -> FallSignal? {
        guard phase == .awaitingCancel, let cancelDeadline else { return nil }
        guard date >= cancelDeadline else { return nil }
        return finish(at: date, kind: kind ?? .fall)
    }

    private func isImpact(_ sample: FallSample) -> Bool {
        if sample.userG >= limits.impactG { return true }
        if let total = sample.totalG, total.isFinite, total >= limits.impactG { return true }
        return false
    }

    private mutating func beginStillness(at date: Date) {
        phase = .confirmingStill
        kind = classify(at: date)
        stillSince = nil
        lastQuietAt = nil
        cancelDeadline = nil
    }

    private func classify(at date: Date) -> FallKind {
        guard let freefallAt else { return .impact }
        let lead = date.timeIntervalSince(freefallAt)
        if lead >= 0, lead <= limits.freefallLeadSeconds { return .fall }
        return .impact
    }

    private mutating func noteStill(at date: Date) -> FallSignal? {
        if let lastQuietAt, date.timeIntervalSince(lastQuietAt) > limits.sampleGapSeconds {
            stillSince = date
            self.lastQuietAt = date
            return nil
        }
        if stillSince == nil {
            stillSince = date
        }
        lastQuietAt = date
        guard let stillSince, date.timeIntervalSince(stillSince) >= limits.stillSeconds else { return nil }
        return beginCancel(kind: kind ?? .impact, deadline: date.addingTimeInterval(limits.cancelSeconds))
    }

    private mutating func beginCancel(kind: FallKind, deadline: Date) -> FallSignal {
        self.kind = kind
        phase = .awaitingCancel
        cancelDeadline = deadline
        stillSince = nil
        lastQuietAt = nil
        return .awaitingCancel(kind)
    }

    private mutating func finish(at date: Date, kind: FallKind) -> FallSignal {
        self.kind = kind
        phase = .confirmed
        cancelDeadline = nil
        stillSince = nil
        quietUntil = date.addingTimeInterval(limits.quietSeconds)
        return .confirmed(kind)
    }

    private mutating func abandon() {
        phase = .idle
        kind = nil
        stillSince = nil
        lastQuietAt = nil
        cancelDeadline = nil
    }
}

public struct FallNotice: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var at: Date
    public var deviceID: String
    public var name: String
    public var kind: FallKind
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var channelID: String

    public init(
        id: UUID = UUID(),
        at: Date,
        deviceID: String,
        name: String,
        kind: FallKind,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        channelID: String
    ) {
        self.id = id
        self.at = at
        self.deviceID = deviceID
        self.name = name
        self.kind = kind
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.channelID = channelID
    }
}

public struct FallCue: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var speech: String
    public var relativeDegrees: Double
    public var distanceMeters: Double

    public init(id: UUID, speech: String, relativeDegrees: Double, distanceMeters: Double) {
        self.id = id
        self.speech = speech
        self.relativeDegrees = relativeDegrees
        self.distanceMeters = distanceMeters
    }
}

public struct FallAnnouncement: Equatable, Sendable {
    public var speech: String
    public var cue: FallCue?

    public init(speech: String, cue: FallCue?) {
        self.speech = speech
        self.cue = cue
    }
}

public enum FallCall {
    public static let disclaimer = "補助機能であり緊急通報の代わりではない"

    public static func speech(kind: FallKind, distanceMeters: Double, relativeDegrees: Double) -> String {
        let meters = max(0, Int(distanceMeters.rounded()))
        let sector = ThreatBearing.sector(relativeDegrees: relativeDegrees)
        return "\(sector)\(meters)m \(kind.label)"
    }

    /// 受けた側の向きから、倒れた人の方向を言う。向きが無いときは距離だけ。
    public static func announce(
        notice: FallNotice,
        fromLatitude: Double,
        fromLongitude: Double,
        courseDegrees: Double?,
        headingDegrees: Double?
    ) -> FallAnnouncement? {
        guard let inverse = GRS80Geodesic.inverse(
            latitude1: fromLatitude,
            longitude1: fromLongitude,
            latitude2: notice.latitudeDegrees,
            longitude2: notice.longitudeDegrees
        ) else { return nil }
        let meters = max(0, Int(inverse.distanceMeters.rounded()))
        guard let facing = ThreatBearing.facing(courseDegrees: courseDegrees, headingDegrees: headingDegrees) else {
            return FallAnnouncement(speech: "\(meters)m \(notice.kind.label)", cue: nil)
        }
        let turn = ThreatBearing.relative(targetAzimuthDegrees: inverse.azimuthDegrees, facingDegrees: facing.degrees)
        let line = speech(kind: notice.kind, distanceMeters: inverse.distanceMeters, relativeDegrees: turn)
        let cue = FallCue(id: notice.id, speech: line, relativeDegrees: turn, distanceMeters: inverse.distanceMeters)
        return FallAnnouncement(speech: line, cue: cue)
    }
}

/// P510 へ転倒を渡す口。サーバーはまだ無く、届かないあいだは端末内に留める。
public final class FallRelay: @unchecked Sendable {
    public var isReachable: Bool
    public private(set) var sent: [FallNotice] = []
    public private(set) var pending: [FallNotice] = []

    public init(reachable: Bool) {
        self.isReachable = reachable
    }

    @discardableResult
    public func submit(_ notice: FallNotice) -> RadioDelivery {
        guard isReachable else {
            pending.append(notice)
            return .unreachable
        }
        sent.append(notice)
        return .sent
    }

    public func flush() {
        guard isReachable else { return }
        sent.append(contentsOf: pending)
        pending.removeAll()
    }
}
