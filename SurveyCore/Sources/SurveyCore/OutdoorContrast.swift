import Foundation

public enum OutdoorChoice: String, Sendable, Equatable {
    case automatic
    case outdoor
    case indoor
}

public struct ContrastColor: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(byteRed: Double, green: Double, blue: Double) {
        self.red = byteRed / 255
        self.green = green / 255
        self.blue = blue / 255
    }
}

public struct ContrastPair: Sendable, Equatable {
    public var name: String
    public var foreground: ContrastColor
    public var background: ContrastColor
    /// 18pt 以上、または 14pt 以上の太字。AAA は 4.5。本文は 7。
    public var largeText: Bool

    public init(name: String, foreground: ContrastColor, background: ContrastColor, largeText: Bool = false) {
        self.name = name
        self.foreground = foreground
        self.background = background
        self.largeText = largeText
    }
}

/// 屋外の白地。影も半透明も使わない。本文は WCAG AAA（7:1）、大きい文字は 4.5:1。
public enum OutdoorContrast {
    public static let brightnessThreshold = 0.6
    public static let bodyRatio = 7.0
    public static let largeRatio = 4.5
    public static let primaryPoints = 60.0
    public static let strokePoints = 3.0

    public static let white = ContrastColor(byteRed: 255, green: 255, blue: 255)
    public static let black = ContrastColor(byteRed: 0, green: 0, blue: 0)
    public static let muted = ContrastColor(byteRed: 34, green: 34, blue: 34)
    public static let blue = ContrastColor(byteRed: 0, green: 45, blue: 156)
    public static let red = ContrastColor(byteRed: 158, green: 0, blue: 0)
    public static let green = ContrastColor(byteRed: 0, green: 100, blue: 0)
    public static let yellow = ContrastColor(byteRed: 255, green: 214, blue: 0)
    public static let grey = ContrastColor(byteRed: 45, green: 45, blue: 45)

    public static let pairs: [ContrastPair] = [
        ContrastPair(name: "本文", foreground: black, background: white),
        ContrastPair(name: "補足", foreground: muted, background: white),
        ContrastPair(name: "青", foreground: blue, background: white),
        ContrastPair(name: "青地に白", foreground: white, background: blue, largeText: true),
        ContrastPair(name: "赤", foreground: red, background: white),
        ContrastPair(name: "赤地に白", foreground: white, background: red, largeText: true),
        ContrastPair(name: "緑", foreground: green, background: white),
        ContrastPair(name: "緑地に白", foreground: white, background: green, largeText: true),
        ContrastPair(name: "黄地に黒", foreground: black, background: yellow, largeText: true),
        ContrastPair(name: "灰色", foreground: grey, background: white)
    ]

    public static func prefersOutdoor(_ choice: OutdoorChoice, brightness: Double) -> Bool {
        switch choice {
        case .outdoor: return true
        case .indoor: return false
        case .automatic: return brightness >= brightnessThreshold
        }
    }

    public static func ratio(_ foreground: ContrastColor, _ background: ContrastColor) -> Double {
        let lighter = max(luminance(foreground), luminance(background))
        let darker = min(luminance(foreground), luminance(background))
        return (lighter + 0.05) / (darker + 0.05)
    }

    public static func passesAAA(_ pair: ContrastPair) -> Bool {
        ratio(pair.foreground, pair.background) >= (pair.largeText ? largeRatio : bodyRatio)
    }

    /// 白地で 7:1 を切る線は黒にする。黄や純緑は、太い黒線に替える。
    public static func ink(red: Double, green: Double, blue: Double) -> ContrastColor {
        let color = ContrastColor(red: red, green: green, blue: blue)
        if ratio(color, white) >= bodyRatio { return color }
        return black
    }

    public static func luminance(_ color: ContrastColor) -> Double {
        0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
    }

    private static func channel(_ value: Double) -> Double {
        let clamped = min(1, max(0, value))
        if clamped <= 0.04045 { return clamped / 12.92 }
        return pow((clamped + 0.055) / 1.055, 2.4)
    }
}
