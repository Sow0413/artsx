import Foundation
import SurveyCore

#if !SURVEY_PLAYGROUND && canImport(NearbyInteraction)
import NearbyInteraction

/// UWB が使える端末だけ。距離は GNSS より優先する。発見と測距は未確認。
final class SystemUWB: NSObject, NISessionDelegate {
    private var session: NISession?
    private var peers: [NIDiscoveryToken: String] = []
    var onDistance: ((String, Double) -> Void)?

    func start() {
        guard NISession.isSupported else { return }
        let session = NISession()
        session.delegate = self
        self.session = session
    }

    func tokenData() -> Data? {
        guard let token = session?.discoveryToken else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    func accept(tokenData: Data, peerID: String) {
        guard let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: tokenData) else { return }
        peers[token] = peerID
        session?.run(NINearbyPeerConfiguration(peerToken: token))
    }

    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        for object in nearbyObjects {
            guard let distance = object.distance, let peerID = peers[object.discoveryToken] else { continue }
            onDistance?(peerID, Double(distance))
        }
    }
}
#endif

#if !SURVEY_PLAYGROUND && canImport(WatchConnectivity)
import WatchConnectivity

/// ペアの Apple Watch へ振動の合図を送る。Watch 側の再生は未確認。
final class SystemWatch: NSObject, WCSessionDelegate {
    var onHiyari: (() -> Void)?

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func send(_ cue: WatchCue) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let payload = ["cue": cue.rawValue]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            try? session.updateApplicationContext(payload)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        acceptHiyari(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        acceptHiyari(message)
        replyHandler(["ok": "1"])
    }

    private func acceptHiyari(_ message: [String: Any]) {
        guard message["action"] as? String == "hiyari" else { return }
        DispatchQueue.main.async { self.onHiyari?() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
#endif
