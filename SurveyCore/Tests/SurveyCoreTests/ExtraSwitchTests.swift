import XCTest
@testable import SurveyCore

final class ExtraSwitchTests: XCTestCase {
    func testDefaultsLeaveTheSurveyScreenAlone() {
        let switches = ExtraSwitches.quiet
        XCTAssertTrue(switches.quietScreen)
        XCTAssertFalse(switches.pushToTalk)
        XCTAssertFalse(switches.proximity)
        XCTAssertFalse(switches.fall)
        XCTAssertFalse(switches.sos)
        XCTAssertFalse(switches.firstResponse)
        XCTAssertFalse(switches.accidentReport)
        XCTAssertFalse(switches.disaster)
        XCTAssertFalse(switches.mesh)
        XCTAssertFalse(switches.stats)
        XCTAssertFalse(switches.sharesLocation)
        XCTAssertFalse(switches.usesNearby)
        XCTAssertFalse(switches.recordsIncidents)
    }

    func testEachSwitchIsIndependent() {
        var switches = ExtraSwitches.quiet
        switches.mesh = true
        XCTAssertFalse(switches.quietScreen)
        XCTAssertTrue(switches.usesNearby)
        XCTAssertFalse(switches.sharesLocation)
        XCTAssertFalse(switches.recordsIncidents)
        switches = .quiet
        switches.proximity = true
        XCTAssertTrue(switches.sharesLocation)
        XCTAssertTrue(switches.recordsIncidents)
        switches = .quiet
        switches.disaster = true
        XCTAssertTrue(switches.sharesLocation)
        XCTAssertFalse(switches.recordsIncidents)
        switches = .quiet
        switches.stats = true
        XCTAssertFalse(switches.usesNearby)
        XCTAssertFalse(switches.quietScreen)
    }

    func testMissingFileAndPartialJSONStayOff() throws {
        let root = try TestFiles.directory()
        defer { TestFiles.remove(root) }
        XCTAssertEqual(ExtraSwitchStore.load(from: root), .quiet)
        let url = root.appendingPathComponent(ExtraSwitchStore.fileName)
        try Data("{\"sos\":true}".utf8).write(to: url)
        let loaded = ExtraSwitchStore.load(from: url.deletingLastPathComponent())
        XCTAssertTrue(loaded.sos)
        XCTAssertFalse(loaded.pushToTalk)
        XCTAssertFalse(loaded.fall)
        XCTAssertFalse(loaded.mesh)
        XCTAssertTrue(loaded.usesNearby)
        XCTAssertFalse(loaded.sharesLocation)
    }

    func testRoundTripKeepsASingleSwitch() throws {
        let root = try TestFiles.directory()
        defer { TestFiles.remove(root) }
        var switches = ExtraSwitches.quiet
        switches.accidentReport = true
        try ExtraSwitchStore.save(switches, to: root)
        let loaded = ExtraSwitchStore.load(from: root)
        XCTAssertEqual(loaded, switches)
        XCTAssertFalse(loaded.quietScreen)
        XCTAssertFalse(loaded.stats)
    }
}
