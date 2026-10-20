import SwiftUI
import SurveyCore

struct CampaignSummary: View {
    @ObservedObject var field: FieldModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(field.benchmark?.point.name ?? "三角点")
                .font(SurveyType(22, .heavy))
            Text("\(field.rounds.count) / \(field.plannedRounds) 回")
                .font(SurveyType(15, .heavy))
                .foregroundStyle(SurveyColor.muted)
            if let comparison = field.comparison {
                ForEach(comparison.rounds) { round in
                    roundBlock(round)
                }
                ForEach(Array(comparison.gaps.enumerated()), id: \.offset) { _, gap in
                    Text(CampaignText.gapLine(gap))
                        .font(SurveyType(15, .bold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(CampaignText.overallLine(comparison.overall))
                    .font(SurveyType(18, .heavy))
                    .fixedSize(horizontal: false, vertical: true)
                Text(CampaignText.scatterLine(horizontal: comparison.horizontalScatterMeters, aligned: comparison.aligned))
                    .font(SurveyType(15, .semibold))
                    .foregroundStyle(comparison.aligned ? SurveyColor.text : SurveyColor.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let statistics = field.benchmarkStatistics {
                Text(BenchmarkText.spread(std: statistics.horizontalStdMeters, percentile95: statistics.horizontal95Meters))
                    .font(SurveyType(14, .bold))
                Text(BenchmarkText.verticalNote(statistics))
                    .font(SurveyType(14, .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(BenchmarkText.horizontalOptimism(statistics))
                    .font(SurveyType(15, .heavy))
                    .foregroundStyle(statistics.horizontalOptimistic == true ? SurveyColor.amber : SurveyColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let check = field.returnCheck {
                Text(CampaignText.returnLine(check))
                    .font(SurveyType(16, .heavy))
                    .foregroundStyle(check.valid ? SurveyColor.green : SurveyColor.amber)
                    .fixedSize(horizontal: false, vertical: true)
                if !check.valid {
                    wideButton("時刻で割り振る", action: { field.chooseReturn(.apportion) })
                    wideButton("要再測の印", action: { field.chooseReturn(.resurvey) })
                }
            }
            if let message = field.benchmarkMessage {
                Text(message)
                    .font(SurveyType(14, .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !field.campaignClosed {
                wideButton("次の回を記録", filled: true, action: field.startBenchmark)
                wideButton("この回数でまとめる", action: field.summarizeCampaign)
            } else if field.comparison?.aligned == true {
                wideButton("この三角点で補正", filled: true, action: field.applyControlCorrection)
            }
            HStack(spacing: 8) {
                if let url = field.benchmarkExportURL {
                    ShareLink(item: url) {
                        Text("CSV")
                            .font(SurveyType(18, .heavy))
                            .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                            .background(SurveyColor.blue)
                            .foregroundStyle(SurveyColor.onAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                wideButton("閉じる", action: field.dismissBenchmark)
            }
        }
    }

    private func roundBlock(_ round: RoundSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(CampaignText.roundLine(index: round.index, offset: round.offset))
                .font(SurveyType(16, .heavy))
                .fixedSize(horizontal: false, vertical: true)
            Text(CampaignText.settledLine(round.settledElapsedSeconds))
                .font(SurveyType(14, .bold))
                .foregroundStyle(SurveyColor.muted)
            ConvergenceChart(curve: round.curve)
        }
    }

    private func wideButton(_ title: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(SurveyType(18, .heavy))
                .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                .background(filled ? SurveyColor.blue : SurveyColor.background)
                .foregroundStyle(filled ? SurveyColor.onAccent : SurveyColor.text)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct ConvergenceChart: View {
    var curve: [ConvergenceSample]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Canvas { context, size in
                let drawn = Self.decimated(curve)
                guard drawn.count >= 2 else { return }
                let maxTime = max(drawn.map(\.elapsedSeconds).max() ?? 1, 1)
                let magnitudes = drawn.flatMap { sample -> [Double] in
                    var values = [sample.horizontalMeters]
                    if let vertical = sample.verticalMeters { values.append(abs(vertical)) }
                    return values
                }
                let maxValue = max(magnitudes.max() ?? 1, 0.01)
                func place(_ elapsed: Double, _ meters: Double) -> CGPoint {
                    CGPoint(
                        x: size.width * elapsed / maxTime,
                        y: size.height * (1 - min(max(meters, 0), maxValue) / maxValue)
                    )
                }
                var horizontal = Path()
                var vertical = Path()
                var verticalStarted = false
                for (index, sample) in drawn.enumerated() {
                    let point = place(sample.elapsedSeconds, sample.horizontalMeters)
                    if index == 0 { horizontal.move(to: point) } else { horizontal.addLine(to: point) }
                    if let height = sample.verticalMeters {
                        let point = place(sample.elapsedSeconds, abs(height))
                        if verticalStarted { vertical.addLine(to: point) } else {
                            vertical.move(to: point)
                            verticalStarted = true
                        }
                    }
                }
                context.stroke(horizontal, with: .color(SurveyColor.blue), lineWidth: 2)
                context.stroke(vertical, with: .color(SurveyColor.amber), lineWidth: 2)
            }
            .frame(height: 72)
            .background(SurveyColor.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack(spacing: 12) {
                Text("青が水平")
                Text("黄が高さ")
            }
            .font(SurveyType(12, .bold))
            .foregroundStyle(SurveyColor.muted)
        }
        .accessibilityLabel("置いてからの累積平均のずれ")
    }

    private static func decimated(_ curve: [ConvergenceSample]) -> [ConvergenceSample] {
        guard curve.count > 180 else { return curve }
        let step = max(curve.count / 180, 1)
        return curve.enumerated().compactMap { index, sample in
            index % step == 0 || index == curve.count - 1 ? sample : nil
        }
    }
}

struct CorrectionStatusBar: View {
    let correction: ControlCorrection

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let age = correction.age(at: context.date)
            Text(line(age))
                .font(SurveyType(15, .heavy))
                .foregroundStyle(age.stale ? SurveyColor.yellow : SurveyColor.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
        }
    }

    private func line(_ age: CorrectionAge) -> String {
        let clock = Self.clock.string(from: correction.acquiredAt)
        let base = "補正 \(correction.pointName) \(clock)取得・経過\(age.elapsedMinutes)分"
        return age.stale ? base + "。古いので判定に使っていません" : base
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
