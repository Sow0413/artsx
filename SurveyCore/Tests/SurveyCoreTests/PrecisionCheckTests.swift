import XCTest
@testable import SurveyCore

final class PrecisionCheckTests: XCTestCase {
    func testComplianceGatesAndReportOmitKBMAndTwoSet() {
        XCTAssertFalse(PrecisionGate.complianceAllowsStart(fix: false, durationSeconds: 12))
        XCTAssertFalse(PrecisionGate.complianceAllowsStart(fix: true, durationSeconds: 9))
        XCTAssertTrue(PrecisionGate.complianceAllowsStart(fix: true, durationSeconds: 10))
        XCTAssertFalse(PrecisionGate.tiltAllowsStart(degrees: 0.6))
        XCTAssertTrue(PrecisionGate.tiltAllowsStart(degrees: 0.5))
        XCTAssertTrue(PrecisionGate.tiltAllowsStart(degrees: nil))
        XCTAssertFalse(PrecisionGate.localizeAllows(knownPoints: 2))
        XCTAssertTrue(PrecisionGate.localizeAllows(knownPoints: 3))
        let report = PrecisionReport.text(
            trials: [
                PrecisionTrial(name: "IRB-1", planeErrorMeters: 0.01, verticalErrorMeters: 0.02),
                PrecisionTrial(name: "KBM1", planeErrorMeters: 0, verticalErrorMeters: 0, isKBM: true)
            ],
            antennaNote: "ポール高",
            geoidNote: "ジオイド2024"
        )
        XCTAssertTrue(report.contains("精度確認試験報告書"))
        XCTAssertTrue(report.contains("2セット較差: 使わない"))
        XCTAssertTrue(report.contains("IRB-1 平面合格"))
        XCTAssertFalse(report.contains("KBM1"))
    }

    func testAntennaAndKBMStaySeparateFromCamera() {
        var instrument = SiteInstrument(antennaMethod: "laser", laserMeters: 1.5)
        XCTAssertEqual(instrument.antennaToGroundMeters ?? 0, 0.1877 + 1.5, accuracy: 1e-9)
        XCTAssertEqual(instrument.groundMarkMeters(ellipsoidal: 40) ?? 0, 40 - 1.6877, accuracy: 1e-6)
        XCTAssertEqual(KBMCorrection.title, "現場高さ補正（KBM 1点）")
        XCTAssertEqual(KBMCorrection.n(ellipsoidal: 31.51, orthometric: 31.50), 0.01, accuracy: 1e-9)
        let first = Date(timeIntervalSince1970: 10)
        let second = Date(timeIntervalSince1970: 40)
        XCTAssertTrue(KBMCorrection.accepted(first: 0.011, firstAt: first, second: 0.020, secondAt: second))
        XCTAssertFalse(KBMCorrection.accepted(first: 0.011, firstAt: first, second: 0.040, secondAt: second))
        XCTAssertFalse(KBMCorrection.accepted(first: 0.011, firstAt: first, second: 0.011, secondAt: first))
        XCTAssertEqual(CameraOffset.spcPlus15ProMax.x, 0.022)
        XCTAssertEqual(CameraOffset.spcPlus15ProMax.y, 0.056)
        XCTAssertEqual(CameraOffset.spcPlus15ProMax.z, 0.017)
        XCTAssertTrue(CameraOffset.customOnly(machine: "iPhone 17 Pro"))
        XCTAssertFalse(CameraOffset.customOnly(machine: "iPhone17,1"))
    }

    func testGeoidGridAndFirmwareBanner() {
        let grid = GeoidGrid2024.parse("# ジオイド2024\n26.0 124.0 31.2\n26.1 124.1 31.4\n")
        XCTAssertEqual(grid.separation(latitude: 26.0, longitude: 124.0) ?? 0, 31.2, accuracy: 1e-9)
        XCTAssertNil(GeoidGrid2024(samples: []).separation(latitude: 0, longitude: 0))
        XCTAssertEqual(ViDocFirmware.version(in: "\u{02}df Ver_3.0.0.0\u{03}"), "3.0.0.0")
        XCTAssertTrue(ViDocLink.isWaitLine("df Ver_3.0.0.0"))
        XCTAssertFalse(ViDocLink.isReadyText("df Ver_3.0.0.0"))
        XCTAssertFalse(ViDocLaser.enabled)
        XCTAssertFalse(ViDocLaser.heldReason.isEmpty)
    }

    func testZoneXVINamesUseIRBPrefix() {
        let document = DrawingDocument(
            layers: [],
            entities: [
                DrawingEntity(
                    id: 1,
                    layer: "測設_基準点",
                    color: .white,
                    primitive: .text(origin: PlanarPoint(x: 1, y: 2), string: "IRB-KBM1", height: 1, rotationDegrees: 0),
                    bounds: .empty
                ),
                DrawingEntity(
                    id: 2,
                    layer: "測設_基準点",
                    color: .white,
                    primitive: .text(origin: PlanarPoint(x: 1, y: 2), string: "T1", height: 1, rotationDegrees: 0),
                    bounds: .empty
                )
            ],
            bounds: .empty,
            unsupportedCounts: [:],
            codePage: "UTF-8",
            unitWarning: nil,
            index: DrawingSpatialIndex(entities: [])
        )
        XCTAssertEqual(SiteDXF.mismatches(drawing: SiteDXF.controlNames(in: document), ledger: ["IRB-KBM1"]), ["T1"])
        XCTAssertEqual(SiteDXF.zone, 16)
        XCTAssertEqual(SiteDXF.epsg, 6684)
        XCTAssertTrue(SiteDXF.prefersUTF8(acadVersion: "AC1021"))
        XCTAssertFalse(SiteDXF.prefersUTF8(acadVersion: "AC1015"))
    }
}
