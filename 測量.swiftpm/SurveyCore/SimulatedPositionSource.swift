import Foundation

/// プレビューとテスト用。機器の代わりに台本の位置を流す。
public final class SimulatedPositionSource: PositionSource, @unchecked Sendable {
    public let receiver: ReceiverKind
    public let stage: PositionStage
    public let script: [PositionReading]
    public let readings: AsyncStream<PositionReading>
    private let continuation: AsyncStream<PositionReading>.Continuation
    private let lock = NSLock()
    private var didStart = false

    public init(script: [PositionReading], receiver: ReceiverKind, stage: PositionStage) {
        self.script = script
        self.receiver = receiver
        self.stage = stage
        let pair = AsyncStream<PositionReading>.makeStream()
        self.readings = pair.stream
        self.continuation = pair.continuation
    }

    public func start() {
        lock.lock()
        let shouldYield = !didStart
        didStart = true
        lock.unlock()
        guard shouldYield else { return }
        for reading in script {
            continuation.yield(reading)
        }
    }

    public func stop() {
        continuation.finish()
    }

    public func emit(_ reading: PositionReading) {
        continuation.yield(reading)
    }
}

public extension SimulatedPositionSource {
    /// モックと同じ東京付近。水平 3.2m なので表示は「約3m」。
    static func iphonePreview() -> SimulatedPositionSource {
        let position = GeodeticPosition(
            latitudeDegrees: 35.68123,
            longitudeDegrees: 139.76712,
            ellipsoidalHeightMeters: 12.4,
            horizontalAccuracyMeters: 3.2,
            verticalAccuracyMeters: 8,
            timestamp: PreviewClock.instant,
            stage: .iphone,
            fixQuality: .standalone,
            receiver: .iphoneGPS
        )
        return SimulatedPositionSource(
            script: [PositionReading(position: position, availability: .available)],
            receiver: .iphoneGPS,
            stage: .iphone
        )
    }

    static func clasPreview() -> SimulatedPositionSource {
        let position = GeodeticPosition(
            latitudeDegrees: 35.68123,
            longitudeDegrees: 139.76712,
            ellipsoidalHeightMeters: 12.4,
            horizontalAccuracyMeters: 0.05,
            verticalAccuracyMeters: 0.12,
            timestamp: PreviewClock.instant,
            stage: .clas,
            fixQuality: .clas,
            receiver: .clas
        )
        return SimulatedPositionSource(
            script: [PositionReading(position: position, availability: .available)],
            receiver: .clas,
            stage: .clas
        )
    }

    static func rtkFixPreview() -> SimulatedPositionSource {
        let position = GeodeticPosition(
            latitudeDegrees: 35.68123,
            longitudeDegrees: 139.76712,
            ellipsoidalHeightMeters: 12.4,
            horizontalAccuracyMeters: 0.02,
            verticalAccuracyMeters: 0.03,
            timestamp: PreviewClock.instant,
            stage: .rtk,
            fixQuality: .rtkFix,
            receiver: .rtk
        )
        return SimulatedPositionSource(
            script: [PositionReading(position: position, availability: .available)],
            receiver: .rtk,
            stage: .rtk
        )
    }
}

public enum PreviewClock {
    /// 2026-10-20 00:00 UTC。プレビューとテストで固定する。
    public static let instant = Date(timeIntervalSince1970: 1_792_454_400)
}
