import XCTest

/// ベーシックの地図、RTK、測る、書き出しがタップに答えることを見る。
final class MapResponsivenessTests: XCTestCase {
    private var app = XCUIApplication()
    private var shotDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("survey-ui-shots", isDirectory: true)

    override func setUpWithError() throws {
        continueAfterFailure = false
        try FileManager.default.createDirectory(at: shotDirectory, withIntermediateDirectories: true)
        app = XCUIApplication()
        app.launch()
        allowSystemPrompts()
        dismissStaturePrompt()
        allowSystemPrompts()
    }

    func testBasicMapMeasureExportAndRTK() {
        let map = app.buttons["tab-map"]
        XCTAssertTrue(map.waitForExistence(timeout: 8), "地図タブが出ない")
        waitUntilSelected(map, name: "地図")
        XCTAssertFalse(app.buttons["tab-drawing"].exists, "図面タブがベーシックに残っている")
        XCTAssertFalse(app.buttons["tab-seat"].exists, "オペタブがベーシックに残っている")
        XCTAssertFalse(app.buttons["水準器"].exists, "水準器がベーシックの地図に出ている")
        XCTAssertTrue(app.scrollViews["map-controls"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["rtk-entry"].waitForExistence(timeout: 5), "RTK のボタンが画面に無い")
        shot("01-map")

        app.scrollViews["map-controls"].swipeUp()
        shot("02-map-scrolled")

        let rtk = app.buttons["rtk-entry"]
        XCTAssertTrue(rtk.isHittable, "RTK のボタンをタップできない")
        rtk.tap()
        XCTAssertTrue(app.navigationBars["RTK"].waitForExistence(timeout: 5), "RTK のシートが開かない")
        XCTAssertTrue(app.staticTexts["NTRIP"].waitForExistence(timeout: 5), "RTK の中身が出ない")
        shot("03-rtk")
        app.buttons["閉じる"].tap()
        XCTAssertTrue(app.buttons["tab-map"].waitForExistence(timeout: 5))

        openTab("tab-measure", showing: "screen-measure")
        XCTAssertTrue(app.descendants(matching: .any)["rtk-status"].waitForExistence(timeout: 5), "測る画面に RTK の状態が無い")
        shot("04-measure")
        let sheet = app.scrollViews["screen-measure"]
        sheet.swipeUp()

        let project = app.textFields["basic-project-name"]
        XCTAssertTrue(project.waitForExistence(timeout: 5), "プロジェクト名が無い")
        project.tap()
        project.typeText("SiteA")
        app.buttons["basic-create"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'SiteA'")).firstMatch.waitForExistence(timeout: 5), "プロジェクトを作れない")
        shot("07-project")
        project.tap()
        project.typeText("SiteB")
        app.buttons["basic-rename"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'SiteB'")).firstMatch.waitForExistence(timeout: 5), "名前を変えられない")
        shot("07b-rename")

        let save = app.scrollViews["screen-measure"].buttons["basic-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "測る画面の中に保存ボタンが無い")
        XCTAssertEqual(app.scrollViews["screen-measure"].buttons.matching(identifier: "basic-save").count, 1)
        save.tap()
        let confirm = app.scrollViews["screen-measure"].buttons["この点を確定"]
        if confirm.waitForExistence(timeout: 4) {
            confirm.tap()
        }
        shot("08-save")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'T1'")).firstMatch.waitForExistence(timeout: 5), "残した点が座標簿に無い")
        shot("09-book")

        app.buttons["basic-export-csv"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '書き' OR label CONTAINS '点'")).firstMatch.waitForExistence(timeout: 5))
        shot("10-export")
        app.buttons["basic-import"].tap()
        shot("11-import")
        dismissPicker()
        app.buttons["basic-backup"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'バックアップ'")).firstMatch.waitForExistence(timeout: 5))
        shot("12-backup")
        app.buttons["basic-restore"].tap()
        shot("13-restore")
        dismissPicker()

        let stake = app.buttons["basic-stakeout"]
        if !stake.isHittable {
            sheet.swipeUp()
        }
        stake.tap()
        openTab("tab-map", showing: "stakeout-guide")
        let guide = app.descendants(matching: .any)["stakeout-guide"]
        let numbers = expectation(
            for: NSPredicate(format: "label CONTAINS '方位' AND label CONTAINS '北' AND label CONTAINS '東'"),
            evaluatedWith: guide
        )
        XCTAssertEqual(XCTWaiter().wait(for: [numbers], timeout: 8), .completed, "測設に距離と方位と南北東西が出ない")
        shot("14-stakeout")
        app.buttons["basic-gcp"].tap()
        shot("15-gcp")

        openTab("tab-export", showing: "screen-export")
        shot("05-export")
        openTab("tab-map", showing: "map-controls")
        shot("06-map-return")
    }

    private func dismissPicker() {
        let cancel = app.buttons["Cancel"]
        let japanese = app.buttons["キャンセル"]
        if cancel.waitForExistence(timeout: 2) {
            cancel.tap()
        } else if japanese.waitForExistence(timeout: 1) {
            japanese.tap()
        }
    }

    private func openTab(_ identifier: String, showing needle: String) {
        let tab = app.buttons[identifier]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "\(identifier) が無い")
        tab.tap()
        waitUntilSelected(tab, name: identifier)
        XCTAssertTrue(marker(needle).waitForExistence(timeout: 5), "\(identifier) をタップしても画面が変わらない")
    }

    private func marker(_ needle: String) -> XCUIElement {
        app.descendants(matching: .any)[needle]
    }

    private func waitUntilSelected(_ element: XCUIElement, name: String) {
        let selected = expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: element)
        let result = XCTWaiter().wait(for: [selected], timeout: 5)
        XCTAssertEqual(result, .completed, "\(name) が選ばれない")
    }

    private func dismissStaturePrompt() {
        let later = app.buttons["あとで"]
        guard later.waitForExistence(timeout: 1) else { return }
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

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let url = shotDirectory.appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: url)
    }
}
