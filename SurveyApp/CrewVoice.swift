import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

/// 方向の読み上げ。イヤホンと車の Bluetooth へも流す。読み上げは止めない。実機の声は未確認。
enum CrewVoice {
    static func say(_ text: String) {
        #if canImport(AVFoundation)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
        )
        try? session.setActive(true)
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
