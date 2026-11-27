import Foundation

/// 図面の `.meta.json` と、北・東の点から系を決める。初期値の 9 系や 16 系は、根拠が無い限り残さない。
public enum FieldPackPlacement {
    public struct Decision: Equatable, Sendable {
        public var zone: Int?
        public var axis: DrawingAxis?
        public var choices: [Int]
        public var epsg: Int?
    }

    /// meta の EPSG が最優先。無ければ現在地。決まらなければ 1〜19 の候補だけ返す。
    public static func resolve(
        sidecar: DrawingSidecar?,
        x: Double?,
        y: Double?,
        latitude: Double?,
        longitude: Double?,
        prefecture: String?
    ) -> Decision {
        if let sidecar, let zone = sidecar.zone {
            return Decision(
                zone: zone,
                axis: sidecar.drawingAxis ?? .cadEastNorth,
                choices: [zone],
                epsg: sidecar.epsg
            )
        }
        guard let x, let y, x.isFinite, y.isFinite else {
            return Decision(zone: nil, axis: nil, choices: Array(1...19), epsg: nil)
        }
        let placement = PlanePlacementChooser.choose(
            x: x,
            y: y,
            prefecture: latitude == nil ? prefecture : nil,
            latitude: latitude,
            longitude: longitude
        )
        if let zone = placement.decidedZone {
            return Decision(
                zone: zone,
                axis: placement.decidedAxis ?? .cadEastNorth,
                choices: placement.zones.isEmpty ? [zone] : placement.zones,
                epsg: 6668 + zone
            )
        }
        let choices = placement.zones.isEmpty ? Array(1...19) : placement.zones
        return Decision(zone: nil, axis: placement.decidedAxis, choices: choices, epsg: nil)
    }

    /// 北・東。現在地が一つの系に絞れればそれ。無理なら、meta で決めた系。どちらも無ければピッカー。
    public static func zoneForPlane(
        northing: Double,
        easting: Double,
        latitude: Double?,
        longitude: Double?,
        trustedZone: Int?
    ) -> (zone: Int?, choices: [Int]) {
        if let latitude, let longitude {
            let placement = PlanePlacementChooser.choose(
                x: easting,
                y: northing,
                prefecture: nil,
                latitude: latitude,
                longitude: longitude
            )
            if let zone = placement.decidedZone {
                let choices = placement.zones.isEmpty ? [zone] : placement.zones
                return (zone, choices)
            }
        }
        if let trustedZone, (1...19).contains(trustedZone) {
            return (trustedZone, [trustedZone])
        }
        return (nil, Array(1...19))
    }
}

/// 第VI系（EPSG:6674）の合成図面と、34点の基準点。実在の図面は入れない。
public enum VIPack {
    public static let latitude = 34.6
    public static let longitude = 135.8
    public static let zone = 6
    public static let epsg = 6674
    public static let pointCount = 34

    public static var meta: Data {
        Data(#"{"epsg":6674,"axis":"EN","unit":"m"}"#.utf8)
    }

    public static func plane() -> (easting: Double, northing: Double)? {
        guard let projected = PlaneRectangular.forward(
            latitudeDegrees: latitude,
            longitudeDegrees: longitude,
            zone: zone
        ) else { return nil }
        return (projected.eastingMeters, projected.northingMeters)
    }

    /// AC1021、UTF-8、メートル、X が東、Y が北。
    public static var dxf: Data {
        let east = plane()?.easting ?? -18344.214
        let north = plane()?.northing ?? -155290.823
        let body = """
        0
        SECTION
        2
        HEADER
        9
        $ACADVER
        1
        AC1021
        9
        $INSUNITS
        70
        6
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        LINE
        8
        図
        10
        \(east)
        20
        \(north)
        11
        \(east + 80)
        21
        \(north + 40)
        0
        ENDSEC
        0
        EOF

        """
        return Data(body.utf8)
    }

    /// 現場パックの基準点。標高は標高のままにし、楕円体高には入れない。
    public static var csv: Data {
        var lines = ["id,name,kind,grade,latitude_deg,longitude_deg,height_m,height_kind,source_note"]
        for index in 1...pointCount {
            let name = String(format: "P%02d", index)
            let lat = latitude + Double(index) * 0.00004
            let lon = longitude + Double(index) * 0.00004
            lines.append("\(name),\(name),基準点,,\(lat),\(lon),\(400 + index),orthometric,合成")
        }
        return Data(lines.joined(separator: "\n").appending("\n").utf8)
    }

    /// 平面直角の SIMA。標高は入れるが、楕円体高としては読まない。
    public static var sima: Data {
        let east = plane()?.easting ?? -18344.214
        let north = plane()?.northing ?? -155290.823
        var lines = ["G00,02,"]
        for index in 1...4 {
            lines.append(String(
                format: "A01,%d,S%02d,%.3f,%.3f,450.000,",
                index,
                index,
                north + Double(index) * 8,
                east + Double(index) * 6
            ))
        }
        return Data(lines.joined(separator: "\n").appending("\n").utf8)
    }
}
