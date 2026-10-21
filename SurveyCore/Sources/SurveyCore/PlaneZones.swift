import Foundation

/// 一つの県の中で系が分かれるときの区域。平成14年告示第9号の区域と、測量計算サイトの市町村名。
public struct PlaneZoneArea: Sendable, Equatable, Identifiable {
    public var name: String
    public var zone: Int
    /// 平成16年時点の旧市町村名。ピッカーには出さない。
    public var formerNames: [String]

    public var id: String { name }

    public init(name: String, zone: Int, formerNames: [String] = []) {
        self.name = name
        self.zone = zone
        self.formerNames = formerNames
    }
}

/// 平成14年国土交通省告示第9号（最終改正 平成22年国土交通省告示第289号）の県と系。
/// 北海道、東京都、鹿児島県、沖縄県は複数の系を持つ。それ以外の県は一つの系で決まる。
/// 東京都の系は IX・XIV・XVIII・XIX。I系は長崎県と鹿児島県の島で、東京都には入らない。
public struct PrefectureZones: Sendable, Equatable, Identifiable {
    public var name: String
    public var zones: [Int]
    /// 県の概略の箱。島がある県は複数。軸の取り違えで別の場所に落ちた候補を外す。
    var boxes: [GeoBox]
    /// 系が分かれる県だけ。一つの系の県は空。
    public var areas: [PlaneZoneArea] = []

    public var id: String { name }
    public var decidesZone: Bool { zones.count == 1 }
    public var needsArea: Bool { !decidesZone }

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
        entry("北海道", [11, 12, 13], [box(41.3, 139.3, 45.6, 145.9)], areas: PlaneZoneAreas.hokkaido),
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
        ], areas: PlaneZoneAreas.tokyo),
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
        entry("鹿児島県", [1, 2], [box(27.0, 128.3, 32.2, 131.2)], areas: PlaneZoneAreas.kagoshima),
        entry("沖縄県", [15, 16, 17], [box(24.0, 122.9, 27.9, 131.4)], areas: PlaneZoneAreas.okinawa)
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

    /// 県が一つの系ならその系。複数の県は区域名で決まる。決まらなければ nil。
    public static func zone(prefecture raw: String, area rawArea: String?) -> Int? {
        guard let record = named(raw) else { return nil }
        if record.decidesZone { return record.zones[0] }
        return areaRecord(in: record, named: rawArea)?.zone
    }

    /// ピッカーに出す名前へ揃える。旧市町村名は現在の区域名になる。
    public static func canonicalArea(prefecture raw: String, area rawArea: String?) -> String? {
        guard let record = named(raw) else { return nil }
        return areaRecord(in: record, named: rawArea)?.name
    }

    /// 「三重県 → VI系」。区域があるときは県名のあとに置く。
    public static func summary(prefecture raw: String, area: String?, zone: Int) -> String {
        let name = named(raw)?.name ?? raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let roman = PlaneRectangular.zone(zone)?.romanLabel ?? "\(zone)系"
        let canonical = canonicalArea(prefecture: name, area: area)
        if let canonical, !canonical.isEmpty {
            return "\(name) \(canonical) → \(roman)"
        }
        return "\(name) → \(roman)"
    }

    private static func areaRecord(in record: PrefectureZones, named raw: String?) -> PlaneZoneArea? {
        guard let raw else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { return nil }
        return record.areas.first { $0.name == key || $0.formerNames.contains(key) }
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

    private static func entry(
        _ name: String,
        _ zones: [Int],
        _ boxes: [GeoBox],
        areas: [PlaneZoneArea] = []
    ) -> PrefectureZones {
        PrefectureZones(name: name, zones: zones, boxes: boxes, areas: areas)
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
    /// 原点の近く、選んだ系の範囲外、県の箱の外。2点合わせへ案内する。
    public var looksLocal: Bool = false
}

public struct PlaneGridFit: Sendable, Equatable {
    public var looksLocal: Bool
    public var note: String

    public init(looksLocal: Bool, note: String) {
        self.looksLocal = looksLocal
        self.note = note
    }
}

public enum PlanePlacementChooser {
    public static let originLimitMeters = 180_000.0
    /// 原点のすぐ近くは、現地の公共座標ではなく図面のローカル座標とみる。
    public static let nearOriginMeters = 1_000.0

    /// 手合わせがあるか、図面の数値がその系の公共座標として県の範囲に載るか。
    public static func isGeoreferenced(
        midX: Double,
        midY: Double,
        zone: Int,
        hasTransform: Bool,
        prefecture: String? = nil
    ) -> Bool {
        if hasTransform { return true }
        return !gridFit(x: midX, y: midY, zone: zone, prefecture: prefecture).looksLocal
    }

    public static func isNearOrigin(x: Double, y: Double) -> Bool {
        guard x.isFinite, y.isFinite else { return true }
        return GeoMath.hypotenuse(x, y) <= nearOriginMeters
    }

    /// SFC は東・北。選んだ系の範囲と県の箱に載るかを見る。
    public static func gridFit(x: Double, y: Double, zone: Int, prefecture raw: String?) -> PlaneGridFit {
        let roman = PlaneRectangular.zone(zone)?.romanLabel ?? "\(zone)系"
        if isNearOrigin(x: x, y: y) {
            return PlaneGridFit(
                looksLocal: true,
                note: "図面の数値が原点の近くです。公共座標ではなさそうです。2点合わせで載せてください。"
            )
        }
        let hits = landings(x: x, y: y).filter { $0.zone == zone && $0.axis == .cadEastNorth }
        if hits.isEmpty {
            return PlaneGridFit(
                looksLocal: true,
                note: "図面の数値が\(roman)の範囲外です。公共座標ではなさそうです。2点合わせで載せてください。"
            )
        }
        if let record = raw.flatMap(PlaneZoneCatalog.named) {
            let inside = hits.contains { record.contains(latitude: $0.latitudeDegrees, longitude: $0.longitudeDegrees) }
            if !inside {
                return PlaneGridFit(
                    looksLocal: true,
                    note: "図面の数値が\(record.name)の範囲には載りません。2点合わせで載せてください。"
                )
            }
        }
        return PlaneGridFit(looksLocal: false, note: "")
    }

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
        longitude: Double?,
        zone explicitZone: Int? = nil,
        area: String? = nil
    ) -> PlanePlacement {
        if let explicitZone, PlaneRectangular.zone(explicitZone) != nil {
            return fixed(x: x, y: y, zone: explicitZone, prefecture: rawPrefecture, area: area)
        }
        let all = landings(x: x, y: y)
        let placement: PlanePlacement
        if let record = rawPrefecture.flatMap(PlaneZoneCatalog.named) {
            placement = place(all, prefecture: record)
        } else if let latitude, let longitude {
            placement = place(all, latitude: latitude, longitude: longitude)
        } else {
            let zones = uniqueZones(all)
            placement = PlanePlacement(
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
        return annotate(placement, x: x, y: y, prefecture: rawPrefecture, area: area)
    }

    private static func fixed(x: Double, y: Double, zone: Int, prefecture raw: String?, area: String?) -> PlanePlacement {
        let record = raw.flatMap(PlaneZoneCatalog.named)
        let fit = gridFit(x: x, y: y, zone: zone, prefecture: record?.name)
        let note = publicNote(fit: fit, prefecture: record?.name, area: area, zone: zone)
            ?? (fit.looksLocal ? fit.note : "\(PlaneRectangular.zone(zone)?.romanLabel ?? "\(zone)系")の公共座標として読みました。")
        let hits = landings(x: x, y: y).filter { $0.zone == zone }
        return PlanePlacement(
            landings: hits,
            zones: record?.zones ?? [zone],
            decidedZone: zone,
            decidedAxis: nil,
            prefecture: record?.name,
            note: note,
            looksLocal: fit.looksLocal
        )
    }

    private static func annotate(
        _ placement: PlanePlacement,
        x: Double,
        y: Double,
        prefecture raw: String?,
        area: String?
    ) -> PlanePlacement {
        var placement = placement
        guard let zone = placement.decidedZone else {
            if isNearOrigin(x: x, y: y) || placement.landings.isEmpty {
                placement.looksLocal = true
                placement.note = isNearOrigin(x: x, y: y)
                    ? "図面の数値が原点の近くです。公共座標ではなさそうです。2点合わせで載せてください。"
                    : "図面の数値が原点から180kmの範囲には載りません。2点合わせで載せてください。"
            }
            return placement
        }
        let fit = gridFit(x: x, y: y, zone: zone, prefecture: raw)
        if let note = publicNote(fit: fit, prefecture: placement.prefecture, area: area, zone: zone) {
            placement.note = note
            placement.looksLocal = false
        } else if fit.looksLocal {
            placement.looksLocal = true
            placement.note = fit.note
        }
        return placement
    }

    private static func publicNote(fit: PlaneGridFit, prefecture: String?, area: String?, zone: Int) -> String? {
        guard !fit.looksLocal, let prefecture else { return nil }
        return PlaneZoneCatalog.summary(prefecture: prefecture, area: area, zone: zone) + "の公共座標として読みました。"
    }

    private static func place(_ all: [PlaneLanding], prefecture: PrefectureZones) -> PlanePlacement {
        let inZone = all.filter { prefecture.zones.contains($0.zone) }
        let inside = inZone.filter { prefecture.contains(latitude: $0.latitudeDegrees, longitude: $0.longitudeDegrees) }
        let hits = inside.isEmpty ? inZone : inside
        let decidedZone: Int? = prefecture.decidesZone ? prefecture.zones[0] : (uniqueZones(hits).count == 1 ? uniqueZones(hits)[0] : nil)
        let axisPool = hits.filter { decidedZone == nil || $0.zone == decidedZone }
        let decidedAxis = axisPool.count == 1 ? axisPool[0].axis : nil
        let zoneText = prefecture.zones.map { PlaneRectangular.zone($0)?.romanLabel ?? "\($0)系" }.joined(separator: "・")
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
            : "現在地で絞ると、\(zones.map { PlaneRectangular.zone($0)?.romanLabel ?? "\($0)系" }.joined(separator: "・"))です。\(list(hits))"
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
            let roman = PlaneRectangular.zone(hit.zone)?.romanLabel ?? "\(hit.zone)系"
            return String(
                format: "%@（%@）北緯%.4f° 東経%.4f°",
                roman,
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

/// 告示の区域を、ピッカーの行にした。市町村名は測量計算サイト（平成16年時点）と、その後の合併後の名前。
enum PlaneZoneAreas {
    static let hokkaido: [PlaneZoneArea] = [
        row("小樽市", 11),
        row("函館市", 11),
        row("伊達市", 11),
        row("北斗市", 11),
        row("後志", 11),
        row("渡島", 11),
        row("檜山", 11),
        row("胆振（豊浦町・壮瞥町・洞爺湖町）", 11, ["豊浦町", "壮瞥町", "洞爺湖町"]),
        row("北見市", 13),
        row("帯広市", 13),
        row("釧路市", 13),
        row("網走市", 13),
        row("根室市", 13),
        row("十勝", 13),
        row("釧路", 13),
        row("根室", 13),
        row(
            "オホーツク（美幌町・津別町・斜里町・清里町・小清水町・訓子府町・置戸町・佐呂間町・大空町）",
            13,
            ["美幌町", "津別町", "斜里町", "清里町", "小清水町", "訓子府町", "置戸町", "佐呂間町", "大空町"]
        ),
        row("札幌・旭川など（上記以外）", 12, ["札幌市", "旭川市", "苫小牧市", "室蘭市", "稚内市", "岩見沢市"])
    ]

    static let tokyo: [PlaneZoneArea] = [
        row("23区・多摩", 9, ["23区", "多摩", "特別区"]),
        row(
            "伊豆諸島（大島町・利島村・新島村・神津島村・三宅村・御蔵島村・八丈町・青ヶ島村）",
            9,
            ["大島町", "利島村", "新島村", "神津島村", "三宅村", "御蔵島村", "八丈町", "青ヶ島村", "青ケ島村"]
        ),
        row("小笠原（父島・母島・硫黄島）", 14, ["父島", "母島", "硫黄島", "聟島列島", "父島列島", "母島列島"]),
        row("沖ノ鳥島", 18),
        row("南鳥島", 19)
    ]

    static let kagoshima: [PlaneZoneArea] = [
        row("甑島（薩摩川内市）", 1, ["里村", "上甑村", "下甑村", "鹿島村", "甑島"]),
        row("宇治群島・草垣群島（南さつま市）", 1, ["笠沙町"]),
        row("十島村", 1),
        row("黒島（三島村）", 1, ["黒島"]),
        row("奄美市", 1, ["名瀬市", "住用村", "笠利町"]),
        row("大和村", 1),
        row("宇検村", 1),
        row("瀬戸内町", 1),
        row("龍郷町", 1),
        row("喜界町", 1),
        row("徳之島町", 1),
        row("天城町", 1),
        row("伊仙町", 1),
        row("和泊町", 1),
        row("知名町", 1),
        row("与論町", 1),
        row("本土", 2),
        row("種子島（西之表市・中種子町・南種子町）", 2, ["西之表市", "中種子町", "南種子町", "種子島"]),
        row("屋久島（屋久島町）", 2, ["屋久島町", "上屋久町", "屋久町", "口永良部島"]),
        row("竹島・硫黄島（三島村）", 2, ["竹島"])
    ]

    static let okinawa: [PlaneZoneArea] = [
        row(
            "沖縄本島・久米島・慶良間",
            15,
            ["那覇市", "宜野湾市", "浦添市", "名護市", "糸満市", "沖縄市", "うるま市", "南城市", "豊見城市", "久米島町", "渡嘉敷村", "座間味村", "粟国村", "渡名喜村", "伊平屋村", "伊是名村", "伊江村", "石川市", "具志川市", "仲里村", "具志川村"]
        ),
        row("宮古島市", 16, ["平良市", "城辺町", "下地町", "上野村", "伊良部町"]),
        row("多良間村", 16),
        row("石垣市", 16),
        row("竹富町", 16),
        row("与那国町", 16),
        row("北大東村", 17),
        row("南大東村", 17)
    ]

    private static func row(_ name: String, _ zone: Int, _ former: [String] = []) -> PlaneZoneArea {
        PlaneZoneArea(name: name, zone: zone, formerNames: former)
    }
}
