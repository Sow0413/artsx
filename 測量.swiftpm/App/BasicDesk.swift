import SwiftUI
import SurveyCore
import UniformTypeIdentifiers

/// ベーシックのプロジェクト、座標簿、測設、バックアップ。ほかの測量機能は出さない。
struct BasicDesk: View {
    @ObservedObject var field: FieldModel
    @State private var projectName = ""
    @State private var rename = ""
    @State private var pointName = ""
    @State private var editing = ""
    @State private var latitude = "35.11561"
    @State private var longitude = "136.90213"
    @State private var height = ""
    @State private var presentingFile = false
    @State private var file: BasicFile = .importBook

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            HStack {
                Button("作る") {
                    field.drawing.createProject(named: projectName)
                    projectName = ""
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("basic-create")
                Button("名前を変える") {
                    field.drawing.renameProject(to: projectName.isEmpty ? rename : projectName)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("basic-rename")
            }
            .font(SurveyType(16, .heavy))
            if let message = field.drawing.message {
                Text(message)
                    .font(SurveyType(14, .semibold))
                    .foregroundStyle(SurveyColor.muted)
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
                    HStack {
                        Button("ここへ") { field.aimBasic(entry) }
                            .accessibilityIdentifier("aim-\(entry.name)")
                        Button("名前") {
                            editing = entry.name
                            pointName = entry.name
                        }
                    }
                    .font(SurveyType(15, .heavy))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !editing.isEmpty {
                TextField("新しい点名", text: $pointName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("basic-point-name")
                Button("点名を変える") {
                    field.renameBasicPoint(from: editing, to: pointName)
                    editing = ""
                }
                .accessibilityIdentifier("basic-point-rename")
            }

            HStack {
                Button("座標一覧") { field.exportBasic(.csv) }
                    .accessibilityIdentifier("basic-export-csv")
                Button("SIMA") { field.exportBasic(.sima) }
                    .accessibilityIdentifier("basic-export-sima")
            }
            .font(SurveyType(16, .heavy))
            HStack {
                Button("読み込む") {
                    file = .importBook
                    presentingFile = true
                }
                    .accessibilityIdentifier("basic-import")
                Button("バックアップ") { field.makeBasicBackup() }
                    .accessibilityIdentifier("basic-backup")
                Button("復元") {
                    file = .restore
                    presentingFile = true
                }
                    .accessibilityIdentifier("basic-restore")
            }
            .font(SurveyType(16, .heavy))
            if let message = field.exportMessage {
                Text(message)
                    .font(SurveyType(14, .semibold))
                    .foregroundStyle(SurveyColor.muted)
            }
            if let url = field.exportURL {
                ShareLink(item: url) {
                    Text("ファイルを保存")
                        .font(SurveyType(16, .heavy))
                }
            }

            Text("測設")
                .font(SurveyType(18, .heavy))
            TextField("点名", text: $rename)
                .textFieldStyle(.roundedBorder)
            TextField("緯度", text: $latitude)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("stakeout-latitude")
            TextField("経度", text: $longitude)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("stakeout-longitude")
            TextField("楕円体高", text: $height)
                .textFieldStyle(.roundedBorder)
            Button("この座標へ") {
                field.aimBasic(name: rename, latitude: latitude, longitude: longitude, height: height)
            }
            .font(SurveyType(16, .heavy))
            .accessibilityIdentifier("basic-stakeout")
            if let line = field.basicStakeoutLine {
                Text(line)
                    .font(SurveyType(16, .heavy))
                    .accessibilityIdentifier("stakeout-guide")
            }
            Button("測設を残す") { field.recordStake() }
                .font(SurveyType(16, .heavy))
                .accessibilityIdentifier("basic-record-stake")
            if let message = field.captureMessage {
                Text(message)
                    .font(SurveyType(14, .semibold))
                    .foregroundStyle(SurveyColor.amber)
            }
        }
        .padding(12)
        .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

private enum BasicFile {
    case importBook
    case restore
}
