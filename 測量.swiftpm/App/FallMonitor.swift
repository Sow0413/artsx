import Foundation
import SwiftUI
import SurveyCore

#if !SURVEY_PLAYGROUND && canImport(CoreMotion)
import CoreMotion
#endif

/// 加速度で転倒と衝撃を見る。確定は SurveyCore の判定に従う。実機の加速度と時計の通知は未確認。
final class FallMonitor: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var phase: FallPhase = .idle
    @Published private(set) var kind: FallKind?
    @Published private(set) var countdown = 0
    @Published private(set) var status = "転倒検知は待機しています"
    @Published private(set) var impactG: Double
    @Published private(set) var stillSeconds: TimeInterval

    let disclaimer = FallCall.disclaimer
    var onAwaiting: ((FallKind, Date) -> Void)?
    var onConfirmed: ((FallKind) -> Void)?

    private var detector: FallDetector
    private var ticker: Timer?
    private var started = false
    private var seenExternal: Set<String> = []
    private let defaults: UserDefaults
    #if !SURVEY_PLAYGROUND && canImport(CoreMotion)
    private let motion = SystemMotion()
    #endif

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedImpact = defaults.object(forKey: Key.impact) as? Double
        let storedStill = defaults.object(forKey: Key.still) as? Double
        let limits = FallLimits.resolved(impactG: storedImpact, stillSeconds: storedStill)
        enabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        impactG = limits.impactG
        stillSeconds = limits.stillSeconds
        detector = FallDetector(limits: limits)
    }

    func start() {
        guard !started else { return }
        started = true
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        guard enabled else { return }
        startMotion()
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        defaults.set(on, forKey: Key.enabled)
        guard started else { return }
        if on {
            startMotion()
        } else if phase != .awaitingCancel {
            stopMotion()
        }
    }

    @discardableResult
    func setImpactG(_ text: String) -> String {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces)), value.isFinite else {
            return "閾値は数にしてください。"
        }
        let limits = FallLimits.resolved(impactG: value, stillSeconds: stillSeconds)
        apply(limits)
        if abs(limits.impactG - value) > 0.001 {
            return "閾値は \(format(limits.impactG))g にしました。1.5g から 8g です。"
        }
        return "衝撃の閾値を \(format(limits.impactG))g にしました。"
    }

    @discardableResult
    func setStillSeconds(_ text: String) -> String {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces)), value.isFinite else {
            return "静止の秒数は数にしてください。"
        }
        let limits = FallLimits.resolved(impactG: impactG, stillSeconds: value)
        apply(limits)
        if abs(limits.stillSeconds - value) > 0.001 {
            return "静止は \(format(limits.stillSeconds))秒にしました。1秒から5秒です。"
        }
        return "静止の確認を \(format(limits.stillSeconds))秒にしました。"
    }

    func ingest(_ sample: FallSample) {
        guard enabled || phase == .awaitingCancel else { return }
        let signal = detector.ingest(sample)
        publish(signal, at: sample.at)
    }

    func noteExternal(kind: FallKind, detectedAt: Date, now: Date, immediate: Bool) {
        guard enabled || phase == .awaitingCancel else { return }
        let key = "\(kind.rawValue)|\(detectedAt.timeIntervalSince1970)"
        guard seenExternal.insert(key).inserted else { return }
        let signal = detector.noteExternal(kind: kind, detectedAt: detectedAt, now: now, immediate: immediate)
        publish(signal, at: now)
    }

    @discardableResult
    func cancel() -> Bool {
        let now = Date()
        let signal = detector.cancel(at: now)
        publish(signal, at: now)
        return signal == .cancelled
    }

    private func tick() {
        let now = Date()
        let signal = detector.tick(at: now)
        publish(signal, at: now)
    }

    private func publish(_ signal: FallSignal?, at date: Date) {
        let snap = detector.snapshot(at: date)
        if phase != snap.phase { phase = snap.phase }
        if kind != snap.kind { kind = snap.kind }
        let remaining = Int(ceil(snap.cancelRemaining ?? 0))
        if countdown != remaining { countdown = remaining }
        switch signal {
        case .awaitingCancel(let kind):
            status = "\(kind.label)かもしれません。大丈夫なら取り消せます"
            onAwaiting?(kind, date)
        case .confirmed(let kind):
            status = "\(kind.label)を近くに知らせます"
            onConfirmed?(kind)
        case .cancelled:
            status = "取り消ししました"
        case nil:
            break
        }
    }

    private func apply(_ limits: FallLimits) {
        impactG = limits.impactG
        stillSeconds = limits.stillSeconds
        detector.updateLimits(limits)
        defaults.set(limits.impactG, forKey: Key.impact)
        defaults.set(limits.stillSeconds, forKey: Key.still)
    }

    private func startMotion() {
        #if !SURVEY_PLAYGROUND && canImport(CoreMotion)
        motion.onSample = { [weak self] sample in
            self?.ingest(sample)
        }
        motion.start()
        #endif
    }

    private func stopMotion() {
        #if !SURVEY_PLAYGROUND && canImport(CoreMotion)
        motion.stop()
        #endif
    }

    private func format(_ value: Double) -> String {
        String(format: "%g", value)
    }

    private enum Key {
        static let enabled = "fall.enabled"
        static let impact = "fall.impactG"
        static let still = "fall.stillSeconds"
    }
}

struct FallBanner: View {
    @ObservedObject var fall: FallMonitor
    var incoming: String?
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(fall.disclaimer)
                .font(SurveyType(12, .heavy))
                .foregroundStyle(fall.phase == .awaitingCancel ? Color.white : SurveyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(fall.disclaimer)
            if fall.phase == .awaitingCancel {
                HStack(spacing: 12) {
                    Text("\(fall.kind?.label ?? "転倒")？ \(fall.countdown)秒")
                        .font(SurveyType(22, .black))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("大丈夫", action: onCancel)
                        .font(SurveyType(20, .black))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(SurveyColor.green)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel("大丈夫。転倒の通知を取り消す")
                }
            } else if let incoming {
                Text(incoming)
                    .font(SurveyType(28, .black))
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(incoming)
            } else if !fall.enabled {
                Text("転倒検知はオフ")
                    .font(SurveyType(13, .heavy))
                    .foregroundStyle(SurveyColor.muted)
            }
        }
        .foregroundStyle(fall.phase == .awaitingCancel || incoming != nil ? Color.white : SurveyColor.text)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var fill: Color {
        if fall.phase == .awaitingCancel || incoming != nil {
            return SurveyColor.red
        }
        return SurveyColor.card.opacity(0.94)
    }
}

#if !SURVEY_PLAYGROUND && canImport(CoreMotion)
/// iPhone の加速度。50Hz。実機での転倒判定は未確認。
final class SystemMotion {
    var onSample: ((FallSample) -> Void)?
    private let manager = CMMotionManager()
    private var running = false

    func start() {
        guard !running, manager.isDeviceMotionAvailable else { return }
        running = true
        manager.deviceMotionUpdateInterval = 1.0 / 50.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let user = motion.userAcceleration
            let gravity = motion.gravity
            let userG = Self.magnitude(user.x, user.y, user.z)
            let totalG = Self.magnitude(user.x + gravity.x, user.y + gravity.y, user.z + gravity.z)
            self.onSample?(FallSample(at: Date(), userG: userG, totalG: totalG))
        }
    }

    func stop() {
        guard running else { return }
        manager.stopDeviceMotionUpdates()
        running = false
    }

    private static func magnitude(_ x: Double, _ y: Double, _ z: Double) -> Double {
        (x * x + y * y + z * z).squareRoot()
    }
}
#endif
