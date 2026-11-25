import SwiftUI
import SurveyCore

struct ScaleCheckPage: View {
    @ObservedObject var field: FieldModel
    @State private var drawingText = "100"
    @State private var measuredText = "100.001"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("図面の距離と、測った距離を比べる。")
                    .font(SurveyType(18, .heavy))
                    .lineLimit(2)
                    .accessibilityIdentifier("purpose-scale")
                Text("差は 2cm 以内、かつ 1/10000 以内。")
                    .font(SurveyType(16, .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .lineLimit(2)
                TextField("図面の距離 m", text: $drawingText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("scale-drawing")
                TextField("測った距離 m", text: $measuredText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("scale-measured")
                DeskTile(title: "比べる", systemImage: "ruler", identifier: "scale-run", prominent: true) {
                    field.compareScale(drawingMeters: Double(drawingText), measuredMeters: Double(measuredText))
                }
                if let message = field.scaleMessage {
                    Text(message)
                        .font(SurveyType(18, .heavy))
                        .lineLimit(3)
                        .accessibilityIdentifier("scale-result")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("screen-scale")
        .background(SurveyColor.background)
    }
}

struct LocalizePage: View {
    @ObservedObject var field: FieldModel
    @State private var name = "IRB-1"
    @State private var designEast = ""
    @State private var designNorth = ""
    @State private var measuredEast = ""
    @State private var measuredNorth = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("測った点を、設計の座標に合わせる。")
                    .font(SurveyType(18, .heavy))
                    .lineLimit(2)
                    .accessibilityIdentifier("purpose-localize")
                Text("既知点は3点以上。2点では始めません。")
                    .font(SurveyType(16, .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .lineLimit(2)
                TextField("点名", text: $name).textFieldStyle(.roundedBorder).accessibilityIdentifier("localize-name")
                TextField("設計 X 東 m", text: $designEast).textFieldStyle(.roundedBorder).accessibilityIdentifier("localize-design-east")
                TextField("設計 Y 北 m", text: $designNorth).textFieldStyle(.roundedBorder).accessibilityIdentifier("localize-design-north")
                TextField("測定 X 東 m", text: $measuredEast).textFieldStyle(.roundedBorder).accessibilityIdentifier("localize-measured-east")
                TextField("測定 Y 北 m", text: $measuredNorth).textFieldStyle(.roundedBorder).accessibilityIdentifier("localize-measured-north")
                DeskTile(title: "この点を足す", systemImage: "plus", identifier: "localize-add") {
                    field.addLocalizeDraft(
                        name: name,
                        designEast: Double(designEast),
                        designNorth: Double(designNorth),
                        measuredEast: Double(measuredEast),
                        measuredNorth: Double(measuredNorth)
                    )
                }
                Text("たまり \(field.localizeDrafts.count) 点")
                    .font(SurveyType(16, .heavy))
                    .accessibilityIdentifier("localize-count")
                DeskTile(title: "合わせる", systemImage: "location.north.line", identifier: "localize-run", prominent: true) {
                    field.runLocalize()
                }
                if let message = field.localizeMessage {
                    Text(message)
                        .font(SurveyType(18, .heavy))
                        .lineLimit(3)
                        .accessibilityIdentifier("localize-result")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("screen-localize")
        .background(SurveyColor.background)
    }
}

struct CadStakePage: View {
    @ObservedObject var field: FieldModel
    @State private var points: [(name: String, east: Double, north: Double)] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("図面の点を選んで、そこへ測設する。")
                    .font(SurveyType(18, .heavy))
                    .lineLimit(2)
                    .accessibilityIdentifier("purpose-cad")
                if let message = field.cadMessage {
                    Text(message)
                        .font(SurveyType(18, .heavy))
                        .lineLimit(3)
                        .accessibilityIdentifier("cad-result")
                }
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    DeskTile(title: point.name, systemImage: "scope", identifier: "cad-\(point.name)") {
                        field.aimCadPoint(name: point.name, east: point.east, north: point.north)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("screen-cad")
        .background(SurveyColor.background)
        .onAppear { points = field.refreshCadPoints() }
    }
}

struct RestorePointsPage: View {
    @ObservedObject var field: FieldModel
    @State private var confirming = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("書き出した座標を、台帳へ戻す。")
                    .font(SurveyType(18, .heavy))
                    .lineLimit(2)
                    .accessibilityIdentifier("purpose-restore")
                Text("戻す前に確認します。測った点の仮置きは混ぜません。")
                    .font(SurveyType(16, .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .lineLimit(2)
                DeskTile(title: "書き出しを戻す", systemImage: "arrow.uturn.backward", identifier: "restore-run", prominent: true) {
                    confirming = true
                }
                if let message = field.exportMessage {
                    Text(message)
                        .font(SurveyType(18, .heavy))
                        .lineLimit(3)
                        .accessibilityIdentifier("restore-result")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("screen-restore-points")
        .background(SurveyColor.background)
        .alert("台帳へ戻す", isPresented: $confirming) {
            Button("戻す", role: .destructive) { field.restoreExportedBook() }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("いまの座標簿を、最後に書き出したファイルで置き換えます。")
        }
    }
}
