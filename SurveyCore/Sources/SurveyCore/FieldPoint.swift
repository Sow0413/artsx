import Foundation

public enum FieldPointOrigin: String, Codable, Sendable, Equatable {
    case sima
    case list
    case arbitrary
}

/// grid は SIMA の北・東を、選んだ系で読み直す。geographic は緯度経度を動かさない。
public enum PlaneAnchor: String, Codable, Sendable, Equatable {
    case grid
    case geographic
}

public struct FieldPoint: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var northingMeters: Double
    public var eastingMeters: Double
    public var zone: Int
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    /// 地盤高 GL。
    public var groundLevelMeters: Double?
    /// 計画高・仕上がり FH。
    public var formationHeightMeters: Double?
    /// 種別のない標高。
    public var heightMeters: Double?
    /// 任意点で入れた計画高。
    public var designHeightMeters: Double?
    public var origin: FieldPointOrigin
    public var anchor: PlaneAnchor
    public var snapLabel: String?
    public var drawingX: Double?
    public var drawingY: Double?

    public init(
        id: String,
        name: String,
        northingMeters: Double,
        eastingMeters: Double,
        zone: Int,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        groundLevelMeters: Double? = nil,
        formationHeightMeters: Double? = nil,
        heightMeters: Double? = nil,
        designHeightMeters: Double? = nil,
        origin: FieldPointOrigin,
        anchor: PlaneAnchor,
        snapLabel: String? = nil,
        drawingX: Double? = nil,
        drawingY: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.northingMeters = northingMeters
        self.eastingMeters = eastingMeters
        self.zone = zone
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.groundLevelMeters = groundLevelMeters
        self.formationHeightMeters = formationHeightMeters
        self.heightMeters = heightMeters
        self.designHeightMeters = designHeightMeters
        self.origin = origin
        self.anchor = anchor
        self.snapLabel = snapLabel
        self.drawingX = drawingX
        self.drawingY = drawingY
    }

    /// 地図の札。FH があれば点名のうしろに付ける。
    public var mapLabel: String {
        if let formation = formationHeightMeters, formation.isFinite {
            return "\(name) \(Self.meters(formation))"
        }
        return name
    }

    public var bookHeightMeters: Double? {
        formationHeightMeters ?? designHeightMeters ?? groundLevelMeters ?? heightMeters
    }

    public static func meters(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    public func relocated(to newZone: Int) -> FieldPoint {
        var copy = self
        guard PlaneRectangular.zone(newZone) != nil, newZone != zone else { return copy }
        switch anchor {
        case .grid:
            guard let geo = PlaneRectangular.inverse(
                northingMeters: northingMeters,
                eastingMeters: eastingMeters,
                zone: newZone
            ) else { return copy }
            copy.zone = newZone
            copy.latitudeDegrees = geo.latitudeDegrees
            copy.longitudeDegrees = geo.longitudeDegrees
        case .geographic:
            guard let plane = PlaneRectangular.forward(
                latitudeDegrees: latitudeDegrees,
                longitudeDegrees: longitudeDegrees,
                zone: newZone
            ) else { return copy }
            copy.zone = newZone
            copy.northingMeters = plane.northingMeters
            copy.eastingMeters = plane.eastingMeters
        }
        return copy
    }
}

/// FH − GL。正なら盛土、負なら切土。
public struct CutFill: Equatable, Sendable {
    public var formationMeters: Double?
    public var groundMeters: Double?
    public var differenceMeters: Double?
    public var word: String?

    public init(formationMeters: Double?, groundMeters: Double?, differenceMeters: Double?, word: String?) {
        self.formationMeters = formationMeters
        self.groundMeters = groundMeters
        self.differenceMeters = differenceMeters
        self.word = word
    }

    public static func make(formation: Double?, ground: Double?) -> CutFill {
        let fh = formation.flatMap { $0.isFinite ? $0 : nil }
        let gl = ground.flatMap { $0.isFinite ? $0 : nil }
        guard let fh, let gl else {
            return CutFill(formationMeters: fh, groundMeters: gl, differenceMeters: nil, word: nil)
        }
        let delta = fh - gl
        let word: String
        if abs(delta) < 5e-4 {
            word = "0"
        } else if delta > 0 {
            word = "盛土"
        } else {
            word = "切土"
        }
        return CutFill(formationMeters: fh, groundMeters: gl, differenceMeters: delta, word: word)
    }

    public var differenceText: String? {
        guard let differenceMeters else { return nil }
        return String(format: "%+.3f", locale: Locale(identifier: "en_US_POSIX"), differenceMeters)
    }
}

public enum FieldPointStore {
    public static func load(projectName: String, at root: URL) -> [FieldPoint] {
        guard let directory = try? ProjectStore.projectDirectory(projectName, at: root) else { return [] }
        let url = directory.appendingPathComponent("座標簿", isDirectory: true).appendingPathComponent("取込.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([FieldPoint].self, from: data)) ?? []
    }

    public static func save(_ points: [FieldPoint], projectName: String, at root: URL) throws {
        let directory = try ProjectStore.projectDirectory(projectName, at: root)
        let folder = directory.appendingPathComponent("座標簿", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(points).write(to: folder.appendingPathComponent("取込.json"))
    }
}
