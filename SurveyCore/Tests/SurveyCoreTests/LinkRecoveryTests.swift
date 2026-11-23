import XCTest
@testable import SurveyCore

final class LinkRecoveryTests: XCTestCase {
    func testBackoffSequenceCapsAt15() {
        var backoff = LinkBackoff()
        let delays = (0..<6).map { _ in backoff.take() }
        XCTAssertEqual(delays, [1, 2, 4, 8, 15, 15])
    }

    func testStallNeedsConnectedSilenceOverFiveSeconds() {
        var stall = LinkStall(limit: 5)
        XCTAssertFalse(stall.isStalled(at: 10, connected: true))
        stall.mark(at: 10)
        XCTAssertFalse(stall.isStalled(at: 15, connected: true))
        XCTAssertFalse(stall.isStalled(at: 15.1, connected: false))
        XCTAssertTrue(stall.isStalled(at: 15.1, connected: true))
        stall.reset()
        XCTAssertFalse(stall.isStalled(at: 30, connected: true))
    }

    func testNTRIPKeepsOneSocketAndRestartsBackoffAfterAStream() {
        var plan = NTRIPReconnect()
        XCTAssertEqual(plan.start(), 1)
        XCTAssertEqual(plan.lost(reason: "Casterが切断しました", at: 0, dialectHint: true), 1)
        XCTAssertEqual(plan.dialect, .v1)
        XCTAssertEqual(plan.health.reconnectingText(time: "03:58:01"), "再接続中 (1回目) Casterが切断しました 03:58:01")
        XCTAssertNil(plan.readyToOpen())
        plan.noteClosed(1)
        XCTAssertEqual(plan.readyToOpen(), 2)
        XCTAssertNil(plan.readyToOpen())
        XCTAssertEqual(plan.socket.openID, 2)
        XCTAssertNil(plan.socket.closingID)

        plan.streamBegan(at: 10)
        plan.bytes(at: 12)
        XCTAssertFalse(plan.stalled(at: 17))
        XCTAssertTrue(plan.stalled(at: 17.1))
        XCTAssertEqual(plan.lost(reason: "RTCMが止まった", at: 17.1, dialectHint: false), 1)
        XCTAssertEqual(plan.dialect, .v1)
        XCTAssertEqual(plan.health.drops, 2)
        plan.noteClosed(2)
        XCTAssertEqual(plan.readyToOpen(), 3)

        var delays: [TimeInterval] = []
        var again = NTRIPReconnect()
        _ = again.start()
        for index in 0..<6 {
            let delay = again.lost(reason: "切断", at: Double(index), dialectHint: false)
            delays.append(delay ?? -1)
            if let id = again.socket.closingID { again.noteClosed(id) }
            _ = again.readyToOpen()
        }
        XCTAssertEqual(delays, [1, 2, 4, 8, 15, 15])
        again.correctionsEnabled = false
        XCTAssertNil(again.lost(reason: "オフ", at: 20, dialectHint: false))
    }

    func testViDocReconnectRetrievesThenScansAndBootsAgain() {
        var recovery = ViDocRecovery()
        recovery.remember("vidoc-1")
        recovery.linkUp(at: 0)
        XCTAssertEqual(recovery.bootRuns, 1)
        recovery.notify(at: 1)
        XCTAssertFalse(recovery.stall.isStalled(at: 6, connected: recovery.linked))
        XCTAssertTrue(recovery.stall.isStalled(at: 6.1, connected: recovery.linked))

        XCTAssertEqual(recovery.recover(reason: "通知が止まった", at: 6.1, retrieved: true), ["retrieve"])
        recovery.linkUp(at: 7)
        XCTAssertEqual(recovery.bootRuns, 2)
        XCTAssertEqual(recovery.health.drops, 1)
        XCTAssertFalse(recovery.health.reconnecting)

        XCTAssertEqual(recovery.recover(reason: "切断", at: 8, retrieved: false), ["retrieve", "scan"])
        recovery.linkUp(at: 9)
        XCTAssertEqual(recovery.bootRuns, 3)
        XCTAssertEqual(recovery.health.reconnectingText(time: "03:58:09"), "再接続中 (2回目) 切断 03:58:09")

        var buffer = RTCMOutboundBuffer()
        let fresh = Data([0xD3, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00])
        let stale = Data([0xD3, 0x00, 0x01, 0x02, 0x00, 0x00, 0x00])
        buffer.append(stale, at: 0)
        buffer.append(fresh, at: 1.5)
        buffer.dropOlder(than: 2, now: 3)
        XCTAssertEqual(buffer.bufferedBytes, fresh.count)
        XCTAssertEqual(buffer.nextChunk(maximumBytes: 180), fresh)
    }
}
