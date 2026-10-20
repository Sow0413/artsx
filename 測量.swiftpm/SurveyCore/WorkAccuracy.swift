import Foundation

/// 作業。要求精度の数値は仮で、現場パックの JSON から上書きする。
public struct WorkRequirement: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var shortTitle: String
    public var horizontalMeters: Double
    public var verticalMeters: Double

    public init(
        id: String,
        title: String,
        shortTitle: String,
        horizontalMeters: Double,
        verticalMeters: Double
    ) {
        self.id = id
        self.title = title
        self.shortTitle = shortTitle
        self.horizontalMeters = horizontalMeters
        self.verticalMeters = verticalMeters
    }
}

/// 選んでいる作業と、楽観的な報告にかける係数。
public struct WorkCatalog: Codable, Equatable, Sendable {
    public static let fileName = "work-requirements.json"
    public static let defaultSafetyFactor = 2.0

    public var selectedID: String
    public var optimisticSafetyFactor: Double
    public var works: [WorkRequirement]

    public init(selectedID: String, optimisticSafetyFactor: Double, works: [WorkRequirement]) {
        self.selectedID = selectedID
        self.optimisticSafetyFactor = optimisticSafetyFactor
        self.works = works
    }

    /// 2026-10-20 の仮値。高さは、丁張だけ 1cm。ほかは水平と同じ。
    public static let provisional = WorkCatalog(
        selectedID: "preview",
        optimisticSafetyFactor: defaultSafetyFactor,
        works: [
            WorkRequirement(id: "preview", title: "下見・現況スケッチ", shortTitle: "下見", horizontalMeters: 5, verticalMeters: 5),
            WorkRequirement(id: "rough", title: "概略の位置出し", shortTitle: "概略", horizontalMeters: 0.5, verticalMeters: 0.5),
            WorkRequirement(id: "traverse", title: "測量（トラバー）", shortTitle: "測量", horizontalMeters: 0.02, verticalMeters: 0.02),
            WorkRequirement(id: "stakeout", title: "丁張・測設", shortTitle: "丁張", horizontalMeters: 0.02, verticalMeters: 0.01),
            WorkRequirement(id: "asBuilt", title: "出来形", shortTitle: "出来形", horizontalMeters: 0.05, verticalMeters: 0.05),
            WorkRequirement(id: "boundary", title: "境界・基準点", shortTitle: "境界", horizontalMeters: 0.02, verticalMeters: 0.02)
        ]
    )

    public var selected: WorkRequirement {
        works.first { $0.id == selectedID } ?? works[0]
    }

    public func selecting(_ id: String) -> WorkCatalog {
        var copy = self
        if works.contains(where: { $0.id == id }) {
            copy.selectedID = id
        }
        return copy
    }

    public func replacing(_ work: WorkRequirement) -> WorkCatalog {
        var copy = self
        guard let index = copy.works.firstIndex(where: { $0.id == work.id }) else { return copy }
        copy.works[index] = work
        return copy
    }

    /// 保存済みの数値を仮値の上に載せる。新しい作業は残す。
    public static func merging(saved: WorkCatalog) -> WorkCatalog {
        var works = provisional.works.map { base in
            saved.works.first { $0.id == base.id } ?? base
        }
        for extra in saved.works where !works.contains(where: { $0.id == extra.id }) {
            works.append(extra)
        }
        let factor = saved.optimisticSafetyFactor.isFinite && saved.optimisticSafetyFactor >= 1
            ? saved.optimisticSafetyFactor
            : defaultSafetyFactor
        let selected = works.contains(where: { $0.id == saved.selectedID }) ? saved.selectedID : provisional.selectedID
        return WorkCatalog(selectedID: selected, optimisticSafetyFactor: factor, works: works)
    }

    public static func load(from directory: URL) -> WorkCatalog {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(WorkCatalog.self, from: data) else {
            return provisional
        }
        return merging(saved: saved)
    }

    public func save(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }
}

/// 受信機と補正の組。三角点検証で楽観的だった組に係数をかける。
public struct InstrumentState: Codable, Hashable, Sendable, Equatable {
    public var receiver: ReceiverKind
    public var stage: PositionStage
    public var fixQuality: FixQuality

    public init(receiver: ReceiverKind, stage: PositionStage, fixQuality: FixQuality) {
        self.receiver = receiver
        self.stage = stage
        self.fixQuality = fixQuality
    }

    public init(_ position: GeodeticPosition) {
        self.receiver = position.receiver
        self.stage = position.stage
        self.fixQuality = position.fixQuality
    }
}

public struct InstrumentTrust: Codable, Equatable, Sendable {
    public static let fileName = "instrument-trust.json"
    public var optimistic: [InstrumentState]

    public init(optimistic: [InstrumentState] = []) {
        self.optimistic = optimistic
    }

    public func contains(_ state: InstrumentState) -> Bool {
        optimistic.contains(state)
    }

    public func factor(for position: GeodeticPosition, safetyFactor: Double) -> Double {
        let factor = safetyFactor.isFinite && safetyFactor >= 1 ? safetyFactor : 1
        return contains(InstrumentState(position)) ? factor : 1
    }

    public func setting(_ state: InstrumentState, optimistic isOptimistic: Bool) -> InstrumentTrust {
        var copy = self
        copy.optimistic.removeAll { $0 == state }
        if isOptimistic {
            copy.optimistic.append(state)
        }
        return copy
    }

    public static func load(from directory: URL) -> InstrumentTrust {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(InstrumentTrust.self, from: data) else {
            return InstrumentTrust()
        }
        return saved
    }

    public func save(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }
}

/// 要求に届く手段の目安。仮の値で、判定の文言にだけ使う。
public struct ReachingMethod: Equatable, Sendable {
    public var id: String
    public var title: String
    public var horizontalMeters: Double
    public var verticalMeters: Double

    public init(id: String, title: String, horizontalMeters: Double, verticalMeters: Double) {
        self.id = id
        self.title = title
        self.horizontalMeters = horizontalMeters
        self.verticalMeters = verticalMeters
    }

    public func reaches(_ work: WorkRequirement) -> Bool {
        horizontalMeters <= work.horizontalMeters && verticalMeters <= work.verticalMeters
    }
}

public enum ReachingMethods {
    /// 三角点補正は概略まで。CLAS は 5cm／10cm。RTK は 2cm／3cm。TS は 5mm。
    public static let all: [ReachingMethod] = [
        ReachingMethod(id: "control", title: "三角点補正", horizontalMeters: 0.50, verticalMeters: 0.50),
        ReachingMethod(id: "clas", title: "CLAS", horizontalMeters: 0.05, verticalMeters: 0.10),
        ReachingMethod(id: "rtk", title: "RTK", horizontalMeters: 0.02, verticalMeters: 0.03),
        ReachingMethod(id: "ts", title: "TS", horizontalMeters: 0.005, verticalMeters: 0.005)
    ]

    public static func reaching(_ work: WorkRequirement) -> [ReachingMethod] {
        all.filter { $0.reaches(work) }
    }
}

public enum WorkFit: String, Equatable, Sendable {
    case meet
    case close
    case short
}

public struct AxisJudgment: Equatable, Sendable {
    public var reportedMeters: Double
    public var effectiveMeters: Double
    public var requirementMeters: Double
    public var fit: WorkFit
    public var shortfallMeters: Double

    public init(
        reportedMeters: Double,
        effectiveMeters: Double,
        requirementMeters: Double,
        fit: WorkFit,
        shortfallMeters: Double
    ) {
        self.reportedMeters = reportedMeters
        self.effectiveMeters = effectiveMeters
        self.requirementMeters = requirementMeters
        self.fit = fit
        self.shortfallMeters = shortfallMeters
    }
}

public enum WorkJudgment {
    public static func axis(reported: Double, requirement: Double, factor: Double) -> AxisJudgment? {
        guard reported.isFinite, reported >= 0, requirement.isFinite, requirement > 0 else { return nil }
        let applied = factor.isFinite && factor >= 1 ? factor : 1
        let effective = reported * applied
        let fit: WorkFit
        if effective <= requirement {
            fit = .meet
        } else if effective <= requirement * 2 {
            fit = .close
        } else {
            fit = .short
        }
        let shortfall = fit == .meet ? 0 : max(0, effective - requirement)
        return AxisJudgment(
            reportedMeters: reported,
            effectiveMeters: effective,
            requirementMeters: requirement,
            fit: fit,
            shortfallMeters: shortfall
        )
    }

    public static func tone(horizontal: AxisJudgment?, vertical: AxisJudgment?, verticalMissing: Bool) -> AccuracyTone {
        guard horizontal != nil || vertical != nil || verticalMissing else { return .grey }
        let fits = [horizontal?.fit, vertical?.fit].compactMap { $0 }
        if fits.contains(.short) { return .red }
        if verticalMissing || fits.contains(.close) { return .yellow }
        if fits.isEmpty { return .grey }
        return .green
    }

    public static func guidance(
        work: WorkRequirement,
        horizontal: AxisJudgment?,
        vertical: AxisJudgment?,
        verticalMissing: Bool
    ) -> String {
        var parts: [String] = []
        if let horizontal, horizontal.fit != .meet {
            parts.append("水平が\(WorkText.shortfall(horizontal.shortfallMeters))足りません")
        }
        if verticalMissing {
            parts.append("高さが未取得なので、この作業では緑にしません")
        } else if let vertical, vertical.fit != .meet {
            parts.append("高さが\(WorkText.shortfall(vertical.shortfallMeters))足りません")
        }
        guard !parts.isEmpty else { return "" }
        let methods = ReachingMethods.reaching(work)
        let means = methods.isEmpty ? "今の手段の目安では届きません" : "届く手段: " + methods.map(\.title).joined(separator: "、")
        return parts.joined(separator: "。") + "。" + means + "。"
    }

    public static func caution(factor: Double) -> String {
        guard factor > 1 else { return "" }
        return "この機器の報告は楽観的だったので、判定は\(WorkText.factor(factor))倍で見ています。"
    }
}

public enum WorkText {
    public static func shortfall(_ meters: Double) -> String {
        let centimeters = Int((meters * 100).rounded(.toNearestOrAwayFromZero))
        let shown = centimeters == 0 && meters > 0 ? 1 : centimeters
        return "あと\(shown)cm"
    }

    public static func factor(_ value: Double) -> String {
        FixedNumber.string(value, fractionDigits: value.rounded() == value ? 0 : 1)
    }
}
