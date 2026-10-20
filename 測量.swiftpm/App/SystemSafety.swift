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
    var onFall: ((FallKind, Date, Bool) -> Void)?
    var onFallCancel: (() -> Void)?
    var onSOS: (() -> Void)?
    var onSOSStop: (() -> Void)?

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func send(_ cue: WatchCue, text: String? = nil) {
        guard WCSession.isSupported() else { return }
        var payload: [String: Any] = ["cue": cue.rawValue]
        if let text { payload["text"] = text }
        let session = WCSession.default
        if cue == .fall {
            deliver(payload, session: session)
            return
        }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            try? session.updateApplicationContext(payload)
        }
    }

    func sendFallClear() {
        guard WCSession.isSupported() else { return }
        deliver(["action": "fall-clear"], session: WCSession.default)
    }

    func sendFallAsk(kind: FallKind, at date: Date) {
        guard WCSession.isSupported() else { return }
        deliver([
            "action": "fall-ask",
            "kind": kind.rawValue,
            "at": date.timeIntervalSince1970
        ], session: WCSession.default)
    }

    func sendFallSent(text: String) {
        guard WCSession.isSupported() else { return }
        deliver(["action": "fall-sent", "text": text], session: WCSession.default)
    }

    func sendSOSLive(_ live: Bool) {
        guard WCSession.isSupported() else { return }
        deliver(["action": live ? "sos-on" : "sos-off"], session: WCSession.default)
    }

    func sendSOSAlert(_ text: String) {
        guard WCSession.isSupported() else { return }
        deliver(["action": "sos-alert", "text": text], session: WCSession.default)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        accept(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        accept(message)
        replyHandler(["ok": "1"])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        accept(userInfo)
    }

    private func deliver(_ payload: [String: Any], session: WCSession) {
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func accept(_ message: [String: Any]) {
        let action = message["action"] as? String
        if action == "hiyari" {
            DispatchQueue.main.async { self.onHiyari?() }
            return
        }
        if action == "fall-cancel" {
            DispatchQueue.main.async { self.onFallCancel?() }
            return
        }
        if action == "sos" {
            DispatchQueue.main.async { self.onSOS?() }
            return
        }
        if action == "sos-stop" {
            DispatchQueue.main.async { self.onSOSStop?() }
            return
        }
        guard action == "fall" else { return }
        let kind: FallKind = (message["kind"] as? String) == FallKind.impact.rawValue ? .impact : .fall
        let detectedAt = Self.time(from: message)
        let immediate = (message["immediate"] as? String) == "1"
        DispatchQueue.main.async { self.onFall?(kind, detectedAt, immediate) }
    }

    private static func time(from message: [String: Any]) -> Date {
        if let value = message["at"] as? Double {
            return Date(timeIntervalSince1970: value)
        }
        if let value = message["at"] as? NSNumber {
            return Date(timeIntervalSince1970: value.doubleValue)
        }
        return Date()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
#endif
