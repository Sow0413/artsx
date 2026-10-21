import MapKit
import SurveyCore
import UIKit

/// MapKit は描画だけをする。タイルの中身は TileStore がメモリ、現場パック、ディスク、通信の順で渡す。
final class GSITileOverlay: MKTileOverlay {
    private let store: TileStore

    init(store: TileStore) {
        self.store = store
        super.init(urlTemplate: GSITileCatalog.urlTemplate(for: .gsiStandard))
        // maximumZ をソース最大のままにすると、それより深い縮尺では loadTile が呼ばれず、
        // 地物を消した地図は道路ラベルだけ残って暗くなる。表示範囲は深くし、中身は親タイルから作る。
        minimumZ = GSITileCatalog.displayZoomRange.lowerBound
        maximumZ = GSITileCatalog.displayZoomRange.upperBound
        tileSize = CGSize(width: 256, height: 256)
        canReplaceMapContent = true
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        GSITileCatalog.url(for: GSITileRequest.source(for: path))
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let coverage = TileSampler.coverage(
            z: path.z,
            x: path.x,
            y: path.y,
            style: .gsiStandard,
            range: GSITileCatalog.standardZoomRange
        )
        let scale = path.contentScaleFactor
        let pointSize = tileSize.width
        let store = self.store
        // MapKit は retina では contentScaleFactor 倍の画素を待つ。256px のまま返すと描かず、
        // canReplaceMapContent で地物が消えた画面は黒のままになる。完了はメインで返す。
        // 取るのは実在するズームだけなので、オフラインのキャッシュと現場パックがそのまま効く。
        Task.detached {
            let payload: Data?
            let failure: Error?
            do {
                payload = try await GSITileRequest.image(for: coverage, store: store, pointSize: pointSize, screenScale: scale)
                failure = nil
            } catch {
                payload = nil
                failure = error
            }
            DispatchQueue.main.async {
                result(payload, failure)
            }
        }
    }
}

private enum GSITileRequest {
    static func source(for path: MKTileOverlayPath) -> TileID {
        switch TileSampler.coverage(
            z: path.z,
            x: path.x,
            y: path.y,
            style: .gsiStandard,
            range: GSITileCatalog.standardZoomRange
        ) {
        case .native(let tile):
            return tile
        case .crop(let source, _, _, _):
            return source
        case .mosaic(let tiles, _):
            return tiles.first ?? TileID(style: .gsiStandard, z: GSITileCatalog.standardZoomRange.lowerBound, x: 0, y: 0)
        }
    }

    static func image(for coverage: TileCoverage, store: TileStore, pointSize: CGFloat, screenScale: CGFloat) async throws -> Data {
        switch coverage {
        case .native(let tile):
            let raw = try await store.fetch(tile)
            return GSITileImage.bitmap(raw, pointSize: pointSize, screenScale: screenScale)
        case .crop(let source, let column, let row, let factor):
            let raw = try await store.fetch(source)
            return GSITileImage.crop(raw, column: column, row: row, factor: factor, pointSize: pointSize, screenScale: screenScale)
        case .mosaic(let tiles, let grid):
            var parts: [Data] = []
            parts.reserveCapacity(tiles.count)
            var found = false
            for tile in tiles {
                if let data = try? await store.fetch(tile), !data.isEmpty {
                    parts.append(data)
                    found = true
                } else {
                    parts.append(Data())
                }
            }
            guard !tiles.isEmpty, found, let image = GSITileImage.mosaic(parts, grid: grid, pointSize: pointSize, screenScale: screenScale) else {
                throw TileError.notFound(tiles.first ?? TileID(style: .gsiStandard, z: 0, x: 0, y: 0))
            }
            return image
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

    /// 親タイルの升目を、MapKit が要求した大きさまで拡大する。factor が 1 のときは全体。
    static func crop(_ data: Data, column: Int, row: Int, factor: Int, pointSize: CGFloat, screenScale: CGFloat) -> Data {
        let scale = screenScale > 0 ? screenScale : 1
        let pixels = max(1, Int((pointSize * scale).rounded()))
        let parts = max(factor, 1)
        guard let image = UIImage(data: data)?.cgImage else { return bitmap(data, pointSize: pointSize, screenScale: scale) }
        let col = min(max(column, 0), parts - 1)
        let line = min(max(row, 0), parts - 1)
        let cellWidth = CGFloat(image.width) / CGFloat(parts)
        let cellHeight = CGFloat(image.height) / CGFloat(parts)
        var rect = CGRect(
            x: floor(CGFloat(col) * cellWidth),
            y: floor(CGFloat(line) * cellHeight),
            width: ceil(cellWidth),
            height: ceil(cellHeight)
        )
        rect = rect.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard rect.width >= 1, rect.height >= 1, let cropped = image.cropping(to: rect) else {
            return bitmap(data, pointSize: pointSize, screenScale: scale)
        }
        return paint(pixels: pixels) { _ in
            UIImage(cgImage: cropped, scale: 1, orientation: .up)
                .draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        }
    }

    /// 北を上にした格子。取れなかった升は地の色のまま残し、1枚でもあれば地図に出す。
    static func mosaic(_ tiles: [Data], grid: Int, pointSize: CGFloat, screenScale: CGFloat) -> Data? {
        let scale = screenScale > 0 ? screenScale : 1
        let pixels = max(1, Int((pointSize * scale).rounded()))
        let grid = max(grid, 1)
        let images = tiles.map { UIImage(data: $0) }
        guard images.contains(where: { $0 != nil }) else { return nil }
        let cell = CGFloat(pixels) / CGFloat(grid)
        return paint(pixels: pixels) { _ in
            UIColor(white: 0.82, alpha: 1).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
            for index in images.indices {
                guard let image = images[index] else { continue }
                let column = index % grid
                let row = index / grid
                image.draw(in: CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell))
            }
        }
    }

    private static func paint(pixels: Int, _ draw: (CGContext) -> Void) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pixels, height: pixels), format: format)
        return renderer.pngData { context in
            draw(context.cgContext)
        }
    }
}
