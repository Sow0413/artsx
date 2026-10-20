import Foundation
import SurveyCore

/// オペ画面のボタンと、中継・近距離・端末内記録をつなぐ。
final class RadioController: ObservableObject {
    @Published private(set) var phase: RadioPhase = .idle
    @Published private(set) var status: String
    @Published var attachStation = true

    private let relay = P510RelayStub(reachable: false)
    private let mesh = NearbyMesh(reachable: false)
    private let desk: RadioDesk
    private var systemBegan = false

    #if !SURVEY_PLAYGROUND && canImport(PushToTalk)
    private let system = SystemPushToTalk()
    #endif
    #if !SURVEY_PLAYGROUND && canImport(MultipeerConnectivity)
    private let peers = SystemNearbyRadio()
    #endif

    init() {
        desk = RadioDesk(speaker: "この端末", relay: relay, nearby: mesh)
        if RadioHardware.pushToTalk || RadioHardware.nearbyPeers {
            status = "中継はまだありません。近くに同じ現場がいれば、そちらへ出します。"
        } else {
            status = "無線の権限は切ってあります。発話は端末に残します。"
        }
    }

    func arm() {
        #if !SURVEY_PLAYGROUND && canImport(PushToTalk)
        if RadioHardware.pushToTalk {
            system.onBegan = { [weak self] in self?.systemTalkBegan() }
            system.onEnded = { [weak self] in self?.systemTalkEnded() }
            system.start()
        }
        #endif
        #if !SURVEY_PLAYGROUND && canImport(MultipeerConnectivity)
        if RadioHardware.nearbyPeers {
            peers.onPacket = { [weak self] packet in
                self?.desk.receive(packet)
                self?.publish()
            }
            peers.onPeerCount = { [weak self] count in
                self?.mesh.isReachable = count > 0
                self?.publish()
            }
            mesh.onSent = { [weak self] packet in
                self?.peers.send(packet)
            }
        }
        #endif
    }

    func begin(channel: RadioChannel, station: RadioStationStamp?) {
        desk.attachStation = attachStation
        desk.join(channel)
        #if !SURVEY_PLAYGROUND && canImport(PushToTalk)
        if RadioHardware.pushToTalk {
            system.join(channel)
        }
        #endif
        #if !SURVEY_PLAYGROUND && canImport(MultipeerConnectivity)
        if RadioHardware.nearbyPeers {
            peers.start(channel: channel, name: desk.speaker)
        }
        #endif
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

    private func publish() {
        phase = desk.phase
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
