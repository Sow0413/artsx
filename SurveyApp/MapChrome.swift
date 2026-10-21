import SwiftUI
import SurveyCore

struct AccuracyBadgeView: View {
    let badge: AccuracyBadgeModel
    var stage: PositionStage?
    var compact = false
    @State private var showsDetail = false

    var body: some View {
        Button {
            showsDetail = true
        } label: {
            compactLine
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showsDetail) {
            AccuracyDetailSheet(badge: badge, stage: stage)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge.accessibilityText)
        .accessibilityHint("詳しく見る")
    }

    private var compactLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(badge.tone.mark)
                .frame(width: 12, height: 12)
            Text(badge.compactText.isEmpty ? badge.text : badge.compactText)
                .font(SurveyType(16, .heavy))
                .foregroundStyle(badge.tone.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(badge.tone.badgeBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SurveyColor.line, lineWidth: SurveyColor.stroke)
        )
    }

}

/// 足りない長さと届く手段。常時バナーには出さない。
struct AccuracyDetailSheet: View {
    let badge: AccuracyBadgeModel
    var stage: PositionStage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(badge.compactText.isEmpty ? badge.text : badge.compactText)
                        .font(SurveyType(34, .heavy))
                        .foregroundStyle(badge.tone.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let stage {
                        Text("段階\(stage.rawValue)")
                            .font(SurveyType(16, .heavy))
                            .foregroundStyle(SurveyColor.muted)
                    }
                    if badge.text != badge.compactText {
                        Text(badge.text)
                            .font(SurveyType(18, .heavy))
                    }
                    if !badge.caution.isEmpty {
                        Text(badge.caution)
                            .font(SurveyType(16, .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !badge.guidance.isEmpty {
                        Text(badge.guidance)
                            .font(SurveyType(16, .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(SurveyColor.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .background(SurveyColor.background)
            .navigationTitle("測位")
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

struct SurveyTabBar: View {
    @Binding var selection: FieldTab
    var onRecord: () -> Void
    var onList: () -> Void
    var onReselect: (FieldTab) -> Void
    @State private var suppressRecordTap = false

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.map)
            tabButton(.drawing)
            Color.clear
                .frame(width: 76, height: 68)
                .accessibilityHidden(true)
            tabButton(.survey)
            tabButton(.build)
        }
        .background(SurveyColor.bar)
        .overlay(alignment: .top) {
            Rectangle().fill(SurveyColor.line).frame(height: SurveyColor.stroke)
        }
        .overlay {
            recordButton
                .offset(y: -18)
        }
        .overlay {
            Button(action: onList) {
                Text("一覧")
                    .font(SurveyType(13, .heavy))
                    .foregroundStyle(Color.black)
                    .frame(width: 44, height: 44)
                    .background(Color.white, in: Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 58, y: -48)
            .accessibilityLabel("記録一覧")
        }
    }

    private var recordButton: some View {
        Text("記録")
            .font(SurveyType(18, .heavy))
            .foregroundStyle(SurveyColor.onAccent)
            .frame(width: 76, height: 76)
            .background(SurveyColor.blue, in: Circle())
            .contentShape(Circle())
            .onTapGesture {
                if suppressRecordTap {
                    suppressRecordTap = false
                    return
                }
                onRecord()
            }
            .onLongPressGesture(minimumDuration: 0.45) {
                suppressRecordTap = true
                onList()
            }
            .accessibilityLabel("記録")
            .accessibilityHint("長押しで記録一覧")
            .accessibilityAction(named: "記録一覧") { onList() }
    }

    private func tabButton(_ tab: FieldTab) -> some View {
        Button {
            if selection == tab {
                onReselect(tab)
            } else {
                selection = tab
            }
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
    var showsLevel = false
    var levelTilt: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("現在地")
                .font(SurveyType(13, .heavy))
                .foregroundStyle(SurveyColor.muted)
            if let position = reading.position, position.isPlottable {
                Text(CoordinateText.latitude(position.latitudeDegrees))
                    .font(SurveyType(20, .heavy, mono: true))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(CoordinateText.longitude(position.longitudeDegrees))
                    .font(SurveyType(20, .heavy, mono: true))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                let height = SurveyHeight.resolve(
                    ellipsoidalMeters: position.ellipsoidalHeightMeters,
                    latitudeDegrees: position.latitudeDegrees,
                    longitudeDegrees: position.longitudeDegrees,
                    meanSeaLevelMeters: position.meanSeaLevelMeters
                )
                Text(height.primaryLine)
                    .font(SurveyType(15, .bold))
                ForEach(height.detailLines, id: \.self) { line in
                    Text(line)
                        .font(SurveyType(13, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                }
                if let statureNotice {
                    Button(action: { onStature?() }) {
                        Text(statureNotice)
                            .font(SurveyType(16, .heavy))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .disabled(onStature == nil)
                }
                if showsLevel {
                    LevelBubble(tiltRadians: levelTilt, compact: true)
                }
                if let note {
                    Text(note)
                        .font(SurveyType(14, .heavy))
                        .foregroundStyle(SurveyColor.blue)
                        .lineLimit(2)
                }
                if let warning = warningText {
                    Text(warning)
                        .font(SurveyType(15, .bold))
                        .foregroundStyle(SurveyColor.amber)
                }
            } else {
                Text(emptyTitle)
                    .font(SurveyType(18, .heavy))
                Text(emptyDetail)
                    .font(SurveyType(14, .semibold))
                    .foregroundStyle(SurveyColor.amber)
                    .fixedSize(horizontal: false, vertical: true)
                if showsLevel {
                    LevelBubble(tiltRadians: levelTilt, compact: true)
                }
            }
        }
        .foregroundStyle(SurveyColor.text)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SurveyColor.line, lineWidth: SurveyColor.stroke)
        )
        .accessibilityElement(children: .combine)
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
            return "設定で許可"
        case .unavailable:
            return "空の見える場所で待つ"
        case .waiting, .available:
            return "iPhone GPS"
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
                        .font(SurveyType(15, .heavy))
                        .minimumScaleFactor(0.7)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, minHeight: 44)
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
                            .font(SurveyType(15, .heavy))
                            .frame(minWidth: 72, minHeight: 44)
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
                .font(SurveyType(18, .bold))
                .frame(width: 44, height: 44)
                .background(Color.white, in: Circle())
                .foregroundStyle(Color.black)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("現在地へ")
    }
}
