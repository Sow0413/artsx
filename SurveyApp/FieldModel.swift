import Foundation
import SurveyCore

enum FieldTab: String, CaseIterable, Identifiable {
    case map
    case drawing
    case measure
    case export

    var id: String { rawValue }

    var title: String {
        switch self {
        case .map: return "地図"
        case .drawing: return "図面"
        case .measure: return "測る"
        case .export: return "出す"
        }
    }

    var symbol: String {
        switch self {
        case .map: return "map"
        case .drawing: return "ruler"
        case .measure: return "mappin"
        case .export: return "square.and.arrow.up"
        }
    }
}

/// 画面の状態。位置の更新はメインスレッドで Published に書く。
final class FieldModel: ObservableObject {
    @Published private(set) var reading: PositionReading
    @Published private(set) var viewport: MapViewport
    @Published var followUser: Bool
    @Published var tab: FieldTab
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadMessage = "表示中の範囲を、圏外用に保存します。"
    @Published private(set) var savedAreaCount = 0
    @Published private(set) var offlineRevision = 0
    @Published private(set) var visibleControlPoints: [ControlPoint] = []
    @Published var selectedControlPointID: String?
    @Published var benchmarkDurationSeconds: TimeInterval = BenchmarkPlan.defaultDurationSeconds
    @Published private(set) var benchmark: BenchmarkRecorder?
    @Published private(set) var benchmarkStatistics: BenchmarkStatistics?
    @Published private(set) var benchmarkExportURL: URL?
    @Published private(set) var benchmarkMessage: String?
    @Published private(set) var controlPointNotice: String?
    @Published private(set) var workCatalog: WorkCatalog
    @Published private(set) var instrumentTrust: InstrumentTrust
    @Published private(set) var observations: FieldObservationLog
    @Published var showsWorkSettings = false
    @Published private(set) var captureMessage: String?

    let tiles: TileStore
    let packDirectory: URL
    let siteDirectory: URL
    let controlPoints: [ControlPoint]
    private let source: any PositionSource
    private var camera: MapCameraFollow
    private var readTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var benchmarkTask: Task<Void, Never>?
    private var visibleBounds: GeoBounds?
    private var visibleZoom: Int?

    init(
        source: any PositionSource,
        tiles: TileStore,
        packDirectory: URL,
        controlPoints: [ControlPoint] = [],
        controlPointNotice: String? = nil,
        siteDirectory: URL
    ) {
        self.source = source
        self.tiles = tiles
        self.packDirectory = packDirectory
        self.siteDirectory = siteDirectory
        self.controlPoints = controlPoints
        self.controlPointNotice = controlPointNotice
        self.workCatalog = WorkCatalog.load(from: siteDirectory)
        self.instrumentTrust = InstrumentTrust.load(from: siteDirectory)
        self.observations = FieldObservationLog.load(from: siteDirectory)
        self.reading = .waiting
        self.camera = MapCameraFollow()
        self.viewport = MapViewportPolicy.japanOverview
        self.followUser = true
        self.tab = .map
    }

    var badge: AccuracyBadgeModel {
        AccuracyPolicy.badge(
            for: reading,
            work: workCatalog.selected,
            trust: instrumentTrust,
            safetyFactor: workCatalog.optimisticSafetyFactor
        )
    }

    func selectWork(_ id: String) {
        workCatalog = workCatalog.selecting(id)
        try? workCatalog.save(to: siteDirectory)
    }

    func applyWorkEdits(_ works: [WorkRequirement], safetyFactor: Double) {
        var catalog = workCatalog
        guard safetyFactor.isFinite, safetyFactor >= 1 else { return }
        catalog.optimisticSafetyFactor = safetyFactor
        for work in works where work.horizontalMeters > 0, work.verticalMeters > 0 {
            catalog = catalog.replacing(work)
        }
        workCatalog = catalog
        try? workCatalog.save(to: siteDirectory)
    }

    func captureObservation() {
        guard let position = reading.position, position.isPlottable, position.hasValidHorizontalAccuracy else {
            captureMessage = "位置が無いので残せません。"
            return
        }
        let work = workCatalog.selected
        let count = observations.observations.filter { $0.workID == work.id }.count + 1
        let observation = FieldObservation(name: "\(work.shortTitle)\(count)", workID: work.id, captured: position)
        observations = observations.appending(observation)
        try? observations.save(to: siteDirectory)
        captureMessage = "\(observation.name)を残しました。下見の座標は捨てません。"
    }

    func rebase(_ observationID: UUID, onto targetID: UUID) {
        guard let source = observations.observations.first(where: { $0.id == observationID }),
              let target = observations.observations.first(where: { $0.id == targetID }),
              source.id != target.id else { return }
        observations = observations.replacing(source.rebase(onto: target.captured))
        try? observations.save(to: siteDirectory)
        captureMessage = "\(source.name)を\(target.name)の座標に乗せ替えました。取得時の精度は残しています。"
    }

    var selectedControlPoint: ControlPoint? {
        controlPoints.first { $0.id == selectedControlPointID }
    }

    var isBenchmarkRunning: Bool {
        benchmark != nil && benchmarkStatistics == nil
    }

    var benchmarkProgressLabel: String? {
        guard let benchmark, isBenchmarkRunning else { return nil }
        return "三角点で検証 \(benchmark.samples.count)/\(benchmark.plan.expectedCount)"
    }

    func start() {
        source.start()
        if readTask == nil {
            let readings = source.readings
            readTask = Task { [weak self] in
                for await reading in readings {
                    await MainActor.run {
                        self?.apply(reading)
                    }
                }
            }
        }
        let tiles = self.tiles
        Task { [weak self] in
            await tiles.reloadPacks()
            let count = await tiles.packCount()
            await MainActor.run {
                guard let self else { return }
                self.savedAreaCount = count
                if count > 0, !self.isDownloading {
                    self.downloadMessage = "オフライン \(count)件。表示中の範囲を追加で保存できます。"
                }
            }
        }
        refreshVisibleControlPoints()
    }

    func stop() {
        source.stop()
    }

    func userPannedMap() {
        followUser = false
    }

    func recenter() {
        followUser = true
        camera = MapCameraFollow()
        if let position = reading.position, position.isPlottable {
            viewport = camera.update(for: position)
        }
    }

    func noteVisible(bounds: GeoBounds, zoom: Int) {
        visibleBounds = bounds
        visibleZoom = zoom
        refreshVisibleControlPoints()
    }

    func selectControlPoint(_ id: String) {
        guard !isBenchmarkRunning else { return }
        guard controlPoints.contains(where: { $0.id == id }) else { return }
        if benchmarkStatistics != nil {
            clearBenchmarkResults()
        }
        selectedControlPointID = id
        benchmarkMessage = nil
    }

    func startBenchmark() {
        guard !isBenchmarkRunning, let point = selectedControlPoint else { return }
        benchmarkTask?.cancel()
        benchmarkStatistics = nil
        benchmarkExportURL = nil
        benchmarkMessage = nil
        benchmark = BenchmarkRecorder(
            point: point,
            plan: BenchmarkPlan(durationSeconds: benchmarkDurationSeconds, intervalSeconds: 1),
            startedAt: Date()
        )
        benchmarkTask = Task { [weak self] in
            while !Task.isCancelled {
                let finished = await MainActor.run { self?.pumpBenchmark() ?? true }
                if finished || Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func cancelBenchmark() {
        benchmarkTask?.cancel()
        benchmarkTask = nil
        guard let recorder = benchmark else { return }
        if recorder.samples.isEmpty {
            benchmark = nil
            benchmarkMessage = "位置が取れないので、記録を残せませんでした。"
            return
        }
        benchmarkMessage = "中止しました。取れた\(recorder.samples.count)点で集計しています。"
        finishBenchmark(recorder)
    }

    func dismissBenchmark() {
        benchmarkTask?.cancel()
        benchmarkTask = nil
        clearBenchmarkResults()
        selectedControlPointID = nil
        benchmarkMessage = nil
    }

    private func pumpBenchmark() -> Bool {
        guard var recorder = benchmark, benchmarkStatistics == nil else { return true }
        let now = Date()
        if recorder.isFinished(at: now) {
            finishBenchmark(recorder)
            return true
        }
        recorder.tick(reading: reading, now: now)
        benchmark = recorder
        return false
    }

    private func finishBenchmark(_ recorder: BenchmarkRecorder) {
        benchmark = recorder
        benchmarkTask = nil
        guard let statistics = BenchmarkStatistics.make(point: recorder.point, samples: recorder.samples) else {
            benchmark = nil
            benchmarkMessage = "位置が取れないので、記録を残せませんでした。"
            return
        }
        benchmarkStatistics = statistics
        if let position = recorder.samples.last?.position, let optimistic = statistics.horizontalOptimistic {
            instrumentTrust = instrumentTrust.setting(InstrumentState(position), optimistic: optimistic)
            try? instrumentTrust.save(to: siteDirectory)
        }
        writeExport(recorder: recorder, statistics: statistics)
        if benchmarkMessage == nil {
            benchmarkMessage = "記録が終わりました。"
        }
    }

    private func writeExport(recorder: BenchmarkRecorder, statistics: BenchmarkStatistics) {
        let csv = BenchmarkCSV.render(recorder: recorder, statistics: statistics)
        let safe = recorder.point.id.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sankakuten-\(safe).csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            benchmarkExportURL = url
        } catch {
            benchmarkExportURL = nil
            benchmarkMessage = "CSVを書き出せませんでした。"
        }
    }

    private func clearBenchmarkResults() {
        benchmark = nil
        benchmarkStatistics = nil
        benchmarkExportURL = nil
    }

    private func refreshVisibleControlPoints() {
        let position = reading.position
        let userIsPlottable = position?.isPlottable == true
        let next = ControlPointCatalog.visible(
            controlPoints,
            userLatitude: userIsPlottable ? position?.latitudeDegrees : nil,
            userLongitude: userIsPlottable ? position?.longitudeDegrees : nil,
            bounds: visibleBounds
        )
        if next.map(\.id) != visibleControlPoints.map(\.id) {
            visibleControlPoints = next
        }
    }

    func downloadVisibleArea() {
        guard downloadTask == nil else { return }
        guard let bounds = visibleBounds, let zoom = visibleZoom else {
            downloadMessage = "地図の範囲がまだ分かりません"
            return
        }
        let plan: TileDownloadPlan
        do {
            plan = try OfflineAreaPolicy.plan(bounds: bounds, zoom: zoom)
        } catch let error as TileDownloadError {
            downloadMessage = Self.message(for: error)
            return
        } catch {
            downloadMessage = "保存できませんでした"
            return
        }
        let directory = packDirectory.appendingPathComponent("view-\(UUID().uuidString)", isDirectory: true)
        let manifest = BaseMapPackManifest(
            id: directory.lastPathComponent,
            title: "表示中の範囲",
            style: .gsiStandard,
            minZoom: plan.zoomRange.lowerBound,
            maxZoom: plan.zoomRange.upperBound,
            bounds: bounds
        )
        isDownloading = true
        downloadMessage = "保存中 0/\(plan.tiles.count)"
        let (stream, continuation) = AsyncStream<RegionDownloadProgress>.makeStream()
        let progressTask = Task { [weak self] in
            for await progress in stream {
                let text = "保存中 \(progress.completed)/\(progress.total)"
                await MainActor.run {
                    self?.downloadMessage = text
                }
            }
        }
        let tiles = self.tiles
        downloadTask = Task { [weak self] in
            defer { continuation.finish() }
            do {
                let result = try await RegionTileDownloader().download(
                    plan: plan,
                    source: GSINetworkTileFetcher(),
                    directory: directory,
                    manifest: manifest,
                    progress: continuation
                )
                progressTask.cancel()
                await tiles.reloadPacks()
                let count = await tiles.packCount()
                await MainActor.run {
                    guard let self else { return }
                    self.isDownloading = false
                    self.downloadTask = nil
                    self.savedAreaCount = count
                    self.offlineRevision += 1
                    if result.failed > 0 {
                        self.downloadMessage = "一部を保存しました（\(result.completed)/\(result.completed + result.failed)）。"
                    } else {
                        self.downloadMessage = "保存しました。圏外でもこの範囲を表示します。"
                    }
                }
            } catch is CancellationError {
                progressTask.cancel()
                await tiles.reloadPacks()
                let count = await tiles.packCount()
                await MainActor.run {
                    guard let self else { return }
                    self.isDownloading = false
                    self.downloadTask = nil
                    self.savedAreaCount = count
                    self.offlineRevision += 1
                    self.downloadMessage = "中止しました"
                }
            } catch {
                progressTask.cancel()
                await MainActor.run {
                    guard let self else { return }
                    self.isDownloading = false
                    self.downloadTask = nil
                    self.downloadMessage = "保存できませんでした。電波を確認してください。"
                }
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    private func apply(_ reading: PositionReading) {
        self.reading = reading
        refreshVisibleControlPoints()
        guard followUser, let position = reading.position, position.isPlottable else { return }
        viewport = camera.update(for: position)
    }

    private static func message(for error: TileDownloadError) -> String {
        switch error {
        case let .tooManyTiles(count, limit):
            return "範囲が広すぎます（\(count)枚、上限\(limit)）。拡大してから保存してください。"
        case .invalidBounds:
            return "この範囲は保存できません"
        case .nothingSaved:
            return "保存できませんでした。電波を確認してください。"
        }
    }
}
