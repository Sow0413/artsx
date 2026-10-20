import SwiftUI
import WatchConnectivity
import WatchKit

/// iPhone からの接近合図で振動する。このターゲットは実機未確認で、Playgrounds には入れない。
@main
struct SurveyWatchApp: App {
    @StateObject private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 6) {
                Text(model.line)
                    .font(.headline)
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
