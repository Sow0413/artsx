import XCTest
@testable import SurveyCore

final class ProximityTests: XCTestCase {
    func testRelayCarriesTheSameProjectAndNearbyCoversTheGap() {
        let relay = CrewRelayStub(reachable: true)
        let nearby = CrewMesh()
        let desk = desk(id: "a", role: .machine, relay: relay, nearby: nearby)
        desk.join(projectID: "現場")
        let path = desk.publish(machine(id: "a", at: date(1), meters: 0))
        XCTAssertEqual(path, .relay)
        XCTAssertEqual(relay.sent.map(\.projectID), ["現場"])
        XCTAssertTrue(nearby.sent.isEmpty)

        relay.isReachable = false
        XCTAssertEqual(desk.publish(machine(id: "a", at: date(2), meters: 0)), .nearby)
        XCTAssertEqual(nearby.sent.count, 1)
    }

    func testOtherProjectsAndSelfAreIgnored() {
        let leftMesh = CrewMesh()
        let rightMesh = CrewMesh()
        leftMesh.peers = [rightMesh]
        let left = desk(id: "left", role: .machine, relay: CrewRelayStub(reachable: false), nearby: leftMesh)
        let right = desk(id: "right", role: .worker, relay: CrewRelayStub(reachable: false), nearby: rightMesh)
        left.join(projectID: "現場")
        right.join(projectID: "別")
        right.evaluate(selfFix: worker(id: "right", at: date(1), meters: 10), now: date(1))
        _ = left.publish(machine(id: "left", at: date(1), meters: 0))
        XCTAssertTrue(right.others.isEmpty)

        right.join(projectID: "現場")
        _ = left.publish(machine(id: "left", at: date(1), meters: 0))
        XCTAssertEqual(right.others.map(\.id), ["left"])
        _ = right.publish(worker(id: "right", at: date(1), meters: 10))
        right.receive(CrewPacket(projectID: "現場", fix: worker(id: "right", at: date(1), meters: 10)), now: date(1))
        XCTAssertEqual(right.others.map(\.id), ["left"])
    }

    func testPersonInsideThePaddedRadiusAlarmsBothSides() throws {
        let machinePoint = place(meters: 0)
        let inside = place(meters: 10)
        let limits = ProximityLimits.standard
        let machineFix = fix("m", .machine, machinePoint, date(1), radius: 9)
        let workerFix = fix("w", .worker, inside, date(1), radius: nil)
        let onMachine = ProximityJudge.hit(selfFix: machineFix, other: workerFix, limits: limits, now: date(1))
        let onWorker = ProximityJudge.hit(selfFix: workerFix, other: machineFix, limits: limits, now: date(1))
        XCTAssertEqual(onMachine?.level, .alarm)
        XCTAssertEqual(onWorker?.level, .alarm)
        XCTAssertEqual(onMachine?.alarmRadiusMeters, 14)
        XCTAssertEqual(onWorker?.alarmRadiusMeters, 14)
    }

    func testCautionAtFiftyAndClearBeyondIt() throws {
        let limits = ProximityLimits.standard
        let machineFix = fix("m", .machine, place(meters: 0), date(1), radius: 9)
        let caution = place(meters: 40)
        let clear = place(meters: 60)
        let near = ProximityJudge.hit(selfFix: machineFix, other: fix("w", .worker, caution, date(1), radius: nil), limits: limits, now: date(1))
        let far = ProximityJudge.hit(selfFix: machineFix, other: fix("w", .worker, clear, date(1), radius: nil), limits: limits, now: date(1))
        XCTAssertEqual(near?.level, .caution)
        XCTAssertEqual(far?.level, .clear)
    }

    func testDistancesAreConfigurableAndZeroMarginUsesTheRadius() throws {
        let limits = ProximityLimits(cautionMeters: 20, marginMeters: 0)
        let machineFix = fix("m", .machine, place(meters: 0), date(1), radius: 9)
        let outside = place(meters: 30)
        let hit = ProximityJudge.hit(selfFix: machineFix, other: fix("w", .worker, outside, date(1), radius: nil), limits: limits, now: date(1))
        XCTAssertEqual(hit?.level, .clear)
        let onRadius = place(meters: 9)
        let edged = ProximityJudge.hit(selfFix: machineFix, other: fix("w", .worker, onRadius, date(1), radius: nil), limits: limits, now: date(1))
        XCTAssertEqual(edged?.level, .alarm)
        XCTAssertEqual(ProximityLimits.resolved(caution: nil, margin: -1), .standard)
        XCTAssertEqual(ProximityLimits.resolved(caution: 30, margin: 0).marginMeters, 0)
    }

    func testSameRolesDoNotUseTheWorkRadius() throws {
        let limits = ProximityLimits.standard
        let near = place(meters: 8)
        let machines = ProximityJudge.hit(
            selfFix: fix("a", .machine, place(meters: 0), date(1), radius: 9),
            other: fix("b", .machine, near, date(1), radius: 9),
            limits: limits,
            now: date(1)
        )
        let people = ProximityJudge.hit(
            selfFix: fix("a", .worker, place(meters: 0), date(1), radius: nil),
            other: fix("b", .worker, near, date(1), radius: nil),
            limits: limits,
            now: date(1)
        )
        XCTAssertEqual(machines?.level, .caution)
        XCTAssertNil(machines?.alarmRadiusMeters)
        XCTAssertEqual(people?.level, .caution)
        XCTAssertNil(people?.alarmRadiusMeters)
    }

    func testFreshUWBBeatsAFarGNSSFix() throws {
        let far = place(meters: 80)
        var workerFix = fix("w", .worker, far, date(1), radius: nil)
        workerFix.ranges = [CrewRange(peerID: "m", distanceMeters: 3, measuredAt: date(1))]
        let machineFix = fix("m", .machine, place(meters: 0), date(1), radius: 9)
        let hit = ProximityJudge.hit(selfFix: machineFix, other: workerFix, limits: .standard, now: date(1))
        XCTAssertEqual(hit?.level, .alarm)
        XCTAssertEqual(hit?.rangeKind, .uwb)
        let near = try XCTUnwrap(hit)
        let plotted = try XCTUnwrap(CrewPlot.marks(origin: machineFix, hits: [near]).first)
        let span = (plotted.eastMeters * plotted.eastMeters + plotted.northMeters * plotted.northMeters).squareRoot()
        XCTAssertEqual(span, 3, accuracy: 0.05)
        let stale = ProximityJudge.hit(selfFix: machineFix, other: workerFix, limits: .standard, now: date(10))
        XCTAssertEqual(stale?.level, .clear)
        XCTAssertEqual(stale?.rangeKind, .gnss)
    }

    func testDirectionUsesTravelThenCompass() {
        let person = CrewMark(id: "w", name: "歩", role: .worker, eastMeters: 0, northMeters: -12, workRadiusMeters: nil, level: .caution)
        let moving = ThreatBearing.picture(
            selfRole: .machine,
            marks: [person],
            courseDegrees: 0,
            headingDegrees: 90,
            cautionMeters: 50
        )
        XCTAssertEqual(moving.facingSource, "進行")
        XCTAssertEqual(moving.cues.first?.sector, "うしろ")
        XCTAssertEqual(moving.cues.first?.text, "うしろ 12.0m")
        XCTAssertEqual(moving.cues.first?.speech, "うしろ、人")
        XCTAssertEqual(moving.headline, "うしろ 12.0m")

        let stopped = ThreatBearing.picture(
            selfRole: .machine,
            marks: [person],
            courseDegrees: nil,
            headingDegrees: 180,
            cautionMeters: 50
        )
        XCTAssertEqual(stopped.facingSource, "方位")
        XCTAssertEqual(stopped.cues.first?.sector, "前")

        let lost = ThreatBearing.picture(
            selfRole: .machine,
            marks: [person],
            courseDegrees: nil,
            headingDegrees: nil,
            cautionMeters: 50
        )
        XCTAssertEqual(lost.headline, "向きがありません")
        XCTAssertTrue(lost.cues.isEmpty)
    }

    func testSectorsAndWhoIsShown() {
        XCTAssertEqual(ThreatBearing.sector(relativeDegrees: 0), "前")
        XCTAssertEqual(ThreatBearing.sector(relativeDegrees: 45), "右まえ")
        XCTAssertEqual(ThreatBearing.sector(relativeDegrees: 90), "右")
        XCTAssertEqual(ThreatBearing.sector(relativeDegrees: 135), "右うしろ")
        XCTAssertEqual(ThreatBearing.sector(relativeDegrees: 180), "うしろ")
        XCTAssertEqual(ThreatBearing.sector(relativeDegrees: -180), "うしろ")
        XCTAssertEqual(ThreatBearing.sector(relativeDegrees: -135), "左うしろ")
        XCTAssertEqual(ThreatBearing.sector(relativeDegrees: -90), "左")
        XCTAssertEqual(ThreatBearing.sector(relativeDegrees: -45), "左まえ")
        XCTAssertEqual(ThreatBearing.relative(targetAzimuthDegrees: 10, facingDegrees: 350), 20, accuracy: 0.001)

        let rightBehind = CrewMark(id: "w", name: "歩", role: .worker, eastMeters: 8.5, northMeters: -8.5, workRadiusMeters: nil, level: .alarm)
        let otherMachine = CrewMark(id: "m2", name: "別", role: .machine, eastMeters: 5, northMeters: 0, workRadiusMeters: 9, level: .caution)
        let far = CrewMark(id: "far", name: "遠", role: .worker, eastMeters: 0, northMeters: 80, workRadiusMeters: nil, level: .clear)
        let fromCab = ThreatBearing.picture(
            selfRole: .machine,
            marks: [far, otherMachine, rightBehind],
            courseDegrees: 0,
            headingDegrees: nil,
            cautionMeters: 50
        )
        XCTAssertEqual(fromCab.cues.map(\.id), ["w"])
        XCTAssertEqual(fromCab.cues.first?.sector, "右うしろ")
        XCTAssertGreaterThan(fromCab.cues[0].closeness, 0.5)

        let behindTheWalker = CrewMark(id: "m2", name: "別", role: .machine, eastMeters: -5, northMeters: 0, workRadiusMeters: 9, level: .caution)
        let fromFoot = ThreatBearing.picture(
            selfRole: .worker,
            marks: [rightBehind, behindTheWalker],
            courseDegrees: 90,
            headingDegrees: nil,
            cautionMeters: 50
        )
        XCTAssertEqual(fromFoot.cues.map(\.id), ["m2"])
        XCTAssertEqual(fromFoot.cues.first?.sector, "うしろ")
        XCTAssertEqual(fromFoot.cues.first?.speech, "うしろ、重機")
        XCTAssertEqual(
            ThreatBearing.picture(selfRole: .worker, marks: [], courseDegrees: 0, headingDegrees: nil, cautionMeters: 50).headline,
            "近くに重機はいません"
        )
    }

    func testEventsOpenUpgradeAndClose() throws {
        let relay = CrewRelayStub(reachable: false)
        let mesh = CrewMesh()
        let desk = desk(id: "m", role: .machine, relay: relay, nearby: mesh)
        desk.join(projectID: "現場")
        let origin = machine(id: "m", at: date(0), meters: 0)
        desk.evaluate(selfFix: origin, now: date(0))
        desk.receive(CrewPacket(projectID: "現場", fix: worker(id: "w", at: date(1), meters: 40)), now: date(1))
        XCTAssertEqual(desk.worst, .caution)
        XCTAssertEqual(desk.events.map(\.level), [.caution])
        XCTAssertNil(desk.events.first?.endedAt)

        desk.receive(CrewPacket(projectID: "現場", fix: worker(id: "w", at: date(2), meters: 8)), now: date(2))
        XCTAssertEqual(desk.worst, .alarm)
        XCTAssertEqual(desk.events.map(\.level).sorted { $0.rawValue < $1.rawValue }, [.alarm, .caution])
        XCTAssertNotNil(desk.events.first { $0.level == .caution }?.endedAt)
        let alarm = try XCTUnwrap(desk.events.first { $0.level == .alarm })
        XCTAssertNil(alarm.endedAt)
        XCTAssertEqual(alarm.closestMeters, desk.hits.first?.distanceMeters)

        desk.receive(CrewPacket(projectID: "現場", fix: worker(id: "w", at: date(3), meters: 80)), now: date(3))
        XCTAssertEqual(desk.worst, .clear)
        XCTAssertTrue(desk.events.allSatisfy { $0.endedAt != nil })

        desk.receive(CrewPacket(projectID: "現場", fix: worker(id: "w", at: date(4), meters: 8)), now: date(4))
        desk.evaluate(selfFix: origin, now: date(40))
        XCTAssertTrue(desk.others.isEmpty)
        XCTAssertTrue(desk.events.allSatisfy { $0.endedAt != nil })
    }

    func testPlotAndLogRoundTrip() throws {
        let origin = fix("m", .machine, place(meters: 0), date(1), radius: 9)
        let east = GRS80Geodesic.direct(latitude: origin.latitudeDegrees, longitude: origin.longitudeDegrees, azimuthDegrees: 90, distanceMeters: 10)
        let other = CrewFix(
            id: "w",
            name: "歩",
            role: .worker,
            latitudeDegrees: east?.latitude ?? 0,
            longitudeDegrees: east?.longitude ?? 0,
            horizontalAccuracyMeters: 5,
            workRadiusMeters: nil,
            sentAt: date(1)
        )
        let hit = try XCTUnwrap(ProximityJudge.hit(selfFix: origin, other: other, limits: .standard, now: date(1)))
        let mark = try XCTUnwrap(CrewPlot.marks(origin: origin, hits: [hit]).first)
        XCTAssertEqual(mark.eastMeters, 10, accuracy: 0.05)
        XCTAssertEqual(mark.northMeters, 0, accuracy: 0.05)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let project = try ProjectStore.create(name: "接近現場", at: root, now: date(0))
        var saved = project
        saved.cautionMeters = 40
        saved.proximityMarginMeters = 2
        let loadedLimits = ProximityLimits.resolved(caution: saved.cautionMeters, margin: saved.proximityMarginMeters)
        XCTAssertEqual(loadedLimits.cautionMeters, 40)
        XCTAssertEqual(loadedLimits.marginMeters, 2)
        let identity = CrewIdentity(deviceID: "phone", name: "この端末", role: .machine)
        try CrewIdentityStore.save(identity, projectName: project.name, at: root)
        XCTAssertEqual(CrewIdentityStore.load(projectName: project.name, at: root), identity)
        let event = ProximityEvent(
            projectID: project.id,
            level: .alarm,
            startedAt: date(1),
            endedAt: date(2),
            selfID: "phone",
            selfRole: .machine,
            otherID: "w",
            otherName: "歩",
            otherRole: .worker,
            enteredMeters: 8,
            closestMeters: 6,
            alarmRadiusMeters: 14,
            rangeKind: .gnss
        )
        try ProximityLog.save([event], projectName: project.name, at: root)
        XCTAssertEqual(ProximityLog.load(projectName: project.name, at: root), [event])
        XCTAssertEqual(WatchCue(.alarm), .alarm)
    }

    private func desk(id: String, role: CrewRole, relay: CrewRelayStub, nearby: CrewMesh) -> CrewDesk {
        CrewDesk(deviceID: id, name: id, role: role, relay: relay, nearby: nearby)
    }

    private func machine(id: String, at date: Date, meters: Double) -> CrewFix {
        fix(id, .machine, place(meters: meters), date, radius: 9)
    }

    private func worker(id: String, at date: Date, meters: Double) -> CrewFix {
        fix(id, .worker, place(meters: meters), date, radius: nil)
    }

    private func fix(_ id: String, _ role: CrewRole, _ point: (Double, Double), _ date: Date, radius: Double?) -> CrewFix {
        CrewFix(
            id: id,
            name: id,
            role: role,
            latitudeDegrees: point.0,
            longitudeDegrees: point.1,
            horizontalAccuracyMeters: 5,
            workRadiusMeters: radius,
            sentAt: date
        )
    }

    private func place(meters: Double) -> (Double, Double) {
        let moved = GRS80Geodesic.direct(latitude: 35, longitude: 139, azimuthDegrees: 0, distanceMeters: meters)
        return (moved?.latitude ?? 35, moved?.longitude ?? 139)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
