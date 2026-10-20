import SwiftUI
import SurveyCore

struct MeasureLogView: View {
    @ObservedObject var field: FieldModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("測る")
                    .font(.system(size: 28, weight: .heavy))
                Text("今の作業「\(field.workCatalog.selected.title)」で点を残します。点名は頭のアルファベットと連番です。下見で取った点は捨てず、あとから測量点の座標に乗せ替えられます。")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("点名の頭（T）", text: prefixBinding)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Text(field.nextPointName.map { "次の点名は \($0)" } ?? "頭文字は半角アルファベットだけにしてください。")
                    .font(.system(size: 16, weight: .heavy))
                if let folder = field.drawing.activeRecordFolder {
                    Text("この頭文字は記録 \(folder) に残します。")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SurveyColor.muted)
                }
                Button(action: field.captureObservation) {
                    Text("現在地を残す")
                        .font(.system(size: 18, weight: .heavy))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(SurveyColor.blue)
                        .foregroundStyle(SurveyColor.text)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                controlSection
                if let message = field.captureMessage {
                    Text(message)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(SurveyColor.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if field.observations.observations.isEmpty {
                    Text("まだ点がありません。")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SurveyColor.muted)
                }
                ForEach(field.observations.observations.reversed()) { observation in
                    observationRow(observation)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SurveyColor.background)
        .foregroundStyle(SurveyColor.text)
    }

    private func observationRow(_ observation: FieldObservation) -> some View {
        let work = field.workCatalog.works.first { $0.id == observation.workID }
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(work?.shortTitle ?? observation.workID)  \(observation.name)")
                .font(.system(size: 18, weight: .heavy))
            Text(CoordinateText.latitude(observation.captured.latitudeDegrees) + "  " + CoordinateText.longitude(observation.captured.longitudeDegrees))
                .font(.system(size: 15, weight: .bold, design: .monospaced))
            Text(accuracyLine(observation))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SurveyColor.muted)
            if let seconds = observation.fixDurationSeconds {
                let satellites = observation.captured.satelliteCount.map { "衛星 \($0)" } ?? "衛星 —"
                Text("基準点　FIX \(Int(seconds.rounded()))秒、\(satellites)")
                    .font(.system(size: 14, weight: .heavy))
            }
            if observation.needsResurvey {
                Text("要再測")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(SurveyColor.amber)
            }
            if let corrected = observation.corrected {
                Text("補正後 \(CoordinateText.latitude(corrected.latitudeDegrees)), \(CoordinateText.longitude(corrected.longitudeDegrees))")
                    .font(.system(size: 14, weight: .bold))
            }
            if let adjusted = observation.closureAdjustment {
                Text("割り振り後 \(CoordinateText.latitude(adjusted.position.latitudeDegrees)), \(CoordinateText.longitude(adjusted.position.longitudeDegrees))")
                    .font(.system(size: 14, weight: .bold))
            }
            if let adopted = observation.adopted {
                Text("乗せ替え先 \(CoordinateText.latitude(adopted.latitudeDegrees)), \(CoordinateText.longitude(adopted.longitudeDegrees))")
                    .font(.system(size: 14, weight: .bold))
            } else if observation.workID == "preview" || observation.workID == "rough" {
                rebaseMenu(for: observation)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var prefixBinding: Binding<String> {
        Binding(get: { field.pointPrefix }, set: { field.setPointPrefix($0) })
    }

    private var controlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("基準点")
                .font(.system(size: 18, weight: .heavy))
            Text(controlStatus)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(field.controlFix.restarted ? SurveyColor.amber : SurveyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let position = field.controlFix.latest {
                let seconds = field.controlFix.continuousSeconds(at: position.timestamp)
                Text("FIX 継続 \(seconds.map { "\(Int($0.rounded()))秒" } ?? "—")　水平 \(CoordinateText.accuracyMeters(position.horizontalAccuracyMeters))　高さ \(position.verticalAccuracyMeters.map { CoordinateText.accuracyMeters($0) } ?? "—")　\(position.satelliteCount.map { "衛星 \($0)" } ?? "衛星 —")")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SurveyColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: field.recordControlPoint) {
                Text("基準点を記録")
                    .font(.system(size: 18, weight: .heavy))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(field.canRecordControlPoint ? SurveyColor.blue : SurveyColor.card)
                    .foregroundStyle(SurveyColor.text)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!field.canRecordControlPoint)
            Text("RTK FIX のあいだだけ残せます。観測中に FIX が切れたら、最初からやり直します。iPhone の GPS では衛星数は出ません。")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SurveyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var controlStatus: String {
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
                .font(.system(size: 13, weight: .semibold))
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
                    .font(.system(size: 16, weight: .heavy))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(SurveyColor.background)
                    .foregroundStyle(SurveyColor.text)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}
