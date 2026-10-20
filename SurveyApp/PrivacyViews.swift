import SwiftUI
import SurveyCore

/// 今、自分の位置を送っているかを常に出す。
struct LocationShareBanner: View {
    @ObservedObject var field: FieldModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(field.locationShare.label)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(field.locationShare.shares ? SurveyColor.green : SurveyColor.amber)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("location-share-status")
            HStack(spacing: 8) {
                Button(field.sharePaused ? "共有を再開" : "休憩") {
                    field.setSharePaused(!field.sharePaused)
                }
                .buttonStyle(ShareChipStyle())
                Button("誰が見られるか") {
                    field.showsPrivacy = true
                }
                .buttonStyle(ShareChipStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(field.locationShare.shares ? SurveyColor.greenBackground : SurveyColor.amberBackground)
    }
}

struct LocationPrivacySheet: View {
    @ObservedObject var field: FieldModel
    @Environment(\.dismiss) private var dismiss
    @State private var startHour = 8
    @State private var endHour = 17
    @State private var radius = LocationPrivacy.suggestedRadiusMeters

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(field.locationShare.label)
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(field.locationShare.shares ? SurveyColor.green : SurveyColor.amber)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(field.sharePaused ? "共有を再開" : "休憩にする") {
                        field.setSharePaused(!field.sharePaused)
                    }
                    .buttonStyle(ShareActionStyle())
                    Text(LocationPrivacy.safetyNote)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(SurveyColor.amber)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(LocationPrivacy.terms)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(SurveyColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(LocationPrivacy.trackNote)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SurveyColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(LocationPrivacy.audienceNote)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SurveyColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    viewers
                    fence
                    hours
                    if let privacyMessage = field.privacyMessage {
                        Text(privacyMessage)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(SurveyColor.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
            .background(SurveyColor.background)
            .navigationTitle("位置の共有")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                        .font(.system(size: 17, weight: .heavy))
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: loadDraft)
    }

    private var viewers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("今、見られる相手")
                .font(.system(size: 18, weight: .heavy))
            if field.shareViewers.isEmpty {
                Text(field.locationShare.shares ? "今つながっている端末はありません。" : "今は送っていません")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(SurveyColor.muted)
            } else {
                ForEach(field.shareViewers) { viewer in
                    Text("\(viewer.name)　\(viewer.role)")
                        .font(.system(size: 16, weight: .heavy))
                }
            }
        }
    }

    private var fence: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("現場の範囲")
                .font(.system(size: 18, weight: .heavy))
            if let fence = field.drawing.project?.siteFence {
                Text("中心 \(String(format: "%.5f", fence.latitudeDegrees)), \(String(format: "%.5f", fence.longitudeDegrees))　半径 \(Int(fence.radiusMeters))m")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SurveyColor.muted)
            } else {
                Text("未設定です。未設定のあいだは位置を送りません。")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Stepper(value: $radius, in: LocationPrivacy.minimumRadiusMeters...LocationPrivacy.maximumRadiusMeters, step: 50) {
                Text("半径 \(Int(radius))m")
                    .font(.system(size: 16, weight: .heavy))
            }
            Button("現在地を現場の中心にする") {
                field.placeFence(radiusMeters: radius)
            }
            .buttonStyle(ShareActionStyle())
            Button("半径をこの値にする") {
                field.updateFenceRadius(radius)
            }
            .buttonStyle(ShareActionStyle())
        }
    }

    private var hours: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("作業時間")
                .font(.system(size: 18, weight: .heavy))
            if let hours = field.drawing.project?.workHours {
                Text("いまの設定は \(hours.startHour)時から\(hours.endHour)時まで。終了の時刻は含みません。")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("未設定です。未設定のあいだは位置を送りません。")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            hourRow("開始", value: $startHour, upper: 23)
            hourRow("終了", value: $endHour, upper: 24)
            Button("この時間にする") {
                field.saveWorkHours(start: startHour, end: endHour)
            }
            .buttonStyle(ShareActionStyle())
        }
    }

    private func hourRow(_ title: String, value: Binding<Int>, upper: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .heavy))
                .frame(width: 48, alignment: .leading)
            Text("\(value.wrappedValue)時")
                .font(.system(size: 18, weight: .black))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("−") { value.wrappedValue = max(0, value.wrappedValue - 1) }
                .buttonStyle(ShareChipStyle())
            Button("＋") { value.wrappedValue = min(upper, value.wrappedValue + 1) }
                .buttonStyle(ShareChipStyle())
        }
    }

    private func loadDraft() {
        if let hours = field.drawing.project?.workHours {
            startHour = hours.startHour
            endHour = hours.endHour
        }
        if let fence = field.drawing.project?.siteFence, fence.radiusMeters > 0 {
            radius = fence.radiusMeters
        }
    }
}

private struct ShareChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .black))
            .foregroundStyle(SurveyColor.text)
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(SurveyColor.card)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ShareActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .black))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(SurveyColor.blue)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
