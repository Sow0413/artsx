import MapKit
import SurveyCore
import UIKit

/// MapKit は描画だけをする。タイルの中身は TileStore がメモリ、現場パック、ディスク、通信の順で渡す。
final class GSITileOverlay: MKTileOverlay {
    private let store: TileStore

    init(store: TileStore) {
        self.store = store
        super.init(urlTemplate: GSITileCatalog.urlTemplate(for: .gsiStandard))
        minimumZ = GSITileCatalog.standardZoomRange.lowerBound
        maximumZ = GSITileCatalog.standardZoomRange.upperBound
        tileSize = CGSize(width: 256, height: 256)
        canReplaceMapContent = true
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        GSITileCatalog.url(for: TileID(style: .gsiStandard, z: path.z, x: path.x, y: path.y))
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let tile = TileID(style: .gsiStandard, z: path.z, x: path.x, y: path.y)
        let scale = path.contentScaleFactor
        let pointSize = tileSize.width
        let store = self.store
        // MapKit は retina では contentScaleFactor 倍の画素を待つ。256px のまま返すと描かず、
        // canReplaceMapContent で地物が消えた画面は黒のままになる。完了はメインで返す。
        Task.detached {
            let payload: Data
            let failure: Error?
            do {
                let raw = try await store.fetch(tile)
                payload = GSITileImage.bitmap(raw, pointSize: pointSize, screenScale: scale)
                failure = nil
            } catch {
                payload = Data()
                failure = error
            }
            DispatchQueue.main.async {
                if let failure {
                    result(nil, failure)
                } else {
                    result(payload, nil)
                }
            }
        }
    }
}

enum GSITileImage {
    /// 地理院の 256px PNG を、MapKit が要求した倍率の不透明ビットマップにする。
    static func bitmap(_ data: Data, pointSize: CGFloat, screenScale: CGFloat) -> Data {
        let scale = screenScale > 0 ? screenScale : 1
        let pixels = max(1, Int((pointSize * scale).rounded()))
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { return data }
        if cgImage.width == pixels, cgImage.height == pixels { return data }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pixels, height: pixels), format: format)
        let rendered = renderer.pngData { _ in
            UIImage(cgImage: cgImage, scale: 1, orientation: .up)
                .draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        }
        return rendered.isEmpty ? data : rendered
    }
}
