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
        if name.contains("DrawingFixture") {
            app.launchArguments.append("-surveyUITestDrawings")
        }
        app.launch()
        allowSystemPrompts()
        dismissStaturePrompt()
        allowSystemPrompts()
    }

    func testDrawingFixtureMapOverlays() {
        let steps = [
            (1, "1_irabu", "34-draw-irabu", 40.0),
            (2, "2_nagoya", "35-draw-nagoya", 40.0),
            (3, "ミリ", "36-draw-mm", 40.0),
            (4, "置きました", "37-draw-heavy", 90.0),
            (5, "途中で切れています", "38-draw-broken", 30.0),
            (6, "DXF の形になっていません", "39-draw-empty", 30.0),
            (7, "1系", "40-draw-wrong-zone", 30.0),
            (8, "位置合わせが必要", "41-sfig-list", 40.0),
            (9, "点名で合わせました", "42-sfig-aligned", 40.0),
            (10, "点名で合わせました", "43-zoom-low", 40.0),
            (11, "点名で合わせました", "44-zoom-mid", 40.0),
            (12, "点名で合わせました", "45-zoom-near-max", 40.0),
            (13, "点名で合わせました", "46-zoom-max", 40.0)
        ]
        for step in steps {
            app.terminate()
            app.launchArguments = ["-surveyUITest", "-surveyUITestDrawings", "-uitestDrawing", "\(step.0)"]
            app.launch()
            allowSystemPrompts()
            dismissStaturePrompt()
            let status = app.staticTexts["draw-overlay-status"]
            let shown = expectation(for: NSPredicate(format: "label CONTAINS %@", step.1), evaluatedWith: status)
            XCTAssertEqual(
                XCTWaiter().wait(for: [shown], timeout: step.3),
                .completed,
                "\(step.2) の結果が出ない。表示は \(status.exists ? status.label : "なし")"
            )
            let map = app.buttons["tab-map"]
            if map.waitForExistence(timeout: 5) { map.tap() }
            if step.2 == "42-sfig-aligned" || step.2.contains("zoom") {
                XCTAssertFalse(status.label.contains("仮置き"), "合わせたあとも仮置きが残っている")
                let tiles = expectation(description: "地理院タイル")
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) { tiles.fulfill() }
                wait(for: [tiles], timeout: 10)
            }
            shot(step.2)
        }
    }

    func testDrawingPickerAppears() {
        app.terminate()
        app.launchArguments = ["-surveyUITest", "-surveyUITestPicker"]
        app.launch()
        allowSystemPrompts()
        dismissStaturePrompt()
        let tab = app.buttons["tab-export"]
        XCTAssertTrue(tab.waitForExistence(timeout: 8), "出すタブが無い")
        tab.tap()
        let draw = app.buttons["open-draw"]
        XCTAssertTrue(draw.waitForExistence(timeout: 8), "図面を読み込むが無い")
        draw.tap()
        let read = app.buttons["draw-import"]
        XCTAssertTrue(read.waitForExistence(timeout: 8), "図面を読むが無い")
        XCTAssertTrue(read.label.contains("図面を読む"))
        read.tap()
        let labels = ["キャンセル", "Cancel", "ブラウズ", "Browse", "最近使った項目", "Recents"]
        func pickerIsVisible() -> Bool {
            labels.contains { label in
                app.buttons[label].exists || app.navigationBars[label].exists || app.staticTexts[label].exists
            }
        }
        var picker = false
        for _ in 0..<2 {
            let appeared = expectation(description: "書類ピッカー")
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { appeared.fulfill() }
            wait(for: [appeared], timeout: 10)
            if pickerIsVisible() {
                picker = true
                break
            }
            if read.exists { read.tap() }
        }
        XCTAssertTrue(picker, "図面を読むを押しても書類ピッカーが出ない")
        shot("50-draw-picker")
        if app.buttons["キャンセル"].exists {
            app.buttons["キャンセル"].tap()
        } else if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        }
    }

    func testCoordinateImportAndStakeout() {
        app.terminate()
        app.launchArguments = ["-surveyUITest", "-uitestLatitude", "34.6", "-uitestLongitude", "135.8"]
        app.launch()
        allowSystemPrompts()
        dismissStaturePrompt()
        let map = app.buttons["tab-map"]
        XCTAssertTrue(map.waitForExistence(timeout: 8), "地図タブが無い")
        map.tap()
        openLoadMenu()
        let load = menuItem("import-coordinates", title: "座標を読み込む")
        XCTAssertTrue(load.waitForExistence(timeout: 8), "座標を読み込むが無い")
        let draw = menuItem("map-open-draw", title: "図面を読む")
        XCTAssertTrue(draw.waitForExistence(timeout: 5), "図面を読むが無い")
        shot("53-coord-button")
        load.tap()
        if app.buttons["coord-zone-6"].waitForExistence(timeout: 3) {
            app.buttons["coord-zone-6"].tap()
        }
        let marks = app.staticTexts["survey-points"]
        XCTAssertTrue(marks.waitForExistence(timeout: 10), "測点が出ない")
        XCTAssertGreaterThanOrEqual(Int(marks.label.replacingOccurrences(of: "測点 ", with: "")) ?? 0, 34)
        assertLoadMenuStays()
        shot("54-coord-loaded")
        openLoadMenu()
        let pick = menuItem("pick-imported-point", title: "T4-15'")
        XCTAssertTrue(pick.waitForExistence(timeout: 5), "点を選べない")
        pick.tap()
        let back = app.buttons["selection-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "戻るが無い")
        XCTAssertTrue(back.label.contains("戻る"))
        back.tap()
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["stake-selected"])
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 5), .completed, "戻っても測設が残る")
        openLoadMenu()
        let pickAgain = menuItem("pick-imported-point", title: "T4-15'")
        XCTAssertTrue(pickAgain.waitForExistence(timeout: 5), "点を選び直せない")
        pickAgain.tap()
        let stake = app.buttons["stake-selected"]
        XCTAssertTrue(stake.waitForExistence(timeout: 5), "測設が無い")
        shot("55-point-select")
        stake.tap()
        assertStakeoutOffsetsVisible()
        XCTAssertTrue(app.staticTexts["stakeout-zone"].label.contains("第VI系"))
        assertLoadMenuStays()
        shot("56-stakeout")
        let stop = app.buttons["stakeout-stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5), "測設をやめるが無い")
        XCTAssertTrue(stop.label.contains("測設をやめる"))
        stop.tap()
        let guide = app.descendants(matching: .any)["stakeout-guide"]
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: guide)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "測設をやめても案内が残る")
        assertLoadMenuStays()
    }

    func testVIDrawingAndSurveyPoints() {
        app.terminate()
        app.launchArguments = ["-surveyUITest", "-uitestField", "vi", "-uitestLatitude", "34.60045", "-uitestLongitude", "135.8"]
        app.launch()
        allowSystemPrompts()
        dismissStaturePrompt()
        openDrawingImport()
        let preview = app.descendants(matching: .any)["sheet-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 25), "図面のプレビューが無い")
        let place = app.buttons["view-on-map"]
        XCTAssertTrue(place.waitForExistence(timeout: 5), "地図で見るが無い")
        XCTAssertTrue(place.label.contains("地図で見る"))
        XCTAssertFalse(app.buttons["go-scale"].exists, "座標のある図面に縮尺設定が出ている")
        XCTAssertTrue(app.staticTexts["draw-result"].label.contains("図面を座標で置きました（第VI系）"))
        shot("47-vi-preview")
        place.tap()
        let zone = app.staticTexts["map-zone"]
        XCTAssertTrue(zone.waitForExistence(timeout: 15), "6系の図面が出ない")
        XCTAssertEqual(zone.label, "6系")
        let marks = app.staticTexts["survey-points"]
        XCTAssertTrue(marks.waitForExistence(timeout: 8), "測点が出ない")
        let countText = marks.label.replacingOccurrences(of: "測点 ", with: "")
        XCTAssertGreaterThanOrEqual(Int(countText) ?? 0, 34)
        let tiles = expectation(description: "地理院タイル")
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { tiles.fulfill() }
        wait(for: [tiles], timeout: 8)
        shot("48-vi-map")
        assertLoadMenuStays()
        openLoadMenu()
        let vertex = menuItem("cad-tap-vertex", title: "図面の頂点")
        XCTAssertTrue(vertex.waitForExistence(timeout: 5), "図面の頂点が無い")
        vertex.tap()
        let stakeHere = app.buttons["cad-stake"]
        XCTAssertTrue(stakeHere.waitForExistence(timeout: 5), "ここへ測設が無い")
        XCTAssertTrue(app.staticTexts["cad-target-name"].waitForExistence(timeout: 5), "図面の点名が無い")
        shot("57-cad-tap")
        stakeHere.tap()
        let distance = app.staticTexts["cad-distance"]
        let arrived = expectation(for: NSPredicate(format: "label CONTAINS 'あと' OR label CONTAINS '到達'"), evaluatedWith: distance)
        XCTAssertEqual(XCTWaiter().wait(for: [arrived], timeout: 20), .completed, "距離が出ない。表示は \(distance.label)")
        shot("58-cad-target")
        shot("59-cad-guide")
        assertLoadMenuStays()
        let stopGuide = app.buttons["stakeout-stop"]
        XCTAssertTrue(stopGuide.waitForExistence(timeout: 5), "測設をやめるが無い")
        stopGuide.tap()
        let data = app.buttons["tab-measure"]
        XCTAssertTrue(data.waitForExistence(timeout: 5))
        data.tap()
        let ledger = app.buttons["open-ledger"]
        XCTAssertTrue(ledger.waitForExistence(timeout: 5))
        ledger.tap()
        let book = app.staticTexts["book-count"]
        XCTAssertTrue(book.waitForExistence(timeout: 8))
        XCTAssertTrue(book.label.contains("第VI系"))
        let named = app.staticTexts["book-ll-T4-15'"]
        XCTAssertTrue(named.waitForExistence(timeout: 5), "T4-15' の経緯度が無い")
        XCTAssertTrue(named.label.contains("34.60000"))
        XCTAssertTrue(named.label.contains("135.80000"))
        XCTAssertTrue(app.staticTexts["book-ll-S01"].waitForExistence(timeout: 5), "SIMA の S01 が無い")
        shot("49-vi-book")

        app.terminate()
        app.launchArguments = ["-surveyUITest", "-uitestField", "vi-fail"]
        app.launch()
        allowSystemPrompts()
        dismissStaturePrompt()
        openDrawingImport()
        let failed = app.staticTexts["draw-result"]
        XCTAssertTrue(failed.waitForExistence(timeout: 15), "失敗の文が無い")
        XCTAssertTrue(failed.label.contains("読めませんでした"))
        shot("51-vi-fail")

        app.terminate()
        app.launchArguments = ["-surveyUITest", "-uitestField", "vi-nomet"]
        app.launch()
        allowSystemPrompts()
        dismissStaturePrompt()
        openDrawingImport()
        let sixth = app.buttons["sheet-zone-6"]
        XCTAssertTrue(sixth.waitForExistence(timeout: 20), "第VI系のピッカーが無い")
        XCTAssertEqual(sixth.label, "第VI系")
        XCTAssertTrue(app.staticTexts["draw-result"].label.contains("meta.json"))
        shot("52-vi-zone-picker")
    }

    private func openLoadMenu() {
        let menu = app.buttons["map-load"]
        XCTAssertTrue(menu.waitForExistence(timeout: 8), "読込が無い")
        if !app.buttons["図面を読む"].exists && !app.buttons["座標を読む"].exists && !app.buttons["座標を読み込む"].exists {
            menu.tap()
        }
    }

    private func menuItem(_ identifier: String, title: String) -> XCUIElement {
        let identified = app.buttons[identifier]
        if identified.waitForExistence(timeout: 4) { return identified }
        let titled = app.buttons[title]
        if titled.waitForExistence(timeout: 2) { return titled }
        return identified
    }

    private func assertLoadMenuStays() {
        let menu = app.buttons["map-load"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "読込が隠れた")
        XCTAssertTrue(menu.isHittable || app.frame.intersects(menu.frame), "読込が押せない")
    }

    private func assertStakeoutOffsetsVisible() {
        let north = app.staticTexts["stakeout-north"]
        let east = app.staticTexts["stakeout-east"]
        let ready = expectation(for: NSPredicate(format: "exists == true AND label MATCHES '.*[0-9].*'"), evaluatedWith: north)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 25), .completed, "北か南が出ない。表示は \(north.label)")
        XCTAssertTrue(north.label.contains("北") || north.label.contains("南"))
        XCTAssertTrue(east.waitForExistence(timeout: 5), "東か西が出ない。表示は \(east.label)")
        XCTAssertTrue(east.label.contains("東") || east.label.contains("西"))
        XCTAssertNotNil(north.label.range(of: "[0-9]", options: .regularExpression))
        XCTAssertNotNil(east.label.range(of: "[0-9]", options: .regularExpression))
        XCTAssertFalse(north.label.contains("+"))
        XCTAssertFalse(east.label.contains("+"))
        XCTAssertTrue(north.isHittable || app.frame.intersects(north.frame), "北か南が画面の外")
        XCTAssertTrue(east.isHittable || app.frame.intersects(east.frame), "東か西が画面の外")
    }

    private func openDrawingImport() {
        let tab = app.buttons["tab-export"]
        XCTAssertTrue(tab.waitForExistence(timeout: 8), "出すタブが無い")
        tab.tap()
        let draw = app.buttons["open-draw"]
        XCTAssertTrue(draw.waitForExistence(timeout: 8), "図面を読み込むが無い")
        draw.tap()
        XCTAssertTrue(app.scrollViews["screen-draw"].waitForExistence(timeout: 8), "図面の読み込みが開かない")
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
        let record = app.buttons["map-record"]
        XCTAssertTrue(record.waitForExistence(timeout: 5), "記録ボタンが無い")
        scrollClear(record, in: app.scrollViews["map-controls"])
        let gcp = app.buttons["basic-gcp"]
        XCTAssertTrue(gcp.exists, "GCP ボタンが無い")
        XCTAssertFalse(gcp.isEnabled, "FIX 以外で GCP が押せる")
        XCTAssertLessThan(panel.frame.height, 210, "現在地カードが半分まで縮んでいない")
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
        let siteTile = app.buttons["open-site"]
        let ledgerTile = app.buttons["open-ledger"]
        let exportTile = app.buttons["open-export"]
        XCTAssertTrue(siteTile.waitForExistence(timeout: 5), "データに現場管理が無い")
        XCTAssertTrue(siteTile.label.contains("現場管理"))
        XCTAssertTrue(ledgerTile.label.contains("データ管理"))
        XCTAssertTrue(exportTile.label.contains("データ書き出し"))
        XCTAssertTrue(siteTile.label.contains("先にここ"), "未選択の現場が目立っていない")
        XCTAssertFalse(app.buttons["basic-save"].exists, "データに現在地を残すが残っている")
        XCTAssertFalse(app.descendants(matching: .any)["rtk-status"].exists, "データの GNSS 状態が残っている")
        let measureBadge = app.descendants(matching: .any)["accuracy-badge"]
        XCTAssertTrue(measureBadge.waitForExistence(timeout: 5))
        XCTAssertLessThan(measureBadge.frame.height, 72, "データの精度帯が1行に収まっていない")
        XCTAssertGreaterThanOrEqual(siteTile.frame.minY, measureBadge.frame.maxY - 1, "現場管理が状態バーの下に無い")
        XCTAssertGreaterThanOrEqual(siteTile.frame.height, 56, "現場管理のタイルが小さい")
        shot("16-data")
        let home = app.scrollViews["screen-measure"]
        scrollClear(exportTile, in: home)
        shot("16-data-bottom")
        scrollClear(siteTile, in: home)

        siteTile.tap()
        let siteSheet = app.scrollViews["screen-site"]
        XCTAssertTrue(siteSheet.waitForExistence(timeout: 5), "現場管理が開かない")
        XCTAssertLessThan(measureBadge.frame.height, 72, "現場管理の精度帯が1行でない")
        shot("18-site")
        shot("04-link")
        let project = app.textFields["basic-project-name"]
        scrollClear(project, in: siteSheet)
        replace(project, with: "SiteA")
        let create = app.buttons["basic-create"]
        scrollClear(create, in: siteSheet)
        XCTAssertGreaterThanOrEqual(create.frame.height, 56, "作るが小さい")
        create.tap()
        let made = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'SiteA'")).firstMatch
        XCTAssertTrue(made.waitForExistence(timeout: 5), "プロジェクトを作れない")
        shot("07-project")
        scrollClear(project, in: siteSheet)
        replace(project, with: "SiteB")
        let rename = app.buttons["basic-rename"]
        scrollClear(rename, in: siteSheet)
        rename.tap()
        let renamed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'SiteB'")).firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 5), "名前を変えられない")
        shot("07b-rename")
        shot("18-site-bottom")
        app.buttons["data-back"].tap()
        XCTAssertTrue(home.waitForExistence(timeout: 5), "データトップに戻らない")
        let recordNext = app.buttons["go-map-record"]
        XCTAssertTrue(recordNext.waitForExistence(timeout: 5), "地図で記録へ戻れない")
        scrollClear(recordNext, in: home)
        shot("16-data-record")
        let setup = app.buttons["open-setup"]
        scrollClear(setup, in: home)
        setup.tap()
        let setupSheet = app.scrollViews["screen-setup"]
        XCTAssertTrue(setupSheet.waitForExistence(timeout: 5), "器械設定が開かない")
        shot("27-setup")
        let downLaser = app.buttons["下レーザー"]
        scrollClear(downLaser, in: setupSheet)
        downLaser.tap()
        let aim = app.buttons["laser-light"]
        let readLaser = app.buttons["laser-measure"]
        XCTAssertTrue(aim.waitForExistence(timeout: 5), "点灯が無い")
        XCTAssertTrue(readLaser.waitForExistence(timeout: 5), "測るが無い")
        XCTAssertTrue(app.staticTexts["laser-status"].waitForExistence(timeout: 5), "レーザーの状態が無い")
        scrollClear(aim, in: setupSheet)
        shot("27-laser")
        let frontAim = app.buttons["laser-front-light"]
        let frontRead = app.buttons["laser-front-measure"]
        scrollClear(frontAim, in: setupSheet)
        XCTAssertTrue(frontAim.waitForExistence(timeout: 5), "前の点灯が無い")
        XCTAssertTrue(frontRead.waitForExistence(timeout: 5), "前の測るが無い")
        shot("27-front-laser")
        let calib = app.buttons["open-calib"]
        scrollClear(calib, in: setupSheet)
        calib.tap()
        XCTAssertTrue(app.staticTexts["screen-calib-tilt"].waitForExistence(timeout: 5), "傾きの校正が開かない")
        shot("29-calib-tilt")
        app.buttons["calib-read-a"].tap()
        let readB = app.buttons["calib-read-b"]
        XCTAssertTrue(readB.waitForExistence(timeout: 5), "B を読めない")
        readB.tap()
        app.buttons["calib-save"].tap()
        XCTAssertTrue(app.staticTexts["screen-calib-mag"].waitForExistence(timeout: 5), "方位の校正が開かない")
        shot("30-calib-mag")
        app.buttons["calib-mock-spin"].tap()
        XCTAssertTrue(app.staticTexts["screen-calib-live"].waitForExistence(timeout: 5), "確かめが開かない")
        shot("31-calib-live")
        app.buttons["calib-close"].tap()
        let rawToggle = app.switches["raw-capture"]
        scrollClear(rawToggle, in: setupSheet)
        XCTAssertEqual(rawToggle.value as? String, "1", "観測モードが既定でオンでない")
        shot("32-raw-setting")
        let ppk = app.buttons["ppk-toggle"]
        scrollClear(ppk, in: setupSheet)
        ppk.tap()
        let ppkState = app.staticTexts["ppk-status"]
        XCTAssertTrue(ppkState.waitForExistence(timeout: 5))
        XCTAssertTrue(ppkState.label.contains("記録中"))
        shot("28-ppk")
        ppk.tap()
        let saveSetup = app.buttons["setup-save"]
        scrollClear(saveSetup, in: setupSheet)
        saveSetup.tap()
        XCTAssertTrue(app.staticTexts["setup-result"].waitForExistence(timeout: 5), "器械設定の結果が無い")
        shot("27-setup-result")
        app.buttons["data-back"].tap()
        XCTAssertTrue(home.waitForExistence(timeout: 5))

        openTab("tab-map", showing: "map-record")
        XCTAssertTrue(record.waitForExistence(timeout: 5), "地図の記録が無い")
        record.tap()
        let stagedNote = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'を仮置きしました'")).firstMatch
        XCTAssertTrue(stagedNote.waitForExistence(timeout: 12), "地図の記録で仮置きできない")
        let rawLive = app.staticTexts["raw-status"]
        XCTAssertTrue(rawLive.waitForExistence(timeout: 5), "観測中の記録中が無い")
        XCTAssertTrue(rawLive.label.contains("記録中"))
        shot("33-raw-recording")
        openTab("tab-measure", showing: "screen-measure")
        let ledgerHome = app.buttons["open-ledger"]
        scrollClear(ledgerHome, in: app.scrollViews["screen-measure"])
        XCTAssertTrue(ledgerHome.label.contains("仮置き"), "仮置きの件数が目立っていない")
        ledgerHome.tap()
        let ledger = app.scrollViews["screen-ledger"]
        XCTAssertTrue(ledger.waitForExistence(timeout: 5), "データ管理が開かない")
        shot("19-ledger")
        shot("04-measure")
        let accept = app.buttons["accept-T1"]
        XCTAssertTrue(accept.waitForExistence(timeout: 8), "台帳へが無い")
        scrollClear(accept, in: ledger)
        XCTAssertGreaterThanOrEqual(accept.frame.height, 56, "台帳へ入れるが小さい")
        accept.tap()
        let saved = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'を台帳に入れました'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 12), "台帳へ入れた文が無い")
        scrollClear(saved, in: ledger)
        shot("08-save")
        let book = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'T1' AND label CONTAINS '下見'")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 5), "台帳の点が座標簿に無い")
        scrollClear(book, in: ledger)
        shot("09-book")
        shot("19-ledger-bottom")
        app.buttons["data-back"].tap()
        XCTAssertTrue(app.scrollViews["screen-measure"].waitForExistence(timeout: 5))

        app.buttons["open-export"].tap()
        let exportData = app.scrollViews["screen-data-export"]
        XCTAssertTrue(exportData.waitForExistence(timeout: 5), "データ書き出しが開かない")
        shot("20-data-export")
        tapClear("basic-export-csv", in: exportData)
        let wrote = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '書きました'")).firstMatch
        XCTAssertTrue(wrote.waitForExistence(timeout: 5), "座標一覧を書き出せない")
        XCTAssertTrue(app.staticTexts["export-where"].waitForExistence(timeout: 5), "保存先が無い")
        scrollClear(wrote, in: exportData)
        shot("10-export")
        tapClear("basic-import", in: exportData)
        confirm("上書きして読む")
        let needsZone = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '系を選んでください'")).firstMatch
        if needsZone.waitForExistence(timeout: 3) {
            let zone = app.buttons["book-zone-6"]
            XCTAssertTrue(zone.waitForExistence(timeout: 3), "系のピッカーが無い")
            zone.tap()
        }
        let imported = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '点を読みました'")).firstMatch
        XCTAssertTrue(imported.waitForExistence(timeout: 5), "座標を読み込めない")
        XCTAssertTrue(imported.label.contains("系"))
        scrollClear(imported, in: exportData)
        shot("11-import")
        tapClear("basic-backup", in: exportData)
        let backup = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'バックアップを作りました'")).firstMatch
        XCTAssertTrue(backup.waitForExistence(timeout: 5), "バックアップを作れない")
        scrollClear(backup, in: exportData)
        shot("12-backup")
        tapClear("basic-restore", in: exportData)
        confirm("戻す")
        let restored = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '1点を戻しました'")).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 5), "バックアップから戻せない")
        scrollClear(restored, in: exportData)
        shot("13-restore")
        shot("20-data-export-bottom")

        openTab("tab-export", showing: "screen-export")
        let exportSheet = app.scrollViews["screen-export"]
        XCTAssertTrue(app.buttons["open-draw"].waitForExistence(timeout: 5), "出すに図面の入口が無い")
        XCTAssertTrue(app.buttons["open-scale"].label.contains("図面の縮尺設定／2点割り付け"))
        XCTAssertFalse(app.buttons["open-scale"].label.contains("次の版"), "縮尺設定が次の版のまま")
        XCTAssertTrue(app.buttons["open-localize"].label.contains("GNSSローカライズ"))
        XCTAssertTrue(app.buttons["open-cad"].label.contains("CAD測設"))
        XCTAssertTrue(app.buttons["open-restore-points"].label.contains("データから点の復元"))
        XCTAssertTrue(app.staticTexts["測設"].exists)
        let exportBadge = app.descendants(matching: .any)["accuracy-badge"]
        XCTAssertTrue(exportBadge.waitForExistence(timeout: 5))
        XCTAssertLessThan(exportBadge.frame.height, 72, "出すの精度帯が1行に収まっていない")
        shot("05-export")
        let draw = app.buttons["open-draw"]
        scrollClear(draw, in: exportSheet)
        draw.tap()
        let drawSheet = app.scrollViews["screen-draw"]
        XCTAssertTrue(drawSheet.waitForExistence(timeout: 5), "図面の読み込みが開かない")
        XCTAssertTrue(app.staticTexts["purpose-draw"].waitForExistence(timeout: 5), "図面の目的が無い")
        shot("21-draw")
        let read = app.buttons["draw-import"]
        scrollClear(read, in: drawSheet)
        read.tap()
        let loaded = app.staticTexts["draw-result"]
        XCTAssertTrue(loaded.waitForExistence(timeout: 5), "図面を置いた結果が無い")
        XCTAssertTrue(loaded.label.contains("済"))
        XCTAssertTrue(loaded.label.contains("図面.png"))
        let nextScale = app.buttons["go-scale"]
        XCTAssertTrue(nextScale.waitForExistence(timeout: 5), "縮尺設定へ進めない")
        scrollClear(nextScale, in: drawSheet)
        shot("21-draw-loaded")
        nextScale.tap()
        let scaleSheet = app.scrollViews["screen-scale"]
        XCTAssertTrue(scaleSheet.waitForExistence(timeout: 5), "縮尺設定が開かない")
        let scaleDrawing = app.textFields["scale-drawing"]
        scrollClear(scaleDrawing, in: scaleSheet)
        replace(scaleDrawing, with: "100")
        let scaleMeasured = app.textFields["scale-measured"]
        replace(scaleMeasured, with: "100.001")
        let scaleRun = app.buttons["scale-run"]
        scrollClear(scaleRun, in: scaleSheet)
        scaleRun.tap()
        let scaleResult = app.staticTexts["scale-result"]
        XCTAssertTrue(scaleResult.waitForExistence(timeout: 5), "縮尺の合否が無い")
        XCTAssertTrue(scaleResult.label.contains("合格"))
        shot("22-scale")
        app.buttons["deliver-back"].tap()
        XCTAssertTrue(drawSheet.waitForExistence(timeout: 5))
        app.buttons["deliver-back"].tap()
        XCTAssertTrue(app.scrollViews["screen-export"].waitForExistence(timeout: 5), "出すトップに戻らない")
        openWork("open-localize", screen: "screen-localize")
        let localizeRun = app.buttons["localize-run"]
        scrollClear(localizeRun, in: app.scrollViews["screen-localize"])
        localizeRun.tap()
        let localizeResult = app.staticTexts["localize-result"]
        XCTAssertTrue(localizeResult.waitForExistence(timeout: 5), "ローカライズの結果が無い")
        XCTAssertTrue(localizeResult.label.contains("3点"))
        shot("23-localize")
        app.buttons["deliver-back"].tap()
        openWork("open-cad", screen: "screen-cad")
        let cadResult = app.staticTexts["cad-result"]
        XCTAssertTrue(cadResult.waitForExistence(timeout: 5), "CAD測設の結果が無い")
        XCTAssertTrue(cadResult.label.contains("点名"))
        shot("24-cad")
        app.buttons["deliver-back"].tap()
        openWork("open-restore-points", screen: "screen-restore-points")
        let restoreRun = app.buttons["restore-run"]
        scrollClear(restoreRun, in: app.scrollViews["screen-restore-points"])
        restoreRun.tap()
        confirm("戻す")
        let restoreResult = app.staticTexts["restore-result"]
        let restoredPoints = expectation(
            for: NSPredicate(format: "label CONTAINS '点を読みました'"),
            evaluatedWith: restoreResult
        )
        XCTAssertEqual(XCTWaiter().wait(for: [restoredPoints], timeout: 8), .completed, "復元の結果が無い")
        shot("25-restore-points")
        app.buttons["deliver-back"].tap()
        let coordinate = app.buttons["open-coordinate"]
        scrollClear(coordinate, in: exportSheet)
        shot("17-deliver")
        coordinate.tap()
        let stakeSheet = app.scrollViews["screen-coordinate"]
        XCTAssertTrue(stakeSheet.waitForExistence(timeout: 5), "座標測設が開かない")
        XCTAssertTrue(app.staticTexts["purpose-stake"].waitForExistence(timeout: 5), "測設の目的が無い")
        shot("26-coordinate")
        let stake = app.buttons["basic-stakeout"]
        let kept = app.buttons["basic-record-stake"]
        scrollClear(kept, in: stakeSheet)
        XCTAssertGreaterThanOrEqual(stake.frame.height, 56, "測設がタイルの高さでない")
        shot("17-deliver-bottom")
        stake.tap()
        openTab("tab-map", showing: "stakeout-guide")
        assertStakeoutOffsetsVisible()
        shot("14-stakeout")
        let mapGCP = app.buttons["basic-gcp"]
        if mapGCP.waitForExistence(timeout: 3), mapGCP.isEnabled {
            mapGCP.tap()
        }
        shot("15-gcp")
        shot("06-map-return")
    }

    private func openWork(_ button: String, screen: String) {
        let control = app.buttons[button]
        scrollClear(control, in: app.scrollViews["screen-export"])
        control.tap()
        XCTAssertTrue(app.scrollViews[screen].waitForExistence(timeout: 5), "\(screen) が開かない")
    }

    private func visitDeliver(_ button: String, screen: String, shotName: String) {
        let control = app.buttons[button]
        scrollClear(control, in: app.scrollViews["screen-export"])
        control.tap()
        XCTAssertTrue(app.scrollViews[screen].waitForExistence(timeout: 5), "\(screen) が開かない")
        XCTAssertTrue(app.staticTexts["次の版"].waitForExistence(timeout: 5), "次の版が無い")
        shot(shotName)
        app.buttons["deliver-back"].tap()
        XCTAssertTrue(app.scrollViews["screen-export"].waitForExistence(timeout: 5), "出すトップに戻らない")
    }

    private func confirm(_ title: String) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "確認が出ない")
        let button = alert.buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "\(title) が無い")
        button.tap()
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
