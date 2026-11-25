import MapKit
import UIKit
import SurveyCore

/// MapKit は描画だけをする。タイルの中身は TileStore がメモリ、現場パック、ディスク、通信の順で渡す。
/// 地理院の標準地図は z18 までなので、それより寄った画面は z18 を引き伸ばす。
final class GSITileOverlay: MKTileOverlay {
    private let store: TileStore

    init(store: TileStore) {
        self.store = store
        super.init(urlTemplate: GSITileCatalog.urlTemplate(for: .gsiStandard))
        minimumZ = GSITileCatalog.standardZoomRange.lowerBound
        maximumZ = MapTileOverzoom.appMaxZoom
        tileSize = CGSize(width: 256, height: 256)
        canReplaceMapContent = true
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        let resolved = MapTileOverzoom.resolve(z: path.z, x: path.x, y: path.y)
        return GSITileCatalog.url(for: resolved.source)
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let resolved = MapTileOverzoom.resolve(z: path.z, x: path.x, y: path.y)
        Task { [weak self] in
            guard let self else {
                result(nil, TileError.notFound(resolved.source))
                return
            }
            do {
                let data = try await self.store.fetch(resolved.source)
                let shown = Self.overzoom(data, crop: resolved) ?? data
                await MainActor.run { result(shown, nil) }
            } catch {
                await MainActor.run { result(nil, error) }
            }
        }
    }

    /// 親タイルの一区画を 256px まで拡大する。通信は z18 までしか要らない。
    static func overzoom(_ data: Data, crop: OverzoomedTile) -> Data? {
        guard crop.usesParent, let image = UIImage(data: data), crop.cropSize > 0 else { return data }
        let scale = CGFloat(MapTileOverzoom.tilePixels) / CGFloat(crop.cropSize)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format)
        let enlarged = renderer.image { _ in
            image.draw(in: CGRect(
                x: -CGFloat(crop.cropX) * scale,
                y: -CGFloat(crop.cropY) * scale,
                width: image.size.width * scale,
                height: image.size.height * scale
            ))
        }
        return enlarged.pngData()
    }
}
