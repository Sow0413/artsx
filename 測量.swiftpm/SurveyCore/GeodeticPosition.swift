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
public enum ReceiverKind: String, Sendable, Codable, Equatable, CaseIterable {
    case iphoneGPS
    case clas
    case rtk
    case totalStation
    case level
    case uwb

    public var label: String {
        switch self {
        case .iphoneGPS: return "iPhone"
        case .clas: return "CLAS"
        case .rtk: return "RTK"
        case .totalStation: return "TS"
        case .level: return "レベル"
        case .uwb: return "UWB"
        }
    }
}

public enum SatelliteSystem: String, Codable, Sendable, Equatable, CaseIterable {
    case gps
    case glonass
    case galileo
    case qzss
    case beidou

    public var label: String {
        switch self {
        case .gps: return "GPS"
        case .glonass: return "GLONASS"
        case .galileo: return "Galileo"
        case .qzss: return "QZSS"
        case .beidou: return "BeiDou"
        }
    }
}

public struct SatelliteCount: Codable, Sendable, Equatable {
    public var system: SatelliteSystem
    public var count: Int

    public init(system: SatelliteSystem, count: Int) {
        self.system = system
        self.count = count
    }
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
    /// 受信機が報告した衛星数。iPhone の CoreLocation には無いので、無いときは nil。
    public var satelliteCount: Int?
    /// 系統ごとの衛星数。無い受信機は nil。
    public var satellites: [SatelliteCount]?
    public var pdop: Double?
    /// 補正が届いてからの秒。補正が無いときは nil。
    public var correctionAgeSeconds: Double?
    /// VRS、基地局名など、補正の出どころ。
    public var correctionSource: String?
    /// 進行方向。北から時計回り。止まっている、または不明なときは nil。
    public var courseDegrees: Double?
    /// 端末の方位。北から時計回り。コンパスが無いときは nil。
    public var headingDegrees: Double?

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
        frame: CoordinateFrame = .wgs84ITRF,
        satelliteCount: Int? = nil,
        satellites: [SatelliteCount]? = nil,
        pdop: Double? = nil,
        correctionAgeSeconds: Double? = nil,
        correctionSource: String? = nil,
        courseDegrees: Double? = nil,
        headingDegrees: Double? = nil
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
        self.satelliteCount = satelliteCount
        self.satellites = satellites
        self.pdop = pdop
        self.correctionAgeSeconds = correctionAgeSeconds
        self.correctionSource = correctionSource
        self.courseDegrees = courseDegrees
        self.headingDegrees = headingDegrees
    }

    /// バッジに常時出す解の文字。iPhone が Fix と名乗っても単独。外部の DGPS は DGPS。
    public var solutionLabel: String {
        if receiver == .iphoneGPS { return "単独" }
        switch fixQuality {
        case .rtkFix: return receiver == .clas ? "CLAS" : "FIX"
        case .float: return "FLOAT"
        case .clas: return "CLAS"
        case .dgps: return "DGPS"
        case .standalone, .none: return "単独"
        }
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
