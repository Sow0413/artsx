import SwiftUI
import SurveyCore

struct CrewGlyph: Equatable {
    var id: String
    var name: String
    var role: CrewRole
    var point: PlanarPoint
    var radius: Double?
    var level: ProximityLevel
}

struct SafetyBanner: View {
    @ObservedObject var crew: CrewController

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(crew.notice)
                .font(.system(size: 13, weight: .heavy))
            Text(crew.statusLine)
                .font(.system(size: crew.worst == .clear ? 15 : 22, weight: .black))
                .minimumScaleFactor(0.6)
                .lineLimit(2)
        }
        .foregroundStyle(crew.worst == .alarm ? Color.white : SurveyColor.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(fill)
        .accessibilityElement(children: .combine)
    }

    private var fill: Color {
        switch crew.worst {
        case .alarm: return SurveyColor.red
        case .caution: return SurveyColor.yellow
        case .clear: return SurveyColor.card.opacity(0.94)
        }
    }
}

struct SafetyWash: View {
    var level: ProximityLevel

    var body: some View {
        fill
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var fill: Color {
        switch level {
        case .alarm: return SurveyColor.red.opacity(0.33)
        case .caution: return SurveyColor.yellow.opacity(0.2)
        case .clear: return Color.clear
        }
    }
}

struct CrewRadar: View {
    var marks: [CrewMark]
    var selfRole: CrewRole
    var selfRadius: Double
    var cautionMeters: Double

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let farthest = marks.map { hypot($0.eastMeters, $0.northMeters) + ($0.workRadiusMeters ?? 0) }.max() ?? 0
            let span = max(cautionMeters, selfRole == .machine ? selfRadius : 0, farthest, 20)
            let scale = (min(size.width, size.height) * 0.42) / span
            func place(_ east: Double, _ north: Double) -> CGPoint {
                CGPoint(x: center.x + CGFloat(east * scale), y: center.y - CGFloat(north * scale))
            }
            func ring(_ meters: Double, color: Color) {
                let pixels = CGFloat(meters * scale)
                let rect = CGRect(x: center.x - pixels, y: center.y - pixels, width: pixels * 2, height: pixels * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 2)
            }
            ring(cautionMeters, color: SurveyColor.yellow.opacity(0.9))
            if selfRole == .machine {
                ring(selfRadius, color: SurveyColor.amber)
            }
            for mark in marks {
                let origin = place(mark.eastMeters, mark.northMeters)
                if mark.role == .machine, let radius = mark.workRadiusMeters, radius > 0 {
                    let pixels = CGFloat(radius * scale)
                    let rect = CGRect(x: origin.x - pixels, y: origin.y - pixels, width: pixels * 2, height: pixels * 2)
                    context.stroke(Path(ellipseIn: rect), with: .color(color(mark.level)), lineWidth: 2)
                }
                let dot = CGRect(x: origin.x - 6, y: origin.y - 6, width: 12, height: 12)
                context.fill(Path(ellipseIn: dot), with: .color(color(mark.level)))
            }
            let me = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: me), with: .color(Color.white))
        }
        .frame(height: 88)
        .accessibilityLabel("相手の位置。\(SafetyNotice.text)")
    }

    private func color(_ level: ProximityLevel) -> Color {
        switch level {
        case .alarm: return SurveyColor.red
        case .caution: return SurveyColor.yellow
        case .clear: return SurveyColor.blue
        }
    }
}
