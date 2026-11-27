import Foundation

/// 平成14年国土交通省告示第9号（最終改正 平成22年国土交通省告示第289号）の県と系。
/// 北海道、東京都、鹿児島県、沖縄県は複数の系を持つ。それ以外の県は一つの系で決まる。
public struct PrefectureZones: Sendable, Equatable, Identifiable {
    public var name: String
    public var zones: [Int]
    /// 県の概略の箱。島がある県は複数。軸の取り違えで別の場所に落ちた候補を外す。
    var boxes: [GeoBox]

    public var id: String { name }
    public var decidesZone: Bool { zones.count == 1 }

    public func contains(latitude: Double, longitude: Double) -> Bool {
        let pad = 0.25
        return boxes.contains { box in
            latitude >= box.south - pad && latitude <= box.north + pad
                && longitude >= box.west - pad && longitude <= box.east + pad
        }
    }
}

struct GeoBox: Sendable, Equatable {
    var south: Double
    var west: Double
    var north: Double
    var east: Double
}

public enum PlaneZoneCatalog {
    public static let prefectures: [PrefectureZones] = [
        entry("北海道", [11, 12, 13], [box(41.3, 139.3, 45.6, 145.9)]),
        entry("青森県", [10], [box(40.2, 139.4, 41.6, 141.7)]),
        entry("岩手県", [10], [box(38.7, 140.6, 40.5, 142.1)]),
        entry("宮城県", [10], [box(37.7, 140.2, 39.0, 141.7)]),
        entry("秋田県", [10], [box(38.8, 139.6, 40.5, 140.9)]),
        entry("山形県", [10], [box(37.7, 139.5, 39.2, 140.7)]),
        entry("福島県", [9], [box(36.8, 139.1, 37.9, 141.1)]),
        entry("茨城県", [9], [box(35.7, 139.6, 36.9, 140.9)]),
        entry("栃木県", [9], [box(36.2, 139.3, 37.2, 140.3)]),
        entry("群馬県", [9], [box(36.0, 138.4, 37.1, 139.7)]),
        entry("埼玉県", [9], [box(35.7, 138.7, 36.3, 139.9)]),
        entry("千葉県", [9], [box(34.9, 139.7, 36.1, 140.9)]),
        entry("東京都", [9, 14, 18, 19], [
            box(32.4, 138.9, 35.9, 140.9),
            box(26.5, 141.9, 27.8, 142.3),
            box(20.3, 136.0, 20.5, 136.2),
            box(24.2, 153.9, 24.4, 154.1)
        ]),
        entry("神奈川県", [9], [box(35.1, 138.9, 35.7, 139.8)]),
        entry("新潟県", [8], [box(36.7, 137.6, 38.6, 139.9)]),
        entry("富山県", [7], [box(36.2, 136.7, 36.9, 137.8)]),
        entry("石川県", [7], [box(36.1, 136.2, 37.9, 137.4)]),
        entry("福井県", [6], [box(35.3, 135.4, 36.3, 136.8)]),
        entry("山梨県", [8], [box(35.2, 138.1, 35.9, 139.1)]),
        entry("長野県", [8], [box(35.1, 137.3, 37.0, 138.7)]),
        entry("岐阜県", [7], [box(35.1, 136.2, 36.5, 137.7)]),
        entry("静岡県", [8], [box(34.6, 137.4, 35.6, 139.2)]),
        entry("愛知県", [7], [box(34.5, 136.6, 35.4, 137.8)]),
        entry("三重県", [6], [box(33.7, 135.8, 35.2, 136.9)]),
        entry("滋賀県", [6], [box(34.7, 135.7, 35.7, 136.5)]),
        entry("京都府", [6], [box(34.7, 134.8, 35.8, 136.1)]),
        entry("大阪府", [6], [box(34.2, 135.0, 35.0, 135.8)]),
        entry("兵庫県", [5], [box(34.1, 134.2, 35.7, 135.5)]),
        entry("奈良県", [6], [box(33.8, 135.5, 34.8, 136.2)]),
        entry("和歌山県", [6], [box(33.4, 134.9, 34.4, 136.0)]),
        entry("鳥取県", [5], [box(35.0, 133.1, 35.6, 134.5)]),
        entry("島根県", [3], [box(34.3, 131.6, 36.3, 133.4)]),
        entry("岡山県", [5], [box(34.3, 133.2, 35.3, 134.4)]),
        entry("広島県", [3], [box(34.0, 132.0, 35.1, 133.5)]),
        entry("山口県", [3], [box(33.7, 130.7, 34.8, 132.2)]),
        entry("徳島県", [4], [box(33.5, 133.5, 34.3, 134.8)]),
        entry("香川県", [4], [box(34.0, 133.4, 34.5, 134.5)]),
        entry("愛媛県", [4], [box(32.9, 132.0, 34.3, 133.4)]),
        entry("高知県", [4], [box(32.7, 132.4, 33.9, 134.3)]),
        entry("福岡県", [2], [box(33.0, 130.0, 34.0, 131.2)]),
        entry("佐賀県", [2], [box(32.9, 129.7, 33.6, 130.5)]),
        entry("長崎県", [1], [box(32.5, 128.5, 34.7, 130.4)]),
        entry("熊本県", [2], [box(32.0, 130.0, 33.2, 131.3)]),
        entry("大分県", [2], [box(32.7, 130.8, 33.7, 132.1)]),
        entry("宮崎県", [2], [box(31.3, 130.6, 32.8, 131.9)]),
        entry("鹿児島県", [1, 2], [box(27.0, 128.3, 32.2, 131.2)]),
        entry("沖縄県", [15, 16, 17], [box(24.0, 122.9, 27.9, 131.4)])
    ]

    public static func named(_ raw: String) -> PrefectureZones? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = prefectures.first(where: { $0.name == trimmed }) { return exact }
        let aliases = ["東京": "東京都", "京都": "京都府", "大阪": "大阪府"]
        if let name = aliases[trimmed], let found = prefectures.first(where: { $0.name == name }) {
            return found
        }
        return prefectures.first { prefecture in
            prefecture.name == trimmed + "県" || prefecture.name == trimmed + "府" || prefecture.name == trimmed + "都"
        }
    }

    public static func zones(forPrefecture name: String) -> [Int] {
        named(name)?.zones ?? []
    }

    /// 現在地に一番近い平面直角の系。奈良付近は 6。
    public static func nearestZone(latitude: Double, longitude: Double) -> Int? {
        zones(nearLatitude: latitude, longitude: longitude).first
    }

    /// 現在地から、原点までの距離が近い系。県境では複数残す。
    public static func zones(nearLatitude latitude: Double, longitude: Double) -> [Int] {
        var ranked: [(zone: Int, distance: Double)] = []
        for zone in PlaneRectangular.zones {
            guard let plane = PlaneRectangular.forward(
                latitudeDegrees: latitude,
                longitudeDegrees: longitude,
                zone: zone.number
            ) else { continue }
            ranked.append((zone.number, GeoMath.hypotenuse(plane.northingMeters, plane.eastingMeters)))
        }
        ranked.sort { $0.distance < $1.distance }
        guard let nearest = ranked.first else { return [] }
        let cutoff = min(200_000, max(nearest.distance + 40_000, nearest.distance * 1.25))
        let near = ranked.filter { $0.distance <= cutoff }
        return (near.isEmpty ? [nearest] : near).map(\.zone)
    }

    private static func entry(_ name: String, _ zones: [Int], _ boxes: [GeoBox]) -> PrefectureZones {
        PrefectureZones(name: name, zones: zones, boxes: boxes)
    }

    private static func box(_ south: Double, _ west: Double, _ north: Double, _ east: Double) -> GeoBox {
        GeoBox(south: south, west: west, north: north, east: east)
    }
}

/// 図面の中心を、両方の軸と1〜19系で緯度経度に戻したもの。
public struct PlaneLanding: Sendable, Equatable, Identifiable {
    public var zone: Int
    public var axis: DrawingAxis
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var northingMeters: Double
    public var eastingMeters: Double
    public var originDistanceMeters: Double

    public var id: String { "\(zone)-\(axis.rawValue)" }
}

public struct PlanePlacement: Sendable, Equatable {
    public var landings: [PlaneLanding]
    /// ピッカーに出す系。県が一つのときはその系だけ。
    public var zones: [Int]
    public var decidedZone: Int?
    public var decidedAxis: DrawingAxis?
    public var prefecture: String?
    public var note: String
}

public enum PlanePlacementChooser {
    public static let originLimitMeters = 180_000.0

    public static func landings(x: Double, y: Double, limit: Double = originLimitMeters) -> [PlaneLanding] {
        var hits: [PlaneLanding] = []
        for zone in PlaneRectangular.zones {
            for axis in DrawingAxis.allCases {
                let plane = axis.plane(drawingX: x, drawingY: y)
                guard let geo = PlaneRectangular.inverse(
                    northingMeters: plane.northing,
                    eastingMeters: plane.easting,
                    zone: zone.number
                ) else { continue }
                guard inJapan(geo.latitudeDegrees, geo.longitudeDegrees) else { continue }
                let distance = GeoMath.hypotenuse(plane.northing, plane.easting)
                guard distance <= limit else { continue }
                hits.append(PlaneLanding(
                    zone: zone.number,
                    axis: axis,
                    latitudeDegrees: geo.latitudeDegrees,
                    longitudeDegrees: geo.longitudeDegrees,
                    northingMeters: plane.northing,
                    eastingMeters: plane.easting,
                    originDistanceMeters: distance
                ))
            }
        }
        return hits.sorted { $0.originDistanceMeters < $1.originDistanceMeters }
    }

    /// 県が保存されていれば県で絞る。無ければ現在地で絞る。県が一つの系なら、その系に決める。
    public static func choose(
        x: Double,
        y: Double,
        prefecture rawPrefecture: String?,
        latitude: Double?,
        longitude: Double?
    ) -> PlanePlacement {
        let all = landings(x: x, y: y)
        if let record = rawPrefecture.flatMap(PlaneZoneCatalog.named) {
            return place(all, prefecture: record)
        }
        if let latitude, let longitude {
            return place(all, latitude: latitude, longitude: longitude)
        }
        let zones = uniqueZones(all)
        return PlanePlacement(
            landings: all,
            zones: zones.isEmpty ? Array(1...19) : zones,
            decidedZone: zones.count == 1 ? zones[0] : nil,
            decidedAxis: all.count == 1 ? all[0].axis : nil,
            prefecture: nil,
            note: all.isEmpty
                ? "原点から180km以内に載る系がありません。"
                : "県も現在地も無いので、原点から180km以内に載る読み方を出します。\(list(all))"
        )
    }

    private static func place(_ all: [PlaneLanding], prefecture: PrefectureZones) -> PlanePlacement {
        let inZone = all.filter { prefecture.zones.contains($0.zone) }
        let inside = inZone.filter { prefecture.contains(latitude: $0.latitudeDegrees, longitude: $0.longitudeDegrees) }
        let hits = inside.isEmpty ? inZone : inside
        let decidedZone: Int? = prefecture.decidesZone ? prefecture.zones[0] : (uniqueZones(hits).count == 1 ? uniqueZones(hits)[0] : nil)
        let axisPool = hits.filter { decidedZone == nil || $0.zone == decidedZone }
        let decidedAxis = axisPool.count == 1 ? axisPool[0].axis : nil
        let zoneText = prefecture.zones.map { "\($0)系" }.joined(separator: "・")
        var note = prefecture.decidesZone
            ? "\(prefecture.name)は\(zoneText)です。"
            : "\(prefecture.name)は\(zoneText)です。候補は全部残します。"
        if hits.isEmpty {
            note += "図面の数値は、この県の範囲には載りませんでした。"
        } else {
            note += list(hits)
        }
        let shown = prefecture.decidesZone ? prefecture.zones : (hits.isEmpty ? prefecture.zones : uniqueZones(hits))
        return PlanePlacement(
            landings: hits,
            zones: shown,
            decidedZone: decidedZone,
            decidedAxis: decidedAxis,
            prefecture: prefecture.name,
            note: note
        )
    }

    private static func place(_ all: [PlaneLanding], latitude: Double, longitude: Double) -> PlanePlacement {
        let allowed = PlaneZoneCatalog.zones(nearLatitude: latitude, longitude: longitude)
        var hits = all.filter { allowed.contains($0.zone) }
        let nearby = hits.filter { landing in
            guard let gap = GRS80Geodesic.inverse(
                latitude1: latitude,
                longitude1: longitude,
                latitude2: landing.latitudeDegrees,
                longitude2: landing.longitudeDegrees
            ) else { return false }
            return gap.distanceMeters <= 120_000
        }
        if !nearby.isEmpty { hits = nearby }
        let zones = uniqueZones(hits)
        let decidedZone = zones.count == 1 ? zones[0] : nil
        let axisPool = hits.filter { decidedZone == nil || $0.zone == decidedZone }
        let note = hits.isEmpty
            ? "現在地に近い系では、この図面は載りませんでした。"
            : "現在地で絞ると、\(zones.map { "\($0)系" }.joined(separator: "・"))です。\(list(hits))"
        return PlanePlacement(
            landings: hits,
            zones: zones.isEmpty ? allowed : zones,
            decidedZone: decidedZone,
            decidedAxis: axisPool.count == 1 ? axisPool[0].axis : nil,
            prefecture: nil,
            note: note
        )
    }

    private static func uniqueZones(_ hits: [PlaneLanding]) -> [Int] {
        var seen: [Int] = []
        for hit in hits where !seen.contains(hit.zone) {
            seen.append(hit.zone)
        }
        return seen
    }

    private static func list(_ hits: [PlaneLanding]) -> String {
        hits.prefix(4).map { hit in
            String(
                format: "%d系（%@）北緯%.4f° 東経%.4f°",
                hit.zone,
                hit.axis.label,
                hit.latitudeDegrees,
                hit.longitudeDegrees
            )
        }.joined(separator: "。")
    }

    private static func inJapan(_ latitude: Double, _ longitude: Double) -> Bool {
        latitude >= 20 && latitude <= 46 && longitude >= 122 && longitude <= 154.2
    }
}
