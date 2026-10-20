import XCTest
@testable import SurveyCore

final class WorkAccuracyTests: XCTestCase {
    func testProvisionalTolerances() {
        let works = Dictionary(uniqueKeysWithValues: WorkCatalog.provisional.works.map { ($0.id, $0) })
        XCTAssertEqual(works["preview"]?.horizontalMeters, 5)
        XCTAssertEqual(works["rough"]?.horizontalMeters, 0.5)
        XCTAssertEqual(works["traverse"]?.horizontalMeters, 0.02)
        XCTAssertEqual(works["stakeout"]?.horizontalMeters, 0.02)
        XCTAssertEqual(works["stakeout"]?.verticalMeters, 0.01)
        XCTAssertEqual(works["asBuilt"]?.horizontalMeters, 0.05)
        XCTAssertEqual(works["boundary"]?.horizontalMeters, 0.02)
        XCTAssertEqual(WorkCatalog.provisional.optimisticSafetyFactor, 2)
    }

    func testCatalogRoundTripKeepsEditedTolerancesAndNewWorks() throws {
        var catalog = WorkCatalog.provisional
        var stakeout = catalog.works.first { $0.id == "stakeout" }!
        stakeout.horizontalMeters = 0.03
        stakeout.verticalMeters = 0.015
        catalog = catalog.replacing(stakeout).selecting("stakeout")
        catalog.optimisticSafetyFactor = 3
        let directory = try TestFiles.directory()
        defer { TestFiles.remove(directory) }
        try catalog.save(to: directory)
        let loaded = WorkCatalog.load(from: directory)
        XCTAssertEqual(loaded.selected.horizontalMeters, 0.03, accuracy: 1e-12)
        XCTAssertEqual(loaded.selected.verticalMeters, 0.015, accuracy: 1e-12)
        XCTAssertEqual(loaded.optimisticSafetyFactor, 3, accuracy: 1e-12)
        XCTAssertEqual(loaded.works.count, WorkCatalog.provisional.works.count)
        XCTAssertEqual(WorkCatalog.load(from: directory.appendingPathComponent("missing")).selectedID, "preview")
    }

    func testSamePhoneIsGreenForPreviewAndRedForStakeout() {
        let phone = samplePosition(accuracy: 3.2, verticalAccuracy: 4)
        let preview = AccuracyPolicy.badge(for: PositionReading(position: phone, availability: .available), work: work("preview"))
        let rough = AccuracyPolicy.badge(for: PositionReading(position: phone, availability: .available), work: work("rough"))
        let stakeout = AccuracyPolicy.badge(for: PositionReading(position: phone, availability: .available), work: work("stakeout"))
        XCTAssertEqual(preview.tone, .green)
        XCTAssertEqual(preview.guidance, "")
        XCTAssertEqual(rough.tone, .red)
        XCTAssertEqual(stakeout.tone, .red)
        XCTAssertTrue(stakeout.guidance.contains("水平があと318cm足りません"))
        XCTAssertTrue(stakeout.guidance.contains("届く手段: TS"))
        XCTAssertFalse(stakeout.guidance.contains("CLAS"))
        XCTAssertFalse(stakeout.guidance.contains("三角点補正"))
    }

    func testWithinTwiceTheRequirementIsYellow() {
        let position = samplePosition(accuracy: 0.8, verticalAccuracy: 0.4)
        let badge = AccuracyPolicy.badge(for: PositionReading(position: position, availability: .available), work: work("rough"))
        XCTAssertEqual(badge.tone, .yellow)
        XCTAssertTrue(badge.guidance.contains("水平があと30cm足りません"))
        XCTAssertTrue(badge.guidance.contains("三角点補正"))
        XCTAssertTrue(badge.guidance.contains("CLAS"))
    }

    func testOptimisticInstrumentUsesTheSafetyFactor() throws {
        let phone = samplePosition(accuracy: 3, verticalAccuracy: 3)
        var trust = InstrumentTrust()
        trust = trust.setting(InstrumentState(phone), optimistic: true)
        let plain = AccuracyPolicy.badge(for: PositionReading(position: phone, availability: .available), work: work("preview"))
        let cautious = AccuracyPolicy.badge(
            for: PositionReading(position: phone, availability: .available),
            work: work("preview"),
            trust: trust,
            safetyFactor: 2
        )
        XCTAssertEqual(plain.tone, .green)
        XCTAssertEqual(cautious.tone, .yellow)
        XCTAssertTrue(cautious.caution.contains("2倍"))
        XCTAssertTrue(cautious.guidance.contains("水平があと100cm"))
        let directory = try TestFiles.directory()
        defer { TestFiles.remove(directory) }
        try trust.save(to: directory)
        XCTAssertTrue(InstrumentTrust.load(from: directory).contains(InstrumentState(phone)))
        let cleared = trust.setting(InstrumentState(phone), optimistic: false)
        XCTAssertFalse(cleared.contains(InstrumentState(phone)))
    }

    func testMissingHeightDoesNotTurnGreen() {
        let position = samplePosition(accuracy: 0.01, verticalAccuracy: nil)
        let badge = AccuracyPolicy.badge(for: PositionReading(position: position, availability: .available), work: work("stakeout"))
        XCTAssertEqual(badge.tone, .yellow)
        XCTAssertTrue(badge.guidance.contains("高さが未取得"))
    }

    func testObservationKeepsPreviewAccuracyWhenRebasedOntoATraversePoint() throws {
        let captured = samplePosition(accuracy: 4.2, verticalAccuracy: 6)
        let original = FieldObservation(name: "小屋", workID: "preview", captured: captured)
        let traverse = samplePosition(latitude: 35.6815, longitude: 139.7674, accuracy: 0.02, verticalAccuracy: 0.02, stage: .rtk, quality: .rtkFix, receiver: .rtk)
        let rebased = original.rebase(onto: traverse)
        XCTAssertEqual(rebased.workID, "preview")
        XCTAssertEqual(rebased.captured, captured)
        XCTAssertEqual(rebased.horizontalAccuracyAtCapture, 4.2, accuracy: 1e-12)
        XCTAssertEqual(rebased.verticalAccuracyAtCapture ?? -1, 6, accuracy: 1e-12)
        XCTAssertEqual(rebased.adopted?.latitudeDegrees ?? 0, traverse.latitudeDegrees, accuracy: 1e-12)
        XCTAssertEqual(rebased.adopted?.horizontalAccuracyMeters ?? -1, 0.02, accuracy: 1e-12)

        let directory = try TestFiles.directory()
        defer { TestFiles.remove(directory) }
        let log = FieldObservationLog().appending(original).replacing(rebased)
        try log.save(to: directory)
        let loaded = FieldObservationLog.load(from: directory)
        XCTAssertEqual(loaded.observations.first?.captured.horizontalAccuracyMeters ?? -1, 4.2, accuracy: 1e-9)
        XCTAssertEqual(loaded.observations.first?.adopted?.longitudeDegrees ?? 0, traverse.longitudeDegrees, accuracy: 1e-12)
    }

    private func work(_ id: String) -> WorkRequirement {
        WorkCatalog.provisional.works.first { $0.id == id }!
    }
}
