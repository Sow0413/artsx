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
#endif
