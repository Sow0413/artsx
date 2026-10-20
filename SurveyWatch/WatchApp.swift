import CoreMotion
import SwiftUI
import SurveyCore
import WatchConnectivity
import WatchKit

/// iPhone へ転倒を渡す。CMFallDetectionManager は資格が要り、実機の通知は未確認。
@main
struct SurveyWatchApp: App {
    @StateObject private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 8) {
                if model.pending {
                    Text("\(model.pendingLabel)？")
                        .font(.headline)
                    Text("\(model.countdown)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Button("大丈夫") {
                        model.cancel()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                } else {
                    Text(model.line)
                        .font(.headline)
                    Button("ヒヤリ") {
                        model.sendHiyari()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                Text(FallCall.disclaimer)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .onAppear { model.start() }
        }
    }
}

final class WatchModel: NSObject, ObservableObject, WCSessionDelegate, CMFallDetectionDelegate {
    @Published var line = "待機"
    @Published var pending = false
    @Published var countdown = 0
    @Published var pendingLabel = "転倒"

    private var detector = FallDetector()
    private var sentBegin = false
    private var ticker: Timer?
    private let motion = CMMotionManager()
    private var fallManager: CMFallDetectionManager?

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        if CMFallDetectionManager.isAvailable {
            let manager = CMFallDetectionManager()
            manager.delegate = self
            fallManager = manager
        }
    }

    func start() {
        if ticker == nil {
            ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.tick()
            }
        }
        startMotion()
        if fallManager?.authorizationStatus == .notDetermined {
            fallManager?.requestAuthorization { _ in }
        }
    }

    func cancel() {
        let signal = detector.cancel(at: Date())
        pending = false
        countdown = 0
        sentBegin = false
        guard signal == .cancelled else { return }
        line = "取り消ししました"
        send(["action": "fall-cancel"])
    }

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

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        apply(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        apply(message)
        replyHandler(["ok": "1"])
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        apply(userInfo)
    }

    func fallDetectionManager(
        _ fallDetectionManager: CMFallDetectionManager,
        didDetect event: CMFallDetectionEvent,
        completionHandler handler: @escaping @Sendable () -> Void
    ) {
        let detectedAt = event.date
        let resolution = event.resolution
        handler()
        DispatchQueue.main.async {
            switch resolution {
            case .rejected:
                self.cancelFromWatch()
            case .confirmed:
                self.beginPending(kind: .fall, at: detectedAt, immediate: true)
            case .dismissed, .unresponsive:
                self.beginPending(kind: .fall, at: detectedAt, immediate: false)
            @unknown default:
                self.beginPending(kind: .fall, at: detectedAt, immediate: false)
            }
        }
    }

    private func startMotion() {
        guard !motion.isDeviceMotionActive, motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 20.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let user = data.userAcceleration
            let gravity = data.gravity
            let userG = Self.magnitude(user.x, user.y, user.z)
            let totalG = Self.magnitude(user.x + gravity.x, user.y + gravity.y, user.z + gravity.z)
            self.ingest(FallSample(at: Date(), userG: userG, totalG: totalG))
        }
    }

    private func ingest(_ sample: FallSample) {
        let signal = detector.ingest(sample)
        guard case .awaitingCancel(let kind) = signal else { return }
        beginPending(kind: kind, at: sample.at, immediate: false)
    }

    private func beginPending(kind: FallKind, at date: Date, immediate: Bool) {
        if immediate {
            pending = false
            countdown = 0
            line = "\(kind.label)を知らせます"
            send([
                "action": "fall",
                "kind": kind.rawValue,
                "at": date.timeIntervalSince1970,
                "immediate": "1"
            ])
            return
        }
        guard !pending, !sentBegin else { return }
        pending = true
        pendingLabel = kind.label
        countdown = 10
        sentBegin = true
        send([
            "action": "fall",
            "kind": kind.rawValue,
            "at": date.timeIntervalSince1970,
            "immediate": "0"
        ])
    }

    private func tick() {
        guard pending else { return }
        let now = Date()
        let signal = detector.tick(at: now)
        let snap = detector.snapshot(at: now)
        countdown = Int(ceil(snap.cancelRemaining ?? 0))
        if case .confirmed = signal {
            pending = false
            sentBegin = false
            line = "近くに知らせます"
        }
    }

    private func cancelFromWatch() {
        _ = detector.cancel(at: Date())
        pending = false
        countdown = 0
        sentBegin = false
        line = "取り消ししました"
        send(["action": "fall-cancel"])
    }

    private func apply(_ message: [String: Any]) {
        if message["action"] as? String == "fall-clear" {
            DispatchQueue.main.async {
                _ = self.detector.cancel(at: Date())
                self.pending = false
                self.countdown = 0
                self.sentBegin = false
                self.line = "取り消ししました"
            }
            return
        }
        if message["action"] as? String == "fall-ask" {
            let kind: FallKind = (message["kind"] as? String) == FallKind.impact.rawValue ? .impact : .fall
            let detectedAt = Self.time(from: message)
            DispatchQueue.main.async {
                guard !self.pending else { return }
                _ = self.detector.noteExternal(kind: kind, detectedAt: detectedAt, now: Date(), immediate: false)
                self.pending = self.detector.phase == .awaitingCancel
                self.pendingLabel = kind.label
                self.sentBegin = true
                let snap = self.detector.snapshot(at: Date())
                self.countdown = Int(ceil(snap.cancelRemaining ?? 0))
                if !self.pending {
                    self.line = "\(kind.label)を知らせます"
                }
            }
            return
        }
        if message["action"] as? String == "fall-sent" {
            let text = message["text"] as? String
            DispatchQueue.main.async {
                self.pending = false
                self.countdown = 0
                self.sentBegin = false
                self.line = text ?? "近くに知らせました"
                WKInterfaceDevice.current().play(.failure)
            }
            return
        }
        let cue = message["cue"] as? String
        let text = message["text"] as? String
        DispatchQueue.main.async {
            switch cue {
            case "alarm":
                self.line = text ?? "警報"
                WKInterfaceDevice.current().play(.failure)
            case "caution":
                self.line = text ?? "注意"
                WKInterfaceDevice.current().play(.notification)
            case "fall":
                self.line = text ?? "転倒"
                WKInterfaceDevice.current().play(.failure)
            case "clear":
                if !self.pending { self.line = "待機" }
            default:
                break
            }
        }
    }

    private func send(_ payload: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    private static func magnitude(_ x: Double, _ y: Double, _ z: Double) -> Double {
        (x * x + y * y + z * z).squareRoot()
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
}
