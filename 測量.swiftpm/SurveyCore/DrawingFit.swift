import Foundation

/// 図面の上の点。DXF の X を x、Y を y とする。画面では右が x、上が y。
public struct PlanarPoint: Sendable, Equatable, Codable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to other: PlanarPoint) -> Double {
        GeoMath.hypotenuse(x - other.x, y - other.y)
    }
}

public struct Segment2D: Sendable, Equatable, Codable {
    public var start: PlanarPoint
    public var end: PlanarPoint

    public init(start: PlanarPoint, end: PlanarPoint) {
        self.start = start
        self.end = end
    }

    public var length: Double { start.distance(to: end) }
}

/// DXF の軸の読み方。手合わせの変換とは別に、数値をそのまま公共座標と読むときに使う。
public enum DrawingAxis: String, Codable, Sendable, Equatable, CaseIterable {
    /// CAD の普通の向き。ファイルの X が東（告示の Y）、Y が北（告示の X）。
    case cadEastNorth
    /// 測量の数値をそのまま書いたもの。ファイルの X が北、Y が東。
    case surveyNorthEast

    public var label: String {
        switch self {
        case .cadEastNorth: return "X が東、Y が北"
        case .surveyNorthEast: return "X が北、Y が東"
        }
    }

    public func plane(drawingX: Double, drawingY: Double) -> (easting: Double, northing: Double) {
        switch self {
        case .cadEastNorth: return (drawingX, drawingY)
        case .surveyNorthEast: return (drawingY, drawingX)
        }
    }

    public func drawing(easting: Double, northing: Double) -> PlanarPoint {
        switch self {
        case .cadEastNorth: return PlanarPoint(x: easting, y: northing)
        case .surveyNorthEast: return PlanarPoint(x: northing, y: easting)
        }
    }
}

/// 図面の点を、平面の東・北（メートル）へ写す相似変換。移動、回転、縮尺。
/// 出力の x は東、y は北。反転は入れない。
public struct Similarity2D: Sendable, Equatable, Codable {
    public var scale: Double
    public var rotationDegrees: Double
    /// 東方向の移動。メートル。
    public var translationEasting: Double
    /// 北方向の移動。メートル。
    public var translationNorthing: Double

    public init(scale: Double, rotationDegrees: Double, translationEasting: Double, translationNorthing: Double) {
        self.scale = scale
        self.rotationDegrees = rotationDegrees
        self.translationEasting = translationEasting
        self.translationNorthing = translationNorthing
    }

    public static let identity = Similarity2D(scale: 1, rotationDegrees: 0, translationEasting: 0, translationNorthing: 0)

    public func apply(_ point: PlanarPoint) -> PlanarPoint {
        let radians = GeoMath.radians(fromDegrees: rotationDegrees)
        let cosR = GeoMath.cosine(radians)
        let sinR = GeoMath.sine(radians)
        return PlanarPoint(
            x: scale * (cosR * point.x - sinR * point.y) + translationEasting,
            y: scale * (sinR * point.x + cosR * point.y) + translationNorthing
        )
    }

    public func inverse(_ point: PlanarPoint) -> PlanarPoint? {
        guard scale.isFinite, abs(scale) > 1e-15 else { return nil }
        let radians = GeoMath.radians(fromDegrees: rotationDegrees)
        let cosR = GeoMath.cosine(radians)
        let sinR = GeoMath.sine(radians)
        let dx = (point.x - translationEasting) / scale
        let dy = (point.y - translationNorthing) / scale
        return PlanarPoint(x: cosR * dx + sinR * dy, y: -sinR * dx + cosR * dy)
    }
}

public struct SimilarityFit: Sendable, Equatable {
    public var transform: Similarity2D
    /// 対応点ごとの残差。メートル。並びは入力と同じ。
    public var residualsMeters: [Double]
    public var rmsMeters: Double

    public init(transform: Similarity2D, residualsMeters: [Double], rmsMeters: Double) {
        self.transform = transform
        self.residualsMeters = residualsMeters
        self.rmsMeters = rmsMeters
    }
}

public enum SimilaritySolver {
    /// 2点以上。点が重なると nil。縮尺を固定するときは 1（図面の 1 が 1 m）。
    public static func fit(_ pairs: [(source: PlanarPoint, target: PlanarPoint)], lockScale: Bool) -> SimilarityFit? {
        guard pairs.count >= 2 else { return nil }
        guard pairs.allSatisfy({ $0.source.x.isFinite && $0.source.y.isFinite && $0.target.x.isFinite && $0.target.y.isFinite }) else {
            return nil
        }
        let count = Double(pairs.count)
        let sourceCenter = centroid(pairs.map(\.source))
        let targetCenter = centroid(pairs.map(\.target))
        var dot = 0.0
        var cross = 0.0
        var sourceSpread = 0.0
        for pair in pairs {
            let px = pair.source.x - sourceCenter.x
            let py = pair.source.y - sourceCenter.y
            let qx = pair.target.x - targetCenter.x
            let qy = pair.target.y - targetCenter.y
            dot += px * qx + py * qy
            cross += px * qy - py * qx
            sourceSpread += px * px + py * py
        }
        guard sourceSpread > 1e-12 else { return nil }
        let rotation = GeoMath.arctangent(cross, dot)
        let cosR = GeoMath.cosine(rotation)
        let sinR = GeoMath.sine(rotation)
        let scale = lockScale ? 1 : (dot * cosR + cross * sinR) / sourceSpread
        guard scale.isFinite, abs(scale) > 1e-15 else { return nil }
        let rotatedX = cosR * sourceCenter.x - sinR * sourceCenter.y
        let rotatedY = sinR * sourceCenter.x + cosR * sourceCenter.y
        let transform = Similarity2D(
            scale: scale,
            rotationDegrees: GeoMath.degrees(fromRadians: rotation),
            translationEasting: targetCenter.x - scale * rotatedX,
            translationNorthing: targetCenter.y - scale * rotatedY
        )
        let residuals = pairs.map { pair in
            transform.apply(pair.source).distance(to: pair.target)
        }
        let rms = GeoMath.squareRoot(residuals.reduce(0) { $0 + $1 * $1 } / count)
        return SimilarityFit(transform: transform, residualsMeters: residuals, rmsMeters: rms)
    }

    private static func centroid(_ points: [PlanarPoint]) -> PlanarPoint {
        let count = Double(points.count)
        let x = points.reduce(0) { $0 + $1.x } / count
        let y = points.reduce(0) { $0 + $1.y } / count
        return PlanarPoint(x: x, y: y)
    }
}

public enum AlignmentTargetKind: String, Codable, Sendable, Equatable {
    case map
    case gnss
    case coordinateBook
}

public struct AlignmentPair: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    public var drawingX: Double
    public var drawingY: Double
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var kind: AlignmentTargetKind
    public var label: String

    public init(
        id: String = UUID().uuidString,
        drawingX: Double,
        drawingY: Double,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        kind: AlignmentTargetKind,
        label: String
    ) {
        self.id = id
        self.drawingX = drawingX
        self.drawingY = drawingY
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.kind = kind
        self.label = label
    }

    public var drawingPoint: PlanarPoint { PlanarPoint(x: drawingX, y: drawingY) }
}

public enum AlignmentAccuracy: String, Codable, Sendable, Equatable {
    case mapGrade = "地図並み（m）"
    case coordinateBook = "座標簿"

    public static let stakeoutNotice = "測設では座標簿の点で合わせ直してください。"

    public static func decide(_ kinds: [AlignmentTargetKind]) -> AlignmentAccuracy {
        guard !kinds.isEmpty, kinds.allSatisfy({ $0 == .coordinateBook }) else { return .mapGrade }
        return .coordinateBook
    }

    public var notice: String? {
        self == .mapGrade ? Self.stakeoutNotice : nil
    }
}

public struct AlignmentRecord: Sendable, Equatable, Codable, Identifiable {
    public var name: String
    public var version: Int
    public var createdAt: Date
    public var zone: Int
    public var axis: DrawingAxis
    public var lockScale: Bool
    public var transform: Similarity2D
    public var pairs: [AlignmentPair]
    public var residualsMeters: [Double]
    public var rmsMeters: Double
    public var accuracyTag: AlignmentAccuracy
    public var stakeoutNotice: String?
    public var drawingFileName: String
    /// true のとき、変換は軸で読んだ公共座標の上に載せる。手合わせは false で、図面の X Y を直接写す。
    public var composesAxis: Bool

    public var id: String { "\(name)-v\(version)" }

    public init(
        name: String,
        version: Int,
        createdAt: Date,
        zone: Int,
        axis: DrawingAxis,
        lockScale: Bool,
        transform: Similarity2D,
        pairs: [AlignmentPair],
        residualsMeters: [Double],
        rmsMeters: Double,
        accuracyTag: AlignmentAccuracy,
        stakeoutNotice: String?,
        drawingFileName: String,
        composesAxis: Bool = false
    ) {
        self.name = name
        self.version = version
        self.createdAt = createdAt
        self.zone = zone
        self.axis = axis
        self.lockScale = lockScale
        self.transform = transform
        self.pairs = pairs
        self.residualsMeters = residualsMeters
        self.rmsMeters = rmsMeters
        self.accuracyTag = accuracyTag
        self.stakeoutNotice = stakeoutNotice
        self.drawingFileName = drawingFileName
        self.composesAxis = composesAxis
    }

    private enum CodingKeys: String, CodingKey {
        case name, version, createdAt, zone, axis, lockScale, transform, pairs
        case residualsMeters, rmsMeters, accuracyTag, stakeoutNotice, drawingFileName, composesAxis
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(Int.self, forKey: .version)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        zone = try container.decode(Int.self, forKey: .zone)
        axis = try container.decode(DrawingAxis.self, forKey: .axis)
        lockScale = try container.decode(Bool.self, forKey: .lockScale)
        transform = try container.decode(Similarity2D.self, forKey: .transform)
        pairs = try container.decode([AlignmentPair].self, forKey: .pairs)
        residualsMeters = try container.decode([Double].self, forKey: .residualsMeters)
        rmsMeters = try container.decode(Double.self, forKey: .rmsMeters)
        accuracyTag = try container.decode(AlignmentAccuracy.self, forKey: .accuracyTag)
        stakeoutNotice = try container.decodeIfPresent(String.self, forKey: .stakeoutNotice)
        drawingFileName = try container.decode(String.self, forKey: .drawingFileName)
        composesAxis = try container.decodeIfPresent(Bool.self, forKey: .composesAxis) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(version, forKey: .version)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(zone, forKey: .zone)
        try container.encode(axis, forKey: .axis)
        try container.encode(lockScale, forKey: .lockScale)
        try container.encode(transform, forKey: .transform)
        try container.encode(pairs, forKey: .pairs)
        try container.encode(residualsMeters, forKey: .residualsMeters)
        try container.encode(rmsMeters, forKey: .rmsMeters)
        try container.encode(accuracyTag, forKey: .accuracyTag)
        try container.encodeIfPresent(stakeoutNotice, forKey: .stakeoutNotice)
        try container.encode(drawingFileName, forKey: .drawingFileName)
        try container.encode(composesAxis, forKey: .composesAxis)
    }
}

public enum AlignmentSolver {
    /// 対応点の緯度経度を、選んだ系の東・北に直してから相似変換する。
    public static func fit(pairs: [AlignmentPair], zone: Int, lockScale: Bool) -> SimilarityFit? {
        var mapped: [(source: PlanarPoint, target: PlanarPoint)] = []
        for pair in pairs {
            guard let plane = PlaneRectangular.forward(
                latitudeDegrees: pair.latitudeDegrees,
                longitudeDegrees: pair.longitudeDegrees,
                zone: zone
            ) else { return nil }
            mapped.append((
                pair.drawingPoint,
                PlanarPoint(x: plane.eastingMeters, y: plane.northingMeters)
            ))
        }
        return SimilaritySolver.fit(mapped, lockScale: lockScale)
    }
}

public struct ZoneCandidate: Sendable, Equatable, Identifiable {
    public var zone: Int
    public var axis: DrawingAxis
    /// 図面の数値と、その系の公共座標とのずれ。場所だけから出した候補では原点までの距離。
    public var rmsMeters: Double
    public var distanceMeters: Double
    public var matchesNumbers: Bool

    public var id: String { "\(zone)-\(axis.rawValue)-\(matchesNumbers)" }

    public init(zone: Int, axis: DrawingAxis, rmsMeters: Double, distanceMeters: Double, matchesNumbers: Bool) {
        self.zone = zone
        self.axis = axis
        self.rmsMeters = rmsMeters
        self.distanceMeters = distanceMeters
        self.matchesNumbers = matchesNumbers
    }
}

public struct ZoneSuggestion: Sendable, Equatable {
    /// 図面の数値が、その系の公共座標と直接そろったもの。
    public var fromDrawingNumbers: [ZoneCandidate]
    /// 対応点がある場所に、法令上合いそうな系。原点に近い順。
    public var forThisPlace: [ZoneCandidate]
    public var matchesDrawingNumbers: Bool

    public init(fromDrawingNumbers: [ZoneCandidate], forThisPlace: [ZoneCandidate], matchesDrawingNumbers: Bool) {
        self.fromDrawingNumbers = fromDrawingNumbers
        self.forThisPlace = forThisPlace
        self.matchesDrawingNumbers = matchesDrawingNumbers
    }
}

public struct ZoneWarning: Sendable, Equatable {
    public var message: String?
    public var distanceMeters: Double
    public var candidates: [ZoneCandidate]

    public init(message: String?, distanceMeters: Double, candidates: [ZoneCandidate]) {
        self.message = message
        self.distanceMeters = distanceMeters
        self.candidates = candidates
    }
}

public enum ZoneAdvisor {
    public static let farMeters = 20_000.0
    /// これよりずれが小さいとき、図面の数値はその系の公共座標とみる。
    public static let numberMatchMeters = 500.0

    public static func placement(
        drawingX: Double,
        drawingY: Double,
        zone: Int,
        axis: DrawingAxis,
        referenceLatitude: Double,
        referenceLongitude: Double,
        referenceName: String
    ) -> ZoneWarning {
        let ranked = rankInterpretations(
            drawingX: drawingX,
            drawingY: drawingY,
            referenceLatitude: referenceLatitude,
            referenceLongitude: referenceLongitude
        )
        let selected = ranked.first { $0.zone == zone && $0.axis == axis }
        let distance = selected?.distanceMeters ?? .infinity
        let nearer = ranked.filter { $0.distanceMeters + 1 < distance }.prefix(3)
        guard distance > farMeters else {
            return ZoneWarning(message: nil, distanceMeters: distance, candidates: Array(ranked.prefix(3)))
        }
        let lead = nearer.first
        let message: String
        if let lead, lead.distanceMeters <= farMeters {
            message = "\(zone)系（\(axis.label)）で重ねると、\(referenceName)から \(format(distance)) 離れています。合いそうなのは \(lead.zone)系（\(lead.axis.label)）です。"
        } else if let lead {
            message = "\(zone)系で重ねると、\(referenceName)から \(format(distance)) 離れています。いちばん近くても \(lead.zone)系で \(format(lead.distanceMeters)) です。図面の数値が公共座標でない可能性があります。"
        } else {
            message = "\(zone)系で重ねると、\(referenceName)から大きく離れています。"
        }
        let shown = nearer.isEmpty ? Array(ranked.prefix(3)) : Array(nearer)
        return ZoneWarning(message: message, distanceMeters: distance, candidates: shown)
    }

    /// 対応点から、図面の数値が載る系と、その場所の系を分ける。
    public static func suggest(
        pairs: [(drawingX: Double, drawingY: Double, latitude: Double, longitude: Double)]
    ) -> ZoneSuggestion {
        guard let first = pairs.first else {
            return ZoneSuggestion(fromDrawingNumbers: [], forThisPlace: [], matchesDrawingNumbers: false)
        }
        var latitude = 0.0
        var longitude = 0.0
        for pair in pairs {
            latitude += pair.latitude
            longitude += pair.longitude
        }
        let count = Double(pairs.count)
        let place = zonesForPlace(latitude: latitude / count, longitude: longitude / count)
        var matches: [ZoneCandidate] = []
        for zone in PlaneRectangular.zones {
            for axis in DrawingAxis.allCases {
                var square = 0.0
                var usable = 0
                for pair in pairs {
                    guard let plane = PlaneRectangular.forward(
                        latitudeDegrees: pair.latitude,
                        longitudeDegrees: pair.longitude,
                        zone: zone.number
                    ) else { continue }
                    let mapped = axis.plane(drawingX: pair.drawingX, drawingY: pair.drawingY)
                    let dE = mapped.easting - plane.eastingMeters
                    let dN = mapped.northing - plane.northingMeters
                    square += dE * dE + dN * dN
                    usable += 1
                }
                guard usable == pairs.count, usable > 0 else { continue }
                let rms = GeoMath.squareRoot(square / Double(usable))
                guard let origin = PlaneRectangular.inverse(
                    northingMeters: axis.plane(drawingX: first.drawingX, drawingY: first.drawingY).northing,
                    eastingMeters: axis.plane(drawingX: first.drawingX, drawingY: first.drawingY).easting,
                    zone: zone.number
                ), let gap = GRS80Geodesic.inverse(
                    latitude1: origin.latitudeDegrees,
                    longitude1: origin.longitudeDegrees,
                    latitude2: first.latitude,
                    longitude2: first.longitude
                ) else { continue }
                matches.append(ZoneCandidate(
                    zone: zone.number,
                    axis: axis,
                    rmsMeters: rms,
                    distanceMeters: gap.distanceMeters,
                    matchesNumbers: rms <= numberMatchMeters
                ))
            }
        }
        matches.sort { $0.rmsMeters < $1.rmsMeters }
        let hits = matches.filter(\.matchesNumbers)
        return ZoneSuggestion(
            fromDrawingNumbers: hits.isEmpty ? Array(matches.prefix(3)) : hits,
            forThisPlace: place,
            matchesDrawingNumbers: !hits.isEmpty
        )
    }

    public static func zonesForPlace(latitude: Double, longitude: Double) -> [ZoneCandidate] {
        var ranked: [ZoneCandidate] = []
        for zone in PlaneRectangular.zones {
            guard let plane = PlaneRectangular.forward(
                latitudeDegrees: latitude,
                longitudeDegrees: longitude,
                zone: zone.number
            ) else { continue }
            let distance = GeoMath.hypotenuse(plane.northingMeters, plane.eastingMeters)
            ranked.append(ZoneCandidate(
                zone: zone.number,
                axis: .cadEastNorth,
                rmsMeters: distance,
                distanceMeters: distance,
                matchesNumbers: false
            ))
        }
        ranked.sort { $0.distanceMeters < $1.distanceMeters }
        return Array(ranked.prefix(3))
    }

    private static func rankInterpretations(
        drawingX: Double,
        drawingY: Double,
        referenceLatitude: Double,
        referenceLongitude: Double
    ) -> [ZoneCandidate] {
        var ranked: [ZoneCandidate] = []
        for zone in PlaneRectangular.zones {
            for axis in DrawingAxis.allCases {
                let mapped = axis.plane(drawingX: drawingX, drawingY: drawingY)
                guard let geo = PlaneRectangular.inverse(
                    northingMeters: mapped.northing,
                    eastingMeters: mapped.easting,
                    zone: zone.number
                ), let gap = GRS80Geodesic.inverse(
                    latitude1: geo.latitudeDegrees,
                    longitude1: geo.longitudeDegrees,
                    latitude2: referenceLatitude,
                    longitude2: referenceLongitude
                ) else { continue }
                ranked.append(ZoneCandidate(
                    zone: zone.number,
                    axis: axis,
                    rmsMeters: gap.distanceMeters,
                    distanceMeters: gap.distanceMeters,
                    matchesNumbers: gap.distanceMeters <= farMeters
                ))
            }
        }
        ranked.sort { $0.distanceMeters < $1.distanceMeters }
        return ranked
    }

    private static func format(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }
}

/// 基盤地図の道路縁・建物の線と、図面の線を合わせる 2 次元 ICP。
/// 切り出しは事務所側。こちらは同じ平面に載った線分の組だけを受け取る。
public struct ICP2DRequest: Sendable, Equatable {
    public var source: [Segment2D]
    public var target: [Segment2D]
    public var initial: Similarity2D
    public var lockScale: Bool
    public var maxIterations: Int
    public var sampleSpacingMeters: Double
    public var outlierMeters: Double

    public init(
        source: [Segment2D],
        target: [Segment2D],
        initial: Similarity2D,
        lockScale: Bool = true,
        maxIterations: Int = 25,
        sampleSpacingMeters: Double = 2,
        outlierMeters: Double = 15
    ) {
        self.source = source
        self.target = target
        self.initial = initial
        self.lockScale = lockScale
        self.maxIterations = maxIterations
        self.sampleSpacingMeters = sampleSpacingMeters
        self.outlierMeters = outlierMeters
    }
}

public struct ICP2DResult: Sendable, Equatable {
    public var transform: Similarity2D
    public var rmsMeters: Double
    public var iterations: Int
    public var usedPointCount: Int

    public init(transform: Similarity2D, rmsMeters: Double, iterations: Int, usedPointCount: Int) {
        self.transform = transform
        self.rmsMeters = rmsMeters
        self.iterations = iterations
        self.usedPointCount = usedPointCount
    }
}

public enum ICP2D {
    public static func align(_ request: ICP2DRequest) -> ICP2DResult? {
        let samples = sample(request.source, spacing: max(request.sampleSpacingMeters, 0.05))
        guard samples.count >= 2, !request.target.isEmpty else { return nil }
        let index = SegmentGrid(segments: request.target, cell: max(request.outlierMeters, 1))
        var current = request.initial
        var previous = Double.greatestFiniteMagnitude
        var used = 0
        var iterations = 0
        let limit = max(1, request.maxIterations)
        for iteration in 1...limit {
            iterations = iteration
            var pairs: [(source: PlanarPoint, target: PlanarPoint)] = []
            for samplePoint in samples {
                let world = current.apply(samplePoint)
                guard let nearest = index.nearest(to: world, within: request.outlierMeters) else { continue }
                pairs.append((samplePoint, nearest))
            }
            guard let fit = SimilaritySolver.fit(pairs, lockScale: request.lockScale) else { break }
            current = fit.transform
            used = pairs.count
            if abs(previous - fit.rmsMeters) < 1e-4 {
                return ICP2DResult(transform: current, rmsMeters: fit.rmsMeters, iterations: iteration, usedPointCount: used)
            }
            previous = fit.rmsMeters
        }
        guard used >= 2 else { return nil }
        let residuals = samples.compactMap { samplePoint -> Double? in
            let world = current.apply(samplePoint)
            guard let nearest = index.nearest(to: world, within: request.outlierMeters) else { return nil }
            return world.distance(to: nearest)
        }
        guard !residuals.isEmpty else { return nil }
        let rms = GeoMath.squareRoot(residuals.reduce(0) { $0 + $1 * $1 } / Double(residuals.count))
        return ICP2DResult(transform: current, rmsMeters: rms, iterations: iterations, usedPointCount: residuals.count)
    }

    private static func sample(_ segments: [Segment2D], spacing: Double) -> [PlanarPoint] {
        var points: [PlanarPoint] = []
        for segment in segments {
            let length = segment.length
            if length < 1e-9 {
                points.append(segment.start)
                continue
            }
            let steps = min(64, max(1, Int(ceil(length / spacing))))
            for step in 0...steps {
                let t = Double(step) / Double(steps)
                points.append(PlanarPoint(
                    x: segment.start.x + (segment.end.x - segment.start.x) * t,
                    y: segment.start.y + (segment.end.y - segment.start.y) * t
                ))
            }
        }
        return points
    }
}

struct SegmentGrid {
    let cell: Double
    private var cells: [Int64: [Segment2D]] = [:]

    init(segments: [Segment2D], cell: Double) {
        self.cell = cell
        for segment in segments {
            let minX = min(segment.start.x, segment.end.x)
            let maxX = max(segment.start.x, segment.end.x)
            let minY = min(segment.start.y, segment.end.y)
            let maxY = max(segment.start.y, segment.end.y)
            let x0 = Int(floor(minX / cell))
            let x1 = Int(floor(maxX / cell))
            let y0 = Int(floor(minY / cell))
            let y1 = Int(floor(maxY / cell))
            for ix in x0...x1 {
                for iy in y0...y1 {
                    cells[key(ix, iy), default: []].append(segment)
                }
            }
        }
    }

    func nearest(to point: PlanarPoint, within limit: Double) -> PlanarPoint? {
        let ix = Int(floor(point.x / cell))
        let iy = Int(floor(point.y / cell))
        var best: PlanarPoint?
        var bestDistance = limit
        for dx in -1...1 {
            for dy in -1...1 {
                guard let bucket = cells[key(ix + dx, iy + dy)] else { continue }
                for segment in bucket {
                    let candidate = closest(point, on: segment)
                    let distance = point.distance(to: candidate)
                    if distance <= bestDistance {
                        bestDistance = distance
                        best = candidate
                    }
                }
            }
        }
        return best
    }

    private func key(_ x: Int, _ y: Int) -> Int64 {
        (Int64(x) << 32) ^ Int64(y)
    }

    private func closest(_ point: PlanarPoint, on segment: Segment2D) -> PlanarPoint {
        let dx = segment.end.x - segment.start.x
        let dy = segment.end.y - segment.start.y
        let length2 = dx * dx + dy * dy
        if length2 < 1e-18 { return segment.start }
        var t = ((point.x - segment.start.x) * dx + (point.y - segment.start.y) * dy) / length2
        t = min(1, max(0, t))
        return PlanarPoint(x: segment.start.x + t * dx, y: segment.start.y + t * dy)
    }
}
