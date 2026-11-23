import XCTest
@testable import SurveyCore

final class DeliveryTests: XCTestCase {
    func testStageRisesWithTheInstrumentAndDropsOneStepWithoutStopping() {
        var held = PositionStage.iphone
        let raised = StageLadder.step(held: held, reported: fix(quality: .rtkFix))
        XCTAssertEqual(raised.stage, .rtk)
        XCTAssertFalse(raised.steppedDown)
        XCTAssertTrue(raised.continues)
        XCTAssertTrue(raised.notice.contains("上げました"))
        held = raised.stage

        let floated = StageLadder.step(held: held, reported: fix(quality: .float))
        XCTAssertEqual(floated.stage, .clas)
        XCTAssertTrue(floated.steppedDown)
        XCTAssertTrue(floated.continues)
        XCTAssertTrue(floated.notice.contains("1段") || floated.notice.contains("段階1"))
        held = floated.stage

        let stillFloat = StageLadder.step(held: held, reported: fix(quality: .float))
        XCTAssertEqual(stillFloat.stage, .clas)
        XCTAssertFalse(stillFloat.steppedDown)

        let alone = StageLadder.step(held: held, reported: fix(quality: .standalone))
        XCTAssertEqual(alone.stage, .iphone)
        XCTAssertTrue(alone.steppedDown)
        XCTAssertTrue(alone.continues)

        let unplugged = StageLadder.step(held: .rtk, reported: samplePosition())
        XCTAssertEqual(unplugged.stage, .iphone)
        XCTAssertTrue(unplugged.continues)

        let clasUp = StageLadder.step(held: .iphone, reported: samplePosition(stage: .clas, quality: .clas, receiver: .clas))
        XCTAssertEqual(clasUp.stage, .clas)

        XCTAssertFalse(StageGate.allowsRecording(workID: "boundary", stage: .clas))
        XCTAssertFalse(StageGate.allowsRecording(workID: "boundary", stage: .iphone))
        XCTAssertTrue(StageGate.allowsRecording(workID: "boundary", stage: .rtk))
        XCTAssertTrue(StageGate.allowsRecording(workID: "preview", stage: .iphone))

        let banner = StageDropNotice.recordingStopped
        XCTAssertEqual(StageDropNotice.resolve(current: nil, stage: .clas, quality: .float), nil)
        XCTAssertTrue(StageDropNotice.downgradeIsCurrent(stage: .clas, quality: .float))
        XCTAssertEqual(StageDropNotice.resolve(current: banner, stage: .clas, quality: .float), banner)
        XCTAssertEqual(StageDropNotice.resolve(current: banner, stage: .rtk, quality: .float), banner)
        XCTAssertFalse(StageDropNotice.downgradeIsCurrent(stage: .rtk, quality: .rtkFix))
        XCTAssertNil(StageDropNotice.resolve(current: banner, stage: .rtk, quality: .rtkFix))
        XCTAssertEqual(
            StageDropNotice.resolve(current: "T1を残しました", stage: .rtk, quality: .rtkFix),
            "T1を残しました"
        )

        let demoted = AccuracyPolicy.badge(
            for: PositionReading(position: fix(quality: .float), availability: .available),
            stageNotice: floated.notice,
            demoteForStageDrop: true
        )
        XCTAssertEqual(demoted.solutionLabel, "FLOAT")
        XCTAssertEqual(demoted.tone, .yellow)
        XCTAssertTrue(demoted.text.hasPrefix("FLOAT"))
        XCTAssertTrue(demoted.guidance.contains("下げました"))
        XCTAssertFalse(demoted.isStakeoutGrade)
    }

    func testObservationConditionIsOnTheReportAndOldJSONStillLoads() throws {
        let position = samplePosition(
            accuracy: 0.02,
            verticalAccuracy: 0.03,
            stage: .rtk,
            quality: .rtkFix,
            receiver: .rtk,
            satelliteCount: 18,
            satellites: [
                SatelliteCount(system: .gps, count: 8),
                SatelliteCount(system: .qzss, count: 4),
                SatelliteCount(system: .galileo, count: 6)
            ],
            pdop: 1.2,
            correctionAgeSeconds: 1.4,
            correctionSource: "VRS"
        )
        let condition = ObservationCondition.snapshot(position: position, stage: .rtk, durationSeconds: 30, epochCount: 42)
        let lines = condition.reportLines.joined(separator: "\n")
        XCTAssertTrue(lines.contains("解 FIX"))
        XCTAssertTrue(lines.contains("GPS 8"))
        XCTAssertTrue(lines.contains("QZSS 4"))
        XCTAssertTrue(lines.contains("衛星 18"))
        XCTAssertTrue(lines.contains("PDOP 1.2"))
        XCTAssertTrue(lines.contains("補正の遅れ 1.4秒"))
        XCTAssertTrue(lines.contains("補正元 VRS"))
        XCTAssertTrue(lines.contains("30秒"))
        XCTAssertTrue(lines.contains("42エポック"))
        XCTAssertTrue(lines.contains("機器 RTK"))
        XCTAssertTrue(lines.contains("段階2"))

        let observation = FieldObservation(name: "T1", workID: "boundary", captured: position, fixDurationSeconds: 30, condition: condition)
        let encoded = try JSONEncoder().encode(observation)
        let decoded = try JSONDecoder().decode(FieldObservation.self, from: encoded)
        XCTAssertEqual(decoded.condition?.epochCount, 42)
        XCTAssertEqual(decoded.condition?.pdop ?? 0, 1.2, accuracy: 1e-9)

        let old = #"{"name":"K1","latitudeDegrees":36,"longitudeDegrees":140,"horizontalAccuracyMeters":0.02,"fixDurationSeconds":30,"recordedAt":"2026-10-20T00:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(CoordinateBookEntry.self, from: Data(old.utf8))
        XCTAssertEqual(entry.name, "K1")
        XCTAssertNil(entry.kind)
        XCTAssertNil(entry.stage)
        XCTAssertNil(entry.pdop)
    }

    func testFilterCombinesAndOnlyTheMatchesAreExported() throws {
        let early = Date(timeIntervalSince1970: 1_792_454_400)
        let later = early.addingTimeInterval(86_400)
        let inside = sampleEntry(name: "T1", latitude: 35.68, longitude: 139.76, accuracy: 0.02, at: early, kind: "基準点", source: "観測", stage: .rtk, solution: .rtkFix)
        let outside = sampleEntry(name: "T2", latitude: 34.0, longitude: 135.0, accuracy: 0.02, at: early, kind: "基準点", source: "観測", stage: .rtk, solution: .rtkFix)
        let rough = sampleEntry(name: "A1", latitude: 35.681, longitude: 139.77, accuracy: 3, at: early, kind: "下見", source: "観測", stage: .iphone, solution: .standalone)
        let otherDay = sampleEntry(name: "T3", latitude: 35.682, longitude: 139.78, accuracy: 0.02, at: later, kind: "基準点", source: "取込", stage: .rtk, solution: .float)
        let entries = [inside, outside, rough, otherDay]
        let query = CoordinateBookQuery(
            namePrefix: "T",
            kind: "基準点",
            source: "観測",
            minimumStage: .rtk,
            maximumHorizontalMeters: 0.05,
            importedDay: "2026-10-20",
            bounds: GeoBounds(south: 35.6, west: 139.7, north: 35.8, east: 139.9)
        )
        let filtered = CoordinateBookQuery.apply(entries, query: query)
        XCTAssertEqual(filtered.map(\.name), ["T1"])

        let sima = CoordinateDelivery.sima(filtered, zone: 9)
        XCTAssertTrue(sima.contains("G00,02,"))
        XCTAssertTrue(sima.contains("A01,1,T1,"))
        XCTAssertFalse(sima.contains("T2"))
        XCTAssertTrue(sima.contains("A99,"))
        let plane = try XCTUnwrap(PlaneRectangular.forward(latitudeDegrees: 35.68, longitudeDegrees: 139.76, zone: 9))
        XCTAssertTrue(sima.contains(String(format: "%.3f", plane.northingMeters)))

        let csv = CoordinateDelivery.csv(filtered, zone: 9)
        XCTAssertTrue(csv.contains("点名,種類,出典,解"))
        XCTAssertTrue(csv.contains("T1,基準点,観測,FIX,2,"))
        XCTAssertTrue(csv.contains("PDOP"))

        let dxf = try DXFParser.parse(Data(CoordinateDelivery.dxf(filtered, zone: 9).utf8))
        XCTAssertTrue(dxf.entities.contains { entity in
            if case let .point(point) = entity.primitive {
                return abs(point.x - plane.eastingMeters) < 0.01 && abs(point.y - plane.northingMeters) < 0.01
            }
            return false
        })
        XCTAssertEqual(try text(in: dxf), "T1")

        let sfc = try SFCParser.parse(Data(CoordinateDelivery.sfc(filtered, zone: 9).utf8))
        XCTAssertEqual(sfc.layers.first?.name, "座標")
        XCTAssertTrue(sfc.entities.contains { entity in
            if case let .point(point) = entity.primitive {
                return abs(point.x - plane.eastingMeters) < 0.01 && abs(point.y - plane.northingMeters) < 0.01
            }
            return false
        })

        let sheet = CoordinateDelivery.sheet(filtered, zone: 9)
        XCTAssertTrue(sheet.contains("出来形管理表"))
        XCTAssertTrue(sheet.contains("解 FIX"))
        XCTAssertTrue(sheet.contains("設計値は未入力"))
        XCTAssertTrue(sheet.contains("点群と3Dはこの表に入れません"))
        let pdf = CoordinateDelivery.pdf(filtered, zone: 9)
        XCTAssertTrue(pdf.starts(with: Data("%PDF".utf8)))
        XCTAssertTrue(String(decoding: pdf, as: UTF8.self).contains("T1"))
        XCTAssertFalse(CoordinateDelivery.pointCloudNote.isEmpty)
    }

    private func fix(quality: FixQuality) -> GeodeticPosition {
        samplePosition(accuracy: 0.02, verticalAccuracy: 0.03, stage: .rtk, quality: quality, receiver: .rtk)
    }

    private func sampleEntry(
        name: String,
        latitude: Double,
        longitude: Double,
        accuracy: Double,
        at: Date,
        kind: String,
        source: String,
        stage: PositionStage,
        solution: FixQuality
    ) -> CoordinateBookEntry {
        CoordinateBookEntry(
            name: name,
            latitudeDegrees: latitude,
            longitudeDegrees: longitude,
            ellipsoidalHeightMeters: 12.4,
            horizontalAccuracyMeters: accuracy,
            verticalAccuracyMeters: accuracy,
            satelliteCount: 18,
            fixDurationSeconds: 10,
            recordedAt: at,
            kind: kind,
            source: source,
            stage: stage,
            solution: solution,
            pdop: 1.1,
            correctionAgeSeconds: 0.8,
            correctionSource: "VRS",
            epochCount: 12,
            receiverLabel: "RTK",
            satelliteNote: "18（GPS 8、QZSS 4）"
        )
    }

    private func text(in document: DrawingDocument) throws -> String {
        for entity in document.entities {
            if case let .text(_, value, _, _) = entity.primitive { return value }
        }
        throw XCTSkip("文字がない")
    }
}
