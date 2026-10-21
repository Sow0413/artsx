import SwiftUI
import SurveyCore

struct ExportTabView: View {
    @ObservedObject var field: FieldModel
    @State private var accuracyText = ""
    @State private var importedDay = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 0) {
                    Text("出す")
                        .font(SurveyType(28, .heavy))
                    InfoButton(help: .delivery)
                    Spacer(minLength: 0)
                }
                filters
                let preview = field.bookPreview()
                Text("\(preview.count) 点")
                    .font(SurveyType(18, .heavy))
                names(preview.sample)
                ForEach(DeliveryFormat.allCases) { format in
                    Button {
                        field.exportDelivery(format)
                    } label: {
                        Text(format.label)
                            .font(SurveyType(18, .heavy))
                            .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                            .background(SurveyColor.blue)
                            .foregroundStyle(SurveyColor.onAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                if let message = field.exportMessage {
                    Text(message)
                        .font(SurveyType(15, .heavy))
                        .foregroundStyle(SurveyColor.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let url = field.exportURL {
                    ShareLink(item: url) {
                        Text("共有シートで渡す")
                            .font(SurveyType(18, .heavy))
                            .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                            .background(SurveyColor.blue)
                            .foregroundStyle(SurveyColor.onAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SurveyColor.background)
        .foregroundStyle(SurveyColor.text)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("絞り込み")
                .font(SurveyType(18, .heavy))
            fieldRow("点名の頭") {
                TextField("T", text: prefixBinding)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            fieldRow("種類") {
                TextField("基準点", text: kindBinding)
                    .autocorrectionDisabled()
            }
            fieldRow("出典") {
                TextField("観測", text: sourceBinding)
                    .autocorrectionDisabled()
            }
            fieldRow("解段階") {
                Picker("解段階", selection: stageBinding) {
                    Text("指定しない").tag(-1)
                    Text("段階0以上").tag(0)
                    Text("段階1以上").tag(1)
                    Text("段階2以上").tag(2)
                    Text("段階3").tag(3)
                }
                .pickerStyle(.menu)
            }
            fieldRow("水平精度 m 以内") {
                TextField("0.03", text: $accuracyText)
                    .keyboardType(.decimalPad)
                    .autocorrectionDisabled()
                    .onChange(of: accuracyText) { _, value in
                        let trimmed = value.trimmingCharacters(in: .whitespaces)
                        field.bookQuery.maximumHorizontalMeters = trimmed.isEmpty ? nil : Double(trimmed)
                    }
            }
            fieldRow("取込日") {
                TextField("2026-10-20", text: $importedDay)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .onChange(of: importedDay) { _, value in
                        let trimmed = value.trimmingCharacters(in: .whitespaces)
                        field.bookQuery.importedDay = trimmed.isEmpty ? nil : trimmed
                    }
            }
            if let bounds = field.bookQuery.bounds {
                Text(boundsLabel(bounds))
                    .font(SurveyType(13, .semibold, mono: true))
                    .fixedSize(horizontal: false, vertical: true)
                Button("範囲を外す") {
                    field.bookQuery.bounds = nil
                }
                .font(SurveyType(15, .heavy))
                .foregroundStyle(SurveyColor.amber)
            }
            HStack(spacing: 10) {
                Button("地図で範囲を囲む") {
                    field.beginBookEnclosure()
                }
                .font(SurveyType(15, .heavy))
                .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                .background(SurveyColor.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button("条件を消す") {
                    accuracyText = ""
                    importedDay = ""
                    field.clearBookFilters()
                }
                .font(SurveyType(15, .heavy))
                .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                .background(SurveyColor.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func names(_ shown: [CoordinateBookEntry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if shown.isEmpty {
                Text("合う点がありません。")
                    .font(SurveyType(15, .semibold))
                    .foregroundStyle(SurveyColor.muted)
            } else {
                ForEach(Array(shown), id: \.name) { entry in
                    Text(entryLine(entry))
                        .font(SurveyType(14, .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func fieldRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SurveyType(13, .heavy))
                .foregroundStyle(SurveyColor.muted)
            content()
                .textFieldStyle(.roundedBorder)
        }
    }

    private var prefixBinding: Binding<String> {
        Binding(get: { field.bookQuery.namePrefix }, set: { field.bookQuery.namePrefix = $0 })
    }

    private var kindBinding: Binding<String> {
        Binding(get: { field.bookQuery.kind }, set: { field.bookQuery.kind = $0 })
    }

    private var sourceBinding: Binding<String> {
        Binding(get: { field.bookQuery.source }, set: { field.bookQuery.source = $0 })
    }

    private var stageBinding: Binding<Int> {
        Binding(
            get: { field.bookQuery.minimumStage?.rawValue ?? -1 },
            set: { field.bookQuery.minimumStage = PositionStage(rawValue: $0) }
        )
    }

    private func boundsLabel(_ bounds: GeoBounds) -> String {
        String(format: "N %.5f–%.5f  E %.5f–%.5f", bounds.south, bounds.north, bounds.west, bounds.east)
    }

    private func entryLine(_ entry: CoordinateBookEntry) -> String {
        let kind = entry.kind ?? "—"
        return "\(entry.name)  \(kind)  \(entry.source ?? "—")  \(solutionWord(entry))"
    }

    private func solutionWord(_ entry: CoordinateBookEntry) -> String {
        guard let solution = entry.solution else { return "—" }
        if entry.receiverLabel == "iPhone" { return "単独" }
        switch solution {
        case .rtkFix: return entry.receiverLabel == "CLAS" ? "CLAS" : "FIX"
        case .float: return "FLOAT"
        case .clas: return "CLAS"
        case .dgps: return "DGPS"
        case .standalone, .none: return "単独"
        }
    }
}
