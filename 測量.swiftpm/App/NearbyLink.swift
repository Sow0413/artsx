import Foundation
import SurveyCore

/// 無線と位置共有が、同じ近距離セッションを使う。
final class NearbyLink {
    var onRadio: ((RadioPacket) -> Void)?
    var onCrew: ((CrewPacket) -> Void)?
    var onFall: ((FallNotice) -> Void)?
    var onSOS: ((SOSPacket) -> Void)?
    var onAid: ((AidPacket) -> Void)?
    var onBucket: ((BucketEnvelope) -> Void)?
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
        peers.onFall = { [weak self] notice in
            self?.onFall?(notice)
        }
        peers.onSOS = { [weak self] packet in
            self?.onSOS?(packet)
        }
        peers.onAid = { [weak self] packet in
            self?.onAid?(packet)
        }
        peers.onBucket = { [weak self] envelope in
            self?.onBucket?(envelope)
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

    func send(_ notice: FallNotice) {
        #if !SURVEY_PLAYGROUND && canImport(MultipeerConnectivity)
        peers.send(notice)
        #else
        _ = notice
        #endif
    }

    func send(_ packet: SOSPacket) {
        #if !SURVEY_PLAYGROUND && canImport(MultipeerConnectivity)
        peers.send(packet)
        #else
        _ = packet
        #endif
    }

    func send(_ packet: AidPacket) {
        #if !SURVEY_PLAYGROUND && canImport(MultipeerConnectivity)
        peers.send(packet)
        #else
        _ = packet
        #endif
    }

    func send(_ envelope: BucketEnvelope) {
        #if !SURVEY_PLAYGROUND && canImport(MultipeerConnectivity)
        peers.send(envelope)
        #else
        _ = envelope
        #endif
    }
}
