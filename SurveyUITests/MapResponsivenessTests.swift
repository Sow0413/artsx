import XCTest

/// ベーシックの地図、RTK、測る、書き出しがタップに答えることを見る。
final class MapResponsivenessTests: XCTestCase {
    private var app = XCUIApplication()
    private var shotDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("survey-ui-shots", isDirectory: true)

    override func setUpWithError() throws {
        continueAfterFailure = false
        try FileManager.default.createDirectory(at: shotDirectory, withIntermediateDirectories: true)
        app = XCUIApplication()
        app.launchArguments = ["-surveyUITest"]
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
        let tiles = expectation(description: "地理院タイル")
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { tiles.fulfill() }
        wait(for: [tiles], timeout: 12)
        let badge = app.descendants(matching: .any)["accuracy-badge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 5), "精度帯が無い")
        XCTAssertLessThan(badge.frame.height, 72, "精度帯が1行に収まっていない")
        let panel = app.descendants(matching: .any)["location-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "現在地カードが無い")
        XCTAssertLessThan(panel.frame.height, 160, "現在地カードが半分まで縮んでいない")
        shot("01-map")

        app.scrollViews["map-controls"].swipeUp()
        shot("02-map-scrolled")

        let rtk = app.buttons["rtk-entry"]
        XCTAssertTrue(rtk.isHittable, "RTK のボタンをタップできない")
        rtk.tap()
        XCTAssertTrue(app.navigationBars["RTK"].waitForExistence(timeout: 5), "RTK のシートが開かない")
        XCTAssertTrue(app.staticTexts["NTRIP"].waitForExistence(timeout: 5), "RTK の中身が出ない")
        XCTAssertTrue(app.staticTexts["vidoc-status"].waitForExistence(timeout: 5), "ViDoc の行が無い")
        XCTAssertTrue(app.staticTexts["ntrip-status"].waitForExistence(timeout: 5), "NTRIP の行が無い")
        shot("03-rtk")
        shot("03-link")
        app.buttons["閉じる"].tap()
        XCTAssertTrue(app.buttons["tab-map"].waitForExistence(timeout: 5))

        openTab("tab-measure", showing: "screen-measure")
        XCTAssertTrue(app.descendants(matching: .any)["rtk-status"].waitForExistence(timeout: 5), "測る画面に RTK の状態が無い")
        let sheet = app.scrollViews["screen-measure"]
        scrollClear(app.staticTexts["vidoc-status"], in: sheet)
        XCTAssertTrue(app.staticTexts["ntrip-status"].exists)
        shot("04-link")
        let intro = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'します。'")).firstMatch
        XCTAssertTrue(intro.waitForExistence(timeout: 5), "測るの説明が無い")
        let badge = app.descendants(matching: .any)["accuracy-badge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(intro.frame.minY, badge.frame.maxY - 1, "説明が黄帯の下に隠れている")
        scrollClear(app.textFields["stakeout-height"], in: sheet)
        shot("04-measure")

        let project = app.textFields["basic-project-name"]
        scrollClear(project, in: sheet)
        replace(project, with: "SiteA")
        let create = app.buttons["basic-create"]
        scrollClear(create, in: sheet)
        create.tap()
        let made = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'SiteA'")).firstMatch
        XCTAssertTrue(made.waitForExistence(timeout: 5), "プロジェクトを作れない")
        scrollClear(app.textFields["stakeout-latitude"], in: sheet)
        shot("07-project")
        scrollClear(project, in: sheet)
        replace(project, with: "SiteB")
        let rename = app.buttons["basic-rename"]
        scrollClear(rename, in: sheet)
        rename.tap()
        let renamed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'SiteB'")).firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 5), "名前を変えられない")
        shot("07b-rename")

        let save = app.scrollViews["screen-measure"].buttons["basic-save"]
        XCTAssertEqual(app.scrollViews["screen-measure"].buttons.matching(identifier: "basic-save").count, 1)
        tapWhenClear(save, in: sheet, missing: "現在地を残すが押せない")
        let confirm = app.buttons["この点を確定"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 12), "確認のボタンが出ない")
        tapWhenClear(confirm, in: sheet, missing: "この点を確定が押せない")
        let saved = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'を残しました' AND NOT label CONTAINS '基準点'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 12), "点を残した文が無い")
        scrollClear(saved, in: sheet)
        shot("08-save")
        let book = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'T1' AND label CONTAINS '下見'")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 5), "残した点が座標簿に無い")
        scrollClear(book, in: sheet)
        shot("09-book")

        tapClear("basic-export-csv", in: sheet)
        let wrote = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '書きました'")).firstMatch
        XCTAssertTrue(wrote.waitForExistence(timeout: 5), "座標一覧を書き出せない")
        scrollClear(wrote, in: sheet)
        shot("10-export")
        tapClear("basic-import", in: sheet)
        let imported = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '1点を読みました'")).firstMatch
        XCTAssertTrue(imported.waitForExistence(timeout: 5), "座標を読み込めない")
        scrollClear(imported, in: sheet)
        shot("11-import")
        tapClear("basic-backup", in: sheet)
        let backup = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'バックアップを作りました'")).firstMatch
        XCTAssertTrue(backup.waitForExistence(timeout: 5), "バックアップを作れない")
        scrollClear(backup, in: sheet)
        shot("12-backup")
        tapClear("basic-restore", in: sheet)
        let restored = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '1点を戻しました'")).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 5), "バックアップから戻せない")
        scrollClear(restored, in: sheet)
        shot("13-restore")

        let stake = app.buttons["basic-stakeout"]
        scrollClear(stake, in: sheet)
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
        let gcp = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'を基準点にしました'")).firstMatch
        XCTAssertTrue(gcp.waitForExistence(timeout: 5), "基準点を残した文が無い")
        shot("15-gcp")

        openTab("tab-export", showing: "screen-export")
        scrollClear(app.textFields["book-imported-day"], in: app.scrollViews["screen-export"])
        shot("05-export")
        openTab("tab-map", showing: "map-controls")
        shot("06-map-return")
    }

    private func replace(_ field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        var entered = false
        for _ in 0..<2 {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let current = (field.value as? String) ?? ""
            if current.contains(text) {
                entered = true
                break
            }
            if !current.isEmpty, current != "プロジェクト名" {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: min(current.count, 40)))
            }
            field.typeText(text)
            let typed = expectation(for: NSPredicate(format: "value CONTAINS %@", text), evaluatedWith: field)
            if XCTWaiter().wait(for: [typed], timeout: 4) == .completed {
                entered = true
                break
            }
        }
        XCTAssertTrue(entered, "\(text) が欄に入らない")
        let keys = ["Return", "改行", "完了", "Done"]
        for key in keys where app.keyboards.buttons[key].exists {
            app.keyboards.buttons[key].tap()
            return
        }
    }

    private func tapWhenClear(_ element: XCUIElement, in sheet: XCUIElement, missing: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), missing)
        scrollClear(element, in: sheet)
        let hittable = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: element)
        if XCTWaiter().wait(for: [hittable], timeout: 3) != .completed {
            scrollClear(element, in: sheet)
        }
        XCTAssertTrue(element.isHittable, missing)
        element.tap()
    }

    private func tapClear(_ identifier: String, in sheet: XCUIElement) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "\(identifier) が無い")
        scrollClear(button, in: sheet)
        button.tap()
    }

    /// 欄の下端をタブバーの上まで動かす。ずらし量は枠の差で、試行は4回まで。
    private func scrollClear(_ element: XCUIElement, in sheet: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        for _ in 0..<4 where !clearOfTabBar(element) {
            let frame = element.frame
            let top = tabBarTop()
            let delta: CGFloat
            if frame.maxY > top - 12 {
                delta = -min(frame.maxY - (top - 12) + 20, 360)
            } else if !element.isHittable || frame.minY < 72 {
                let gap = frame.maxY < 100 ? 160 - frame.maxY : 140 - frame.minY
                delta = min(max(gap, 100), 360)
            } else {
                delta = 0
            }
            if delta == 0 { break }
            let start = sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            start.press(forDuration: 0.02, thenDragTo: start.withOffset(CGVector(dx: 0, dy: delta)))
        }
        XCTAssertTrue(clearOfTabBar(element), "欄がタブバーに隠れたまま")
    }

    private func tabBarTop() -> CGFloat {
        ["tab-map", "tab-measure", "tab-export"].compactMap { identifier -> CGFloat? in
            let tab = app.buttons[identifier]
            return tab.exists ? tab.frame.minY : nil
        }.min() ?? app.frame.maxY
    }

    private func clearOfTabBar(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        return element.frame.minY >= 72 && element.frame.maxY <= tabBarTop() - 8
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
