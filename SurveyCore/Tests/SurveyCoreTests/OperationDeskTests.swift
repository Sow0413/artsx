import XCTest
@testable import SurveyCore

final class OperationDeskTests: XCTestCase {
    func testMainActionsStayWithinThreeTaps() {
        for goal in OperationGoal.allCases {
            for level in [SkillLevel.beginner, SkillLevel.skilled] {
                let taps = OperationDesk.screenTaps(goal, level: level)
                print("SURVEY OPS \(goal.rawValue) \(level.rawValue) \(taps)タップ")
                XCTAssertLessThanOrEqual(taps, OperationDesk.tapLimit, "\(goal) \(level)")
                XCTAssertGreaterThan(taps, 0)
            }
        }
        XCTAssertEqual(OperationDesk.screenTaps(.confirmObservation, level: .beginner), 2)
        XCTAssertEqual(OperationDesk.screenTaps(.nextPoint, level: .beginner), 3)
        XCTAssertEqual(OperationDesk.screenTaps(.recordControl, level: .beginner), 3)
        XCTAssertEqual(OperationDesk.screenTaps(.confirmObservation, level: .skilled), 1)
        XCTAssertEqual(OperationDesk.screenTaps(.exportFile, level: .skilled), 2)
        XCTAssertEqual(OperationDesk.screenTaps(.confirmObservation, level: .skilled, eyesFree: true), 0)
        XCTAssertEqual(OperationDesk.screenTaps(.nextPoint, level: .skilled, eyesFree: true), 0)
    }

    func testBeginnerConfirmsBeforeSavingAndThenAdvances() {
        var desk = OperationDesk(level: .beginner)
        XCTAssertEqual(desk.visibleCommands, [.capture])
        XCTAssertEqual(desk.receive(.tap(.capture)), .review(.capture))
        XCTAssertEqual(desk.phase, .review)
        XCTAssertEqual(desk.visibleCommands, [.confirm, .cancel])
        XCTAssertEqual(desk.receive(.tap(.confirm)), .saveObservation(.confirmed))
        XCTAssertEqual(desk.phase, .saved)
        XCTAssertTrue(OperationDesk.shouldCue(.saveObservation(.confirmed)))
        XCTAssertEqual(desk.memory.last, .capture)
        XCTAssertEqual(desk.receive(.tap(.nextPoint)), .idle)
        XCTAssertEqual(desk.phase, .idle)
    }

    func testBeginnerCancelDoesNotSave() {
        var desk = OperationDesk(level: .beginner)
        _ = desk.receive(.tap(.capture))
        XCTAssertEqual(desk.receive(.tap(.cancel)), .idle)
        XCTAssertNil(desk.memory.last)
        XCTAssertFalse(OperationDesk.shouldCue(.idle))
    }

    func testBeginnerHardwareDoesNotSave() {
        var desk = OperationDesk(level: .beginner)
        for input in [OperationInput.longPress, .swipe, .volumeUp, .volumeDown, .actionButton] {
            XCTAssertEqual(desk.receive(input), .none, "\(input)")
            XCTAssertEqual(desk.phase, .idle)
        }
    }

    func testSkilledShortcutsSaveAndStayReadyForTheNextPoint() {
        let inputs: [OperationInput] = [.tap(.capture), .longPress, .swipe, .volumeUp, .volumeDown, .actionButton]
        for input in inputs {
            var desk = OperationDesk(level: .skilled)
            let effect = desk.receive(input)
            XCTAssertEqual(effect, .saveObservation(.confirmed), "\(input)")
            XCTAssertTrue(OperationDesk.shouldCue(effect))
            XCTAssertEqual(desk.phase, .idle)
            XCTAssertEqual(desk.memory.last, .capture)
        }
    }

    func testEyesFreeCanBeTurnedOff() {
        var desk = OperationDesk(level: .skilled, eyesFree: false)
        XCTAssertEqual(desk.receive(.volumeUp), .none)
        XCTAssertEqual(desk.receive(.actionButton), .none)
        XCTAssertEqual(desk.receive(.longPress), .saveObservation(.confirmed))
    }

    func testRepeatUsesTheLastSuccessfulAction() {
        var skilled = OperationDesk(level: .skilled)
        XCTAssertEqual(skilled.receive(.tap(.repeatLast)), .none)
        _ = skilled.receive(.tap(.controlPoint))
        XCTAssertEqual(skilled.receive(.tap(.repeatLast)), .saveControl(.confirmed))
        XCTAssertEqual(skilled.receive(.keyboard(key: "R", commandKey: true)), .saveControl(.confirmed))

        var beginner = OperationDesk(level: .beginner)
        _ = beginner.receive(.tap(.capture))
        _ = beginner.receive(.tap(.confirm))
        XCTAssertEqual(beginner.receive(.tap(.repeatLast)), .review(.capture))
        XCTAssertEqual(beginner.receive(.tap(.confirm)), .saveObservation(.confirmed))
    }

    func testControlReviewAndKeyboard() {
        var desk = OperationDesk(level: .beginner)
        XCTAssertEqual(desk.receive(.tap(.controlPoint)), .review(.controlPoint))
        XCTAssertEqual(desk.receive(.keyboard(key: "return", commandKey: true)), .saveControl(.confirmed))
        XCTAssertEqual(desk.phase, .saved)

        var skilled = OperationDesk(level: .skilled)
        XCTAssertEqual(skilled.receive(.keyboard(key: "b", commandKey: true)), .saveControl(.confirmed))
        XCTAssertEqual(skilled.receive(.keyboard(key: "e", commandKey: true)), .openExport)
        XCTAssertEqual(skilled.tabAfterExport, .idle)
        XCTAssertEqual(skilled.receive(.keyboard(key: "y", commandKey: true)), .openWork)
        XCTAssertEqual(skilled.receive(.keyboard(key: "escape", commandKey: false)), .none)
    }

    func testToolbarKeepsEveryToolAndRemembersOrder() {
        var shelf = ToolShelf(items: [.exportFile, .capture, .capture])
        XCTAssertEqual(shelf.items.first, .exportFile)
        XCTAssertEqual(Set(shelf.items), Set(ToolShelf.reorderable))
        shelf.move(from: IndexSet(integer: 0), to: 2)
        XCTAssertEqual(shelf.items.count, ToolShelf.reorderable.count)
        XCTAssertEqual(shelf.items[0], .capture)

        let beginner = OperationDesk(level: .beginner, shelf: shelf)
        XCTAssertEqual(beginner.visibleCommands, [.capture])
        let skilled = OperationDesk(level: .skilled, shelf: shelf)
        XCTAssertEqual(skilled.visibleCommands, shelf.items)
    }

    func testPreferencesAndPendingConfirmRoundTrip() {
        let name = "operation-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        var desk = OperationDesk(level: .skilled, showsDetail: true, eyesFree: false)
        desk.shelf.move(from: IndexSet(integer: 4), to: 0)
        desk.save(to: defaults)
        let loaded = OperationDesk.load(from: defaults)
        XCTAssertEqual(loaded.level, .skilled)
        XCTAssertEqual(loaded.shelf.items, desk.shelf.items)
        XCTAssertTrue(loaded.showsDetail)
        XCTAssertFalse(loaded.eyesFree)
        XCTAssertEqual(loaded.phase, .idle)

        XCTAssertFalse(OperationPending.consume(defaults))
        OperationPending.arm(defaults)
        XCTAssertTrue(OperationPending.consume(defaults))
        XCTAssertFalse(OperationPending.consume(defaults))
    }

    func testLabelsAndCoachArePresent() {
        var seen = Set<String>()
        for command in SurveyCommand.allCases {
            XCTAssertFalse(command.title.isEmpty)
            XCTAssertTrue(seen.insert(command.title).inserted)
        }
        let desk = OperationDesk()
        XCTAssertFalse(desk.coach.isEmpty)
        XCTAssertEqual(SkillLevel.beginner.title, "初心者")
        XCTAssertEqual(SkillLevel.skilled.title, "慣れたら")
    }
}

private extension OperationDesk {
    var tabAfterExport: CapturePhase { phase }
}
