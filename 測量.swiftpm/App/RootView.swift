import Combine
import Foundation
import SwiftUI
import SurveyCore

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var field: FieldModel
    @StateObject private var appearance = SurveyAppearance()

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
            if field.tab != .seat {
                AccuracyBadgeView(badge: field.badge, stage: field.stageTransition.stage)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }
            if field.tab != .seat, let correction = field.correctionStore.active {
                CorrectionStatusBar(correction: correction)
            }
            if field.tab != .seat, let progress = field.benchmarkProgressLabel {
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
                } else if field.tab == .measure {
                    MeasureLogView(field: field)
                } else if field.tab == .export {
                    ExportTabView(field: field)
                } else if field.tab == .seat {
                    OperatorView(field: field, drawing: field.drawing)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            themeButton
            if field.tab != .seat {
                SurveyTabBar(selection: $field.tab)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SurveyColor.background.ignoresSafeArea())
        .environment(\.surveyOutdoor, appearance.outdoor)
        .preferredColorScheme(appearance.outdoor ? .light : .dark)
        .background {
            OperationKeyCommands(field: field)
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
        .onChange(of: field.operation.level) { _, _ in syncVolume() }
        .onChange(of: field.operation.eyesFree) { _, _ in syncVolume() }
        .onReceive(NotificationCenter.default.publisher(for: .surveyConfirmObservation)) { _ in
            field.consumePendingConfirm()
        }
        .modifier(MeshPresenceWatcher(field: field))
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

    private var themeButton: some View {
        Button(action: appearance.cycle) {
            Text(appearance.label)
                .font(SurveyType(18, .heavy))
                .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                .background(appearance.outdoor ? SurveyColor.color(OutdoorContrast.yellow) : SurveyColor.card)
                .foregroundStyle(appearance.outdoor ? SurveyColor.color(OutdoorContrast.black) : SurveyColor.text)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(SurveyColor.line, lineWidth: SurveyColor.stroke)
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .accessibilityLabel(appearance.label)
    }
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
