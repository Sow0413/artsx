import SwiftUI
import UIKit
import SurveyCore

/// 運転席に置いた iPhone。測点、向き、下がり、作業半径と、押して話すボタン。
struct OperatorView: View {
    @ObservedObject var field: FieldModel
    @ObservedObject var drawing: DrawingSession

    var body: some View {
        let position = field.navigationReading.position
        let guide = drawing.operatorGuide(at: position)
        let station = stationText(position: position, guide: guide)
        let arrow = guide.flatMap {
            OperatorStation.arrow(
                courseDegrees: position?.courseDegrees,
                headingDegrees: position?.headingDegrees,
                centerlineAzimuth: $0.forwardAzimuthDegrees
            )
        }
        let phoneHeight = position.flatMap { here -> Double? in
            SurveyHeight.resolve(
                ellipsoidalMeters: here.ellipsoidalHeightMeters,
                latitudeDegrees: here.latitudeDegrees,
                longitudeDegrees: here.longitudeDegrees,
                meanSeaLevelMeters: here.meanSeaLevelMeters,
                deviceEllipsoidalMeters: here.ellipsoidalHeightMeters
            ).orthometricMeters ?? here.ellipsoidalHeightMeters
        }
        let height = OperatorStation.height(
            ellipsoidalMeters: phoneHeight,
            designMeters: drawing.designHeightMeters,
            eyeHeightMeters: drawing.eyeHeightMeters,
            phoneAtEyes: drawing.phoneAtEyes,
            sightDropMeters: eyeLineDrop
        )
        let reach = reachCall(position: position)
        return GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            let busy = field.extras.proximity || field.extras.fall || field.extras.sos || field.extras.pushToTalk || field.extras.firstResponse
            ZStack {
                SurveyColor.background
                if field.extras.proximity {
                    SafetyWash(level: field.crew.worst)
                    ThreatRim(cues: field.crew.threats.cues, fall: nil)
                }
                if field.extras.fall {
                    ThreatRim(cues: [], fall: field.crew.fallCue)
                }
                if field.extras.pushToTalk {
                    TalkRim(pointer: field.talkPointer)
                }
                if field.extras.sos {
                    SOSRim(pointer: field.sosPointer)
                }
                if landscape {
                    VStack(spacing: 4) {
                        guidanceBlock
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
                    .padding(.bottom, busy ? 300 : 88)
                } else {
                    VStack(spacing: 6) {
                        guidanceBlock
                        stationLabel(station)
                        arrowMark(arrow, size: min(geo.size.width * 0.42, geo.size.height * 0.28))
                        heightLabel(height)
                        reachLabel(reach.text, coverage: reach.coverage)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 28)
                    .padding(.bottom, busy ? 340 : 88)
                }
                VStack {
                    HStack {
                        Circle()
                            .fill(field.badge.tone.tint)
                            .frame(width: 14, height: 14)
                            .accessibilityLabel(field.badge.accessibilityText)
                        Spacer()
                    }
                    Spacer()
                    if field.extras.proximity {
                        SafetyBanner(crew: field.crew)
                        directionHeadline
                        hailButton
                        hiyariButton
                        CrewRadar(
                            marks: field.crew.marks,
                            selfRole: field.crew.role,
                            selfRadius: drawing.machineRadiusMeters,
                            cautionMeters: drawing.cautionMeters,
                            facingDegrees: field.crew.threats.facingDegrees
                        )
                    }
                    if field.extras.fall {
                        FallBanner(fall: field.fall, incoming: field.crew.fallSpeech) {
                            field.cancelFall()
                        }
                    }
                    if field.extras.firstResponse {
                        FirstResponseCard(field: field)
                    }
                    if field.extras.sos {
                        SOSControl(field: field)
                    }
                    if field.extras.recordsIncidents {
                        IncidentTray(field: field)
                    }
                    if field.extras.pushToTalk {
                        talkButton
                    }
                    Button(FieldFlow.title(FieldFlow.buildStep(field), field: field)) {
                        FieldFlow.perform(FieldFlow.buildStep(field), field: field, fromMenu: false)
                    }
                    .buttonStyle(FlowNextButton())
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
        }
        .background(SurveyColor.background)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = !field.batterySaver }
        .onChange(of: field.batterySaver) { _, saver in
            UIApplication.shared.isIdleTimerDisabled = !saver
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    @ViewBuilder
    private var hailButton: some View {
        if let callout = field.crew.callout {
            let talking = field.radio.phase == .transmitting
            Button(talking ? "話しています" : callout.buttonTitle) {
                field.toggleHail()
            }
            .font(SurveyType(28, .black))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .background(talking ? SurveyColor.red : SurveyColor.amber)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityLabel(talking ? "話しています。もう一度押すと終わります" : callout.buttonTitle)
        }
    }

    private var directionHeadline: some View {
        let fallLine = field.crew.fallSpeech
        return VStack(spacing: 0) {
            Text(fallLine ?? field.crew.threats.headline)
                .font(SurveyType(40, .black))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .foregroundStyle(fallLine == nil ? (field.crew.threats.cues.isEmpty ? SurveyColor.muted : SurveyColor.text) : SurveyColor.red)
            if !field.crew.threats.facingSource.isEmpty {
                Text(field.crew.threats.facingSource)
                    .font(SurveyType(13, .heavy))
                    .foregroundStyle(SurveyColor.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(fallLine ?? field.crew.threats.cues.first.map { "\($0.text)。\($0.speech)" } ?? field.crew.threats.headline)
    }

    @ViewBuilder
    private var guidanceBlock: some View {
        if let point = drawing.stakeoutPoint {
            let fill = CutFill.make(formation: point.formationHeightMeters, ground: point.groundLevelMeters)
            VStack(alignment: .leading, spacing: 0) {
                Text(point.mapLabel)
                    .font(SurveyType(22, .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let formation = fill.formationMeters {
                    Text("FH \(FieldPoint.meters(formation))")
                }
                if let ground = fill.groundMeters {
                    Text("標高 \(FieldPoint.meters(ground))")
                }
                if let word = fill.word, let difference = fill.differenceText {
                    Text(word)
                    Text(difference)
                        .font(SurveyType(40, .heavy, mono: true))
                } else if let design = point.designHeightMeters {
                    Text("計画 \(FieldPoint.meters(design))")
                        .font(SurveyType(34, .heavy, mono: true))
                }
            }
            .font(SurveyType(22, .heavy, mono: true))
            .foregroundStyle(SurveyColor.text)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let guide = field.stakeoutGuide {
            VStack(alignment: .leading, spacing: 0) {
                Text(guide.speech)
                    .font(SurveyType(40, .heavy))
                    .minimumScaleFactor(0.4)
                    .lineLimit(2)
                if let detail = guide.detail {
                    Text(detail)
                        .font(SurveyType(20, .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .foregroundStyle(SurveyColor.text)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
            .font(SurveyType(56, .heavy))
            .minimumScaleFactor(0.3)
            .lineLimit(1)
            .foregroundStyle(SurveyColor.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var eyeLineDrop: Double {
        guard drawing.phoneAtEyes, field.stature.style == .sight, let sight = field.liveSight else { return 0 }
        return StatureMath.dropBelowEye(tiltRadians: sight.tiltRadians, eyeDistanceMeters: sight.eyeDistanceMeters)
    }

    private func heightLabel(_ height: OperatorHeight) -> some View {
        VStack(spacing: 2) {
            if field.stature.style == .sight, drawing.phoneAtEyes {
                LevelBubble(tiltRadians: field.sightTiltRadians, compact: true)
            }
            Text(height.meters == nil && height.text != "—" ? "標高 \(height.text)" : height.text)
                .font(SurveyType(64, .heavy))
                .minimumScaleFactor(0.3)
                .lineLimit(1)
                .foregroundStyle(SurveyColor.text)
            if !height.note.isEmpty {
                Text(height.note)
                    .font(SurveyType(14, .heavy))
                    .foregroundStyle(SurveyColor.amber)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(height.note.isEmpty ? height.text : "\(height.text)。\(height.note)")
    }

    private func reachLabel(_ text: String, coverage: ReachCoverage?) -> some View {
        Text(text)
            .font(SurveyType(44, .heavy))
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
                    .font(SurveyType(size, .black))
                    .rotationEffect(.degrees(arrow.relativeDegrees))
                    .foregroundStyle(SurveyColor.text)
                    .frame(width: size, height: size)
                    .accessibilityLabel("\(arrow.source)、中心線から\(Int(arrow.relativeDegrees.rounded()))度")
                Text(arrow.source)
                    .font(SurveyType(18, .heavy))
                    .foregroundStyle(SurveyColor.muted)
            } else {
                Text("向き —")
                    .font(SurveyType(40, .heavy))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .foregroundStyle(SurveyColor.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hiyariButton: some View {
        Button("ヒヤリ") {
            field.recordIncident(trigger: .manual)
        }
        .font(SurveyType(28, .black))
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .background(SurveyColor.red)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel("ヒヤリ")
    }

    private var talkButton: some View {
        let talking = field.radio.phase == .transmitting
        return VStack(spacing: 6) {
            Text(field.radio.status)
                .font(SurveyType(13, .heavy))
                .foregroundStyle(SurveyColor.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 16) {
                Text(talking ? "話しています" : "押して話す")
                    .font(SurveyType(28, .black))
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
                VStack(spacing: 8) {
                    Button(field.crew.speakDirections ? "読み上げオン" : "読み上げ") {
                        field.crew.setSpeakDirections(!field.crew.speakDirections)
                    }
                    .font(SurveyType(13, .heavy))
                    .foregroundStyle(field.crew.speakDirections ? SurveyColor.amber : SurveyColor.muted)
                    Button(field.crew.role.label) {
                        field.crew.setRole(field.crew.role == .machine ? .worker : .machine)
                    }
                    .font(SurveyType(13, .heavy))
                    .foregroundStyle(SurveyColor.muted)
                    Button(field.radio.attachStation ? "測点を添える" : "測点なし") {
                        field.radio.attachStation.toggle()
                    }
                    .font(SurveyType(13, .heavy))
                    .foregroundStyle(SurveyColor.muted)
                    Button(field.radio.spaceAudio ? "定位オン" : "定位") {
                        field.radio.setSpaceAudio(!field.radio.spaceAudio)
                    }
                    .font(SurveyType(13, .heavy))
                    .foregroundStyle(field.radio.spaceAudio ? SurveyColor.amber : SurveyColor.muted)
                    .accessibilityLabel(field.radio.spaceAudio ? "音声の方向定位オン" : "音声の方向定位オフ")
                }
            }
        }
    }
}
