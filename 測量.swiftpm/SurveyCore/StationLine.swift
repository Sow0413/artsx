import Foundation

/// 測点名の付いた点。点列から中心線を作るときと、図面の文字を追加距離に使うときに使う。
public struct StationAnchor: Codable, Equatable, Sendable {
    public var name: String
    public var point: PlanarPoint

    public init(name: String, point: PlanarPoint) {
        self.name = name
        self.point = point
    }
}

public enum StationLineSource: String, Codable, Sendable {
    /// 図面の線。追加距離は線の長さ。近くの測点名があれば、その名前に合わせる。
    case polyline
    /// 測点名の付いた点を、並びの順につないだ線。
    case anchors
}

/// 路線の中心線と、頂点ごとの追加距離。
/// 将来ほかの人の端末へ渡すのはこの値だけにする。受け取った側は自分の現在地を
/// `locate(latitudeDegrees:longitudeDegrees:)` に入れれば、同じ測点になる。通信はここには書かない。
public struct StationLine: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var zone: Int
    public var intervalMeters: Double
    /// 線の始点を No. いくつにするか。名前から距離を読む点列では、読めない点の始まりに使う。
    public var originStation: Int
    public var source: StationLineSource
    /// 平面の東・北。メートル。
    public var vertices: [PlanarPoint]
    /// `vertices` と同じ個数の追加距離。
    public var chainageMeters: [Double]
    public var anchors: [StationAnchor]

    public init(
        id: String = UUID().uuidString,
        name: String,
        zone: Int,
        intervalMeters: Double,
        originStation: Int,
        source: StationLineSource,
        vertices: [PlanarPoint],
        chainageMeters: [Double],
        anchors: [StationAnchor] = []
    ) {
        self.id = id
        self.name = name
        self.zone = zone
        self.intervalMeters = intervalMeters
        self.originStation = originStation
        self.source = source
        self.vertices = vertices
        self.chainageMeters = chainageMeters
        self.anchors = anchors
    }

    public var lengthMeters: Double {
        guard let first = chainageMeters.first, let last = chainageMeters.last else { return 0 }
        return last - first
    }

    public func locate(_ point: PlanarPoint) -> OperatorGuide? {
        OperatorStation.guide(
            point: point,
            vertices: vertices,
            chainageMeters: chainageMeters,
            interval: intervalMeters
        )
    }

    /// 共有先の端末が、自分の緯度経度から測点を出す入口。
    public func locate(latitudeDegrees: Double, longitudeDegrees: Double) -> OperatorGuide? {
        guard let plane = PlaneRectangular.forward(
            latitudeDegrees: latitudeDegrees,
            longitudeDegrees: longitudeDegrees,
            zone: zone
        ) else { return nil }
        return locate(PlanarPoint(x: plane.eastingMeters, y: plane.northingMeters))
    }

    public func rebuilt(intervalMeters: Double, originStation: Int) -> StationLine? {
        switch source {
        case .polyline:
            return StationLine.polyline(
                vertices: vertices,
                zone: zone,
                intervalMeters: intervalMeters,
                originStation: originStation,
                name: name,
                anchors: anchors,
                id: id
            )
        case .anchors:
            return StationLine.namedPoints(
                anchors: anchors,
                zone: zone,
                intervalMeters: intervalMeters,
                originStation: originStation,
                name: name,
                id: id
            )
        }
    }

    /// 図面の折れ線。追加距離は始点を起点番号として、線に沿ったメートル。
    /// 測点名が線の近くにあれば、その間は名前の追加距離になる。
    public static func polyline(
        vertices: [PlanarPoint],
        zone: Int,
        intervalMeters: Double,
        originStation: Int,
        name: String = "中心線",
        anchors: [StationAnchor] = [],
        id: String = UUID().uuidString
    ) -> StationLine? {
        guard vertices.count >= 2, intervalMeters > 0, intervalMeters.isFinite else { return nil }
        let geometric = OperatorStation.geometricChainage(vertices)
        let shift = Double(originStation) * intervalMeters
        var chainage = geometric.map { shift + $0 }
        let controls = anchors.compactMap { anchor -> (along: Double, chainage: Double)? in
            guard let named = StationName.chainageMeters(in: anchor.name, interval: intervalMeters) else { return nil }
            guard let hit = OperatorStation.project(anchor.point, onto: vertices) else { return nil }
            if abs(hit.offset) > 40 { return nil }
            if hit.along < -1 || hit.along > hit.total + 1 { return nil }
            return (min(max(hit.along, 0), hit.total), named)
        }.sorted { $0.along < $1.along }
        if !controls.isEmpty {
            chainage = stamp(geometric: geometric, controls: controls)
        }
        return StationLine(
            id: id,
            name: name,
            zone: zone,
            intervalMeters: intervalMeters,
            originStation: originStation,
            source: .polyline,
            vertices: vertices,
            chainageMeters: chainage,
            anchors: anchors
        )
    }

    /// 測点名の付いた点を、渡された順につなぐ。名前が No.23 や No.23+5 なら、その追加距離を張る。
    public static func namedPoints(
        anchors: [StationAnchor],
        zone: Int,
        intervalMeters: Double,
        originStation: Int,
        name: String = "測点",
        id: String = UUID().uuidString
    ) -> StationLine? {
        guard anchors.count >= 2, intervalMeters > 0, intervalMeters.isFinite else { return nil }
        var chainage: [Double] = []
        var cursor = Double(originStation) * intervalMeters
        for (index, anchor) in anchors.enumerated() {
            if let named = StationName.chainageMeters(in: anchor.name, interval: intervalMeters) {
                cursor = named
            } else if index > 0 {
                cursor += anchors[index - 1].point.distance(to: anchor.point)
            }
            chainage.append(cursor)
        }
        return StationLine(
            id: id,
            name: name,
            zone: zone,
            intervalMeters: intervalMeters,
            originStation: originStation,
            source: .anchors,
            vertices: anchors.map(\.point),
            chainageMeters: chainage,
            anchors: anchors
        )
    }

    private static func stamp(geometric: [Double], controls: [(along: Double, chainage: Double)]) -> [Double] {
        geometric.map { distance in
            if distance <= controls[0].along {
                return controls[0].chainage + (distance - controls[0].along)
            }
            let last = controls[controls.count - 1]
            if distance >= last.along {
                return last.chainage + (distance - last.along)
            }
            for index in 0..<(controls.count - 1) {
                let end = controls[index + 1]
                if distance <= end.along {
                    let span = end.along - controls[index].along
                    let fraction = span < 1e-8 ? 0 : (distance - controls[index].along) / span
                    return controls[index].chainage + fraction * (end.chainage - controls[index].chainage)
                }
            }
            return last.chainage
        }
    }
}

public enum StationName {
    /// `No.23` は間隔×23。`No.23+5.2` と `23+5.2` はそこにメートルを足す。ただの点名は nil。
    public static func chainageMeters(in raw: String, interval: Double) -> Double? {
        guard interval > 0, interval.isFinite else { return nil }
        var body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { return nil }
        let folded = body
            .replacingOccurrences(of: "Ｎ", with: "N")
            .replacingOccurrences(of: "ｏ", with: "o")
            .replacingOccurrences(of: "Ｏ", with: "O")
            .replacingOccurrences(of: "．", with: ".")
            .replacingOccurrences(of: "＋", with: "+")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
        body = String(folded.map { character in
            guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return character }
            let value = scalar.value
            if value >= 0xFF10 && value <= 0xFF19, let ascii = UnicodeScalar(value - 0xFF10 + 48) {
                return Character(ascii)
            }
            return character
        })
        let hadStationWord = body.lowercased().hasPrefix("no")
        if hadStationWord {
            body = String(body.dropFirst(2))
            if body.hasPrefix(".") { body = String(body.dropFirst()) }
        } else if !body.contains("+") {
            return nil
        }
        if body.lowercased().hasSuffix("m") {
            body = String(body.dropLast())
        }
        let parts = body.split(separator: "+", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2, let number = Int(parts[0]), number >= 0, number < 100_000 else {
            return nil
        }
        var plus = 0.0
        if parts.count == 2 {
            guard let value = Double(parts[1]), value.isFinite, value >= 0 else { return nil }
            plus = value
        }
        return Double(number) * interval + plus
    }
}
