import SwiftUI
import SurveyCore

struct AccuracyBadgeView: View {
    let badge: AccuracyBadgeModel

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(badge.tone.tint)
                .frame(width: 16, height: 16)
            Text(badge.text)
                .font(.system(size: 20, weight: .heavy))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .foregroundStyle(badge.tone.tint)
        .background(badge.tone.badgeBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(badge.tone.tint, lineWidth: 3)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge.accessibilityText)
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
                            .font(.system(size: 24, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 14, weight: .bold))
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
            Rectangle().fill(SurveyColor.line).frame(height: 1)
        }
    }
}

struct PlaceholderTabView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 28, weight: .heavy))
            Text(message)
                .font(.system(size: 18, weight: .semibold))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("現在地")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(SurveyColor.muted)
            if let position = reading.position, position.isPlottable {
                Text(CoordinateText.latitude(position.latitudeDegrees))
                    .font(.system(size: 32, weight: .heavy, design: .monospaced))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(CoordinateText.longitude(position.longitudeDegrees))
                    .font(.system(size: 32, weight: .heavy, design: .monospaced))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(CoordinateText.ellipsoidalHeight(position.ellipsoidalHeightMeters))
                    Text(accuracyText(position))
                }
                .font(.system(size: 18, weight: .bold))
                Text(CoordinateText.previewNote)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SurveyColor.muted)
                Text(CoordinateText.storageNote)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SurveyColor.muted)
                if let warning = warningText {
                    Text(warning)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(SurveyColor.amber)
                }
            } else {
                Text(emptyTitle)
                    .font(.system(size: 22, weight: .heavy))
                Text(emptyDetail)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SurveyColor.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(SurveyColor.text)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SurveyColor.card.opacity(0.96), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(SurveyColor.line, lineWidth: 1)
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
                        .font(.system(size: 18, weight: .heavy))
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
                            .font(.system(size: 18, weight: .heavy))
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
                    .font(.system(size: 14, weight: .semibold))
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
                .font(.system(size: 13, weight: .heavy))
            Text(GSITileCatalog.sourceCredit)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Color.black)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel("\(GSITileCatalog.attribution)。\(GSITileCatalog.sourceCredit)")
    }
}

struct RecenterButton: View {
    let following: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: following ? "location.fill" : "location")
                .font(.system(size: 22, weight: .bold))
                .frame(width: 60, height: 60)
                .background(Color.white, in: Circle())
                .foregroundStyle(Color.black)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("現在地へ")
    }
}
