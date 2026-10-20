import SwiftUI
import SurveyCore

struct CampaignSummary: View {
    @ObservedObject var field: FieldModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(field.benchmark?.point.name ?? "三角点")
                .font(.system(size: 22, weight: .heavy))
            Text("\(field.rounds.count) / \(field.plannedRounds) 回")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(SurveyColor.muted)
            if let comparison = field.comparison {
                ForEach(comparison.rounds) { round in
                    roundBlock(round)
                }
                ForEach(Array(comparison.gaps.enumerated()), id: \.offset) { _, gap in
                    Text(CampaignText.gapLine(gap))
                        .font(.system(size: 15, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(CampaignText.overallLine(comparison.overall))
                    .font(.system(size: 18, weight: .heavy))
                    .fixedSize(horizontal: false, vertical: true)
                Text(CampaignText.scatterLine(horizontal: comparison.horizontalScatterMeters, aligned: comparison.aligned))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(comparison.aligned ? SurveyColor.text : SurveyColor.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let statistics = field.benchmarkStatistics {
                Text(BenchmarkText.spread(std: statistics.horizontalStdMeters, percentile95: statistics.horizontal95Meters))
                    .font(.system(size: 14, weight: .bold))
                Text(BenchmarkText.verticalNote(statistics))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(BenchmarkText.horizontalOptimism(statistics))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(statistics.horizontalOptimistic == true ? SurveyColor.amber : SurveyColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let check = field.returnCheck {
                Text(CampaignText.returnLine(check))
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(check.valid ? SurveyColor.green : SurveyColor.amber)
                    .fixedSize(horizontal: false, vertical: true)
                if !check.valid {
                    wideButton("時刻で割り振る", action: { field.chooseReturn(.apportion) })
                    wideButton("要再測の印", action: { field.chooseReturn(.resurvey) })
                }
            }
            if let message = field.benchmarkMessage {
                Text(message)
                    .font(.system(size: 14, weight: .semibold))
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
                            .font(.system(size: 18, weight: .heavy))
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(SurveyColor.blue)
                            .foregroundStyle(SurveyColor.text)
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
                .font(.system(size: 16, weight: .heavy))
                .fixedSize(horizontal: false, vertical: true)
            Text(CampaignText.settledLine(round.settledElapsedSeconds))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(SurveyColor.muted)
            ConvergenceChart(curve: round.curve)
        }
    }

    private func wideButton(_ title: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .heavy))
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(filled ? SurveyColor.blue : SurveyColor.background)
                .foregroundStyle(SurveyColor.text)
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
            .font(.system(size: 12, weight: .bold))
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
                .font(.system(size: 15, weight: .heavy))
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
