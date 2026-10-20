import SwiftUI
import SurveyCore

/// 気泡管。中央が鉛直（視線が水平）。後傾で気泡は上へ動く。
struct LevelBubble: View {
    var tiltRadians: Double?
    var compact: Bool = false

    private var level: Bool {
        tiltRadians.map(StatureMath.isEyeLevel) ?? false
    }

    var body: some View {
        let tubeHeight: CGFloat = compact ? 72 : 96
        HStack(spacing: 12) {
            tube(height: tubeHeight)
            VStack(alignment: .leading, spacing: 2) {
                Text(level ? "目線水平" : "水平器")
                    .font(SurveyType(compact ? 16 : 18, .heavy))
                Text(caption)
                    .font(SurveyType(14, .semibold))
                    .foregroundStyle(SurveyColor.muted)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    private var caption: String {
        guard let tiltRadians else { return "傾きを待っています" }
        if level { return "±1°以内" }
        return "傾き \(StatureMath.degreeText(tiltRadians))°"
    }

    private var accessibility: String {
        guard let tiltRadians else { return "水平器。傾きを待っています" }
        if level { return "目線水平。鉛直から1度以内" }
        return "水平器。傾き \(StatureMath.degreeText(tiltRadians))度"
    }

    private func tube(height: CGFloat) -> some View {
        let travel = (height - 28) / 2
        let limit = 20.0 * .pi / 180
        let fraction: CGFloat = {
            guard let tiltRadians else { return 0 }
            let raw = tiltRadians / limit
            return CGFloat(min(1, max(-1, raw)))
        }()
        return ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(SurveyColor.background)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(level ? SurveyColor.green : SurveyColor.line, lineWidth: SurveyColor.stroke)
            Rectangle()
                .fill(SurveyColor.line)
                .frame(width: 28, height: SurveyColor.stroke)
            if tiltRadians != nil {
                Circle()
                    .fill(level ? SurveyColor.green : SurveyColor.blue)
                    .frame(width: 22, height: 22)
                    .offset(y: -fraction * travel)
            }
        }
        .frame(width: 36, height: height)
    }
}
