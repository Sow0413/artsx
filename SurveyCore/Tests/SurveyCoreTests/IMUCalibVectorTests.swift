import XCTest
@testable import SurveyCore

final class IMUCalibVectorTests: XCTestCase {
    func testVectorFileMatchesSectionBySection() throws {
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: vectorURL())) as! [String: Any]
        checkHeading(root["heading"] as! [[String: Any]])
        checkTilt(root["tilt_azimuth"] as! [[String: Any]])
        checkDeclination(root["decl_gsi2020"] as! [[String: Any]])
        checkReversal(root["reversal"] as! [[String: Any]])
        checkSixFace(root["six_face"] as! [String: Any])
        checkSphere(root["sphere_fit"] as! [String: Any])
        checkRobust(root["robust"] as! [[String: Any]])
    }

    private func vectorURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("docs/imu_calib_testvectors_20261125.json")
    }

    private func vector(_ values: [Double]) -> IMUVector { IMUVector(values) }
    private func numbers(_ value: Any?) -> [Double] {
        (value as? [NSNumber])?.map(\.doubleValue) ?? []
    }

    private func number(_ value: Any?) -> Double {
        (value as? NSNumber)?.doubleValue ?? .nan
    }

    private func checkHeading(_ rows: [[String: Any]]) {
        for (index, row) in rows.enumerated() {
            let got = IMUCalib.azimuthDegrees(
                acceleration: vector(numbers(row["a"])),
                magnetic: vector(numbers(row["m"])),
                hardIron: vector(numbers(row["center"])),
                declinationWestDegrees: number(row["decl_w"]),
                axis: vector(numbers(row["axis"]))
            )
            XCTAssertEqual(got ?? .nan, number(row["expect"]), accuracy: 1e-6, "heading \(index)")
        }
    }

    private func checkTilt(_ rows: [[String: Any]]) {
        for (index, row) in rows.enumerated() {
            let got = IMUCalib.leanAzimuthDegrees(
                acceleration: vector(numbers(row["a"])),
                magnetic: vector(numbers(row["m"])),
                hardIron: vector(numbers(row["center"])),
                declinationWestDegrees: number(row["decl_w"])
            )
            XCTAssertEqual(got ?? .nan, number(row["expect"]), accuracy: 1e-6, "tilt_azimuth \(index)")
        }
    }

    private func checkDeclination(_ rows: [[String: Any]]) {
        for (index, row) in rows.enumerated() {
            let got = IMUCalib.declinationWestDegrees(latitude: number(row["lat"]), longitude: number(row["lon"]))
            XCTAssertEqual(got, number(row["expect"]), accuracy: 1e-9, "decl_gsi2020 \(index)")
        }
    }

    private func checkReversal(_ rows: [[String: Any]]) {
        for (index, row) in rows.enumerated() {
            let a = numbers(row["A"])
            let b = numbers(row["B"])
            let got = IMUCalib.reversal(aPitch: a[0], aRoll: a[1], bPitch: b[0], bRoll: b[1])
            let bias = numbers(row["expect_bias"])
            let surface = numbers(row["expect_surface"])
            XCTAssertEqual(got.biasPitch, bias[0], accuracy: 1e-9, "reversal bias pitch \(index)")
            XCTAssertEqual(got.biasRoll, bias[1], accuracy: 1e-9, "reversal bias roll \(index)")
            XCTAssertEqual(got.surfacePitch, surface[0], accuracy: 1e-9, "reversal surface pitch \(index)")
            XCTAssertEqual(got.surfaceRoll, surface[1], accuracy: 1e-9, "reversal surface roll \(index)")
        }
    }

    private func checkSixFace(_ row: [String: Any]) {
        let faces = row["faces"] as! [String: Any]
        let got = IMUCalib.sixFace(
            positiveX: vector(numbers(faces["+x"])),
            negativeX: vector(numbers(faces["-x"])),
            positiveY: vector(numbers(faces["+y"])),
            negativeY: vector(numbers(faces["-y"])),
            positiveZ: vector(numbers(faces["+z"])),
            negativeZ: vector(numbers(faces["-z"]))
        )
        let offset = numbers(row["expect_offset"])
        let scale = numbers(row["expect_scale"])
        XCTAssertEqual(got.offset.x, offset[0], accuracy: 1e-9)
        XCTAssertEqual(got.offset.y, offset[1], accuracy: 1e-9)
        XCTAssertEqual(got.offset.z, offset[2], accuracy: 1e-9)
        XCTAssertEqual(got.scale.x, scale[0], accuracy: 1e-9)
        XCTAssertEqual(got.scale.y, scale[1], accuracy: 1e-9)
        XCTAssertEqual(got.scale.z, scale[2], accuracy: 1e-9)
    }

    private func checkSphere(_ row: [String: Any]) {
        let points = (row["points"] as! [Any]).map { vector(numbers($0)) }
        let got = IMUCalib.sphereFit(points)
        let center = numbers(row["expect_center"])
        XCTAssertEqual(got?.center.x ?? .nan, center[0], accuracy: 1e-9, "sphere center x")
        XCTAssertEqual(got?.center.y ?? .nan, center[1], accuracy: 1e-9, "sphere center y")
        XCTAssertEqual(got?.center.z ?? .nan, center[2], accuracy: 1e-9, "sphere center z")
        XCTAssertEqual(got?.radius ?? .nan, number(row["expect_radius"]), accuracy: 1e-9, "sphere radius")
    }

    private func checkRobust(_ rows: [[String: Any]]) {
        for (index, row) in rows.enumerated() {
            let got = IMUCalib.robustMean(numbers(row["values"]), k: number(row["k"]), floor: number(row["floor"]))
            XCTAssertEqual(got?.mean ?? .nan, number(row["expect_mean"]), accuracy: 1e-9, "robust mean \(index)")
            XCTAssertEqual(got?.standardDeviation ?? .nan, number(row["expect_sd"]), accuracy: 1e-9, "robust sd \(index)")
            XCTAssertEqual(got?.kept ?? -1, (row["expect_kept"] as? NSNumber)?.intValue ?? -1, "robust kept \(index)")
            XCTAssertEqual(got?.dropped ?? -1, (row["expect_dropped"] as? NSNumber)?.intValue ?? -1, "robust dropped \(index)")
        }
    }
}
