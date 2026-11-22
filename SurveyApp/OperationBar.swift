import SwiftUI
import SurveyCore

struct OperationBar: View {
    @ObservedObject var field: FieldModel
    var showsSkill: Bool
    var compact: Bool = false
    var saveIdentifier: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsSkill {
                skillSwitch
            }
            Text(field.operation.coach)
                .font(SurveyType(15, .semibold))
                .foregroundStyle(SurveyColor.muted)
                .lineLimit(compact ? 2 : nil as Int?)
                .fixedSize(horizontal: false, vertical: true)
            if field.operation.phase == .review {
                Text(reviewLine)
                    .font(SurveyType(20, .heavy))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let name = field.nextPointName {
                Text("次の点名は \(name)")
                    .font(SurveyType(16, .heavy))
            } else {
                Text("頭文字は半角アルファベットだけにしてください。")
                    .font(SurveyType(16, .heavy))
            }
            if field.operation.level == .beginner, showsSkill || field.nextPointName == nil {
                TextField("点名の頭（T）", text: prefixBinding)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            if compact {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(field.operation.visibleCommands, id: \.self) { command in
                            commandButton(command)
                        }
                    }
                }
            } else {
                ForEach(field.operation.visibleCommands, id: \.self) { command in
                    commandButton(command)
                }
            }
            if showsSkill, field.operation.level == .beginner, field.operation.phase == .idle {
                Button(field.operation.controlOpen ? "基準点を閉じる" : "基準点を開く") {
                    field.toggleControlSection()
                }
                .font(SurveyType(18, .heavy))
                .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                .background(SurveyColor.card)
                .foregroundStyle(SurveyColor.text)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(stroke)
                Button(field.operation.showsDetail ? "説明を閉じる" : "くわしく") {
                    field.toggleOperationDetail()
                }
                .font(SurveyType(16, .heavy))
                .foregroundStyle(SurveyColor.muted)
            }
            if showsSkill, field.operation.level == .skilled {
                Toggle("音量とアクションボタンで確定", isOn: eyesFreeBinding)
                    .font(SurveyType(16, .heavy))
                    .tint(SurveyColor.blue)
                Button("よく使う機能の順番") {
                    field.showsToolOrder = true
                }
                .font(SurveyType(16, .heavy))
                .foregroundStyle(SurveyColor.text)
            }
            if !showsSkill, let message = field.captureMessage {
                Text(message)
                    .font(SurveyType(15, .heavy))
                    .foregroundStyle(SurveyColor.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var skillSwitch: some View {
        HStack(spacing: 8) {
            skillButton(.beginner)
            skillButton(.skilled)
        }
    }

    private func skillButton(_ level: SkillLevel) -> some View {
        let selected = field.operation.level == level
        return Button(level.title) {
            field.setSkill(level)
        }
        .font(SurveyType(18, .heavy))
        .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
        .background(selected ? SurveyColor.blue : SurveyColor.card)
        .foregroundStyle(selected ? SurveyColor.onAccent : SurveyColor.text)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(stroke)
    }

    @ViewBuilder
    private func commandButton(_ command: SurveyCommand) -> some View {
        if command == .capture {
            CaptureControl(title: command.title, identifier: saveIdentifier) { input in
                field.receiveOperation(input)
            }
        } else {
            Button {
                field.receiveOperation(.tap(command))
            } label: {
                Text(command.title)
                    .font(SurveyType(18, .heavy))
                    .frame(minWidth: 160, maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                    .background(filled(command) ? SurveyColor.blue : SurveyColor.card)
                    .foregroundStyle(filled(command) ? SurveyColor.onAccent : SurveyColor.text)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(stroke)
            }
            .buttonStyle(.plain)
        }
    }

    private func filled(_ command: SurveyCommand) -> Bool {
        switch command {
        case .capture, .confirm, .controlPoint, .repeatLast: return true
        default: return false
        }
    }

    private var stroke: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(SurveyColor.line, lineWidth: SurveyColor.stroke)
    }

    private var reviewLine: String {
        let name = field.nextPointName ?? "点名未設定"
        let work = field.operation.pending == .controlPoint ? "基準点" : field.workCatalog.selected.title
        return "\(name)を、\(work)として残します。"
    }

    private var prefixBinding: Binding<String> {
        Binding(get: { field.pointPrefix }, set: { field.setPointPrefix($0) })
    }

    private var eyesFreeBinding: Binding<Bool> {
        Binding(get: { field.operation.eyesFree }, set: { _ in field.toggleEyesFree() })
    }
}

/// タップは確認、長押しと横スワイプは慣れたら即確定。
private struct CaptureControl: View {
    var title: String
    var identifier: String? = nil
    var onInput: (OperationInput) -> Void
    @State private var suppressTap = false

    var body: some View {
            Text(title)
            .font(SurveyType(18, .heavy))
            .frame(minWidth: 160, maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
            .background(SurveyColor.blue)
            .foregroundStyle(SurveyColor.onAccent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(SurveyColor.line, lineWidth: SurveyColor.stroke)
            )
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.45) {
                suppressTap = true
                onInput(.longPress)
            } onPressingChanged: { pressing in
                guard !pressing else { return }
                if suppressTap {
                    suppressTap = false
                    return
                }
                onInput(.tap(.capture))
            }
            .gesture(
                DragGesture(minimumDistance: 48)
                    .onEnded { value in
                        guard abs(value.translation.width) > 64, abs(value.translation.width) > abs(value.translation.height) else { return }
                        suppressTap = true
                        onInput(.swipe)
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(title)
            .accessibilityIdentifier(identifier ?? "save-point")
            .accessibilityHint("長押し、または横にスワイプすると、慣れたらすぐ残します。")
    }
}

struct ToolOrderSheet: View {
    @ObservedObject var field: FieldModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(field.operation.shelf.items, id: \.self) { item in
                    Text(item.title)
                        .font(SurveyType(18, .heavy))
                }
                .onMove { field.moveTools(from: $0, to: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .background(SurveyColor.background)
            .navigationTitle("よく使う機能")
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
}

struct OperationKeyCommands: View {
    @ObservedObject var field: FieldModel

    var body: some View {
        ZStack {
            key("現在地を残す", shortcut: .return, modifiers: .command) {
                field.receiveOperation(.keyboard(key: "return", commandKey: true))
            }
            key("もう一度", shortcut: "r", modifiers: .command) {
                field.receiveOperation(.keyboard(key: "r", commandKey: true))
            }
            key("基準点を記録", shortcut: "b", modifiers: .command) {
                field.receiveOperation(.keyboard(key: "b", commandKey: true))
            }
            key("ファイルを出す", shortcut: "e", modifiers: .command) {
                field.receiveOperation(.keyboard(key: "e", commandKey: true))
            }
            key("次の点へ", shortcut: "n", modifiers: .command) {
                field.receiveOperation(.keyboard(key: "n", commandKey: true))
            }
            key("作業を変える", shortcut: "y", modifiers: .command) {
                field.receiveOperation(.keyboard(key: "y", commandKey: true))
            }
        }
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func key(_ title: String, shortcut: KeyEquivalent, modifiers: EventModifiers, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .keyboardShortcut(shortcut, modifiers: modifiers)
            .opacity(0)
    }
}
