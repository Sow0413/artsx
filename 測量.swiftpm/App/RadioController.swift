import Foundation
import SurveyCore

/// オペ画面のボタンと、中継・近距離・端末内記録をつなぐ。
final class RadioController: ObservableObject {
    @Published private(set) var phase: RadioPhase = .idle
    @Published private(set) var hearingSpeaker: String?
    @Published private(set) var status: String
    @Published var attachStation = true
    @Published private(set) var spaceAudio = false

    private let relay = P510RelayStub(reachable: false)
    private let mesh = NearbyMesh(reachable: false)
    private let desk: RadioDesk
    private let nearby: NearbyLink
    private let space = RadioSpace()
    private let defaults: UserDefaults
    private var systemBegan = false
    /// 受信中の話者を、空間オーディオの位置に変える。方向不明なら nil。
    var spacePoint: () -> TalkPoint? = { nil }
    var onRelay: ((RadioPacket) -> Void)?
    private var heardRadio: [String] = []

    #if !SURVEY_PLAYGROUND && canImport(PushToTalk)
    private let system = SystemPushToTalk()
    #endif

    init(nearby: NearbyLink, defaults: UserDefaults = .standard) {
        self.nearby = nearby
        self.defaults = defaults
        desk = RadioDesk(speaker: "この端末", relay: relay, nearby: mesh)
        if RadioHardware.pushToTalk || RadioHardware.nearbyPeers {
            status = "中継はまだありません。近くに同じ現場がいれば、そちらへ出します。"
        } else {
            status = "無線の権限は切ってあります。発話は端末に残します。"
        }
        let audio = defaults.object(forKey: "radio.spaceAudio") as? Bool ?? false
        spaceAudio = audio
        space.enabled = audio
        desk.onAudio = { [weak self] data in
            self?.playIncoming(data)
        }
    }

    func rename(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        desk.speaker = trimmed
    }

    func setSpaceAudio(_ enabled: Bool) {
        spaceAudio = enabled
        space.enabled = enabled
        defaults.set(enabled, forKey: "radio.spaceAudio")
        refreshSpace()
    }

    func refreshSpace() {
        guard spaceAudio, hearingSpeaker != nil, let point = spacePoint() else { return }
        space.place(point)
    }

    var relayReachable: Bool {
        get { relay.isReachable }
        set { relay.isReachable = newValue }
    }

    func recentUtterances() -> [RadioUtterance] { desk.utterances }

    func audioData() -> [UUID: Data] { desk.audio }

    func arm() {
        #if !SURVEY_PLAYGROUND && canImport(PushToTalk)
        if RadioHardware.pushToTalk {
            system.onBegan = { [weak self] in self?.systemTalkBegan() }
            system.onEnded = { [weak self] in self?.systemTalkEnded() }
            system.start()
        }
        #endif
        nearby.onRadio = { [weak self] packet in
            guard let self else { return }
            if self.claim(packet) {
                self.desk.receive(packet)
                self.publish()
            }
            self.onRelay?(packet)
        }
        nearby.observePeers { [weak self] count in
            guard RadioHardware.nearbyPeers else { return }
            self?.mesh.isReachable = count > 0
            self?.publish()
        }
        mesh.onSent = { [weak self] packet in
            guard let self else { return }
            self.nearby.send(packet)
            self.claim(packet)
            self.onRelay?(packet)
        }
    }

    func begin(channel: RadioChannel, station: RadioStationStamp?) {
        desk.attachStation = attachStation
        desk.join(channel)
        #if !SURVEY_PLAYGROUND && canImport(PushToTalk)
        if RadioHardware.pushToTalk {
            system.join(channel)
        }
        #endif
        nearby.start(channel: channel, name: desk.speaker)
        let started = desk.beginTalking(at: Date(), station: station) != nil
        systemBegan = started
        #if !SURVEY_PLAYGROUND && canImport(PushToTalk)
        if started, RadioHardware.pushToTalk {
            system.begin()
        }
        #endif
        publish()
    }

    func end(projectName: String?, root: URL?) {
        #if !SURVEY_PLAYGROUND && canImport(PushToTalk)
        if RadioHardware.pushToTalk {
            system.end()
        }
        #endif
        systemBegan = false
        guard let utterance = desk.endTalking(at: Date()) else {
            publish()
            return
        }
        if let projectName, let root {
            try? RadioLog.append(utterance, projectName: projectName, at: root)
        }
        publish()
    }

    private func systemTalkBegan() {
        guard desk.phase != .transmitting, desk.channel != nil else { return }
        _ = desk.beginTalking(at: Date(), station: nil)
        publish()
    }

    private func systemTalkEnded() {
        guard systemBegan == false else { return }
        _ = desk.endTalking(at: Date())
        publish()
    }

    func ingestRelayed(_ packet: RadioPacket, play: Bool) {
        guard claim(packet) else { return }
        desk.receive(packet)
        if play, let data = packet.audio {
            playIncoming(data)
        }
        publish()
    }

    private func claim(_ packet: RadioPacket) -> Bool {
        let key = MeshDuty.radioFingerprint(packet)
        if heardRadio.contains(key) { return false }
        heardRadio.append(key)
        if heardRadio.count > 200 {
            heardRadio.removeFirst(heardRadio.count - 200)
        }
        return true
    }

    private func playIncoming(_ data: Data) {
        guard spaceAudio else { return }
        if let point = spacePoint() {
            space.place(point)
        } else {
            space.place(TalkPoint(x: 0, y: 0, z: 0))
        }
        space.play(data)
    }

    private func publish() {
        phase = desk.phase
        hearingSpeaker = desk.hearingSpeaker
        refreshSpace()
        if let speaker = desk.hearingSpeaker {
            status = "\(speaker) が話しています"
            return
        }
        if phase == .transmitting {
            switch desk.activePath {
            case .relay: status = "中継へ話しています"
            case .nearby: status = "近くの端末へ話しています"
            case nil: status = "記録しています。相手には届いていません"
            }
            return
        }
        switch desk.activePath {
        case .relay: status = "中継"
        case .nearby: status = "近くの端末"
        case nil:
            status = RadioHardware.pushToTalk
                ? "中継はまだありません"
                : "無線の権限は切ってあります。発話は端末に残します。"
        }
    }
}
