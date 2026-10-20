import SwiftUI
import UIKit
import SurveyCore

/// 運転席に置いた iPhone。測点、向き、下がり、作業半径と、押して話すボタン。
struct OperatorView: View {
    @ObservedObject var field: FieldModel
    @ObservedObject var drawing: DrawingSession

    var body: some View {
        let position = field.workingReading.position
        let guide = drawing.operatorGuide(at: position)
        let station = stationText(position: position, guide: guide)
        let arrow = guide.flatMap {
            OperatorStation.arrow(
                courseDegrees: position?.courseDegrees,
                headingDegrees: position?.headingDegrees,
                centerlineAzimuth: $0.forwardAzimuthDegrees
            )
        }
        let height = OperatorStation.height(
            ellipsoidalMeters: position?.ellipsoidalHeightMeters,
            designMeters: drawing.designHeightMeters,
            eyeHeightMeters: drawing.eyeHeightMeters,
            phoneAtEyes: drawing.phoneAtEyes
        )
        let reach = reachCall(position: position)
        return GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                SurveyColor.background
                if landscape {
                    VStack(spacing: 4) {
                        HStack(spacing: 8) {
                            stationLabel(station)
                            arrowMark(arrow, size: min(geo.size.height * 0.42, 220))
                            heightLabel(height)
                        }
                        reachLabel(reach.text, coverage: reach.coverage)
                            .frame(height: geo.size.height * 0.28)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 28)
                    .padding(.bottom, 108)
                } else {
                    VStack(spacing: 6) {
                        stationLabel(station)
                        arrowMark(arrow, size: min(geo.size.width * 0.42, geo.size.height * 0.28))
                        heightLabel(height)
                        reachLabel(reach.text, coverage: reach.coverage)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 28)
                    .padding(.bottom, 108)
                }
                VStack {
                    HStack {
                        Circle()
                            .fill(field.badge.tone.tint)
                            .frame(width: 14, height: 14)
                            .accessibilityLabel(field.badge.accessibilityText)
                        Spacer()
                        Button("戻る") {
                            field.tab = .map
                        }
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(SurveyColor.muted)
                    }
                    Spacer()
                    talkButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
        }
        .background(SurveyColor.background)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func stationText(position: GeodeticPosition?, guide: OperatorGuide?) -> String {
        if position == nil || position?.isPlottable != true { return "位置がありません" }
        return guide?.line ?? "中心線がありません"
    }

    private func reachCall(position: GeodeticPosition?) -> (text: String, coverage: ReachCoverage?) {
        guard let position, position.isPlottable else {
            return ("位置がありません", nil)
        }
        guard let target = drawing.operatorTarget(control: field.selectedControlPoint) else {
            return ("目標がありません", nil)
        }
        guard let call = MachineReach.geodesic(
            fromLatitude: position.latitudeDegrees,
            fromLongitude: position.longitudeDegrees,
            toLatitude: target.latitude,
            toLongitude: target.longitude,
            radiusMeters: drawing.machineRadiusMeters
        ) else {
            return ("目標まで出せません", nil)
        }
        return (call.text, call.coverage)
    }

    private func stationLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 56, weight: .heavy))
            .minimumScaleFactor(0.3)
            .lineLimit(1)
            .foregroundStyle(SurveyColor.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func heightLabel(_ height: OperatorHeight) -> some View {
        VStack(spacing: 2) {
            Text(height.text)
                .font(.system(size: 64, weight: .heavy))
                .minimumScaleFactor(0.3)
                .lineLimit(1)
                .foregroundStyle(SurveyColor.text)
            if !height.note.isEmpty {
                Text(height.note)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(SurveyColor.amber)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(height.note.isEmpty ? height.text : "\(height.text)。\(height.note)")
    }

    private func reachLabel(_ text: String, coverage: ReachCoverage?) -> some View {
        Text(text)
            .font(.system(size: 44, weight: .heavy))
            .minimumScaleFactor(0.35)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .foregroundStyle(reachTint(coverage))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reachTint(_ coverage: ReachCoverage?) -> Color {
        switch coverage {
        case .inside, .onRadius: return SurveyColor.green
        case .outside: return SurveyColor.red
        case .partial, nil: return SurveyColor.text
        }
    }

    private func arrowMark(_ arrow: OperatorArrow?, size: CGFloat) -> some View {
        VStack(spacing: 4) {
            if let arrow {
                Image(systemName: "arrow.up")
                    .font(.system(size: size, weight: .black))
                    .rotationEffect(.degrees(arrow.relativeDegrees))
                    .foregroundStyle(SurveyColor.text)
                    .frame(width: size, height: size)
                    .accessibilityLabel("\(arrow.source)、中心線から\(Int(arrow.relativeDegrees.rounded()))度")
                Text(arrow.source)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(SurveyColor.muted)
            } else {
                Text("向き —")
                    .font(.system(size: 40, weight: .heavy))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .foregroundStyle(SurveyColor.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var talkButton: some View {
        let talking = field.radio.phase == .transmitting
        return VStack(spacing: 6) {
            Text(field.radio.status)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(SurveyColor.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 16) {
                Text(talking ? "話しています" : "押して話す")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 84)
                    .background(talking ? SurveyColor.red : SurveyColor.amber)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(talking ? "話しています。離すと終わります" : "押して話す")
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if field.radio.phase != .transmitting {
                                    field.beginRadio()
                                }
                            }
                            .onEnded { _ in
                                field.endRadio()
                            }
                    )
                Button(field.radio.attachStation ? "測点を添える" : "測点なし") {
                    field.radio.attachStation.toggle()
                }
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(SurveyColor.muted)
            }
        }
    }
}
