import SwiftUI
import UIKit
import SurveyCore

/// モードメニューを閉じたあとで開く画面。シートの上にシートを出さない。
enum ModeHandoff {
    case projects
    case fileImport
    case crosshair
    case pace
    case ar
    case batter
    case download
}

/// 現場の手順。次の一手だけを、親指の届く下に置く。
enum FieldFlow {
    static let surveyWorkIDs = ["preview", "rough", "traverse", "boundary"]
    static let buildWorkIDs = ["stakeout", "asBuilt"]

    enum Step: Equatable {
        case projects
        case pickData
        case importFile
        case align
        case arbitrary
        case sendStakeout
        case goMap
        case pickPoint
        case guide
        case record
        case openExport
        case writeDrawing
        case writeSurvey
        case writeBuild
        case toggleCad
        case toggleHeading
    }

    static func title(_ step: Step, field: FieldModel) -> String {
        switch step {
        case .projects: return "現場"
        case .pickData: return "データ選択"
        case .importFile: return "取り込む"
        case .align: return "2点合わせ"
        case .arbitrary: return field.drawing.placingArbitrary ? "任意点中" : "任意点"
        case .sendStakeout: return "丁張へ"
        case .goMap: return "記録へ"
        case .pickPoint: return "点を選ぶ"
        case .guide: return "誘導"
        case .record: return "記録"
        case .openExport, .writeDrawing, .writeSurvey, .writeBuild: return "出す"
        case .toggleCad: return field.mapCadOn ? "図面オフ" : "図面オン"
        case .toggleHeading: return field.mapHeadingUp ? "北を上" : "進行を上"
        }
    }

    static func drawingStep(_ drawing: DrawingSession) -> Step? {
        if drawing.project == nil { return .projects }
        if drawing.document == nil, drawing.pdfData == nil { return .importFile }
        if drawing.twoPointMode { return nil }
        if drawing.draftPoint != nil { return .sendStakeout }
        if drawing.activeTransform == nil, drawing.document != nil { return .align }
        if drawing.canPlaceArbitrary, drawing.stakeoutPointID == nil { return .arbitrary }
        if drawing.stakeoutPointID != nil || drawing.activeTransform != nil {
            return .openExport
        }
        return nil
    }

    static func surveyStep(_ field: FieldModel) -> Step {
        field.observationCount == 0 && field.recordPins.isEmpty ? .goMap : .openExport
    }

    static func buildStep(_ field: FieldModel) -> Step {
        let drawing = field.drawing
        if drawing.project == nil, drawing.fieldPoints.isEmpty { return .pickData }
        let guided = drawing.stakeoutPoint != nil || drawing.inspection != nil || drawing.stationLine != nil
        if !guided { return .pickPoint }
        if field.recordBanner != nil { return .openExport }
        return .record
    }

    static func mapStep(_ field: FieldModel) -> Step {
        field.drawing.hasMapOverlay ? .toggleCad : .toggleHeading
    }

    /// メニューの下端。出すが次なら、そのモードの主な書き出しを置く。
    static func menuPin(_ mode: FieldTab, field: FieldModel) -> Step? {
        switch mode {
        case .map:
            return mapStep(field)
        case .drawing:
            guard let step = drawingStep(field.drawing) else { return nil }
            return step == .openExport ? .writeDrawing : step
        case .survey:
            let step = surveyStep(field)
            return step == .openExport ? .writeSurvey : step
        case .build:
            let step = buildStep(field)
            return step == .openExport ? .writeBuild : step
        }
    }

    static func perform(_ step: Step, field: FieldModel, fromMenu: Bool, handoff: ((ModeHandoff) -> Void)? = nil) {
        func close(_ next: ModeHandoff? = nil) {
            if let next { handoff?(next) }
            if fromMenu { field.modeMenu = nil }
        }
        switch step {
        case .projects, .pickData:
            if fromMenu {
                close(.projects)
            } else {
                field.showsProjects = true
            }
        case .importFile:
            if fromMenu {
                close(.fileImport)
            } else {
                field.asksImport = true
            }
        case .align:
            if field.drawing.beginTwoPoint() { field.ensureMapCad() }
            field.tab = .drawing
            close()
        case .arbitrary:
            if fromMenu {
                field.drawing.placingArbitrary = true
            } else {
                field.drawing.placingArbitrary.toggle()
            }
            field.tab = .drawing
            close()
        case .sendStakeout:
            if field.drawing.sendDraftToStakeout() {
                field.selectWork("stakeout")
                field.tab = .build
            }
            close()
        case .goMap:
            field.tab = .map
            close()
        case .pickPoint:
            field.tab = field.drawing.fieldPoints.isEmpty ? .drawing : .map
            close()
        case .guide:
            field.tab = .build
            close()
        case .record:
            field.recordHere()
            close()
        case .openExport:
            switch field.tab {
            case .drawing: field.modeMenu = .drawing
            case .build: field.modeMenu = .build
            default:
                field.tab = .survey
                field.modeMenu = .survey
            }
        case .writeDrawing:
            if field.drawing.activeTransform != nil {
                field.exportDrawingTransform()
            } else {
                field.exportArbitraryPoints()
            }
        case .writeSurvey:
            if field.bookQuery.bounds != nil {
                field.exportDelivery(.csv)
            } else {
                field.exportRecordedPoints()
            }
        case .writeBuild:
            field.exportStakeoutResults()
        case .toggleCad:
            field.toggleMapCad()
        case .toggleHeading:
            field.toggleMapHeading()
        }
    }
}

/// 測量メニューと同じページ。図面・施工・地図もこの幅と下端ボタンを使う。
struct ModeMenuPage<Content: View>: View {
    let title: String
    var pinTitle: String?
    var notice: ExportNotice?
    var onDismissNotice: () -> Void
    var onPin: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        content()
                    }
                    .padding(16)
                    .frame(width: width, alignment: .leading)
                }
                .scrollContentBackground(.hidden)
                .background(SurveyColor.background)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let pinTitle {
                        Button(pinTitle, action: onPin)
                            .buttonStyle(FlowNextButton())
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                            .frame(width: width)
                            .background(SurveyColor.bar)
                    }
                }
                .overlay(alignment: .top) {
                    if let notice {
                        ExportNoticeButton(notice: notice, onDismiss: onDismissNotice)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .frame(width: width)
                    }
                }
            }
            .frame(width: width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerRelativeFrame(.horizontal)
        .modifier(SurveyScheme())
        .modifier(PageSheetWidth())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(SurveyColor.background)
    }
}

struct ModeMenuSheet: View {
    @ObservedObject var field: FieldModel
    let mode: FieldTab
    @Binding var handoff: ModeHandoff?

    var body: some View {
        ModeMenuPage(
            title: mode.title,
            pinTitle: pin.map { FieldFlow.title($0, field: field) },
            notice: field.exportNotice,
            onDismissNotice: { field.dismissExportNotice() },
            onPin: {
                guard let pin else { return }
                FieldFlow.perform(pin, field: field, fromMenu: true) { handoff = $0 }
            }
        ) {
            rows
        }
    }

    @ViewBuilder
    private var rows: some View {
        switch mode {
        case .map:
            mapRows
        case .drawing:
            drawingRows
        case .survey:
            surveyRows
        case .build:
            buildRows
        }
    }

    private var pin: FieldFlow.Step? {
        FieldFlow.menuPin(mode, field: field)
    }

    @ViewBuilder
    private var mapRows: some View {
        if let layers = field.drawing.document?.layers, !layers.isEmpty {
            DisclosureGroup("レイヤ") {
                ForEach(layers) { layer in
                    Toggle(layer.name, isOn: Binding(
                        get: { field.drawing.document?.layers.first { $0.name == layer.name }?.isVisible ?? layer.isVisible },
                        set: { field.drawing.toggleLayer(layer.name, visible: $0) }
                    ))
                    .font(SurveyType(16, .heavy))
                    .tint(SurveyColor.blue)
                    .frame(minHeight: 44)
                }
            }
            .font(SurveyType(18, .heavy))
            .foregroundStyle(SurveyColor.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        flowRow(FieldFlow.title(.toggleHeading, field: field), icon: "location.north") {
            field.toggleMapHeading()
        }
        if field.drawing.hasMapOverlay {
            flowRow(field.mapCadOn ? "図面オフ" : "図面オン", icon: "ruler") {
                field.toggleMapCad()
            }
        }
        if field.drawing.hasMapOverlay {
            VStack(alignment: .leading, spacing: 4) {
                Text("濃さ")
                    .font(SurveyType(15, .heavy))
                    .foregroundStyle(SurveyColor.muted)
                Slider(
                    value: Binding(get: { field.mapCadOpacity }, set: { field.setMapCadOpacity($0) }),
                    in: 0.15...1
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        flowRow(field.isDownloading ? "保存を中止" : "この範囲を保存", icon: "arrow.down.circle") {
            if field.isDownloading {
                field.cancelDownload()
            } else {
                handoff = .download
                field.modeMenu = nil
            }
        }
    }

    @ViewBuilder
    private var drawingRows: some View {
        flowRow("取り込む", icon: "square.and.arrow.down") {
            if field.drawing.project == nil {
                handoff = .projects
            } else {
                handoff = .fileImport
            }
            field.modeMenu = nil
        }
        flowRow("2点合わせ", icon: "link") {
            FieldFlow.perform(.align, field: field, fromMenu: true) { handoff = $0 }
        }
        flowRow("任意点", icon: "mappin") {
            FieldFlow.perform(.arbitrary, field: field, fromMenu: true) { handoff = $0 }
        }
        flowRow("丁張へ", icon: "arrow.up.forward") {
            let sent: Bool
            if field.drawing.draftPoint != nil {
                sent = field.drawing.sendDraftToStakeout()
            } else if let id = field.drawing.selectedPointID {
                sent = field.drawing.sendToStakeout(id)
            } else if let id = field.drawing.fieldPoints.first?.id {
                sent = field.drawing.sendToStakeout(id)
            } else {
                sent = false
            }
            if sent {
                field.selectWork("stakeout")
                field.tab = .build
            } else {
                field.drawing.report("先に点を置いてください。")
            }
            field.modeMenu = nil
        }
        flowRow("出す", icon: "square.and.arrow.up") {
            FieldFlow.perform(.writeDrawing, field: field, fromMenu: false)
        }
        exportRow("合わせた図面") { field.exportAlignedDrawing() }
        exportRow("任意点") { field.exportArbitraryPoints() }
        exportRow("変換") { field.exportDrawingTransform() }
    }

    @ViewBuilder
    private var surveyRows: some View {
        WorkBar(field: field, ids: FieldFlow.surveyWorkIDs)
        flowRow("水準器", icon: "level") {
            handoff = .crosshair
            field.modeMenu = nil
        }
        flowRow("歩測", icon: "figure.walk") {
            handoff = .pace
            field.modeMenu = nil
        }
        flowRow("AR位置出し", icon: "viewfinder") {
            handoff = .ar
            field.modeMenu = nil
        }
        flowRow("記録へ", icon: "record.circle") {
            FieldFlow.perform(.goMap, field: field, fromMenu: true) { handoff = $0 }
        }
        exportRow("記録点") { field.exportRecordedPoints() }
        exportRow("SIMA") { field.exportDelivery(.sima) }
        exportRow("CSV") { field.exportDelivery(.csv) }
        exportRow("観測記録") { field.exportObservationLog() }
    }

    @ViewBuilder
    private var buildRows: some View {
        flowRow("データ選択", icon: "folder") {
            FieldFlow.perform(.pickData, field: field, fromMenu: true) { handoff = $0 }
        }
        flowRow("点を選ぶ", icon: "mappin") {
            FieldFlow.perform(.pickPoint, field: field, fromMenu: true) { handoff = $0 }
        }
        WorkBar(field: field, ids: FieldFlow.buildWorkIDs)
        flowRow("誘導", icon: "location") {
            FieldFlow.perform(.guide, field: field, fromMenu: true) { handoff = $0 }
        }
        flowRow("丁張", icon: "arrow.up.forward") {
            handoff = .batter
            field.modeMenu = nil
        }
        flowRow("記録", icon: "record.circle") {
            FieldFlow.perform(.record, field: field, fromMenu: true) { handoff = $0 }
        }
        exportRow("丁張結果") { field.exportStakeoutResults() }
        exportRow("出来形") { field.exportDelivery(.asBuiltPDF) }
        exportRow("切盛") { field.exportCutFill() }
    }

    private func flowRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        FlowRow(title: title, icon: icon, action: action)
    }

    private func exportRow(_ title: String, action: @escaping () -> Void) -> some View {
        flowRow(title, icon: "square.and.arrow.up", action: action)
    }
}

struct ExportNoticeButton: View {
    let notice: ExportNotice
    var onDismiss: () -> Void
    @State private var sharing = false

    var body: some View {
        Button {
            if notice.fileURL != nil {
                sharing = true
            } else {
                onDismiss()
            }
        } label: {
            Text(notice.text)
                .font(SurveyType(16, .heavy))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Color.black)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.white.opacity(0.94), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(notice.text)
        .accessibilityHint(notice.fileURL == nil ? "閉じる" : "共有")
        .sheet(isPresented: $sharing) {
            if let url = notice.fileURL {
                ActivityShare(url: url)
            }
        }
    }
}

struct ActivityShare: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// シートを画面幅に固定する。中身の理想幅が細いと、iOS 18 以降のシートが縦の帯になる。
private struct PageSheetWidth: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.page)
        } else {
            content
        }
    }
}

struct FlowRow: View {
    let title: String
    var icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(SurveyType(18, .bold))
                    .frame(width: 28)
                Text(title)
                    .font(SurveyType(18, .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(SurveyType(14, .bold))
                    .foregroundStyle(SurveyColor.muted)
            }
            .foregroundStyle(SurveyColor.text)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct FlowNextButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SurveyType(20, .heavy))
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(configuration.isPressed ? SurveyColor.pressed : SurveyColor.blue)
            .foregroundStyle(SurveyColor.onAccent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
