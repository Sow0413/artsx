import Foundation

/// 第VII系の重い図面。150,000 本の LINE で、左下から右上まで × を敷く。
public enum HeavyDrawingFixture {
    public static let lineCount = 150_000
    public static let southWest = PlanarPoint(x: -23877.120, y: -89828.129)
    public static let northEast = PlanarPoint(x: -22977.620, y: -88829.129)
    public static let zone = 7
    public static let southWestLatitude = 35.1900192
    public static let southWestLongitude = 136.9044756
    public static let northEastLatitude = 35.1990455
    public static let northEastLongitude = 136.9143249

    public static func makeDXF() -> Data {
        var data = Data()
        data.reserveCapacity(14_000_000)
        data.append(Data("""
        0
        SECTION
        2
        HEADER
        9
        $ACADVER
        1
        AC1015
        9
        $DWGCODEPAGE
        3
        ANSI_1252
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

        """.utf8))
        let columns = 250
        let rows = 300
        let dx = (northEast.x - southWest.x) / Double(columns)
        let dy = (northEast.y - southWest.y) / Double(rows)
        for row in 0..<rows {
            let y0 = southWest.y + Double(row) * dy
            let y1 = y0 + dy
            for column in 0..<columns {
                let x0 = southWest.x + Double(column) * dx
                let x1 = x0 + dx
                appendLine(&data, x0: x0, y0: y0, x1: x1, y1: y1)
                appendLine(&data, x0: x0, y0: y1, x1: x1, y1: y0)
            }
        }
        data.append(Data("0\nENDSEC\n0\nEOF\n".utf8))
        return data
    }

    private static func appendLine(_ data: inout Data, x0: Double, y0: Double, x1: Double, y1: Double) {
        var text = "0\nLINE\n8\nX\n10\n"
        text += number(x0)
        text += "\n20\n"
        text += number(y0)
        text += "\n11\n"
        text += number(x1)
        text += "\n21\n"
        text += number(y1)
        text += "\n"
        data.append(Data(text.utf8))
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
