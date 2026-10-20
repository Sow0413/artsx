import Foundation
import SurveyCore

#if canImport(AVFoundation)
import AVFoundation
#endif

/// 受信した PCM を、話者の方向に置く。既定はオフ。PushToTalk のシステム再生は向けられない。実機は未確認。
final class RadioSpace {
    var enabled = false
    #if canImport(AVFoundation)
    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private let player = AVAudioPlayerNode()
    private var started = false
    private var failed = false
    #endif

    func place(_ point: TalkPoint) {
        #if canImport(AVFoundation)
        player.position = AVAudio3DPoint(x: point.x, y: point.y, z: point.z)
        #else
        _ = point
        #endif
    }

    func play(_ data: Data) {
        guard enabled else { return }
        #if canImport(AVFoundation)
        guard !failed else { return }
        guard let buffer = Self.buffer(from: data) else { return }
        if !started {
            guard start(format: buffer.format) else {
                failed = true
                return
            }
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying {
            player.play()
        }
        #else
        _ = data
        #endif
    }

    #if canImport(AVFoundation)
    private func start(format: AVAudioFormat) -> Bool {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
        )
        try? session.setActive(true)
        engine.attach(environment)
        engine.attach(player)
        engine.connect(player, to: environment, format: format)
        engine.connect(environment, to: engine.mainMixerNode, format: nil)
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)
        player.renderingAlgorithm = .HRTF
        do {
            try engine.start()
            started = true
            return true
        } catch {
            return false
        }
    }

    /// 16 kHz、16 bit、モノラルのリトルエンディアンを想定する。
    private static func buffer(from data: Data) -> AVAudioPCMBuffer? {
        guard data.count >= 2, data.count.isMultiple(of: 2) else { return nil }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) else { return nil }
        let frames = AVAudioFrameCount(data.count / 2)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        data.withUnsafeBytes { raw in
            guard let source = raw.bindMemory(to: Int16.self).baseAddress else { return }
            for index in 0..<Int(frames) {
                channel[index] = Float(Int16(littleEndian: source[index])) / 32_768
            }
        }
        return buffer
    }
    #endif
}
