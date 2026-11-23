import SwiftUI
import UIKit
import SurveyCore

struct MeasureLogView: View {
    @ObservedObject var field: FieldModel

    private let listBottomClearance: CGFloat = 68 + 24

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if SurveyBuild.basicMode {
                VStack(alignment: .leading, spacing: 6) {
                    Text("測る")
                        .font(SurveyType(28, .heavy))
                    Text(field.operation.coach)
                        .font(SurveyType(15, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            measureList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .background(SurveyColor.background)
        .foregroundStyle(SurveyColor.text)
    }

    private var measureList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !SurveyBuild.basicMode {
                Text("測る")
                    .font(SurveyType(28, .heavy))
                }
                if !SurveyBuild.basicMode {
                Button {
                    field.showsStature = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(PersonalProfile.title)
                            .font(SurveyType(18, .heavy))
                        if let notice = field.statureNotice {
                            Text(notice)
                                .font(SurveyType(15, .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(SurveyColor.card)
                    .foregroundStyle(SurveyColor.text)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(SurveyColor.line, lineWidth: SurveyColor.stroke)
                    )
                }
                .buttonStyle(.plain)
                Button {
                    field.showsCrosshair = true
                } label: {
                    Text("水準器")
                        .font(SurveyType(18, .heavy))
                        .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                        .background(SurveyColor.blue)
                        .foregroundStyle(SurveyColor.onAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                Button {
                    field.showsBatter = true
                } label: {
                    Text("丁張")
                        .font(SurveyType(18, .heavy))
                        .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                        .background(SurveyColor.blue)
                        .foregroundStyle(SurveyColor.onAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                Button {
                    field.showsPace = true
                } label: {
                    Text("歩測")
                        .font(SurveyType(18, .heavy))
                        .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                        .background(SurveyColor.blue)
                        .foregroundStyle(SurveyColor.onAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                if field.stature.style == .sight {
                    LevelBubble(tiltRadians: field.sightTiltRadians)
                }
                }
                OperationBar(
                    field: field,
                    showsSkill: !SurveyBuild.basicMode,
                    showsCoach: !SurveyBuild.basicMode,
                    saveIdentifier: SurveyBuild.basicMode ? "basic-save" : nil
                )
                if field.operation.showsAdvanced {
                    Text("今の作業「\(field.workCatalog.selected.title)」で点を残します。点名は頭のアルファベットと連番です。下見で取った点は捨てず、あとから測量点の座標に乗せ替えられます。")
                        .font(SurveyType(16, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("点名の頭（T）", text: prefixBinding)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    if let folder = field.drawing.activeRecordFolder {
                        Text("この頭文字は記録 \(folder) に残します。")
                            .font(SurveyType(13, .semibold))
                            .foregroundStyle(SurveyColor.muted)
                    }
                }
                if field.operation.level == .skilled || field.operation.controlOpen || field.operation.showsDetail {
                    controlSection
                }
                if !SurveyBuild.basicMode, let message = field.captureMessage {
                    Text(message)
                        .font(SurveyType(15, .heavy))
                        .foregroundStyle(SurveyColor.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if SurveyBuild.basicMode || (field.gnssAvailable && field.operation.showsAdvanced) {
                    gnssSection
                }
                if SurveyBuild.basicMode {
                    BasicDesk(field: field)
                }
                if !SurveyBuild.basicMode, field.observations.observations.isEmpty {
                    Text(field.observationCount == 0 ? "まだ点がありません。" : "点は端末に残しています。")
                        .font(SurveyType(16, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                }
                if !SurveyBuild.basicMode, field.observationCount > field.observations.observations.count {
                    Text("画面には新しい \(field.observations.observations.count) 点だけ出します。ほか \(field.observationCount - field.observations.observations.count) 点は端末に残しています。")
                        .font(SurveyType(13, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !SurveyBuild.basicMode {
                ForEach(field.observations.observations.reversed()) { observation in
                    observationRow(observation)
                }
                }
                Color.clear
                    .frame(height: listBottomClearance)
                    .accessibilityHidden(true)
            }
            .padding(20)
        }
        .contentMargins(.bottom, listBottomClearance, for: .scrollContent)
        .safeAreaPadding(.bottom, 24)
        .accessibilityIdentifier("screen-measure")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func observationRow(_ observation: FieldObservation) -> some View {
        let work = field.workCatalog.works.first { $0.id == observation.workID }
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(work?.shortTitle ?? observation.workID)  \(observation.name)")
                .font(SurveyType(18, .heavy))
            Text(CoordinateText.latitude(observation.captured.latitudeDegrees) + "  " + CoordinateText.longitude(observation.captured.longitudeDegrees))
                .font(SurveyType(15, .bold, mono: true))
            Text(accuracyLine(observation))
                .font(SurveyType(14, .semibold))
                .foregroundStyle(SurveyColor.muted)
            if let seconds = observation.fixDurationSeconds {
                let satellites = observation.captured.satelliteCount.map { "衛星 \($0)" } ?? "衛星 —"
                Text("基準点　FIX \(Int(seconds.rounded()))秒、\(satellites)")
                    .font(SurveyType(14, .heavy))
            }
            if let condition = observation.condition {
                Text(condition.reportLines.joined(separator: "\n"))
                    .font(SurveyType(13, .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if observation.needsResurvey {
                Text("要再測")
                    .font(SurveyType(15, .heavy))
                    .foregroundStyle(SurveyColor.amber)
            }
            if let corrected = observation.corrected {
                Text("補正後 \(CoordinateText.latitude(corrected.latitudeDegrees)), \(CoordinateText.longitude(corrected.longitudeDegrees))")
                    .font(SurveyType(14, .bold))
            }
            if let adjusted = observation.closureAdjustment {
                Text("割り振り後 \(CoordinateText.latitude(adjusted.position.latitudeDegrees)), \(CoordinateText.longitude(adjusted.position.longitudeDegrees))")
                    .font(SurveyType(14, .bold))
            }
            if let adopted = observation.adopted {
                Text("乗せ替え先 \(CoordinateText.latitude(adopted.latitudeDegrees)), \(CoordinateText.longitude(adopted.longitudeDegrees))")
                    .font(SurveyType(14, .bold))
            } else if observation.workID == "preview" || observation.workID == "rough" {
                rebaseMenu(for: observation)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contextMenu {
            Button("点名をコピー") {
                UIPasteboard.general.string = observation.name
            }
            Button("座標をコピー") {
                let latitude = CoordinateText.latitude(observation.captured.latitudeDegrees)
                let longitude = CoordinateText.longitude(observation.captured.longitudeDegrees)
                UIPasteboard.general.string = "\(latitude) \(longitude)"
            }
        }
    }

    private var gnssSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("GNSS")
                    .font(SurveyType(18, .heavy))
                Spacer()
                #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth) && canImport(Network)
                if field.rtkSession != nil {
                    RTKEntryButton {
                        field.openRTK()
                    }
                }
                #endif
            }
            #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth) && canImport(Network)
            if let session = field.rtkSession {
                Text(rtkLine(session))
                    .font(SurveyType(16, .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityIdentifier("rtk-status")
                Text("ViDoc \(session.vidocLine)")
                    .font(SurveyType(15, .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .accessibilityIdentifier("vidoc-status")
                Text("NTRIP \(session.ntripLine)")
                    .font(SurveyType(15, .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .accessibilityIdentifier("ntrip-status")
            }
            #endif
            if !SurveyBuild.basicMode {
            Text(field.gnssState == .idle ? "受信機を選ぶと、切れたときにつなぎ直します。" : field.gnssState.label)
                .font(SurveyType(15, .semibold))
                .foregroundStyle(field.gnssState == .reconnecting ? SurveyColor.amber : SurveyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: field.scanGNSS) {
                Text("近くの GNSS を探す")
                    .font(SurveyType(16, .heavy))
                    .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                    .background(SurveyColor.card)
                    .foregroundStyle(SurveyColor.text)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            ForEach(field.gnssChoices.prefix(8)) { choice in
                Button {
                    field.chooseGNSS(choice.id)
                } label: {
                    Text(choice.name)
                        .font(SurveyType(16, .heavy))
                        .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            }
        }
    }

    #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth) && canImport(Network)
    private func rtkLine(_ session: RTKPositionSession) -> String {
        let quality: String
        switch session.fix {
        case .rtkFix: quality = "FIX"
        case .float: quality = "FLOAT"
        case .dgps: quality = "DGPS"
        case .clas: quality = "CLAS"
        case .standalone, .none: quality = "単独"
        }
        let place = session.mode == .rtk ? "ViDoc" : "iPhone"
        return session.message.isEmpty ? "\(place) \(quality)" : "\(place) \(quality) \(session.message)"
    }
    #endif

    private var prefixBinding: Binding<String> {
        Binding(get: { field.pointPrefix }, set: { field.setPointPrefix($0) })
    }

    private var controlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("基準点")
                .font(SurveyType(18, .heavy))
            Text(controlStatus)
                .font(SurveyType(15, .semibold))
                .foregroundStyle(field.controlFix.restarted ? SurveyColor.amber : SurveyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let position = field.controlFix.latest {
                let seconds = field.controlFix.continuousSeconds(at: position.timestamp)
                Text("FIX 継続 \(seconds.map { "\(Int($0.rounded()))秒" } ?? "—")　水平 \(CoordinateText.accuracyMeters(position.horizontalAccuracyMeters))　高さ \(position.verticalAccuracyMeters.map { CoordinateText.accuracyMeters($0) } ?? "—")　\(position.satelliteCount.map { "衛星 \($0)" } ?? "衛星 —")")
                    .font(SurveyType(14, .semibold))
                    .foregroundStyle(SurveyColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                field.receiveOperation(.tap(.controlPoint))
            } label: {
                Text("基準点を記録")
                    .font(SurveyType(18, .heavy))
                    .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                    .background(field.canRecordControlPoint ? SurveyColor.blue : SurveyColor.card)
                    .foregroundStyle(field.canRecordControlPoint ? SurveyColor.onAccent : SurveyColor.text)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            Text("段階2の RTK FIX のあいだだけ残せます。解が落ちて段階が下がると記録は止まり、測位は続きます。iPhone の GPS では衛星数・PDOP・補正の遅れは出ません。")
                .font(SurveyType(13, .semibold))
                .foregroundStyle(SurveyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var controlStatus: String {
        if !StageGate.allowsRecording(workID: "boundary", stage: field.stageTransition.stage),
           field.controlFix.restarted || field.stageTransition.steppedDown {
            return FieldModel.stageDroppedRecording
        }
        if field.controlFix.restarted && !field.controlFix.canRecord {
            return "FIX が切れたので、やり直してください。"
        }
        guard let position = field.controlFix.latest else { return "まだ位置がありません。" }
        if position.isTrustedRTKFix { return "RTK FIX。記録できます。" }
        if position.fixQuality == .float { return "FLOAT では基準点を記録できません。" }
        return "単独測位では基準点を記録できません。"
    }

    private func accuracyLine(_ observation: FieldObservation) -> String {
        let horizontal = "取得時 水平 \(CoordinateText.accuracyMeters(observation.horizontalAccuracyAtCapture))"
        guard let vertical = observation.verticalAccuracyAtCapture else { return horizontal + "、高さ —" }
        return horizontal + "、高さ \(CoordinateText.accuracyMeters(vertical))"
    }

    @ViewBuilder
    private func rebaseMenu(for observation: FieldObservation) -> some View {
        let targets = field.observations.observations.filter {
            $0.id != observation.id && ($0.workID == "traverse" || $0.workID == "boundary" || $0.workID == "stakeout")
        }
        if targets.isEmpty {
            Text("測量・丁張・境界の点を残すと、その座標に乗せ替えられます。")
                .font(SurveyType(13, .semibold))
                .foregroundStyle(SurveyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Menu {
                ForEach(targets) { target in
                    Button(target.name) {
                        field.rebase(observation.id, onto: target.id)
                    }
                }
            } label: {
                Text("測量点に乗せ替える")
                    .font(SurveyType(16, .heavy))
                    .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                    .background(SurveyColor.background)
                    .foregroundStyle(SurveyColor.text)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}
