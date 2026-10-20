import XCTest
@testable import SurveyCore

final class ARStakeoutTests: XCTestCase {
    func testKnownPointsLockScaleAndShowResiduals() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let alignment = ARStakeoutMath.align(pairs: [
            ARStakeoutPair(name: "A1", arX: 0, arZ: 0, eastingMeters: 100, northingMeters: 200),
            ARStakeoutPair(name: "A2", arX: 10, arZ: 0, eastingMeters: 110, northingMeters: 200),
            ARStakeoutPair(name: "A3", arX: 0, arZ: 10, eastingMeters: 100, northingMeters: 210.2)
        ], at: date)
        let fit = try XCTUnwrap(alignment)
        XCTAssertEqual(fit.method, .knownPoints)
        XCTAssertEqual(fit.transform.scale, 1, accuracy: 1e-9)
        XCTAssertEqual(fit.residualsMeters.count, 3)
        XCTAssertGreaterThan(fit.rmsMeters, 0)
        let text = try XCTUnwrap(ARStakeoutMath.residualText(fit.residualsMeters))
        XCTAssertTrue(text.hasPrefix("残差"))
        let exact = try XCTUnwrap(ARStakeoutMath.align(pairs: [
            ARStakeoutPair(name: "A1", arX: 0, arZ: 0, eastingMeters: 100, northingMeters: 200),
            ARStakeoutPair(name: "A2", arX: 10, arZ: 0, eastingMeters: 110, northingMeters: 200)
        ], at: date))
        let placed = try XCTUnwrap(exact.transform.inverse(PlanarPoint(x: 105, y: 200)))
        XCTAssertEqual(placed.x, 5, accuracy: 1e-6)
        XCTAssertEqual(placed.y, 0, accuracy: 1e-6)
        XCTAssertNil(ARStakeoutMath.align(pairs: [
            ARStakeoutPair(name: "A1", arX: 0, arZ: 0, eastingMeters: 0, northingMeters: 0)
        ], at: date))
        print("SURVEY ARSTAKEOUT 残差 \(fit.residualsMeters.count)")
    }

    func testWalkAzimuthAndRTKCorrection() throws {
        XCTAssertNil(ARStakeoutMath.trackAzimuth(fromEasting: 0, fromNorthing: 0, toEasting: 1, toNorthing: 0))
        XCTAssertEqual(
            ARStakeoutMath.trackAzimuth(fromEasting: 0, fromNorthing: 0, toEasting: 0, toNorthing: 10) ?? -1,
            0,
            accuracy: 1e-6
        )
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let walk = try XCTUnwrap(ARStakeoutMath.alignWalk(
            cameraX: 0,
            cameraZ: 0,
            forwardX: 0,
            forwardZ: 1,
            eastingMeters: 500,
            northingMeters: 600,
            azimuthDegrees: 90,
            at: date
        ))
        let ahead = walk.transform.apply(PlanarPoint(x: 0, y: 1))
        XCTAssertEqual(ahead.x, 501, accuracy: 1e-6)
        XCTAssertEqual(ahead.y, 600, accuracy: 1e-6)
        let camera = walk.transform.apply(PlanarPoint(x: 0, y: 0))
        XCTAssertEqual(camera.x, 500, accuracy: 1e-6)
        XCTAssertEqual(camera.y, 600, accuracy: 1e-6)

        let fixed = try XCTUnwrap(ARStakeoutMath.correct(
            walk,
            cameraX: 0,
            cameraZ: 0,
            eastingMeters: 500.2,
            northingMeters: 600,
            gnssMeters: 0.02,
            at: date.addingTimeInterval(2)
        ))
        XCTAssertEqual(fixed.method, .rtk)
        let shifted = fixed.transform.apply(PlanarPoint(x: 0, y: 0))
        XCTAssertEqual(shifted.x, 500.2, accuracy: 1e-6)
        XCTAssertEqual(shifted.y, 600, accuracy: 1e-6)
        XCTAssertEqual(fixed.transform.rotationDegrees, walk.transform.rotationDegrees, accuracy: 1e-9)
    }

    func testDriftRealignGroundAndNumericHandoff() throws {
        XCTAssertEqual(ARStakeoutMath.drift(seconds: 10, walkedMeters: 4), 0.09, accuracy: 1e-12)
        XCTAssertFalse(ARStakeoutMath.shouldRealign(ARStakeoutMath.errorMeters(drift: 0.09, rms: 0)))
        XCTAssertTrue(ARStakeoutMath.shouldRealign(ARStakeoutMath.errorMeters(drift: 0.12, rms: 0)))
        XCTAssertEqual(ARStakeoutMath.ground(lidarY: 1.2, planeY: 0.4).source, "LiDAR")
        XCTAssertEqual(ARStakeoutMath.ground(lidarY: nil, planeY: 0.4).source, "平面")
        XCTAssertEqual(ARStakeoutMath.ground(lidarY: nil, planeY: nil).source, "仮定")

        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let alignment = try XCTUnwrap(ARStakeoutMath.align(pairs: [
            ARStakeoutPair(name: "A1", arX: 0, arZ: 0, eastingMeters: 0, northingMeters: 0),
            ARStakeoutPair(name: "A2", arX: 10, arZ: 0, eastingMeters: 10, northingMeters: 0)
        ], at: date))
        let far = try XCTUnwrap(ARStakeoutMath.picture(
            alignment: alignment,
            targets: [
                ARStakeoutTarget(name: "K1", eastingMeters: 12.8, northingMeters: 0),
                ARStakeoutTarget(name: "K2", eastingMeters: 20, northingMeters: 0)
            ],
            currentIndex: 0,
            groundY: 0.4,
            hereEasting: 0,
            hereNorthing: 0,
            facingDegrees: 0,
            strideMeters: 0.8,
            unit: .steps,
            seconds: 1,
            walkedMeters: 0
        ))
        XCTAssertEqual(far.staffs.count, 2)
        XCTAssertEqual(far.staffs[0].label, "右 16歩")
        XCTAssertTrue(far.staffs[0].primary)
        XCTAssertFalse(far.staffs[1].primary)
        XCTAssertEqual(far.staffs[0].groundY, 0.4, accuracy: 1e-12)
        XCTAssertEqual(far.staffs[1].label, "K2")
        XCTAssertFalse(far.numeric)

        let near = try XCTUnwrap(ARStakeoutMath.picture(
            alignment: alignment,
            targets: [ARStakeoutTarget(name: "K1", eastingMeters: 0, northingMeters: 0.035)],
            currentIndex: 0,
            groundY: 0,
            hereEasting: 0,
            hereNorthing: 0,
            facingDegrees: 0,
            strideMeters: 0.8,
            unit: .steps,
            seconds: 30,
            walkedMeters: 0
        ))
        XCTAssertTrue(near.numeric)
        XCTAssertTrue(near.staffs.isEmpty)
        XCTAssertEqual(near.speech, "あと4cm前")
        XCTAssertTrue(near.realign)
        XCTAssertTrue(near.errorText.contains("もう一度合わせてください"))
    }

    func testHandoffUsesOneMeterAndHysteresis() throws {
        XCTAssertEqual(ARHandoffPreference().meters, 1, accuracy: 1e-12)
        XCTAssertEqual(ARHandoffPreference().resumeMeters, 1.2, accuracy: 1e-12)
        XCTAssertEqual(ARStakeoutMath.mode(distanceMeters: 1, current: .augmented, switchMeters: 1), .augmented)
        XCTAssertEqual(ARStakeoutMath.mode(distanceMeters: 0.99, current: .augmented, switchMeters: 1), .numeric)
        XCTAssertEqual(ARStakeoutMath.mode(distanceMeters: 1.19, current: .numeric, switchMeters: 1), .numeric)
        XCTAssertEqual(ARStakeoutMath.mode(distanceMeters: 1.2, current: .numeric, switchMeters: 1), .augmented)
        XCTAssertEqual(ARStakeoutMath.mode(distanceMeters: 2.3, current: .numeric, switchMeters: 2), .numeric)
        XCTAssertEqual(ARStakeoutMath.mode(distanceMeters: 2.4, current: .numeric, switchMeters: 2), .augmented)
        XCTAssertNil(ARHandoffPreference.accepted(0.1))
        let name = "handoff-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        ARHandoffPreference(meters: 2).save(to: defaults)
        XCTAssertEqual(ARHandoffPreference.load(from: defaults).meters, 2, accuracy: 1e-12)
        XCTAssertEqual(ARHandoffPreference.load(from: defaults).resumeMeters, 2.4, accuracy: 1e-12)
        XCTAssertNil(defaults.data(forKey: StatureProfile.storageKey))

        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let alignment = try XCTUnwrap(ARStakeoutMath.align(pairs: [
            ARStakeoutPair(name: "A1", arX: 0, arZ: 0, eastingMeters: 0, northingMeters: 0),
            ARStakeoutPair(name: "A2", arX: 10, arZ: 0, eastingMeters: 10, northingMeters: 0)
        ], at: date))
        let inside = try XCTUnwrap(ARStakeoutMath.picture(
            alignment: alignment,
            targets: [ARStakeoutTarget(name: "K1", eastingMeters: 0.12, northingMeters: 0.80)],
            currentIndex: 0,
            groundY: 0,
            hereEasting: 0,
            hereNorthing: 0,
            facingDegrees: 0,
            strideMeters: 0.8,
            unit: .steps,
            seconds: 0,
            walkedMeters: 0,
            current: .augmented,
            switchMeters: 1
        ))
        XCTAssertEqual(inside.mode, .numeric)
        XCTAssertTrue(inside.staffs.isEmpty)
        XCTAssertEqual(inside.speech, "あと80cm前")
        XCTAssertEqual(inside.detail, "前 80cm　右 12cm")
        XCTAssertEqual(inside.alongCentimeters, 80)
        XCTAssertEqual(inside.acrossCentimeters, 12)

        let held = try XCTUnwrap(ARStakeoutMath.picture(
            alignment: alignment,
            targets: [ARStakeoutTarget(name: "K1", eastingMeters: 0, northingMeters: 1.05)],
            currentIndex: 0,
            groundY: 0,
            hereEasting: 0,
            hereNorthing: 0,
            facingDegrees: 0,
            strideMeters: 0.8,
            unit: .steps,
            seconds: 0,
            walkedMeters: 0,
            current: .numeric,
            switchMeters: 1
        ))
        XCTAssertEqual(held.mode, .numeric)
        XCTAssertFalse(held.speech?.contains("歩") == true)
        XCTAssertEqual(held.detail, "前 105cm")
        print("SURVEY ARHANDOFF 1.2m")
    }

    func testProjectionAndGroundTap() throws {
        var camera = Array(repeating: 0.0, count: 16)
        camera[0] = 1
        camera[5] = 1
        camera[10] = 1
        camera[15] = 1
        let top = try XCTUnwrap(ARStakeoutMath.project(
            camera: camera, fx: 1000, fy: 1000, cx: 500, cy: 500,
            imageWidth: 1000, imageHeight: 1000, viewportWidth: 200, viewportHeight: 200,
            worldX: 0, worldY: 1.5, worldZ: -2
        ))
        XCTAssertTrue(top.visible)
        XCTAssertEqual(top.x, 100, accuracy: 1e-6)
        XCTAssertEqual(top.y, -50, accuracy: 1e-6)
        let behind = try XCTUnwrap(ARStakeoutMath.project(
            camera: camera, fx: 1000, fy: 1000, cx: 500, cy: 500,
            imageWidth: 1000, imageHeight: 1000, viewportWidth: 200, viewportHeight: 200,
            worldX: 0, worldY: 0, worldZ: 2
        ))
        XCTAssertFalse(behind.visible)

        var down = Array(repeating: 0.0, count: 16)
        down[0] = 1
        down[6] = -1
        down[9] = 1
        down[13] = 2
        down[15] = 1
        let hit = try XCTUnwrap(ARStakeoutMath.groundHit(
            tapX: 100, tapY: 100, viewportWidth: 200, viewportHeight: 200,
            camera: down, fx: 1000, fy: 1000, cx: 500, cy: 500,
            imageWidth: 1000, imageHeight: 1000, groundY: 0
        ))
        XCTAssertEqual(hit.x, 0, accuracy: 1e-6)
        XCTAssertEqual(hit.z, 0, accuracy: 1e-6)
    }
}
