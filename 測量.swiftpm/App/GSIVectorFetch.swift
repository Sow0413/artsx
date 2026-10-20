import Foundation
import SurveyCore

enum GSIVectorFetch {
    enum Failure: Error {
        case unavailable
    }

    /// 背景の線が載る範囲の地理院ベクトルタイルを取り、道路縁・建物などの線を平面メートルにする。
    static func reference(document: DrawingDocument, zone: Int) async throws -> [Segment2D] {
        var reference: [Segment2D] = []
        var fetched = false
        for axis in DrawingAxis.allCases {
            let segments = DrawingGeometry.backgroundPlaneSegments(document: document, axis: axis)
            guard let bounds = DrawingGeometry.geoBounds(segments: segments, zone: zone) else { continue }
            for tile in GSIVectorTile.cappedTiles(covering: bounds) {
                guard let url = GSIVectorTile.url(z: tile.z, x: tile.x, y: tile.y) else { continue }
                var request = URLRequest(url: url)
                request.setValue(GSITileCatalog.userAgent, forHTTPHeaderField: "User-Agent")
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else { continue }
                    fetched = true
                    reference.append(contentsOf: GSIVectorTile.segments(protobuf: data, tile: tile, zone: zone))
                } catch {
                    continue
                }
            }
        }
        if !fetched { throw Failure.unavailable }
        return reference
    }
}
