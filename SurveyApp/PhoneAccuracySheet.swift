import SwiftUI
import SurveyCore

struct PhoneAverageSheet: View {
    @ObservedObject var field: FieldModel

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(PhoneAccuracyLabel.average)
                    .font(SurveyType(16, .heavy))
                    .foregroundStyle(SurveyColor.amber)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("時間", selection: Binding(
                    get: { field.averageSpan },
                    set: { field.setAverageSpan($0) }
                )) {
                    ForEach(PhoneAverageSpan.allCases) { span in
                        Text(span.title).tag(span)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minHeight: 44)
                Button("始める") {
                    field.beginPhoneAverage(.record)
                }
                .buttonStyle(SurveyPlainButton())
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(SurveyColor.background)
            .navigationTitle("平均")
            .navigationBarTitleDisplayMode(.inline)
        }
        .modifier(SurveyScheme())
    }
}

struct KnownShiftSheet: View {
    @ObservedObject var field: FieldModel
    @State private var selectedID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(PhoneAccuracyLabel.shift)
                        .font(SurveyType(16, .heavy))
                        .foregroundStyle(SurveyColor.amber)
                        .fixedSize(horizontal: false, vertical: true)
                    if field.drawing.project == nil {
                        Text("現場を選んでください")
                            .font(SurveyType(18, .heavy))
                            .frame(minHeight: 44)
                    } else if field.drawing.fieldPoints.isEmpty {
                        Text("SIMAか座標リストを取り込んでください")
                            .font(SurveyType(18, .heavy))
                            .frame(minHeight: 44)
                    } else {
                        ForEach(field.drawing.fieldPoints) { point in
                            Button {
                                selectedID = point.id
                            } label: {
                                HStack {
                                    Text(point.name)
                                        .font(SurveyType(18, .heavy))
                                    Spacer(minLength: 8)
                                    if let height = point.bookHeightMeters {
                                        Text(FieldPoint.meters(height))
                                            .font(SurveyType(16, .heavy, mono: true))
                                    }
                                }
                                .foregroundStyle(selectedID == point.id ? SurveyColor.onAccent : SurveyColor.text)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(
                                    selectedID == point.id ? SurveyColor.blue : SurveyColor.card,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        Picker("時間", selection: Binding(
                            get: { field.averageSpan },
                            set: { field.setAverageSpan($0) }
                        )) {
                            ForEach(PhoneAverageSpan.allCases) { span in
                                Text(span.title).tag(span)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(minHeight: 44)
                        Button("この点で合わせる") {
                            guard let point = field.drawing.fieldPoints.first(where: { $0.id == selectedID }) else { return }
                            let anchor = KnownAnchor(
                                id: point.id,
                                name: point.name,
                                latitudeDegrees: point.latitudeDegrees,
                                longitudeDegrees: point.longitudeDegrees,
                                heightMeters: point.bookHeightMeters
                            )
                            field.beginPhoneAverage(.knownPoint(anchor))
                        }
                        .buttonStyle(SurveyPlainButton())
                        .disabled(selectedID == nil)
                    }
                    if let shift = field.knownShift {
                        Text(shift.deltaText)
                            .font(SurveyType(18, .heavy, mono: true))
                            .frame(minHeight: 44)
                        Text(shift.statusLine(
                            at: field.phoneClock,
                            latitude: field.reading.position?.latitudeDegrees,
                            longitude: field.reading.position?.longitudeDegrees
                        ))
                        .font(SurveyType(16, .heavy))
                        Toggle("合わせを使う", isOn: Binding(
                            get: { field.knownShift?.enabled == true },
                            set: { field.setKnownShiftEnabled($0) }
                        ))
                        .font(SurveyType(18, .heavy))
                        .tint(SurveyColor.blue)
                        .frame(minHeight: 44)
                    }
                }
                .padding(16)
            }
            .background(SurveyColor.background)
            .navigationTitle("既知点合わせ")
            .navigationBarTitleDisplayMode(.inline)
        }
        .modifier(SurveyScheme())
    }
}

struct PhoneAccuracyBar: View {
    @ObservedObject var field: FieldModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let run = field.phoneRun {
                HStack(spacing: 8) {
                    Text(run.line(at: field.phoneClock))
                        .font(SurveyType(16, .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("止める") { field.stopPhoneAverage() }
                        .font(SurveyType(16, .heavy))
                        .foregroundStyle(SurveyColor.onAccent)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(SurveyColor.blue, in: Capsule())
                        .buttonStyle(.plain)
                }
                Text(PhoneAccuracyLabel.average)
                    .font(SurveyType(13, .heavy))
                    .foregroundStyle(SurveyColor.amber)
            }
            if let shift = field.knownShift, shift.enabled, !calibrating {
                let position = field.reading.position
                let stale = shift.isStale(
                    at: field.phoneClock,
                    latitude: position?.latitudeDegrees,
                    longitude: position?.longitudeDegrees
                )
                Text(shift.statusLine(
                    at: field.phoneClock,
                    latitude: position?.latitudeDegrees,
                    longitude: position?.longitudeDegrees
                ) + (position?.receiver == .iphoneGPS ? "" : "  iPhoneの点だけ"))
                .font(SurveyType(16, .heavy))
                .foregroundStyle(stale ? SurveyColor.amber : SurveyColor.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                Text(PhoneAccuracyLabel.shift)
                    .font(SurveyType(13, .heavy))
                    .foregroundStyle(SurveyColor.amber)
            }
        }
    }

    private var calibrating: Bool {
        if case .knownPoint = field.phoneRun?.purpose { return true }
        return false
    }
}
