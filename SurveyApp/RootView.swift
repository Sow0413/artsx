import Combine
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import SurveyCore

#if !SURVEY_PLAYGROUND && canImport(AVFoundation)
import AVFoundation
#endif

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var field: FieldModel
    @StateObject private var appearance = SurveyAppearance()
    @State private var showsMenu = false
    @State private var menuNext: FieldMenuNext?
    @State private var modeHandoff: ModeHandoff?

    init(
        source: any PositionSource,
        tiles: TileStore,
        packDirectory: URL,
        controlPoints: [ControlPoint] = [],
        controlPointNotice: String? = nil,
        siteDirectory: URL
    ) {
        _field = StateObject(wrappedValue: FieldModel(
            source: source,
            tiles: tiles,
            packDirectory: packDirectory,
            controlPoints: controlPoints,
            controlPointNotice: controlPointNotice,
            siteDirectory: siteDirectory
        ))
    }

    var body: some View {
        let _ = SurveyColor.install(appearance.outdoor)
        VStack(spacing: 0) {
            if field.extras.mesh {
                MeshRelayStatus(field: field)
            }
            if field.extras.sharesLocation {
                LocationShareBanner(field: field)
            }
            if field.gnssState == .connecting || field.gnssState == .reconnecting {
                Text(field.gnssState.label)
                    .font(SurveyType(14, .heavy))
                    .foregroundStyle(SurveyColor.amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            }
            if let notice = field.gnssNotice {
                Text(notice)
                    .font(SurveyType(14, .heavy))
                    .foregroundStyle(SurveyColor.amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }
            HStack(spacing: 8) {
                AccuracyBadgeView(badge: field.badge, stage: field.stageTransition.stage, compact: true)
                    .frame(maxWidth: .infinity)
                settingsButton
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 4)
            if let correction = field.correctionStore.active {
                CorrectionStatusBar(correction: correction)
            }
            if field.phoneRun != nil || field.knownShift?.enabled == true {
                PhoneAccuracyBar(field: field)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
            if let progress = field.benchmarkProgressLabel {
                Text(progress)
                    .font(SurveyType(16, .heavy))
                    .foregroundStyle(SurveyColor.amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
            ZStack {
                MapTabView(field: field)
                    .opacity(field.tab == .map ? 1 : 0)
                    .allowsHitTesting(field.tab == .map)
                    .accessibilityHidden(field.tab != .map)
                if field.tab == .drawing {
                    DrawingTabView(field: field, drawing: field.drawing)
                } else if field.tab == .survey {
                    MeasureLogView(field: field)
                } else if field.tab == .build {
                    OperatorView(field: field, drawing: field.drawing)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SurveyColor.background)
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
                    if let banner = field.recordBanner {
                        Button {
                            openRecordBanner()
                        } label: {
                            Text(banner.text)
                                .font(SurveyType(16, .heavy))
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 44)
                                .background(Color.white.opacity(0.94), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(banner.text)
                        .accessibilityHint(banner.folderURL == nil ? "閉じる" : "フォルダを開く")
                    }
                    if field.modeMenu == nil, let notice = field.exportNotice {
                        ExportNoticeButton(notice: notice) {
                            field.dismissExportNotice()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            SurveyTabBar(
                selection: $field.tab,
                onRecord: { field.recordHere() },
                onList: { field.showRecordList() },
                onReselect: { field.modeMenu = $0 }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SurveyColor.background.ignoresSafeArea())
        .environment(\.surveyOutdoor, appearance.outdoor)
        .preferredColorScheme(appearance.outdoor ? .light : .dark)
        .background {
            OperationKeyCommands(field: field)
            StakeoutSpeaker(field: field)
            if field.operation.level == .skilled, field.operation.eyesFree {
                VolumeSliderHost()
                    .frame(width: 1, height: 1)
                    .offset(x: -2000)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onAppear {
            field.start()
            field.setSightForeground(scenePhase == .active)
            syncVolume()
        }
        .onDisappear {
            field.stop()
            VolumeConfirmWatcher.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                field.resumeGNSS()
            } else {
                field.pauseGNSS()
            }
            field.setSightForeground(phase == .active)
            syncVolume()
        }
        .sensoryFeedback(.success, trigger: field.recordSuccessTick)
        .sensoryFeedback(.warning, trigger: field.recordWarningTick)
        .onChange(of: field.operation.level) { _, _ in syncVolume() }
        .onChange(of: field.operation.eyesFree) { _, _ in syncVolume() }
        .onReceive(NotificationCenter.default.publisher(for: .surveyConfirmObservation)) { _ in
            field.consumePendingConfirm()
        }
        .modifier(MeshPresenceWatcher(field: field))
        .sheet(isPresented: $showsMenu, onDismiss: openMenuNext) {
            FieldMenuSheet(field: field, appearance: appearance, next: $menuNext)
        }
        .sheet(item: $field.modeMenu, onDismiss: openModeHandoff) { mode in
            ModeMenuSheet(field: field, mode: mode, handoff: $modeHandoff)
        }
        .sheet(isPresented: $field.showsPrivacy) {
            LocationPrivacySheet(field: field)
        }
        .sheet(isPresented: $field.showsExtras) {
            ExtraSettingsSheet(field: field)
        }
        .sheet(isPresented: $field.showsToolOrder) {
            ToolOrderSheet(field: field)
        }
        .sheet(isPresented: $field.showsStature) {
            StatureSheet(field: field)
        }
        .sheet(isPresented: $field.asksStature) {
            StatureAskSheet(field: field)
        }
        .sheet(isPresented: $field.showsCrosshair) {
            CrosshairSheet(field: field)
        }
        .sheet(isPresented: $field.showsBatter) {
            BatterSheet(field: field, drawing: field.drawing)
        }
        .sheet(isPresented: $field.showsPace) {
            PaceSheet(field: field)
        }
        .sheet(isPresented: $field.showsARStakeout) {
            ARStakeoutSheet(field: field)
        }
        .sheet(isPresented: $field.showsPhoneAverage) {
            PhoneAverageSheet(field: field)
        }
        .sheet(isPresented: $field.showsKnownShift) {
            KnownShiftSheet(field: field)
        }
        .sheet(isPresented: Binding(
            get: { field.selectedControlPoint != nil },
            set: { if !$0 { field.dismissBenchmark() } }
        )) {
            NavigationStack {
                BenchmarkCard(field: field)
                    .background(SurveyColor.background)
                    .navigationTitle("三角点")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") { field.dismissBenchmark() }
                                .font(SurveyType(17, .heavy))
                        }
                    }
            }
            .modifier(SurveyScheme())
        }
        .sheet(isPresented: $field.showsPointList) {
            PointListSheet(field: field)
        }
        .sheet(isPresented: $field.showsProjects) {
            ProjectListSheet(field: field, drawing: field.drawing)
        }
        .sheet(isPresented: $field.showsCadOpacity) {
            NavigationStack {
                Slider(
                    value: Binding(get: { field.mapCadOpacity }, set: { field.setMapCadOpacity($0) }),
                    in: 0.15...1
                )
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(SurveyColor.background)
                .navigationTitle("濃さ")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("閉じる") { field.showsCadOpacity = false }
                            .font(SurveyType(17, .heavy))
                    }
                }
            }
            .modifier(SurveyScheme())
        }
        .fileImporter(isPresented: $field.asksImport, allowedContentTypes: surveyImportTypes()) { result in
            switch result {
            case let .success(url):
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else {
                    field.drawing.report("ファイルを読めませんでした。")
                    return
                }
                field.drawing.importFile(data: data, fileName: url.lastPathComponent)
                field.tab = .drawing
            case .failure:
                field.drawing.report("ファイルを読めませんでした。")
            }
        }
    }

    private func openRecordBanner() {
        guard let folder = field.takeRecordFolder() else { return }
        RecordFolderOpener.open(folder) { opened in
            if !opened {
                field.showRecordList()
            }
        }
    }

    private func openModeHandoff() {
        let next = modeHandoff
        modeHandoff = nil
        switch next {
        case .projects:
            field.showsProjects = true
        case .fileImport:
            field.asksImport = true
        case .crosshair:
            field.showsCrosshair = true
        case .pace:
            field.showsPace = true
        case .ar:
            field.showsARStakeout = true
        case .batter:
            field.showsBatter = true
        case .download:
            field.downloadVisibleArea()
        case nil:
            break
        }
    }

    private func openMenuNext() {
        if field.importAfterMenu {
            field.importAfterMenu = false
            field.asksImport = true
        }
        let next = menuNext
        menuNext = nil
        switch next {
        case .stature:
            field.showsStature = true
        case .extras:
            field.showsExtras = true
        case .tools:
            field.showsToolOrder = true
        case .privacy:
            field.showsPrivacy = true
        case .crosshair:
            field.showsCrosshair = true
        case .batter:
            field.showsBatter = true
        case .ar:
            field.showsARStakeout = true
        case .pace:
            field.showsPace = true
        case .download:
            field.downloadVisibleArea()
        case nil:
            break
        }
    }

    private func syncVolume() {
        if field.operation.level == .skilled, field.operation.eyesFree, scenePhase == .active {
            VolumeConfirmWatcher.start {
                field.receiveOperation(.volumeUp)
            }
        } else {
            VolumeConfirmWatcher.stop()
        }
    }

    private var settingsButton: some View {
        Button {
            showsMenu = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(SurveyType(18, .bold))
                .frame(width: 44, height: 44)
                .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(SurveyColor.text)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(SurveyColor.line, lineWidth: SurveyColor.stroke)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("設定")
    }
}

/// 地図と図面で、画面の上を前にした方向が変わったときだけ読む。施工では読まない。実機の声は未確認。
private struct StakeoutSpeaker: View {
    @ObservedObject var field: FieldModel
    @State private var spoken = ""

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: phrase) { _, next in
                if let utterance = field.stakeoutUtterance, utterance.mode != field.stakeoutSpeechMode {
                    field.stakeoutSpeechMode = utterance.mode
                }
                guard field.tab == .map || field.tab == .drawing else { return }
                guard let next, next != spoken else {
                    if next == nil { StakeoutVoice.stop() }
                    return
                }
                spoken = next
                StakeoutVoice.say(field.stakeoutUtterance?.speech ?? next)
            }
            .onChange(of: field.tab) { _, tab in
                if tab == .build {
                    spoken = ""
                    StakeoutVoice.stop()
                }
            }
    }

    private var phrase: String? {
        guard field.tab == .map || field.tab == .drawing else { return nil }
        return field.stakeoutUtterance?.directionKey
    }
}

enum StakeoutVoice {
    static func say(_ text: String) {
        #if !SURVEY_PLAYGROUND && canImport(AVFoundation)
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = 0.5
        speaker.speak(utterance)
        #else
        _ = text
        #endif
    }

    static func stop() {
        #if !SURVEY_PLAYGROUND && canImport(AVFoundation)
        speaker.stopSpeaking(at: .immediate)
        #endif
    }

    #if !SURVEY_PLAYGROUND && canImport(AVFoundation)
    private static let speaker = AVSpeechSynthesizer()
    #endif
}

enum AppEnvironment {
    static func live() -> (source: CoreLocationPositionSource, tiles: TileStore, packs: URL, points: [ControlPoint], notice: String?, site: URL) {
        let directories = directories(inTemporary: false)
        let tiles = TileStore(packDirectory: directories.packs, cacheDirectory: directories.cache)
        let loaded = ControlPointLoader.load(siteDirectory: directories.site)
        return (CoreLocationPositionSource(), tiles, directories.packs, loaded.points, loaded.notice, directories.site)
    }

    static func preview(source: any PositionSource) -> (source: any PositionSource, tiles: TileStore, packs: URL, points: [ControlPoint], notice: String?, site: URL) {
        let directories = directories(inTemporary: true)
        let tiles = TileStore(
            packDirectory: directories.packs,
            cacheDirectory: directories.cache,
            network: PreviewTileSource()
        )
        let loaded = ControlPointLoader.load(siteDirectory: directories.site)
        return (source, tiles, directories.packs, loaded.points, loaded.notice, directories.site)
    }

    private static func directories(inTemporary: Bool) -> (packs: URL, cache: URL, site: URL) {
        let manager = FileManager.default
        let base: URL
        if inTemporary {
            base = manager.temporaryDirectory.appendingPathComponent("survey-preview-\(UUID().uuidString)", isDirectory: true)
        } else {
            base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        }
        let packs = base.appendingPathComponent("BaseMapPacks", isDirectory: true)
        let site = base.appendingPathComponent("SitePack", isDirectory: true)
        let cache = manager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(inTemporary ? "GSITileCache-\(UUID().uuidString)" : "GSITileCache", isDirectory: true)
        try? manager.createDirectory(at: packs, withIntermediateDirectories: true)
        try? manager.createDirectory(at: site, withIntermediateDirectories: true)
        try? manager.createDirectory(at: cache, withIntermediateDirectories: true)
        return (packs, cache, site)
    }
}

private struct PreviewTileSource: TileFetching {
    func fetch(_ tile: TileID) async throws -> Data {
        throw TileError.notFound(tile)
    }
}
