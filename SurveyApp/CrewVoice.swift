import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

/// 方向の読み上げ。オフが既定。実機の声は未確認。
enum CrewVoice {
    static func say(_ text: String) {
        #if canImport(AVFoundation)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = 0.5
        speaker.speak(utterance)
        #else
        _ = text
        #endif
    }

    #if canImport(AVFoundation)
    private static let speaker = AVSpeechSynthesizer()
    #endif
}
