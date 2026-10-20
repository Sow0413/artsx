import Foundation
import SwiftUI
import SurveyCore

struct RootView: View {
    @StateObject private var field: FieldModel

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
        VStack(spacing: 0) {
            AccuracyBadgeView(badge: field.badge)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 8)
            if let correction = field.correctionStore.active {
                CorrectionStatusBar(correction: correction)
            }
            if let progress = field.benchmarkProgressLabel {
                Text(progress)
                    .font(.system(size: 16, weight: .heavy))
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
                    PlaceholderTabView(
                        title: "図面",
                        message: "DXF を重ねて、2点で合わせる画面は次のスライスです。RTK Fix になるまで、合わせは緑にしません。"
                    )
                } else if field.tab == .measure {
                    MeasureLogView(field: field)
                } else if field.tab == .export {
                    PlaceholderTabView(
                        title: "出す",
                        message: "PDF・DXF・SIMA の書き出しは次のスライスです。JGD2024 への変換は、出すときだけ行います。"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            SurveyTabBar(selection: $field.tab)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SurveyColor.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { field.start() }
        .onDisappear { field.stop() }
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
