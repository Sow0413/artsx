import Foundation
import SurveyCore

/// 無線と位置共有が、同じ近距離セッションを使う。
final class NearbyLink {
    var onRadio: ((RadioPacket) -> Void)?
    var onCrew: ((CrewPacket) -> Void)?
    private var peerObservers: [(Int) -> Void] = []

    #if !SURVEY_PLAYGROUND && canImport(MultipeerConnectivity)
    private let peers = SystemNearbyRadio()
    #endif

    init() {
        #if !SURVEY_PLAYGROUND && canImport(MultipeerConnectivity)
        peers.onPacket = { [weak self] packet in
            self?.onRadio?(packet)
        }
        peers.onCrew = { [weak self] packet in
            self?.onCrew?(packet)
        }
        peers.onPeerCount = { [weak self] count in
            self?.peerObservers.forEach { $0(count) }
        }
        #endif
    }

    func observePeers(_ body: @escaping (Int) -> Void) {
        peerObservers.append(body)
    }

    func start(channel: RadioChannel, name: String) {
        #if !SURVEY_PLAYGROUND && canImport(MultipeerConnectivity)
        guard RadioHardware.nearbyPeers else { return }
        peers.start(channel: channel, name: name)
        #else
        _ = channel
        _ = name
        #endif
    }

    func send(_ packet: RadioPacket) {
        #if !SURVEY_PLAYGROUND && canImport(MultipeerConnectivity)
        peers.send(packet)
        #else
        _ = packet
        #endif
    }

    func send(_ packet: CrewPacket) {
        #if !SURVEY_PLAYGROUND && canImport(MultipeerConnectivity)
        peers.send(packet)
        #else
        _ = packet
        #endif
    }
}
