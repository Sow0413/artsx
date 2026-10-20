import Combine
import Foundation
import SurveyCore

enum FieldTab: String, CaseIterable, Identifiable {
    case map
    case drawing
    case measure
    case export
    case seat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .map: return "地図"
        case .drawing: return "図面"
        case .measure: return "測る"
        case .export: return "出す"
        case .seat: return "オペ"
        }
    }

    var symbol: String {
        switch self {
        case .map: return "map"
        case .drawing: return "ruler"
        case .measure: return "mappin"
        case .export: return "square.and.arrow.up"
        case .seat: return "steeringwheel"
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
    @Published var plannedRounds = 3
    @Published private(set) var rounds: [BenchmarkRound] = []
    @Published private(set) var comparison: CampaignComparison?
    @Published private(set) var campaignClosed = false
    @Published private(set) var correctionStore: CorrectionStore
    @Published var pointPrefix: String
    @Published private(set) var controlFix = ControlFixSession()
    @Published private(set) var stageTransition = StageTransition.ground
    @Published var bookQuery = CoordinateBookQuery()
    @Published var enclosingBook = false
    @Published private(set) var exportMessage: String?
    private var epochWatch = EpochWatch()

    let tiles: TileStore
    let packDirectory: URL
    let siteDirectory: URL
    let drawing: DrawingSession
    let nearby: NearbyLink
    let radio: RadioController
    let crew: CrewController
    let incidents = IncidentSession()
    let fall = FallMonitor()
    let fallRelay = FallRelay(reachable: false)
    @Published private(set) var incidentOpen = false
    @Published private(set) var incidentNote: String?
    @Published private(set) var incidentRecordingMemo = false
    @Published var showsIncidentStats = false
    @Published var showIncidentHeat = false
    @Published var anonymizeStats = true
    @Published private(set) var incidentStatRows: [IncidentStatRow] = []
    @Published private(set) var incidentHeat: [IncidentHeatCell] = []
    @Published private(set) var statMessage: String?
    private let statsRelay = IncidentStatsRelayStub(reachable: false)
    private var incidentTimer: Timer?
    private var restoredIncidentProject: String?
    let controlPoints: [ControlPoint]
    private var prefixStore: PointPrefixStore
    private let source: any PositionSource
    private var camera: MapCameraFollow
    private var readTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var benchmarkTask: Task<Void, Never>?
    private var visibleBounds: GeoBounds?
    private var visibleZoom: Int?
    private var campaignPoint: ControlPoint?
    private var cancellables: Set<AnyCancellable> = []

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
        self.correctionStore = CorrectionStore.load(from: siteDirectory)
        let prefixes = PointPrefixStore.load(from: siteDirectory)
        self.prefixStore = prefixes
        self.pointPrefix = prefixes.prefix(for: prefixes.activeKey)
        self.drawing = DrawingSession(projectsRoot: siteDirectory.appendingPathComponent("プロジェクト", isDirectory: true))
        let nearby = NearbyLink()
        self.nearby = nearby
        self.radio = RadioController(nearby: nearby)
        self.crew = CrewController(nearby: nearby)
        self.reading = .waiting
        self.camera = MapCameraFollow()
        self.viewport = MapViewportPolicy.japanOverview
        self.followUser = true
        self.tab = .map
        drawing.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        radio.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        crew.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        crew.onAlarm = { [weak self] _ in
            self?.recordIncident(trigger: .alarm) ?? false
        }
        crew.onHiyari = { [weak self] in
            self?.recordIncident(trigger: .manual)
        }
        crew.onWatchFall = { [weak self] kind, date, immediate in
            self?.fall.noteExternal(kind: kind, detectedAt: date, now: Date(), immediate: immediate)
        }
        crew.onWatchFallCancel = { [weak self] in
            self?.fall.cancel()
        }
        fall.onAwaiting = { [weak self] kind, date in
            self?.crew.askWatchFall(kind: kind, at: date)
        }
        fall.onConfirmed = { [weak self] kind in
            self?.broadcastFall(kind)
        }
        fall.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        HiyariHook.fire = { [weak self] in
            self?.recordIncident(trigger: .manual)
        }
    }

    func cancelFall() {
        if fall.cancel() {
            crew.clearWatchFall()
        }
    }

    func beginRadio() {
        let project = drawing.project
        let channel = RadioChannel.project(id: project?.id ?? "local", name: project?.name ?? "未選択")
        let position = workingReading.position
        let text = drawing.operatorGuide(at: position)?.line ?? ""
        let stamp = RadioStationStamp(
            text: text,
            latitudeDegrees: position?.latitudeDegrees,
            longitudeDegrees: position?.longitudeDegrees
        )
        radio.begin(channel: channel, station: stamp)
    }

    func endRadio() {
        radio.end(projectName: drawing.project?.name, root: drawing.projectsRoot)
    }

    func toggleHail() {
        if radio.phase == .transmitting {
            endRadio()
        } else {
            beginRadio()
        }
    }

    @discardableResult
    func recordIncident(trigger: IncidentTrigger, workKind: String? = nil, workName: String? = nil) -> Bool {
        guard let project = drawing.project else {
            incidentNote = "先にプロジェクトを作ってください。"
            return false
        }
        guard let position = workingReading.position, position.isPlottable else {
            incidentNote = "位置が無いので記録できません。"
            return false
        }
        let now = Date()
        let radius: Double
        if crew.role == .machine {
            radius = drawing.machineRadiusMeters
        } else {
            radius = crew.peers.first { $0.role == .machine }?.workRadiusMeters ?? drawing.machineRadiusMeters
        }
        let opening = IncidentOpening(
            projectID: project.id,
            projectName: project.name,
            occurredAt: now,
            trigger: trigger,
            parties: IncidentParties.assemble(
                selfID: crew.deviceID,
                selfName: crew.displayName,
                selfRole: crew.role,
                selfLatitude: position.latitudeDegrees,
                selfLongitude: position.longitudeDegrees,
                selfAccuracy: position.horizontalAccuracyMeters,
                selfCourse: position.courseDegrees,
                selfHeading: position.headingDegrees,
                selfRadius: drawing.machineRadiusMeters,
                others: crew.peers,
                distances: crew.distances(),
                stationLine: drawing.stationLine
            ),
            machineRadiusMeters: radius,
            work: IncidentWork(
                kind: workKind ?? drawing.activeRecordKind ?? workCatalog.selected.shortTitle,
                name: workName ?? drawing.activeRecordName ?? workCatalog.selected.title
            ),
            accuracyMeters: position.horizontalAccuracyMeters,
            stageLabel: "段階\(position.stage.rawValue)",
            solutionLabel: position.solutionLabel,
            speeches: crew.recentSpeeches().filter { abs($0.at.timeIntervalSince(now)) <= IncidentBook.beforeSeconds },
            radio: radioClips(around: now),
            strokes: incidentStrokes(around: position),
            notice: trigger == .fall ? "\(SafetyNotice.text) \(FallCall.disclaimer)" : SafetyNotice.text,
            weather: drawing.weatherLabel.isEmpty ? nil : drawing.weatherLabel
        )
        do {
            let id = try incidents.open(opening, projectName: project.name, at: drawing.projectsRoot)
            incidentOpen = incidents.latestID != nil
            if id == opening.id {
                switch trigger {
                case .alarm:
                    incidentNote = "接近警報を記録しています"
                case .manual:
                    incidentNote = "ヒヤリを記録しています"
                case .fall:
                    incidentNote = "\(opening.work.kind)を記録しています"
                }
            }
            return true
        } catch {
            incidentNote = "記録を作れませんでした。"
            return false
        }
    }

    func broadcastFall(_ kind: FallKind) {
        let now = Date()
        guard let project = drawing.project else {
            incidentNote = "プロジェクトが無いので、\(kind.label)は知らせていません。"
            return
        }
        guard let position = workingReading.position, position.isPlottable else {
            incidentNote = "位置が無いので、\(kind.label)は知らせていません。"
            return
        }
        let notice = FallNotice(
            at: now,
            deviceID: crew.deviceID,
            name: crew.displayName,
            kind: kind,
            latitudeDegrees: position.latitudeDegrees,
            longitudeDegrees: position.longitudeDegrees,
            channelID: project.id
        )
        nearby.send(notice)
        fallRelay.isReachable = radio.relayReachable
        let delivery = fallRelay.submit(notice)
        crew.rememberFallSpeech("\(kind.label)を知らせました", at: now)
        crew.noteWatchFallSent("\(kind.label)を近くに知らせました")
        let recorded = recordIncident(trigger: .fall, workKind: kind.label, workName: "転倒検知")
        if recorded {
            incidentNote = delivery == .sent
                ? "\(kind.label)を記録し、P510へ渡しました"
                : "\(kind.label)を記録しました。P510にはまだ渡していません"
        }
    }

    func attachIncidentPhoto(_ data: Data) {
        guard let project = drawing.project else { return }
        do {
            try incidents.attachPhoto(data, projectName: project.name, at: drawing.projectsRoot)
            incidentNote = "写真を添えました"
        } catch {
            incidentNote = "写真は確定した記録には足せません。"
        }
    }

    func toggleIncidentMemo() {
        if let data = IncidentVoiceMemo.toggle() {
            incidentRecordingMemo = false
            attachIncidentVoice(data)
            return
        }
        incidentRecordingMemo = IncidentVoiceMemo.isRecording
        if incidentRecordingMemo {
            incidentNote = "音声メモを録音しています"
        }
    }

    private func attachIncidentVoice(_ data: Data) {
        guard let project = drawing.project else { return }
        do {
            try incidents.attachVoice(data, projectName: project.name, at: drawing.projectsRoot)
            incidentNote = "音声メモを添えました"
        } catch {
            incidentNote = "音声メモは確定した記録には足せません。"
        }
    }

    func beginDrawingMapPick() {
        guard drawing.beginMapPick() else { return }
        followUser = false
        tab = .map
    }

    func cancelDrawingMapPick() {
        drawing.cancelPick()
        tab = .drawing
    }

    func completeDrawingMapPick(latitude: Double, longitude: Double) {
        drawing.addTarget(kind: .map, latitude: latitude, longitude: longitude, label: "地図")
        tab = .drawing
    }

    var badge: AccuracyBadgeModel {
        AccuracyPolicy.badge(
            for: reading,
            work: workCatalog.selected,
            trust: instrumentTrust,
            safetyFactor: workCatalog.optimisticSafetyFactor,
            correction: correctionStore.active,
            now: Date(),
            operatingStage: stageTransition.stage,
            stageNotice: stageTransition.notice,
            demoteForStageDrop: stageTransition.steppedDown
        )
    }

    var workingReading: PositionReading {
        guard let position = reading.position,
              let shifted = correctionStore.active?.workingPosition(from: position, now: Date()) else {
            return reading
        }
        return PositionReading(position: shifted, availability: reading.availability)
    }

    var showsCorrectedPosition: Bool {
        guard let position = reading.position else { return false }
        return correctionStore.active?.applies(to: position, now: Date()) == true
    }

    var returnCheck: ReturnCheck? {
        guard campaignClosed, let comparison, let start = correctionStore.active, let point = campaignPoint,
              start.pointID == point.id, rounds.last?.instrument == start.instrument else { return nil }
        return ReturnCheck.compare(start: start, end: comparison.overall)
    }

    func selectWork(_ id: String) {
        workCatalog = workCatalog.selecting(id)
        try? workCatalog.save(to: siteDirectory)
    }

    func applyWorkEdits(_ works: [WorkRequirement], safetyFactor: Double) {
        var catalog = workCatalog
        guard safetyFactor.isFinite, safetyFactor >= 1 else { return }
        catalog.optimisticSafetyFactor = safetyFactor
        for work in works where work.horizontalMeters > 0 && work.verticalMeters > 0 {
            catalog = catalog.replacing(work)
        }
        workCatalog = catalog
        try? workCatalog.save(to: siteDirectory)
    }

    var nextPointName: String? {
        PointNamer.nextName(prefix: pointPrefix, existing: occupiedNames())
    }

    var canRecordControlPoint: Bool {
        controlFix.canRecord && StageGate.allowsRecording(workID: "boundary", stage: stageTransition.stage)
    }

    static let stageDroppedRecording = "段階が下がったので、基準点の記録を止めました。測位は続けます。"

    func setPointPrefix(_ raw: String) {
        pointPrefix = raw
        guard let prefix = PointNamer.normalizePrefix(raw) else { return }
        let key = drawing.activeRecordFolder ?? prefixStore.activeKey
        prefixStore.activeKey = key
        prefixStore.prefixes[key] = prefix
        try? prefixStore.save(to: siteDirectory)
        if let folder = drawing.activeRecordFolder, let project = drawing.project {
            try? ProjectStore.setRecordPrefix(
                folder: folder,
                prefix: prefix,
                projectName: project.name,
                at: drawing.projectsRoot
            )
        }
    }

    func addProjectRecord(date: String, kind: String, name: String) {
        let prefix = PointNamer.normalizePrefix(pointPrefix)
        guard let folder = drawing.addFieldRecord(date: date, kind: kind, name: name, pointPrefix: prefix) else { return }
        prefixStore.activeKey = folder
        if let prefix {
            prefixStore.prefixes[folder] = prefix
            pointPrefix = prefix
        }
        try? prefixStore.save(to: siteDirectory)
    }

    func captureObservation() {
        guard StageGate.allowsRecording(workID: workCatalog.selected.id, stage: stageTransition.stage) else {
            captureMessage = Self.stageDroppedRecording
            return
        }
        guard let position = reading.position, position.isPlottable, position.hasValidHorizontalAccuracy else {
            captureMessage = "位置が無いので残せません。"
            return
        }
        guard let name = nextPointName else {
            captureMessage = "点名の頭は半角アルファベットだけにしてください。"
            return
        }
        let work = workCatalog.selected
        let correction = correctionStore.active
        let shifted = correction?.applies(to: position, now: Date()) == true ? correction?.subtracting(from: position) : nil
        let condition = ObservationCondition.snapshot(
            position: position,
            stage: stageTransition.stage,
            durationSeconds: epochWatch.duration(at: position.timestamp),
            epochCount: epochWatch.count
        )
        let observation = FieldObservation(
            name: name,
            workID: work.id,
            captured: position,
            corrected: shifted,
            appliedCorrectionID: shifted == nil ? nil : correction?.id,
            condition: condition
        )
        observations = observations.appending(observation)
        try? observations.save(to: siteDirectory)
        remember(CoordinateBookIndex.entry(from: observation, kind: bookKind(for: work)))
        captureMessage = shifted == nil
            ? "\(observation.name)を残しました。下見の座標は捨てません。"
            : "\(observation.name)を残しました。補正を引いた座標も残し、取得時の位置は捨てません。"
    }

    func recordControlPoint() {
        guard StageGate.allowsRecording(workID: "boundary", stage: stageTransition.stage) else {
            captureMessage = Self.stageDroppedRecording
            return
        }
        guard let position = reading.position else {
            captureMessage = "位置が無いので残せません。"
            return
        }
        guard let fix = controlFix.record(at: position.timestamp) else {
            captureMessage = controlFix.restarted
                ? "FIX が切れたので、やり直してください。"
                : "RTK FIX のときだけ基準点を記録できます。FLOAT と単独は残せません。"
            return
        }
        guard let name = nextPointName else {
            captureMessage = "点名の頭は半角アルファベットだけにしてください。"
            return
        }
        let condition = ObservationCondition.snapshot(
            position: fix.position,
            stage: stageTransition.stage,
            durationSeconds: fix.fixDurationSeconds,
            epochCount: fix.epochCount
        )
        let observation = FieldObservation(
            name: name,
            workID: "boundary",
            captured: fix.position,
            fixDurationSeconds: fix.fixDurationSeconds,
            condition: condition
        )
        observations = observations.appending(observation)
        try? observations.save(to: siteDirectory)
        remember(CoordinateBookIndex.entry(from: observation, kind: "基準点"))
        let satellites = condition.satelliteNote
        let vertical = fix.verticalAccuracyMeters.map { CoordinateText.accuracyMeters($0) } ?? "—"
        captureMessage = "\(name)を基準点にしました。\(condition.solutionLabel) \(Int(fix.fixDurationSeconds.rounded()))秒、水平 \(CoordinateText.accuracyMeters(fix.horizontalAccuracyMeters))、高さ \(vertical)、衛星 \(satellites)。"
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
        radio.arm()
        crew.arm()
        nearby.onFall = { [weak self] notice in
            DispatchQueue.main.async {
                guard let self else { return }
                self.crew.receiveFall(notice, position: self.workingReading.position)
            }
        }
        fall.start()
        incidentTimer?.invalidate()
        incidentTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.crew.ageFall(now: Date())
            self?.closeIncidents(now: Date())
        }
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
        if let position = workingReading.position, position.isPlottable {
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
        if campaignPoint?.id != id {
            clearCampaign()
        }
        selectedControlPointID = id
        benchmarkMessage = nil
    }

    func startBenchmark() {
        guard !isBenchmarkRunning, let point = selectedControlPoint else { return }
        if campaignPoint?.id != point.id {
            rounds = []
            comparison = nil
            campaignClosed = false
        }
        campaignPoint = point
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
        let instrument = recorder.samples.last.map { InstrumentState($0.position) }
            ?? InstrumentState(receiver: .iphoneGPS, stage: .iphone, fixQuality: .standalone)
        rounds.append(BenchmarkRound(
            index: rounds.count + 1,
            startedAt: recorder.startedAt,
            samples: recorder.samples,
            statistics: statistics,
            instrument: instrument
        ))
        comparison = CampaignComparison.make(point: recorder.point, rounds: rounds)
        campaignClosed = rounds.count >= max(plannedRounds, 1)
        writeCampaignExport(point: recorder.point)
        if benchmarkMessage == nil {
            benchmarkMessage = campaignClosed
                ? "記録が終わりました。"
                : "置き直して、向きを変えてから次の回を始めてください。"
        }
    }

    private func writeCampaignExport(point: ControlPoint) {
        let plan = benchmark?.plan ?? BenchmarkPlan(durationSeconds: benchmarkDurationSeconds)
        var body = ""
        for (index, round) in rounds.enumerated() {
            let recorder = BenchmarkRecorder(point: point, plan: plan, startedAt: round.startedAt, samples: round.samples)
            let csv = BenchmarkCSV.render(recorder: recorder, statistics: round.statistics)
            if index == 0 {
                body = csv
            } else {
                let rows = csv.split(separator: "\n", omittingEmptySubsequences: false).dropFirst()
                body += rows.joined(separator: "\n")
            }
        }
        let safe = point.id.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sankakuten-\(safe).csv")
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            benchmarkExportURL = url
        } catch {
            benchmarkExportURL = nil
            benchmarkMessage = "CSVを書き出せませんでした。"
        }
    }

    private func clearBenchmarkResults() {
        clearCampaign()
    }

    func summarizeCampaign() {
        guard !rounds.isEmpty, !isBenchmarkRunning else { return }
        campaignClosed = true
        benchmarkMessage = "この回数でまとめました。"
    }

    func applyControlCorrection() {
        guard let point = campaignPoint, let comparison, let instrument = rounds.last?.instrument,
              let correction = ControlCorrection.make(
                point: point,
                instrument: instrument,
                comparison: comparison,
                acquiredAt: Date()
              ) else {
            benchmarkMessage = "回のずれがそろっていないので、補正値にはしません。"
            return
        }
        correctionStore = correctionStore.saving(correction)
        try? correctionStore.save(to: siteDirectory)
        benchmarkMessage = "\(point.name)の補正を、以後の観測から引きます。"
    }

    func chooseReturn(_ choice: ClosureChoice) {
        guard let start = correctionStore.active, let comparison, let point = campaignPoint, start.pointID == point.id else { return }
        let endAt = rounds.last?.samples.last?.loggedAt ?? Date()
        let updated: [FieldObservation]
        switch choice {
        case .apportion:
            updated = ClosureAdjustmentMath.apportion(
                observations: observations.observations,
                start: start,
                end: comparison.overall,
                endAt: endAt
            )
            benchmarkMessage = "途中の点に、時刻の割合で差を振りました。元の座標は残しています。"
        case .resurvey:
            updated = ClosureAdjustmentMath.markResurvey(
                observations: observations.observations,
                start: start,
                endAt: endAt
            )
            benchmarkMessage = "途中の点に要再測の印を付けました。元の座標は残しています。"
        }
        observations = FieldObservationLog(observations: updated)
        try? observations.save(to: siteDirectory)
        let check = ReturnCheck.compare(start: start, end: comparison.overall)
        correctionStore.lastReturnCheck = ReturnCheckRecord(
            pointID: point.id,
            startCorrectionID: start.id,
            checkedAt: Date(),
            horizontalDifferenceMeters: check.horizontalDifferenceMeters,
            verticalDifferenceMeters: check.verticalDifferenceMeters,
            valid: check.valid,
            choice: choice
        )
        try? correctionStore.save(to: siteDirectory)
    }

    private func clearCampaign() {
        benchmark = nil
        benchmarkStatistics = nil
        benchmarkExportURL = nil
        rounds = []
        comparison = nil
        campaignPoint = nil
        campaignClosed = false
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

    private func occupiedNames() -> Set<String> {
        var names = Set(observations.observations.map(\.name))
        names.formUnion(controlPoints.map(\.name))
        names.formUnion(SiteCoordinateBook.load(from: siteDirectory).map(\.name))
        if let project = drawing.project {
            names.formUnion(ProjectStore.coordinateBookNames(projectName: project.name, at: drawing.projectsRoot))
        }
        return names
    }

    func beginBookEnclosure() {
        enclosingBook = true
        followUser = false
        tab = .map
    }

    func cancelBookEnclosure() {
        enclosingBook = false
        tab = .export
    }

    func confirmBookEnclosure() {
        bookQuery.bounds = viewport.bounds
        enclosingBook = false
        tab = .export
    }

    func clearBookFilters() {
        bookQuery = CoordinateBookQuery()
    }

    func filteredBookEntries() -> [CoordinateBookEntry] {
        let projectBook = drawing.project.map {
            ProjectStore.coordinateBookEntries(projectName: $0.name, at: drawing.projectsRoot)
        } ?? []
        let collected = CoordinateBookIndex.collect(
            book: projectBook + SiteCoordinateBook.load(from: siteDirectory),
            observations: observations.observations,
            known: controlPoints
        )
        return CoordinateBookQuery.apply(collected, query: bookQuery)
    }

    func exportDelivery(_ format: DeliveryFormat) {
        let entries = filteredBookEntries()
        guard !entries.isEmpty else {
            exportMessage = "絞り込みに合う点がありません。"
            return
        }
        let bytes = CoordinateDelivery.data(entries, format: format, zone: drawing.zone)
        do {
            let folder = try deliveryFolder()
            let url = folder.appendingPathComponent(format.filename)
            try bytes.write(to: url, options: .atomic)
            exportMessage = "\(format.label)を \(entries.count) 点、\(format.filename) に書きました。"
        } catch {
            exportMessage = "書き出せませんでした。"
        }
    }

    private func deliveryFolder() throws -> URL {
        if let project = drawing.project {
            return try ProjectStore.exportDirectory(projectName: project.name, at: drawing.projectsRoot)
        }
        let folder = siteDirectory.appendingPathComponent("出す", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func bookKind(for work: WorkRequirement) -> String {
        work.id == "boundary" ? "基準点" : work.shortTitle
    }

    private func remember(_ entry: CoordinateBookEntry) {
        try? SiteCoordinateBook.append(entry, to: siteDirectory)
        if let project = drawing.project {
            try? ProjectStore.saveCoordinate(entry, projectName: project.name, at: drawing.projectsRoot)
        }
    }

    private func apply(_ reading: PositionReading) {
        self.reading = reading
        if let position = reading.position {
            let wasRecording = controlFix.canRecord
            let transition = StageLadder.step(held: stageTransition.stage, reported: position)
            stageTransition = transition
            epochWatch.observe(position)
            controlFix.observe(position, at: position.timestamp)
            if wasRecording && !StageGate.allowsRecording(workID: "boundary", stage: transition.stage) {
                if controlFix.canRecord {
                    controlFix.abort()
                }
                captureMessage = Self.stageDroppedRecording
            }
        }
        if let position = workingReading.position, position.isPlottable {
            drawing.noteReference(
                latitude: position.latitudeDegrees,
                longitude: position.longitudeDegrees,
                name: "現在地"
            )
        }
        crew.note(
            position: workingReading.position,
            project: drawing.project,
            radius: drawing.machineRadiusMeters,
            root: drawing.projectsRoot
        )
        trackIncidents()
        refreshVisibleControlPoints()
        guard followUser, let position = workingReading.position, position.isPlottable else { return }
        viewport = camera.update(for: position)
    }

    private func trackIncidents(now: Date = Date()) {
        guard let project = drawing.project else { return }
        if restoredIncidentProject != project.name {
            restoredIncidentProject = project.name
            incidents.restore(projectName: project.name, at: drawing.projectsRoot)
        }
        var batch: [IncidentSample] = []
        if let position = workingReading.position, position.isPlottable {
            batch.append(IncidentSample(
                at: now,
                id: crew.deviceID,
                name: crew.displayName,
                role: crew.role,
                latitudeDegrees: position.latitudeDegrees,
                longitudeDegrees: position.longitudeDegrees,
                horizontalAccuracyMeters: position.horizontalAccuracyMeters,
                courseDegrees: position.courseDegrees,
                headingDegrees: position.headingDegrees
            ))
        }
        for peer in crew.peers {
            batch.append(IncidentSample(
                at: peer.sentAt,
                id: peer.id,
                name: peer.name,
                role: peer.role,
                latitudeDegrees: peer.latitudeDegrees,
                longitudeDegrees: peer.longitudeDegrees,
                horizontalAccuracyMeters: peer.horizontalAccuracyMeters,
                courseDegrees: peer.courseDegrees,
                headingDegrees: peer.headingDegrees
            ))
        }
        incidents.observe(batch, projectName: project.name, at: drawing.projectsRoot)
        closeIncidents(now: now)
    }

    private func closeIncidents(now: Date) {
        guard let project = drawing.project else { return }
        incidents.relay.isReachable = radio.relayReachable
        fallRelay.isReachable = radio.relayReachable
        fallRelay.flush()
        let results = (try? incidents.closeDue(
            projectName: project.name,
            at: drawing.projectsRoot,
            now: now,
            speeches: crew.recentSpeeches(),
            radio: radioClips(around: now),
            audio: radio.audioData()
        )) ?? []
        if !results.isEmpty {
            let sent = results.contains { $0.delivery == .sent }
            incidentNote = sent
                ? "ヒヤリハット報告書を記録し、P510へ渡しました"
                : "ヒヤリハット報告書を記録簿に入れました。P510にはまだ渡していません"
        }
        incidents.flush(projectName: project.name, at: drawing.projectsRoot, now: now)
        incidentOpen = incidents.latestID != nil
        if !results.isEmpty {
            reloadIncidentStats()
        }
    }

    func reloadIncidentStats() {
        guard let project = drawing.project else {
            incidentStatRows = []
            incidentHeat = []
            return
        }
        incidentStatRows = IncidentStats.load(project: project, at: drawing.projectsRoot, anonymize: anonymizeStats)
        incidentHeat = IncidentStats.heat(incidentStatRows)
    }

    func exportIncidentStats() {
        guard let project = drawing.project else {
            statMessage = "先にプロジェクトを作ってください。"
            return
        }
        reloadIncidentStats()
        do {
            _ = try IncidentStats.writeCSV(incidentStatRows, projectName: project.name, at: drawing.projectsRoot)
            statsRelay.isReachable = radio.relayReachable
            let csv = IncidentStats.csv(incidentStatRows)
            let delivery = statsRelay.submit(csv: csv)
            statMessage = delivery == .sent
                ? "集計CSVを書き、P510へ渡しました"
                : "集計CSVを記録簿に書きました。P510にはまだ渡していません"
        } catch {
            statMessage = "集計CSVを書けませんでした。"
        }
    }

    private func radioClips(around now: Date) -> [IncidentRadioClip] {
        radio.recentUtterances().compactMap { utterance in
            let end = utterance.endedAt ?? utterance.startedAt
            let overlaps = end.timeIntervalSince(now) >= -IncidentBook.beforeSeconds
                && utterance.startedAt.timeIntervalSince(now) <= IncidentBook.afterSeconds
            guard overlaps else { return nil }
            return IncidentRadioClip(
                id: utterance.id,
                speaker: utterance.speaker,
                startedAt: utterance.startedAt,
                endedAt: utterance.endedAt,
                stationText: utterance.station?.text,
                audioByteCount: utterance.audioByteCount,
                delivered: utterance.delivered
            )
        }
    }

    private func incidentStrokes(around position: GeodeticPosition) -> [IncidentStroke] {
        guard let line = drawing.stationLine,
              let origin = PlaneRectangular.forward(
                latitudeDegrees: position.latitudeDegrees,
                longitudeDegrees: position.longitudeDegrees,
                zone: line.zone
              ) else { return [] }
        var east: [Double] = []
        var north: [Double] = []
        for vertex in line.vertices {
            let deltaEast = vertex.x - origin.eastingMeters
            let deltaNorth = vertex.y - origin.northingMeters
            if abs(deltaEast) < 150, abs(deltaNorth) < 150 {
                east.append(deltaEast)
                north.append(deltaNorth)
            } else if !east.isEmpty {
                break
            }
        }
        guard east.count >= 2 else { return [] }
        return [IncidentStroke(eastMeters: east, northMeters: north)]
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
