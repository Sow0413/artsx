import XCTest
@testable import SurveyCore

final class BasicExchangeTests: XCTestCase {
    func testCSVAndSIMARoundTripKeepThePoint() throws {
        let entry = CoordinateBookEntry(
            name: "G1",
            latitudeDegrees: 35.11561,
            longitudeDegrees: 136.90213,
            ellipsoidalHeightMeters: 40.8,
            horizontalAccuracyMeters: 0.02,
            verticalAccuracyMeters: 0.03,
            satelliteCount: 12,
            fixDurationSeconds: 30,
            recordedAt: Date(timeIntervalSince1970: 1_792_454_400),
            kind: "GCP",
            source: "観測",
            solution: .rtkFix,
            receiverLabel: "RTK"
        )
        let csv = CoordinateExchange.parse(data: Data(CoordinateDelivery.csv([entry], zone: 7).utf8), filename: "座標一覧.csv", zone: 7)
        XCTAssertEqual(csv.first?.name, "G1")
        XCTAssertEqual(csv.first?.kind, "GCP")
        XCTAssertEqual(csv.first?.solution, .rtkFix)
        XCTAssertEqual(csv.first?.latitudeDegrees ?? 0, 35.11561, accuracy: 1e-6)

        let sima = CoordinateExchange.parse(data: Data(CoordinateDelivery.sima([entry], zone: 7).utf8), filename: "座標.sima", zone: 7)
        XCTAssertEqual(sima.first?.name, "G1")
        XCTAssertEqual(sima.first?.latitudeDegrees ?? 0, entry.latitudeDegrees, accuracy: 1e-5)
        XCTAssertEqual(sima.first?.longitudeDegrees ?? 0, entry.longitudeDegrees, accuracy: 1e-5)
    }

    func testBackupRestoresAProjectBook() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try ProjectStore.create(name: "現場A", at: root)
        let entry = CoordinateBookEntry(
            name: "T1",
            latitudeDegrees: 35.1,
            longitudeDegrees: 136.9,
            ellipsoidalHeightMeters: 10,
            horizontalAccuracyMeters: 1,
            verticalAccuracyMeters: nil,
            satelliteCount: nil,
            fixDurationSeconds: 0,
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000),
            kind: "下見"
        )
        try ProjectStore.saveCoordinate(entry, projectName: project.name, at: root)
        let backup = BasicBackup.capture(at: root)
        let data = try XCTUnwrap(backup.data())
        try FileManager.default.removeItem(at: root)
        let loaded = try XCTUnwrap(BasicBackup.load(data))
        XCTAssertEqual(try loaded.restore(at: root), 1)
        let restored = ProjectStore.coordinateBookEntries(projectName: "現場A", at: root)
        XCTAssertEqual(restored.map(\.name), ["T1"])
        XCTAssertEqual(restored.first?.kind, "下見")
    }

    func testStakeoutReportsNorthAndEastWithoutMotion() {
        let here = samplePosition(latitude: 35.11561, longitude: 136.90213, height: 40.8, quality: .rtkFix, receiver: .rtk)
        let target = CoordinateBookEntry(
            name: "P1",
            latitudeDegrees: 35.11571,
            longitudeDegrees: 136.90213,
            ellipsoidalHeightMeters: 41.0,
            horizontalAccuracyMeters: 0,
            verticalAccuracyMeters: nil,
            satelliteCount: nil,
            fixDurationSeconds: 0,
            recordedAt: Date(),
            kind: "設計"
        )
        let guide = BasicStakeout.guide(from: here, to: target, zone: 7)
        XCTAssertNotNil(guide)
        XCTAssertGreaterThan(guide?.northMeters ?? 0, 5)
        XCTAssertLessThan(abs(guide?.eastMeters ?? 10), 5)
        XCTAssertEqual(guide?.heightMeters ?? 0, -0.2, accuracy: 0.001)
        XCTAssertEqual(guide?.solution, .rtkFix)
        XCTAssertTrue(guide?.line.contains("FIX") == true)
    }
}
