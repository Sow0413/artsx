import AudioToolbox
import Foundation
import SurveyCore
import UIKit

/// 同じプロジェクトの位置と役割。警報は音、振動、画面。Watch がつながっていればそちらも。
final class CrewController: ObservableObject {
    @Published private(set) var worst: ProximityLevel = .clear
    @Published private(set) var statusLine = "同じ現場の相手はまだいません"
    @Published private(set) var marks: [CrewMark] = []
    @Published private(set) var peers: [CrewFix] = []
    @Published private(set) var role: CrewRole = .worker
    @Published private(set) var limits = ProximityLimits.standard
    @Published private(set) var threats = ThreatPicture(facingDegrees: nil, facingSource: "", cues: [], headline: "近くに人はいません")
    @Published private(set) var callout: ApproachNotice?
    @Published private(set) var fallSpeech: String?
    @Published private(set) var fallCue: FallCue?
    @Published var speakDirections = false
    @Published private(set) var revision = 0

    var onAlarm: ((Date) -> Bool)?
    var onHiyari: (() -> Void)?
    var onWatchFall: ((FallKind, Date, Bool) -> Void)?
    var onWatchFallCancel: (() -> Void)?
    var onSOS: (() -> Void)?
    var onSOSStop: (() -> Void)?
    let notice = SafetyNotice.text
    private let relay = CrewRelayStub(reachable: false)
    private let mesh = CrewMesh(reachable: false)
    private let desk: CrewDesk
    private let nearby: NearbyLink
    private var projectName: String?
    private var root: URL?
    private var savedSignature = ""
    private var lastCue: WatchCue?
    private var lastAlarmSound: Date?
    private var courseDegrees: Double?
    private var headingDegrees: Double?
    private var lastSpoken = ""
    private var approachMemory: [ApproachMemory] = []
    private var workRadius = MachineCatalog.twentyTon.radiusMeters
    private var approachLead = ApproachCallout.defaultLeadMeters
    private var approachRepeat = ApproachCallout.defaultRepeatSeconds
    private var openedAlarms: Set<UUID> = []
    private var speeches: [IncidentSpeech] = []
    private var channelID = ""
    private var heardFalls: Set<UUID> = []
    private var fallUntil: Date?
    #if !SURVEY_PLAYGROUND && canImport(NearbyInteraction)
    private let uwb = SystemUWB()
    #endif
    #if !SURVEY_PLAYGROUND && canImport(WatchConnectivity)
    private let watch = SystemWatch()
    #endif

    init(nearby: NearbyLink) {
        self.nearby = nearby
        desk = CrewDesk(deviceID: UUID().uuidString, name: "この端末", role: .worker, relay: relay, nearby: mesh)
    }

    func arm() {
        nearby.onCrew = { [weak self] packet in
            self?.accept(packet)
        }
        nearby.observePeers { [weak self] count in
            guard RadioHardware.nearbyPeers else { return }
            self?.mesh.isReachable = count > 0
        }
        mesh.onSent = { [weak self] packet in
            self?.nearby.send(packet)
        }
        #if !SURVEY_PLAYGROUND && canImport(NearbyInteraction)
        if RadioHardware.nearbyInteraction {
            uwb.onDistance = { [weak self] peerID, distance in
                self?.desk.noteRange(peerID: peerID, distanceMeters: distance, at: Date())
                self?.publish(now: Date(), sound: true)
            }
            uwb.start()
        }
        #endif
        #if !SURVEY_PLAYGROUND && canImport(WatchConnectivity)
        if RadioHardware.watch {
            watch.onHiyari = { [weak self] in
                self?.onHiyari?()
            }
            watch.onFall = { [weak self] kind, date, immediate in
                self?.onWatchFall?(kind, date, immediate)
            }
            watch.onFallCancel = { [weak self] in
                self?.onWatchFallCancel?()
            }
            watch.onSOS = { [weak self] in
                self?.onSOS?()
            }
            watch.onSOSStop = { [weak self] in
                self?.onSOSStop?()
            }
            watch.start()
        }
        #endif
    }

    var deviceID: String { desk.deviceID }
    var displayName: String { desk.name }

    func recentSpeeches() -> [IncidentSpeech] { speeches }

    func rememberFallSpeech(_ text: String, at date: Date) {
        rememberSpeech(text, at: date)
    }

    func clearWatchFall() {
        #if !SURVEY_PLAYGROUND && canImport(WatchConnectivity)
        if RadioHardware.watch {
            watch.sendFallClear()
        }
        #endif
    }

    func askWatchFall(kind: FallKind, at date: Date) {
        #if !SURVEY_PLAYGROUND && canImport(WatchConnectivity)
        if RadioHardware.watch {
            watch.sendFallAsk(kind: kind, at: date)
        }
        #else
        _ = kind
        _ = date
        #endif
    }

    func tellWatchSOS(live: Bool) {
        #if !SURVEY_PLAYGROUND && canImport(WatchConnectivity)
        if RadioHardware.watch {
            watch.sendSOSLive(live)
        }
        #else
        _ = live
        #endif
    }

    func alertSOS(_ text: String) {
        #if !SURVEY_PLAYGROUND && canImport(WatchConnectivity)
        if RadioHardware.watch {
            watch.sendSOSAlert(text)
        }
        #else
        _ = text
        #endif
    }

    func noteWatchFallSent(_ text: String) {
        #if !SURVEY_PLAYGROUND && canImport(WatchConnectivity)
        if RadioHardware.watch {
            watch.sendFallSent(text: text)
        }
        #else
        _ = text
        #endif
    }

    func distances() -> [String: Double] {
        Dictionary(desk.hits.map { ($0.other.id, $0.distanceMeters) }, uniquingKeysWith: { first, _ in first })
    }

    func setSpeakDirections(_ enabled: Bool) {
        speakDirections = enabled
        lastSpoken = ""
        if enabled {
            speak(at: Date())
        }
    }

    func setRole(_ role: CrewRole) {
        self.role = role
        desk.role = role
        threats = currentPicture()
        guard let projectName, let root else { return }
        let identity = CrewIdentity(deviceID: desk.deviceID, name: desk.name, role: role)
        try? CrewIdentityStore.save(identity, projectName: projectName, at: root)
    }

    func note(position: GeodeticPosition?, project: SurveyProject?, radius: Double, root: URL, now: Date = Date()) {
        self.root = root
        guard let project else {
            desk.leave(at: now)
            publish(now: now, sound: true)
            return
        }
        if projectName != project.name {
            let identity = CrewIdentityStore.load(projectName: project.name, at: root)
            desk.deviceID = identity.deviceID
            desk.name = identity.name
            desk.role = identity.role
            role = identity.role
            projectName = project.name
            desk.join(projectID: project.id)
            let history = ProximityLog.load(projectName: project.name, at: root)
            desk.remember(history)
            savedSignature = signature(history)
            approachMemory = []
            callout = nil
            openedAlarms = []
            speeches = []
            heardFalls = []
            fallSpeech = nil
            fallCue = nil
            fallUntil = nil
        }
        channelID = project.id
        limits = ProximityLimits.resolved(caution: project.cautionMeters, margin: project.proximityMarginMeters)
        desk.limits = limits
        workRadius = radius
        approachLead = ApproachCallout.lead(from: project.approachLeadMeters)
        approachRepeat = ApproachCallout.repeatSeconds(from: project.approachRepeatSeconds)
        courseDegrees = position?.courseDegrees
        headingDegrees = position?.headingDegrees
        guard let position, position.isPlottable else {
            publish(now: now, sound: false)
            return
        }
        let channel = RadioChannel.project(id: project.id, name: project.name)
        nearby.start(channel: channel, name: desk.name)
        let fix = CrewFix(
            id: desk.deviceID,
            name: desk.name,
            role: desk.role,
            latitudeDegrees: position.latitudeDegrees,
            longitudeDegrees: position.longitudeDegrees,
            horizontalAccuracyMeters: position.horizontalAccuracyMeters,
            workRadiusMeters: desk.role == .machine ? radius : nil,
            sentAt: now,
            ranges: desk.ranges,
            courseDegrees: position.courseDegrees,
            headingDegrees: position.headingDegrees
        )
        #if !SURVEY_PLAYGROUND && canImport(NearbyInteraction)
        _ = desk.publish(fix, uwbToken: RadioHardware.nearbyInteraction ? uwb.tokenData() : nil)
        #else
        _ = desk.publish(fix)
        #endif
        desk.evaluate(selfFix: fix, now: now)
        publish(now: now, sound: true)
    }

    private func accept(_ packet: CrewPacket) {
        desk.receive(packet, now: Date())
        #if !SURVEY_PLAYGROUND && canImport(NearbyInteraction)
        if RadioHardware.nearbyInteraction, let token = packet.uwbToken {
            uwb.accept(tokenData: token, peerID: packet.fix.id)
        }
        #endif
        publish(now: Date(), sound: true)
    }

    func receiveFall(_ notice: FallNotice, position: GeodeticPosition?) {
        guard notice.deviceID != deviceID, notice.channelID == channelID else { return }
        guard heardFalls.insert(notice.id).inserted else { return }
        let announcement: FallAnnouncement
        if let position, position.isPlottable,
           let made = FallCall.announce(
            notice: notice,
            fromLatitude: position.latitudeDegrees,
            fromLongitude: position.longitudeDegrees,
            courseDegrees: position.courseDegrees,
            headingDegrees: position.headingDegrees
           ) {
            announcement = made
        } else {
            announcement = FallAnnouncement(speech: "\(notice.name) \(notice.kind.label)", cue: nil)
        }
        fallSpeech = announcement.speech
        fallCue = announcement.cue
        fallUntil = Date().addingTimeInterval(30)
        rememberSpeech(announcement.speech, at: Date())
        CrewVoice.say(announcement.speech)
        pulseFall(announcement.speech)
        revision += 1
    }

    func ageFall(now: Date) {
        guard let fallUntil, now >= fallUntil else { return }
        fallSpeech = nil
        fallCue = nil
        self.fallUntil = nil
        revision += 1
    }

    private func publish(now: Date, sound: Bool) {
        ageFall(now: now)
        peers = desk.others
        worst = desk.worst
        if let origin = desk.selfFix {
            marks = CrewPlot.marks(origin: origin, hits: desk.hits)
        } else {
            marks = []
        }
        threats = currentPicture()
        let approach = ApproachCallout.evaluate(
            selfRole: role,
            selfWorkRadius: workRadius,
            marks: marks,
            courseDegrees: courseDegrees,
            headingDegrees: headingDegrees,
            leadMeters: approachLead,
            repeatSeconds: approachRepeat,
            now: now,
            memory: approachMemory
        )
        approachMemory = approach.memory
        callout = approach.open
        statusLine = describe()
        revision += 1
        persist()
        let fresh = desk.events.filter { $0.level == .alarm && $0.endedAt == nil && !openedAlarms.contains($0.id) }
        if !fresh.isEmpty, onAlarm?(now) == true {
            for event in fresh {
                openedAlarms.insert(event.id)
            }
        }
        guard sound else { return }
        signal(now: now)
        if let spoken = approach.spoken {
            rememberSpeech(spoken.speech, at: now)
            CrewVoice.say(spoken.speech)
        } else {
            speak(at: now)
        }
    }

    private func currentPicture() -> ThreatPicture {
        ThreatBearing.picture(
            selfRole: role,
            marks: marks,
            courseDegrees: courseDegrees,
            headingDegrees: headingDegrees,
            cautionMeters: limits.cautionMeters
        )
    }

    private func speak(at date: Date) {
        guard speakDirections, let cue = threats.cues.first else { return }
        guard cue.speech != lastSpoken else { return }
        lastSpoken = cue.speech
        rememberSpeech(cue.speech, at: date)
        CrewVoice.say(cue.speech)
    }

    private func rememberSpeech(_ text: String, at date: Date) {
        guard !text.isEmpty else { return }
        speeches.append(IncidentSpeech(at: date, text: text))
        if speeches.count > 30 {
            speeches.removeFirst(speeches.count - 30)
        }
    }

    private func describe() -> String {
        let threats = desk.hits.filter { $0.level != .clear }
        if let first = threats.first {
            let kind = first.level == .alarm ? "警報" : "注意"
            let distance = String(format: "%.1f", MachineReach.roundTenths(first.distanceMeters))
            let via = first.rangeKind == .uwb ? " UWB" : ""
            return "\(kind) \(first.other.role.label) \(first.other.name) \(distance)m\(via)"
        }
        if desk.others.isEmpty {
            return "同じ現場の相手はまだいません"
        }
        return "相手 \(desk.others.count)。半径の外です"
    }

    private func persist() {
        guard let projectName, let root else { return }
        let next = signature(desk.events)
        guard next != savedSignature else { return }
        try? ProximityLog.save(desk.events, projectName: projectName, at: root)
        savedSignature = next
    }

    private func signature(_ events: [ProximityEvent]) -> String {
        events.map { "\($0.id.uuidString):\($0.endedAt?.timeIntervalSince1970 ?? -1):\($0.closestMeters)" }.joined(separator: "|")
    }

    private func signal(now: Date) {
        let cue = WatchCue(worst)
        let repeatAlarm = worst == .alarm && (lastAlarmSound == nil || now.timeIntervalSince(lastAlarmSound ?? now) >= 4)
        let changed = cue != lastCue
        guard changed || repeatAlarm else { return }
        lastCue = cue
        if worst == .alarm {
            lastAlarmSound = now
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
            AudioServicesPlayAlertSound(1005)
        } else if worst == .caution, changed {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
        }
        #if !SURVEY_PLAYGROUND && canImport(WatchConnectivity)
        if RadioHardware.watch, changed || repeatAlarm {
            watch.send(cue)
        }
        #endif
    }

    private func pulseFall(_ speech: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
        AudioServicesPlayAlertSound(1005)
        #if !SURVEY_PLAYGROUND && canImport(WatchConnectivity)
        if RadioHardware.watch {
            watch.send(.fall, text: speech)
        }
        #endif
    }
}
