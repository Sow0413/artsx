import XCTest
@testable import SurveyCore

final class TileTests: XCTestCase {
    func testTokyoTileAndAttribution() {
        let tile = TileMath.tileID(latitude: 35.68123, longitude: 139.76712, zoom: 15)
        XCTAssertEqual(tile, TileID(style: .gsiStandard, z: 15, x: 29105, y: 12903))
        let bounds = TileMath.bounds(of: tile)
        XCTAssertTrue(bounds.contains(latitude: 35.68123, longitude: 139.76712))
        XCTAssertEqual(
            GSITileCatalog.url(for: tile).absoluteString,
            "https://cyberjapandata.gsi.go.jp/xyz/std/15/29105/12903.png"
        )
        XCTAssertEqual(
            GSITileCatalog.urlTemplate(for: .gsiStandard),
            "https://cyberjapandata.gsi.go.jp/xyz/std/{z}/{x}/{y}.png"
        )
        XCTAssertEqual(GSITileCatalog.attribution, "地理院タイル")
        XCTAssertEqual(GSITileCatalog.sourceCredit, "出典：国土地理院")
    }

    func testOtherReferenceTilesAndYAxis() {
        XCTAssertEqual(
            TileMath.tileID(latitude: 0.1, longitude: 0.1, zoom: 1),
            TileID(style: .gsiStandard, z: 1, x: 1, y: 0)
        )
        XCTAssertEqual(
            TileMath.tileID(latitude: 10, longitude: 10, zoom: 2),
            TileID(style: .gsiStandard, z: 2, x: 2, y: 1)
        )
        XCTAssertEqual(
            TileMath.tileID(latitude: -33.8, longitude: 151.2, zoom: 4),
            TileID(style: .gsiStandard, z: 4, x: 14, y: 9)
        )
        XCTAssertEqual(TileMath.tileID(latitude: 35.68123, longitude: 139.76712, zoom: 0).z, 0)
        let north = TileMath.tileID(latitude: 45, longitude: 139, zoom: 8)
        let south = TileMath.tileID(latitude: 30, longitude: 139, zoom: 8)
        XCTAssertLessThan(north.y, south.y)
        let negativeZoom = TileMath.tileID(latitude: 35, longitude: 139, zoom: -3)
        XCTAssertEqual(negativeZoom.z, 0)
    }

    func testBoundsRoundTrip() {
        let samples = [
            (35.68123, 139.76712, 15),
            (0.1, 0.1, 1),
            (10.0, 10.0, 2),
            (-33.8, 151.2, 4),
            (36.2, 138.25, 6)
        ]
        for (latitude, longitude, zoom) in samples {
            let tile = TileMath.tileID(latitude: latitude, longitude: longitude, zoom: zoom)
            XCTAssertTrue(
                TileMath.bounds(of: tile).contains(latitude: latitude, longitude: longitude),
                "\(latitude), \(longitude) z\(zoom)"
            )
        }
    }

    func testManifestJSONShape() throws {
        let json = """
        {"id":"sample","title":"白山","style":"std","minZoom":14,"maxZoom":18,"bounds":{"south":35.6,"west":139.6,"north":35.8,"east":139.9}}
        """.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(BaseMapPackManifest.self, from: json)
        XCTAssertEqual(manifest.id, "sample")
        XCTAssertEqual(manifest.style, .gsiStandard)
        XCTAssertTrue(manifest.bounds.contains(latitude: 35.68123, longitude: 139.76712))
    }

    func testNetworkFetcherUsesCatalogURLAndStatus() async throws {
        let tile = TileID(style: .gsiStandard, z: 15, x: 29105, y: 12903)
        let box = RequestBox()
        let ok = GSINetworkTileFetcher { request in
            box.url = request.url?.absoluteString
            box.agent = request.value(forHTTPHeaderField: "User-Agent")
            return (200, Data("png".utf8))
        }
        let data = try await ok.fetch(tile)
        XCTAssertEqual(data, Data("png".utf8))
        XCTAssertEqual(box.url, GSITileCatalog.url(for: tile).absoluteString)
        XCTAssertEqual(box.agent, GSITileCatalog.userAgent)

        let missing = GSINetworkTileFetcher { _ in (404, Data()) }
        do {
            _ = try await missing.fetch(tile)
            XCTFail("404 は失敗する")
        } catch let error as TileError {
            XCTAssertEqual(error, .badResponse(tile, status: 404))
        }
        let empty = GSINetworkTileFetcher { _ in (200, Data()) }
        do {
            _ = try await empty.fetch(tile)
            XCTFail("空は失敗する")
        } catch let error as TileError {
            XCTAssertEqual(error, .empty(tile))
        }
    }

    func testDiskCacheHitsAndEvicts() async throws {
        let root = try TestFiles.directory()
        defer { TestFiles.remove(root) }
        let upstream = ScriptedTileFetcher(payload: Data(repeating: 7, count: 40))
        let cache = DiskTileCache(directory: root, upstream: upstream, maxBytes: 50)
        let first = TileID(style: .gsiStandard, z: 15, x: 1, y: 1)
        let second = TileID(style: .gsiStandard, z: 15, x: 1, y: 2)
        let third = TileID(style: .gsiStandard, z: 15, x: 1, y: 3)
        _ = try await cache.fetch(first)
        _ = try await cache.fetch(first)
        _ = try await cache.fetch(second)
        _ = try await cache.fetch(third)
        let calls = await upstream.calls
        XCTAssertEqual(calls.filter { $0 == first }.count, 1)
        XCTAssertEqual(calls.count, 3)
        let cachedBytes = await cache.cachedByteCount()
        XCTAssertLessThanOrEqual(cachedBytes, 50)

        let upstreamAgain = ScriptedTileFetcher(payload: Data(repeating: 7, count: 40))
        let reopened = DiskTileCache(directory: root, upstream: upstreamAgain, maxBytes: 50)
        _ = try await reopened.fetch(third)
        let hits = await upstreamAgain.calls
        XCTAssertEqual(hits.count, 0)
        _ = try await reopened.fetch(first)
        let misses = await upstreamAgain.calls
        XCTAssertEqual(misses.count, 1)
    }

    func testLocalPackBeatsNetworkAndBrokenFoldersAreSkipped() async throws {
        let root = try TestFiles.directory()
        defer { TestFiles.remove(root) }
        let tile = TileMath.tileID(latitude: 35.68123, longitude: 139.76712, zoom: 15)
        let packRoot = root.appendingPathComponent("pack-a", isDirectory: true)
        try writePack(at: packRoot, tile: tile, bytes: Data("local".utf8))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("notes", isDirectory: true), withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: root.appendingPathComponent("readme.txt"))
        let packs = LocalPackDirectory.load(in: root)
        XCTAssertEqual(packs.count, 1)
        let loaded = try await packs[0].fetch(tile)
        XCTAssertEqual(loaded, Data("local".utf8))

        let network = ScriptedTileFetcher(payload: Data("net".utf8))
        let store = TileStore(
            packDirectory: root,
            cacheDirectory: root.appendingPathComponent("cache", isDirectory: true),
            memoryCapacity: 4,
            network: network
        )
        let fromStore = try await store.fetch(tile)
        XCTAssertEqual(fromStore, Data("local".utf8))
        _ = try await store.fetch(tile)
        let packCalls = await network.calls
        XCTAssertEqual(packCalls.count, 0)
        let packsLoaded = await store.packCount()
        XCTAssertEqual(packsLoaded, 1)

        let elsewhere = TileID(style: .gsiStandard, z: 15, x: 1, y: 1)
        _ = try await store.fetch(elsewhere)
        _ = try await store.fetch(elsewhere)
        let networkCalls = await network.calls
        XCTAssertEqual(networkCalls.count, 1)
    }

    func testMemoryDropsTheOldestTile() async throws {
        let root = try TestFiles.directory()
        defer { TestFiles.remove(root) }
        let network = ScriptedTileFetcher(payload: Data("n".utf8))
        let store = TileStore(
            packDirectory: root.appendingPathComponent("packs", isDirectory: true),
            cacheDirectory: root.appendingPathComponent("cache", isDirectory: true),
            memoryCapacity: 1,
            maxCacheBytes: 0,
            network: network
        )
        let a = TileID(style: .gsiStandard, z: 10, x: 2, y: 3)
        let b = TileID(style: .gsiStandard, z: 10, x: 2, y: 4)
        _ = try await store.fetch(a)
        _ = try await store.fetch(b)
        _ = try await store.fetch(a)
        let calls = await network.calls
        XCTAssertEqual(calls.filter { $0 == a }.count, 2)
        XCTAssertEqual(calls.filter { $0 == b }.count, 1)
    }

    private func writePack(at root: URL, tile: TileID, bytes: Data) throws {
        let manifest = BaseMapPackManifest(
            id: "pack-a",
            title: "テスト",
            style: .gsiStandard,
            minZoom: tile.z,
            maxZoom: tile.z,
            bounds: TileMath.bounds(of: tile)
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoded = try JSONEncoder().encode(manifest)
        try encoded.write(to: root.appendingPathComponent("manifest.json"))
        let file = root
            .appendingPathComponent(String(tile.z), isDirectory: true)
            .appendingPathComponent(String(tile.x), isDirectory: true)
            .appendingPathComponent("\(tile.y).png")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: file)
    }
}
