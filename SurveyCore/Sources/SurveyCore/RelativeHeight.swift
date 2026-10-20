import Foundation

/// 視覚慣性の状態。ARKit の trackingState を、この3つに落とす。
public enum RelativeQuality: String, Sendable, Equatable {
    case normal
    case limited
    case lost
}

/// 相対高の出どころ。RTK FIX が来たら GNSS が先。
public enum RelativeChannel: String, Sendable, Equatable {
    case gnssFix
    case visual
    case visualBaro
    case barometer
    case inertial

    public var label: String {
        switch self {
        case .gnssFix: return "RTK FIX"
        case .visual: return "視覚慣性"
        case .visualBaro: return "視覚慣性+気圧"
        case .barometer: return "気圧"
        case .inertial: return "IMU"
        }
    }
}

/// ゼロ合わせに使う既知点。楕円体高だけ。標高だけの点は入れない。
public enum KnownHeightSource: String, Sendable, Equatable {
    case control
    case book

    public var label: String {
        switch self {
        case .control: return "基準点"
        case .book: return "座標簿"
        }
    }
}

public struct KnownHeight: Equatable, Sendable, Identifiable {
    public var name: String
    public var heightMeters: Double
    public var source: KnownHeightSource

    public var id: String { "\(source.rawValue)|\(name)" }

    public init(name: String, heightMeters: Double, source: KnownHeightSource) {
        self.name = name
        self.heightMeters = heightMeters
        self.source = source
    }
}

public enum KnownHeightPick {
    public static func control(_ point: ControlPoint) -> KnownHeight? {
        guard let height = point.comparableEllipsoidalHeightMeters else { return nil }
        let name = point.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return KnownHeight(name: name, heightMeters: height, source: .control)
    }

    public static func book(_ entry: CoordinateBookEntry) -> KnownHeight? {
        guard let height = entry.ellipsoidalHeightMeters, height.isFinite else { return nil }
        let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return KnownHeight(name: name, heightMeters: height, source: .book)
    }
}

/// 既知点で合わせた原点。以降の差は、このときのセンサー値から引く。
public struct RelativeZero: Equatable, Sendable {
    public var name: String
    public var knownHeightMeters: Double
    public var alignedAt: Date
    public var visualOriginMeters: Double
    public var baroOriginMeters: Double?
    public var inertialOriginMeters: Double

    public init(
        name: String,
        knownHeightMeters: Double,
        alignedAt: Date,
        visualOriginMeters: Double,
        baroOriginMeters: Double?,
        inertialOriginMeters: Double
    ) {
        self.name = name
        self.knownHeightMeters = knownHeightMeters
        self.alignedAt = alignedAt
        self.visualOriginMeters = visualOriginMeters
        self.baroOriginMeters = baroOriginMeters
        self.inertialOriginMeters = inertialOriginMeters
    }
}

/// 重力を除いた鉛直加速度の二重積分。穴が開いたら速度は捨てる。
public struct InertialVertical: Equatable, Sendable {
    public var velocity: Double
    public var displacement: Double
    public var lastAt: Date?
    public static let maxStep = 0.2
    public static let maxAcceleration = 30.0

    public init(velocity: Double = 0, displacement: Double = 0, lastAt: Date? = nil) {
        self.velocity = velocity
        self.displacement = displacement
        self.lastAt = lastAt
    }

    public mutating func integrate(upAcceleration: Double, at: Date) {
        guard upAcceleration.isFinite else { return }
        guard let last = lastAt else {
            lastAt = at
            return
        }
        let dt = at.timeIntervalSince(last)
        lastAt = at
        guard dt > 0, dt <= Self.maxStep, abs(upAcceleration) <= Self.maxAcceleration else {
            velocity = 0
            return
        }
        velocity += upAcceleration * dt
        displacement += velocity * dt
    }
}

/// 端末が今見ているセンサー。日付は呼び出し側が付ける。
public struct RelativeSample: Equatable, Sendable {
    public var at: Date
    public var visualUp: Double?
    public var visualX: Double?
    public var visualZ: Double?
    public var baro: Double?
    public var upAcceleration: Double?
    public var quality: RelativeQuality
    public var gnssEllipsoidal: Double?
    public var gnssTrustedFix: Bool
    public var gnssVerticalAccuracy: Double?
    public var poleMeters: Double?

    public init(
        at: Date,
        visualUp: Double? = nil,
        visualX: Double? = nil,
        visualZ: Double? = nil,
        baro: Double? = nil,
        upAcceleration: Double? = nil,
        quality: RelativeQuality = .normal,
        gnssEllipsoidal: Double? = nil,
        gnssTrustedFix: Bool = false,
        gnssVerticalAccuracy: Double? = nil,
        poleMeters: Double? = nil
    ) {
        self.at = at
        self.visualUp = visualUp
        self.visualX = visualX
        self.visualZ = visualZ
        self.baro = baro
        self.upAcceleration = upAcceleration
        self.quality = quality
        self.gnssEllipsoidal = gnssEllipsoidal
        self.gnssTrustedFix = gnssTrustedFix
        self.gnssVerticalAccuracy = gnssVerticalAccuracy
        self.poleMeters = poleMeters
    }
}

public struct RelativeFix: Equatable, Sendable {
    public var heightMeters: Double
    public var channel: RelativeChannel
    public var deltaMeters: Double
    public var sigmaMeters: Double
    public var elapsedSeconds: TimeInterval
    public var traveledMeters: Double
    public var needsRealign: Bool
    public var quality: RelativeQuality

    public init(
        heightMeters: Double,
        channel: RelativeChannel,
        deltaMeters: Double,
        sigmaMeters: Double,
        elapsedSeconds: TimeInterval,
        traveledMeters: Double,
        needsRealign: Bool,
        quality: RelativeQuality
    ) {
        self.heightMeters = heightMeters
        self.channel = channel
        self.deltaMeters = deltaMeters
        self.sigmaMeters = sigmaMeters
        self.elapsedSeconds = elapsedSeconds
        self.traveledMeters = traveledMeters
        self.needsRealign = needsRealign
        self.quality = quality
    }
}

/// 相対高専用のバッジ。GNSS の段階0〜3には入れない。測設の合格にはしない。
public struct RelativeBadge: Equatable, Sendable {
    public static let stageLabel = "相対"
    public var text: String
    public var accessibilityText: String
    public var needsRealign: Bool
    public var isStakeoutGrade: Bool
    public var tone: AccuracyTone

    public init(text: String, accessibilityText: String, needsRealign: Bool, isStakeoutGrade: Bool, tone: AccuracyTone) {
        self.text = text
        self.accessibilityText = accessibilityText
        self.needsRealign = needsRealign
        self.isStakeoutGrade = isStakeoutGrade
        self.tone = tone
    }
}

/// ゼロ以降の追跡。移動距離は視覚慣性の水平成分を足す。
public struct RelativeTrack: Equatable, Sendable {
    public private(set) var zero: RelativeZero?
    public private(set) var traveledMeters: Double
    public private(set) var inertial: InertialVertical
    private var lastX: Double?
    private var lastZ: Double?

    public init(zero: RelativeZero? = nil, traveledMeters: Double = 0, inertial: InertialVertical = InertialVertical()) {
        self.zero = zero
        self.traveledMeters = traveledMeters
        self.inertial = inertial
    }

    public static func == (lhs: RelativeTrack, rhs: RelativeTrack) -> Bool {
        lhs.zero == rhs.zero
            && lhs.traveledMeters == rhs.traveledMeters
            && lhs.inertial == rhs.inertial
            && lhs.lastX == rhs.lastX
            && lhs.lastZ == rhs.lastZ
    }

    @discardableResult
    public mutating func align(
        name: String,
        knownHeight: Double,
        visualUp: Double,
        visualX: Double,
        visualZ: Double,
        baro: Double?,
        at: Date
    ) -> RelativeZero? {
        guard let made = RelativeHeight.makeZero(
            name: name,
            knownHeight: knownHeight,
            visualUp: visualUp,
            baro: baro,
            inertialDisplacement: inertial.displacement,
            at: at
        ), visualX.isFinite, visualZ.isFinite else { return nil }
        zero = made
        traveledMeters = 0
        lastX = visualX
        lastZ = visualZ
        return made
    }

    public mutating func consume(_ sample: RelativeSample) -> RelativeFix? {
        if let accel = sample.upAcceleration {
            inertial.integrate(upAcceleration: accel, at: sample.at)
        }
        guard let zero else { return nil }
        if sample.quality != .lost {
            addTravel(sample)
        }
        let elapsed = max(0, sample.at.timeIntervalSince(zero.alignedAt))
        let visualDelta = sample.visualUp.flatMap { RelativeHeight.delta(current: $0, origin: zero.visualOriginMeters) }
        let baroDelta: Double?
        if let baro = sample.baro, let origin = zero.baroOriginMeters {
            baroDelta = RelativeHeight.delta(current: baro, origin: origin)
        } else {
            baroDelta = nil
        }
        let inertialDelta = RelativeHeight.delta(current: inertial.displacement, origin: zero.inertialOriginMeters)
        return RelativeHeight.solve(
            knownHeight: zero.knownHeightMeters,
            visualDelta: visualDelta,
            baroDelta: baroDelta,
            inertialDelta: inertialDelta,
            elapsedSeconds: elapsed,
            traveledMeters: traveledMeters,
            quality: sample.quality,
            gnssEllipsoidal: sample.gnssEllipsoidal,
            gnssTrustedFix: sample.gnssTrustedFix,
            gnssVerticalAccuracy: sample.gnssVerticalAccuracy,
            poleMeters: sample.poleMeters
        )
    }

    private mutating func addTravel(_ sample: RelativeSample) {
        guard let x = sample.visualX, let z = sample.visualZ, x.isFinite, z.isFinite else { return }
        if let lastX, let lastZ {
            let step = GeoMath.hypotenuse(x - lastX, z - lastZ)
            if step.isFinite, step > 0 { traveledMeters += step }
        }
        lastX = x
        lastZ = z
    }
}

public enum RelativeHeight {
    public static let standardGravity = 9.80665
    /// 設計値。実機で測るまでは、この率で推定する。手順は docs/batter.md。
    public static let visualPerSecond = 0.001
    public static let visualPerMeter = 0.002
    public static let baroPerSecond = 0.003
    public static let baroPerMeter = 0.0005
    public static let inertialPerSecond = 0.010
    public static let inertialPerMeter = 0.005
    public static let limitedFactor = 2.0
    /// これを超えたら合わせ直す。ちょうど閾値はまだ許す。
    public static let realignMeters = 0.020
    public static let realignWord = "合わせ直して"
    public static let visualWeight = 0.7

    private static var posix: Locale { Locale(identifier: "en_US_POSIX") }

    public static func makeZero(
        name: String,
        knownHeight: Double,
        visualUp: Double,
        baro: Double?,
        inertialDisplacement: Double,
        at: Date
    ) -> RelativeZero? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, knownHeight.isFinite, visualUp.isFinite, inertialDisplacement.isFinite else { return nil }
        let baroOrigin = baro.flatMap { $0.isFinite ? $0 : nil }
        return RelativeZero(
            name: trimmed,
            knownHeightMeters: knownHeight,
            alignedAt: at,
            visualOriginMeters: visualUp,
            baroOriginMeters: baroOrigin,
            inertialOriginMeters: inertialDisplacement
        )
    }

    public static func delta(current: Double, origin: Double) -> Double? {
        guard current.isFinite, origin.isFinite else { return nil }
        let value = current - origin
        return value.isFinite ? value : nil
    }

    /// 重力の向きを下として、ユーザー加速度の鉛直成分を m/s² にする。入力は g。
    public static func upAcceleration(
        userX: Double, userY: Double, userZ: Double,
        gravityX: Double, gravityY: Double, gravityZ: Double
    ) -> Double? {
        guard userX.isFinite, userY.isFinite, userZ.isFinite, gravityX.isFinite, gravityY.isFinite, gravityZ.isFinite else { return nil }
        let gravity = GeoMath.hypotenuse(gravityX, GeoMath.hypotenuse(gravityY, gravityZ))
        guard gravity > 0.5 else { return nil }
        let down = (userX * gravityX + userY * gravityY + userZ * gravityZ) / gravity
        return -down * standardGravity
    }

    public static func solve(
        knownHeight: Double,
        visualDelta: Double?,
        baroDelta: Double?,
        inertialDelta: Double?,
        elapsedSeconds: Double,
        traveledMeters: Double,
        quality: RelativeQuality,
        gnssEllipsoidal: Double?,
        gnssTrustedFix: Bool,
        gnssVerticalAccuracy: Double?,
        poleMeters: Double?
    ) -> RelativeFix? {
        guard knownHeight.isFinite else { return nil }
        let elapsed = elapsedSeconds.isFinite ? max(0, elapsedSeconds) : 0
        let traveled = traveledMeters.isFinite ? max(0, traveledMeters) : 0
        if gnssTrustedFix, let gnss = gnssEllipsoidal, gnss.isFinite {
            let height = BatterMath.poleTip(deviceEllipsoidal: gnss, poleMeters: poleMeters) ?? gnss
            let sigma: Double
            if let reported = gnssVerticalAccuracy, reported.isFinite, reported >= 0 {
                sigma = reported
            } else {
                sigma = .nan
            }
            return RelativeFix(
                heightMeters: height,
                channel: .gnssFix,
                deltaMeters: height - knownHeight,
                sigmaMeters: sigma,
                elapsedSeconds: elapsed,
                traveledMeters: traveled,
                needsRealign: false,
                quality: quality
            )
        }
        let visual = quality == .lost ? nil : visualDelta.flatMap { $0.isFinite ? $0 : nil }
        let baro = baroDelta.flatMap { $0.isFinite ? $0 : nil }
        let inertial = inertialDelta.flatMap { $0.isFinite ? $0 : nil }
        let chosen = channel(visual: visual, baro: baro, inertial: inertial, quality: quality)
        guard let chosen else { return nil }
        let disagreement: Double
        if let visual, let baro, chosen.channel == .visual || chosen.channel == .visualBaro {
            disagreement = abs(visual - baro)
        } else {
            disagreement = 0
        }
        let sigma = error(
            channel: chosen.channel,
            elapsed: elapsed,
            traveled: traveled,
            quality: quality,
            disagreement: disagreement
        )
        let realign = quality == .lost || sigma > realignMeters
        return RelativeFix(
            heightMeters: knownHeight + chosen.delta,
            channel: chosen.channel,
            deltaMeters: chosen.delta,
            sigmaMeters: sigma,
            elapsedSeconds: elapsed,
            traveledMeters: traveled,
            needsRealign: realign,
            quality: quality
        )
    }

    public static func usesReceiverStage(_ channel: RelativeChannel) -> Bool {
        channel == .gnssFix
    }

    public static func canRecord(_ fix: RelativeFix) -> Bool {
        !fix.needsRealign
    }

    public static func estimateText(_ meters: Double) -> String {
        guard meters.isFinite else { return "推定 —" }
        let centimeters = abs(meters) * 100
        return String(format: "推定 ±%.1fcm", locale: posix, centimeters)
    }

    public static func statusText(_ fix: RelativeFix) -> String {
        let seconds = Int(fix.elapsedSeconds.rounded())
        let distance = String(format: "%.1f", locale: posix, fix.traveledMeters)
        return "経過 \(seconds)秒、移動 \(distance)m、\(fix.channel.label)、\(estimateText(fix.sigmaMeters))"
    }

    public static func badge(for fix: RelativeFix) -> RelativeBadge {
        var parts = [fix.channel.label, estimateText(fix.sigmaMeters)]
        if fix.needsRealign { parts.append(realignWord) }
        let text = parts.joined(separator: "　")
        let tone: AccuracyTone
        if fix.needsRealign {
            tone = .red
        } else if fix.sigmaMeters <= 0.010 {
            tone = .green
        } else {
            tone = .yellow
        }
        return RelativeBadge(
            text: text,
            accessibilityText: "相対。\(text)。測設の合格にはしません。",
            needsRealign: fix.needsRealign,
            isStakeoutGrade: false,
            tone: tone
        )
    }

    public static func waitingBadge() -> RelativeBadge {
        RelativeBadge(
            text: "ゼロを待っています",
            accessibilityText: "相対。ゼロを待っています。測設の合格にはしません。",
            needsRealign: false,
            isStakeoutGrade: false,
            tone: .grey
        )
    }

    private static func channel(
        visual: Double?,
        baro: Double?,
        inertial: Double?,
        quality: RelativeQuality
    ) -> (channel: RelativeChannel, delta: Double)? {
        if let visual {
            if quality == .limited, let baro {
                return (.visualBaro, visualWeight * visual + (1 - visualWeight) * baro)
            }
            return (.visual, visual)
        }
        if let baro { return (.barometer, baro) }
        if let inertial { return (.inertial, inertial) }
        return nil
    }

    private static func error(
        channel: RelativeChannel,
        elapsed: Double,
        traveled: Double,
        quality: RelativeQuality,
        disagreement: Double
    ) -> Double {
        let perSecond: Double
        let perMeter: Double
        switch channel {
        case .gnssFix:
            return 0
        case .visual, .visualBaro:
            perSecond = visualPerSecond
            perMeter = visualPerMeter
        case .barometer:
            perSecond = baroPerSecond
            perMeter = baroPerMeter
        case .inertial:
            perSecond = inertialPerSecond
            perMeter = inertialPerMeter
        }
        let factor = quality == .limited ? limitedFactor : 1
        let base = GeoMath.hypotenuse(perSecond * elapsed, perMeter * traveled) * factor
        return GeoMath.hypotenuse(base, max(0, disagreement))
    }
}
