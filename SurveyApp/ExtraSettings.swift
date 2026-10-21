import SwiftUI
import SurveyCore

/// 測量の画面から離れた設定。既定は全部オフ。
struct ExtraSettingsSheet: View {
    @ObservedObject var field: FieldModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HelpLabel(title: "追加機能", help: .extras)
                    row("押して話す", "オペ画面の無線ボタンと、話しているあいだの矢印。", \.pushToTalk)
                    row("接近警報", "相手の位置、ヒヤリ、音と画面の色。", \.proximity)
                    row("転倒", "加速度での転倒と衝撃。", \.fall)
                    row("SOS", "スライドで知らせるボタン。119は自動で掛けません。", \.sos)
                    row("初動", "SOSか転倒のあと、最寄りと119の読み上げ。", \.firstResponse)
                    row("事故報告", "確定した記録から対外説明のPDF。", \.accidentReport)
                    row("災害", "被災箇所と通行。位置の共有も、このスイッチか接近がオンのときだけ。", \.disaster)
                    row("メッシュ", "見通しの届く端末への中継。オフのあいだは中継しません。", \.mesh)
                    row("統計", "この現場のヒヤリ件数とヒートマップ。", \.stats)
                }
                .padding(16)
            }
            .background(SurveyColor.background)
            .navigationTitle("追加機能")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                        .font(SurveyType(17, .heavy))
                }
            }
        }
        .modifier(SurveyScheme())
    }

    private func row(_ title: String, _ note: String, _ key: WritableKeyPath<ExtraSwitches, Bool>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: binding(key))
                .font(SurveyType(18, .heavy))
                .tint(SurveyColor.amber)
            Text(note)
                .font(SurveyType(14, .semibold))
                .foregroundStyle(SurveyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func binding(_ key: WritableKeyPath<ExtraSwitches, Bool>) -> Binding<Bool> {
        Binding(
            get: { field.extras[keyPath: key] },
            set: { field.setExtra(key, $0) }
        )
    }
}

