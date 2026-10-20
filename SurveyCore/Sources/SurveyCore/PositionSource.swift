import Foundation

public enum PositionAvailability: String, Sendable, Codable, Equatable {
    case waiting
    case available
    case denied
    case unavailable
}

public struct PositionReading: Sendable, Equatable {
    public var position: GeodeticPosition?
    public var availability: PositionAvailability

    public init(position: GeodeticPosition?, availability: PositionAvailability) {
        self.position = position
        self.availability = availability
    }

    public static let waiting = PositionReading(position: nil, availability: .waiting)
}

/// 位置の出どころ。iPhone、CLAS、RTK は同じ読み方で画面に入る。
/// このスライスで実装するのは iPhone（アプリ側）と模擬（プレビューとテスト）だけ。
public protocol PositionSource: AnyObject {
    var receiver: ReceiverKind { get }
    var stage: PositionStage { get }
    var readings: AsyncStream<PositionReading> { get }
    func start()
    func stop()
}

/// CoreLocation の数値を段階0に固定する。精度が良く見えても RTK Fix にはしない。
public enum IPhonePosition {
    public static func make(
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        ellipsoidalHeightMeters: Double?,
        horizontalAccuracyMeters: Double,
        verticalAccuracyMeters: Double?,
        timestamp: Date
    ) -> GeodeticPosition {
        GeodeticPosition(
            latitudeDegrees: latitudeDegrees,
            longitudeDegrees: longitudeDegrees,
            ellipsoidalHeightMeters: ellipsoidalHeightMeters,
            horizontalAccuracyMeters: horizontalAccuracyMeters,
            verticalAccuracyMeters: verticalAccuracyMeters,
            timestamp: timestamp,
            stage: .iphone,
            fixQuality: .standalone,
            receiver: .iphoneGPS,
            frame: .wgs84ITRF
        )
    }
}
