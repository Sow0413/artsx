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
    @Published var speakDirections = false
    @Published private(set) var revision = 0

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
            watch.start()
        }
        #endif
    }

    func setSpeakDirections(_ enabled: Bool) {
        speakDirections = enabled
        lastSpoken = ""
        if enabled {
            speak()
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
        }
        limits = ProximityLimits.resolved(caution: project.cautionMeters, margin: project.proximityMarginMeters)
        desk.limits = limits
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
            ranges: desk.ranges
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

    private func publish(now: Date, sound: Bool) {
        peers = desk.others
        worst = desk.worst
        if let origin = desk.selfFix {
            marks = CrewPlot.marks(origin: origin, hits: desk.hits)
        } else {
            marks = []
        }
        threats = currentPicture()
        statusLine = describe()
        revision += 1
        persist()
        guard sound else { return }
        signal(now: now)
        speak()
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

    private func speak() {
        guard speakDirections, let cue = threats.cues.first else { return }
        guard cue.speech != lastSpoken else { return }
        lastSpoken = cue.speech
        CrewVoice.say(cue.speech)
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
}
