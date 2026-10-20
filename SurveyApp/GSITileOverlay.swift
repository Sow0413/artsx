import MapKit
import SurveyCore

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
        Task { [weak self] in
            guard let self else {
                result(nil, TileError.notFound(tile))
                return
            }
            do {
                let data = try await self.store.fetch(tile)
                result(data, nil)
            } catch {
                result(nil, error)
            }
        }
    }
}
