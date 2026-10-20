import Foundation

/// 現場の範囲。中心と半径。外に出たら位置の共有は止める。
public struct SiteFence: Codable, Equatable, Sendable {
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var radiusMeters: Double

    public init(latitudeDegrees: Double, longitudeDegrees: Double, radiusMeters: Double) {
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.radiusMeters = radiusMeters
    }

    public func contains(latitude: Double, longitude: Double) -> Bool {
        guard radiusMeters > 0, radiusMeters.isFinite else { return false }
        guard let inverse = GRS80Geodesic.inverse(
            latitude1: latitudeDegrees,
            longitude1: longitudeDegrees,
            latitude2: latitude,
            longitude2: longitude
        ) else { return false }
        return inverse.distanceMeters <= radiusMeters
    }
}

/// 作業時間。開始は含み、終了は含まない。日付をまたがない。
public struct WorkHours: Codable, Equatable, Sendable {
    public var startHour: Int
    public var endHour: Int

    public init(startHour: Int, endHour: Int) {
        self.startHour = startHour
        self.endHour = endHour
    }

    public func contains(_ date: Date, timeZone: TimeZone = LocationPrivacy.tokyo) -> Bool {
        guard startHour >= 0, endHour <= 24, startHour < endHour else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let second = calendar.component(.second, from: date)
        let now = hour * 3600 + minute * 60 + second
        return now >= startHour * 3600 && now < endHour * 3600
    }
}

public struct ShareViewer: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var role: String

    public init(id: String, name: String, role: String) {
        self.id = id
        self.name = name
        self.role = role
    }
}

public enum ShareState: Equatable, Sendable {
    case sharing
    case paused
    case outsideFence
    case outsideHours
    case unset
    case noFix

    public var shares: Bool { self == .sharing }

    public var label: String {
        switch self {
        case .sharing: return "位置を共有中"
        case .paused: return "休憩中。位置は共有していません。SOSと転倒は有効です。"
        case .outsideFence: return "現場の外なので、位置の共有を止めました。"
        case .outsideHours: return "作業時間の外なので、位置の共有を止めました。"
        case .unset: return "現場範囲か作業時間が未設定なので、位置は共有しません。"
        case .noFix: return "位置がまだ無いので、共有しません。"
        }
    }
}

/// 位置は現場の中と作業時間だけ。普段の軌跡は残さない。
public enum LocationPrivacy {
    public static let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? TimeZone(secondsFromGMT: 9 * 3600)!
    public static let ringSeconds: TimeInterval = 60
    public static let suggestedRadiusMeters = 300.0
    public static let minimumRadiusMeters = 50.0
    public static let maximumRadiusMeters = 5000.0
    public static let terms = "位置の共有は、同じ現場の安全のためです。勤怠管理にも、人事評価にも使いません。"
    public static let trackNote = "普段の軌跡は保存しません。端末の中に直前60秒だけ置き、インシデントのときだけ前後を記録に固定します。P510へ常時の軌跡は送りません。"
    public static let audienceNote = "見られるのは、同じプロジェクトで今つながっている端末だけです。一覧は、30秒以内に位置が届いている端末です。共有を止めると、新しい位置は送りません。"
    public static let safetyNote = "休憩中も、現場の外でも、SOSと転倒の検知は止めません。"

    public static func radiusMeters(_ value: Double) -> Double {
        guard value.isFinite else { return suggestedRadiusMeters }
        return min(maximumRadiusMeters, max(minimumRadiusMeters, value))
    }

    public static func gate(
        hasFix: Bool,
        latitude: Double,
        longitude: Double,
        at date: Date,
        fence: SiteFence?,
        hours: WorkHours?,
        paused: Bool
    ) -> ShareState {
        if paused { return .paused }
        guard let fence, let hours else { return .unset }
        guard hasFix else { return .noFix }
        guard fence.contains(latitude: latitude, longitude: longitude) else { return .outsideFence }
        guard hours.contains(date, timeZone: tokyo) else { return .outsideHours }
        return .sharing
    }

    /// 共有中だけ、今つながっている相手を返す。止まっているときは空。
    public static func viewers(sharing: Bool, peers: [ShareViewer]) -> [ShareViewer] {
        guard sharing else { return [] }
        return peers.sorted { $0.name < $1.name }
    }
}
