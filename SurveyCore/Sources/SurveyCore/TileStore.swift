import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 地理院のサーバから1枚取る。テストでは transport を差し替える。
public final class GSINetworkTileFetcher: TileFetching, @unchecked Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (status: Int, data: Data)
    private let transport: Transport

    public init(transport: Transport? = nil) {
        self.transport = transport ?? Self.liveTransport
    }

    public func fetch(_ tile: TileID) async throws -> Data {
        var request = URLRequest(url: GSITileCatalog.url(for: tile))
        request.setValue(GSITileCatalog.userAgent, forHTTPHeaderField: "User-Agent")
        let status: Int
        let data: Data
        do {
            (status, data) = try await transport(request)
        } catch {
            throw TileError.transport(String(describing: error))
        }
        guard (200..<300).contains(status) else {
            throw TileError.badResponse(tile, status: status)
        }
        guard !data.isEmpty else { throw TileError.empty(tile) }
        return data
    }

    public static let liveTransport: Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return (status, data)
    }
}

/// 一度見たタイルをディスクに残す。容量を超えたら古いものから消す。
public actor DiskTileCache: TileFetching {
    public let directory: URL
    public let maxBytes: Int
    private let upstream: any TileFetching
    private var index = CacheIndex()
    private var loaded = false

    public init(directory: URL, upstream: any TileFetching, maxBytes: Int = 512 * 1024 * 1024) {
        self.directory = directory
        self.upstream = upstream
        self.maxBytes = max(0, maxBytes)
    }

    public func fetch(_ tile: TileID) async throws -> Data {
        try loadIfNeeded()
        if let data = read(tile) {
            touch(tile, bytes: data.count)
            try? persist()
            return data
        }
        let data = try await upstream.fetch(tile)
        guard !data.isEmpty else { throw TileError.empty(tile) }
        // ディスクに書けなくても、取れた画像は地図に出す。書けないと result が失敗し、全面が黒になる。
        do {
            try write(data, for: tile)
        } catch {
            return data
        }
        return data
    }

    public func cachedByteCount() -> Int {
        try? loadIfNeeded()
        return index.entries.reduce(0) { $0 + $1.bytes }
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let indexURL = directory.appendingPathComponent("index.json")
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode(CacheIndex.self, from: data) {
            index = decoded
        }
        loaded = true
    }

    private func read(_ tile: TileID) -> Data? {
        let url = TileFiles.cacheFile(root: directory, tile: tile)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            index.entries.removeAll { $0.tile == tile }
            return nil
        }
        return data
    }

    private func write(_ data: Data, for tile: TileID) throws {
        let url = TileFiles.cacheFile(root: directory, tile: tile)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        touch(tile, bytes: data.count)
        evictIfNeeded()
        try persist()
    }

    private func touch(_ tile: TileID, bytes: Int) {
        index.nextSequence += 1
        if let existing = index.entries.firstIndex(where: { $0.tile == tile }) {
            index.entries[existing].sequence = index.nextSequence
            index.entries[existing].bytes = bytes
        } else {
            index.entries.append(CacheEntry(tile: tile, bytes: bytes, sequence: index.nextSequence))
        }
    }

    private func evictIfNeeded() {
        var total = index.entries.reduce(0) { $0 + $1.bytes }
        guard total > maxBytes else { return }
        let oldestFirst = index.entries.sorted { $0.sequence < $1.sequence }
        var remove: [TileID] = []
        for entry in oldestFirst {
            if total <= maxBytes { break }
            if index.entries.count - remove.count <= 1 { break }
            remove.append(entry.tile)
            total -= entry.bytes
        }
        for tile in remove {
            try? FileManager.default.removeItem(at: TileFiles.cacheFile(root: directory, tile: tile))
            index.entries.removeAll { $0.tile == tile }
        }
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(index)
        try data.write(to: directory.appendingPathComponent("index.json"), options: .atomic)
    }
}

/// 描画側が毎フレーム同じタイルを取りに来ても、ディスクと通信に落ちないようにする。
public actor TileStore: TileFetching {
    public let packDirectory: URL
    public let memoryCapacity: Int
    private let disk: DiskTileCache
    private var packs: [LocalBaseMapPack] = []
    private var didLoadPacks = false
    private var memoryOrder: [TileID] = []
    private var memoryValues: [TileID: Data] = [:]

    public init(
        packDirectory: URL,
        cacheDirectory: URL,
        memoryCapacity: Int = 128,
        maxCacheBytes: Int = 512 * 1024 * 1024,
        network: any TileFetching = GSINetworkTileFetcher()
    ) {
        self.packDirectory = packDirectory
        self.memoryCapacity = max(1, memoryCapacity)
        self.disk = DiskTileCache(directory: cacheDirectory, upstream: network, maxBytes: maxCacheBytes)
    }

    /// 保存した範囲を読み直す。描画スレッドでは待たない。呼び出し側が await する。
    public func reloadPacks() {
        packs = LocalPackDirectory.load(in: packDirectory)
        didLoadPacks = true
        memoryOrder.removeAll()
        memoryValues.removeAll()
    }

    public func packCount() -> Int {
        if !didLoadPacks {
            reloadPacks()
        }
        return packs.count
    }

    public func fetch(_ tile: TileID) async throws -> Data {
        if !didLoadPacks {
            reloadPacks()
        }
        if let cached = rememberHit(tile) {
            return cached
        }
        for pack in packs {
            if let data = try? await pack.fetch(tile) {
                storeMemory(tile, data)
                return data
            }
        }
        let data = try await disk.fetch(tile)
        storeMemory(tile, data)
        return data
    }

    private func rememberHit(_ tile: TileID) -> Data? {
        guard let data = memoryValues[tile] else { return nil }
        memoryOrder.removeAll { $0 == tile }
        memoryOrder.append(tile)
        return data
    }

    private func storeMemory(_ tile: TileID, _ data: Data) {
        if memoryValues[tile] != nil {
            memoryOrder.removeAll { $0 == tile }
        }
        memoryValues[tile] = data
        memoryOrder.append(tile)
        while memoryOrder.count > memoryCapacity, let oldest = memoryOrder.first {
            memoryOrder.removeFirst()
            memoryValues[oldest] = nil
        }
    }
}

private struct CacheEntry: Codable, Equatable {
    var tile: TileID
    var bytes: Int
    var sequence: Int
}

private struct CacheIndex: Codable, Equatable {
    var nextSequence: Int = 0
    var entries: [CacheEntry] = []
}
