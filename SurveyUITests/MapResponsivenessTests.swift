import XCTest

/// 起動直後の地図が、タップとスクロールに答え続けることを見る。
final class MapResponsivenessTests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        allowSystemPrompts()
        dismissStaturePrompt()
        allowSystemPrompts()
    }

    func testMapStaysResponsiveAndOpensRTK() {
        let map = app.buttons["tab-map"]
        XCTAssertTrue(map.waitForExistence(timeout: 8), "地図タブが出ない")
        waitUntilSelected(map, name: "地図")

        let controls = app.scrollViews["map-controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 5), "地図の操作をスクロールできない")
        controls.swipeUp()
        let pace = app.buttons["歩測"]
        XCTAssertTrue(pace.waitForExistence(timeout: 5), "歩測ボタンが無い")
        XCTAssertTrue(pace.isHittable, "歩測ボタンをタップできない")

        openTab("tab-drawing", showing: "DXF")
        openTab("tab-measure", showing: "GNSS")
        openTab("tab-export", showing: "受取手")
        openTab("tab-map", showing: "map-controls")

        let rtk = app.buttons["rtk-entry"]
        XCTAssertTrue(rtk.waitForExistence(timeout: 5), "RTK のボタンが届かない")
        XCTAssertTrue(rtk.isHittable, "RTK のボタンをタップできない")
        rtk.tap()
        let sheet = app.navigationBars["RTK"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "RTK のシートが開かない")
        XCTAssertTrue(app.staticTexts["NTRIP"].waitForExistence(timeout: 5), "RTK の中身が出ない")
    }

    private func openTab(_ identifier: String, showing needle: String) {
        let tab = app.buttons[identifier]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "\(identifier) が無い")
        tab.tap()
        XCTAssertTrue(marker(needle).waitForExistence(timeout: 5), "\(identifier) をタップしても画面が変わらない")
    }

    private func marker(_ needle: String) -> XCUIElement {
        if needle == "map-controls" {
            return app.scrollViews["map-controls"]
        }
        return app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", needle)).firstMatch
    }

    private func waitUntilSelected(_ element: XCUIElement, name: String) {
        let selected = expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: element)
        let result = XCTWaiter().wait(for: [selected], timeout: 5)
        XCTAssertEqual(result, .completed, "\(name) が選ばれない")
    }

    private func dismissStaturePrompt() {
        let later = app.buttons["あとで"]
        guard later.waitForExistence(timeout: 3) else { return }
        later.tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: later)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "身長の確認を閉じられない")
    }

    private func allowSystemPrompts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let labels = [
            "Allow While Using App",
            "Allow Once",
            "Allow",
            "OK",
            "許可",
            "Appの使用中は許可",
            "アプリの使用中は許可",
            "一度だけ許可"
        ]
        for _ in 0..<3 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 2) else { return }
            var tapped = false
            for label in labels where alert.buttons[label].exists {
                alert.buttons[label].tap()
                tapped = true
                break
            }
            if !tapped, alert.buttons.firstMatch.exists {
                alert.buttons.firstMatch.tap()
            }
        }
    }
}
