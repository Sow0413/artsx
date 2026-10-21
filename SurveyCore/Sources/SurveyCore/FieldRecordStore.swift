import Foundation

/// 記録ボタンが残す1点。出す画面は座標簿を使う。これは Documents 上の控え。
public struct FieldPointFile: Codable, Equatable, Sendable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var ellipsoidalHeightMeters: Double?
    /// 標高。楕円体高からジオイド高を引いた値。
    public var orthometricHeightMeters: Double?
    /// 使ったジオイド。詳細記録に残す。
    public var geoidModel: String?
    public var horizontalAccuracyMeters: Double?
    public var verticalAccuracyMeters: Double?
    public var timestamp: Date
    /// iPhone の平均。RTK ではない。
    public var phoneAverage: PhoneAverageStamp?
    /// iPhone の既知点合わせ。受信機の点には付けない。
    public var knownShift: KnownShiftStamp?

    public init(
        name: String,
        latitude: Double,
        longitude: Double,
        ellipsoidalHeightMeters: Double?,
        orthometricHeightMeters: Double? = nil,
        geoidModel: String? = nil,
        horizontalAccuracyMeters: Double?,
        verticalAccuracyMeters: Double?,
        timestamp: Date,
        phoneAverage: PhoneAverageStamp? = nil,
        knownShift: KnownShiftStamp? = nil
    ) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.ellipsoidalHeightMeters = ellipsoidalHeightMeters
        self.orthometricHeightMeters = orthometricHeightMeters
        self.geoidModel = geoidModel
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.verticalAccuracyMeters = verticalAccuracyMeters
        self.timestamp = timestamp
        self.phoneAverage = phoneAverage
        self.knownShift = knownShift
    }
}

/// 今日の記録を地図に出す1点。番号は同じ日の時刻順。
public struct FieldRecordPin: Equatable, Sendable {
    public var number: Int
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var place: String
    public var day: String
    public var fileURL: URL

    public init(
        number: Int,
        name: String,
        latitude: Double,
        longitude: Double,
        place: String,
        day: String,
        fileURL: URL
    ) {
        self.number = number
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.place = place
        self.day = day
        self.fileURL = fileURL
    }

    public var caption: String {
        "記録 #\(number) ・\(place)/\(day)"
    }

    public var folderURL: URL {
        fileURL.deletingLastPathComponent()
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

    /// その場所の日付フォルダ。空の場所は空。
    public static func dayFolders(in root: URL, place raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        let folder = root.appendingPathComponent(placeFolder(trimmed, latitude: 0, longitude: 0), isDirectory: true)
        guard let days = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return days.compactMap { url in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
            let name = url.lastPathComponent
            guard name.count == 10 else { return nil }
            return name
        }.sorted()
    }

    /// 現場の記録。place が空なら全部。day があればその日付だけ。ゴミ箱は含めない。
    public static func points(in root: URL, place: String?, day: String? = nil) -> [FieldRecordPin] {
        let manager = FileManager.default
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let placeName = place?.trimmingCharacters(in: .whitespacesAndNewlines)
        let places: [URL]
        if let placeName, !placeName.isEmpty {
            places = [root.appendingPathComponent(placeFolder(placeName, latitude: 0, longitude: 0), isDirectory: true)]
        } else if let found = try? manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            places = found
        } else {
            return []
        }
        var found = collected(in: root, place: place, day: day, places: places, decoder: decoder)
        found.sort { lhs, rhs in
            if lhs.point.timestamp != rhs.point.timestamp {
                return lhs.point.timestamp > rhs.point.timestamp
            }
            return lhs.point.name < rhs.point.name
        }
        var seen: Set<String> = []
        var pins: [FieldRecordPin] = []
        for item in found where seen.insert(item.point.name).inserted {
            pins.append(FieldRecordPin(
                number: pins.count + 1,
                name: item.point.name,
                latitude: item.point.latitude,
                longitude: item.point.longitude,
                place: item.place,
                day: item.day,
                fileURL: item.url
            ))
        }
        return pins
    }

    /// 同じ点名の記録ファイル。一覧は新しい1件だけ出すので、削除では残りもまとめて移す。
    public static func files(named name: String, in root: URL, place: String?, day: String? = nil) -> [URL] {
        collected(in: root, place: place, day: day)
            .filter { $0.point.name == name }
            .map(\.url)
    }

    public static func relativePath(of file: URL, root: URL) -> String {
        let path = resolvedPath(file)
        let rootPath = resolvedPath(root)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return file.lastPathComponent
    }

    public static func moveToTrash(_ file: URL, id: UUID, index: Int, root: URL) throws {
        let folder = trashFolder(id: id, root: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = folder.appendingPathComponent("\(index).json")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: file, to: dest)
    }

    public static func restoreTrashFile(id: UUID, index: Int, root: URL, relativePath: String) throws {
        let source = trashFolder(id: id, root: root).appendingPathComponent("\(index).json")
        let dest = url(root: root, relativePath: relativePath)
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: source, to: dest)
    }

    public static func removeTrashFolder(id: UUID, root: URL) {
        try? FileManager.default.removeItem(at: trashFolder(id: id, root: root))
    }

    /// その日の記録だけ。場所フォルダを横断し、時刻順に 1 から番号を振る。
    public static func pins(in root: URL, on day: Date, calendar: Calendar = .current) -> [FieldRecordPin] {
        let dayName = dayFolder(day, calendar: calendar)
        let manager = FileManager.default
        guard let places = try? manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var found: [(point: FieldPointFile, place: String, url: URL)] = []
        for placeURL in places {
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: placeURL.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            let folder = placeURL.appendingPathComponent(dayName, isDirectory: true)
            guard let files = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                continue
            }
            for file in files where file.pathExtension.lowercased() == "json" {
                guard let data = try? Data(contentsOf: file),
                      let point = try? decoder.decode(FieldPointFile.self, from: data) else { continue }
                found.append((point, placeURL.lastPathComponent, file))
            }
        }
        found.sort { lhs, rhs in
            if lhs.point.timestamp != rhs.point.timestamp {
                return lhs.point.timestamp < rhs.point.timestamp
            }
            return lhs.point.name < rhs.point.name
        }
        return found.enumerated().map { index, item in
            FieldRecordPin(
                number: index + 1,
                name: item.point.name,
                latitude: item.point.latitude,
                longitude: item.point.longitude,
                place: item.place,
                day: dayName,
                fileURL: item.url
            )
        }
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

    private static func trashFolder(id: UUID, root: URL) -> URL {
        for name in [".Trash", ".trash"] {
            let existing = root.appendingPathComponent(name, isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
            if FileManager.default.fileExists(atPath: existing.path) { return existing }
        }
        return root.appendingPathComponent(".Trash", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// macOS の一時ディレクトリは `/var` から `/private/var` へのリンクになる。比べる前に両方を解く。
    private static func resolvedPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().path
    }

    /// `appendingPathComponent` は `/` をフォルダ区切りにせず、1つの名前へエンコードする。
    private static func url(root: URL, relativePath: String) -> URL {
        let parts = relativePath.split(separator: "/").map(String.init).filter { $0 != "." && $0 != ".." }
        return parts.reduce(root) { $0.appendingPathComponent($1) }
    }

    private static func collected(
        in root: URL,
        place: String?,
        day: String?,
        places given: [URL]? = nil,
        decoder givenDecoder: JSONDecoder? = nil
    ) -> [(point: FieldPointFile, place: String, day: String, url: URL)] {
        let manager = FileManager.default
        let decoder = givenDecoder ?? {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return decoder
        }()
        let places = given ?? {
            let placeName = place?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let placeName, !placeName.isEmpty {
                return [root.appendingPathComponent(placeFolder(placeName, latitude: 0, longitude: 0), isDirectory: true)]
            }
            return (try? manager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        }()
        var found: [(point: FieldPointFile, place: String, day: String, url: URL)] = []
        for placeURL in places {
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: placeURL.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            let days = (try? manager.contentsOfDirectory(
                at: placeURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for dayURL in days {
                let dayName = dayURL.lastPathComponent
                guard day == nil || day == dayName else { continue }
                guard let files = try? manager.contentsOfDirectory(at: dayURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                    continue
                }
                for file in files where file.pathExtension.lowercased() == "json" {
                    guard let data = try? Data(contentsOf: file),
                          let point = try? decoder.decode(FieldPointFile.self, from: data) else { continue }
                    found.append((point, placeURL.lastPathComponent, dayName, file))
                }
            }
        }
        return found
    }

    private static let posix = Locale(identifier: "en_US_POSIX")
}
