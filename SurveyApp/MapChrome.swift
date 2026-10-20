import SwiftUI
import SurveyCore

struct AccuracyBadgeView: View {
    let badge: AccuracyBadgeModel
    var stage: PositionStage?

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(badge.tone.mark)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(badge.solutionLabel)
                        .font(SurveyType(15, .heavy))
                        .foregroundStyle(chipInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(badge.tone.mark, in: Capsule())
                    if let stage {
                        Text("段階\(stage.rawValue)")
                            .font(SurveyType(13, .heavy))
                            .foregroundStyle(SurveyColor.muted)
                    }
                }
                Text(badge.text)
                    .font(SurveyType(20, .heavy))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if !badge.caution.isEmpty {
                    Text(badge.caution)
                        .font(SurveyType(13, .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !badge.guidance.isEmpty {
                    Text(badge.guidance)
                        .font(SurveyType(14, .heavy))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints, alignment: .leading)
        .foregroundStyle(badge.tone.tint)
        .background(badge.tone.badgeBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SurveyColor.line, lineWidth: SurveyColor.stroke)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge.accessibilityText)
    }

    /// 黄地は黒文字。赤と緑の原色地は白文字。
    private var chipInk: Color {
        switch badge.tone {
        case .amber, .yellow: return SurveyColor.color(OutdoorContrast.black)
        case .red, .green, .grey: return SurveyColor.onAccent
        }
    }
}

struct SurveyTabBar: View {
    @Binding var selection: FieldTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FieldTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(SurveyType(24, .semibold))
                        Text(tab.title)
                            .font(SurveyType(14, .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 68)
                    .foregroundStyle(selection == tab ? SurveyColor.text : SurveyColor.muted)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .background(SurveyColor.bar)
        .overlay(alignment: .top) {
            Rectangle().fill(SurveyColor.line).frame(height: SurveyColor.stroke)
        }
    }
}

struct PlaceholderTabView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(SurveyType(28, .heavy))
            Text(message)
                .font(SurveyType(18, .semibold))
                .foregroundStyle(SurveyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SurveyColor.background)
    }
}

struct LocationPanel: View {
    let reading: PositionReading
    var note: String? = nil
    var statureNotice: String? = nil
    var onStature: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("現在地")
                .font(SurveyType(15, .heavy))
                .foregroundStyle(SurveyColor.muted)
            if let position = reading.position, position.isPlottable {
                Text(CoordinateText.latitude(position.latitudeDegrees))
                    .font(SurveyType(32, .heavy, mono: true))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(CoordinateText.longitude(position.longitudeDegrees))
                    .font(SurveyType(32, .heavy, mono: true))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(CoordinateText.ellipsoidalHeight(position.ellipsoidalHeightMeters))
                    Text(accuracyText(position))
                }
                .font(SurveyType(18, .bold))
                if let statureNotice {
                    Button(action: { onStature?() }) {
                        Text(statureNotice)
                            .font(SurveyType(22, .heavy))
                            .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .disabled(onStature == nil)
                }
                if let note {
                    Text(note)
                        .font(SurveyType(15, .heavy))
                        .foregroundStyle(SurveyColor.blue)
                }
                Text(CoordinateText.previewNote)
                    .font(SurveyType(14, .bold))
                    .foregroundStyle(SurveyColor.muted)
                Text(CoordinateText.storageNote)
                    .font(SurveyType(13, .medium))
                    .foregroundStyle(SurveyColor.muted)
                if let warning = warningText {
                    Text(warning)
                        .font(SurveyType(15, .bold))
                        .foregroundStyle(SurveyColor.amber)
                }
            } else {
                Text(emptyTitle)
                    .font(SurveyType(22, .heavy))
                Text(emptyDetail)
                    .font(SurveyType(16, .semibold))
                    .foregroundStyle(SurveyColor.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(SurveyColor.text)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(SurveyColor.line, lineWidth: SurveyColor.stroke)
        )
        .accessibilityElement(children: .combine)
    }

    private func accuracyText(_ position: GeodeticPosition) -> String {
        guard position.hasValidHorizontalAccuracy else { return "精度不明" }
        return CoordinateText.accuracyMeters(position.horizontalAccuracyMeters)
    }

    private var warningText: String? {
        switch reading.availability {
        case .available:
            return nil
        case .waiting:
            return "位置を取得しています"
        case .denied:
            return "位置情報を許可してください"
        case .unavailable:
            return "直前の位置です"
        }
    }

    private var emptyTitle: String {
        switch reading.availability {
        case .denied:
            return "位置情報を許可してください"
        case .unavailable:
            return "位置を取得できません"
        case .waiting, .available:
            return "位置を取得中"
        }
    }

    private var emptyDetail: String {
        switch reading.availability {
        case .denied:
            return "iPhone の設定で、このアプリの位置情報を許可すると現在地が出ます。"
        case .unavailable:
            return "空の見える場所でもう一度待ってください。"
        case .waiting, .available:
            return "iPhone GPS の段階0です。数mの下見に使います。"
        }
    }
}

struct DownloadBar: View {
    let message: String
    let isDownloading: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(action: onSave) {
                    Text(isDownloading ? message : "この範囲を保存")
                        .font(SurveyType(18, .heavy))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .padding(.horizontal, 12)
                        .background(isDownloading ? SurveyColor.card : SurveyColor.blue)
                        .foregroundStyle(SurveyColor.text)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isDownloading)
                .accessibilityLabel(isDownloading ? message : "この範囲を保存")
                if isDownloading {
                    Button(action: onCancel) {
                        Text("中止")
                            .font(SurveyType(18, .heavy))
                            .frame(minWidth: 88, minHeight: 64)
                            .background(SurveyColor.card)
                            .foregroundStyle(SurveyColor.text)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(SurveyColor.line, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("保存を中止")
                }
            }
            if !isDownloading {
                Text(message)
                    .font(SurveyType(14, .semibold))
                    .foregroundStyle(message.contains("広すぎ") || message.contains("できません") ? SurveyColor.amber : SurveyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct AttributionLabel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(GSITileCatalog.attribution)
                .font(SurveyType(13, .heavy))
            Text(GSITileCatalog.sourceCredit)
                .font(SurveyType(11, .semibold))
        }
        .foregroundStyle(Color.black)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.black, lineWidth: SurveyColor.stroke)
        )
        .accessibilityLabel("\(GSITileCatalog.attribution)。\(GSITileCatalog.sourceCredit)")
    }
}

struct RecenterButton: View {
    let following: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: following ? "location.fill" : "location")
                .font(SurveyType(22, .bold))
                .frame(width: 60, height: 60)
                .background(Color.white, in: Circle())
                .foregroundStyle(Color.black)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("現在地へ")
    }
}
