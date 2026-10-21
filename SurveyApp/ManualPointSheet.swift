import SwiftUI
import SurveyCore

struct ManualPointSheet: View {
    @ObservedObject var field: FieldModel
    @State private var name = ""
    @State private var coordinate = ""
    @State private var height = ""
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    fieldRow("点名") {
                        TextField("K-1", text: $name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    fieldRow("座標") {
                        TextField("36.77450, 139.20081", text: $coordinate, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .lineLimit(2...4)
                    }
                    Text("十進の緯度経度、度分秒、または平面直角の X Y。カンマ区切りで貼れます。")
                        .font(SurveyType(13, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(counterpart)
                        .font(SurveyType(16, .heavy, mono: true))
                        .foregroundStyle(reading == nil ? SurveyColor.muted : SurveyColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    fieldRow("標高") {
                        TextField("空でもよい", text: $height)
                            .keyboardType(.numbersAndPunctuation)
                    }
                    if let notice {
                        Text(notice)
                            .font(SurveyType(15, .heavy))
                            .foregroundStyle(SurveyColor.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("保存") { save() }
                        .buttonStyle(SurveyPlainButton())
                }
                .padding(16)
            }
            .background(SurveyColor.background)
            .navigationTitle(name == "ここ" ? "ここ" : "点を登録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { field.showsManualPoint = false }
                        .font(SurveyType(17, .heavy))
                }
            }
        }
        .modifier(SurveyScheme())
        .onAppear {
            name = field.manualPointName
            coordinate = field.manualPointCoordinate
        }
    }

    private var reading: ManualPointFix? {
        ManualPoint.parse(coordinate, zone: field.drawing.zone)
    }

    private var counterpart: String {
        if coordinate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "入れると、緯度経度と平面直角を並べます。"
        }
        return reading?.counterpart ?? "緯度経度か、平面直角の X Y にしてください。"
    }

    private func fieldRow(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SurveyType(13, .heavy))
                .foregroundStyle(SurveyColor.muted)
            content()
                .font(SurveyType(18, .heavy, mono: true))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func save() {
        if let error = field.drawing.saveEnteredPoint(name: name, coordinate: coordinate, heightText: height) {
            notice = error
            return
        }
        field.ensureMapCad()
        field.tab = .map
        field.showsManualPoint = false
    }
}
