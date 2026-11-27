import Combine
import Foundation
import SurveyCore

struct StakeoutLines: Equatable {
    var zone: String
    var name: String
    var distance: String
    var north: String
    var east: String
    var height: String
}

struct SealedIncidentRow: Identifiable, Equatable {
    var id: UUID
    var title: String
}

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
        case .measure: return "データ"
        case .export: return "出す"
        case .seat: return "オペ"
        }
    }

    var symbol: String {
        switch self {
        case .map: return "map"
        case .drawing: return "ruler"
        case .measure: return "tray.full"
        case .export: return "square.and.arrow.up"
        case .seat: return "steeringwheel"
        }
    }

    /// ベーシックのタブバー。図面とオペは出さない。
    static var bar: [FieldTab] {
        SurveyBuild.basicMode ? [.map, .measure, .export] : Array(allCases)
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
    /// 測設を仮置きしたときの設計差。画面に残す。
    @Published private(set) var stakeResult: String?
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
    @Published private(set) var exportURL: URL?
    /// 出すの1段目。現場の下敷きに置いた図面。
    @Published private(set) var projectSheet: ProjectSheet?
    @Published private(set) var sheetMessage: String?
    @Published private(set) var sheetZoneChoices: [Int] = []
    @Published private(set) var bookNote: String?
    @Published private(set) var bookZoneChoices: [Int] = []
    @Published private(set) var canPlaceOnSite = false
    @Published private(set) var coordinateZoneChoices: [Int] = []
    private var zoneIsExplicit = false
    /// 図面フィクスチャを地図へ重ねた結果。`-surveyUITestDrawings` のときだけ書く。
    @Published var uiTestDrawingStatus: String?
    private var uiTestDrawingStep = 0
    private var heldSidecarData: Data?
    private var trustedZone: Int?
    private var pendingSheet: PendingDrawingSheet?
    private var pendingBook: (data: Data, filename: String)?

    private struct PendingDrawingSheet {
        var data: Data
        var fileName: String
        var document: DrawingDocument
        var kind: String
        var axis: DrawingAxis
        var books: [(Data, String)]
    }
    @Published var scaleMessage: String?
    @Published var localizeMessage: String?
    @Published var cadMessage: String?
    struct LocalizeDraft: Identifiable, Equatable {
        var id = UUID()
        var name: String
        var designEast: Double
        var designNorth: Double
        var measuredEast: Double
        var measuredNorth: Double
    }
    @Published var localizeDrafts: [LocalizeDraft] = []
    @Published var instrument = SiteInstrument()
    @Published var instrumentMessage: String?
    @Published var tiltDegrees: Double?
    @Published var tiltMeanDegrees: Double?
    @Published var tiltMaxDegrees: Double?
    @Published var deviceTiltLive = false
    @Published var laserReadingMeters: Double?
    @Published var laserLamp: ViDocCommandPlan.Lamp = .off
    @Published var rawCaptureEnabled = true
    @Published var rawCaptureStatus = "停止"
    private var rawObservationID: UUID?
    private let rawCaptureKey = "arts.raw-capture"
    @Published var ppkStatus = "停止"
    @Published var ppkShare: URL?
    private var ppkBase: URL?
    private var tiltWindow: [(TimeInterval, Double)] = []
    @Published var receiverFirmware: String?
    @Published var operation = OperationDesk.load()
    @Published var showsToolOrder = false
    @Published var stature = StatureProfile.load()
    @Published var showsStature = false
    @Published var asksStature = false
    @Published var showsCrosshair = false
    @Published var showsBatter = false
    @Published var showsPace = false
    @Published var showsARStakeout = false
    @Published var basicTarget: CoordinateBookEntry?
    @Published private(set) var basicRevision = 0
    @Published var pace = PaceProfile.load()
    @Published var stakeoutUnit = StakeoutPacePreference.load()
    @Published var stakeoutSpeechStyle = StakeoutSpeechPreference.load()
    @Published var stakeoutSpeechMode = ARGuidanceMode.augmented
    @Published var arHandoff = ARHandoffPreference.load()
    @Published private(set) var walkMode: WalkMode = .gnss
    @Published private(set) var bridgeFix: WalkFix?
    @Published private(set) var bridgeNotice: String?
    @Published private(set) var calibrating = false
    @Published private(set) var calibrationSteps = 0
    @Published private(set) var pacing = false
    @Published private(set) var measureSteps = 0
    @Published private(set) var paceFix: WalkFix?
    @Published var batter = BatterSettings.load()
    @Published var poleHeight = PoleHeight.load()
    @Published var tiltZero = TiltZero.load()
    @Published private(set) var crosshairTilt: Double?
    @Published private(set) var sightTiltRadians: Double?
    @Published private(set) var measuredEyeDistance: Double?
    let deviceMachine = DeviceIdentity.machine
    private var sightInForeground = false
    private let tiltUI = UIThrottle()
    private let distanceUI = UIThrottle()
    private let crosshairUI = UIThrottle()
    private let readingUI = UIThrottle()
    private var pendingReading: PositionReading?
    private var announcedEyeLevel = false
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
    let sosRelay = SOSRelay(reachable: false)
    let aidRelay = AidRelay(reachable: false)
    let disasterRelay = DisasterRelay(reachable: false)
    var bucketDesk = BucketDesk(selfID: "")
    var disasterPeersDesk = DisasterPeers()
    var lastDisasterShare: Date?
    var lastDisasterRelay: Date?
    var lastPassageSample: PassageSample?
    var disasterPeersNearby = 0
    var disasterUplink = DisasterUplink()
    var disasterLoadedProject: String?
    #if canImport(Network)
    var disasterPath: DisasterPathMonitor?
    #endif
    @Published var disasterMode = false
    @Published var batterySaver = false
    @Published var disasterSites: [DisasterSite] = []
    @Published var disasterSegments: [PassageSegment] = []
    @Published var disasterPeers: [DisasterPosition] = []
    @Published var disasterTexts: [DisasterText] = []
    @Published var disasterPending = 0
    @Published var disasterMessage: String?
    @Published var showsDisaster = false
    @Published var meshBattery: Int?
    @Published var meshCharging = false
    @Published var meshPresence: MeshDuty.Presence = .active
    @Published private(set) var firstEpisode: FirstEpisode?
    @Published private(set) var firstView: FirstView?
    @Published private(set) var aidArrows: [AidArrow] = []
    @Published var showsReadout119 = false
    @Published private(set) var sosActive = false
    @Published private(set) var sosPointer: SOSPointer?
    @Published private(set) var sosHelpers = ""
    @Published var showsEmergencySOS = false
    @Published private(set) var incidentOpen = false
    @Published private(set) var incidentNote: String?
    @Published private(set) var incidentRecordingMemo = false
    @Published var showsIncidentStats = false
    @Published var showIncidentHeat = false
    @Published var anonymizeStats = IncidentStats.anonymizeByDefault
    /// 休憩の一時停止。この画面だけ。project.json には残さない。
    @Published var sharePaused = false
    @Published private(set) var locationShare: ShareState = .unset
    @Published private(set) var shareViewers: [ShareViewer] = []
    @Published var showsPrivacy = false
    @Published private(set) var privacyMessage: String?
    @Published var extras: ExtraSwitches
    @Published var showsExtras = false
    #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth) && canImport(Network)
    @Published var showsRTK = false
    #endif
    @Published private(set) var gnssState: GNSSLinkState = .idle
    @Published private(set) var gnssChoices: [GNSSChoice] = []
    @Published private(set) var observationCount = 0
    @Published private(set) var incidentStatRows: [IncidentStatRow] = []
    @Published private(set) var sealedIncidents: [SealedIncidentRow] = []
    @Published private(set) var incidentHeat: [IncidentHeatCell] = []
    @Published private(set) var statMessage: String?
    private let statsRelay = IncidentStatsRelayStub(reachable: false)
    private var incidentTimer: Timer?
    private var restoredIncidentProject: String?
    private(set) var controlPoints: [ControlPoint]
    let journal: FieldJournal
    let gnss: GNSSLink
    let gnssAvailable: Bool
    private var prefixStore: PointPrefixStore
    private var lastFixSave = Date.distantPast
    private let source: any PositionSource
    #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth) && canImport(Network)
    var rtkSession: RTKPositionSession? { source as? RTKPositionSession }
    #endif
    private var camera: MapCameraFollow
    private var readTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var benchmarkTask: Task<Void, Never>?
    private var visibleBounds: GeoBounds?
    private var visibleZoom: Int?
    private var campaignPoint: ControlPoint?
    private var sosDesk = SOSDesk()
    private var sosIncoming: SOSBeacon?
    private var firstDesk = FirstDesk()
    private var firstIncidentID: UUID?
    private var lastIncidentID: UUID?
    private var spokenFirst = ""
    private var cancellables: Set<AnyCancellable> = []
    private let paceSession = PaceSession()
    private var measureBridge: WalkBridge?
    private var deadReckon: WalkBridge?
    private var bridgeSteps = 0
    private let paceVision = UUID()
    private var paceVisionOn = false
    private var measureSeenX: Double?
    private var measureSeenZ: Double?
    private var bridgeSeenX: Double?
    private var bridgeSeenZ: Double?
    private var paceYaw: Double?

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
        let journal = FieldJournal(directory: siteDirectory)
        journal.importLegacyIfNeeded()
        self.journal = journal
        self.observations = FieldObservationLog(observations: journal.recent())
        self.observationCount = journal.count()
        let gnssBox = GNSSRadioBox.make()
        self.gnss = gnssBox.link
        self.gnssAvailable = gnssBox.available
        self.correctionStore = CorrectionStore.load(from: siteDirectory)
        let prefixes = PointPrefixStore.load(from: siteDirectory)
        self.prefixStore = prefixes
        self.pointPrefix = prefixes.prefix(for: prefixes.activeKey)
        self.drawing = DrawingSession(projectsRoot: siteDirectory.appendingPathComponent("プロジェクト", isDirectory: true))
        self.extras = ExtraSwitchStore.load(from: siteDirectory)
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
        crew.onSOS = { [weak self] in
            self?.startSOS()
        }
        crew.onSOSStop = { [weak self] in
            self?.stopSOS()
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
        radio.spacePoint = { [weak self] in
            guard let pointer = self?.talkPointer, pointer.known, let degrees = pointer.relativeDegrees else { return nil }
            return TalkDirection.space(relativeDegrees: degrees, distanceMeters: pointer.distanceMeters ?? 0)
        }
        HiyariHook.fire = { [weak self] in
            self?.recordIncident(trigger: .manual)
        }
        drawing.onProjectCommitted = { [weak self] in
            self?.rememberSession()
        }
        $tab.dropFirst().sink { [weak self] _ in
            self?.rememberSession()
        }.store(in: &cancellables)
        let saved = journal.session()
        if let tab = FieldTab(rawValue: saved.tab) {
            self.tab = tab
        }
        if SurveyBuild.basicMode, !FieldTab.bar.contains(self.tab) {
            self.tab = .map
        }
        if SurveyBuild.basicMode, pointPrefix.isEmpty {
            pointPrefix = "T"
        }
        if let workID = saved.workID, workCatalog.works.contains(where: { $0.id == workID }) {
            workCatalog = workCatalog.selecting(workID)
        }
        controlFix = saved.controlFix
        if let name = saved.projectName, let project = drawing.projects.first(where: { $0.name == name }) {
            drawing.select(project)
        }
        gnss.onState = { [weak self] state in
            self?.gnssState = state
        }
        #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth) && canImport(Network)
        rtkSession?.onDeviceTilt = { [weak self] degrees in
            self?.noteTilt(degrees, fromDevice: true)
        }
        rtkSession?.onLaserDistance = { [weak self] meters in
            self?.instrument.laserMeters = meters
            self?.instrument.antennaMethod = "laser"
            self?.laserReadingMeters = meters
            self?.instrumentMessage = String(format: "下レーザー %.3f m", meters)
        }
        rtkSession?.onLaserFailed = { [weak self] in
            self?.instrumentMessage = "測れず"
        }
        rtkSession?.onLaserLamp = { [weak self] lamp in
            self?.laserLamp = lamp
        }
        rtkSession?.onLaserNeedAim = { [weak self] in
            self?.instrumentMessage = "先に点灯してください。"
        }
        if UserDefaults.standard.object(forKey: rawCaptureKey) == nil {
            rawCaptureEnabled = true
        } else {
            rawCaptureEnabled = UserDefaults.standard.bool(forKey: rawCaptureKey)
        }
        rtkSession?.onRawStatus = { [weak self] text in
            self?.rawCaptureStatus = text
        }
        rtkSession?.onRawFinished = { [weak self] unverified in
            self?.noteRawRestore(unverified: unverified)
        }
        #endif
        gnss.onDiscover = { [weak self] choice in
            DispatchQueue.main.async {
                guard let self else { return }
                if !self.gnssChoices.contains(where: { $0.id == choice.id }) {
                    self.gnssChoices.append(choice)
                }
            }
        }
        paceSession.onSteps = { [weak self] slot, count in
            self?.ingestSteps(slot, count)
        }
    }

    func cancelFall() {
        if fall.cancel() {
            crew.clearWatchFall()
        }
    }

    func toggleSOS() {
        if sosDesk.session.active {
            stopSOS()
        } else {
            startSOS()
        }
    }

    func startSOS() {
        guard extras.sos else { return }
        guard drawing.project != nil else {
            incidentNote = "先にプロジェクトを作ってください。"
            return
        }
        guard !sosDesk.session.active else { return }
        guard sosDesk.begin(at: Date()) != nil else { return }
        sosActive = true
        SOSSound.arm()
        crew.tellWatchSOS(live: true)
        let previousIncident = lastIncidentID
        refreshSOS(now: Date())
        beginFirst(trigger: .sos, incidentID: lastIncidentID != previousIncident ? lastIncidentID : nil)
    }

    func stopSOS() {
        guard sosDesk.session.active, let project = drawing.project else { return }
        let position = navigationReading.position
        let plottable = position?.isPlottable == true
        guard let beacon = sosDesk.end(
            deviceID: crew.deviceID,
            name: crew.displayName,
            channelID: project.id,
            latitude: plottable ? position?.latitudeDegrees : nil,
            longitude: plottable ? position?.longitudeDegrees : nil,
            at: Date()
        ) else { return }
        sendSOS(SOSPacket(beacon: beacon))
        sosActive = false
        crew.tellWatchSOS(live: false)
        incidentNote = "SOSを止めました"
    }

    func refreshSOS(now: Date = Date()) {
        sosRelay.isReachable = radio.relayReachable
        sosRelay.flush()
        guard sosDesk.session.active, let project = drawing.project else { return }
        let position = navigationReading.position
        let plottable = position?.isPlottable == true
        guard let beacon = sosDesk.beacon(
            deviceID: crew.deviceID,
            name: crew.displayName,
            channelID: project.id,
            latitude: plottable ? position?.latitudeDegrees : nil,
            longitude: plottable ? position?.longitudeDegrees : nil,
            at: now
        ) else { return }
        sendSOS(SOSPacket(beacon: beacon))
        if !sosDesk.session.incidentOpened {
            if recordIncident(trigger: .sos, workKind: "SOS", workName: "SOS") {
                sosDesk.markIncidentOpened()
            }
        }
    }

    func respondSOS() {
        guard let beacon = sosIncoming else { return }
        let reply = sosDesk.reply(
            to: beacon,
            fromDeviceID: crew.deviceID,
            fromName: crew.displayName,
            at: Date()
        )
        sendSOS(SOSPacket(reply: reply))
        incidentNote = "向かう、と返しました"
    }

    func ingestSOS(_ packet: SOSPacket, arrived: SOSPath) {
        guard extras.sos else { return }
        if let beacon = packet.beacon {
            guard beacon.channelID == drawing.project?.id, beacon.deviceID != crew.deviceID else { return }
            let position = navigationReading.position
            let plottable = position?.isPlottable == true
            let heard = sosDesk.hear(
                beacon,
                selfLatitude: plottable ? position?.latitudeDegrees : nil,
                selfLongitude: plottable ? position?.longitudeDegrees : nil,
                courseDegrees: position?.courseDegrees,
                headingDegrees: position?.headingDegrees,
                facing: tab == .seat ? .machine : .own,
                now: Date()
            )
            if heard.beacon.active {
                sosPointer = heard.pointer
                sosIncoming = heard.beacon
            } else if sosIncoming?.id == heard.beacon.id {
                sosPointer = nil
                sosIncoming = nil
            }
            if heard.speak {
                crew.rememberFallSpeech(heard.pointer.text, at: Date())
                CrewVoice.say(heard.pointer.text)
                SOSSound.ring(heard.pointer.text)
                crew.alertSOS(heard.pointer.text)
            }
            if sosDesk.shouldForward(beacon, arrived: arrived, relayReachable: radio.relayReachable) {
                sosRelay.isReachable = true
                sosRelay.submit(SOSPacket(beacon: beacon))
            }
        }
        if let reply = packet.reply,
           sosDesk.hearReply(reply, selfDeviceID: crew.deviceID, beaconID: sosDesk.session.beaconID) {
            sosHelpers = sosDesk.helperLine
            CrewVoice.say(sosDesk.helperLine)
        }
    }

    private func sendSOS(_ packet: SOSPacket) {
        switch SOSPath.choose(relayReachable: radio.relayReachable) {
        case .relay:
            sosRelay.isReachable = true
            sosRelay.submit(packet)
        case .nearby:
            nearby.send(packet)
        }
        relayDisasterSOS(packet)
    }

    func acceptNearestDuty() {
        guard let episode = firstDesk.acceptNearest(deviceID: crew.deviceID, at: Date()) else { return }
        commitFirst(episode)
    }

    func assignGreeter(id: String, name: String) {
        guard let episode = firstDesk.assignGreeter(id: id, name: name, at: Date()) else { return }
        commitFirst(episode)
    }

    func acceptGreeterDuty() {
        guard let episode = firstDesk.acceptGreeter(deviceID: crew.deviceID, at: Date()) else { return }
        commitFirst(episode)
    }

    func takeGreeterDuty() {
        assignGreeter(id: crew.deviceID, name: crew.displayName)
        acceptGreeterDuty()
    }

    func setAidCheck(_ item: AidCheck, answer: Bool) {
        guard let episode = firstDesk.setCheck(item, answer: answer, at: Date()) else { return }
        commitFirst(episode)
    }

    func openReadout119() {
        showsReadout119 = true
        if let episode = firstDesk.noteReadout(at: Date()) {
            commitFirst(episode)
        }
        CrewVoice.say(readoutSpeech())
    }

    func noteCall119() {
        if let episode = firstDesk.noteCall(at: Date()) {
            commitFirst(episode)
        }
    }

    func endFirst() {
        guard let episode = firstDesk.end(at: Date()) else { return }
        commitFirst(episode)
    }

    func saveSiteAid(_ aid: SiteAid) {
        drawing.setSiteAid(aid)
        refreshAidArrows()
    }

    func addAidPoint(_ kind: AidPointKind) {
        guard let position = workingReading.position, position.isPlottable else {
            incidentNote = "位置が無いので置けません。"
            return
        }
        var aid = drawing.project?.siteAid ?? .empty
        aid.points.append(AidPoint(
            kind: kind,
            latitudeDegrees: position.latitudeDegrees,
            longitudeDegrees: position.longitudeDegrees
        ))
        saveSiteAid(aid)
        incidentNote = "\(kind.label)をここに置きました"
    }

    func removeAidPoint(_ id: String) {
        var aid = drawing.project?.siteAid ?? .empty
        aid.points.removeAll { $0.id == id }
        saveSiteAid(aid)
    }

    func addAidContact(name: String, phone: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty || !trimmedPhone.isEmpty else { return }
        var aid = drawing.project?.siteAid ?? .empty
        aid.contacts.append(AidContact(name: trimmedName, phone: trimmedPhone))
        saveSiteAid(aid)
    }

    func removeAidContact(_ id: String) {
        var aid = drawing.project?.siteAid ?? .empty
        aid.contacts.removeAll { $0.id == id }
        saveSiteAid(aid)
    }

    private func beginFirst(trigger: IncidentTrigger, incidentID: UUID?) {
        guard extras.firstResponse else { return }
        guard let project = drawing.project else { return }
        guard let position = workingReading.position, position.isPlottable else { return }
        let peers = crew.peers.map {
            FirstPeer(
                id: $0.id,
                name: $0.name,
                latitudeDegrees: $0.latitudeDegrees,
                longitudeDegrees: $0.longitudeDegrees,
                sentAt: $0.sentAt,
                courseDegrees: $0.courseDegrees,
                headingDegrees: $0.headingDegrees
            )
        }
        guard let episode = firstDesk.begin(
            trigger: trigger,
            victimID: crew.deviceID,
            victimName: crew.displayName,
            latitude: position.latitudeDegrees,
            longitude: position.longitudeDegrees,
            channelID: project.id,
            peers: peers,
            at: Date()
        ) else { return }
        firstIncidentID = incidentID
        commitFirst(episode)
    }

    private func commitFirst(_ episode: FirstEpisode) {
        publishFirst(speak: true)
        sendAid(AidPacket(episode: episode))
        recordAidStamps(episode.stamps)
    }

    private func publishFirst(speak: Bool) {
        let episode = firstDesk.episode
        firstEpisode = episode
        refreshAidArrows()
        guard let episode, episode.active else {
            firstView = nil
            spokenFirst = ""
            return
        }
        let position = workingReading.position
        let plottable = position?.isPlottable == true
        let view = FirstCall.view(
            episode: episode,
            selfID: crew.deviceID,
            selfLatitude: plottable ? position?.latitudeDegrees : nil,
            selfLongitude: plottable ? position?.longitudeDegrees : nil,
            courseDegrees: position?.courseDegrees,
            headingDegrees: position?.headingDegrees,
            facing: tab == .seat ? .machine : .own
        )
        firstView = view
        let line = view.nearestOpen || view.greeterOpen ? view.headline : view.progress
        if speak, line != spokenFirst {
            spokenFirst = line
            CrewVoice.say(line)
        }
    }

    private func refreshAidArrows() {
        let position = workingReading.position
        let plottable = position?.isPlottable == true
        aidArrows = FirstCall.arrows(
            points: drawing.project?.siteAid?.points ?? [],
            selfLatitude: plottable ? position?.latitudeDegrees : nil,
            selfLongitude: plottable ? position?.longitudeDegrees : nil,
            courseDegrees: position?.courseDegrees,
            headingDegrees: position?.headingDegrees,
            facing: tab == .seat ? .machine : .own
        )
    }

    private func recordAidStamps(_ stamps: [AidStamp]) {
        guard firstDesk.originated, let id = firstIncidentID, let project = drawing.project else { return }
        for stamp in stamps {
            try? incidents.noteAid(stamp, incidentID: id, projectName: project.name, at: drawing.projectsRoot)
        }
    }

    private func readoutSpeech() -> String {
        let site = drawing.project?.siteAid ?? .empty
        let position = workingReading.position
        let plottable = position?.isPlottable == true
        return Readout119.speech(
            site: site,
            latitude: plottable ? position?.latitudeDegrees : nil,
            longitude: plottable ? position?.longitudeDegrees : nil
        )
    }

    func ingestAid(_ packet: AidPacket, arrived: SOSPath) {
        guard extras.firstResponse else { return }
        guard packet.episode.channelID == drawing.project?.id else { return }
        let before = firstDesk.episode?.stamps ?? []
        guard firstDesk.hear(packet.episode) else { return }
        if firstDesk.originated {
            let known = Set(before.map { "\($0.at.timeIntervalSince1970)|\($0.text)" })
            let fresh = packet.episode.stamps.filter { !known.contains("\($0.at.timeIntervalSince1970)|\($0.text)") }
            recordAidStamps(fresh)
        }
        publishFirst(speak: true)
        if firstDesk.shouldForward(packet.episode, arrived: arrived, relayReachable: radio.relayReachable) {
            aidRelay.isReachable = true
            aidRelay.submit(packet)
        }
    }

    private func sendAid(_ packet: AidPacket) {
        switch SOSPath.choose(relayReachable: radio.relayReachable) {
        case .relay:
            aidRelay.isReachable = true
            aidRelay.submit(packet)
        case .nearby:
            nearby.send(packet)
        }
    }

    private func sosNotice(_ trigger: IncidentTrigger) -> String {
        switch trigger {
        case .fall:
            return "\(SafetyNotice.text) \(FallCall.disclaimer)"
        case .sos:
            return SOSCall.disclaimer
        case .alarm, .manual:
            return SafetyNotice.text
        }
    }

    func beginRadio() {
        guard extras.pushToTalk else { return }
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
    func setExtra(_ key: WritableKeyPath<ExtraSwitches, Bool>, _ on: Bool) {
        var next = extras
        next[keyPath: key] = on
        extras = next
        try? ExtraSwitchStore.save(next, to: siteDirectory)
        applyExtraSwitches()
    }

    func applyExtraSwitches() {
        fall.setEnabled(extras.fall)
        if !extras.disaster {
            disasterMode = false
            batterySaver = false
        }
        if !extras.sos, sosActive {
            stopSOS()
        }
        if !extras.pushToTalk, radio.phase == .transmitting {
            endRadio()
        }
        applyShareGate()
    }

    func recordIncident(trigger: IncidentTrigger, workKind: String? = nil, workName: String? = nil) -> Bool {
        switch trigger {
        case .alarm, .manual:
            guard extras.proximity else { return false }
        case .fall:
            guard extras.fall else { return false }
        case .sos:
            guard extras.sos else { return false }
        }
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
            notice: sosNotice(trigger),
            weather: drawing.weatherLabel.isEmpty ? nil : drawing.weatherLabel,
            address: siteAddress
        )
        do {
            let id = try incidents.open(opening, projectName: project.name, at: drawing.projectsRoot)
            incidentOpen = incidents.latestID != nil
            if id == opening.id {
                lastIncidentID = id
                switch trigger {
                case .alarm:
                    incidentNote = "接近警報を記録しています"
                case .manual:
                    incidentNote = "ヒヤリを記録しています"
                case .fall:
                    incidentNote = "\(opening.work.kind)を記録しています"
                case .sos:
                    incidentNote = "SOSを記録しています"
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
        let previousIncident = lastIncidentID
        let recorded = recordIncident(trigger: .fall, workKind: kind.label, workName: "転倒検知")
        beginFirst(trigger: .fall, incidentID: lastIncidentID != previousIncident ? lastIncidentID : nil)
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

    /// 受信中だけ。オペ画面は重機の向き、それ以外は自分の進行か方位。
    var talkPointer: TalkPointer? {
        guard let speaker = radio.hearingSpeaker else { return nil }
        let position = navigationReading.position
        let plottable = position?.isPlottable == true
        return TalkDirection.pointer(
            speaker: speaker,
            fixes: crew.peers,
            selfLatitude: plottable ? position?.latitudeDegrees : nil,
            selfLongitude: plottable ? position?.longitudeDegrees : nil,
            courseDegrees: position?.courseDegrees,
            headingDegrees: position?.headingDegrees,
            facing: tab == .seat ? .machine : .own,
            now: Date()
        )
    }

    var workingReading: PositionReading {
        guard let position = reading.position,
              let shifted = correctionStore.active?.workingPosition(from: position, now: Date()) else {
            return reading
        }
        return PositionReading(position: shifted, availability: reading.availability)
    }

    /// 地図と共有に出す位置。GNSS が弱いあいだは歩行推測。観測の記録は workingReading のまま。
    var navigationReading: PositionReading {
        let base = workingReading
        guard walkMode == .bridge, let bridge = deadReckon else { return base }
        let fix = bridgeFix
        let sigma = fix?.sigmaMeters ?? PaceMath.bridgeSigma(pathMeters: 0, disagreementMeters: 0)
        let latitude = fix?.latitudeDegrees ?? bridge.originLatitude
        let longitude = fix?.longitudeDegrees ?? bridge.originLongitude
        if var position = base.position {
            position.latitudeDegrees = latitude
            position.longitudeDegrees = longitude
            position.horizontalAccuracyMeters = sigma
            position.stage = .iphone
            position.fixQuality = .standalone
            position.receiver = .iphoneGPS
            position.correctionAgeSeconds = nil
            position.correctionSource = nil
            position.timestamp = Date()
            return PositionReading(position: position, availability: base.availability)
        }
        return PositionReading(
            position: IPhonePosition.make(
                latitudeDegrees: latitude,
                longitudeDegrees: longitude,
                ellipsoidalHeightMeters: nil,
                horizontalAccuracyMeters: sigma,
                verticalAccuracyMeters: nil,
                timestamp: Date()
            ),
            availability: .available
        )
    }

    var navigationNote: String? {
        var parts: [String] = []
        if showsCorrectedPosition { parts.append("三角点補正を引いた位置") }
        if walkMode == .bridge {
            let sigma = bridgeFix?.sigmaMeters ?? PaceMath.bridgeSigma(pathMeters: 0, disagreementMeters: 0)
            parts.append("歩行推測　\(PaceMath.estimateText(sigma))")
        } else if let bridgeNotice {
            parts.append(bridgeNotice)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "。")
    }

    var pacePathMeters: Double {
        paceFix?.pathMeters ?? measureBridge?.pathMeters ?? 0
    }

    var paceWaitsForHeading: Bool {
        pacing && paceFix == nil && measureSteps > 0 && pacePathMeters == 0
    }

    var paceBadge: PaceBadge {
        let walking = pacing || paceFix != nil
        let distance = walking ? pacePathMeters : nil
        let sigma = distance.map { PaceMath.paceSigma(distanceMeters: $0) }
        return PaceMath.badge(distanceMeters: distance, sigmaMeters: sigma)
    }

    func arTargets() -> [ARStakeoutTarget] {
        let zone = drawing.zone
        var targets: [ARStakeoutTarget] = []
        if let inspection = drawing.inspection,
           let east = inspection.eastingMeters,
           let north = inspection.northingMeters {
            let name = inspection.snapLabel ?? "タップした点"
            targets.append(ARStakeoutTarget(name: name, eastingMeters: east, northingMeters: north))
        }
        for entry in journal.bookEntries() {
            guard let plane = PlaneRectangular.forward(
                latitudeDegrees: entry.latitudeDegrees,
                longitudeDegrees: entry.longitudeDegrees,
                zone: zone
            ) else { continue }
            if targets.contains(where: { $0.name == entry.name }) { continue }
            targets.append(ARStakeoutTarget(name: entry.name, eastingMeters: plane.eastingMeters, northingMeters: plane.northingMeters))
        }
        return targets
    }

    /// タップした測設点までの案内。オペ画面の測点には使わない。
    var stakeoutGuide: StakeoutPaceGuide? {
        guard let inspection = drawing.inspection,
              let targetLatitude = inspection.latitudeDegrees,
              let targetLongitude = inspection.longitudeDegrees,
              let here = navigationReading.position,
              here.isPlottable,
              let inverse = GRS80Geodesic.inverse(
                latitude1: here.latitudeDegrees,
                longitude1: here.longitudeDegrees,
                latitude2: targetLatitude,
                longitude2: targetLongitude
              ) else { return nil }
        let facing = StakeoutSpeech.screenForward(headingDegrees: here.headingDegrees)
        return StakeoutPace.guide(
            distanceMeters: inverse.distanceMeters,
            azimuthDegrees: inverse.azimuthDegrees,
            facingDegrees: facing,
            strideMeters: pace.strideMeters,
            unit: stakeoutUnit.unit,
            precision: StakeoutPrecision.decide(drawing.stakeoutAccuracy)
        )
    }

    /// 画面の上を前にした短い声。数字は、数値も読むときだけ足す。オペ画面では使わない。
    var stakeoutUtterance: StakeoutUtterance? {
        guard let inspection = drawing.inspection,
              let targetLatitude = inspection.latitudeDegrees,
              let targetLongitude = inspection.longitudeDegrees,
              let here = navigationReading.position,
              here.isPlottable,
              let inverse = GRS80Geodesic.inverse(
                latitude1: here.latitudeDegrees,
                longitude1: here.longitudeDegrees,
                latitude2: targetLatitude,
                longitude2: targetLongitude
              ) else { return nil }
        return StakeoutSpeech.utterance(
            distanceMeters: inverse.distanceMeters,
            azimuthDegrees: inverse.azimuthDegrees,
            headingDegrees: here.headingDegrees,
            style: stakeoutSpeechStyle.style,
            strideMeters: pace.strideMeters,
            unit: stakeoutUnit.unit,
            current: stakeoutSpeechMode,
            switchMeters: arHandoff.meters,
            precision: StakeoutPrecision.decide(drawing.stakeoutAccuracy)
        )
    }

    func setStakeoutUnit(_ unit: StakeoutUnit) {
        let preference = StakeoutPacePreference(unit: unit)
        stakeoutUnit = preference
        preference.save()
    }

    func setStakeoutSpeech(_ style: StakeoutSpeechStyle) {
        let preference = StakeoutSpeechPreference(style: style)
        stakeoutSpeechStyle = preference
        preference.save()
    }

    func setARHandoff(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed), let meters = ARHandoffPreference.accepted(value) else {
            return "切替距離は 0.2m から 20m です。"
        }
        let preference = ARHandoffPreference(meters: meters)
        arHandoff = preference
        preference.save()
        return "\(String(format: "%g", meters))m 未満で数値、\(String(format: "%g", preference.resumeMeters))m でARに戻します。"
    }

    var paceFactorText: String {
        guard let factor = PaceMath.factor(slope: pace.slope, override: pace.factorOverride) else { return "—" }
        return String(format: "%.3f", locale: Self.posix, factor)
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
        rememberSession()
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

    static let stageDroppedRecording = StageDropNotice.recordingStopped

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

    @discardableResult
    func captureObservation() -> Bool {
        guard basicProjectReady() else { return false }
        guard StageGate.allowsRecording(workID: workCatalog.selected.id, stage: stageTransition.stage) else {
            captureMessage = Self.stageDroppedRecording
            return false
        }
        guard let position = reading.position, position.isPlottable, position.hasValidHorizontalAccuracy else {
            captureMessage = "位置が無いので残せません。"
            return false
        }
        guard let name = nextPointName else {
            captureMessage = "点名の頭は半角アルファベットだけにしてください。"
            return false
        }
        let work = workCatalog.selected
        let correction = correctionStore.active
        let shifted = correction?.applies(to: position, now: Date()) == true ? correction?.subtracting(from: position) : nil
        let condition = ObservationCondition.snapshot(
            position: position,
            stage: stageTransition.stage,
            durationSeconds: epochWatch.duration(at: position.timestamp),
            epochCount: epochWatch.count,
            stature: stature,
            sight: liveSight
        )
        let observation = FieldObservation(
            name: name,
            workID: work.id,
            captured: position,
            corrected: shifted,
            appliedCorrectionID: shifted == nil ? nil : correction?.id,
            condition: condition
        )
        store(observation)
        remember(CoordinateBookIndex.entry(from: observation, kind: bookKind(for: work)))
        captureMessage = shifted == nil
            ? "\(observation.name)を残しました。下見の座標は捨てません。"
            : "\(observation.name)を残しました。補正を引いた座標も残し、取得時の位置は捨てません。"
        return true
    }

    /// 地図の記録。解の種類と精度を付けて仮置きし、座標簿には入れない。
    @discardableResult
    func stageMapObservation() -> Bool {
        stageCurrentPoint(asGCP: false)
    }

    /// FIX のときだけ仮置きの GCP。座標簿には入れない。
    @discardableResult
    func stageMapGCP() -> Bool {
        guard canStageGCP else { return false }
        return stageCurrentPoint(asGCP: true)
    }

    var canStageGCP: Bool {
        guard let position = reading.position, position.fixQuality == .rtkFix, position.receiver != .iphoneGPS else { return false }
        #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth) && canImport(Network)
        if rtkSession?.holdGCPUntilFix == true { return false }
        #endif
        return true
    }

    private func stageCurrentPoint(asGCP: Bool) -> Bool {
        rtkSession?.setObserving(true)
        defer { rtkSession?.setObserving(false) }
        guard basicProjectReady() else { return false }
        guard let position = reading.position, position.isPlottable, position.hasValidHorizontalAccuracy else {
            captureMessage = "位置が無いので残せません。"
            return false
        }
        guard !asGCP || position.fixQuality == .rtkFix else { return false }
        if !PrecisionGate.tiltAllowsStart(degrees: tiltDegrees) {
            captureMessage = "鉛直から 0.5° を超えているので、観測を始めません。"
            return false
        }
        if instrument.complianceEnabled {
            let duration = epochWatch.duration(at: position.timestamp) ?? 0
            if !PrecisionGate.complianceAllowsStart(fix: position.fixQuality == .rtkFix, durationSeconds: duration) {
                captureMessage = "準拠モードは FIX が 10 秒以上のときだけ仮置きできます。"
                return false
            }
        }
        guard let name = nextPointName else {
            captureMessage = "点名の頭は半角アルファベットだけにしてください。"
            return false
        }
        var condition = ObservationCondition.snapshot(
            position: position,
            stage: stageTransition.stage,
            durationSeconds: epochWatch.duration(at: position.timestamp),
            epochCount: epochWatch.count
        )
        annotate(&condition, position: position)
        let observation = FieldObservation(
            name: name,
            workID: asGCP ? "boundary" : workCatalog.selected.id,
            captured: position,
            condition: condition
        )
        store(observation)
        if let base = ppkBase { PPKLog.noteObservation(observation.name, base: base) }
        if rawCaptureEnabled {
            startRawCapture(observation)
        }
        let accuracy = CoordinateText.accuracyMeters(position.horizontalAccuracyMeters)
        captureMessage = asGCP
            ? "\(name)を仮置きしました。GCP \(position.solutionLabel) \(accuracy)。"
            : "\(name)を仮置きしました。\(position.solutionLabel) \(accuracy)。"
        return true
    }

    /// ベーシックは、今の位置を GCP として残す。RTK が無いときは、その解のまま書く。
    @discardableResult
    private func recordBasicGCP() -> Bool {
        guard let position = reading.position, position.isPlottable, position.hasValidHorizontalAccuracy else {
            captureMessage = "位置が無いので残せません。"
            return false
        }
        guard let name = nextPointName else {
            captureMessage = "点名の頭は半角アルファベットだけにしてください。"
            return false
        }
        let condition = ObservationCondition.snapshot(
            position: position,
            stage: stageTransition.stage,
            durationSeconds: epochWatch.duration(at: position.timestamp),
            epochCount: epochWatch.count
        )
        let observation = FieldObservation(
            name: name,
            workID: "boundary",
            captured: position,
            condition: condition
        )
        store(observation)
        remember(CoordinateBookIndex.entry(from: observation, kind: "GCP"))
        let vertical = position.verticalAccuracyMeters.map { CoordinateText.accuracyMeters($0) } ?? "—"
        captureMessage = "\(name)を基準点にしました。\(condition.solutionLabel) 水平 \(CoordinateText.accuracyMeters(position.horizontalAccuracyMeters))、高さ \(vertical)。"
        return true
    }

    @discardableResult
    func recordControlPoint() -> Bool {
        guard basicProjectReady() else { return false }
        if SurveyBuild.basicMode {
            return recordBasicGCP()
        }
        guard StageGate.allowsRecording(workID: "boundary", stage: stageTransition.stage) else {
            captureMessage = Self.stageDroppedRecording
            return false
        }
        guard let position = reading.position else {
            captureMessage = "位置が無いので残せません。"
            return false
        }
        guard let fix = controlFix.record(at: position.timestamp) else {
            captureMessage = controlFix.restarted
                ? "FIX が切れたので、やり直してください。"
                : "RTK FIX のときだけ基準点を記録できます。FLOAT と単独は残せません。"
            return false
        }
        guard let name = nextPointName else {
            captureMessage = "点名の頭は半角アルファベットだけにしてください。"
            return false
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
        store(observation)
        remember(CoordinateBookIndex.entry(from: observation, kind: SurveyBuild.basicMode ? "GCP" : "基準点"))
        let satellites = condition.satelliteNote
        let vertical = fix.verticalAccuracyMeters.map { CoordinateText.accuracyMeters($0) } ?? "—"
        captureMessage = "\(name)を基準点にしました。\(condition.solutionLabel) \(Int(fix.fixDurationSeconds.rounded()))秒、水平 \(CoordinateText.accuracyMeters(fix.horizontalAccuracyMeters))、高さ \(vertical)、衛星 \(satellites)。"
        return true
    }

    var liveSight: SightSample? {
        guard let sightTiltRadians else { return nil }
        return SightSample.resolved(
            tiltRadians: sightTiltRadians,
            measuredDistance: measuredEyeDistance,
            antennaAlongUpMeters: AntennaCatalog.alongUpMeters(model: deviceMachine)
        )
    }

    var statureNotice: String? {
        guard let position = reading.position else { return nil }
        return StatureMath.notice(profile: stature, stage: stageTransition.stage, receiver: position.receiver, sight: liveSight)
    }

    func setCrosshairSession(_ on: Bool) {
        #if !SURVEY_PLAYGROUND && canImport(CoreMotion)
        if on {
            SystemMotion.shared.onCrosshairPitch = { [weak self] pitch in
                let tilt = StatureMath.tiltFromVertical(pitchRadians: pitch)
                self?.crosshairUI.submit { [weak self] in
                    self?.crosshairTilt = tilt
                }
            }
            SystemMotion.shared.setCrosshairPitch(true)
        } else {
            SystemMotion.shared.setCrosshairPitch(false)
            SystemMotion.shared.onCrosshairPitch = nil
            crosshairTilt = nil
        }
        #else
        if !on { crosshairTilt = nil }
        #endif
    }

    func saveTiltZero(_ bias: Double) {
        tiltZero = TiltZero(biasRadians: bias, calibrated: true)
        tiltZero.save()
    }

    func saveBatter(_ settings: BatterSettings) {
        let clean = settings.sanitized()
        batter = clean
        clean.save()
    }

    func savePoleMeters(_ meters: Double?) {
        let height = PoleHeight(meters: meters)
        poleHeight = height
        height.save()
    }

    /// 決めた高さを種別「丁張」で残す。身長補正は掛けない。iPhone なら段階0。
    @discardableResult
    func registerBatter(measuredHeight: Double, note: String? = nil) -> Bool {
        guard var position = workingReading.position, position.isPlottable else {
            captureMessage = "位置が無いので、残せません。"
            return false
        }
        guard let record = BatterMath.record(measured: measuredHeight, stage: position.stage, receiver: position.receiver) else {
            captureMessage = "高さが無いので、残せません。"
            return false
        }
        guard let name = nextPointName else {
            captureMessage = "点名の頭は半角アルファベットだけにしてください。"
            return false
        }
        position.ellipsoidalHeightMeters = record.heightMeters
        let condition = ObservationCondition.snapshot(
            position: position,
            stage: record.stage,
            durationSeconds: nil,
            epochCount: nil
        )
        let observation = FieldObservation(
            name: name,
            workID: workCatalog.selected.id,
            captured: position,
            condition: condition
        )
        store(observation)
        remember(CoordinateBookIndex.entry(from: observation, kind: record.kind))
        let guide = record.guide ? "\(BatterMath.guideWord)。" : ""
        if let note {
            captureMessage = "\(name)を丁張にしました。\(note)"
        } else {
            captureMessage = "\(name)を丁張にしました。段階\(record.stage.rawValue)。\(guide)"
        }
        return true
    }

    func knownBookHeights(matching text: String) -> [KnownHeight] {
        journal.bookEntries(matching: text, limit: 20).compactMap(KnownHeightPick.book)
    }

    var crosshairElevation: Double? {
        guard let crosshairTilt else { return nil }
        return tiltZero.corrected(crosshairTilt)
    }

    /// 今の端末高から持ち高さを引いた地盤高。水準の器械高に使う。
    func crosshairGroundHeight() -> Double? {
        guard let device = reading.position?.ellipsoidalHeightMeters else { return nil }
        let sight = liveSight ?? crosshairTilt.flatMap { tilt in
            SightSample.resolved(
                tiltRadians: tilt,
                measuredDistance: measuredEyeDistance,
                antennaAlongUpMeters: AntennaCatalog.alongUpMeters(model: deviceMachine)
            )
        }
        guard let hold = StatureMath.holdMeters(profile: stature, sight: sight) else { return nil }
        return device - hold
    }

    @discardableResult
    func registerTarget(_ shot: TargetResult, rangeLabel: String) -> Bool {
        guard let latitude = shot.latitudeDegrees, let longitude = shot.longitudeDegrees else {
            captureMessage = "方位が無いので、座標は登録できません。"
            return false
        }
        guard let name = nextPointName else {
            captureMessage = "点名の頭は半角アルファベットだけにしてください。"
            return false
        }
        let origin = reading.position
        let accuracy = CrosshairMath.storedAccuracy(
            originHorizontal: origin?.horizontalAccuracyMeters ?? shot.horizontalSigmaMeters,
            originVertical: origin?.verticalAccuracyMeters,
            aimHorizontal: shot.horizontalSigmaMeters,
            aimVertical: shot.heightSigmaMeters
        )
        let position = CrosshairMath.position(
            latitude: latitude,
            longitude: longitude,
            height: shot.targetHeightMeters,
            horizontalAccuracy: accuracy.horizontal,
            verticalAccuracy: accuracy.vertical,
            at: Date()
        )
        let condition = ObservationCondition.snapshot(
            position: position,
            stage: .iphone,
            durationSeconds: nil,
            epochCount: nil
        )
        let observation = FieldObservation(
            name: name,
            workID: workCatalog.selected.id,
            captured: position,
            condition: condition
        )
        store(observation)
        remember(CoordinateBookIndex.entry(from: observation, kind: CrosshairMath.kind))
        captureMessage = "\(name)を簡易ターゲットにしました。\(rangeLabel)、段階0。"
        return true
    }

    func setSightForeground(_ active: Bool) {
        sightInForeground = active
        guard !SurveyBuild.basicMode else { return }
        syncSightSensors()
        if active {
            paceSession.resume()
        } else {
            paceSession.pause()
        }
    }

    func savePace(_ profile: PaceProfile) {
        let clean = profile.sanitized()
        pace = clean
        clean.save()
        if let stride = clean.strideMeters {
            measureBridge?.strideMeters = stride
            deadReckon?.strideMeters = stride
        }
        measureBridge?.slope = clean.slope
        measureBridge?.factorOverride = clean.factorOverride
        deadReckon?.slope = clean.slope
        deadReckon?.factorOverride = clean.factorOverride
        if clean.strideMeters == nil, walkMode == .bridge {
            finishBridge(restored: false)
        }
        refreshPace()
        refreshBridge()
    }

    func beginCalibration() {
        calibrating = true
        calibrationSteps = 0
        paceSession.watch(.calibration, from: Date())
    }

    func endCalibration(distanceMeters: Double) {
        paceSession.unwatch(.calibration)
        calibrating = false
        guard let stride = PaceMath.stride(distanceMeters: distanceMeters, steps: calibrationSteps) else {
            captureMessage = "歩幅にできません。平らな所で、5m以上を5歩以上歩いてください。"
            return
        }
        var next = pace
        next.strideMeters = stride
        next.calibratedDistanceMeters = distanceMeters
        next.calibratedSteps = calibrationSteps
        next.strideOrigin = .walked
        next.strideSetAt = Date()
        savePace(next)
        captureMessage = "歩幅を\(Self.meters(stride))にしました。"
    }

    func beginPace() {
        guard let stride = pace.strideMeters else {
            captureMessage = "先に自分の校正で身長を入れるか、歩幅を合わせてください。"
            return
        }
        guard let origin = workingReading.position, origin.isPlottable else {
            captureMessage = "開始の位置が無いので、歩けません。"
            return
        }
        pacing = true
        measureSteps = 0
        paceFix = nil
        measureSeenX = nil
        measureSeenZ = nil
        measureBridge = WalkBridge(
            originLatitude: origin.latitudeDegrees,
            originLongitude: origin.longitudeDegrees,
            strideMeters: stride,
            slope: pace.slope,
            factorOverride: pace.factorOverride
        )
        paceSession.watch(.measure, from: Date())
        holdPaceVision()
        refreshPace()
    }

    func endPace() {
        guard pacing else { return }
        pacing = false
        paceSession.unwatch(.measure)
        measureBridge?.add(totalSteps: measureSteps, headingDegrees: headingNow)
        refreshPace()
        releasePaceVisionIfIdle()
    }

    func noteManualSteps(_ slot: PaceSlot, _ count: Int) {
        guard count >= 0 else { return }
        ingestSteps(slot, count)
    }

    /// 歩いた終わりを種別「歩測」で残す。身長補正は掛けない。段階は 0。
    @discardableResult
    func recordPace() -> Bool {
        guard let fix = paceFix else {
            captureMessage = measureBridge == nil
                ? "先に歩測を始めてください。"
                : "方位が無いので、点は残せません。"
            return false
        }
        guard let name = nextPointName else {
            captureMessage = "点名の頭は半角アルファベットだけにしてください。"
            return false
        }
        let sigma = PaceMath.paceSigma(distanceMeters: fix.pathMeters)
        let position = IPhonePosition.make(
            latitudeDegrees: fix.latitudeDegrees,
            longitudeDegrees: fix.longitudeDegrees,
            ellipsoidalHeightMeters: reading.position?.ellipsoidalHeightMeters,
            horizontalAccuracyMeters: sigma,
            verticalAccuracyMeters: nil,
            timestamp: Date(),
            headingDegrees: headingNow
        )
        let condition = ObservationCondition.snapshot(
            position: position,
            stage: .iphone,
            durationSeconds: nil,
            epochCount: nil
        )
        let observation = FieldObservation(
            name: name,
            workID: workCatalog.selected.id,
            captured: position,
            condition: condition
        )
        store(observation)
        remember(CoordinateBookIndex.entry(from: observation, kind: PaceMath.kind))
        captureMessage = "\(name)を歩測で残しました。\(PaceMath.distanceText(fix.pathMeters))、段階0。\(PaceMath.estimateText(sigma))。"
        return true
    }

    func saveStature(_ profile: StatureProfile) {
        let stored: StatureProfile
        if let meters = profile.statureMeters,
           let adopted = PersonalProfile.adopt(statureMeters: meters, stature: profile, pace: pace, at: Date()) {
            stored = adopted.stature
            savePace(adopted.pace)
        } else {
            stored = profile
        }
        stature = stored
        stored.save()
        if stored.statureMeters != nil {
            asksStature = false
        }
        syncSightSensors()
    }

    func reapplyStature() {
        let profile = stature
        let catalog = workCatalog
        let journal = journal
        DispatchQueue.global(qos: .userInitiated).async {
            let updated = journal.allObservations().map { $0.applying(profile) }
            DispatchQueue.main.async {
                for item in updated where StatureMath.applies(stage: item.captured.stage, receiver: item.captured.receiver) || item.condition?.stature != nil {
                    try? self.journal.commit(item)
                    let kind = item.workID == "boundary" ? "基準点" : (catalog.works.first { $0.id == item.workID }?.shortTitle ?? item.workID)
                    self.remember(CoordinateBookIndex.entry(from: item, kind: kind))
                }
                self.observations = FieldObservationLog(observations: self.journal.recent())
                self.observationCount = self.journal.count()
                self.captureMessage = "段階0の点へ、今の身長補正を掛け直しました。"
            }
        }
    }

    func setSkill(_ level: SkillLevel) {
        operation.level = level
        operation.phase = .idle
        operation.pending = nil
        operation.save()
    }

    func moveTools(from source: IndexSet, to destination: Int) {
        operation.shelf.move(from: source, to: destination)
        operation.save()
    }

    func toggleOperationDetail() {
        operation.toggleDetail()
        operation.save()
    }

    func toggleControlSection() {
        operation.toggleControl()
    }

    func toggleEyesFree() {
        operation.eyesFree.toggle()
        operation.save()
    }

    func receiveOperation(_ input: OperationInput) {
        let effect = operation.preview(input)
        switch effect {
        case .saveObservation(let feedback):
            guard captureObservation() else { return }
            operation.commit(effect)
            ConfirmCue.play(feedback)
        case .saveControl(let feedback):
            guard recordControlPoint() else { return }
            operation.commit(effect)
            ConfirmCue.play(feedback)
        case .openWork:
            operation.commit(effect)
            tab = .map
        case .openExport:
            operation.commit(effect)
            tab = .export
        default:
            operation.commit(effect)
        }
    }

    func consumePendingConfirm() {
        guard OperationPending.consume() else { return }
        receiveOperation(.actionButton)
    }

    func rebase(_ observationID: UUID, onto targetID: UUID) {
        guard let source = observations.observations.first(where: { $0.id == observationID }),
              let target = observations.observations.first(where: { $0.id == targetID }),
              source.id != target.id else { return }
        let replaced = source.rebase(onto: target.captured)
        observations = observations.replacing(replaced)
        try? journal.commit(replaced)
        observationCount = journal.count()
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
        loadUITestDrawingIfRequested()
        loadVIPackIfRequested()
        if !SurveyBuild.basicMode,
           stature.statureMeters == nil,
           !ProcessInfo.processInfo.arguments.contains("-skipStatureAsk") {
            asksStature = true
        }
        consumePendingConfirm()
        guard !SurveyBuild.basicMode else {
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
            return
        }
        radio.arm()
        radio.onRelay = { [weak self] packet in
            DispatchQueue.main.async {
                self?.relayRadio(packet)
            }
        }
        crew.arm()
        nearby.onFall = { [weak self] notice in
            DispatchQueue.main.async {
                guard let self, self.extras.fall else { return }
                self.crew.receiveFall(notice, position: self.workingReading.position)
            }
        }
        nearby.onSOS = { [weak self] packet in
            DispatchQueue.main.async {
                guard let self, self.extras.sos else { return }
                self.ingestSOS(packet, arrived: .nearby)
            }
        }
        nearby.onAid = { [weak self] packet in
            DispatchQueue.main.async {
                guard let self, self.extras.firstResponse else { return }
                self.ingestAid(packet, arrived: .nearby)
            }
        }
        nearby.onBucket = { [weak self] envelope in
            DispatchQueue.main.async {
                self?.ingestBucket(envelope)
            }
        }
        nearby.observePeers { [weak self] count in
            DispatchQueue.main.async {
                self?.disasterPeerCount(count)
            }
        }
        startDisasterUplink()
        fall.setEnabled(extras.fall)
        fall.start()
        incidentTimer?.invalidate()
        incidentTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.crew.ageFall(now: Date())
            self?.closeIncidents(now: Date())
        }
        source.start()
        resumeGNSS()
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
        setSightForeground(false)
        pauseGNSS()
        source.stop()
    }

    private func syncSightSensors() {
        let on = sightInForeground && stature.style == .sight
        PhoneSight.setEnabled(on) { [weak self] tilt in
            self?.noteTilt(tilt)
        } onDistance: { [weak self] meters in
            self?.distanceUI.submit { [weak self] in
                self?.measuredEyeDistance = meters
            }
        }
        if !on {
            sightTiltRadians = nil
            measuredEyeDistance = nil
            announcedEyeLevel = false
        }
    }

    private func noteTilt(_ tilt: Double?) {
        let level = tilt.map(StatureMath.isEyeLevel) ?? false
        if level && !announcedEyeLevel {
            LevelCue.play()
            announcedEyeLevel = true
        } else if !level {
            announcedEyeLevel = false
        }
        tiltUI.submit { [weak self] in
            self?.sightTiltRadians = tilt
        }
    }

    func userPannedMap() {
        followUser = false
    }

    func recenter() {
        followUser = true
        camera = MapCameraFollow()
        if let position = navigationReading.position, position.isPlottable {
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
        let span = journal.between(start.acquiredAt, and: endAt)
        let sourceRows = span.isEmpty ? observations.observations : span
        let updated: [FieldObservation]
        switch choice {
        case .apportion:
            updated = ClosureAdjustmentMath.apportion(
                observations: sourceRows,
                start: start,
                end: comparison.overall,
                endAt: endAt
            )
            benchmarkMessage = "途中の点に、時刻の割合で差を振りました。元の座標は残しています。"
        case .resurvey:
            updated = ClosureAdjustmentMath.markResurvey(
                observations: sourceRows,
                start: start,
                endAt: endAt
            )
            benchmarkMessage = "途中の点に要再測の印を付けました。元の座標は残しています。"
        }
        for (before, after) in zip(sourceRows, updated) where before != after {
            try? journal.commit(after)
        }
        observations = FieldObservationLog(observations: journal.recent())
        observationCount = journal.count()
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
        if batterySaver {
            downloadMessage = "電池節約中は、地図の追加保存を止めます。"
            return
        }
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
        names.formUnion(journal.names())
        names.formUnion(journal.bookNames())
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
        guard let project = drawing.project else {
            return CoordinateBookQuery.apply(
                CoordinateBookIndex.collect(
                    book: SiteCoordinateBook.load(from: siteDirectory),
                    observations: observations.observations,
                    known: controlPoints
                ),
                query: bookQuery
            )
        }
        return ProjectStore.filteredCoordinates(
            projectName: project.name,
            at: drawing.projectsRoot,
            query: bookQuery,
            observations: observations.observations,
            known: controlPoints,
            siteBook: SiteCoordinateBook.load(from: siteDirectory)
        )
    }

    func bookPreview() -> CoordinateBookPreview {
        let siteBook = SiteCoordinateBook.load(from: siteDirectory)
        guard let project = drawing.project else {
            let rows = CoordinateBookQuery.apply(
                CoordinateBookIndex.collect(
                    book: siteBook,
                    observations: observations.observations,
                    known: controlPoints
                ),
                query: bookQuery
            )
            return CoordinateBookPreview(count: rows.count, sample: Array(rows.prefix(8)))
        }
        return ProjectStore.coordinateBookPreview(
            projectName: project.name,
            at: drawing.projectsRoot,
            query: bookQuery,
            observations: observations.observations,
            known: controlPoints,
            siteBook: siteBook
        )
    }

    func exportDelivery(_ format: DeliveryFormat) {
        let query = bookQuery
        let zone = drawing.zone
        let projectName = drawing.project?.name
        let root = drawing.projectsRoot
        let site = siteDirectory
        let known = controlPoints
        let journal = journal
        exportMessage = "書き出しています。"
        exportURL = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let observations = journal.allObservations()
            let siteBook = journal.bookEntries()
            let entries: [CoordinateBookEntry]
            if let projectName {
                entries = ProjectStore.filteredCoordinates(
                    projectName: projectName,
                    at: root,
                    query: query,
                    observations: observations,
                    known: known,
                    siteBook: siteBook
                )
            } else {
                entries = CoordinateBookQuery.apply(
                    CoordinateBookIndex.collect(book: siteBook, observations: observations, known: known),
                    query: query
                )
            }
            guard !entries.isEmpty else {
                DispatchQueue.main.async {
                    self.exportMessage = "絞り込みに合う点がありません。"
                    self.exportURL = nil
                }
                return
            }
            let bytes = CoordinateDelivery.data(entries, format: format, zone: zone)
            do {
                let folder = try Self.deliveryFolder(projectName: projectName, root: root, site: site)
                let url = folder.appendingPathComponent(format.filename)
                try bytes.write(to: url, options: .atomic)
                let rawFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("raw", isDirectory: true)
                if let files = try? FileManager.default.contentsOfDirectory(at: rawFolder, includingPropertiesForKeys: nil) {
                    for file in files where ["ubx", "json"].contains(file.pathExtension.lowercased()) {
                        let dest = folder.appendingPathComponent(file.lastPathComponent)
                        try? FileManager.default.removeItem(at: dest)
                        try? FileManager.default.copyItem(at: file, to: dest)
                    }
                }
                DispatchQueue.main.async {
                    self.exportURL = url
                    self.exportMessage = "\(format.label)を \(entries.count) 点、\(format.filename) に書きました。"
                }
            } catch {
                DispatchQueue.main.async {
                    self.exportURL = nil
                    self.exportMessage = "書き出せませんでした。"
                }
            }
        }
    }

    private static func deliveryFolder(projectName: String?, root: URL, site: URL) throws -> URL {
        if let projectName {
            return try ProjectStore.exportDirectory(projectName: projectName, at: root)
        }
        let folder = site.appendingPathComponent("出す", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func bookKind(for work: WorkRequirement) -> String {
        work.id == "boundary" ? "基準点" : work.shortTitle
    }

    /// 仮置きの点。座標簿に同じ名前が無いものだけ。
    func stagedPoints() -> [FieldObservation] {
        let booked = Set(basicPoints().map(\.name))
        return observations.observations.filter { !booked.contains($0.name) }
    }

    /// 検品した仮置きを、人が押したときだけ台帳へ入れる。
    func acceptStaged(_ observation: FieldObservation) {
        let work = workCatalog.works.first { $0.id == observation.workID }
        let kind = observation.workID == "boundary" ? "GCP" : (work?.shortTitle ?? observation.workID)
        remember(CoordinateBookIndex.entry(from: observation, kind: kind))
        captureMessage = "\(observation.name)を台帳に入れました。"
    }

    private func remember(_ entry: CoordinateBookEntry) {
        try? journal.upsertBook(entry)
        if let project = drawing.project {
            try? ProjectStore.saveCoordinate(entry, projectName: project.name, at: drawing.projectsRoot)
        }
        if SurveyBuild.basicMode { basicRevision += 1 }
    }

    private func basicProjectReady() -> Bool {
        guard SurveyBuild.basicMode else { return true }
        guard drawing.project != nil else {
            captureMessage = "先にプロジェクトを作ってください。"
            return false
        }
        return true
    }

    func basicPoints() -> [CoordinateBookEntry] {
        guard let project = drawing.project else { return [] }
        return ProjectStore.coordinateBookEntries(projectName: project.name, at: drawing.projectsRoot)
    }

    func renameBasicPoint(from oldName: String, to rawName: String) {
        guard let project = drawing.project else {
            captureMessage = "先にプロジェクトを作ってください。"
            return
        }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, var entry = basicPoints().first(where: { $0.name == oldName }) else { return }
        guard name != oldName else { return }
        entry.name = name
        do {
            try ProjectStore.deleteCoordinate(name: oldName, projectName: project.name, at: drawing.projectsRoot)
            try ProjectStore.saveCoordinate(entry, projectName: project.name, at: drawing.projectsRoot)
            if basicTarget?.name == oldName { basicTarget = entry }
            basicRevision += 1
            captureMessage = "\(oldName) を \(name) に変えました。"
        } catch {
            captureMessage = "点の名前を変えられませんでした。"
        }
    }

    func aimBasic(name: String, latitude: String, longitude: String, height: String) {
        guard let latitudeDegrees = Double(latitude), let longitudeDegrees = Double(longitude) else {
            captureMessage = "緯度と経度を数にしてください。"
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        basicTarget = CoordinateBookEntry(
            name: trimmed.isEmpty ? "入力" : trimmed,
            latitudeDegrees: latitudeDegrees,
            longitudeDegrees: longitudeDegrees,
            ellipsoidalHeightMeters: Double(height),
            horizontalAccuracyMeters: 0,
            verticalAccuracyMeters: nil,
            satelliteCount: nil,
            fixDurationSeconds: 0,
            recordedAt: Date(),
            kind: "設計"
        )
        captureMessage = "\(basicTarget?.name ?? "入力") へ測設します。"
    }

    func aimBasic(_ entry: CoordinateBookEntry) {
        var horizontal = entry
        horizontal.ellipsoidalHeightMeters = nil
        basicTarget = horizontal
        captureMessage = "\(entry.name) へ測設します。高さは未確認。"
    }

    func importCoordinateFile(data: Data, filename: String) {
        if drawing.project == nil {
            drawing.createProject(named: "座標")
        }
        if drawing.project == nil, let existing = drawing.projects.first {
            drawing.select(existing)
        }
        guard drawing.project != nil else {
            failSheet("先に現場を作ってください。")
            return
        }
        if trustedZone == nil {
            let here = placementSample()
            if let latitude = here.latitude, let longitude = here.longitude,
               let zone = PlaneZoneCatalog.nearestZone(latitude: latitude, longitude: longitude) {
                applyExplicitZone(zone)
            }
        }
        importBasic(data: data, filename: filename)
        if trustedZone == nil {
            coordinateZoneChoices = PlaneZoneLabel.pickerZones()
            bookNote = "系を選んでください。奈良の現場は第VI系です。"
            zoneIsExplicit = false
        }
        focusImportedPoints()
    }

    func chooseCoordinateZone(_ zone: Int) {
        guard (1...19).contains(zone) else { return }
        applyExplicitZone(zone)
        coordinateZoneChoices = []
        let count = basicPoints().count
        let note = count > 0 ? Self.readNote(count: count, zone: zone) : PlaneZoneLabel.button(zone)
        bookNote = note
        exportMessage = note
    }

    private static func readNote(count: Int, zone: Int) -> String {
        let name = zone == 6 ? "第VI系" : "第\(zone)系"
        return "\(count)点を読みました（\(name)）"
    }

    private func applyExplicitZone(_ zone: Int) {
        trustedZone = zone
        zoneIsExplicit = true
        drawing.zone = zone
    }

    func stakeSelectedControlPoint() {
        guard let point = selectedControlPoint else {
            captureMessage = "先に点を選んでください。"
            return
        }
        if let entry = basicPoints().first(where: { $0.name == point.name }) {
            aimBasic(entry)
        } else {
            aimBasic(
                name: point.name,
                latitude: String(point.latitudeDegrees),
                longitude: String(point.longitudeDegrees),
                height: ""
            )
        }
        tab = .map
    }

    private func focusImportedPoints() {
        guard !controlPoints.isEmpty else { return }
        var south = controlPoints.map(\.latitudeDegrees).min() ?? 0
        var north = controlPoints.map(\.latitudeDegrees).max() ?? 0
        var west = controlPoints.map(\.longitudeDegrees).min() ?? 0
        var east = controlPoints.map(\.longitudeDegrees).max() ?? 0
        let padLatitude = max((north - south) * 0.35, 0.0012)
        let padLongitude = max((east - west) * 0.35, 0.0012)
        south -= padLatitude
        north += padLatitude
        west -= padLongitude
        east += padLongitude
        followUser = false
        viewport = MapViewport(
            centerLatitude: (south + north) / 2,
            centerLongitude: (west + east) / 2,
            latitudeDelta: max(north - south, 0.002),
            longitudeDelta: max(east - west, 0.002)
        )
        visibleBounds = GeoBounds(south: south, west: west, north: north, east: east)
        refreshVisibleControlPoints()
        tab = .map
    }

    var basicStakeoutLine: String? {
        basicStakeoutLines.map { "\($0.zone) \($0.name) \($0.distance) \($0.north) \($0.east) \($0.height)" }
    }

    var basicStakeoutLines: StakeoutLines? {
        guard SurveyBuild.basicMode, let target = basicTarget else { return nil }
        guard zoneIsExplicit else {
            return StakeoutLines(
                zone: "系を選んでください",
                name: target.name,
                distance: "奈良の現場は第VI系です。",
                north: "",
                east: "",
                height: "高さは未確認"
            )
        }
        let zone = PlaneZoneLabel.button(drawing.zone)
        guard let position = navigationReading.position, position.isPlottable,
              let guide = BasicStakeout.guide(from: position, to: target, zone: drawing.zone) else {
            return StakeoutLines(zone: zone, name: target.name, distance: "位置を待っています", north: "", east: "", height: "高さは未確認")
        }
        let height = guide.heightMeters.map { String(format: "高さ %+.2f m", $0) } ?? "高さは未確認"
        return StakeoutLines(
            zone: zone,
            name: target.name,
            distance: Self.horizontalText(guide.distanceMeters),
            north: Self.offsetText(guide.northMeters, positive: "北", negative: "南"),
            east: Self.offsetText(guide.eastMeters, positive: "東", negative: "西"),
            height: height
        )
    }

    private static func horizontalText(_ meters: Double) -> String {
        if abs(meters) < 1 {
            return String(format: "%.0f cm", abs(meters) * 100)
        }
        return String(format: "%.2f m", meters)
    }

    private static func offsetText(_ meters: Double, positive: String, negative: String) -> String {
        let word = meters < 0 ? negative : positive
        let magnitude = abs(meters)
        if magnitude < 1 {
            return String(format: "%@ %.0f cm", word, magnitude * 100)
        }
        return String(format: "%@ %.2f m", word, magnitude)
    }

    @discardableResult
    func recordStake() -> Bool {
        if rawCaptureStatus == "記録中" { rawCaptureStatus = "停止" }
        endRawCapture()
        guard basicProjectReady() else { return false }
        guard let target = basicTarget else {
            captureMessage = "先に測設する座標を選んでください。"
            return false
        }
        guard let position = reading.position, position.isPlottable, position.hasValidHorizontalAccuracy else {
            captureMessage = "位置が無いので残せません。"
            return false
        }
        if !PrecisionGate.tiltAllowsStart(degrees: tiltDegrees) {
            captureMessage = "鉛直から 0.5° を超えているので、観測を始めません。"
            return false
        }
        if instrument.complianceEnabled {
            let duration = epochWatch.duration(at: position.timestamp) ?? 0
            if !PrecisionGate.complianceAllowsStart(fix: position.fixQuality == .rtkFix, durationSeconds: duration) {
                captureMessage = "準拠モードは FIX が 10 秒以上のときだけ仮置きできます。"
                return false
            }
        }
        guard let guide = BasicStakeout.guide(from: position, to: target, zone: drawing.zone) else {
            captureMessage = "目標までの距離を出せません。"
            return false
        }
        guard let name = nextPointName else {
            captureMessage = "点名の頭は半角アルファベットだけにしてください。"
            return false
        }
        var condition = ObservationCondition.snapshot(
            position: position,
            stage: stageTransition.stage,
            durationSeconds: epochWatch.duration(at: position.timestamp),
            epochCount: epochWatch.count,
            stature: stature,
            sight: liveSight
        )
        annotate(&condition, position: position)
        let observation = FieldObservation(
            name: name,
            workID: "stakeout",
            captured: position,
            condition: condition
        )
        store(observation)
        let height = guide.heightMeters.map { String(format: "%+.3f", $0) } ?? "—"
        let result = String(
            format: "%@を仮置きしました。ΔX %+.3f ΔY %+.3f ΔH %@",
            name, guide.eastMeters, guide.northMeters, height
        )
        stakeResult = result
        captureMessage = result
        return true
    }

    func compareScale(drawingMeters: Double?, measuredMeters: Double?) {
        guard let drawingMeters, let measuredMeters,
              let result = ScaleCheck.compare(drawingMeters: drawingMeters, measuredMeters: measuredMeters) else {
            scaleMessage = "2つの距離を、0より大きい数で入れてください。"
            return
        }
        let millimetres = result.differenceMeters * 1000
        let ratio = result.ratio > 0 ? Int((1 / result.ratio).rounded()) : 0
        scaleMessage = String(
            format: "%@。差 %+.1f mm。1/%d。",
            result.passed ? "合格" : "不合格",
            millimetres,
            ratio
        )
    }

    func addLocalizeDraft(name: String, designEast: Double?, designNorth: Double?, measuredEast: Double?, measuredNorth: Double?) {
        guard let designEast, let designNorth, let measuredEast, let measuredNorth else {
            localizeMessage = "設計と測定の東西南北を数で入れてください。"
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        localizeDrafts.append(LocalizeDraft(
            name: trimmed.isEmpty ? "点\(localizeDrafts.count + 1)" : trimmed,
            designEast: designEast,
            designNorth: designNorth,
            measuredEast: measuredEast,
            measuredNorth: measuredNorth
        ))
        localizeMessage = "\(localizeDrafts.count)点たまりました。3点以上で合わせます。"
    }

    func runLocalize() {
        guard localizeDrafts.count >= PrecisionGate.minimumKnownPoints else {
            localizeMessage = "既知点が3点に足りません。いま \(localizeDrafts.count) 点。"
            return
        }
        let pairs = localizeDrafts.map {
            (source: PlanarPoint(x: $0.measuredEast, y: $0.measuredNorth), target: PlanarPoint(x: $0.designEast, y: $0.designNorth))
        }
        guard let fit = SiteLocalize.fit(pairs) else {
            localizeMessage = "点が重なっているので、合わせられません。"
            return
        }
        localizeMessage = String(format: "合わせました。残差 %.1f mm。縮尺は1のまま。", fit.rmsMeters * 1000)
    }

    func refreshCadPoints() -> [(name: String, east: Double, north: Double)] {
        guard projectSheet?.kind == "dxf", let data = projectSheetData(),
              let document = try? DrawingImport.load(data, fileName: projectSheet?.fileName ?? "図面.dxf") else {
            cadMessage = "この図面に点名がありません。DXFの文字を使います。"
            return []
        }
        let points: [(name: String, east: Double, north: Double)] = document.entities.compactMap { entity in
            guard case let .text(origin, string, _, _) = entity.primitive else { return nil }
            let name = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let plane = drawing.axis.plane(drawingX: origin.x, drawingY: origin.y)
            return (name, plane.easting, plane.northing)
        }
        cadMessage = points.isEmpty ? "この図面に点名がありません。DXFの文字を使います。" : "\(points.count)点あります。選ぶと測設します。"
        return points
    }

    func aimCadPoint(name: String, east: Double, north: Double) {
        guard let geo = PlaneRectangular.inverse(northingMeters: north, eastingMeters: east, zone: drawing.zone) else {
            cadMessage = "この座標を緯度経度に戻せません。"
            return
        }
        aimBasic(
            name: name,
            latitude: String(geo.latitudeDegrees),
            longitude: String(geo.longitudeDegrees),
            height: ""
        )
        cadMessage = "\(name) へ測設します。"
        tab = .map
    }

    func restoreExportedBook() {
        guard let project = drawing.project else {
            exportMessage = "先に現場を作ってください。"
            return
        }
        if let folder = try? ProjectStore.exportDirectory(projectName: project.name, at: drawing.projectsRoot),
           let file = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter({ ["csv", "sima"].contains($0.pathExtension.lowercased()) })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            .last,
           let data = try? Data(contentsOf: file) {
            importBasic(data: data, filename: file.lastPathComponent)
            return
        }
        guard let url = exportURL, let data = try? Data(contentsOf: url) else {
            exportMessage = "先にデータを書き出してください。"
            return
        }
        if url.pathExtension.lowercased() == "json" {
            restoreBasicBackup(data: data)
        } else {
            importBasic(data: data, filename: url.lastPathComponent)
        }
    }

    private var didLoadUITestDrawing = false

    /// `-uitestDrawing n` のとき、その番号の試験図面を1回だけ読む。
    private func loadUITestDrawingIfRequested() {
        guard !didLoadUITestDrawing else { return }
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-uitestDrawing"),
              args.indices.contains(flag + 1),
              let step = Int(args[flag + 1]) else { return }
        didLoadUITestDrawing = true
        uiTestDrawingStep = step - 1
        tab = .map
        showNextUITestDrawing()
    }

    /// 東京付近の座標を、わざと 1 系で開く試験図面。
    private static let wrongZoneSample = """
    0
    SECTION
    2
    HEADER
    9
    $ACADVER
    1
    AC1021
    9
    $INSUNITS
    70
    6
    0
    ENDSEC
    0
    SECTION
    2
    ENTITIES
    0
    LINE
    8
    図
    10
    -5992.920
    20
    -35363.238
    11
    -5982.920
    21
    -35363.238
    0
    ENDSEC
    0
    EOF
    """

    /// 試験の図面を順に読む。1、2、3、生成した 5、壊れた 6。
    func showNextUITestDrawing() {
        if drawing.project == nil {
            drawing.createProject(named: "図面試験")
        }
        guard drawing.project != nil else {
            uiTestDrawingStatus = drawing.message ?? "現場を作れません"
            return
        }
        uiTestDrawingStep += 1
        let step = uiTestDrawingStep
        let data: Data
        let fileName: String
        let zone: Int?
        let axis: DrawingAxis?
        switch step {
        case 1:
            let sidecar = DrawingSidecar.load(UITestDrawingBytes.irabuMeta)
            data = UITestDrawingBytes.irabu
            fileName = "1_irabu_xvi_utf8.dxf"
            zone = sidecar?.zone
            axis = sidecar?.drawingAxis
        case 2:
            data = UITestDrawingBytes.nagoya
            fileName = "2_nagoya_vii_ac1021_ansi932.dxf"
            zone = 7
            axis = .cadEastNorth
        case 3:
            data = UITestDrawingBytes.millimetres
            fileName = "3_site_local_mm.dxf"
            zone = nil
            axis = nil
        case 4:
            data = Data()
            fileName = "5_heavy_vii_150k_lines.dxf"
            zone = HeavyDrawingFixture.zone
            axis = .cadEastNorth
        case 6:
            data = Data()
            fileName = "empty.dxf"
            zone = nil
            axis = nil
        case 7:
            data = Data(Self.wrongZoneSample.utf8)
            fileName = "wrong-zone.dxf"
            zone = 1
            axis = .cadEastNorth
        case 8, 9, 10, 11, 12, 13:
            data = UITestDrawingBytes.sfig
            fileName = "7_local_origin_mm_sfig.sfc"
            zone = 2
            axis = .cadEastNorth
        default:
            data = UITestDrawingBytes.broken
            fileName = "6_broken.dxf"
            zone = nil
            axis = nil
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let bytes = step == 4 ? HeavyDrawingFixture.makeDXF() : data
            let parsed = Result { try DrawingImport.load(bytes, fileName: fileName) }
            DispatchQueue.main.async {
                self.tab = .map
                switch parsed {
                case let .success(document):
                    var note = self.drawing.installParsed(
                        document,
                        data: bytes,
                        fileName: fileName,
                        zone: zone,
                        axis: axis
                    )
                    if step == 9 || (10...13).contains(step), let survey = try? SFCParser.open(bytes),
                       let fit = SFCPointFit.align(document: survey.document, book: survey.book) {
                        self.drawing.placeAligned(survey.document, transform: fit.transform, zone: 2)
                        note = note.replacingOccurrences(of: "仮置き。", with: "")
                        note += "点名で合わせました。残差 \(String(format: "%.3f", fit.rmsMeters)) m。"
                    }
                    if step == 7 {
                        let warning = ZoneAdvisor.placement(
                            drawingX: -5992.920,
                            drawingY: -35363.238,
                            zone: 1,
                            axis: .cadEastNorth,
                            referenceLatitude: 35.681236,
                            referenceLongitude: 139.767125,
                            referenceName: "現在地"
                        )
                        if let message = warning.message { note += message }
                    }
                    self.uiTestDrawingStatus = note
                    self.frameMapToDrawing()
                    if let zoom = Self.previewZoom(step) {
                        self.applyPreviewZoom(zoom)
                    }
                case let .failure(error):
                    self.uiTestDrawingStatus = (error as? DXFError)?.description ?? "図面を読めませんでした。"
                }
            }
        }
    }

    private static func previewZoom(_ step: Int) -> Int? {
        switch step {
        case 10: return 5
        case 11: return 14
        case 12: return 18
        case 13: return MapTileOverzoom.appMaxZoom
        default: return nil
        }
    }

    private func applyPreviewZoom(_ zoom: Int) {
        let longitude = MapZoom.longitudeDelta(forZoom: zoom, screenWidthPoints: 390)
        var latitude = viewport.centerLatitude
        var centerLongitude = viewport.centerLongitude
        if zoom >= MapTileOverzoom.providerMaxZoom, let corner = drawing.mapPaths.first?.coordinates.first {
            latitude = corner.latitudeDegrees
            centerLongitude = corner.longitudeDegrees
        }
        let cosine = max(0.2, abs(cos(latitude * .pi / 180)))
        let latitudeDelta = longitude * cosine
        followUser = false
        viewport = MapViewport(
            centerLatitude: latitude - latitudeDelta * 0.15,
            centerLongitude: centerLongitude,
            latitudeDelta: latitudeDelta,
            longitudeDelta: longitude
        )
    }

    private func frameMapToDrawing() {
        var south = Double.greatestFiniteMagnitude
        var north = -Double.greatestFiniteMagnitude
        var west = Double.greatestFiniteMagnitude
        var east = -Double.greatestFiniteMagnitude
        var any = false
        for path in drawing.mapPaths {
            for coordinate in path.coordinates {
                any = true
                south = min(south, coordinate.latitudeDegrees)
                north = max(north, coordinate.latitudeDegrees)
                west = min(west, coordinate.longitudeDegrees)
                east = max(east, coordinate.longitudeDegrees)
            }
        }
        guard any else { return }
        followUser = false
        viewport = MapViewport(
            centerLatitude: (south + north) / 2,
            centerLongitude: (west + east) / 2,
            latitudeDelta: max(north - south, 0.002) * 1.8,
            longitudeDelta: max(east - west, 0.002) * 1.8
        )
    }

    func refreshProjectSheet() {
        guard let name = drawing.project?.name else {
            projectSheet = nil
            return
        }
        projectSheet = ProjectStore.loadSheet(projectName: name, at: drawing.projectsRoot)
    }

    func importProjectSheet(data: Data, fileName: String, sidecar: Data? = nil, books: [(Data, String)] = []) {
        guard drawing.project?.name != nil else {
            sheetMessage = "先に現場を作ってください。"
            projectSheet = nil
            return
        }
        let kind = Self.sheetKind(fileName: fileName, data: data)
        guard kind != "unknown" else {
            sheetMessage = "\(fileName) は図面として読めません。PDF、画像、DXF、SFC を選んでください。"
            return
        }
        let meta = (sidecar ?? heldSidecarData).flatMap(DrawingSidecar.load)
        if kind == "dxf" || kind == "sfc" {
            sheetMessage = "図面を読んでいます。"
            DispatchQueue.global(qos: .userInitiated).async {
                let parsed = Result { try DrawingImport.load(data, fileName: fileName) }
                DispatchQueue.main.async {
                    self.finishDrawingSheet(parsed, data: data, fileName: fileName, kind: kind, meta: meta, books: books)
                }
            }
            return
        }
        storeLooseSheet(data: data, fileName: fileName, kind: kind, note: nil)
        importBooks(books)
    }

    func failSheet(_ reason: String) {
        let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        sheetMessage = text.isEmpty ? "図面を読めませんでした。" : text
    }

    func holdSidecar(_ data: Data) {
        heldSidecarData = data
        if let sidecar = DrawingSidecar.load(data), let zone = sidecar.zone {
            trustedZone = zone
            sheetMessage = "\(zone)系（EPSG \(sidecar.epsg)）を覚えました。図面を選んでください。"
        }
    }

    func acceptSheetZone(_ zone: Int) {
        guard let pending = pendingSheet, (1...19).contains(zone) else { return }
        stageForPlacement(pending, zone: zone)
    }

    func placeImportedSheet() {
        guard let pending = pendingSheet, let zone = trustedZone else {
            failSheet("置く図面がありません。先に図面を読んでください。")
            return
        }
        let books = pending.books
        pendingSheet = nil
        canPlaceOnSite = false
        placeDrawing(pending, zone: zone, axis: pending.axis)
        importBooks(books)
        frameMapToSurvey()
    }

    func acceptBookZone(_ zone: Int) {
        guard let pending = pendingBook, (1...19).contains(zone) else { return }
        trustedZone = zone
        bookZoneChoices = []
        pendingBook = nil
        commitPlaneBook(pending.data, filename: pending.filename, zone: zone, adoptZone: true)
    }

    private func finishDrawingSheet(
        _ parsed: Result<DrawingDocument, Error>,
        data: Data,
        fileName: String,
        kind: String,
        meta: DrawingSidecar?,
        books: [(Data, String)]
    ) {
        switch parsed {
        case let .failure(error):
            let reason = (error as? DXFError)?.description
                ?? (error as? SFCError)?.description
                ?? error.localizedDescription
            sheetMessage = "\(fileName) を読めませんでした。\(reason)"
        case let .success(document):
            let here = placementSample()
            let decision = FieldPackPlacement.resolve(
                sidecar: meta,
                x: document.bounds.midX,
                y: document.bounds.midY,
                latitude: here.latitude,
                longitude: here.longitude,
                prefecture: drawing.project?.prefecture
            )
            let axis = decision.axis ?? .cadEastNorth
            if meta == nil, kind == "dxf" {
                pendingSheet = PendingDrawingSheet(
                    data: data,
                    fileName: fileName,
                    document: document,
                    kind: kind,
                    axis: axis,
                    books: books
                )
                sheetZoneChoices = PlaneZoneLabel.pickerZones()
                canPlaceOnSite = false
                sheetMessage = "meta.json が読めません。系を選んでください。奈良の現場は第VI系です。"
                return
            }
            guard let zone = decision.zone else {
                pendingSheet = PendingDrawingSheet(
                    data: data,
                    fileName: fileName,
                    document: document,
                    kind: kind,
                    axis: axis,
                    books: books
                )
                sheetZoneChoices = decision.choices
                sheetMessage = "系を選んでください。"
                return
            }
            trustedZone = zone
            stageForPlacement(
                PendingDrawingSheet(data: data, fileName: fileName, document: document, kind: kind, axis: axis, books: books),
                zone: zone
            )
        }
    }

    private func stageForPlacement(_ pending: PendingDrawingSheet, zone: Int) {
        pendingSheet = pending
        applyExplicitZone(zone)
        canPlaceOnSite = true
        sheetZoneChoices = []
        if let name = drawing.project?.name,
           let record = try? ProjectStore.saveSheet(
            data: pending.data,
            fileName: pending.fileName,
            kind: pending.kind,
            projectName: name,
            at: drawing.projectsRoot
           ) {
            projectSheet = record
        }
        let zoneName = zone == 6 ? "第VI系" : "第\(zone)系"
        sheetMessage = "\(pending.fileName) を読みました。\(zoneName)（EPSG \(6668 + zone)）。現場へ置くと地図に出します。"
    }

    private func placeDrawing(_ pending: PendingDrawingSheet, zone: Int, axis: DrawingAxis) {
        let epsg = 6668 + zone
        var note = drawing.installParsed(
            pending.document,
            data: pending.data,
            fileName: pending.fileName,
            zone: zone,
            axis: axis
        )
        let names = SiteDXF.controlNames(in: pending.document)
        let axisLabel = axis == .surveyNorthEast ? "X北 Y東" : "X東 Y北"
        note += "\(zone)系（EPSG \(epsg)）。\(axisLabel)。"
        if pending.kind == "dxf", !names.isEmpty {
            let bad = SiteDXF.mismatches(drawing: names, ledger: basicPoints().map(\.name))
            note += bad.isEmpty ? "測設_基準点は台帳と一致。" : "台帳と違う: \(bad.joined(separator: " "))。"
        }
        if let record = ProjectStore.loadSheet(projectName: drawing.project?.name ?? "", at: drawing.projectsRoot) {
            projectSheet = record
        }
        if let name = drawing.project?.name,
           let record = try? ProjectStore.saveSheet(
            data: pending.data,
            fileName: pending.fileName,
            kind: pending.kind,
            projectName: name,
            at: drawing.projectsRoot
           ) {
            projectSheet = record
        }
        sheetMessage = note
        sheetZoneChoices = []
        if drawing.mapPaths.isEmpty {
            sheetMessage = note + "地図には出ていません。"
            return
        }
        frameMapToDrawing()
        tab = .map
    }

    private func storeLooseSheet(data: Data, fileName: String, kind: String, note extra: String?) {
        guard let name = drawing.project?.name else { return }
        do {
            let record = try ProjectStore.saveSheet(
                data: data,
                fileName: fileName,
                kind: kind,
                projectName: name,
                at: drawing.projectsRoot
            )
            projectSheet = record
            var note = "済。\(record.fileName)。\(record.byteCount) バイト。"
            if let extra { note += extra }
            sheetMessage = note
        } catch {
            sheetMessage = "図面を置けませんでした。"
        }
    }

    private func importBooks(_ books: [(Data, String)]) {
        for book in books {
            importBasic(data: book.0, filename: book.1)
        }
    }

    private func commitPlaneBook(_ data: Data, filename: String, zone: Int, adoptZone: Bool) {
        guard let project = drawing.project else { return }
        let entries = CoordinateExchange.parse(data: data, filename: filename, zone: zone)
        guard !entries.isEmpty else {
            exportMessage = "読める点がありません。"
            bookNote = exportMessage
            return
        }
        do {
            try ProjectStore.saveCoordinates(entries, projectName: project.name, at: drawing.projectsRoot)
            if adoptZone {
                applyExplicitZone(zone)
            }
            basicRevision += 1
            showSurveyMarks(entries)
            let total = basicPoints().count
            let note = adoptZone ? Self.readNote(count: total, zone: zone) : "\(total)点を読みました"
            exportMessage = note
            bookNote = note
        } catch {
            exportMessage = "読み込めませんでした。"
            bookNote = exportMessage
        }
    }

    private func showSurveyMarks(_ entries: [CoordinateBookEntry]) {
        var merged = controlPoints
        for entry in entries {
            let mark = ControlPoint(
                id: entry.name,
                name: entry.name,
                kind: entry.kind ?? "測点",
                latitudeDegrees: entry.latitudeDegrees,
                longitudeDegrees: entry.longitudeDegrees,
                heightMeters: nil,
                ellipsoidalHeightMeters: nil,
                heightKind: .orthometric,
                sourceNote: entry.source ?? ""
            )
            if let index = merged.firstIndex(where: { $0.id == mark.id }) {
                merged[index] = mark
            } else {
                merged.append(mark)
            }
        }
        controlPoints = merged
        refreshVisibleControlPoints()
    }

    private func frameMapToSurvey() {
        frameMapToDrawing()
        guard !controlPoints.isEmpty else { return }
        var south = viewport.centerLatitude - viewport.latitudeDelta / 2
        var north = viewport.centerLatitude + viewport.latitudeDelta / 2
        var west = viewport.centerLongitude - viewport.longitudeDelta / 2
        var east = viewport.centerLongitude + viewport.longitudeDelta / 2
        for point in controlPoints {
            south = min(south, point.latitudeDegrees)
            north = max(north, point.latitudeDegrees)
            west = min(west, point.longitudeDegrees)
            east = max(east, point.longitudeDegrees)
        }
        let padLatitude = max((north - south) * 0.2, 0.0008)
        let padLongitude = max((east - west) * 0.2, 0.0008)
        south -= padLatitude
        north += padLatitude
        west -= padLongitude
        east += padLongitude
        followUser = false
        viewport = MapViewport(
            centerLatitude: (south + north) / 2,
            centerLongitude: (west + east) / 2,
            latitudeDelta: max(north - south, 0.001),
            longitudeDelta: max(east - west, 0.001)
        )
        visibleBounds = GeoBounds(south: south, west: west, north: north, east: east)
        refreshVisibleControlPoints()
    }

    private func adoptControlCatalog(_ points: [ControlPoint], data: Data) {
        guard let project = drawing.project else { return }
        controlPoints = points
        try? data.write(to: siteDirectory.appendingPathComponent("control-points.csv"), options: .atomic)
        refreshVisibleControlPoints()
        let entries = points.map { point in
            CoordinateBookEntry(
                name: point.name,
                latitudeDegrees: point.latitudeDegrees,
                longitudeDegrees: point.longitudeDegrees,
                ellipsoidalHeightMeters: point.comparableEllipsoidalHeightMeters,
                horizontalAccuracyMeters: 0,
                verticalAccuracyMeters: nil,
                satelliteCount: nil,
                fixDurationSeconds: 0,
                recordedAt: Date(),
                kind: point.kind,
                source: "基準点"
            )
        }
        do {
            try ProjectStore.saveCoordinates(entries, projectName: project.name, at: drawing.projectsRoot)
            basicRevision += 1
            showSurveyMarks(entries)
            let total = basicPoints().count
            let note = trustedZone.map { Self.readNote(count: total, zone: $0) } ?? "\(total)点を読みました"
            exportMessage = note
            bookNote = note
        } catch {
            exportMessage = "読み込めませんでした。"
            bookNote = exportMessage
        }
    }

    private func placementSample() -> (latitude: Double?, longitude: Double?) {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> Double? {
            guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
            return Double(args[index + 1])
        }
        if let latitude = value("-uitestLatitude"), let longitude = value("-uitestLongitude") {
            return (latitude, longitude)
        }
        let position = navigationReading.position ?? reading.position
        if let position, position.isPlottable {
            return (position.latitudeDegrees, position.longitudeDegrees)
        }
        return (nil, nil)
    }

    private func loadVIPackIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-uitestField"),
              args.indices.contains(flag + 1) else { return }
        let mode = args[flag + 1]
        guard mode == "vi" || mode == "vi-fail" || mode == "vi-nomet" else { return }
        if drawing.project == nil {
            drawing.createProject(named: "六系")
        }
        if mode == "vi-fail" {
            importProjectSheet(data: Data("not-a-dxf".utf8), fileName: "broken.dxf")
            return
        }
        if mode == "vi-nomet" {
            importProjectSheet(data: VIPack.dxf, fileName: VIPack.dxfFileName)
            return
        }
        // 試験は、伊良部の 16 系が残った状態から始める。meta の 6674 が上書きする。
        drawing.zone = 16
        importProjectSheet(
            data: VIPack.dxf,
            fileName: VIPack.dxfFileName,
            sidecar: VIPack.meta,
            books: [(VIPack.csv, "control-points.csv"), (VIPack.sima, "points.sima")]
        )
    }

    func refreshInstrument() {
        guard let name = drawing.project?.name else { return }
        instrument = ProjectStore.loadInstrument(projectName: name, at: drawing.projectsRoot)
    }

    func saveInstrument() {
        guard let name = drawing.project?.name else {
            instrumentMessage = "先に現場を作ってください。"
            return
        }
        let missingKBM = instrument.kbmSource.isEmpty || instrument.kbmVersion.isEmpty || instrument.kbmDate.isEmpty
        if instrument.kbmH != nil, missingKBM {
            instrumentMessage = "H の出典、版、日付を入れてください。"
            return
        }
        if instrument.cameraKind == "spcPlus" {
            instrument.cameraX = CameraOffset.spcPlus15ProMax.x
            instrument.cameraY = CameraOffset.spcPlus15ProMax.y
            instrument.cameraZ = CameraOffset.spcPlus15ProMax.z
        }
        do {
            try ProjectStore.saveInstrument(instrument, projectName: name, at: drawing.projectsRoot)
            let kbm = KBMCorrection.accepted(
                first: instrument.kbmFirstN,
                firstAt: instrument.kbmFirstAt,
                second: instrument.kbmSecondN,
                secondAt: instrument.kbmSecondAt
            )
            let firmware = receiverFirmware ?? rtkSession?.firmwareVersion ?? "未取得"
            let height = instrument.antennaToGroundMeters.map { String(format: "%.3f m", $0) } ?? "—"
            instrumentMessage = "残しました。カメラ \(CameraOffset.displayName(instrument.cameraKind)) \(instrument.antennaMethodLabel) \(height)。ファームウェア \(firmware)。"
        } catch {
            instrumentMessage = "設定を置けませんでした。"
        }
    }

    func noteTilt(_ degrees: Double, fromDevice: Bool) {
        guard degrees.isFinite else { return }
        if fromDevice, !deviceTiltLive {
            deviceTiltLive = true
            tiltWindow.removeAll(keepingCapacity: true)
        }
        if !fromDevice, deviceTiltLive { return }
        let now = Date().timeIntervalSinceReferenceDate
        tiltWindow.append((now, degrees))
        tiltWindow.removeAll { now - $0.0 > 15 }
        guard let stats = TiltMath.stats(tiltWindow.map(\.1)) else { return }
        tiltDegrees = stats.median
        tiltMeanDegrees = stats.mean
        tiltMaxDegrees = stats.maximum
    }

    func setRawCapture(_ on: Bool) {
        rawCaptureEnabled = on
        UserDefaults.standard.set(on, forKey: rawCaptureKey)
        if !on { endRawCapture() }
    }

    func endRawCapture() {
        #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth) && canImport(Network)
        rtkSession?.endRawCapture()
        #endif
    }

    private func startRawCapture(_ observation: FieldObservation) {
        #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth) && canImport(Network)
        guard rawCaptureStatus != "記録中" else { return }
        let started = observation.captured.timestamp
        let name = RawObsFile.baseName(point: observation.name, started: started)
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("raw", isDirectory: true)
        let base = folder.appendingPathComponent(name)
        let formatter = ISO8601DateFormatter()
        let sidecar = RawObsSidecar(
            pointName: observation.name,
            fileName: name + ".ubx",
            startedAt: formatter.string(from: started),
            solution: observation.captured.solutionLabel,
            pdop: observation.captured.pdop,
            hdop: observation.captured.hdop,
            vdop: observation.captured.vdop,
            tiltMedianDegrees: observation.condition?.tiltMedianDegrees,
            tiltMeanDegrees: observation.condition?.tiltMeanDegrees,
            tiltMaxDegrees: observation.condition?.tiltMaxDegrees,
            latitudeDegrees: observation.captured.latitudeDegrees,
            longitudeDegrees: observation.captured.longitudeDegrees,
            restoreNote: nil
        )
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(sidecar) {
            try? data.write(to: base.appendingPathExtension("json"), options: .atomic)
        }
        rawObservationID = observation.id
        var stored = observation
        stored.condition?.rawFileName = name + ".ubx"
        observations = observations.replacing(stored)
        try? journal.commit(stored)
        rawCaptureStatus = "記録中"
        rtkSession?.beginRawCapture(at: base)
        #endif
    }

    private func noteRawRestore(unverified: Bool) {
        guard let id = rawObservationID,
              var stored = observations.observations.first(where: { $0.id == id }) else { return }
        if unverified {
            stored.condition?.rawRestoreNote = RawObsFile.restoreUnverified
        }
        observations = observations.replacing(stored)
        try? journal.commit(stored)
        if let file = stored.condition?.rawFileName {
            let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("raw", isDirectory: true)
                .appendingPathComponent(file.replacingOccurrences(of: ".ubx", with: ""))
            if var sidecar = try? JSONDecoder().decode(RawObsSidecar.self, from: Data(contentsOf: base.appendingPathExtension("json"))) {
                sidecar.restoreNote = unverified ? RawObsFile.restoreUnverified : nil
                if let data = try? JSONEncoder().encode(sidecar) {
                    try? data.write(to: base.appendingPathExtension("json"), options: .atomic)
                }
            }
        }
        rawObservationID = nil
    }

    func togglePPK() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let base = ppkBase {
            PPKLog.finish(base: base, observationIDs: [])
            ppkShare = base.appendingPathExtension("json")
            ppkBase = nil
            ppkStatus = "停止"
            rtkSession?.setPPKBase(nil)
            return
        }
        guard let base = try? PPKLog.begin(
            deviceName: "ViDoc",
            antennaHeightMeters: instrument.antennaToGroundMeters,
            in: documents
        ) else {
            ppkStatus = "記録を始められません"
            return
        }
        ppkBase = base
        ppkStatus = "記録中"
        ppkShare = nil
        rtkSession?.setPPKBase(base)
    }

    func lightFrontLaser() {
        #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth) && canImport(Network)
        rtkSession?.lightFrontLaser()
        #endif
    }

    func measureFrontLaser() {
        #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth) && canImport(Network)
        rtkSession?.measureFrontLaser()
        #endif
    }

    func lightLowerLaser() {
        #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth) && canImport(Network)
        rtkSession?.lightLowerLaser()
        #else
        instrumentMessage = "受信機が無いので点灯できません。"
        #endif
    }

    func measureLowerLaser() {
        #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth) && canImport(Network)
        rtkSession?.measureLowerLaser()
        #else
        instrumentMessage = "受信機が無いので測れません。"
        #endif
    }

    private func annotate(_ condition: inout ObservationCondition, position: GeodeticPosition) {
        #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth) && canImport(Network)
        condition.firmware = receiverFirmware ?? rtkSession?.firmwareVersion
        #else
        condition.firmware = receiverFirmware
        #endif
        condition.antennaMethod = instrument.antennaMethodLabel
        if let height = position.ellipsoidalHeightMeters {
            condition.groundHeightMeters = instrument.groundMarkMeters(ellipsoidal: height)
        }
        condition.hdop = position.hdop
        condition.vdop = position.vdop
        condition.tiltMedianDegrees = tiltDegrees
        condition.tiltMeanDegrees = tiltMeanDegrees
        condition.tiltMaxDegrees = tiltMaxDegrees
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let record = IMUCalibrationStore.latest(hardwareID: DeviceIdentity.machine, bleName: "ViDoc", in: documents) {
            condition.calibrationUsedAt = record.recordedAt
        }
    }

    func recordKBMSample(ellipsoidal: Double) {
        guard let h = instrument.kbmH else {
            instrumentMessage = "成果の高さ H を入れてください。"
            return
        }
        let sample = KBMCorrection.n(ellipsoidal: ellipsoidal, orthometric: h)
        let now = Date()
        if instrument.kbmFirstAt == nil {
            instrument.kbmFirstN = sample
            instrument.kbmFirstAt = now
            instrumentMessage = "\(KBMCorrection.title) 1回目 N \(String(format: "%+.3f", sample)) m。"
        } else if instrument.kbmFirstAt != now {
            instrument.kbmSecondN = sample
            instrument.kbmSecondAt = now
            let ok = KBMCorrection.accepted(
                first: instrument.kbmFirstN,
                firstAt: instrument.kbmFirstAt,
                second: instrument.kbmSecondN,
                secondAt: instrument.kbmSecondAt
            )
            instrumentMessage = ok
                ? "\(KBMCorrection.title) 2回の差は 2cm 以内。KBM は点検点にしません。"
                : "\(KBMCorrection.title) 2回の差が 2cm を超えています。"
        }
    }

    func projectSheetData() -> Data? {
        guard let name = drawing.project?.name else { return nil }
        return ProjectStore.sheetData(projectName: name, at: drawing.projectsRoot)
    }

    private static func sheetKind(fileName: String, data: Data) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if ext == "pdf" || data.starts(with: Data("%PDF".utf8)) { return "pdf" }
        if ext == "dxf" { return "dxf" }
        if ext == "sfc" { return "sfc" }
        if ["png", "jpg", "jpeg", "heic", "gif", "webp", "tif", "tiff"].contains(ext) { return "image" }
        return "unknown"
    }

    func exportBasic(_ format: DeliveryFormat) {
        guard let project = drawing.project else {
            exportMessage = "先にプロジェクトを作ってください。"
            exportURL = nil
            return
        }
        let entries = ProjectStore.coordinateBookEntries(projectName: project.name, at: drawing.projectsRoot)
        guard !entries.isEmpty else {
            exportMessage = "座標簿に点がありません。"
            exportURL = nil
            return
        }
        let bytes = CoordinateDelivery.data(entries, format: format, zone: drawing.zone)
        do {
            let folder = try Self.deliveryFolder(projectName: project.name, root: drawing.projectsRoot, site: siteDirectory)
            let url = folder.appendingPathComponent(format.filename)
            try bytes.write(to: url, options: .atomic)
            exportURL = url
            exportMessage = "\(format.label)を書きました。"
        } catch {
            exportURL = nil
            exportMessage = "書き出せませんでした。"
        }
    }

    func importBasic(data: Data, filename: String) {
        guard drawing.project != nil else {
            exportMessage = "先にプロジェクトを作ってください。"
            bookNote = exportMessage
            return
        }
        if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS),
           text.contains("latitude_deg"),
           let points = try? ControlPointCatalog.loadCSV(text),
           !points.isEmpty {
            adoptControlCatalog(points, data: data)
            return
        }
        guard let sample = CoordinateExchange.firstPlane(data: data, filename: filename) else {
            commitPlaneBook(data, filename: filename, zone: trustedZone ?? drawing.zone, adoptZone: false)
            return
        }
        if let trustedZone {
            commitPlaneBook(data, filename: filename, zone: trustedZone, adoptZone: true)
            return
        }
        let here = placementSample()
        let decision = FieldPackPlacement.zoneForPlane(
            northing: sample.northing,
            easting: sample.easting,
            latitude: here.latitude,
            longitude: here.longitude,
            trustedZone: trustedZone
        )
        guard let zone = decision.zone else {
            pendingBook = (data, filename)
            bookZoneChoices = decision.choices
            bookNote = "系を選んでください。"
            exportMessage = bookNote
            return
        }
        commitPlaneBook(data, filename: filename, zone: zone, adoptZone: true)
    }

    func makeBasicBackup() {
        let backup = BasicBackup.capture(at: drawing.projectsRoot)
        guard let data = backup.data() else {
            exportMessage = "バックアップを作れませんでした。"
            return
        }
        let url = siteDirectory.appendingPathComponent("バックアップ.json")
        do {
            try data.write(to: url, options: .atomic)
            exportURL = url
            exportMessage = "バックアップを作りました。ファイルに保存すると、入れ直したあとも戻せます。"
        } catch {
            exportMessage = "バックアップを書けませんでした。"
        }
    }

    func restoreBasicBackup(data: Data) {
        guard let backup = BasicBackup.load(data) else {
            exportMessage = "バックアップを読めませんでした。"
            return
        }
        do {
            let count = try backup.restore(at: drawing.projectsRoot)
            drawing.reload()
            if let current = backup.projects.last?.project,
               let match = drawing.projects.first(where: { $0.name == current.name }) {
                drawing.select(match)
            }
            basicRevision += 1
            exportMessage = "\(count)点を戻しました。"
        } catch {
            exportMessage = "戻せませんでした。"
        }
    }

    private func store(_ observation: FieldObservation) {
        observations = observations.appending(observation)
        if observations.observations.count > FieldJournal.recentLimit {
            observations = FieldObservationLog(observations: Array(observations.observations.suffix(FieldJournal.recentLimit)))
        }
        try? journal.commit(observation)
        observationCount = journal.count()
        rememberSession()
    }

    private func rememberSession() {
        try? journal.save(FieldSession(
            tab: tab.rawValue,
            projectName: drawing.project?.name,
            workID: workCatalog.selected.id,
            fixBeganAt: controlFix.fixBeganAt,
            fixEpochCount: controlFix.epochCount,
            fixRestarted: controlFix.restarted,
            fixPosition: controlFix.latest
        ))
    }

    private func persistFix(force: Bool) {
        let now = Date()
        if !force, now.timeIntervalSince(lastFixSave) < 1 { return }
        lastFixSave = now
        rememberSession()
    }

    func resumeGNSS() {
        #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth) && canImport(Network)
        if showsRTK || rtkSession?.mode == .rtk { return }
        #endif
        gnss.resume()
    }

    #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth) && canImport(Network)
    func openRTK() {
        pauseGNSS()
        showsRTK = true
    }
    #endif

    func pauseGNSS() {
        gnss.pause()
    }

    func scanGNSS() {
        #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth) && canImport(Network)
        if rtkSession?.mode == .rtk { return }
        #endif
        gnssChoices = []
        gnss.scan()
    }

    func chooseGNSS(_ id: String) {
        #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth) && canImport(Network)
        if rtkSession?.mode == .rtk { return }
        #endif
        gnss.choose(id)
    }

    private func apply(_ reading: PositionReading) {
        pendingReading = reading
        readingUI.submit { [weak self] in
            guard let self, let reading = self.pendingReading else { return }
            self.commit(reading)
        }
    }

    /// 画面へ出す位置は秒10回まで。方位のたびに全体を描き直すと、タップが届かなくなる。
    private func commit(_ reading: PositionReading) {
        self.reading = reading
        if let position = reading.position {
            let wasRecording = controlFix.canRecord
            let transition = StageLadder.step(held: stageTransition.stage, reported: position)
            stageTransition = transition
            epochWatch.observe(position)
            let began = controlFix.fixBeganAt
            let wasRestarted = controlFix.restarted
            controlFix.observe(position, at: position.timestamp)
            if wasRecording && !StageGate.allowsRecording(workID: "boundary", stage: transition.stage) {
                if controlFix.canRecord {
                    controlFix.abort()
                }
                captureMessage = Self.stageDroppedRecording
            }
            captureMessage = StageDropNotice.resolve(
                current: captureMessage,
                stage: transition.stage,
                quality: position.fixQuality
            )
            persistFix(force: controlFix.fixBeganAt != began || controlFix.restarted != wasRestarted)
        }
        updateWalk()
        if let position = navigationReading.position, position.isPlottable {
            drawing.noteReference(
                latitude: position.latitudeDegrees,
                longitude: position.longitudeDegrees,
                name: "現在地"
            )
        }
        applyShareGate()
        radio.rename(crew.displayName)
        radio.refreshSpace()
        refreshSOS()
        noteDisasterMotion()
        if extras.firstResponse, firstDesk.episode?.active == true {
            publishFirst(speak: false)
        } else if extras.firstResponse {
            refreshAidArrows()
        }
        trackIncidents()
        refreshVisibleControlPoints()
        guard followUser, let position = navigationReading.position, position.isPlottable else { return }
        viewport = camera.update(for: position)
    }

    func applyShareGate(now: Date = Date()) {
        let position = navigationReading.position
        let plottable = position?.isPlottable == true
        let state = extras.sharesLocation
            ? LocationPrivacy.gate(
                hasFix: plottable,
                latitude: position?.latitudeDegrees ?? 0,
                longitude: position?.longitudeDegrees ?? 0,
                at: now,
                fence: drawing.project?.siteFence,
                hours: drawing.project?.workHours,
                paused: sharePaused
            )
            : ShareState.unset
        locationShare = state
        if extras.usesNearby || state.shares {
            crew.note(
                position: position,
                project: drawing.project,
                radius: drawing.machineRadiusMeters,
                root: drawing.projectsRoot,
                broadcast: state.shares,
                alert: extras.proximity,
                listen: extras.usesNearby,
                now: now
            )
        } else {
            crew.standDown()
        }
        shareViewers = LocationPrivacy.viewers(
            sharing: state.shares,
            peers: crew.peers.map { ShareViewer(id: $0.id, name: $0.name, role: $0.role.label) }
        )
    }

    func setSharePaused(_ paused: Bool) {
        sharePaused = paused
        applyShareGate()
    }

    func placeFence(radiusMeters: Double) {
        guard drawing.project != nil else {
            privacyMessage = "先にプロジェクトを作ってください。"
            return
        }
        guard let position = workingReading.position, position.isPlottable else {
            privacyMessage = "現在地がまだ無いので、中心を置けません。"
            return
        }
        let radius = LocationPrivacy.radiusMeters(radiusMeters)
        drawing.setSiteFence(SiteFence(
            latitudeDegrees: position.latitudeDegrees,
            longitudeDegrees: position.longitudeDegrees,
            radiusMeters: radius
        ))
        privacyMessage = "現場の中心を現在地にしました。半径\(Int(radius))m。"
        applyShareGate()
    }

    func updateFenceRadius(_ meters: Double) {
        guard var fence = drawing.project?.siteFence else {
            privacyMessage = "先に現在地を現場の中心にしてください。"
            return
        }
        fence.radiusMeters = LocationPrivacy.radiusMeters(meters)
        drawing.setSiteFence(fence)
        privacyMessage = "半径を\(Int(fence.radiusMeters))mにしました。"
        applyShareGate()
    }

    func saveWorkHours(start: Int, end: Int) {
        guard drawing.project != nil else {
            privacyMessage = "先にプロジェクトを作ってください。"
            return
        }
        guard start >= 0, end <= 24, start < end else {
            privacyMessage = "作業時間は、同じ日の中で開始より終了を遅くしてください。"
            return
        }
        drawing.setWorkHours(WorkHours(startHour: start, endHour: end))
        privacyMessage = "作業時間を\(start)時から\(end)時までにしました。"
        applyShareGate()
    }

    private func trackIncidents(now: Date = Date()) {
        guard extras.recordsIncidents else { return }
        guard let project = drawing.project else { return }
        if restoredIncidentProject != project.name {
            restoredIncidentProject = project.name
            incidents.restore(projectName: project.name, at: drawing.projectsRoot)
        }
        var batch: [IncidentSample] = []
        if let position = navigationReading.position, position.isPlottable {
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
        sosRelay.isReachable = radio.relayReachable
        sosRelay.flush()
        aidRelay.isReachable = radio.relayReachable
        aidRelay.flush()
        flushDisasterSync()
        readMeshBattery()
        relayDisasterHeld(now: now)
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
            sealedIncidents = []
            return
        }
        incidentStatRows = IncidentStats.load(project: project, at: drawing.projectsRoot, anonymize: anonymizeStats)
        incidentHeat = IncidentStats.heat(incidentStatRows)
        sealedIncidents = IncidentBook.sealed(projectName: project.name, at: drawing.projectsRoot)
            .sorted { $0.occurredAt > $1.occurredAt }
            .prefix(8)
            .map { record in
                SealedIncidentRow(
                    id: record.id,
                    title: "\(AccidentReport.clock(record.occurredAt)) \(record.trigger.label) \(record.work.kind)"
                )
            }
    }

    func exportAccidentReport(_ id: UUID, names: AccidentNames) {
        guard let project = drawing.project else {
            statMessage = "先にプロジェクトを作ってください。"
            return
        }
        do {
            let result = try AccidentBook.export(
                incidentID: id,
                projectName: project.name,
                at: drawing.projectsRoot,
                names: names,
                generatedAt: Date()
            )
            statMessage = "対外説明を書きました。照合は\(result.status)です。\(result.fileName)"
        } catch {
            statMessage = "対外説明を書けませんでした。"
        }
    }

    func noteAmbulance(_ id: UUID) {
        guard let project = drawing.project else {
            statMessage = "先にプロジェクトを作ってください。"
            return
        }
        let stamp = AidStamp(at: Date(), text: "救急到着")
        if incidents.open[id] != nil {
            do {
                try incidents.noteAid(stamp, incidentID: id, projectName: project.name, at: drawing.projectsRoot)
                incidentNote = "救急到着を記録しました"
            } catch {
                incidentNote = "確定した記録には足せません。"
            }
            return
        }
        do {
            _ = try AccidentBook.append(text: "救急到着", at: Date(), incidentID: id, projectName: project.name, root: drawing.projectsRoot)
            statMessage = "救急到着を追記しました。記録.jsonは変えていません。"
        } catch {
            statMessage = "救急到着を追記できませんでした。"
        }
    }

    private var siteAddress: String? {
        let raw = drawing.project?.siteAid?.address.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
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

    private static var posix: Locale { Locale(identifier: "en_US_POSIX") }

    private static func meters(_ value: Double) -> String {
        String(format: "%.2fm", locale: posix, value)
    }

    private var headingNow: Double? {
        if let heading = reading.position?.headingDegrees, heading.isFinite { return heading }
        if let course = reading.position?.courseDegrees, course.isFinite { return course }
        return nil
    }

    private func ingestSteps(_ slot: PaceSlot, _ total: Int) {
        switch slot {
        case .calibration:
            calibrationSteps = total
        case .measure:
            measureSteps = total
            measureBridge?.add(totalSteps: total, headingDegrees: headingNow)
            refreshPace()
        case .bridge:
            bridgeSteps = max(bridgeSteps, total)
            deadReckon?.add(totalSteps: bridgeSteps, headingDegrees: headingNow)
            refreshBridge()
        }
    }

    private func updateWalk() {
        guard StepHardware.available else {
            if walkMode == .bridge { finishBridge(restored: false) }
            return
        }
        let desired = PaceMath.nextMode(current: walkMode, accuracyMeters: reading.position?.horizontalAccuracyMeters)
        if desired == .bridge {
            guard pace.strideMeters != nil else {
                if walkMode == .bridge { finishBridge(restored: false) }
                return
            }
            if walkMode != .bridge {
                guard startBridge() else { return }
            }
            deadReckon?.add(totalSteps: bridgeSteps, headingDegrees: headingNow)
            refreshBridge()
        } else if walkMode == .bridge {
            finishBridge(restored: true)
        }
    }

    @discardableResult
    private func startBridge() -> Bool {
        guard let stride = pace.strideMeters,
              let position = workingReading.position,
              position.isPlottable else { return false }
        walkMode = .bridge
        bridgeNotice = nil
        bridgeSteps = 0
        bridgeSeenX = nil
        bridgeSeenZ = nil
        deadReckon = WalkBridge(
            originLatitude: position.latitudeDegrees,
            originLongitude: position.longitudeDegrees,
            strideMeters: stride,
            slope: pace.slope,
            factorOverride: pace.factorOverride
        )
        paceSession.watch(.bridge, from: Date())
        holdPaceVision()
        refreshBridge()
        return true
    }

    private func finishBridge(restored: Bool) {
        walkMode = .gnss
        deadReckon = nil
        bridgeFix = nil
        bridgeSteps = 0
        bridgeSeenX = nil
        bridgeSeenZ = nil
        bridgeNotice = restored ? "GNSSに戻りました。" : nil
        paceSession.unwatch(.bridge)
        releasePaceVisionIfIdle()
    }

    private func refreshPace() {
        paceFix = measureBridge?.place()
    }

    private func refreshBridge() {
        guard walkMode == .bridge else { return }
        bridgeFix = deadReckon?.place()
    }

    private func holdPaceVision() {
        guard !paceVisionOn else { return }
        paceVisionOn = true
        SurveyVision.shared.add(paceVision) { [weak self] frame in
            self?.notePaceVision(frame)
        }
    }

    private func releasePaceVisionIfIdle() {
        guard !pacing, walkMode != .bridge, paceVisionOn else { return }
        paceVisionOn = false
        SurveyVision.shared.remove(paceVision)
        paceYaw = nil
        measureSeenX = nil
        measureSeenZ = nil
        bridgeSeenX = nil
        bridgeSeenZ = nil
    }

    private func notePaceVision(_ frame: VisionFrame) {
        guard frame.quality != .lost else { return }
        if paceYaw == nil {
            guard let heading = headingNow,
                  let forward = PaceMath.forwardFromPlusZ(x: frame.forwardX, z: frame.forwardZ),
                  let yaw = PaceMath.yawOfPlusZ(headingDegrees: heading, forwardFromPlusZDegrees: forward) else { return }
            paceYaw = yaw
        }
        guard let yaw = paceYaw else { return }
        if pacing, var track = measureBridge {
            if measureSeenX == nil {
                measureSeenX = frame.x
                measureSeenZ = frame.z
            }
            if let originX = measureSeenX, let originZ = measureSeenZ,
               let moved = PaceMath.horizontal(dx: frame.x - originX, dz: frame.z - originZ, yawDegrees: yaw) {
                track.setVisual(east: moved.east, north: moved.north)
                measureBridge = track
                refreshPace()
            }
        }
        if walkMode == .bridge, var track = deadReckon {
            if bridgeSeenX == nil {
                bridgeSeenX = frame.x
                bridgeSeenZ = frame.z
            }
            if let originX = bridgeSeenX, let originZ = bridgeSeenZ,
               let moved = PaceMath.horizontal(dx: frame.x - originX, dz: frame.z - originZ, yawDegrees: yaw) {
                track.setVisual(east: moved.east, north: moved.north)
                deadReckon = track
                refreshBridge()
            }
        }
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

/// センサの表示更新を秒10回に揃える。連続した値は最後の一つを残す。
private final class UIThrottle {
    private let interval: TimeInterval
    private var last = Date.distantPast
    private var trailing: DispatchWorkItem?

    init(interval: TimeInterval = 0.1) {
        self.interval = interval
    }

    func submit(_ body: @escaping () -> Void) {
        let elapsed = Date().timeIntervalSince(last)
        if elapsed >= interval {
            last = Date()
            trailing?.cancel()
            trailing = nil
            body()
            return
        }
        trailing?.cancel()
        let wait = interval - elapsed
        let item = DispatchWorkItem { [weak self] in
            self?.last = Date()
            self?.trailing = nil
            body()
        }
        trailing = item
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: item)
    }
}
