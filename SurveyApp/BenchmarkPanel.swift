import SwiftUI
import SurveyCore

struct BenchmarkHint: View {
    let notice: String?
    let loadedCount: Int
    let visibleCount: Int

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(notice == nil ? SurveyColor.muted : SurveyColor.amber)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(SurveyColor.card.opacity(0.96), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var message: String {
        if let notice { return notice }
        if visibleCount > 0 { return "三角点をタップすると、検証の記録を始めます。" }
        if loadedCount > 0 { return "近くに見本の点が無いときは、地図を引いて探します。" }
        return "基準点がありません。"
    }
}

struct BenchmarkCard: View {
    @ObservedObject var field: FieldModel

    var body: some View {
        ScrollView {
            card
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("三角点で検証")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(SurveyColor.muted)
            if field.isBenchmarkRunning, let recorder = field.benchmark {
                running(recorder)
            } else if !field.rounds.isEmpty {
                CampaignSummary(field: field)
            } else if let point = field.selectedControlPoint {
                ready(point)
            }
        }
        .foregroundStyle(SurveyColor.text)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SurveyColor.card.opacity(0.96), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(SurveyColor.line, lineWidth: 1)
        )
    }

    private func ready(_ point: ControlPoint) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(pointTitle(point))
                .font(.system(size: 22, weight: .heavy))
            Text(CoordinateText.latitude(point.latitudeDegrees) + "  " + CoordinateText.longitude(point.longitudeDegrees))
                .font(.system(size: 16, weight: .bold, design: .monospaced))
            Text(heightLine(point))
                .font(.system(size: 16, weight: .semibold))
            if !point.sourceNote.isEmpty {
                Text(point.sourceNote)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SurveyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("毎回、置き直して向きを変えます。")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SurveyColor.muted)
            HStack(spacing: 8) {
                ForEach([1, 3, 5], id: \.self) { count in
                    Button {
                        field.plannedRounds = count
                    } label: {
                        Text("\(count)回")
                            .font(.system(size: 16, weight: .heavy))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(field.plannedRounds == count ? SurveyColor.blue : SurveyColor.background)
                            .foregroundStyle(SurveyColor.text)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                ForEach(BenchmarkPlan.durationChoices, id: \.self) { seconds in
                    Button {
                        field.benchmarkDurationSeconds = seconds
                    } label: {
                        Text(BenchmarkPlan.durationTitle(seconds))
                            .font(.system(size: 16, weight: .heavy))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(field.benchmarkDurationSeconds == seconds ? SurveyColor.blue : SurveyColor.background)
                            .foregroundStyle(SurveyColor.text)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                Button(action: field.startBenchmark) {
                    Text("記録を始める")
                        .font(.system(size: 18, weight: .heavy))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(SurveyColor.blue)
                        .foregroundStyle(SurveyColor.text)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                Button(action: field.dismissBenchmark) {
                    Text("閉じる")
                        .font(.system(size: 18, weight: .heavy))
                        .frame(minWidth: 88, minHeight: 56)
                        .background(SurveyColor.background)
                        .foregroundStyle(SurveyColor.text)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func running(_ recorder: BenchmarkRecorder) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(recorder.point.name)
                .font(.system(size: 22, weight: .heavy))
            Text("\(field.rounds.count + 1) / \(field.plannedRounds) 回")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(SurveyColor.muted)
            Text("\(recorder.samples.count) / \(recorder.plan.expectedCount) 点")
                .font(.system(size: 28, weight: .heavy, design: .monospaced))
            Text("1秒に1点。\(BenchmarkPlan.durationTitle(recorder.plan.durationSeconds))で止まります。")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SurveyColor.muted)
            Button(action: field.cancelBenchmark) {
                Text("中止")
                    .font(.system(size: 18, weight: .heavy))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(SurveyColor.background)
                    .foregroundStyle(SurveyColor.text)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func pointTitle(_ point: ControlPoint) -> String {
        if let grade = point.grade, !grade.isEmpty {
            return "\(grade)\(point.kind) \(point.name)"
        }
        return "\(point.kind) \(point.name)"
    }

    private func heightLine(_ point: ControlPoint) -> String {
        if let ellipsoidal = point.comparableEllipsoidalHeightMeters {
            return "楕円体高 \(FixedNumber.string(ellipsoidal, fractionDigits: 3))m"
        }
        if point.heightKind == .orthometric, let height = point.heightMeters {
            return "標高 \(FixedNumber.string(height, fractionDigits: 4))m（楕円体高ではない）"
        }
        return "高さは未収録"
    }
}
