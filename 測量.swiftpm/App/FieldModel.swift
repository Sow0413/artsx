import Combine
import Foundation
import SurveyCore

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
    @Published private(set) var exportURL: URL?
    @Published var operation = OperationDesk.load()
    @Published var showsToolOrder = false
    @Published var stature = StatureProfile.load()
    @Published var showsStature = false
    @Published var asksStature = false
    @Published var showsCrosshair = false
    @Published var showsBatter = false
    @Published var showsPace = false
    @Published var showsARStakeout = false
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
    let controlPoints: [ControlPoint]
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

    @discardableResult
    func captureObservation() -> Bool {
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

    @discardableResult
    func recordControlPoint() -> Bool {
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
        remember(CoordinateBookIndex.entry(from: observation, kind: "基準点"))
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
        if stature.statureMeters == nil {
            asksStature = true
        }
        consumePendingConfirm()
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

    private func remember(_ entry: CoordinateBookEntry) {
        try? journal.upsertBook(entry)
        if let project = drawing.project {
            try? ProjectStore.saveCoordinate(entry, projectName: project.name, at: drawing.projectsRoot)
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
