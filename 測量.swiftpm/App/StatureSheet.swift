import SwiftUI
import SurveyCore

struct StatureSheet: View {
    @ObservedObject var field: FieldModel
    @Environment(\.dismiss) private var dismiss
    @State private var statureText = ""
    @State private var style: HoldStyle = .sight
    @State private var manualText = ""
    @State private var elbowText = ""
    @State private var chestText = ""
    @State private var eyeText = ""
    @State private var cabText = ""
    @State private var knownText = ""
    @State private var problem = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("段階0の iPhone だけで、端末の高さから持ち高さを引いて地盤高にします。既定は画面の角度です。肘より上は代わりです。外部GNSSのポール高とは別にします。")
                        .font(SurveyType(16, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let label = StatureMath.correction(for: draft, stage: .iphone, receiver: .iphoneGPS, sight: field.liveSight)?.screenLabel {
                        Text(label)
                            .font(SurveyType(28, .heavy))
                    } else {
                        Text("身長が未登録です")
                            .font(SurveyType(22, .heavy))
                    }
                    fieldBlock("身長 m") {
                        TextField("1.70", text: $statureText)
                            .keyboardType(.decimalPad)
                            .autocorrectionDisabled()
                    }
                    Text("持ち方")
                        .font(SurveyType(18, .heavy))
                    ForEach(HoldStyle.allCases, id: \.self) { item in
                        Button(item.menuTitle(coefficients: draft.coefficients)) { style = item }
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
                    if style == .sight {
                        Text(sightLine)
                            .font(SurveyType(16, .heavy))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("アンテナは端末中心から上へ \(StatureMath.factorText(AntennaCatalog.alongUpMeters(model: field.deviceMachine)))m（この機種の定数）です。顔までの距離が測れないときは 0.35m です。")
                            .font(SurveyType(14, .semibold))
                            .foregroundStyle(SurveyColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if style == .manual {
                        fieldBlock("持ち高 m") {
                            TextField("1.19", text: $manualText)
                                .keyboardType(.decimalPad)
                                .autocorrectionDisabled()
                        }
                    }
                    Text("係数")
                        .font(SurveyType(18, .heavy))
                    Text("画面の角度は、目の高さ（身長から引く長さ）を使います。肘より上と胸の前は身長×係数。運転席は、オペ画面の視線高とは別に、既定 2m です。")
                        .font(SurveyType(14, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    fieldBlock("肘より上の係数") {
                        TextField("0.70", text: $elbowText)
                            .keyboardType(.decimalPad)
                            .autocorrectionDisabled()
                    }
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
                    Text("校正")
                        .font(SurveyType(18, .heavy))
                    Text("既知の楕円体高の点で、今の持ち方のまま1回観測します。端末の高さと既知高さの差を、肘より上の係数にします。")
                        .font(SurveyType(14, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    fieldBlock("既知の楕円体高 m") {
                        TextField("11.20", text: $knownText)
                            .keyboardType(.decimalPad)
                            .autocorrectionDisabled()
                    }
                    Button("今の高さで校正") { calibrateNow() }
                        .buttonStyle(.plain)
                        .font(SurveyType(18, .heavy))
                        .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                        .background(SurveyColor.card)
                        .foregroundStyle(SurveyColor.text)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(SurveyColor.line, lineWidth: SurveyColor.stroke)
                        )
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

    private var sightLine: String {
        if let note = StatureMath.correction(for: draft, stage: .iphone, receiver: .iphoneGPS, sight: field.liveSight)?.sightNote {
            return note
        }
        if draft.statureMeters == nil {
            return "身長が未登録です"
        }
        return "傾きを待っています"
    }

    private var draft: StatureProfile {
        StatureProfile(
            statureMeters: Double(statureText.trimmingCharacters(in: .whitespaces)),
            style: style,
            manualMeters: Double(manualText.trimmingCharacters(in: .whitespaces)) ?? 0,
            coefficients: StatureCoefficients(
                elbowFactor: Double(elbowText) ?? StatureCoefficients.standard.elbowFactor,
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
        elbowText = String(format: "%g", profile.coefficients.elbowFactor)
        chestText = String(format: "%g", profile.coefficients.chestFactor)
        eyeText = String(format: "%g", profile.coefficients.eyeDropMeters)
        cabText = String(format: "%g", profile.coefficients.cabMeters)
    }

    private func save() {
        guard saveProfile() else { return }
        dismiss()
    }

    private func calibrateNow() {
        guard let device = field.reading.position?.ellipsoidalHeightMeters, device.isFinite else {
            problem = "位置が無いので校正できません。"
            return
        }
        let trimmed = statureText.trimmingCharacters(in: .whitespaces)
        guard let stature = Double(trimmed), stature > 0, stature <= 3 else {
            problem = "身長は 0m より大きく、3m までです。"
            return
        }
        guard let known = Double(knownText.trimmingCharacters(in: .whitespaces)) else {
            problem = "既知の楕円体高が読めません。"
            return
        }
        guard let calibration = StatureMath.calibrate(deviceHeight: device, knownGround: known, stature: stature) else {
            problem = "この高さと身長では校正できません。"
            return
        }
        var profile = draft
        profile.statureMeters = stature
        profile = StatureMath.applying(calibration, to: profile)
        style = profile.style
        elbowText = String(format: "%g", profile.coefficients.elbowFactor)
        guard saveProfile() else { return }
        problem = ""
    }

    private func saveProfile() -> Bool {
        let trimmed = statureText.trimmingCharacters(in: .whitespaces)
        let stature = trimmed.isEmpty ? nil : Double(trimmed)
        if trimmed.isEmpty == false, stature == nil || (stature ?? 0) <= 0 || (stature ?? 0) > 3 {
            problem = "身長は 0m より大きく、3m までです。"
            return false
        }
        guard let elbow = Double(elbowText), elbow >= 0, elbow <= 1.5,
              let chest = Double(chestText), chest >= 0, chest <= 1.5,
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
            coefficients: StatureCoefficients(elbowFactor: elbow, chestFactor: chest, eyeDropMeters: eye, cabMeters: cab)
        ))
        problem = ""
        return true
    }
}

/// 初回は身長だけ。持ち方の既定は画面の角度。閉じても測量は止めない。
struct StatureAskSheet: View {
    @ObservedObject var field: FieldModel
    @Environment(\.dismiss) private var dismiss
    @State private var statureText = ""
    @State private var problem = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("身長を入れると、段階0の iPhone で地盤高を出せます。持ち方は画面の角度です。目の高さ（身長−約10cm）から、傾きと目までの距離で端末の高さを引きます。距離が測れないときは 35cm です。肘より上は、代わりの持ち方です。")
                    .font(SurveyType(16, .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("身長 m")
                    .font(SurveyType(15, .heavy))
                TextField("1.70", text: $statureText)
                    .keyboardType(.decimalPad)
                    .autocorrectionDisabled()
                    .font(SurveyType(20, .heavy, mono: true))
                    .padding(10)
                    .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                if !problem.isEmpty {
                    Text(problem)
                        .font(SurveyType(15, .heavy))
                        .foregroundStyle(SurveyColor.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("この身長で使う") { save() }
                    .buttonStyle(.plain)
                    .font(SurveyType(18, .heavy))
                    .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                    .background(SurveyColor.blue)
                    .foregroundStyle(SurveyColor.onAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Spacer()
            }
            .padding(20)
            .background(SurveyColor.background)
            .foregroundStyle(SurveyColor.text)
            .navigationTitle("身長")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("あとで") { dismiss() }
                        .font(SurveyType(17, .heavy))
                }
            }
        }
        .modifier(SurveyScheme())
    }

    private func save() {
        let trimmed = statureText.trimmingCharacters(in: .whitespaces)
        guard let stature = Double(trimmed), stature > 0, stature <= 3 else {
            problem = "身長は 0m より大きく、3m までです。"
            return
        }
        var profile = field.stature
        profile.statureMeters = stature
        field.saveStature(profile)
        dismiss()
    }
}
