import CoreLocation

enum PlaceGeocoder {
    /// 市区町村。取れなければ nil。記録フォルダの場所名に使う。
    static func locality(latitude: Double, longitude: Double) async -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let marks = try? await CLGeocoder().reverseGeocodeLocation(location)
        let mark = marks?.first
        let name = mark?.locality ?? mark?.subLocality ?? mark?.administrativeArea ?? mark?.name
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
