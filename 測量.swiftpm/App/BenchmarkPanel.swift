import SwiftUI
import SurveyCore

struct BenchmarkHint: View {
    let notice: String?
    let loadedCount: Int
    let visibleCount: Int

    var body: some View {
        Text(message)
            .font(SurveyType(14, .semibold))
            .foregroundStyle(notice == nil ? SurveyColor.muted : SurveyColor.amber)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                .font(SurveyType(15, .heavy))
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
        .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(SurveyColor.line, lineWidth: 1)
        )
    }

    private func ready(_ point: ControlPoint) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(pointTitle(point))
                .font(SurveyType(22, .heavy))
            Text(CoordinateText.latitude(point.latitudeDegrees) + "  " + CoordinateText.longitude(point.longitudeDegrees))
                .font(SurveyType(16, .bold, mono: true))
            Text(heightLine(point))
                .font(SurveyType(16, .semibold))
            if !point.sourceNote.isEmpty {
                Text(point.sourceNote)
                    .font(SurveyType(13, .medium))
                    .foregroundStyle(SurveyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("毎回、置き直して向きを変えます。")
                .font(SurveyType(14, .semibold))
                .foregroundStyle(SurveyColor.muted)
            HStack(spacing: 8) {
                ForEach([1, 3, 5], id: \.self) { count in
                    Button {
                        field.plannedRounds = count
                    } label: {
                        Text("\(count)回")
                            .font(SurveyType(16, .heavy))
                            .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                            .background(field.plannedRounds == count ? SurveyColor.blue : SurveyColor.background)
                            .foregroundStyle(field.plannedRounds == count ? SurveyColor.onAccent : SurveyColor.text)
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
                            .font(SurveyType(16, .heavy))
                            .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                            .background(field.benchmarkDurationSeconds == seconds ? SurveyColor.blue : SurveyColor.background)
                            .foregroundStyle(field.benchmarkDurationSeconds == seconds ? SurveyColor.onAccent : SurveyColor.text)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                Button(action: field.startBenchmark) {
                    Text("記録を始める")
                        .font(SurveyType(18, .heavy))
                        .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                        .background(SurveyColor.blue)
                        .foregroundStyle(SurveyColor.onAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                Button(action: field.dismissBenchmark) {
                    Text("閉じる")
                        .font(SurveyType(18, .heavy))
                        .frame(minWidth: 88, minHeight: OutdoorContrast.primaryPoints)
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
                .font(SurveyType(22, .heavy))
            Text("\(field.rounds.count + 1) / \(field.plannedRounds) 回")
                .font(SurveyType(16, .heavy))
                .foregroundStyle(SurveyColor.muted)
            Text("\(recorder.samples.count) / \(recorder.plan.expectedCount) 点")
                .font(SurveyType(28, .heavy, mono: true))
            Text("1秒に1点。\(BenchmarkPlan.durationTitle(recorder.plan.durationSeconds))で止まります。")
                .font(SurveyType(15, .semibold))
                .foregroundStyle(SurveyColor.muted)
            Button(action: field.cancelBenchmark) {
                Text("中止")
                    .font(SurveyType(18, .heavy))
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
