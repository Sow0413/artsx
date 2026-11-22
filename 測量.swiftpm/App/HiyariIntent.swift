import Foundation

#if !SURVEY_PLAYGROUND && canImport(AppIntents)
import AppIntents

/// 「ヒヤリ」で記録を始める。Siri からの起動は未確認。
struct HiyariIntent: AppIntent {
    static var title: LocalizedStringResource = "ヒヤリ"
    static var description = IntentDescription("今の位置でヒヤリハットの記録を始めます。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { HiyariHook.fire() }
        return .result()
    }
}

struct SurveyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
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
