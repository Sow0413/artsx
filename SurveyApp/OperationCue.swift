import AudioToolbox
import Foundation
import SurveyCore
import UIKit

extension Notification.Name {
    static let surveyConfirmObservation = Notification.Name("survey.confirmObservation")
}

/// 確定できたときだけ、振動と音を返す。実機のマナーモードは未確認。
enum ConfirmCue {
    static func play(_ feedback: ConfirmFeedback) {
        guard feedback.haptic || feedback.sound else { return }
        #if !SURVEY_PLAYGROUND
        if feedback.haptic {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        if feedback.sound {
            AudioServicesPlaySystemSound(1104)
        }
        #else
        _ = feedback
        #endif
    }
}

/// 鉛直から ±1° に入ったとき、一度だけ振動する。実機は未確認。
enum LevelCue {
    static func play() {
        #if !SURVEY_PLAYGROUND
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}

/// 音量ボタン。慣れたら、かつ「画面を見ずに確定」がオンのときだけ。実機は未確認。
enum VolumeConfirmWatcher {
    static func start(_ onChange: @escaping () -> Void) {
        #if !SURVEY_PLAYGROUND && canImport(AVFoundation)
        VolumeBox.shared.start(onChange)
        #else
        _ = onChange
        #endif
    }

    static func stop() {
        #if !SURVEY_PLAYGROUND && canImport(AVFoundation)
        VolumeBox.shared.stop()
        #endif
    }
}

#if !SURVEY_PLAYGROUND && canImport(AVFoundation)
import AVFoundation

private final class VolumeBox: NSObject {
    static let shared = VolumeBox()
    private var onChange: () -> Void = {}
    private var last: Float = -1
    private var watching = false

    func start(_ onChange: @escaping () -> Void) {
        self.onChange = onChange
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        last = session.outputVolume
        guard !watching else { return }
        session.addObserver(self, forKeyPath: "outputVolume", options: [.new], context: nil)
        watching = true
    }

    func stop() {
        guard watching else { return }
        AVAudioSession.sharedInstance().removeObserver(self, forKeyPath: "outputVolume")
        watching = false
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == "outputVolume" else { return }
        let value = AVAudioSession.sharedInstance().outputVolume
        guard abs(value - last) > 0.001 else { return }
        last = value
        let cue = onChange
        DispatchQueue.main.async(execute: cue)
    }
}
#endif
