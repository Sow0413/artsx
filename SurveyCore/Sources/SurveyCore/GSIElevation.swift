import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 地理院の標高 API。現在地の DEM と、画面の標高との差。
/// 出典: https://cyberjapandata2.gsi.go.jp/general/dem/scripts/getelevation.php
public enum GSIElevationPolicy {
    public static let moveMeters = 10.0
    public static let refreshSeconds: TimeInterval = 30
    /// この差を超えたときだけ、差を橙にする。
    public static let differenceAlertMeters = 5.0

    public struct Fix: Equatable, Sendable {
        public var latitudeDegrees: Double
        public var longitudeDegrees: Double
        public var at: Date

        public init(latitudeDegrees: Double, longitudeDegrees: Double, at: Date) {
            self.latitudeDegrees = latitudeDegrees
            self.longitudeDegrees = longitudeDegrees
            self.at = at
        }
    }

    /// 10 m を超えて動いたとき、または前回から 30 秒たったときに取りにいく。
    public static func shouldRequest(last: Fix?, latitudeDegrees: Double, longitudeDegrees: Double, now: Date) -> Bool {
        guard let last else { return true }
        if now.timeIntervalSince(last.at) >= refreshSeconds { return true }
        let moved = GeoDistance.meters(
            latitude1: last.latitudeDegrees,
            longitude1: last.longitudeDegrees,
            latitude2: latitudeDegrees,
            longitude2: longitudeDegrees
        )
        return moved > moveMeters
    }
}

/// 地図の1行。差は 標高 − 地理院。データが無いときは行を出さない。
public struct GSIElevationLine: Equatable, Sendable {
    public var prefix: String
    public var difference: String?
    public var highlightDifference: Bool

    public init(prefix: String, difference: String?, highlightDifference: Bool) {
        self.prefix = prefix
        self.difference = difference
        self.highlightDifference = highlightDifference
    }

    public var spoken: String {
        prefix + (difference ?? "")
    }
}

public enum GSIElevationText {
    public static func line(demMeters: Double, gnssMeters: Double?) -> GSIElevationLine? {
        guard demMeters.isFinite else { return nil }
        let prefix = "地理院 \(FixedNumber.string(demMeters, fractionDigits: 1))m"
        guard let gnssMeters, gnssMeters.isFinite else {
            return GSIElevationLine(prefix: prefix, difference: nil, highlightDifference: false)
        }
        let demShown = (demMeters * 10).rounded() / 10
        let gnssShown = (gnssMeters * 10).rounded() / 10
        let diff = gnssShown - demShown
        let difference = "（差 \(signed(diff))m）"
        return GSIElevationLine(
            prefix: prefix,
            difference: difference,
            highlightDifference: abs(diff) > GSIElevationPolicy.differenceAlertMeters
        )
    }

    private static func signed(_ value: Double) -> String {
        String(format: "%+.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

public enum GSIElevationAPI {
    public static let endpoint = "https://cyberjapandata2.gsi.go.jp/general/dem/scripts/getelevation.php"
    public static let userAgent = "artsx/1.0 (iOS; GSI elevation)"

    public static func url(latitudeDegrees: Double, longitudeDegrees: Double) -> URL? {
        guard latitudeDegrees.isFinite, longitudeDegrees.isFinite,
              abs(latitudeDegrees) <= 90, abs(longitudeDegrees) <= 180 else { return nil }
        var parts = URLComponents(string: endpoint)
        let posix = Locale(identifier: "en_US_POSIX")
        parts?.queryItems = [
            URLQueryItem(name: "lon", value: String(format: "%.6f", locale: posix, longitudeDegrees)),
            URLQueryItem(name: "lat", value: String(format: "%.6f", locale: posix, latitudeDegrees)),
            URLQueryItem(name: "outtype", value: "JSON")
        ]
        return parts?.url
    }

    /// 数値が無い、または "-----" のときは nil。行は出さない。
    public static func parse(_ data: Data) -> Double? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return payload.elevation.meters
    }

    public static func fetch(latitudeDegrees: Double, longitudeDegrees: Double, session: URLSession = .shared) async -> Double? {
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

    private struct Payload: Decodable {
        var elevation: Value
    }

    private enum Value: Decodable {
        case meters(Double)
        case missing

        var meters: Double? {
            if case .meters(let value) = self, value.isFinite { return value }
            return nil
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self), number.isFinite {
                self = .meters(number)
                return
            }
            if let text = try? container.decode(String.self) {
                if let number = Double(text), number.isFinite {
                    self = .meters(number)
                    return
                }
            }
            self = .missing
        }
    }
}

public struct GSIElevationCache: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public var latitudeDegrees: Double
        public var longitudeDegrees: Double
        public var meters: Double
        public var fetchedAt: Date

        public init(latitudeDegrees: Double, longitudeDegrees: Double, meters: Double, fetchedAt: Date) {
            self.latitudeDegrees = latitudeDegrees
            self.longitudeDegrees = longitudeDegrees
            self.meters = meters
            self.fetchedAt = fetchedAt
        }
    }

    public static let capacity = 64

    public private(set) var entries: [Entry]
    public private(set) var lastRequest: GSIElevationPolicy.Fix?

    public init() {
        entries = []
        lastRequest = nil
    }

    public func fresh(latitudeDegrees: Double, longitudeDegrees: Double, now: Date) -> Entry? {
        let near = entries.filter { entry in
            now.timeIntervalSince(entry.fetchedAt) < GSIElevationPolicy.refreshSeconds
                && GeoDistance.meters(
                    latitude1: entry.latitudeDegrees,
                    longitude1: entry.longitudeDegrees,
                    latitude2: latitudeDegrees,
                    longitude2: longitudeDegrees
                ) <= GSIElevationPolicy.moveMeters
        }
        return near.min { lhs, rhs in
            GeoDistance.meters(
                latitude1: lhs.latitudeDegrees,
                longitude1: lhs.longitudeDegrees,
                latitude2: latitudeDegrees,
                longitude2: longitudeDegrees
            ) < GeoDistance.meters(
                latitude1: rhs.latitudeDegrees,
                longitude1: rhs.longitudeDegrees,
                latitude2: latitudeDegrees,
                longitude2: longitudeDegrees
            )
        }
    }

    public func shouldRequest(latitudeDegrees: Double, longitudeDegrees: Double, now: Date) -> Bool {
        GSIElevationPolicy.shouldRequest(
            last: lastRequest,
            latitudeDegrees: latitudeDegrees,
            longitudeDegrees: longitudeDegrees,
            now: now
        )
    }

    public mutating func noteRequest(latitudeDegrees: Double, longitudeDegrees: Double, at date: Date) {
        lastRequest = GSIElevationPolicy.Fix(latitudeDegrees: latitudeDegrees, longitudeDegrees: longitudeDegrees, at: date)
    }

    public mutating func remember(_ entry: Entry) {
        entries.removeAll { existing in
            GeoDistance.meters(
                latitude1: existing.latitudeDegrees,
                longitude1: existing.longitudeDegrees,
                latitude2: entry.latitudeDegrees,
                longitude2: entry.longitudeDegrees
            ) <= 1
        }
        entries.append(entry)
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }
}
