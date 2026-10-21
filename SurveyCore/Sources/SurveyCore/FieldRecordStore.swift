import Foundation

/// 記録ボタンが残す1点。出す画面は座標簿を使う。これは Documents 上の控え。
public struct FieldPointFile: Codable, Equatable, Sendable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var ellipsoidalHeightMeters: Double?
    public var horizontalAccuracyMeters: Double?
    public var verticalAccuracyMeters: Double?
    public var timestamp: Date

    public init(
        name: String,
        latitude: Double,
        longitude: Double,
        ellipsoidalHeightMeters: Double?,
        horizontalAccuracyMeters: Double?,
        verticalAccuracyMeters: Double?,
        timestamp: Date
    ) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.ellipsoidalHeightMeters = ellipsoidalHeightMeters
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.verticalAccuracyMeters = verticalAccuracyMeters
        self.timestamp = timestamp
    }
}

public enum FieldRecordStore {
    public static func coordinatePlace(latitude: Double, longitude: Double) -> String {
        String(format: "%.2f_%.2f", locale: posix, latitude, longitude)
    }

    /// フォルダ名に使えない文字を除く。空なら座標の丸めに戻す。
    public static func placeFolder(_ raw: String, latitude: Double, longitude: Double) -> String {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "・")
            .replacingOccurrences(of: "\\", with: "・")
            .replacingOccurrences(of: ":", with: "・")
        let trimmed = String(cleaned.prefix(40)).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return coordinatePlace(latitude: latitude, longitude: longitude)
        }
        return trimmed
    }

    public static func dayFolder(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func directory(root: URL, place: String, day: Date, calendar: Calendar = .current) -> URL {
        root
            .appendingPathComponent(place, isDirectory: true)
            .appendingPathComponent(dayFolder(day, calendar: calendar), isDirectory: true)
    }

    @discardableResult
    public static func write(
        _ point: FieldPointFile,
        root: URL,
        place: String,
        calendar: Calendar = .current
    ) throws -> URL {
        let folderName = placeFolder(place, latitude: point.latitude, longitude: point.longitude)
        let folder = directory(root: root, place: folderName, day: point.timestamp, calendar: calendar)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName(for: point, calendar: calendar))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(point).write(to: url, options: .atomic)
        return url
    }

    static func fileName(for point: FieldPointFile, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: point.timestamp)
        let clock = String(format: "%02d%02d%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        let stem = point.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let trimmed = stem.isEmpty ? "point" : stem
        return "\(trimmed)-\(clock).json"
    }

    private static let posix = Locale(identifier: "en_US_POSIX")
}
