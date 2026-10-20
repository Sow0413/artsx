import Foundation

/// 測量本体の時間。大きい現場でも、ここを超えたら遅い。
public enum SurveyBudget {
    /// 起動してから、図面の解析を待たずに操作できるまで。
    public static let operableMilliseconds = 2_000.0
    /// 測設のスナップと、座標簿の絞り込み。
    public static let queryMilliseconds = 100.0
    /// パンとズームを 60fps で出す一枚。
    public static let frameMilliseconds = 1_000.0 / 60.0
    /// 延長の目標。メートル。
    public static let siteMeters = 1_000.0
    public static let bookPoints = 50_000
    public static let drawingBytes = 8_000_000
}

public struct WorkProgress: Equatable, Sendable {
    public var label: String
    public var fraction: Double

    public init(label: String, fraction: Double) {
        self.label = label
        self.fraction = min(1, max(0, fraction))
    }
}

public enum SurveyBench {
    /// 毎回の実行で、名前とミリ秒を出す。
    @discardableResult
    public static func measure(_ name: String, budget milliseconds: Double, _ body: () throws -> Void) rethrows -> Double {
        let start = Date()
        try body()
        let elapsed = Date().timeIntervalSince(start) * 1_000
        let mark = elapsed <= milliseconds ? "以内" : "超過"
        print(String(format: "SURVEY BENCH %@ %.1fms / 目標 %.1fms %@", name, elapsed, milliseconds, mark))
        return elapsed
    }
}
