import Foundation
import SurveyCore

#if !SURVEY_PLAYGROUND && canImport(PushToTalk)
import AVFoundation
import PushToTalk

/// システムの PushToTalk。ロック中の受信とシステムのボタンは、このクラスが枠だけ持つ。
/// 実機の参加、トークン、音声セッションは未確認。
final class SystemPushToTalk: NSObject, PTChannelManagerDelegate, PTChannelRestorationDelegate {
    private var manager: PTChannelManager?
    private var channel: RadioChannel?
    var onBegan: (() -> Void)?
    var onEnded: (() -> Void)?
    var onToken: ((Data) -> Void)?

    func start() {
        Task { @MainActor in
            do {
                manager = try await PTChannelManager.channelManager(delegate: self, restorationDelegate: self)
            } catch {
                manager = nil
            }
        }
    }

    func join(_ channel: RadioChannel) {
        self.channel = channel
        manager?.requestJoinChannel(
            channelUUID: channel.uuid,
            descriptor: PTChannelDescriptor(name: channel.projectName, image: nil)
        )
    }

    func begin() {
        guard let channel else { return }
        manager?.requestBeginTransmitting(channelUUID: channel.uuid)
    }

    func end() {
        guard let channel else { return }
        manager?.stopTransmitting(channelUUID: channel.uuid)
    }

    func channelManager(_ channelManager: PTChannelManager, didJoinChannel channelUUID: UUID, reason: PTChannelJoinReason) {
        Task {
            try? await channelManager.setTransmissionMode(.halfDuplex, channelUUID: channelUUID)
        }
    }

    func channelManager(_ channelManager: PTChannelManager, didLeaveChannel channelUUID: UUID, reason: PTChannelLeaveReason) {}

    func channelManager(
        _ channelManager: PTChannelManager,
        channelUUID: UUID,
        didBeginTransmittingFrom source: PTChannelTransmitRequestSource
    ) {
        onBegan?()
    }

    func channelManager(
        _ channelManager: PTChannelManager,
        channelUUID: UUID,
        didEndTransmittingFrom source: PTChannelTransmitRequestSource
    ) {
        onEnded?()
    }

    func channelManager(_ channelManager: PTChannelManager, receivedEphemeralPushToken pushToken: Data) {
        onToken?(pushToken)
    }

    func incomingPushResult(
        channelManager: PTChannelManager,
        channelUUID: UUID,
        pushPayload: [String: Any]
    ) -> PTPushResult {
        guard let speaker = pushPayload["activeSpeaker"] as? String else {
            return .leaveChannel
        }
        return .activeRemoteParticipant(PTParticipant(name: speaker, image: nil))
    }

    func channelManager(_ channelManager: PTChannelManager, didActivate audioSession: AVAudioSession) {}

    func channelManager(_ channelManager: PTChannelManager, didDeactivate audioSession: AVAudioSession) {}

    func channelDescriptor(restoredChannelUUID channelUUID: UUID) -> PTChannelDescriptor {
        PTChannelDescriptor(name: channel?.projectName ?? "現場", image: nil)
    }
}
#endif

#if !SURVEY_PLAYGROUND && canImport(MultipeerConnectivity)
import MultipeerConnectivity

/// 同じプロジェクトの、近くにいる端末。サービス名は survey-ptt。発見と送受信は未確認。
final class SystemNearbyRadio: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    static let service = "survey-ptt"
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var channel: RadioChannel?
    var onPacket: ((RadioPacket) -> Void)?
    var onCrew: ((CrewPacket) -> Void)?
    var onFall: ((FallNotice) -> Void)?
    var onSOS: ((SOSPacket) -> Void)?
    var onPeerCount: ((Int) -> Void)?

    func start(channel: RadioChannel, name: String) {
        guard self.channel?.uuid != channel.uuid else { return }
        stop()
        self.channel = channel
        let peer = MCPeerID(displayName: String(name.prefix(63)))
        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        let info = ["channel": channel.uuid.uuidString]
        let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: info, serviceType: Self.service)
        advertiser.delegate = self
        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.service)
        browser.delegate = self
        self.session = session
        self.advertiser = advertiser
        self.browser = browser
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        onPeerCount?(0)
    }

    func send(_ packet: RadioPacket) {
        send(LinkFrame(kind: .radio, radio: packet))
    }

    func send(_ packet: CrewPacket) {
        send(LinkFrame(kind: .crew, crew: packet))
    }

    func send(_ notice: FallNotice) {
        send(LinkFrame(kind: .fall, fall: notice))
    }

    func send(_ packet: SOSPacket) {
        send(LinkFrame(kind: .sos, sos: packet))
    }

    private func send(_ frame: LinkFrame) {
        guard let session, !session.connectedPeers.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(frame) else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        invitationHandler(true, session)
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard info?["channel"] == channel?.uuid.uuidString, let session else { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 12)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        onPeerCount?(session.connectedPeers.count)
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let frame = try? decoder.decode(LinkFrame.self, from: data) {
            if let radio = frame.radio { onPacket?(radio) }
            if let crew = frame.crew { onCrew?(crew) }
            if let fall = frame.fall { onFall?(fall) }
            if let sos = frame.sos { onSOS?(sos) }
            return
        }
        if let packet = try? decoder.decode(RadioPacket.self, from: data) {
            onPacket?(packet)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}
}
#endif
