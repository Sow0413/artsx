import SwiftUI
import UIKit
import SurveyCore

enum SurveyPaletteStore {
    static var outdoor = false
}

enum SurveyColor {
    @discardableResult
    static func install(_ outdoor: Bool) -> Bool {
        SurveyPaletteStore.outdoor = outdoor
        return outdoor
    }

    static var outdoor: Bool { SurveyPaletteStore.outdoor }
    static var stroke: CGFloat { outdoor ? OutdoorContrast.strokePoints : 1 }

    static var background: Color { outdoor ? color(OutdoorContrast.white) : Color(red: 11 / 255, green: 13 / 255, blue: 16 / 255) }
    static var card: Color { outdoor ? color(OutdoorContrast.white) : Color(red: 23 / 255, green: 26 / 255, blue: 31 / 255) }
    static var pressed: Color { outdoor ? Color(red: 230 / 255, green: 230 / 255, blue: 230 / 255) : Color(red: 44 / 255, green: 49 / 255, blue: 56 / 255) }
    static var text: Color { outdoor ? color(OutdoorContrast.black) : Color(red: 245 / 255, green: 247 / 255, blue: 250 / 255) }
    static var onAccent: Color { outdoor ? color(OutdoorContrast.white) : Color(red: 245 / 255, green: 247 / 255, blue: 250 / 255) }
    static var muted: Color { outdoor ? color(OutdoorContrast.muted) : Color(red: 154 / 255, green: 163 / 255, blue: 173 / 255) }
    static var line: Color { outdoor ? color(OutdoorContrast.black) : Color(red: 42 / 255, green: 47 / 255, blue: 55 / 255) }
    static var amber: Color { outdoor ? color(OutdoorContrast.black) : Color(red: 1, green: 176 / 255, blue: 32 / 255) }
    static var amberBackground: Color { outdoor ? color(OutdoorContrast.yellow) : Color(red: 42 / 255, green: 31 / 255, blue: 5 / 255) }
    static var yellow: Color { outdoor ? color(OutdoorContrast.black) : Color(red: 245 / 255, green: 217 / 255, blue: 10 / 255) }
    static var yellowBackground: Color { outdoor ? color(OutdoorContrast.yellow) : Color(red: 42 / 255, green: 36 / 255, blue: 5 / 255) }
    static var red: Color { outdoor ? color(OutdoorContrast.red) : Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255) }
    static var redBackground: Color { outdoor ? color(OutdoorContrast.red) : Color(red: 42 / 255, green: 12 / 255, blue: 12 / 255) }
    static var green: Color { outdoor ? color(OutdoorContrast.green) : Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255) }
    static var greenBackground: Color { outdoor ? color(OutdoorContrast.green) : Color(red: 6 / 255, green: 35 / 255, blue: 18 / 255) }
    static var grey: Color { outdoor ? color(OutdoorContrast.grey) : Color(red: 138 / 255, green: 146 / 255, blue: 156 / 255) }
    static var greyBackground: Color { outdoor ? color(OutdoorContrast.white) : Color(red: 28 / 255, green: 31 / 255, blue: 36 / 255) }
    static var blue: Color { outdoor ? color(OutdoorContrast.blue) : Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255) }
    static var bar: Color { outdoor ? color(OutdoorContrast.white) : Color(red: 16 / 255, green: 19 / 255, blue: 23 / 255) }
    static var mapBackdrop: Color { outdoor ? color(OutdoorContrast.white) : Color(red: 0.91, green: 0.94, blue: 0.89) }

    static func color(_ value: ContrastColor) -> Color {
        Color(red: value.red, green: value.green, blue: value.blue)
    }
}

/// 固定サイズを、Dynamic Type の文字スタイルに載せる。
func SurveyType(_ points: CGFloat, _ weight: Font.Weight = .semibold, mono: Bool = false) -> Font {
    let style: Font.TextStyle
    switch points {
    case ..<12: style = .caption2
    case ..<14: style = .caption
    case ..<16: style = .footnote
    case ..<18: style = .subheadline
    case ..<20: style = .body
    case ..<24: style = .title3
    case ..<28: style = .title2
    case ..<34: style = .title
    default: style = .largeTitle
    }
    return .system(style, design: mono ? .monospaced : .default, weight: weight)
}

final class SurveyAppearance: ObservableObject {
    private static let key = "survey.outdoor"

    @Published var choice: OutdoorChoice {
        didSet { UserDefaults.standard.set(choice.rawValue, forKey: Self.key) }
    }

    @Published private(set) var brightness: Double

    var outdoor: Bool { OutdoorContrast.prefersOutdoor(choice, brightness: brightness) }

    var label: String {
        switch choice {
        case .automatic: return outdoor ? "表示 自動・屋外" : "表示 自動・屋内"
        case .outdoor: return "表示 屋外"
        case .indoor: return "表示 屋内"
        }
    }

    private var brightnessObserver: NSObjectProtocol?

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.key), let stored = OutdoorChoice(rawValue: raw) {
            choice = stored
        } else {
            choice = .automatic
        }
        brightness = Double(UIScreen.main.brightness)
        brightnessObserver = NotificationCenter.default.addObserver(
            forName: UIScreen.brightnessDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.brightness = Double(UIScreen.main.brightness)
        }
    }

    deinit {
        if let brightnessObserver {
            NotificationCenter.default.removeObserver(brightnessObserver)
        }
    }

    func cycle() {
        switch choice {
        case .automatic: choice = .outdoor
        case .outdoor: choice = .indoor
        case .indoor: choice = .automatic
        }
    }
}

enum SurveyUIColor {
    static var amber: UIColor { ui(SurveyColor.outdoor ? OutdoorContrast.black : ContrastColor(red: 1, green: 176 / 255, blue: 32 / 255)) }
    static var yellow: UIColor { ui(SurveyColor.outdoor ? OutdoorContrast.black : ContrastColor(red: 245 / 255, green: 217 / 255, blue: 10 / 255)) }
    static var red: UIColor { ui(SurveyColor.outdoor ? OutdoorContrast.red : ContrastColor(red: 239 / 255, green: 68 / 255, blue: 68 / 255)) }
    static var green: UIColor { ui(SurveyColor.outdoor ? OutdoorContrast.green : ContrastColor(red: 34 / 255, green: 197 / 255, blue: 94 / 255)) }
    static var grey: UIColor { ui(SurveyColor.outdoor ? OutdoorContrast.grey : ContrastColor(red: 138 / 255, green: 146 / 255, blue: 156 / 255)) }
    static var blue: UIColor { ui(SurveyColor.outdoor ? OutdoorContrast.blue : ContrastColor(red: 59 / 255, green: 130 / 255, blue: 246 / 255)) }
    static var mapBackdrop: UIColor { ui(SurveyColor.outdoor ? OutdoorContrast.white : ContrastColor(red: 0.91, green: 0.94, blue: 0.89)) }
    static var ink: UIColor { ui(SurveyColor.outdoor ? OutdoorContrast.black : ContrastColor(red: 1, green: 176 / 255, blue: 32 / 255)) }

    private static func ui(_ color: ContrastColor) -> UIColor {
        UIColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
    }
}

extension AccuracyTone {
    var tint: Color {
        switch self {
        case .grey: return SurveyColor.grey
        case .amber: return SurveyColor.outdoor ? SurveyColor.text : SurveyColor.amber
        case .yellow: return SurveyColor.outdoor ? SurveyColor.text : SurveyColor.yellow
        case .red: return SurveyColor.red
        case .green: return SurveyColor.green
        }
    }

    /// 色の点。屋外の黄は文字にせず、点だけ原色にする。
    var mark: Color {
        if SurveyColor.outdoor {
            switch self {
            case .grey: return SurveyColor.grey
            case .amber, .yellow: return SurveyColor.color(OutdoorContrast.yellow)
            case .red: return SurveyColor.color(OutdoorContrast.red)
            case .green: return SurveyColor.color(OutdoorContrast.green)
            }
        }
        return tint
    }

    var badgeBackground: Color {
        if SurveyColor.outdoor {
            switch self {
            case .amber, .yellow: return SurveyColor.amberBackground
            case .red: return SurveyColor.color(OutdoorContrast.white)
            case .green: return SurveyColor.color(OutdoorContrast.white)
            case .grey: return SurveyColor.color(OutdoorContrast.white)
            }
        }
        switch self {
        case .grey: return SurveyColor.greyBackground
        case .amber: return SurveyColor.amberBackground
        case .yellow: return SurveyColor.yellowBackground
        case .red: return SurveyColor.redBackground
        case .green: return SurveyColor.greenBackground
        }
    }

    var circle: UIColor {
        switch self {
        case .grey: return SurveyUIColor.grey
        case .amber: return SurveyUIColor.amber
        case .yellow: return SurveyUIColor.yellow
        case .red: return SurveyUIColor.red
        case .green: return SurveyUIColor.green
        }
    }
}

private struct SurveyOutdoorKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var surveyOutdoor: Bool {
        get { self[SurveyOutdoorKey.self] }
        set { self[SurveyOutdoorKey.self] = newValue }
    }
}

struct SurveyScheme: ViewModifier {
    @Environment(\.surveyOutdoor) private var outdoor

    func body(content: Content) -> some View {
        let _ = SurveyColor.install(outdoor)
        content.preferredColorScheme(outdoor ? .light : .dark)
    }
}
