import Foundation

/// 初心者は確認してから残す。慣れたら、一回で残す。
public enum SkillLevel: String, Codable, Sendable, Equatable {
    case beginner
    case skilled

    public var title: String {
        switch self {
        case .beginner: return "初心者"
        case .skilled: return "慣れたら"
        }
    }
}

public enum SurveyCommand: String, Codable, Sendable, Equatable, CaseIterable {
    case capture
    case confirm
    case cancel
    case nextPoint
    case controlPoint
    case repeatLast
    case switchWork
    case exportFile

    public var title: String {
        switch self {
        case .capture: return "現在地を残す"
        case .confirm: return "この点を確定"
        case .cancel: return "やめる"
        case .nextPoint: return "次の点へ"
        case .controlPoint: return "基準点を記録"
        case .repeatLast: return "もう一度"
        case .switchWork: return "作業を変える"
        case .exportFile: return "ファイルを出す"
        }
    }
}

public enum CapturePhase: String, Sendable, Equatable {
    case idle
    case review
    case saved
}

public enum OperationGoal: String, CaseIterable, Sendable {
    case confirmObservation
    case nextPoint
    case recordControl
    case repeatLast
    case switchWork
    case exportFile
}

public enum OperationInput: Equatable, Sendable {
    case tap(SurveyCommand)
    case longPress
    case swipe
    case volumeUp
    case volumeDown
    case actionButton
    case keyboard(key: String, commandKey: Bool)

    public var isScreenTap: Bool {
        if case .tap = self { return true }
        return false
    }
}

/// 観測を確定したとき。振動と音の両方を返す。
public struct ConfirmFeedback: Equatable, Sendable {
    public var haptic: Bool
    public var sound: Bool

    public static let confirmed = ConfirmFeedback(haptic: true, sound: true)
}

public enum OperationEffect: Equatable, Sendable {
    case none
    case review(SurveyCommand)
    case saveObservation(ConfirmFeedback)
    case saveControl(ConfirmFeedback)
    case openWork
    case openExport
    case idle
}

public struct ToolShelf: Codable, Equatable, Sendable {
    public static let reorderable: [SurveyCommand] = [.capture, .repeatLast, .controlPoint, .switchWork, .exportFile]
    public var items: [SurveyCommand]

    public init(items: [SurveyCommand] = ToolShelf.reorderable) {
        var seen = Set<SurveyCommand>()
        var ordered: [SurveyCommand] = []
        for item in items where Self.reorderable.contains(item) && seen.insert(item).inserted {
            ordered.append(item)
        }
        for item in Self.reorderable where seen.insert(item).inserted {
            ordered.append(item)
        }
        self.items = ordered
    }

    /// `List` の onMove。並びだけを変え、項目は消さない。
    public mutating func move(from source: IndexSet, to destination: Int) {
        let moving = source.sorted().compactMap { items.indices.contains($0) ? items[$0] : nil }
        guard !moving.isEmpty else { return }
        var result = items
        for index in source.sorted(by: >) where result.indices.contains(index) {
            result.remove(at: index)
        }
        let offset = source.filter { $0 < destination }.count
        let index = min(max(0, destination - offset), result.count)
        result.insert(contentsOf: moving, at: index)
        items = ToolShelf(items: result).items
    }
}

public struct OperationMemory: Equatable, Sendable {
    public private(set) var last: SurveyCommand?

    public init(last: SurveyCommand? = nil) {
        self.last = last
    }

    public mutating func note(_ command: SurveyCommand) {
        switch command {
        case .capture, .controlPoint, .switchWork, .exportFile:
            last = command
        default:
            break
        }
    }
}

public struct OperationPreferences: Codable, Equatable, Sendable {
    public static let key = "survey.operation"
    public var level: SkillLevel
    public var items: [SurveyCommand]
    public var showsDetail: Bool
    public var eyesFree: Bool

    public init(level: SkillLevel, items: [SurveyCommand], showsDetail: Bool, eyesFree: Bool) {
        self.level = level
        self.items = items
        self.showsDetail = showsDetail
        self.eyesFree = eyesFree
    }
}

/// アクションボタンが、画面の起動前に確定を残す。
public enum OperationPending {
    public static let key = "survey.operation.pending"

    public static func arm(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key)
    }

    public static func consume(_ defaults: UserDefaults = .standard) -> Bool {
        guard defaults.bool(forKey: key) else { return false }
        defaults.set(false, forKey: key)
        return true
    }
}

public struct OperationDesk: Equatable, Sendable {
    public static let tapLimit = 3

    public var level: SkillLevel
    public var phase: CapturePhase
    public var pending: SurveyCommand?
    public var shelf: ToolShelf
    public var memory: OperationMemory
    public var showsDetail: Bool
    public var controlOpen: Bool
    public var eyesFree: Bool

    public init(
        level: SkillLevel = .beginner,
        phase: CapturePhase = .idle,
        pending: SurveyCommand? = nil,
        shelf: ToolShelf = ToolShelf(),
        memory: OperationMemory = OperationMemory(),
        showsDetail: Bool = false,
        controlOpen: Bool = false,
        eyesFree: Bool = true
    ) {
        self.level = level
        self.phase = phase
        self.pending = pending
        self.shelf = shelf
        self.memory = memory
        self.showsDetail = showsDetail
        self.controlOpen = controlOpen
        self.eyesFree = eyesFree
    }

    public var showsAdvanced: Bool { level == .skilled || showsDetail }

    public var visibleCommands: [SurveyCommand] {
        switch level {
        case .beginner:
            switch phase {
            case .idle: return [.capture]
            case .review: return [.confirm, .cancel]
            case .saved: return [.nextPoint, .repeatLast]
            }
        case .skilled:
            return shelf.items
        }
    }

    public var coach: String {
        switch (level, phase) {
        case (.beginner, .idle):
            return "大きなボタンで、今の点を残します。中身を見てから確定します。"
        case (.beginner, .review):
            return "よければ確定します。音と振動で知らせます。やめると残しません。"
        case (.beginner, .saved):
            return "残りました。次の点へ進むと、次の点名で続きです。"
        case (.skilled, _):
            return "長押し、スワイプ、音量ボタン、アクションボタンで確定します。⌘Return で残し、⌘R でもう一度です。"
        }
    }

    public func preview(_ input: OperationInput) -> OperationEffect {
        guard let command = resolved(input) else { return .none }
        return Self.effect(command, level: level, phase: phase, pending: pending)
    }

    public mutating func commit(_ effect: OperationEffect) {
        switch effect {
        case .none:
            break
        case .review(let command):
            pending = command
            phase = .review
        case .saveObservation:
            memory.note(.capture)
            pending = nil
            phase = level == .beginner ? .saved : .idle
        case .saveControl:
            memory.note(.controlPoint)
            pending = nil
            phase = level == .beginner ? .saved : .idle
        case .openWork:
            memory.note(.switchWork)
            pending = nil
            phase = .idle
        case .openExport:
            memory.note(.exportFile)
            pending = nil
            phase = .idle
        case .idle:
            pending = nil
            phase = .idle
        }
    }

    /// 保存できた前提で進める。失敗した保存は呼ばない。
    @discardableResult
    public mutating func receive(_ input: OperationInput) -> OperationEffect {
        let effect = preview(input)
        commit(effect)
        return effect
    }

    public mutating func toggleDetail() {
        showsDetail.toggle()
    }

    public mutating func toggleControl() {
        controlOpen.toggle()
    }

    public func save(to defaults: UserDefaults = .standard) {
        let prefs = OperationPreferences(level: level, items: shelf.items, showsDetail: showsDetail, eyesFree: eyesFree)
        guard let data = try? JSONEncoder().encode(prefs) else { return }
        defaults.set(data, forKey: OperationPreferences.key)
    }

    public static func load(from defaults: UserDefaults = .standard) -> OperationDesk {
        guard let data = defaults.data(forKey: OperationPreferences.key),
              let prefs = try? JSONDecoder().decode(OperationPreferences.self, from: data) else {
            return OperationDesk()
        }
        return OperationDesk(
            level: prefs.level,
            shelf: ToolShelf(items: prefs.items),
            showsDetail: prefs.showsDetail,
            eyesFree: prefs.eyesFree
        )
    }

    public static func shouldCue(_ effect: OperationEffect) -> Bool {
        switch effect {
        case .saveObservation(let feedback), .saveControl(let feedback):
            return feedback.haptic && feedback.sound
        default:
            return false
        }
    }

    /// 画面をタップする回数。音量とアクションボタンは 0。
    public static func screenTaps(_ goal: OperationGoal, level: SkillLevel, eyesFree: Bool = false) -> Int {
        if eyesFree, level == .skilled, goal == .confirmObservation || goal == .nextPoint {
            return 0
        }
        let taps = demonstration(goal, level: level).filter(\.isScreenTap).count
        switch (goal, level) {
        case (.recordControl, .beginner):
            return taps + 1
        case (.exportFile, _):
            return taps + 1
        default:
            return taps
        }
    }

    /// 状態機械を通る操作。基準点を開くタップと、書き出しの形式ボタンは数に含めていない。
    public static func demonstration(_ goal: OperationGoal, level: SkillLevel) -> [OperationInput] {
        if level == .skilled {
            switch goal {
            case .confirmObservation, .nextPoint: return [.tap(.capture)]
            case .recordControl: return [.tap(.controlPoint)]
            case .repeatLast: return [.tap(.repeatLast)]
            case .switchWork: return [.tap(.switchWork)]
            case .exportFile: return [.tap(.exportFile)]
            }
        }
        switch goal {
        case .confirmObservation: return [.tap(.capture), .tap(.confirm)]
        case .nextPoint: return [.tap(.capture), .tap(.confirm), .tap(.nextPoint)]
        case .recordControl: return [.tap(.controlPoint), .tap(.confirm)]
        case .repeatLast: return [.tap(.repeatLast), .tap(.confirm)]
        case .switchWork: return [.tap(.switchWork)]
        case .exportFile: return [.tap(.exportFile)]
        }
    }

    private func resolved(_ input: OperationInput) -> SurveyCommand? {
        switch input {
        case .tap(let command):
            return command == .repeatLast ? memory.last : command
        case .longPress, .swipe:
            guard level == .skilled, phase != .review else { return nil }
            return .capture
        case .volumeUp, .volumeDown, .actionButton:
            guard level == .skilled, eyesFree else { return nil }
            return phase == .review ? .confirm : .capture
        case .keyboard(let key, let commandKey):
            return Self.keyboard(key, commandKey: commandKey, level: level, phase: phase, last: memory.last)
        }
    }

    private static func keyboard(_ key: String, commandKey: Bool, level: SkillLevel, phase: CapturePhase, last: SurveyCommand?) -> SurveyCommand? {
        let name = key.lowercased()
        if commandKey {
            switch name {
            case "r": return last
            case "b": return .controlPoint
            case "e": return .exportFile
            case "n": return .nextPoint
            case "y": return .switchWork
            case "return": return phase == .review ? .confirm : .capture
            default: return nil
            }
        }
        if name == "escape" { return .cancel }
        return nil
    }

    private static func effect(_ command: SurveyCommand, level: SkillLevel, phase: CapturePhase, pending: SurveyCommand?) -> OperationEffect {
        switch command {
        case .capture:
            if level == .skilled { return .saveObservation(.confirmed) }
            if phase == .review { return .none }
            return .review(.capture)
        case .controlPoint:
            if level == .skilled { return .saveControl(.confirmed) }
            if phase == .review { return .none }
            return .review(.controlPoint)
        case .confirm:
            if phase == .review {
                return pending == .controlPoint ? .saveControl(.confirmed) : .saveObservation(.confirmed)
            }
            if level == .skilled { return .saveObservation(.confirmed) }
            return .none
        case .cancel:
            return phase == .review ? .idle : .none
        case .nextPoint:
            return phase == .saved ? .idle : .none
        case .switchWork:
            return .openWork
        case .exportFile:
            return .openExport
        case .repeatLast:
            return .none
        }
    }
}
