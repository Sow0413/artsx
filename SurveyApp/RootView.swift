import Foundation
import SwiftUI
import SurveyCore

struct RootView: View {
    @StateObject private var field: FieldModel

    init(source: any PositionSource, tiles: TileStore, packDirectory: URL) {
        _field = StateObject(wrappedValue: FieldModel(source: source, tiles: tiles, packDirectory: packDirectory))
    }

    var body: some View {
        VStack(spacing: 0) {
            AccuracyBadgeView(badge: field.badge)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 8)
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
                    PlaceholderTabView(
                        title: "測る",
                        message: "点を取る画面は次のスライスです。地点と軌跡はジオグラフィカの考え方で足します。今は地図で現在地と精度を見ます。"
                    )
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
    static func live() -> (source: CoreLocationPositionSource, tiles: TileStore, packs: URL) {
        let directories = directories(inTemporary: false)
        let tiles = TileStore(packDirectory: directories.packs, cacheDirectory: directories.cache)
        return (CoreLocationPositionSource(), tiles, directories.packs)
    }

    static func preview(source: any PositionSource) -> (source: any PositionSource, tiles: TileStore, packs: URL) {
        let directories = directories(inTemporary: true)
        let tiles = TileStore(
            packDirectory: directories.packs,
            cacheDirectory: directories.cache,
            network: PreviewTileSource()
        )
        return (source, tiles, directories.packs)
    }

    private static func directories(inTemporary: Bool) -> (packs: URL, cache: URL) {
        let manager = FileManager.default
        let base: URL
        if inTemporary {
            base = manager.temporaryDirectory.appendingPathComponent("survey-preview-\(UUID().uuidString)", isDirectory: true)
        } else {
            base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        }
        let packs = base.appendingPathComponent("BaseMapPacks", isDirectory: true)
        let cache = manager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(inTemporary ? "GSITileCache-\(UUID().uuidString)" : "GSITileCache", isDirectory: true)
        try? manager.createDirectory(at: packs, withIntermediateDirectories: true)
        try? manager.createDirectory(at: cache, withIntermediateDirectories: true)
        return (packs, cache)
    }
}

private struct PreviewTileSource: TileFetching {
    func fetch(_ tile: TileID) async throws -> Data {
        throw TileError.notFound(tile)
    }
}

#Preview("段階0 iPhone") {
    let environment = AppEnvironment.preview(source: SimulatedPositionSource.iphonePreview())
    return RootView(source: environment.source, tiles: environment.tiles, packDirectory: environment.packs)
}

#Preview("段階1 CLAS") {
    let environment = AppEnvironment.preview(source: SimulatedPositionSource.clasPreview())
    return RootView(source: environment.source, tiles: environment.tiles, packDirectory: environment.packs)
}

#Preview("段階2 RTK Fix") {
    let environment = AppEnvironment.preview(source: SimulatedPositionSource.rtkFixPreview())
    return RootView(source: environment.source, tiles: environment.tiles, packDirectory: environment.packs)
}
