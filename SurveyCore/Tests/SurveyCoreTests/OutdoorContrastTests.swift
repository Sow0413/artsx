import XCTest
@testable import SurveyCore

final class OutdoorContrastTests: XCTestCase {
    func testOutdoorPairsMeetAAA() {
        for pair in OutdoorContrast.pairs {
            let ratio = OutdoorContrast.ratio(pair.foreground, pair.background)
            let minimum = pair.largeText ? OutdoorContrast.largeRatio : OutdoorContrast.bodyRatio
            print(String(format: "SURVEY CONTRAST %@ %.2f / 目標 %.1f", pair.name, ratio, minimum))
            XCTAssertGreaterThanOrEqual(ratio, minimum, pair.name)
            XCTAssertTrue(OutdoorContrast.passesAAA(pair), pair.name)
        }
    }

    func testYellowOnWhiteIsNotUsedAsText() {
        let yellowOnWhite = OutdoorContrast.ratio(OutdoorContrast.yellow, OutdoorContrast.white)
        XCTAssertLessThan(yellowOnWhite, OutdoorContrast.bodyRatio)
        XCTAssertGreaterThanOrEqual(
            OutdoorContrast.ratio(OutdoorContrast.black, OutdoorContrast.yellow),
            OutdoorContrast.largeRatio
        )
    }

    func testFaintInkBecomesBlack() {
        let yellow = OutdoorContrast.ink(red: 1, green: 1, blue: 0)
        XCTAssertEqual(yellow, OutdoorContrast.black)
        let green = OutdoorContrast.ink(red: 0, green: 1, blue: 0)
        XCTAssertEqual(green, OutdoorContrast.black)
        let navy = OutdoorContrast.ink(red: 0, green: 45 / 255, blue: 156 / 255)
        XCTAssertEqual(navy, OutdoorContrast.blue)
    }

    func testBrightnessSwitchesTheOutdoorTheme() {
        XCTAssertFalse(OutdoorContrast.prefersOutdoor(.automatic, brightness: 0.59))
        XCTAssertTrue(OutdoorContrast.prefersOutdoor(.automatic, brightness: 0.6))
        XCTAssertTrue(OutdoorContrast.prefersOutdoor(.outdoor, brightness: 0))
        XCTAssertFalse(OutdoorContrast.prefersOutdoor(.indoor, brightness: 1))
    }

    func testPrimaryControlIsGloveSized() {
        XCTAssertGreaterThanOrEqual(OutdoorContrast.primaryPoints, 60)
        XCTAssertGreaterThanOrEqual(OutdoorContrast.strokePoints, 3)
    }
}
