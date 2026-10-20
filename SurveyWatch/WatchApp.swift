import SwiftUI
import WatchConnectivity
import WatchKit

/// iPhone からの接近合図で振動する。このターゲットは実機未確認で、Playgrounds には入れない。
@main
struct SurveyWatchApp: App {
    @StateObject private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 8) {
                Text(model.line)
                    .font(.headline)
                Button("ヒヤリ") {
                    model.sendHiyari()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                Text("補助。安全確認の代わりではない")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

final class WatchModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published var line = "待機"

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func sendHiyari() {
        guard WCSession.isSupported() else {
            line = "Watch が使えません"
            return
        }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            line = "iPhone に届いていません"
            return
        }
        session.sendMessage(["action": "hiyari"], replyHandler: { _ in
            DispatchQueue.main.async { self.line = "ヒヤリを送りました" }
        }, errorHandler: { _ in
            DispatchQueue.main.async { self.line = "送れませんでした" }
        })
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        apply(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    private func apply(_ message: [String: Any]) {
        let cue = message["cue"] as? String
        DispatchQueue.main.async {
            switch cue {
            case "alarm":
                self.line = "警報"
                WKInterfaceDevice.current().play(.failure)
            case "caution":
                self.line = "注意"
                WKInterfaceDevice.current().play(.notification)
            default:
                self.line = "待機"
            }
        }
    }
}
