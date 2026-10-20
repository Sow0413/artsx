import SwiftUI
import SurveyCore

/// 歩幅を一度合わせ、歩数で距離を残す。段階は 0。実機の歩数は未確認。
struct PaceSheet: View {
    @ObservedObject var field: FieldModel
    @Environment(\.dismiss) private var dismiss
    @State private var distanceText = "50"
    @State private var slopeText = "0"
    @State private var factorText = ""
    @State private var manualCalibration = ""
    @State private var manualMeasure = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PaceStageBadge(badge: field.paceBadge)
                    if !StepHardware.available {
                        notice("歩数は実機で数えます。ここでは歩数を手で入れます。この端末では歩行推測は始めません。")
                    }
                    if field.walkMode == .bridge {
                        notice("GNSSが弱いので、歩行推測で位置をつないでいます。\(field.navigationNote ?? "")")
                    } else if let bridgeNotice = field.bridgeNotice {
                        notice(bridgeNotice)
                    }
                    calibration
                    measure
                    if let message = field.captureMessage {
                        Text(message)
                            .font(SurveyType(16, .heavy))
                            .foregroundStyle(SurveyColor.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
            .background(SurveyColor.background)
            .foregroundStyle(SurveyColor.text)
            .navigationTitle("歩測")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .font(SurveyType(17, .heavy))
                }
            }
        }
        .modifier(SurveyScheme())
        .onAppear {
            slopeText = Self.format(field.pace.slope)
            if let known = field.pace.calibratedDistanceMeters {
                distanceText = Self.format(known)
            }
            if let factor = field.pace.factorOverride {
                factorText = Self.format(factor)
            }
        }
    }

    private var calibration: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("歩幅の校正")
                .font(SurveyType(22, .heavy))
            Text("平らな所で、分かっている距離を歩きます。")
                .font(SurveyType(16, .semibold))
                .foregroundStyle(SurveyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            labeled("距離（m）", text: $distanceText)
            if field.calibrating {
                Text("\(field.calibrationSteps)歩")
                    .font(SurveyType(40, .heavy))
            }
            if !StepHardware.available, field.calibrating {
                labeled("歩数", text: $manualCalibration)
                    .onChange(of: manualCalibration) { _, value in
                        guard let count = Int(value) else { return }
                        field.noteManualSteps(.calibration, count)
                    }
            }
            Button(field.calibrating ? "校正を終える" : "校正を開始") {
                if field.calibrating {
                    field.endCalibration(distanceMeters: Double(distanceText) ?? .nan)
                } else {
                    field.beginCalibration()
                }
            }
            .buttonStyle(PacePrimaryButton())
            if let stride = field.pace.strideMeters {
                Text("歩幅 \(Self.format(stride))m　\(field.pace.calibratedSteps ?? 0)歩")
                    .font(SurveyType(18, .heavy))
            }
        }
    }

    private var measure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("歩測")
                .font(SurveyType(22, .heavy))
            labeled("勾配（1mあたり。平らなら 0）", text: $slopeText)
                .onChange(of: slopeText) { _, value in
                    guard let slope = Double(value), slope.isFinite else { return }
                    var next = field.pace
                    next.slope = slope
                    field.savePace(next)
                }
            labeled("補正係数（空なら勾配から）", text: $factorText)
                .onChange(of: factorText) { _, value in
                    var next = field.pace
                    let trimmed = value.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        next.factorOverride = nil
                    } else if let factor = Double(trimmed) {
                        next.factorOverride = factor
                    } else {
                        return
                    }
                    field.savePace(next)
                }
            Text("補正係数 \(field.paceFactorText)")
                .font(SurveyType(18, .heavy))
            if field.pacing || field.paceFix != nil {
                Text(PaceMath.distanceText(field.pacePathMeters))
                    .font(SurveyType(64, .heavy))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(PaceMath.estimateText(PaceMath.paceSigma(distanceMeters: field.pacePathMeters)))
                    .font(SurveyType(22, .heavy))
                Text("\(field.measureSteps)歩")
                    .font(SurveyType(18, .heavy))
                    .foregroundStyle(SurveyColor.muted)
            }
            if field.paceWaitsForHeading {
                Text("方位を待っています")
                    .font(SurveyType(22, .heavy))
                    .foregroundStyle(SurveyColor.amber)
                Text("方位が無いので、点は残せません")
                    .font(SurveyType(16, .semibold))
                    .foregroundStyle(SurveyColor.muted)
            }
            if !StepHardware.available, field.pacing {
                labeled("歩数", text: $manualMeasure)
                    .onChange(of: manualMeasure) { _, value in
                        guard let count = Int(value) else { return }
                        field.noteManualSteps(.measure, count)
                    }
            }
            Button(field.pacing ? "終了" : "開始") {
                if field.pacing {
                    field.endPace()
                } else {
                    field.beginPace()
                }
            }
            .buttonStyle(PacePrimaryButton())
            Button("歩測で残す") {
                field.recordPace()
            }
            .buttonStyle(PacePrimaryButton())
        }
    }

    private func labeled(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SurveyType(15, .heavy))
                .foregroundStyle(SurveyColor.muted)
            TextField(title, text: text)
                .font(SurveyType(22, .heavy))
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(SurveyType(16, .semibold))
            .foregroundStyle(SurveyColor.text)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(SurveyColor.line, lineWidth: SurveyColor.stroke)
            )
    }

    private static func format(_ value: Double) -> String {
        String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

private struct PacePrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SurveyType(18, .heavy))
            .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
            .background(configuration.isPressed ? SurveyColor.pressed : SurveyColor.blue)
            .foregroundStyle(SurveyColor.onAccent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct PaceStageBadge: View {
    let badge: PaceBadge

    var body: some View {
        HStack(spacing: 10) {
            Text(PaceBadge.label)
                .font(SurveyType(18, .heavy))
                .foregroundStyle(SurveyColor.color(OutdoorContrast.black))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(SurveyColor.color(OutdoorContrast.yellow), in: Capsule())
            Text(badge.text)
                .font(SurveyType(18, .heavy))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints, alignment: .leading)
        .foregroundStyle(SurveyColor.text)
        .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SurveyColor.line, lineWidth: SurveyColor.stroke)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge.accessibilityText)
    }
}
