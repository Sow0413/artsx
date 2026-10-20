import SwiftUI
import SurveyCore

/// このプロジェクトの件数。全現場を足すのは P510 の集計スクリプト。
struct IncidentStatsSheet: View {
    @ObservedObject var field: FieldModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("この現場のヒヤリと接近です。全プロジェクトを足すのは P510 です。")
                        .font(SurveyType(15, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(SafetyNotice.text)
                        .font(SurveyType(13, .heavy))
                        .foregroundStyle(SurveyColor.amber)
                    if field.extras.stats {
                    Toggle("地図にヒートマップ", isOn: $field.showIncidentHeat)
                        .font(SurveyType(16, .heavy))
                    Toggle("個人名を役割にする（既定）", isOn: $field.anonymizeStats)
                        .font(SurveyType(16, .heavy))
                        .onChange(of: field.anonymizeStats) { _, _ in
                            field.reloadIncidentStats()
                        }
                    Text("ヒヤリの件数は、既定で役割ごとにまとめます。個人名は出しません。")
                        .font(SurveyType(15, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    weatherPicker
                    countBlock("作業別", IncidentStats.countsByWork(field.incidentStatRows))
                    countBlock("時間帯別", IncidentStats.countsByTime(field.incidentStatRows))
                    if field.incidentStatRows.isEmpty {
                        Text("確定した記録はまだありません。")
                            .font(SurveyType(15, .heavy))
                            .foregroundStyle(SurveyColor.muted)
                    } else {
                        Text("直近")
                            .font(SurveyType(18, .heavy))
                        ForEach(Array(field.incidentStatRows.suffix(6).reversed()), id: \.recordID) { row in
                            Text("\(row.timeBand)　\(row.workKind)　\(row.level)　\(row.party)")
                                .font(SurveyType(15, .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    Button("集計CSVを書く") {
                        field.exportIncidentStats()
                    }
                    .font(SurveyType(18, .black))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(SurveyColor.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    if field.extras.accidentReport {
                    Text("対外説明")
                        .font(SurveyType(18, .heavy))
                    Text("確定した記録から、労基署や警察に見せるPDFを作ります。労働者死傷病報告の様式は作らず、提出もしません。氏名を出すか、関係者番号にするかを選べます。")
                        .font(SurveyType(15, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if field.sealedIncidents.isEmpty {
                        Text("確定した記録はまだありません。")
                            .font(SurveyType(15, .heavy))
                            .foregroundStyle(SurveyColor.muted)
                    } else {
                        ForEach(field.sealedIncidents) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.title)
                                    .font(SurveyType(16, .heavy))
                                HStack(spacing: 8) {
                                    reportButton("氏名を出してPDF") {
                                        field.exportAccidentReport(item.id, names: .shown)
                                    }
                                    reportButton("匿名でPDF") {
                                        field.exportAccidentReport(item.id, names: .anonymous)
                                    }
                                }
                                reportButton("救急到着を追記") {
                                    field.noteAmbulance(item.id)
                                }
                            }
                        }
                    }
                    }
                    if let message = field.statMessage {
                        Text(message)
                            .font(SurveyType(14, .heavy))
                            .foregroundStyle(SurveyColor.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }
            .background(SurveyColor.background)
            .foregroundStyle(SurveyColor.text)
            .navigationTitle("統計")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .onAppear { field.reloadIncidentStats() }
    }

    private var weatherPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("天候")
                .font(SurveyType(18, .heavy))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], alignment: .leading, spacing: 8) {
                weatherChip("", "未設定")
                ForEach(IncidentWeather.allCases, id: \.rawValue) { item in
                    weatherChip(item.rawValue, item.rawValue)
                }
            }
        }
    }

    private func weatherChip(_ value: String, _ title: String) -> some View {
        let selected = field.drawing.weatherLabel == value
        return Button(title) {
            field.drawing.setWeather(value)
            field.reloadIncidentStats()
        }
        .font(SurveyType(15, .heavy))
        .foregroundStyle(selected ? Color.white : SurveyColor.text)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(selected ? SurveyColor.blue : SurveyColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func reportButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(SurveyType(15, .black))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(SurveyColor.red)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func countBlock(_ title: String, _ rows: [IncidentStatCount]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(SurveyType(18, .heavy))
            if rows.isEmpty {
                Text("0件")
                    .font(SurveyType(15, .semibold))
                    .foregroundStyle(SurveyColor.muted)
            } else {
                ForEach(rows, id: \.key) { row in
                    HStack {
                        Text(row.key)
                        Spacer()
                        Text("\(row.count)")
                    }
                    .font(SurveyType(17, .heavy))
                }
            }
        }
    }
}
