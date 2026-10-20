import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

enum HiyariHook {
    static var fire: () -> Void = {}
}

/// 確定前の音声メモ。実機のマイクは未確認。
enum IncidentVoiceMemo {
    static var isRecording: Bool {
        #if canImport(AVFoundation)
        return recorder?.isRecording == true
        #else
        return false
        #endif
    }

    static func toggle() -> Data? {
        #if canImport(AVFoundation)
        if let recorder, recorder.isRecording {
            recorder.stop()
            let url = recorder.url
            self.recorder = nil
            return try? Data(contentsOf: url)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hiyari-\(UUID().uuidString).caf")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
        )
        try? session.setActive(true)
        guard let created = try? AVAudioRecorder(url: url, settings: settings) else { return nil }
        recorder = created
        created.record()
        return nil
        #else
        return nil
        #endif
    }

    #if canImport(AVFoundation)
    private static var recorder: AVAudioRecorder?
    #endif
}
