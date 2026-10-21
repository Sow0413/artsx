import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 国土地理院「ジオイド2024日本とその周辺」。標高 = 楕円体高 −（ジオイド高 + 基準面補正量）。
/// 格子ファイルはログインが要るため、公式の計算 API の値を使う。出典: 国土地理院。
public enum GSIGeoid2024Policy {
    /// ジオイドは 1 km で数 cm。500 m 以内の計算結果をそのまま使う。
    public static let reuseMeters = 500.0

    public static func shouldRequest(last: GSIElevationPolicy.Fix?, latitudeDegrees: Double, longitudeDegrees: Double, now: Date) -> Bool {
        GSIElevationPolicy.shouldRequest(
            last: last,
            latitudeDegrees: latitudeDegrees,
            longitudeDegrees: longitudeDegrees,
            now: now
        )
    }
}

public struct GSIGeoid2024Sample: Equatable, Sendable {
    public var geoidMeters: Double
    public var referenceConversionMeters: Double
    /// 楕円体高から引く量。本土では基準面補正は 0。
    public var separationMeters: Double

    public init(geoidMeters: Double, referenceConversionMeters: Double, separationMeters: Double) {
        self.geoidMeters = geoidMeters
        self.referenceConversionMeters = referenceConversionMeters
        self.separationMeters = separationMeters
    }
}

public struct GSIGeoid2024Cache: Equatable, Sendable {
    public private(set) var lastRequest: GSIElevationPolicy.Fix?

    public init() {
        lastRequest = nil
    }

    public func shouldRequest(latitudeDegrees: Double, longitudeDegrees: Double, now: Date) -> Bool {
        GSIGeoid2024Policy.shouldRequest(
            last: lastRequest,
            latitudeDegrees: latitudeDegrees,
            longitudeDegrees: longitudeDegrees,
            now: now
        )
    }

    public mutating func noteRequest(latitudeDegrees: Double, longitudeDegrees: Double, at date: Date) {
        lastRequest = GSIElevationPolicy.Fix(latitudeDegrees: latitudeDegrees, longitudeDegrees: longitudeDegrees, at: date)
    }
}

public enum GSIGeoid2024API {
    public static let endpoint = "https://vldb.gsi.go.jp/sokuchi/surveycalc/geoid/calcgh/cgi/geoidcalc.pl"
    public static let userAgent = "artsx/1.0 (iOS; GSI geoid 2024)"

    public static func url(latitudeDegrees: Double, longitudeDegrees: Double) -> URL? {
        guard latitudeDegrees.isFinite, longitudeDegrees.isFinite,
              abs(latitudeDegrees) <= 90, abs(longitudeDegrees) <= 180 else { return nil }
        var parts = URLComponents(string: endpoint)
        let posix = Locale(identifier: "en_US_POSIX")
        parts?.queryItems = [
            URLQueryItem(name: "outputType", value: "json"),
            URLQueryItem(name: "latitude", value: String(format: "%.8f", locale: posix, latitudeDegrees)),
            URLQueryItem(name: "longitude", value: String(format: "%.8f", locale: posix, longitudeDegrees))
        ]
        return parts?.url
    }

    /// -9999 は無効。受信機のジオイド高はここには入らない。
    public static func parse(_ data: Data) -> GSIGeoid2024Sample? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        let row = payload.output
        guard let geoid = meters(row.geoidHeight) else { return nil }
        let combined = meters(row.combined)
        let href = meters(row.href)
        let separation = combined ?? (href.map { geoid + $0 } ?? geoid)
        let reference = href ?? (combined.map { $0 - geoid } ?? 0)
        guard separation.isFinite, reference.isFinite else { return nil }
        return GSIGeoid2024Sample(
            geoidMeters: geoid,
            referenceConversionMeters: reference,
            separationMeters: separation
        )
    }

    public static func fetch(latitudeDegrees: Double, longitudeDegrees: Double, session: URLSession = .shared) async -> GSIGeoid2024Sample? {
        guard let url = url(latitudeDegrees: latitudeDegrees, longitudeDegrees: longitudeDegrees) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return parse(data)
        } catch {
            return nil
        }
    }

    private static func meters(_ text: String?) -> Double? {
        guard let text, let value = Double(text), value.isFinite, value > -1000 else { return nil }
        return value
    }

    private struct Payload: Decodable {
        var output: Row

        enum CodingKeys: String, CodingKey {
            case output = "OutputData"
        }
    }

    private struct Row: Decodable {
        var geoidHeight: String
        var href: String?
        var combined: String?

        enum CodingKeys: String, CodingKey {
            case geoidHeight
            case href = "HeightReferenceConversion"
            case combined = "geoidHeight+HeightReferenceConversion"
        }
    }
}
