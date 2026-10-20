import Foundation

public struct TileDownloadPlan: Equatable, Sendable {
    public var tiles: [TileID]
    public var bounds: GeoBounds
    public var zoomRange: ClosedRange<Int>

    public init(tiles: [TileID], bounds: GeoBounds, zoomRange: ClosedRange<Int>) {
        self.tiles = tiles
        self.bounds = bounds
        self.zoomRange = zoomRange
    }
}

public enum TileDownloadError: Error, Equatable {
    case tooManyTiles(count: Int, limit: Int)
    case invalidBounds
    case nothingSaved
}

public struct RegionDownloadProgress: Equatable, Sendable {
    public var completed: Int
    public var total: Int
    public var failed: Int

    public init(completed: Int, total: Int, failed: Int) {
        self.completed = completed
        self.total = total
        self.failed = failed
    }
}

public struct RegionDownloadResult: Equatable, Sendable {
    public var completed: Int
    public var failed: Int
    public var directory: URL

    public init(completed: Int, failed: Int, directory: URL) {
        self.completed = completed
        self.failed = failed
        self.directory = directory
    }
}

/// 表示中の範囲を、今のズームとその一つ上だけで保存する。設定画面は置かない。
public enum OfflineAreaPolicy {
    public static let defaultMaxTiles = 800

    public static func zoomRange(
        around zoom: Int,
        extra: Int = 1,
        limits: ClosedRange<Int> = GSITileCatalog.standardZoomRange
    ) -> ClosedRange<Int> {
        let lower = min(max(zoom, limits.lowerBound), limits.upperBound)
        let upper = min(max(lower, zoom + max(0, extra)), limits.upperBound)
        return lower...upper
    }

    public static func plan(
        bounds: GeoBounds,
        zoom: Int,
        style: BaseMapStyle = .gsiStandard,
        extraZoom: Int = 1,
        maxTiles: Int = defaultMaxTiles
    ) throws -> TileDownloadPlan {
        guard bounds.south < bounds.north, bounds.west < bounds.east else {
            throw TileDownloadError.invalidBounds
        }
        var extra = max(0, extraZoom)
        var lastCount = 0
        while extra >= 0 {
            let range = zoomRange(around: zoom, extra: extra)
            let tiles = tiles(in: bounds, zoomRange: range, style: style)
            lastCount = tiles.count
            if !tiles.isEmpty, tiles.count <= maxTiles {
                return TileDownloadPlan(tiles: tiles, bounds: bounds, zoomRange: range)
            }
            extra -= 1
        }
        throw TileDownloadError.tooManyTiles(count: lastCount, limit: maxTiles)
    }

    public static func tiles(in bounds: GeoBounds, zoomRange: ClosedRange<Int>, style: BaseMapStyle) -> [TileID] {
        var result: [TileID] = []
        for zoom in zoomRange {
            result.append(contentsOf: TileMath.tiles(intersecting: bounds, zoom: zoom, style: style))
        }
        return result
    }
}

/// 範囲を現場パックとして書く。通信は渡された source だけを使う。
public struct RegionTileDownloader: Sendable {
    public var maxConcurrent: Int

    public init(maxConcurrent: Int = 4) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    public func download(
        plan: TileDownloadPlan,
        source: any TileFetching,
        directory: URL,
        manifest: BaseMapPackManifest,
        progress: AsyncStream<RegionDownloadProgress>.Continuation? = nil
    ) async throws -> RegionDownloadResult {
        if plan.tiles.isEmpty { throw TileDownloadError.invalidBounds }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoded = try JSONEncoder().encode(manifest)
        try encoded.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)

        let counter = DownloadCounter()
        let queue = TileQueue(plan.tiles)
        let total = plan.tiles.count
        progress?.yield(RegionDownloadProgress(completed: 0, total: total, failed: 0))
        let workers = min(maxConcurrent, total)

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<workers {
                    group.addTask {
                        while let tile = await queue.next() {
                            try Task.checkCancellation()
                            do {
                                let bytes = try await source.fetch(tile)
                                if bytes.isEmpty { throw TileError.empty(tile) }
                                let url = TileFiles.packFile(root: directory, tile: tile)
                                try FileManager.default.createDirectory(
                                    at: url.deletingLastPathComponent(),
                                    withIntermediateDirectories: true
                                )
                                try bytes.write(to: url, options: .atomic)
                                let counts = await counter.succeed()
                                progress?.yield(RegionDownloadProgress(
                                    completed: counts.completed,
                                    total: total,
                                    failed: counts.failed
                                ))
                            } catch is CancellationError {
                                throw CancellationError()
                            } catch {
                                let counts = await counter.fail()
                                progress?.yield(RegionDownloadProgress(
                                    completed: counts.completed,
                                    total: total,
                                    failed: counts.failed
                                ))
                            }
                        }
                    }
                }
                try await group.waitForAll()
            }
        } catch is CancellationError {
            let counts = await counter.snapshot()
            if counts.completed == 0 {
                try? manager.removeItem(at: directory)
            }
            throw CancellationError()
        }

        let counts = await counter.snapshot()
        if counts.completed == 0 {
            try? manager.removeItem(at: directory)
            throw TileDownloadError.nothingSaved
        }
        return RegionDownloadResult(completed: counts.completed, failed: counts.failed, directory: directory)
    }
}

private actor TileQueue {
    private var tiles: [TileID]

    init(_ tiles: [TileID]) {
        self.tiles = tiles
    }

    func next() -> TileID? {
        guard !tiles.isEmpty else { return nil }
        return tiles.removeFirst()
    }
}

private actor DownloadCounter {
    private(set) var completed = 0
    private(set) var failed = 0

    func succeed() -> (completed: Int, failed: Int) {
        completed += 1
        return (completed, failed)
    }

    func fail() -> (completed: Int, failed: Int) {
        failed += 1
        return (completed, failed)
    }

    func snapshot() -> (completed: Int, failed: Int) {
        (completed, failed)
    }
}
