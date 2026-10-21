import Foundation

/// Drogger RWS / RWP / RWX（ZED-F9P）の BLE 設定。Classic SPP は iOS から使わない。
/// コマンドは https://drogger.hatenadiary.jp/rcv_config 。パスワードは載せない。
public enum DroggerLink {
    public static let minimumFirmware = "4.4.2"
    public static let firmwareQueryBody = "PBIZ,query,fwver"
    /// QZSS・GLONASS・Galileo・BeiDou・SBAS・SLAS・CLAS・SAS を有効、NavIC は無効。
    public static let clasBody = "PBIZ,gnss,1,1,1,1,0,1,1,1,1"

    public struct Firmware: Equatable, Sendable {
        public var version: String
        public var ble: Bool

        public init(version: String, ble: Bool) {
            self.version = version
            self.ble = ble
        }
    }

    public static func sentence(_ body: String) -> String {
        "$\(body)*\(NMEA.checksum(body))\r\n"
    }

    public static func isAtLeast(_ version: String, minimum: String = minimumFirmware) -> Bool {
        let left = parts(version)
        let right = parts(minimum)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return true
    }

    /// `$PBIZR,query,fwver,...`。bit0 が 1 のとき BLE。
    public static func firmware(in line: String) -> Firmware? {
        guard let sentence = NMEA.parse(line) else { return nil }
        let fields = sentence.fields
        guard fields.count >= 8, fields[0] == "query", fields[1] == "fwver" else { return nil }
        let flags = Int(fields[6]) ?? 0
        let version = fields[7]
        guard !version.isEmpty else { return nil }
        return Firmware(version: version, ble: flags & 1 == 1)
    }

    private static func parts(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }
}
