import XCTest
@testable import SurveyCore

final class FieldRecordStoreTests: XCTestCase {
    func testPlaceAndDayFolders() {
        XCTAssertEqual(FieldRecordStore.coordinatePlace(latitude: 35.68123, longitude: 139.76712), "35.68_139.77")
        XCTAssertEqual(
            FieldRecordStore.placeFolder(" 千代田区 ", latitude: 35.68, longitude: 139.77),
            "千代田区"
        )
        XCTAssertEqual(
            FieldRecordStore.placeFolder("a/b:c", latitude: 1, longitude: 2),
            "a・b・c"
        )
        XCTAssertEqual(FieldRecordStore.placeFolder("  ", latitude: 35.681, longitude: 139.767), "35.68_139.77")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let date = Date(timeIntervalSince1970: 1_761_000_000)
        let day = FieldRecordStore.dayFolder(date, calendar: calendar)
        XCTAssertEqual(day.count, 10)
        XCTAssertTrue(day.contains("-"))
    }

    func testWriteUsesPlaceAndDate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("records-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 3, minute: 4, second: 5))!
        let point = FieldPointFile(
            name: "T1",
            latitude: 35.68123,
            longitude: 139.76712,
            ellipsoidalHeightMeters: 24.5,
            horizontalAccuracyMeters: 5,
            verticalAccuracyMeters: 8,
            timestamp: date
        )
        let url = try FieldRecordStore.write(point, root: root, place: "千代田", calendar: calendar)
        XCTAssertTrue(url.path.hasSuffix("千代田/2026-10-21/T1-030405.json"), url.path)
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder.iso8601.decode(FieldPointFile.self, from: data)
        XCTAssertEqual(decoded.name, "T1")
        XCTAssertEqual(decoded.latitude, 35.68123)
        XCTAssertEqual(decoded.ellipsoidalHeightMeters, 24.5)
        XCTAssertEqual(decoded.horizontalAccuracyMeters, 5)
    }

    func testPinsAreTodaysPointsInTimeOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("records-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 1, minute: 0, second: 0))!
        let later = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 9, minute: 0, second: 0))!
        let otherDay = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12, minute: 0, second: 0))!
        _ = try FieldRecordStore.write(sample("B", at: later, latitude: 35.2), root: root, place: "港区", calendar: calendar)
        _ = try FieldRecordStore.write(sample("A", at: morning, latitude: 35.1), root: root, place: "千代田", calendar: calendar)
        _ = try FieldRecordStore.write(sample("C", at: otherDay, latitude: 35.3), root: root, place: "千代田", calendar: calendar)
        let pins = FieldRecordStore.pins(in: root, on: morning, calendar: calendar)
        XCTAssertEqual(pins.map(\.number), [1, 2])
        XCTAssertEqual(pins.map(\.name), ["A", "B"])
        XCTAssertEqual(pins.map(\.place), ["千代田", "港区"])
        XCTAssertEqual(pins[0].caption, "記録 #1 ・千代田/2026-10-21")
        XCTAssertEqual(pins[1].day, "2026-10-21")
        XCTAssertEqual(pins[0].folderURL.lastPathComponent, "2026-10-21")
    }

    private func sample(_ name: String, at date: Date, latitude: Double) -> FieldPointFile {
        FieldPointFile(
            name: name,
            latitude: latitude,
            longitude: 139.7,
            ellipsoidalHeightMeters: 1,
            horizontalAccuracyMeters: 3,
            verticalAccuracyMeters: nil,
            timestamp: date
        )
    }
}

private extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
