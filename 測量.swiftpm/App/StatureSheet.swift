import SwiftUI
import SurveyCore

struct StatureSheet: View {
    @ObservedObject var field: FieldModel
    @Environment(\.dismiss) private var dismiss
    @State private var statureText = ""
    @State private var style: HoldStyle = .chest
    @State private var manualText = ""
    @State private var chestText = ""
    @State private var eyeText = ""
    @State private var cabText = ""
    @State private var problem = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("段階0の iPhone だけで、端末の高さから持ち高さを引いて地盤高にします。外部GNSSのポール高とは別にします。")
                        .font(SurveyType(16, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let label = StatureMath.correction(for: draft, stage: .iphone, receiver: .iphoneGPS)?.screenLabel {
                        Text(label)
                            .font(SurveyType(28, .heavy))
                    } else {
                        Text("身長が未登録です")
                            .font(SurveyType(22, .heavy))
                    }
                    fieldBlock("身長 m") {
                        TextField("1.71", text: $statureText)
                            .keyboardType(.decimalPad)
                            .autocorrectionDisabled()
                    }
                    Text("持ち方")
                        .font(SurveyType(18, .heavy))
                    ForEach(HoldStyle.allCases, id: \.self) { item in
                        Button(item.title) { style = item }
                            .buttonStyle(.plain)
                            .font(SurveyType(18, .heavy))
                            .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                            .background(style == item ? SurveyColor.blue : SurveyColor.card)
                            .foregroundStyle(style == item ? SurveyColor.onAccent : SurveyColor.text)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(SurveyColor.line, lineWidth: SurveyColor.stroke)
                            )
                    }
                    if style == .manual {
                        fieldBlock("持ち高 m") {
                            TextField("1.23", text: $manualText)
                                .keyboardType(.decimalPad)
                                .autocorrectionDisabled()
                        }
                    }
                    Text("係数")
                        .font(SurveyType(18, .heavy))
                    Text("胸の前は身長×係数。目の高さは身長からこの長さを引きます。運転席は、オペ画面の視線高とは別に、既定 2m です。")
                        .font(SurveyType(14, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    fieldBlock("胸の係数") {
                        TextField("0.72", text: $chestText)
                            .keyboardType(.decimalPad)
                            .autocorrectionDisabled()
                    }
                    fieldBlock("目の高さから引く m") {
                        TextField("0.10", text: $eyeText)
                            .keyboardType(.decimalPad)
                            .autocorrectionDisabled()
                    }
                    fieldBlock("運転席 m") {
                        TextField("2", text: $cabText)
                            .keyboardType(.decimalPad)
                            .autocorrectionDisabled()
                    }
                    if !problem.isEmpty {
                        Text(problem)
                            .font(SurveyType(15, .heavy))
                            .foregroundStyle(SurveyColor.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("保存") { save() }
                        .buttonStyle(.plain)
                        .font(SurveyType(18, .heavy))
                        .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                        .background(SurveyColor.blue)
                        .foregroundStyle(SurveyColor.onAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Button("取った点を、今の身長でやり直す") {
                        guard saveProfile() else { return }
                        field.reapplyStature()
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .font(SurveyType(18, .heavy))
                    .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                    .background(SurveyColor.card)
                    .foregroundStyle(SurveyColor.text)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(SurveyColor.line, lineWidth: SurveyColor.stroke)
                    )
                }
                .padding(20)
            }
            .background(SurveyColor.background)
            .foregroundStyle(SurveyColor.text)
            .navigationTitle("身長")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .font(SurveyType(17, .heavy))
                }
            }
        }
        .modifier(SurveyScheme())
        .onAppear(perform: load)
    }

    private var draft: StatureProfile {
        StatureProfile(
            statureMeters: Double(statureText.trimmingCharacters(in: .whitespaces)),
            style: style,
            manualMeters: Double(manualText.trimmingCharacters(in: .whitespaces)) ?? 0,
            coefficients: StatureCoefficients(
                chestFactor: Double(chestText) ?? StatureCoefficients.standard.chestFactor,
                eyeDropMeters: Double(eyeText) ?? StatureCoefficients.standard.eyeDropMeters,
                cabMeters: Double(cabText) ?? StatureCoefficients.standard.cabMeters
            )
        )
    }

    private func fieldBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SurveyType(15, .heavy))
            content()
                .font(SurveyType(20, .heavy, mono: true))
                .padding(10)
                .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func load() {
        let profile = field.stature
        statureText = profile.statureMeters.map { String(format: "%g", $0) } ?? ""
        style = profile.style
        manualText = String(format: "%g", profile.manualMeters)
        chestText = String(format: "%g", profile.coefficients.chestFactor)
        eyeText = String(format: "%g", profile.coefficients.eyeDropMeters)
        cabText = String(format: "%g", profile.coefficients.cabMeters)
    }

    private func save() {
        guard saveProfile() else { return }
        dismiss()
    }

    private func saveProfile() -> Bool {
        let trimmed = statureText.trimmingCharacters(in: .whitespaces)
        let stature = trimmed.isEmpty ? nil : Double(trimmed)
        if trimmed.isEmpty == false, stature == nil || (stature ?? 0) <= 0 || (stature ?? 0) > 3 {
            problem = "身長は 0m より大きく、3m までです。"
            return false
        }
        guard let chest = Double(chestText), chest >= 0, chest <= 1.5,
              let eye = Double(eyeText), eye >= 0, eye <= 1,
              let cab = Double(cabText), cab >= 0, cab <= 20,
              let manual = Double(manualText), manual >= 0, manual <= 20 else {
            problem = "係数か持ち高が読めません。"
            return false
        }
        field.saveStature(StatureProfile(
            statureMeters: stature,
            style: style,
            manualMeters: manual,
            coefficients: StatureCoefficients(chestFactor: chest, eyeDropMeters: eye, cabMeters: cab)
        ))
        problem = ""
        return true
    }
}
