import Foundation

/// 現場で保持する座標系。平面直角や標高への変換は出口で一回だけ行う。
public enum CoordinateFrame: String, Sendable, Codable, Equatable {
    case wgs84ITRF = "WGS84/ITRF"
}

/// 精度の段階。つなぐ機械で上がる。バッジの色は、段階ではなく作業の要求精度で決める。
public enum PositionStage: Int, Sendable, Codable, Equatable, CaseIterable {
    /// 段階0。iPhone 単独。数m。下見と概略。
    case iphone = 0
    /// 段階1。CLAS。数cm〜10cm。
    case clas = 1
    /// 段階2。基地局または NTRIP の RTK。
    case rtk = 2
    /// 段階3。TS・レベル・UWB などとの併用。
    case hybrid = 3
}

/// 受信機が報告した解の種類。
public enum FixQuality: String, Sendable, Codable, Equatable {
    case none
    /// 単独測位。iPhone GPS は常にこれ。
    case standalone
    case dgps
    /// RTK Float。報告精度が要求以内なら緑になり得る。測設の合格にはしない。
    case float
    /// RTK Fix。外部受信機が報告し、作業の要求も満たすときだけ測設の合格にする。
    case rtkFix
    /// CLAS の収束。Fix ではない。
    case clas
}

/// 位置を出した機器。iPhone の GPS は、精度の数値が良くても外部受信機ではない。
public enum ReceiverKind: String, Sendable, Codable, Equatable {
    case iphoneGPS
    case clas
    case rtk
    case totalStation
    case level
    case uwb
}

/// 内部保持の1点。緯度・経度・楕円体高。測地系の切り替えは持たない。
public struct GeodeticPosition: Sendable, Equatable, Codable {
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var ellipsoidalHeightMeters: Double?
    public var horizontalAccuracyMeters: Double
    public var verticalAccuracyMeters: Double?
    public var timestamp: Date
    public var stage: PositionStage
    public var fixQuality: FixQuality
    public var receiver: ReceiverKind
    public var frame: CoordinateFrame

    public init(
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        ellipsoidalHeightMeters: Double?,
        horizontalAccuracyMeters: Double,
        verticalAccuracyMeters: Double?,
        timestamp: Date,
        stage: PositionStage,
        fixQuality: FixQuality,
        receiver: ReceiverKind,
        frame: CoordinateFrame = .wgs84ITRF
    ) {
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.ellipsoidalHeightMeters = ellipsoidalHeightMeters
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.verticalAccuracyMeters = verticalAccuracyMeters
        self.timestamp = timestamp
        self.stage = stage
        self.fixQuality = fixQuality
        self.receiver = receiver
        self.frame = frame
    }

    public var isPlottable: Bool {
        latitudeDegrees.isFinite
            && longitudeDegrees.isFinite
            && abs(latitudeDegrees) <= 90
            && abs(longitudeDegrees) <= 180
    }

    /// CoreLocation は無効な精度を負の数で返す。
    public var hasValidHorizontalAccuracy: Bool {
        horizontalAccuracyMeters.isFinite && horizontalAccuracyMeters >= 0
    }

    /// 外部受信機が RTK Fix を報告している。iPhone と CLAS は通らない。
    public var isTrustedRTKFix: Bool {
        guard hasValidHorizontalAccuracy, isPlottable else { return false }
        guard fixQuality == .rtkFix else { return false }
        guard receiver != .iphoneGPS else { return false }
        guard stage == .rtk || stage == .hybrid else { return false }
        return true
    }
}
