import Foundation
@testable import SurveyCore

actor ScriptedTileFetcher: TileFetching {
    private let payload: Data
    private let failing: Set<TileID>
    private(set) var calls: [TileID] = []

    init(payload: Data, failing: Set<TileID> = []) {
        self.payload = payload
        self.failing = failing
    }

    func fetch(_ tile: TileID) async throws -> Data {
        calls.append(tile)
        if failing.contains(tile) {
            throw TileError.notFound(tile)
        }
        return payload
    }
}

final class RequestBox: @unchecked Sendable {
    var url: String?
    var agent: String?
}

enum TestFiles {
    static func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("survey-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

func samplePosition(
    latitude: Double = 35.68123,
    longitude: Double = 139.76712,
    height: Double? = 12.4,
    accuracy: Double = 3.2,
    verticalAccuracy: Double? = nil,
    stage: PositionStage = .iphone,
    quality: FixQuality = .standalone,
    receiver: ReceiverKind = .iphoneGPS
) -> GeodeticPosition {
    GeodeticPosition(
        latitudeDegrees: latitude,
        longitudeDegrees: longitude,
        ellipsoidalHeightMeters: height,
        horizontalAccuracyMeters: accuracy,
        verticalAccuracyMeters: verticalAccuracy,
        timestamp: PreviewClock.instant,
        stage: stage,
        fixQuality: quality,
        receiver: receiver
    )
}
