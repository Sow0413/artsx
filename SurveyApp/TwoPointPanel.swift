import SwiftUI
import SurveyCore

struct TwoPointPanel: View {
    @ObservedObject var field: FieldModel
    @ObservedObject var drawing: DrawingSession
    @State private var millimeters = ""
    @State private var denominator = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(prompt)
                    .font(SurveyType(16, .heavy))
                    .lineLimit(1)
                Spacer()
                Button("閉じる") { drawing.finishTwoPoint() }
                    .font(SurveyType(16, .heavy))
                    .frame(minHeight: 44)
            }
            .foregroundStyle(SurveyColor.text)
            if drawing.pending != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(drawing.fieldPoints) { point in
                            Button(point.name) { _ = drawing.chooseFieldPoint(point.id) }
                                .font(SurveyType(16, .heavy))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(SurveyColor.text)
                        }
                        Button("地図") {
                            if drawing.beginMapPick() {
                                field.ensureMapCad()
                                field.tab = .map
                            }
                        }
                        .font(SurveyType(16, .heavy))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(SurveyColor.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(SurveyColor.onAccent)
                    }
                }
            }
            if let check = drawing.spanCheck {
                span(check)
            }
            if let fit = drawing.fit, drawing.pairs.count >= 2 {
                Text(String(format: "残差 %.3f m", fit.rmsMeters))
                    .font(SurveyType(22, .heavy, mono: true))
                Text(String(format: "縮尺 %.5f", fit.transform.scale))
                    .font(SurveyType(22, .heavy, mono: true))
                Toggle("縮尺 1", isOn: Binding(
                    get: { drawing.lockScale },
                    set: { drawing.setLockScale($0) }
                ))
                .font(SurveyType(16, .heavy))
                .tint(SurveyColor.blue)
                HStack(spacing: 8) {
                    TextField("mm", text: $millimeters)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                    Text("1/")
                        .font(SurveyType(16, .heavy))
                    TextField("N", text: $denominator)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                }
                Button("保存") { drawing.saveAlignment() }
                    .buttonStyle(SurveyPlainButton())
            }
        }
        .padding(12)
        .background(SurveyColor.bar)
        .onAppear(perform: loadTolerance)
        .onChange(of: millimeters) { _, _ in commitTolerance() }
        .onChange(of: denominator) { _, _ in commitTolerance() }
    }

    private var prompt: String {
        if drawing.pending != nil { return "SIMA" }
        if drawing.pairs.count >= 2 { return "2点" }
        return "図面の点"
    }

    private func span(_ check: AlignmentSpanCheck) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(check.verdict.rawValue)
                .font(SurveyType(28, .heavy))
                .foregroundStyle(check.verdict == .ok ? SurveyColor.green : SurveyColor.amber)
            Text(String(format: "図面 %.3f m", check.cadMeters))
            Text(String(format: "SIMA %.3f m", check.simaMeters))
            Text("差 \(check.differenceText) mm")
            Text("比 \(check.ratioText)")
        }
        .font(SurveyType(18, .heavy, mono: true))
        .foregroundStyle(SurveyColor.text)
    }

    private func loadTolerance() {
        millimeters = String(format: "%g", drawing.tolerance.millimeters)
        denominator = String(format: "%g", drawing.tolerance.denominator)
    }

    private func commitTolerance() {
        guard let mm = Double(millimeters), let ratio = Double(denominator) else { return }
        drawing.setTolerance(millimeters: mm, denominator: ratio)
    }
}
