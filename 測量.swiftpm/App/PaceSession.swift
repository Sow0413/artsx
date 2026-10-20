import Foundation
import SurveyCore

#if !SURVEY_PLAYGROUND && canImport(CoreMotion)
import CoreMotion
#endif

enum PaceSlot: Hashable {
    case calibration
    case measure
    case bridge
}

enum StepHardware {
    static var available: Bool {
        #if !SURVEY_PLAYGROUND && canImport(CoreMotion)
        return CMPedometer.isStepCountingAvailable()
        #else
        return false
        #endif
    }
}

/// 歩数計。前面にいるあいだだけ問い合わせる。実機の歩数は未確認。
final class PaceSession {
    var onSteps: ((PaceSlot, Int) -> Void)?
    private var origins: [PaceSlot: Date] = [:]
    private var timer: Timer?
    #if !SURVEY_PLAYGROUND && canImport(CoreMotion)
    private let pedometer = CMPedometer()
    #endif

    func watch(_ slot: PaceSlot, from date: Date) {
        origins[slot] = date
        startTimer()
        poll()
    }

    func unwatch(_ slot: PaceSlot) {
        origins.removeValue(forKey: slot)
        if origins.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    func pause() {
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        guard !origins.isEmpty else { return }
        startTimer()
        poll()
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        let slots = origins
        #if !SURVEY_PLAYGROUND && canImport(CoreMotion)
        guard StepHardware.available else { return }
        for (slot, origin) in slots {
            pedometer.queryPedometerData(from: origin, to: Date()) { [weak self] data, _ in
                let steps = data?.numberOfSteps.intValue ?? 0
                DispatchQueue.main.async {
                    self?.onSteps?(slot, steps)
                }
            }
        }
        #else
        _ = slots
        #endif
    }
}
