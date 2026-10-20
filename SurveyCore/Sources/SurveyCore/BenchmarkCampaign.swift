import Foundation

/// 1回の設置。置き直すたびに新しい回にする。
public struct BenchmarkRound: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var index: Int
    public var startedAt: Date
    public var samples: [BenchmarkSample]
    public var statistics: BenchmarkStatistics
    public var instrument: InstrumentState

    public init(
        id: UUID = UUID(),
        index: Int,
        startedAt: Date,
        samples: [BenchmarkSample],
        statistics: BenchmarkStatistics,
        instrument: InstrumentState
    ) {
        self.id = id
        self.index = index
        self.startedAt = startedAt
        self.samples = samples
        self.statistics = statistics
        self.instrument = instrument
    }
}

/// 既知点から見たずれ。東と北が正。高さは楕円体高どうしのときだけ入る。
public struct SessionOffset: Equatable, Sendable {
    public var eastMeters: Double
    public var northMeters: Double
    public var verticalMeters: Double?

    public init(eastMeters: Double, northMeters: Double, verticalMeters: Double?) {
        self.eastMeters = eastMeters
        self.northMeters = northMeters
        self.verticalMeters = verticalMeters
    }

    public var horizontalMeters: Double {
        GeoMath.hypotenuse(eastMeters, northMeters)
    }
}

public struct ConvergenceSample: Equatable, Sendable {
    public var elapsedSeconds: TimeInterval
    public var eastMeters: Double
    public var northMeters: Double
    public var horizontalMeters: Double
    public var verticalMeters: Double?

    public init(
        elapsedSeconds: TimeInterval,
        eastMeters: Double,
        northMeters: Double,
        horizontalMeters: Double,
        verticalMeters: Double?
    ) {
        self.elapsedSeconds = elapsedSeconds
        self.eastMeters = eastMeters
        self.northMeters = northMeters
        self.horizontalMeters = horizontalMeters
        self.verticalMeters = verticalMeters
    }
}

/// 累積平均の変化を、この窓のあいだで見る。仮の値。
public struct ConvergencePolicy: Equatable, Sendable {
    public var windowSeconds: TimeInterval
    public var horizontalChangeMeters: Double
    public var verticalChangeMeters: Double

    public init(windowSeconds: TimeInterval, horizontalChangeMeters: Double, verticalChangeMeters: Double) {
        self.windowSeconds = windowSeconds
        self.horizontalChangeMeters = horizontalChangeMeters
        self.verticalChangeMeters = verticalChangeMeters
    }

    /// 60秒で水平・高さとも 2cm 以内の変化なら、落ち着いたとみなす。
    public static let provisional = ConvergencePolicy(
        windowSeconds: 60,
        horizontalChangeMeters: 0.02,
        verticalChangeMeters: 0.02
    )
}

public enum ConvergenceCurve {
    public static func make(point: ControlPoint, startedAt: Date, samples: [BenchmarkSample]) -> [ConvergenceSample] {
        let ordered = samples
            .filter { $0.position.isPlottable }
            .sorted { $0.loggedAt < $1.loggedAt }
        var eastSum = 0.0
        var northSum = 0.0
        var counted = 0
        var verticalSum = 0.0
        var verticalCount = 0
        var curve: [ConvergenceSample] = []
        for sample in ordered {
            guard let geodesic = GRS80Geodesic.inverse(
                latitude1: point.latitudeDegrees,
                longitude1: point.longitudeDegrees,
                latitude2: sample.position.latitudeDegrees,
                longitude2: sample.position.longitudeDegrees
            ) else { continue }
            eastSum += geodesic.eastMeters
            northSum += geodesic.northMeters
            counted += 1
            let vertical = ellipsoidalDifference(point: point, height: sample.position.ellipsoidalHeightMeters)
            if let vertical {
                verticalSum += vertical
                verticalCount += 1
            }
            let east = eastSum / Double(counted)
            let north = northSum / Double(counted)
            let elapsed = max(0, sample.loggedAt.timeIntervalSince(startedAt))
            curve.append(ConvergenceSample(
                elapsedSeconds: elapsed,
                eastMeters: east,
                northMeters: north,
                horizontalMeters: GeoMath.hypotenuse(east, north),
                verticalMeters: verticalCount > 0 ? verticalSum / Double(verticalCount) : nil
            ))
        }
        return curve
    }

    /// 窓のあいだの累積平均の変化が、以後ずっと閾値以下になる最初の時刻。
    public static func settledElapsed(_ curve: [ConvergenceSample], policy: ConvergencePolicy) -> TimeInterval? {
        guard curve.count >= 2, policy.windowSeconds > 0,
              policy.horizontalChangeMeters >= 0, policy.verticalChangeMeters >= 0 else { return nil }
        func settled(_ index: Int) -> Bool {
            let cutoff = curve[index].elapsedSeconds - policy.windowSeconds
            guard let earlier = curve.lastIndex(where: { $0.elapsedSeconds <= cutoff + 1e-6 }) else { return false }
            let horizontal = GeoMath.hypotenuse(
                curve[index].eastMeters - curve[earlier].eastMeters,
                curve[index].northMeters - curve[earlier].northMeters
            )
            if horizontal > policy.horizontalChangeMeters { return false }
            if let now = curve[index].verticalMeters, let then = curve[earlier].verticalMeters,
               abs(now - then) > policy.verticalChangeMeters {
                return false
            }
            return true
        }
        for start in curve.indices where settled(start) {
            let tail = (start..<curve.count).allSatisfy(settled)
            if tail { return curve[start].elapsedSeconds }
        }
        return nil
    }

    private static func ellipsoidalDifference(point: ControlPoint, height: Double?) -> Double? {
        guard let height, height.isFinite, let known = point.comparableEllipsoidalHeightMeters else { return nil }
        return height - known
    }
}

public struct RoundGap: Equatable, Sendable {
    public var fromIndex: Int
    public var toIndex: Int
    public var eastMeters: Double
    public var northMeters: Double
    public var verticalMeters: Double?

    public init(fromIndex: Int, toIndex: Int, eastMeters: Double, northMeters: Double, verticalMeters: Double?) {
        self.fromIndex = fromIndex
        self.toIndex = toIndex
        self.eastMeters = eastMeters
        self.northMeters = northMeters
        self.verticalMeters = verticalMeters
    }

    public var horizontalMeters: Double {
        GeoMath.hypotenuse(eastMeters, northMeters)
    }
}

public struct RoundSummary: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var index: Int
    public var offset: SessionOffset
    public var meanLatitudeDegrees: Double
    public var meanLongitudeDegrees: Double
    public var settledElapsedSeconds: TimeInterval?
    public var curve: [ConvergenceSample]

    public init(
        id: UUID,
        index: Int,
        offset: SessionOffset,
        meanLatitudeDegrees: Double,
        meanLongitudeDegrees: Double,
        settledElapsedSeconds: TimeInterval?,
        curve: [ConvergenceSample]
    ) {
        self.id = id
        self.index = index
        self.offset = offset
        self.meanLatitudeDegrees = meanLatitudeDegrees
        self.meanLongitudeDegrees = meanLongitudeDegrees
        self.settledElapsedSeconds = settledElapsedSeconds
        self.curve = curve
    }
}

/// 同じ三角点の複数回。再現性と、補正にしてよいか。
public struct CampaignComparison: Equatable, Sendable {
    public var rounds: [RoundSummary]
    public var gaps: [RoundGap]
    public var overall: SessionOffset
    public var horizontalScatterMeters: Double
    public var verticalScatterMeters: Double?
    public var aligned: Bool

    public init(
        rounds: [RoundSummary],
        gaps: [RoundGap],
        overall: SessionOffset,
        horizontalScatterMeters: Double,
        verticalScatterMeters: Double?,
        aligned: Bool
    ) {
        self.rounds = rounds
        self.gaps = gaps
        self.overall = overall
        self.horizontalScatterMeters = horizontalScatterMeters
        self.verticalScatterMeters = verticalScatterMeters
        self.aligned = aligned
    }

    public static func make(
        point: ControlPoint,
        rounds: [BenchmarkRound],
        convergence: ConvergencePolicy = .provisional,
        limits: CorrectionPolicy = .provisional
    ) -> CampaignComparison? {
        let ordered = rounds.sorted { $0.index < $1.index }
        var summaries: [RoundSummary] = []
        for round in ordered {
            guard let offset = SessionOffset.mean(of: round.statistics, point: point) else { continue }
            let curve = ConvergenceCurve.make(point: point, startedAt: round.startedAt, samples: round.samples)
            summaries.append(RoundSummary(
                id: round.id,
                index: round.index,
                offset: offset,
                meanLatitudeDegrees: round.statistics.meanLatitudeDegrees,
                meanLongitudeDegrees: round.statistics.meanLongitudeDegrees,
                settledElapsedSeconds: ConvergenceCurve.settledElapsed(curve, policy: convergence),
                curve: curve
            ))
        }
        guard !summaries.isEmpty else { return nil }
        var gaps: [RoundGap] = []
        for index in summaries.indices.dropFirst() {
            let previous = summaries[index - 1]
            let current = summaries[index]
            let vertical: Double?
            if let before = previous.offset.verticalMeters, let after = current.offset.verticalMeters {
                vertical = after - before
            } else {
                vertical = nil
            }
            gaps.append(RoundGap(
                fromIndex: previous.index,
                toIndex: current.index,
                eastMeters: current.offset.eastMeters - previous.offset.eastMeters,
                northMeters: current.offset.northMeters - previous.offset.northMeters,
                verticalMeters: vertical
            ))
        }
        let east = summaries.map(\.offset.eastMeters)
        let north = summaries.map(\.offset.northMeters)
        let verticals = summaries.compactMap(\.offset.verticalMeters)
        let overallVertical = verticals.count == summaries.count ? BenchmarkStatistics.mean(verticals) : nil
        let overall = SessionOffset(
            eastMeters: BenchmarkStatistics.mean(east),
            northMeters: BenchmarkStatistics.mean(north),
            verticalMeters: overallVertical
        )
        let horizontalScatter = GeoMath.hypotenuse(
            BenchmarkStatistics.sampleStd(east),
            BenchmarkStatistics.sampleStd(north)
        )
        let verticalScatter = verticals.count == summaries.count ? BenchmarkStatistics.sampleStd(verticals) : nil
        let aligned = summaries.count >= 2
            && horizontalScatter <= limits.horizontalScatterMeters
            && (verticalScatter.map { $0 <= limits.verticalScatterMeters } ?? true)
        return CampaignComparison(
            rounds: summaries,
            gaps: gaps,
            overall: overall,
            horizontalScatterMeters: horizontalScatter,
            verticalScatterMeters: verticalScatter,
            aligned: aligned
        )
    }
}

extension SessionOffset {
    static func mean(of statistics: BenchmarkStatistics, point: ControlPoint) -> SessionOffset? {
        guard let geodesic = GRS80Geodesic.inverse(
            latitude1: point.latitudeDegrees,
            longitude1: point.longitudeDegrees,
            latitude2: statistics.meanLatitudeDegrees,
            longitude2: statistics.meanLongitudeDegrees
        ) else { return nil }
        let vertical = statistics.verticalComparison == .ellipsoidal ? statistics.verticalDifferenceMeters : nil
        return SessionOffset(
            eastMeters: geodesic.eastMeters,
            northMeters: geodesic.northMeters,
            verticalMeters: vertical
        )
    }
}

/// 補正にしてよいか、古いか、戻り点検の差を小さいとするか。仮の値。
public struct CorrectionPolicy: Equatable, Sendable {
    public var horizontalScatterMeters: Double
    public var verticalScatterMeters: Double
    public var staleAfterSeconds: TimeInterval
    public var returnHorizontalMeters: Double
    public var returnVerticalMeters: Double

    public init(
        horizontalScatterMeters: Double,
        verticalScatterMeters: Double,
        staleAfterSeconds: TimeInterval,
        returnHorizontalMeters: Double,
        returnVerticalMeters: Double
    ) {
        self.horizontalScatterMeters = horizontalScatterMeters
        self.verticalScatterMeters = verticalScatterMeters
        self.staleAfterSeconds = staleAfterSeconds
        self.returnHorizontalMeters = returnHorizontalMeters
        self.returnVerticalMeters = returnVerticalMeters
    }

    /// 回のばらつきは水平 2m・高さ 3m まで。2時間で古い。戻りの差は 0.5m まで有効。
    public static let provisional = CorrectionPolicy(
        horizontalScatterMeters: 2,
        verticalScatterMeters: 3,
        staleAfterSeconds: 120 * 60,
        returnHorizontalMeters: 0.5,
        returnVerticalMeters: 0.5
    )
}

public struct CorrectionAge: Equatable, Sendable {
    public var elapsedMinutes: Int
    public var stale: Bool

    public init(elapsedMinutes: Int, stale: Bool) {
        self.elapsedMinutes = elapsedMinutes
        self.stale = stale
    }
}

/// 三角点で見た平均のずれ。以後の観測から引く。
public struct ControlCorrection: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var pointID: String
    public var pointName: String
    public var instrument: InstrumentState
    public var acquiredAt: Date
    public var eastMeters: Double
    public var northMeters: Double
    public var verticalMeters: Double?
    public var horizontalScatterMeters: Double
    public var verticalScatterMeters: Double?
    public var roundCount: Int
    public var active: Bool

    public init(
        id: UUID = UUID(),
        pointID: String,
        pointName: String,
        instrument: InstrumentState,
        acquiredAt: Date,
        eastMeters: Double,
        northMeters: Double,
        verticalMeters: Double?,
        horizontalScatterMeters: Double,
        verticalScatterMeters: Double?,
        roundCount: Int,
        active: Bool
    ) {
        self.id = id
        self.pointID = pointID
        self.pointName = pointName
        self.instrument = instrument
        self.acquiredAt = acquiredAt
        self.eastMeters = eastMeters
        self.northMeters = northMeters
        self.verticalMeters = verticalMeters
        self.horizontalScatterMeters = horizontalScatterMeters
        self.verticalScatterMeters = verticalScatterMeters
        self.roundCount = roundCount
        self.active = active
    }

    public static func make(
        point: ControlPoint,
        instrument: InstrumentState,
        comparison: CampaignComparison,
        acquiredAt: Date
    ) -> ControlCorrection? {
        guard comparison.aligned else { return nil }
        return ControlCorrection(
            pointID: point.id,
            pointName: point.name,
            instrument: instrument,
            acquiredAt: acquiredAt,
            eastMeters: comparison.overall.eastMeters,
            northMeters: comparison.overall.northMeters,
            verticalMeters: comparison.overall.verticalMeters,
            horizontalScatterMeters: comparison.horizontalScatterMeters,
            verticalScatterMeters: comparison.verticalScatterMeters,
            roundCount: comparison.rounds.count,
            active: true
        )
    }

    public func age(at now: Date, policy: CorrectionPolicy = .provisional) -> CorrectionAge {
        let elapsed = max(0, now.timeIntervalSince(acquiredAt))
        let minutes = Int((elapsed / 60).rounded(.down))
        let stale = policy.staleAfterSeconds >= 0 && elapsed >= policy.staleAfterSeconds
        return CorrectionAge(elapsedMinutes: minutes, stale: stale)
    }

    public func applies(to position: GeodeticPosition, now: Date, policy: CorrectionPolicy = .provisional) -> Bool {
        active && InstrumentState(position) == instrument && !age(at: now, policy: policy).stale
    }

    /// 判定に使う精度。三角点補正の目安より良いとは言わない。ばらつきの方が粗ければ、そちらを使う。
    public func judgmentMeters(
        for position: GeodeticPosition,
        now: Date,
        policy: CorrectionPolicy = .provisional
    ) -> (horizontal: Double, vertical: Double?, note: String)? {
        guard applies(to: position, now: now, policy: policy) else { return nil }
        let horizontal = max(Self.nominalHorizontal, max(0, horizontalScatterMeters))
        let vertical: Double?
        if verticalMeters != nil {
            vertical = max(Self.nominalVertical, max(0, verticalScatterMeters ?? 0))
        } else {
            vertical = nil
        }
        return (horizontal, vertical, "三角点補正を引いて判定しています。")
    }

    /// 観測位置から、このずれを引いた点。元の位置は変えない。
    public func subtracting(from position: GeodeticPosition) -> GeodeticPosition? {
        guard position.isPlottable else { return nil }
        let east = -eastMeters
        let north = -northMeters
        let distance = GeoMath.hypotenuse(east, north)
        let moved: (latitude: Double, longitude: Double)
        if distance < 1e-6 {
            moved = (position.latitudeDegrees, position.longitudeDegrees)
        } else if let direct = GRS80Geodesic.direct(
            latitude: position.latitudeDegrees,
            longitude: position.longitudeDegrees,
            azimuthDegrees: GeoMath.degrees(fromRadians: GeoMath.arctangent(east, north)),
            distanceMeters: distance
        ) {
            moved = direct
        } else {
            return nil
        }
        let height: Double?
        if let verticalMeters, let current = position.ellipsoidalHeightMeters, current.isFinite {
            height = current - verticalMeters
        } else {
            height = position.ellipsoidalHeightMeters
        }
        return GeodeticPosition(
            latitudeDegrees: moved.latitude,
            longitudeDegrees: moved.longitude,
            ellipsoidalHeightMeters: height,
            horizontalAccuracyMeters: position.horizontalAccuracyMeters,
            verticalAccuracyMeters: position.verticalAccuracyMeters,
            timestamp: position.timestamp,
            stage: position.stage,
            fixQuality: position.fixQuality,
            receiver: position.receiver,
            frame: position.frame
        )
    }

    public func workingPosition(
        from position: GeodeticPosition,
        now: Date,
        policy: CorrectionPolicy = .provisional
    ) -> GeodeticPosition? {
        guard let meters = judgmentMeters(for: position, now: now, policy: policy),
              var shifted = subtracting(from: position) else { return nil }
        shifted.horizontalAccuracyMeters = meters.horizontal
        if let vertical = meters.vertical {
            shifted.verticalAccuracyMeters = vertical
        }
        return shifted
    }

    private static var nominalHorizontal: Double {
        ReachingMethods.all.first { $0.id == "control" }?.horizontalMeters ?? 0.5
    }

    private static var nominalVertical: Double {
        ReachingMethods.all.first { $0.id == "control" }?.verticalMeters ?? 0.5
    }
}

public struct CorrectionStore: Codable, Equatable, Sendable {
    public static let fileName = "control-corrections.json"
    public var corrections: [ControlCorrection]
    public var lastReturnCheck: ReturnCheckRecord?

    public init(corrections: [ControlCorrection] = [], lastReturnCheck: ReturnCheckRecord? = nil) {
        self.corrections = corrections
        self.lastReturnCheck = lastReturnCheck
    }

    public var active: ControlCorrection? {
        corrections.first { $0.active }
    }

    public func saving(_ correction: ControlCorrection) -> CorrectionStore {
        var copy = self
        copy.corrections = copy.corrections.map { existing in
            var item = existing
            item.active = false
            return item
        }
        var stored = correction
        stored.active = true
        if let index = copy.corrections.firstIndex(where: { $0.id == stored.id }) {
            copy.corrections[index] = stored
        } else {
            copy.corrections.append(stored)
        }
        return copy
    }

    public static func load(from directory: URL) -> CorrectionStore {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(CorrectionStore.self, from: data) else {
            return CorrectionStore()
        }
        return saved
    }

    public func save(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }
}

public struct ReturnCheck: Equatable, Sendable {
    public var horizontalDifferenceMeters: Double
    public var verticalDifferenceMeters: Double?
    public var valid: Bool

    public init(horizontalDifferenceMeters: Double, verticalDifferenceMeters: Double?, valid: Bool) {
        self.horizontalDifferenceMeters = horizontalDifferenceMeters
        self.verticalDifferenceMeters = verticalDifferenceMeters
        self.valid = valid
    }

    public static func compare(
        start: ControlCorrection,
        end: SessionOffset,
        policy: CorrectionPolicy = .provisional
    ) -> ReturnCheck {
        let horizontal = GeoMath.hypotenuse(end.eastMeters - start.eastMeters, end.northMeters - start.northMeters)
        let vertical: Double?
        if let endVertical = end.verticalMeters, let startVertical = start.verticalMeters {
            vertical = endVertical - startVertical
        } else {
            vertical = nil
        }
        let verticalOK = vertical.map { abs($0) <= policy.returnVerticalMeters } ?? true
        return ReturnCheck(
            horizontalDifferenceMeters: horizontal,
            verticalDifferenceMeters: vertical,
            valid: horizontal <= policy.returnHorizontalMeters && verticalOK
        )
    }
}

public enum ClosureChoice: String, Codable, Sendable {
    case apportion
    case resurvey
}

public struct ClosureAdjustment: Codable, Equatable, Sendable {
    public var position: GeodeticPosition
    public var fraction: Double

    public init(position: GeodeticPosition, fraction: Double) {
        self.position = position
        self.fraction = fraction
    }
}

public struct ReturnCheckRecord: Codable, Equatable, Sendable {
    public var pointID: String
    public var startCorrectionID: UUID
    public var checkedAt: Date
    public var horizontalDifferenceMeters: Double
    public var verticalDifferenceMeters: Double?
    public var valid: Bool
    public var choice: ClosureChoice?

    public init(
        pointID: String,
        startCorrectionID: UUID,
        checkedAt: Date,
        horizontalDifferenceMeters: Double,
        verticalDifferenceMeters: Double?,
        valid: Bool,
        choice: ClosureChoice?
    ) {
        self.pointID = pointID
        self.startCorrectionID = startCorrectionID
        self.checkedAt = checkedAt
        self.horizontalDifferenceMeters = horizontalDifferenceMeters
        self.verticalDifferenceMeters = verticalDifferenceMeters
        self.valid = valid
        self.choice = choice
    }
}

public enum ClosureAdjustmentMath {
    /// 開始時刻と終了時刻のあいだの点だけ。元の captured は残す。
    public static func apportion(
        observations: [FieldObservation],
        start: ControlCorrection,
        end: SessionOffset,
        endAt: Date
    ) -> [FieldObservation] {
        observations.map { observation in
            guard let fraction = fraction(of: observation, start: start, endAt: endAt),
                  let shifted = interpolated(start: start, end: end, fraction: fraction).subtracting(from: observation.captured) else {
                return observation
            }
            var copy = observation
            copy.closureAdjustment = ClosureAdjustment(position: shifted, fraction: fraction)
            return copy
        }
    }

    public static func markResurvey(
        observations: [FieldObservation],
        start: ControlCorrection,
        endAt: Date
    ) -> [FieldObservation] {
        observations.map { observation in
            guard fraction(of: observation, start: start, endAt: endAt) != nil else { return observation }
            var copy = observation
            copy.needsResurvey = true
            return copy
        }
    }

    private static func fraction(of observation: FieldObservation, start: ControlCorrection, endAt: Date) -> Double? {
        guard InstrumentState(observation.captured) == start.instrument else { return nil }
        let span = endAt.timeIntervalSince(start.acquiredAt)
        guard span > 0 else { return nil }
        let value = observation.captured.timestamp.timeIntervalSince(start.acquiredAt) / span
        guard value > 0, value < 1 else { return nil }
        return value
    }

    private static func interpolated(start: ControlCorrection, end: SessionOffset, fraction: Double) -> ControlCorrection {
        let vertical: Double?
        if let startVertical = start.verticalMeters, let endVertical = end.verticalMeters {
            vertical = startVertical + fraction * (endVertical - startVertical)
        } else {
            vertical = nil
        }
        return ControlCorrection(
            id: start.id,
            pointID: start.pointID,
            pointName: start.pointName,
            instrument: start.instrument,
            acquiredAt: start.acquiredAt,
            eastMeters: start.eastMeters + fraction * (end.eastMeters - start.eastMeters),
            northMeters: start.northMeters + fraction * (end.northMeters - start.northMeters),
            verticalMeters: vertical,
            horizontalScatterMeters: start.horizontalScatterMeters,
            verticalScatterMeters: start.verticalScatterMeters,
            roundCount: start.roundCount,
            active: false
        )
    }
}

public enum CampaignText {
    public static func roundLine(index: Int, offset: SessionOffset) -> String {
        "\(index)回目 水平 \(BenchmarkText.meters(offset.horizontalMeters)) 高さ \(height(offset.verticalMeters))"
    }

    public static func gapLine(_ gap: RoundGap) -> String {
        "\(gap.fromIndex)回目と\(gap.toIndex)回目の差 水平 \(BenchmarkText.meters(gap.horizontalMeters)) 高さ \(height(gap.verticalMeters))"
    }

    public static func overallLine(_ offset: SessionOffset) -> String {
        "全体の平均 水平 \(BenchmarkText.meters(offset.horizontalMeters)) 高さ \(height(offset.verticalMeters))"
    }

    public static func scatterLine(horizontal: Double, aligned: Bool) -> String {
        let lead = "再現性 水平 \(BenchmarkText.meters(horizontal))。"
        if aligned { return lead + "向きと大きさはそろっています。" }
        return lead + "ばらつきが閾値を超えるので、補正値にはしません。"
    }

    public static func settledLine(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "この回では落ち着きませんでした" }
        let minutes = seconds / 60
        if minutes >= 1 {
            if abs(minutes - minutes.rounded()) < 0.05 {
                return "\(Int(minutes.rounded()))分で落ち着きました"
            }
            return "\(FixedNumber.string(minutes, fractionDigits: 1))分で落ち着きました"
        }
        return "\(Int(seconds.rounded(.toNearestOrAwayFromZero)))秒で落ち着きました"
    }

    public static func returnLine(_ check: ReturnCheck) -> String {
        let lead = "始めと終わりの差は水平 \(BenchmarkText.meters(check.horizontalDifferenceMeters))。"
        if check.valid { return lead + "補正有効。" }
        return lead + "途中の点を割り振るか、要再測の印を付けられます。"
    }

    private static func height(_ meters: Double?) -> String {
        guard let meters else { return "—" }
        return BenchmarkText.signedMeters(meters)
    }
}
