import SwiftUI
import UIKit
import SurveyCore

/// 図面と同じカメラで地理院タイルを敷く。タイルは図面座標なので、回転と拡大は線と一緒に動く。
struct DrawingBaseMapView: View {
    var camera: DrawingCamera
    var zone: Int
    var axis: DrawingAxis
    var transform: Similarity2D?
    var composesAxis: Bool
    var style: BaseMapStyle
    var store: TileStore

    @Environment(\.displayScale) private var displayScale
    @State private var images: [TileID: UIImage] = [:]

    var body: some View {
        GeometryReader { geo in
            let frames = mapFrames(in: geo.size)
            Canvas { context, size in
                draw(frames, in: &context, size: size)
            }
            .task(id: frames.map(\.tile)) {
                await load(frames.map(\.tile))
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }

    private func mapFrames(in size: CGSize) -> [DrawingMapFrame] {
        let scale = max(displayScale, 1)
        return DrawingBaseMap.frames(
            viewCorners: camera.viewCorners(size: size),
            zone: zone,
            axis: axis,
            transform: transform,
            composesAxis: composesAxis,
            style: style,
            pointsPerUnit: camera.pointsPerUnit * scale
        )
    }

    private func draw(_ frames: [DrawingMapFrame], in context: inout GraphicsContext, size: CGSize) {
        for frame in frames {
            guard let image = images[frame.tile] else { continue }
            let northWest = camera.screen(frame.northWest, size: size)
            let northEast = camera.screen(frame.northEast, size: size)
            let southWest = camera.screen(frame.southWest, size: size)
            var copy = context
            copy.transform = CGAffineTransform(
                a: northEast.x - northWest.x,
                b: northEast.y - northWest.y,
                c: southWest.x - northWest.x,
                d: southWest.y - northWest.y,
                tx: northWest.x,
                ty: northWest.y
            )
            copy.draw(Image(uiImage: image), in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    private func load(_ tiles: [TileID]) async {
        let wanted = Set(tiles)
        images = images.filter { wanted.contains($0.key) }
        await withTaskGroup(of: (TileID, Data)?.self) { group in
            for tile in tiles where images[tile] == nil {
                group.addTask {
                    guard let data = try? await store.fetch(tile), !data.isEmpty else { return nil }
                    return (tile, data)
                }
            }
            for await item in group {
                if Task.isCancelled {
                    group.cancelAll()
                    return
                }
                guard let (tile, data) = item, wanted.contains(tile), let image = UIImage(data: data) else { continue }
                images[tile] = image
            }
        }
    }
}
