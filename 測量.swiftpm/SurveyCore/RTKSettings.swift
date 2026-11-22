import Foundation

/// NTRIP 補正のマウントポイント。ドコモ高精度GNSS位置情報サービス。
/// 測地成果 2024 と 2011 は混ぜると座標がずれる（ドコモ注意）。案件の測地系に合わせる。
public enum RTKMountpoint: String, Codable, Sendable, CaseIterable, Identifiable {
    case rrsgd2024 = "RRSGD2024"   // 電子基準点＋ドコモ基準点・測地成果2024（推奨）
    case rrsg2024  = "RRSG2024"    // 電子基準点のみ・2024
    case rrsd2024  = "RRSD2024"    // ドコモ基準点のみ・2024
    case rrsgd     = "RRSGD"       // 電子基準点＋ドコモ基準点・測地成果2011
    case rrsg      = "RRSG"        // 電子基準点のみ・2011
    case rrsd      = "RRSD"        // ドコモ基準点のみ・2011

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .rrsgd2024: return "RRSGD2024（電子＋ドコモ・測地成果2024）"
        case .rrsg2024:  return "RRSG2024（電子基準点・2024）"
        case .rrsd2024:  return "RRSD2024（ドコモ基準点・2024）"
        case .rrsgd:     return "RRSGD（電子＋ドコモ・測地成果2011）"
        case .rrsg:      return "RRSG（電子基準点・2011）"
        case .rrsd:      return "RRSD（ドコモ基準点・2011）"
        }
    }
    public var datum2024: Bool { rawValue.contains("2024") }
}

/// RTK の接続設定。パスワードはここに持たず Keychain に置く。端末内の JSON に残す。
public struct RTKSettings: Codable, Sendable, Equatable {
    public var correctionsEnabled: Bool
    public var host: String
    public var port: UInt16
    public var mountpoint: RTKMountpoint
    public var user: String

    public init(correctionsEnabled: Bool = true,
                host: String = "d-gnss.jp",
                port: UInt16 = 2101,
                mountpoint: RTKMountpoint = .rrsgd2024,
                user: String = "") {
        self.correctionsEnabled = correctionsEnabled
        self.host = host
        self.port = port
        self.mountpoint = mountpoint
        self.user = user
    }
}

/// 端末内の JSON に残す（他の *Store に合わせた作り）。パスワードは含めない。
public enum RTKSettingsStore {
    public static func fileURL(in siteDirectory: URL) -> URL {
        siteDirectory.appendingPathComponent("RTK設定.json")
    }
    public static func load(from siteDirectory: URL) -> RTKSettings {
        let url = fileURL(in: siteDirectory)
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(RTKSettings.self, from: data) else {
            return RTKSettings()
        }
        return settings
    }
    public static func save(_ settings: RTKSettings, to siteDirectory: URL) {
        let url = fileURL(in: siteDirectory)
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
