import Foundation
import SurveyCore

#if !SURVEY_PLAYGROUND && canImport(AppIntents)
import AppIntents

/// アクションボタンに割り当てる。画面を見ずに、今の点を残す。実機は未確認。
struct ConfirmObservationIntent: AppIntent {
    static var title: LocalizedStringResource = "観測を確定"
    static var description = IntentDescription("画面を見ずに、今の点を残します。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        OperationPending.arm()
        await MainActor.run {
            NotificationCenter.default.post(name: .surveyConfirmObservation, object: nil)
        }
        return .result()
    }
}

struct SurveyShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ConfirmObservationIntent(),
            phrases: ["\(.applicationName)で観測を確定"],
            shortTitle: "観測を確定",
            systemImageName: "mappin"
        )
        AppShortcut(
            intent: HiyariIntent(),
            phrases: [
                "\(.applicationName)でヒヤリ",
                "ヒヤリを\(.applicationName)に残して"
            ],
            shortTitle: "ヒヤリ",
            systemImageName: "exclamationmark.triangle"
        )
    }
}
#endif
