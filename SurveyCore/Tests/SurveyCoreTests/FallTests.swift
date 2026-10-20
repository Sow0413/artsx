import XCTest
@testable import SurveyCore

final class FallTests: XCTestCase {
    func testImpactThenMotionDoesNotConfirm() {
        var detector = FallDetector()
        XCTAssertNil(detector.ingest(sample(0, user: 4, total: 4)))
        XCTAssertEqual(detector.phase, .confirmingStill)
        let signal = feed(&detector, user: 1.1, from: 0.1, to: 3)
        XCTAssertNil(signal)
        XCTAssertEqual(detector.phase, .idle)
        XCTAssertNil(detector.tick(at: date(20)))
    }

    func testStillnessOpensCancelAndButtonStopsIt() {
        var detector = FallDetector()
        XCTAssertNil(detector.ingest(sample(0, user: 4, total: 4)))
        let signal = feed(&detector, user: 0.1, from: 0.1, to: 2.1)
        XCTAssertEqual(signal, .awaitingCancel(.impact))
        XCTAssertEqual(detector.snapshot(at: date(2.1)).cancelRemaining ?? -1, 10, accuracy: 0.001)
        XCTAssertNil(detector.tick(at: date(12)))
        XCTAssertEqual(detector.cancel(at: date(12)), .cancelled)
        XCTAssertEqual(detector.phase, .cancelled)
        XCTAssertNil(detector.tick(at: date(30)))
    }

    func testUncancelledStillnessConfirmsImpact() {
        var detector = FallDetector()
        XCTAssertNil(detector.ingest(sample(0, user: 3, total: 3)))
        XCTAssertEqual(feed(&detector, user: 0.1, from: 0.1, to: 2.1), .awaitingCancel(.impact))
        XCTAssertEqual(detector.tick(at: date(12.1)), .confirmed(.impact))
        XCTAssertEqual(detector.phase, .confirmed)
    }

    func testFreefallBeforeImpactIsAFall() {
        var detector = FallDetector()
        XCTAssertNil(detector.ingest(sample(0, user: 0.1, total: 0.2)))
        XCTAssertEqual(detector.phase, .idle)
        XCTAssertNil(detector.ingest(sample(0.4, user: 5, total: 5)))
        XCTAssertEqual(feed(&detector, user: 0.1, from: 0.5, to: 2.5), .awaitingCancel(.fall))
    }

    func testOldFreefallDoesNotRenameTheImpact() {
        var detector = FallDetector()
        XCTAssertNil(detector.ingest(sample(0, user: 0.1, total: 0.2)))
        XCTAssertNil(detector.ingest(sample(3, user: 5, total: 5)))
        XCTAssertEqual(feed(&detector, user: 0.05, from: 3.1, to: 5.1), .awaitingCancel(.impact))
    }

    func testBelowThresholdStaysIdle() {
        var detector = FallDetector(limits: FallLimits.resolved(impactG: 4))
        XCTAssertNil(detector.ingest(sample(0, user: 3.9, total: 3.9)))
        XCTAssertEqual(detector.phase, .idle)
    }

    func testSparseSamplesDoNotCountAsStillness() {
        var detector = FallDetector()
        XCTAssertNil(detector.ingest(sample(0, user: 4, total: 4)))
        XCTAssertNil(detector.ingest(sample(0.1, user: 0.1, total: 1)))
        XCTAssertNil(detector.ingest(sample(2.1, user: 0.1, total: 1)))
        XCTAssertEqual(detector.phase, .confirmingStill)
        XCTAssertEqual(feed(&detector, user: 0.1, from: 2.2, to: 4.2), .awaitingCancel(.impact))
    }

    func testQuietPeriodBlocksASecondSpike() {
        var detector = FallDetector()
        XCTAssertNil(detector.ingest(sample(0, user: 4, total: 4)))
        XCTAssertEqual(feed(&detector, user: 0.1, from: 0.1, to: 2.1), .awaitingCancel(.impact))
        XCTAssertEqual(detector.tick(at: date(12.1)), .confirmed(.impact))
        XCTAssertNil(detector.ingest(sample(13, user: 6, total: 6)))
        XCTAssertEqual(detector.phase, .confirmed)
    }

    func testLateExternalFallConfirmsWithoutAnotherWait() {
        var detector = FallDetector()
        let signal = detector.noteExternal(kind: .fall, detectedAt: date(0), now: date(10), immediate: false)
        XCTAssertEqual(signal, .confirmed(.fall))
    }

    func testExternalFallCanStillBeCancelled() {
        var detector = FallDetector()
        XCTAssertEqual(
            detector.noteExternal(kind: .fall, detectedAt: date(0), now: date(1), immediate: false),
            .awaitingCancel(.fall)
        )
        XCTAssertEqual(detector.cancel(at: date(9)), .cancelled)
    }

    func testAcknowledgedWatchFallConfirmsImmediately() {
        var detector = FallDetector()
        XCTAssertEqual(
            detector.noteExternal(kind: .fall, detectedAt: date(0), now: date(1), immediate: true),
            .confirmed(.fall)
        )
    }

    func testLimitsClampAndKeepTenSeconds() {
        let low = FallLimits.resolved(impactG: 0.2, stillSeconds: 0, quietSeconds: nil)
        XCTAssertEqual(low.impactG, 1.5)
        XCTAssertEqual(low.stillSeconds, 1)
        XCTAssertEqual(low.cancelSeconds, 10)
        let high = FallLimits.resolved(impactG: 12, stillSeconds: 9)
        XCTAssertEqual(high.impactG, 8)
        XCTAssertEqual(high.stillSeconds, 5)
        XCTAssertEqual(FallLimits.resolved().impactG, FallLimits.defaultImpactG)
    }

    func testSpeechSaysRightRearFifteenMeters() {
        XCTAssertEqual(
            FallCall.speech(kind: .fall, distanceMeters: 15.2, relativeDegrees: 135),
            "右うしろ15m 転倒"
        )
        XCTAssertEqual(
            FallCall.speech(kind: .impact, distanceMeters: 14.4, relativeDegrees: -30),
            "左まえ14m 衝撃"
        )
    }

    func testAnnounceUsesCourseTowardTheFallenPerson() throws {
        let originLat = 35.68
        let originLon = 139.76
        let target = try XCTUnwrap(GRS80Geodesic.direct(
            latitude: originLat,
            longitude: originLon,
            azimuthDegrees: 135,
            distanceMeters: 15
        ))
        let notice = FallNotice(
            at: date(0),
            deviceID: "fallen",
            name: "作業員A",
            kind: .fall,
            latitudeDegrees: target.latitude,
            longitudeDegrees: target.longitude,
            channelID: "site"
        )
        let announcement = try XCTUnwrap(FallCall.announce(
            notice: notice,
            fromLatitude: originLat,
            fromLongitude: originLon,
            courseDegrees: 0,
            headingDegrees: 90
        ))
        XCTAssertEqual(announcement.speech, "右うしろ15m 転倒")
        XCTAssertEqual(announcement.cue?.id, notice.id)
    }

    func testRelayHoldsTheNoticeUntilTheLinkReturns() {
        let notice = FallNotice(
            at: date(0),
            deviceID: "phone",
            name: "この端末",
            kind: .impact,
            latitudeDegrees: 35.68,
            longitudeDegrees: 139.76,
            channelID: "site"
        )
        let relay = FallRelay(reachable: false)
        XCTAssertEqual(relay.submit(notice), .unreachable)
        XCTAssertEqual(relay.pending, [notice])
        relay.flush()
        XCTAssertTrue(relay.sent.isEmpty)
        relay.isReachable = true
        relay.flush()
        XCTAssertEqual(relay.sent, [notice])
        XCTAssertTrue(relay.pending.isEmpty)
    }

    func testLinkFrameCarriesAFallNotice() throws {
        let notice = FallNotice(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            at: date(0),
            deviceID: "phone",
            name: "この端末",
            kind: .fall,
            latitudeDegrees: 36,
            longitudeDegrees: 139,
            channelID: "site"
        )
        let frame = LinkFrame(kind: .fall, fall: notice)
        let data = try JSONEncoder().encode(frame)
        let decoded = try JSONDecoder().decode(LinkFrame.self, from: data)
        XCTAssertEqual(decoded.kind, .fall)
        XCTAssertEqual(decoded.fall, notice)
    }

    func testFallRecordSaysItIsNotAnEmergencyCall() {
        let record = IncidentRecord(
            id: UUID(),
            projectID: "project",
            projectName: "現場",
            occurredAt: date(0),
            sealedAt: date(60),
            trigger: .fall,
            parties: [],
            track: [],
            machineRadiusMeters: 9,
            work: IncidentWork(kind: "転倒", name: "転倒検知"),
            accuracyMeters: 3,
            stageLabel: "段階0",
            solutionLabel: "単独",
            speeches: [IncidentSpeech(at: date(0), text: "右うしろ15m 転倒")],
            radio: [],
            drawingFile: "図面.png",
            mapFile: "地図.png",
            photoFile: nil,
            voiceMemoFile: nil,
            notice: SafetyNotice.text
        )
        let lines = IncidentReport.lines(record)
        XCTAssertEqual(record.trigger.label, "転倒検知")
        XCTAssertTrue(lines.contains(FallCall.disclaimer))
        XCTAssertTrue(lines.contains("作業 転倒 転倒検知"))
        XCTAssertTrue(lines.contains("きっかけ 転倒検知"))
    }

    private func sample(_ seconds: TimeInterval, user: Double, total: Double?) -> FallSample {
        FallSample(at: date(seconds), userG: user, totalG: total)
    }

    private func feed(
        _ detector: inout FallDetector,
        user: Double,
        from start: TimeInterval,
        to end: TimeInterval
    ) -> FallSignal? {
        var signal: FallSignal?
        var t = start
        while t <= end + 0.001 {
            if let next = detector.ingest(sample(t, user: user, total: 1)) {
                signal = next
            }
            t += 0.1
        }
        return signal
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + seconds)
    }
}
