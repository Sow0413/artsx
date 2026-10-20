import SwiftUI
import UIKit
import SurveyCore

enum SurveyColor {
    static let background = Color(red: 11 / 255, green: 13 / 255, blue: 16 / 255)
    static let card = Color(red: 23 / 255, green: 26 / 255, blue: 31 / 255)
    static let text = Color(red: 245 / 255, green: 247 / 255, blue: 250 / 255)
    static let muted = Color(red: 154 / 255, green: 163 / 255, blue: 173 / 255)
    static let line = Color(red: 42 / 255, green: 47 / 255, blue: 55 / 255)
    static let amber = Color(red: 1, green: 176 / 255, blue: 32 / 255)
    static let amberBackground = Color(red: 42 / 255, green: 31 / 255, blue: 5 / 255)
    static let yellow = Color(red: 245 / 255, green: 217 / 255, blue: 10 / 255)
    static let yellowBackground = Color(red: 42 / 255, green: 36 / 255, blue: 5 / 255)
    static let red = Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255)
    static let redBackground = Color(red: 42 / 255, green: 12 / 255, blue: 12 / 255)
    static let green = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)
    static let greenBackground = Color(red: 6 / 255, green: 35 / 255, blue: 18 / 255)
    static let grey = Color(red: 138 / 255, green: 146 / 255, blue: 156 / 255)
    static let greyBackground = Color(red: 28 / 255, green: 31 / 255, blue: 36 / 255)
    static let blue = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    static let bar = Color(red: 16 / 255, green: 19 / 255, blue: 23 / 255)
    static let mapBackdrop = Color(red: 0.91, green: 0.94, blue: 0.89)
}

enum SurveyUIColor {
    static let amber = UIColor(red: 1, green: 176 / 255, blue: 32 / 255, alpha: 1)
    static let yellow = UIColor(red: 245 / 255, green: 217 / 255, blue: 10 / 255, alpha: 1)
    static let red = UIColor(red: 239 / 255, green: 68 / 255, blue: 68 / 255, alpha: 1)
    static let green = UIColor(red: 34 / 255, green: 197 / 255, blue: 94 / 255, alpha: 1)
    static let grey = UIColor(red: 138 / 255, green: 146 / 255, blue: 156 / 255, alpha: 1)
    static let blue = UIColor(red: 59 / 255, green: 130 / 255, blue: 246 / 255, alpha: 1)
    static let mapBackdrop = UIColor(red: 0.91, green: 0.94, blue: 0.89, alpha: 1)
}

extension AccuracyTone {
    var tint: Color {
        switch self {
        case .grey: return SurveyColor.grey
        case .amber: return SurveyColor.amber
        case .yellow: return SurveyColor.yellow
        case .red: return SurveyColor.red
        case .green: return SurveyColor.green
        }
    }

    var badgeBackground: Color {
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
