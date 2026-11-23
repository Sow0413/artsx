import SwiftUI
import UIKit
import SurveyCore
import UniformTypeIdentifiers

/// ベーシックの現場、データ管理、書き出し。測設は出すタブ。ほかの測量機能は出さない。
struct BasicDesk: View {
    @ObservedObject var field: FieldModel
    @State private var projectName = ""
    @State private var rename = ""
    @State private var pointName = ""
    @State private var editing = ""
    @State private var presentingFile = false
    @State private var file: BasicFile = .importBook

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("現場管理")
                .font(SurveyType(22, .heavy))
                .accessibilityIdentifier("section-site")
            Text("現場の切替と作成。")
                .font(SurveyType(14, .semibold))
                .foregroundStyle(SurveyColor.muted)
            Text("プロジェクト")
                .font(SurveyType(18, .heavy))
            if field.drawing.projects.isEmpty {
                Text("まだありません。")
                    .font(SurveyType(15, .semibold))
                    .foregroundStyle(SurveyColor.muted)
            } else {
                Picker("プロジェクト", selection: projectBinding) {
                    Text("選ぶ").tag(Optional<String>.none)
                    ForEach(field.drawing.projects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                .accessibilityIdentifier("basic-projects")
            }
            TextField("プロジェクト名", text: $projectName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("basic-project-name")
            HStack(alignment: .top, spacing: 10) {
                DeskTile(title: "作る", systemImage: "folder.badge.plus", identifier: "basic-create") {
                    field.drawing.createProject(named: projectName)
                    projectName = ""
                    dismissKeyboard()
                }
                DeskTile(title: "名前を変える", systemImage: "pencil", identifier: "basic-rename") {
                    field.drawing.renameProject(to: projectName.isEmpty ? rename : projectName)
                    projectName = ""
                    dismissKeyboard()
                }
            }
            if let message = field.drawing.message {
                Text(message)
                    .font(SurveyType(14, .semibold))
                    .foregroundStyle(SurveyColor.muted)
            }

            Text("データ管理")
                .font(SurveyType(22, .heavy))
                .accessibilityIdentifier("section-data")
            Text("仮置きを見てから、台帳へ入れます。自動では入れません。")
                .font(SurveyType(14, .semibold))
                .foregroundStyle(SurveyColor.muted)
            let staged = field.stagedPoints()
            if staged.isEmpty {
                Text("仮置きはまだありません。地図の記録で残します。")
                    .font(SurveyType(15, .semibold))
                    .foregroundStyle(SurveyColor.muted)
            }
            ForEach(staged) { observation in
                VStack(alignment: .leading, spacing: 4) {
                    Text("仮置き \(observation.name) \(observation.captured.solutionLabel)")
                        .font(SurveyType(16, .heavy))
                    Text(CoordinateText.accuracyMeters(observation.captured.horizontalAccuracyMeters))
                        .font(SurveyType(13, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                    HStack(alignment: .top, spacing: 10) {
                        DeskTile(title: "台帳へ入れる", systemImage: "book.closed", identifier: "accept-\(observation.name)") {
                            field.acceptStaged(observation)
                        }
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("座標簿")
                .font(SurveyType(18, .heavy))
                .accessibilityIdentifier("basic-book")
            let points = field.basicPoints()
            if points.isEmpty {
                Text("このプロジェクトの点はまだありません。")
                    .font(SurveyType(15, .semibold))
                    .foregroundStyle(SurveyColor.muted)
            }
            ForEach(points) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(entry.name)  \(entry.kind ?? "")")
                        .font(SurveyType(16, .heavy))
                    Text(line(entry))
                        .font(SurveyType(13, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                    HStack(alignment: .top, spacing: 10) {
                        DeskTile(title: "ここへ", systemImage: "location.fill", identifier: "aim-\(entry.name)") {
                            field.aimBasic(entry)
                        }
                        DeskTile(title: "名前", systemImage: "textformat") {
                            editing = entry.name
                            pointName = entry.name
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !editing.isEmpty {
                TextField("新しい点名", text: $pointName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("basic-point-name")
                HStack(alignment: .top, spacing: 10) {
                    DeskTile(title: "点名を変える", systemImage: "pencil", identifier: "basic-point-rename") {
                        field.renameBasicPoint(from: editing, to: pointName)
                        editing = ""
                    }
                    Color.clear.frame(maxWidth: .infinity)
                }
            }

            Text("データ書き出し")
                .font(SurveyType(22, .heavy))
                .accessibilityIdentifier("section-export")
            Text("座標一覧と SIMA、読み込み、バックアップ。")
                .font(SurveyType(14, .semibold))
                .foregroundStyle(SurveyColor.muted)
            HStack(alignment: .top, spacing: 10) {
                DeskTile(title: "座標一覧", systemImage: "list.bullet.rectangle", identifier: "basic-export-csv") {
                    field.exportBasic(.csv)
                }
                DeskTile(title: "SIMA", systemImage: "doc.text", identifier: "basic-export-sima") {
                    field.exportBasic(.sima)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                DeskTile(title: "読み込む", systemImage: "square.and.arrow.down", identifier: "basic-import") {
                    if Self.uiTest, let url = field.exportURL, let data = try? Data(contentsOf: url) {
                        field.importBasic(data: data, filename: url.lastPathComponent)
                    } else {
                        file = .importBook
                        presentingFile = true
                    }
                }
                DeskTile(title: "バックアップ", systemImage: "archivebox", identifier: "basic-backup") {
                    field.makeBasicBackup()
                }
            }
            HStack(alignment: .top, spacing: 10) {
                DeskTile(title: "復元", systemImage: "arrow.counterclockwise", identifier: "basic-restore") {
                    if Self.uiTest, let url = field.exportURL, let data = try? Data(contentsOf: url) {
                        field.restoreBasicBackup(data: data)
                    } else {
                        file = .restore
                        presentingFile = true
                    }
                }
                if let url = field.exportURL {
                    ShareLink(item: url) {
                        DeskTileLabel(title: "ファイルを保存", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                } else {
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
            if let message = field.exportMessage {
                Text(message)
                    .font(SurveyType(14, .semibold))
                    .foregroundStyle(SurveyColor.muted)
            }
            if let message = field.captureMessage {
                Text(message)
                    .font(SurveyType(14, .semibold))
                    .foregroundStyle(SurveyColor.amber)
            }
        }
        .fileImporter(isPresented: $presentingFile, allowedContentTypes: [.commaSeparatedText, .plainText, .json, .data]) { result in
            let mode = file
            guard case let .success(url) = result else { return }
            let allowed = url.startAccessingSecurityScopedResource()
            defer { if allowed { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            if mode == .restore {
                field.restoreBasicBackup(data: data)
            } else {
                field.importBasic(data: data, filename: url.lastPathComponent)
            }
        }
    }

    private var projectBinding: Binding<String?> {
        Binding(
            get: { field.drawing.project?.id },
            set: { id in
                guard let id, let project = field.drawing.projects.first(where: { $0.id == id }) else { return }
                field.drawing.select(project)
            }
        )
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func line(_ entry: CoordinateBookEntry) -> String {
        let quality: String
        switch entry.solution {
        case .some(.rtkFix): quality = "FIX"
        case .some(.float): quality = "FLOAT"
        case .some(.dgps): quality = "DGPS"
        case .some(.clas): quality = "CLAS"
        case .some(.standalone): quality = "単独"
        case .some(.none): quality = ""
        case nil: quality = ""
        }
        let accuracy = String(format: "±%.2fm", entry.horizontalAccuracyMeters)
        return "\(quality) \(accuracy) \(entry.source ?? "")"
    }
}

private extension BasicDesk {
    static var uiTest: Bool { ProcessInfo.processInfo.arguments.contains("-surveyUITest") }
}

/// 座標を指定して測設する。出すタブに置く。計算は FieldModel のまま。
struct BasicStakeoutCard: View {
    @ObservedObject var field: FieldModel
    @State private var name = ""
    @State private var latitude = "35.11561"
    @State private var longitude = "136.90213"
    @State private var height = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("測設")
                .font(SurveyType(22, .heavy))
            TextField("点名", text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("basic-stake-name")
            TextField("緯度", text: $latitude)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("stakeout-latitude")
            TextField("経度", text: $longitude)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("stakeout-longitude")
            TextField("楕円体高", text: $height)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("stakeout-height")
            HStack(alignment: .top, spacing: 10) {
                DeskTile(title: "この座標へ", systemImage: "scope", identifier: "basic-stakeout") {
                    field.aimBasic(name: name, latitude: latitude, longitude: longitude, height: height)
                }
                DeskTile(title: "測設を残す", systemImage: "mappin.and.ellipse", identifier: "basic-record-stake") {
                    field.recordStake()
                }
            }
            if let line = field.basicStakeoutLine {
                Text(line)
                    .font(SurveyType(16, .heavy))
                    .accessibilityIdentifier("stakeout-guide")
            }
            if let message = field.captureMessage {
                Text(message)
                    .font(SurveyType(14, .semibold))
                    .foregroundStyle(SurveyColor.amber)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// アイコンとラベルの、指で押すタイル。
struct DeskTileLabel: View {
    var title: String
    var systemImage: String
    var caption: String? = nil
    var dimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(dimmed ? SurveyColor.muted : SurveyColor.blue)
            Text(title)
                .font(SurveyType(16, .heavy))
                .foregroundStyle(dimmed ? SurveyColor.muted : SurveyColor.text)
                .lineLimit(3)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.leading)
            if let caption {
                Text(caption)
                    .font(SurveyType(13, .heavy))
                    .foregroundStyle(SurveyColor.amber)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(
            SurveyColor.card.opacity(dimmed ? 0.55 : 1),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SurveyColor.line.opacity(dimmed ? 0.4 : 1), lineWidth: SurveyColor.stroke)
        )
    }
}

struct DeskTile: View {
    var title: String
    var systemImage: String
    var caption: String? = nil
    var dimmed = false
    var identifier: String? = nil
    var action: () -> Void

    var body: some View {
        labeled
            .accessibilityLabel(title)
    }

    @ViewBuilder
    private var labeled: some View {
        let button = Button(action: action) {
            DeskTileLabel(title: title, systemImage: systemImage, caption: caption, dimmed: dimmed)
        }
        .buttonStyle(.plain)
        .disabled(dimmed)
        if let identifier {
            button.accessibilityIdentifier(identifier)
        } else {
            button
        }
    }
}

private enum BasicFile {
    case importBook
    case restore
}
