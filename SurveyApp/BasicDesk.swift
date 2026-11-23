import SwiftUI
import UIKit
import SurveyCore
import UniformTypeIdentifiers

private enum BasicPage: Hashable {
    case site
    case ledger
    case export
}

/// ベーシックの現場、データ管理、書き出し。測設は出すタブ。ほかの測量機能は出さない。
struct BasicDesk: View {
    @ObservedObject var field: FieldModel
    @State private var projectName = ""
    @State private var rename = ""
    @State private var pointName = ""
    @State private var editing = ""
    @State private var presentingFile = false
    @State private var file: BasicFile = .importBook
    @State private var path: [BasicPage] = []
    @State private var confirmImport = false
    @State private var confirmRestore = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(nextHint)
                        .font(SurveyType(18, .heavy))
                        .lineLimit(1)
                        .accessibilityIdentifier("purpose-home")
                    if field.drawing.project != nil, stagedCount == 0 {
                        guideButton(
                            title: "地図で記録",
                            systemImage: "location.fill",
                            identifier: "go-map-record",
                            prominent: bookCount == 0
                        ) {
                            field.tab = .map
                        }
                    }
                    menuTile(
                        title: "現場管理",
                        systemImage: "folder",
                        detail: "切替と作成。",
                        status: siteStatus,
                        badge: nextStep == .site ? "先にここ" : nil,
                        emphasized: nextStep == .site,
                        identifier: "open-site",
                        page: .site
                    )
                    menuTile(
                        title: "データ管理",
                        systemImage: "tray.full",
                        detail: "仮置きを見てから台帳へ。",
                        status: ledgerStatus,
                        badge: stagedCount > 0 ? "仮置き\(stagedCount)件あり" : nil,
                        emphasized: nextStep == .ledger,
                        identifier: "open-ledger",
                        page: .ledger
                    )
                    menuTile(
                        title: "データ書き出し",
                        systemImage: "square.and.arrow.up",
                        detail: "一覧、読み込み、控え。",
                        status: bookCount == 0 ? "台帳はまだありません" : "台帳 \(bookCount)件",
                        badge: nextStep == .export ? "書き出せます" : nil,
                        emphasized: nextStep == .export,
                        identifier: "open-export",
                        page: .export
                    )
                }
                .padding(20)
                .padding(.bottom, 92)
            }
            .accessibilityIdentifier("screen-measure")
            .background(SurveyColor.background)
            .navigationTitle("データ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(path.isEmpty ? .hidden : .visible, for: .navigationBar)
            .navigationDestination(for: BasicPage.self) { page in
                switch page {
                case .site: sitePage
                case .ledger: ledgerPage
                case .export: exportPage
                }
            }
        }
    }

    private enum NextStep {
        case site
        case map
        case ledger
        case export
    }

    private var stagedCount: Int { field.stagedPoints().count }
    private var bookCount: Int { field.basicPoints().count }

    private var nextStep: NextStep {
        if field.drawing.project == nil { return .site }
        if stagedCount > 0 { return .ledger }
        if bookCount == 0 { return .map }
        return .export
    }

    private var nextHint: String {
        switch nextStep {
        case .site: return "先に現場を選びます。"
        case .map: return "次は地図で記録します。"
        case .ledger: return "仮置きを検品します。"
        case .export: return "台帳を書き出します。"
        }
    }

    private var siteStatus: String {
        if let name = field.drawing.project?.name, !name.isEmpty {
            return "いま \(name)"
        }
        let count = field.drawing.projects.count
        return count == 0 ? "現場はまだありません" : "\(count)件"
    }

    private var ledgerStatus: String {
        "仮置き \(field.stagedPoints().count)件、台帳 \(field.basicPoints().count)件"
    }

    private func menuTile(
        title: String,
        systemImage: String,
        detail: String,
        status: String,
        badge: String?,
        emphasized: Bool,
        identifier: String,
        page: BasicPage
    ) -> some View {
        Button {
            path.append(page)
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(SurveyColor.blue)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(SurveyType(22, .heavy))
                    Text(detail)
                        .font(SurveyType(14, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                    Text(status)
                        .font(SurveyType(16, .heavy))
                        .lineLimit(1)
                    if let badge {
                        Text(badge)
                            .font(SurveyType(15, .heavy))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 32)
                            .background(SurveyColor.amber, in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(SurveyColor.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(emphasized ? SurveyColor.blue : SurveyColor.line, lineWidth: emphasized ? 3 : SurveyColor.stroke)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel("\(title)。\(detail)\(status)\(badge ?? "")")
    }

    private func guideButton(title: String, systemImage: String, identifier: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(SurveyType(18, .heavy))
                .frame(maxWidth: .infinity, minHeight: 72)
                .background(
                    prominent ? SurveyColor.blue : SurveyColor.card,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .foregroundStyle(prominent ? SurveyColor.onAccent : SurveyColor.text)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(prominent ? SurveyColor.blue : SurveyColor.line, lineWidth: SurveyColor.stroke)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var sitePage: some View {
        subpage(title: "現場管理", identifier: "screen-site") {
            Text("現場管理")
                .font(SurveyType(22, .heavy))
                .accessibilityIdentifier("section-site")
            Text("現場を作るか、切り替える。")
                .font(SurveyType(18, .heavy))
                .lineLimit(1)
                .accessibilityIdentifier("purpose-site")
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
            DeskTile(title: "作る", systemImage: "folder.badge.plus", identifier: "basic-create", prominent: true) {
                field.drawing.createProject(named: projectName)
                projectName = ""
                dismissKeyboard()
            }
            DeskTile(title: "名前を変える", systemImage: "pencil", identifier: "basic-rename") {
                field.drawing.renameProject(to: projectName.isEmpty ? rename : projectName)
                projectName = ""
                dismissKeyboard()
            }
            if let message = field.drawing.message {
                Text(message)
                    .font(SurveyType(18, .heavy))
                    .lineLimit(2)
                    .accessibilityIdentifier("site-result")
            }
            if field.drawing.project != nil {
                guideButton(title: "地図で記録", systemImage: "location.fill", identifier: "go-map-from-site", prominent: true) {
                    field.tab = .map
                }
            }
        }
    }

    private var ledgerPage: some View {
        subpage(title: "データ管理", identifier: "screen-ledger") {
            Text("データ管理")
                .font(SurveyType(22, .heavy))
                .accessibilityIdentifier("section-data")
            Text("仮置き点を確かめて台帳へ入れる。")
                .font(SurveyType(18, .heavy))
                .lineLimit(1)
                .accessibilityIdentifier("purpose-ledger")
            let staged = field.stagedPoints()
            if staged.isEmpty {
                Text(field.drawing.project == nil ? "先に現場を選びます。" : "仮置きはありません。")
                    .font(SurveyType(16, .heavy))
                    .lineLimit(1)
                if field.drawing.project == nil {
                    guideButton(title: "現場を選ぶ", systemImage: "folder", identifier: "go-site", prominent: true) {
                        path = [.site]
                    }
                } else {
                    guideButton(title: "地図で記録", systemImage: "location.fill", identifier: "go-map-record", prominent: true) {
                        field.tab = .map
                    }
                }
            }
            ForEach(staged) { observation in
                VStack(alignment: .leading, spacing: 4) {
                    Text("仮置き \(observation.name) \(observation.captured.solutionLabel)")
                        .font(SurveyType(16, .heavy))
                    Text(CoordinateText.accuracyMeters(observation.captured.horizontalAccuracyMeters))
                        .font(SurveyType(13, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                    DeskTile(title: "台帳へ入れる", systemImage: "book.closed", identifier: "accept-\(observation.name)", prominent: true) {
                        field.acceptStaged(observation)
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
            if let message = field.captureMessage {
                Text(message)
                    .font(SurveyType(18, .heavy))
                    .lineLimit(3)
                    .accessibilityIdentifier("ledger-result")
            }
            if !field.basicPoints().isEmpty {
                guideButton(title: "書き出しへ", systemImage: "square.and.arrow.up", identifier: "go-data-export", prominent: true) {
                    path = [.export]
                }
            }
        }
    }

    private var exportPage: some View {
        subpage(title: "データ書き出し", identifier: "screen-data-export") {
            Text("データ書き出し")
                .font(SurveyType(22, .heavy))
                .accessibilityIdentifier("section-export")
            Text("台帳をファイルにして共有する。")
                .font(SurveyType(18, .heavy))
                .lineLimit(1)
                .accessibilityIdentifier("purpose-export")
            DeskTile(title: "座標一覧", systemImage: "list.bullet.rectangle", identifier: "basic-export-csv", prominent: true) {
                field.exportBasic(.csv)
            }
            HStack(alignment: .top, spacing: 10) {
                DeskTile(title: "SIMA", systemImage: "doc.text", identifier: "basic-export-sima") {
                    field.exportBasic(.sima)
                }
                DeskTile(title: "バックアップ", systemImage: "archivebox", identifier: "basic-backup") {
                    field.makeBasicBackup()
                }
            }
            DeskTile(title: "読み込む", systemImage: "square.and.arrow.down", identifier: "basic-import") {
                confirmImport = true
            }
            if let message = field.exportMessage {
                Text(message)
                    .font(SurveyType(18, .heavy))
                    .lineLimit(3)
                    .accessibilityIdentifier("export-result")
            }
            if let url = field.exportURL {
                Text("保存先 \(url.lastPathComponent)")
                    .font(SurveyType(16, .heavy))
                    .lineLimit(1)
                    .accessibilityIdentifier("export-where")
                ShareLink(item: url) {
                    DeskTileLabel(title: "共有して保存", systemImage: "square.and.arrow.up", prominent: true)
                }
                .buttonStyle(.plain)
            }
            Text("上書き")
                .font(SurveyType(18, .heavy))
                .padding(.top, 28)
            Text("戻すと、今の座標は上書きされます。")
                .font(SurveyType(16, .semibold))
                .foregroundStyle(SurveyColor.muted)
                .lineLimit(1)
            DeskTile(title: "復元", systemImage: "arrow.counterclockwise", identifier: "basic-restore", danger: true) {
                confirmRestore = true
            }
        }
        .alert("点を読み込みますか", isPresented: $confirmImport) {
            Button("上書きして読む") { runImport() }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("同じ名前は上書きされます。")
        }
        .alert("バックアップから戻しますか", isPresented: $confirmRestore) {
            Button("戻す") { runRestore() }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("今の座標は上書きされます。")
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

    private func subpage<Content: View>(title: String, identifier: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                content()
                Color.clear
                    .frame(height: 92)
                    .accessibilityHidden(true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier(identifier)
        .background(SurveyColor.background)
        .foregroundStyle(SurveyColor.text)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    if !path.isEmpty { path.removeLast() }
                } label: {
                    Label("戻る", systemImage: "chevron.left")
                        .font(SurveyType(18, .heavy))
                        .frame(minWidth: 56, minHeight: 56)
                }
                .accessibilityIdentifier("data-back")
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

    private func runImport() {
        if Self.uiTest, let url = field.exportURL, let data = try? Data(contentsOf: url) {
            field.importBasic(data: data, filename: url.lastPathComponent)
        } else {
            file = .importBook
            presentingFile = true
        }
    }

    private func runRestore() {
        if Self.uiTest, let url = field.exportURL, let data = try? Data(contentsOf: url) {
            field.restoreBasicBackup(data: data)
        } else {
            file = .restore
            presentingFile = true
        }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("座標を打って、設計との差を残す。")
                    .font(SurveyType(18, .heavy))
                    .lineLimit(1)
                    .accessibilityIdentifier("purpose-stake")
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
                DeskTile(title: "この座標へ", systemImage: "scope", identifier: "basic-stakeout", prominent: true) {
                    field.aimBasic(name: name, latitude: latitude, longitude: longitude, height: height)
                }
                if let line = field.basicStakeoutLine {
                    Text(line)
                        .font(SurveyType(28, .heavy))
                        .lineLimit(4)
                        .accessibilityIdentifier("stakeout-live")
                    Text("残り距離・方向・FIX")
                        .font(SurveyType(16, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                        .lineLimit(1)
                }
                DeskTile(title: "測設を残す", systemImage: "mappin.and.ellipse", identifier: "basic-record-stake", prominent: field.basicTarget != nil) {
                    field.recordStake()
                }
                if let result = field.stakeResult {
                    Text(result)
                        .font(SurveyType(18, .heavy))
                        .lineLimit(4)
                        .accessibilityIdentifier("stake-result")
                    guideButtonStandIn
                }
            }
            .padding(20)
            .padding(.bottom, 92)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("screen-coordinate")
        .background(SurveyColor.background)
    }

    private var guideButtonStandIn: some View {
        Button {
            field.tab = .measure
        } label: {
            Text("データ管理で検品")
                .font(SurveyType(18, .heavy))
                .frame(maxWidth: .infinity, minHeight: 72)
                .background(SurveyColor.blue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(SurveyColor.onAccent)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("go-inspect")
    }
}

/// アイコンとラベルの、指で押すタイル。
struct DeskTileLabel: View {
    var title: String
    var systemImage: String
    var caption: String? = nil
    var dimmed = false
    var prominent = false
    var danger = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(title)
                .font(SurveyType(18, .heavy))
                .foregroundStyle(titleColor)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.leading)
            if let caption {
                Text(caption)
                    .font(SurveyType(15, .heavy))
                    .foregroundStyle(prominent ? SurveyColor.onAccent : SurveyColor.amber)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: prominent ? 72 : 112, alignment: .topLeading)
        .background(
            prominent ? SurveyColor.blue : SurveyColor.card.opacity(dimmed ? 0.55 : 1),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(danger ? SurveyColor.red : SurveyColor.line.opacity(dimmed ? 0.4 : 1), lineWidth: danger ? 2 : SurveyColor.stroke)
        )
    }

    private var iconColor: Color {
        if prominent { return SurveyColor.onAccent }
        if danger { return SurveyColor.red }
        if dimmed { return SurveyColor.muted }
        return SurveyColor.blue
    }

    private var titleColor: Color {
        if prominent { return SurveyColor.onAccent }
        if danger { return SurveyColor.red }
        if dimmed { return SurveyColor.muted }
        return SurveyColor.text
    }
}

struct DeskTile: View {
    var title: String
    var systemImage: String
    var caption: String? = nil
    var dimmed = false
    var prominent = false
    var danger = false
    var identifier: String? = nil
    var action: () -> Void

    var body: some View {
        labeled
            .accessibilityLabel(title)
    }

    @ViewBuilder
    private var labeled: some View {
        let button = Button(action: action) {
            DeskTileLabel(title: title, systemImage: systemImage, caption: caption, dimmed: dimmed, prominent: prominent, danger: danger)
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
