import SwiftUI
import SurveyCore

struct MeasureLogView: View {
    @ObservedObject var field: FieldModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("測る")
                    .font(.system(size: 28, weight: .heavy))
                Text("今の作業「\(field.workCatalog.selected.title)」で点を残します。下見で取った点は捨てず、あとから測量点の座標に乗せ替えられます。取得時の精度は残ります。")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: field.captureObservation) {
                    Text("現在地を残す")
                        .font(.system(size: 18, weight: .heavy))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(SurveyColor.blue)
                        .foregroundStyle(SurveyColor.text)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
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
