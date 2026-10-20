import XCTest
@testable import SurveyCore

final class RegionAndTrackTests: XCTestCase {
    func testPlanForOneTileShrinksWhenTheCapIsTight() throws {
        let tile = TileMath.tileID(latitude: 35.68123, longitude: 139.76712, zoom: 15)
        let bounds = TileMath.bounds(of: tile)
        let exact = try OfflineAreaPolicy.plan(bounds: bounds, zoom: 15, extraZoom: 0, maxTiles: 10)
        XCTAssertEqual(exact.tiles, [tile])
        let shrunk = try OfflineAreaPolicy.plan(bounds: bounds, zoom: 15, extraZoom: 1, maxTiles: 1)
        XCTAssertEqual(shrunk.zoomRange, 15...15)
        XCTAssertEqual(shrunk.tiles.count, 1)
        XCTAssertThrowsError(try OfflineAreaPolicy.plan(bounds: bounds, zoom: 15, extraZoom: 0, maxTiles: 0)) { error in
            XCTAssertEqual(error as? TileDownloadError, .tooManyTiles(count: 1, limit: 0))
        }
        XCTAssertThrowsError(
            try OfflineAreaPolicy.plan(
                bounds: GeoBounds(south: 2, west: 0, north: 1, east: 1),
                zoom: 10
            )
        )
        XCTAssertEqual(OfflineAreaPolicy.zoomRange(around: 18), 18...18)
    }

    func testDownloadWritesAPackAndSkipsTheNetworkAfterwards() async throws {
        let root = try TestFiles.directory()
        defer { TestFiles.remove(root) }
        let tile = TileMath.tileID(latitude: 35.68123, longitude: 139.76712, zoom: 15)
        let bounds = TileMath.bounds(of: tile)
        let plan = try OfflineAreaPolicy.plan(bounds: bounds, zoom: 15, extraZoom: 0)
        let source = ScriptedTileFetcher(payload: Data("saved".utf8))
        let directory = root.appendingPathComponent("view-1", isDirectory: true)
        let manifest = BaseMapPackManifest(
            id: "view-1",
            title: "表示中の範囲",
            style: .gsiStandard,
            minZoom: plan.zoomRange.lowerBound,
            maxZoom: plan.zoomRange.upperBound,
            bounds: bounds
        )
        let (stream, continuation) = AsyncStream<RegionDownloadProgress>.makeStream()
        let result = try await RegionTileDownloader(maxConcurrent: 2).download(
            plan: plan,
            source: source,
            directory: directory,
            manifest: manifest,
            progress: continuation
        )
        continuation.finish()
        var sawTotal = false
        for await progress in stream {
            if progress.total == 1, progress.completed == 1 {
                sawTotal = true
            }
        }
        XCTAssertTrue(sawTotal)
        XCTAssertEqual(result.completed, 1)
        XCTAssertEqual(result.failed, 0)
        let pack = try LocalBaseMapPack(root: directory)
        let packed = try await pack.fetch(tile)
        XCTAssertEqual(packed, Data("saved".utf8))

        let network = ScriptedTileFetcher(payload: Data("net".utf8))
        let store = TileStore(
            packDirectory: root,
            cacheDirectory: root.appendingPathComponent("cache", isDirectory: true),
            network: network
        )
        let stored = try await store.fetch(tile)
        XCTAssertEqual(stored, Data("saved".utf8))
        let calls = await network.calls
        XCTAssertEqual(calls.count, 0)
        let packs = await store.packCount()
        XCTAssertEqual(packs, 1)
    }

    func testDownloadKeepsPartialAndDropsTotalFailure() async throws {
        let root = try TestFiles.directory()
        defer { TestFiles.remove(root) }
        let tile = TileMath.tileID(latitude: 35.68123, longitude: 139.76712, zoom: 15)
        let bounds = TileMath.bounds(of: tile)
        var wider = bounds
        wider.east += 0.02
        let plan = try OfflineAreaPolicy.plan(bounds: wider, zoom: 15, extraZoom: 0, maxTiles: 50)
        XCTAssertGreaterThan(plan.tiles.count, 1)
        let failing = ScriptedTileFetcher(payload: Data("ok".utf8), failing: [plan.tiles[0]])
        let directory = root.appendingPathComponent("partial", isDirectory: true)
        let manifest = BaseMapPackManifest(
            id: "partial",
            title: "一部",
            style: .gsiStandard,
            minZoom: 15,
            maxZoom: 15,
            bounds: wider
        )
        let result = try await RegionTileDownloader().download(
            plan: plan,
            source: failing,
            directory: directory,
            manifest: manifest
        )
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(result.completed, plan.tiles.count - 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))

        let emptyPlan = TileDownloadPlan(tiles: [tile], bounds: bounds, zoomRange: 15...15)
        let dead = ScriptedTileFetcher(payload: Data(), failing: [tile])
        let deadDirectory = root.appendingPathComponent("dead", isDirectory: true)
        do {
            _ = try await RegionTileDownloader().download(
                plan: emptyPlan,
                source: dead,
                directory: deadDirectory,
                manifest: manifest
            )
            XCTFail("1枚も取れなければ失敗する")
        } catch let error as TileDownloadError {
            XCTAssertEqual(error, .nothingSaved)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: deadDirectory.path))
    }

    func testMissingPackDirectoryIsEmpty() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)")
        XCTAssertEqual(LocalPackDirectory.load(in: missing).count, 0)
    }

    func testWaypointAndTrackIdeas() throws {
        let rough = Waypoint(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "入口", position: samplePosition())
        XCTAssertFalse(rough.isStakeoutGrade)
        let fix = Waypoint(
            name: "杭1",
            position: samplePosition(accuracy: 0.02, stage: .rtk, quality: .rtkFix, receiver: .rtk)
        )
        XCTAssertTrue(fix.isStakeoutGrade)
        let data = try JSONEncoder().encode(rough)
        XCTAssertEqual(try JSONDecoder().decode(Waypoint.self, from: data), rough)

        let start = samplePosition(latitude: 35, longitude: 139)
        let next = samplePosition(latitude: 36, longitude: 139)
        let track = Track(name: "下見").appending(start).appending(next)
        XCTAssertEqual(track.points.count, 2)
        XCTAssertEqual(Track(name: "下見").points.count, 0)
        XCTAssertEqual(track.lengthMeters, GeoDistance.meters(latitude1: 35, longitude1: 139, latitude2: 36, longitude2: 139), accuracy: 0.01)
        XCTAssertEqual(track.points[0].frame, .wgs84ITRF)
    }
}
