import SwiftUI
import SurveyCore

struct WorkBar: View {
    @ObservedObject var field: FieldModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(field.workCatalog.works) { work in
                    Button {
                        field.selectWork(work.id)
                    } label: {
                        Text(work.shortTitle)
                            .font(SurveyType(16, .heavy))
                            .padding(.horizontal, 14)
                            .frame(minHeight: OutdoorContrast.primaryPoints)
                            .foregroundStyle(field.workCatalog.selectedID == work.id ? SurveyColor.onAccent : SurveyColor.muted)
                            .background(
                                field.workCatalog.selectedID == work.id ? SurveyColor.blue : SurveyColor.card,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(work.title)
                    .accessibilityAddTraits(field.workCatalog.selectedID == work.id ? .isSelected : [])
                }
                Button {
                    field.showsWorkSettings = true
                } label: {
                    Text("数値")
                        .font(SurveyType(16, .heavy))
                        .padding(.horizontal, 14)
                        .frame(minHeight: OutdoorContrast.primaryPoints)
                        .foregroundStyle(SurveyColor.text)
                        .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("要求精度を編集")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(SurveyColor.background)
            .overlay(alignment: .top) {
                Rectangle().fill(SurveyColor.line).frame(height: SurveyColor.stroke)
            }
        .sheet(isPresented: $field.showsWorkSettings) {
            WorkSettingsSheet(field: field)
        }
    }
}

struct WorkSettingsSheet: View {
    @ObservedObject var field: FieldModel
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [Row] = []
    @State private var factor = ""
    @State private var problem = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("仮の既定値です。現場に合わせて直すと、SitePack の work-requirements.json に残ります。")
                        .font(SurveyType(15, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach($rows) { $row in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(row.title)
                                .font(SurveyType(18, .heavy))
                            HStack(spacing: 8) {
                                labeledField("水平 m", text: $row.horizontal)
                                labeledField("高さ m", text: $row.vertical)
                            }
                        }
                        .padding(12)
                        .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("楽観的なときの係数")
                            .font(SurveyType(18, .heavy))
                        Text("三角点で報告が楽観的だった機器は、この倍率をかけてから要求と比べます。")
                            .font(SurveyType(14, .semibold))
                            .foregroundStyle(SurveyColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        labeledField("倍", text: $factor)
                    }
                    .padding(12)
                    .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    if !problem.isEmpty {
                        Text(problem)
                            .font(SurveyType(15, .heavy))
                            .foregroundStyle(SurveyColor.amber)
                    }
                }
                .padding(16)
            }
            .background(SurveyColor.background)
            .navigationTitle("要求精度")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
        }
        .modifier(SurveyScheme())
        .onAppear(perform: load)
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SurveyType(13, .bold))
                .foregroundStyle(SurveyColor.muted)
            TextField(title, text: text)
                .keyboardType(.decimalPad)
                .font(SurveyType(18, .bold, mono: true))
                .padding(10)
                .background(SurveyColor.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func load() {
        rows = field.workCatalog.works.map {
            Row(
                id: $0.id,
                title: $0.title,
                shortTitle: $0.shortTitle,
                horizontal: number($0.horizontalMeters),
                vertical: number($0.verticalMeters)
            )
        }
        factor = number(field.workCatalog.optimisticSafetyFactor)
    }

    private func save() {
        guard let safety = parse(factor), safety >= 1 else {
            problem = "係数は 1 以上の数にしてください。"
            return
        }
        var works: [WorkRequirement] = []
        for row in rows {
            guard let horizontal = parse(row.horizontal), horizontal > 0,
                  let vertical = parse(row.vertical), vertical > 0 else {
                problem = "\(row.title) の水平と高さは、0 より大きい数にしてください。"
                return
            }
            works.append(WorkRequirement(
                id: row.id,
                title: row.title,
                shortTitle: row.shortTitle,
                horizontalMeters: horizontal,
                verticalMeters: vertical
            ))
        }
        field.applyWorkEdits(works, safetyFactor: safety)
        dismiss()
    }

    private func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    private func number(_ value: Double) -> String {
        FixedNumber.string(value, fractionDigits: 3)
    }
}

private struct Row: Identifiable {
    var id: String
    var title: String
    var shortTitle: String
    var horizontal: String
    var vertical: String
}
