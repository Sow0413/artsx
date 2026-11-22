import MapKit
import SwiftUI
import SurveyCore
#if canImport(PhotosUI)
import PhotosUI
#endif

struct DisasterSheet: View {
    @ObservedObject var field: FieldModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind: DisasterKind = .roadCut
    @State private var length = ""
    @State private var width = ""
    @State private var height = ""
    @State private var note = ""
    @State private var text = ""
    #if canImport(PhotosUI)
    @State private var photo: PhotosPickerItem?
    #endif
    @State private var photoData: Data?
    @State private var formNote: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    modeSection
                    statusSection
                    siteSection
                    passageSection
                    textSection
                    exportSection
                    tileSection
                }
                .padding(16)
            }
            .background(SurveyColor.background)
            .navigationTitle("災害派遣")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { field.disasterMode },
                set: { field.setDisasterMode($0) }
            )) {
                Text("災害派遣")
                    .font(SurveyType(18, .heavy))
                    .foregroundStyle(SurveyColor.text)
            }
            .tint(SurveyColor.red)
            Text("圏外を前提にします。位置、SOS、文字、被災箇所、通行は、近くの端末を経由して渡します。期限が切れた情報は中継しません。")
                .font(SurveyType(14, .medium))
                .foregroundStyle(SurveyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: Binding(
                get: { field.batterySaver },
                set: { field.setBatterySaver($0) }
            )) {
                Text("電池節約")
                    .font(SurveyType(16, .heavy))
                    .foregroundStyle(SurveyColor.text)
            }
            .tint(SurveyColor.amber)
            Text(BatterySaver.note)
                .font(SurveyType(14, .medium))
                .foregroundStyle(SurveyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(SurveyColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("中継の控え \(field.bucketDesk.heldCount)件。P510への同期待ち \(field.disasterPending)件。")
                .font(SurveyType(14, .heavy))
                .foregroundStyle(SurveyColor.text)
                .fixedSize(horizontal: false, vertical: true)
            if let message = field.disasterMessage {
                Text(message)
                    .font(SurveyType(14, .medium))
                    .foregroundStyle(SurveyColor.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("P510へまとめて送る") {
                field.flushDisasterNow()
            }
            .buttonStyle(DisasterButtonStyle(fill: SurveyColor.blue))
            Text("Starlink など衛星回線は、P510 まで届く経路の一つです。届いたときだけ送ります。")
                .font(SurveyType(13, .medium))
                .foregroundStyle(SurveyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(SurveyColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var siteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("被災箇所")
                .font(SurveyType(16, .heavy))
                .foregroundStyle(SurveyColor.text)
            Picker("種類", selection: $kind) {
                ForEach(DisasterKind.allCases, id: \.self) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.menu)
            .tint(SurveyColor.text)
            HStack(spacing: 8) {
                measureField("延長", text: $length)
                measureField("幅", text: $width)
                measureField("高さ", text: $height)
            }
            TextField("メモ", text: $note)
                .textFieldStyle(.roundedBorder)
            photoPicker
            Button("現在地で記録") {
                let lengthMeters = measure(length)
                let widthMeters = measure(width)
                let heightMeters = measure(height)
                guard lengthMeters != .invalid, widthMeters != .invalid, heightMeters != .invalid else {
                    formNote = "延長・幅・高さは数字で入れてください。空欄は未計測です。"
                    return
                }
                formNote = nil
                field.recordDisasterSite(
                    kind: kind,
                    length: lengthMeters.value,
                    width: widthMeters.value,
                    height: heightMeters.value,
                    note: note,
                    photo: photoData
                )
            }
            .buttonStyle(DisasterButtonStyle(fill: SurveyColor.red))
            if let formNote {
                Text(formNote)
                    .font(SurveyType(13, .heavy))
                    .foregroundStyle(SurveyColor.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if field.disasterSites.isEmpty {
                Text("被災箇所はまだありません。")
                    .font(SurveyType(14, .medium))
                    .foregroundStyle(SurveyColor.muted)
            } else {
                ForEach(field.disasterSites) { site in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(site.kind.label) \(site.author)")
                            .font(SurveyType(15, .heavy))
                            .foregroundStyle(SurveyColor.text)
                        Text(siteLine(site))
                            .font(SurveyType(13, .medium))
                            .foregroundStyle(SurveyColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(12)
        .background(SurveyColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var passageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("通行")
                .font(SurveyType(16, .heavy))
                .foregroundStyle(SurveyColor.text)
            Text("動いた跡は通れるとして地図に出します。進めない地点はここで止めます。")
                .font(SurveyType(14, .medium))
                .foregroundStyle(SurveyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button("ここで止まった") {
                field.markRoadClosed()
            }
            .buttonStyle(DisasterButtonStyle(fill: SurveyColor.amber))
        }
        .padding(12)
        .background(SurveyColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("文字")
                .font(SurveyType(16, .heavy))
                .foregroundStyle(SurveyColor.text)
            TextField("短く伝える", text: $text)
                .textFieldStyle(.roundedBorder)
            Button("中継する") {
                field.sendDisasterText(text)
                text = ""
            }
            .buttonStyle(DisasterButtonStyle(fill: SurveyColor.card))
            if field.disasterTexts.isEmpty {
                Text("届いた文字はまだありません。")
                    .font(SurveyType(14, .medium))
                    .foregroundStyle(SurveyColor.muted)
            } else {
                ForEach(field.disasterTexts.prefix(8)) { item in
                    Text("\(item.author) \(item.body)")
                        .font(SurveyType(14, .medium))
                        .foregroundStyle(SurveyColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .background(SurveyColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("書き出し")
                .font(SurveyType(16, .heavy))
                .foregroundStyle(SurveyColor.text)
            Text("被災状況の PDF と CSV、災害査定へ転記する写真帳簿です。様式そのものは作らず、提出もしません。")
                .font(SurveyType(14, .medium))
                .foregroundStyle(SurveyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button("PDF、CSV、写真帳簿を書く") {
                field.exportDisasterReports()
            }
            .buttonStyle(DisasterButtonStyle(fill: SurveyColor.green))
        }
        .padding(12)
        .background(SurveyColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var tileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("地図")
                .font(SurveyType(16, .heavy))
                .foregroundStyle(SurveyColor.text)
            Text(field.downloadMessage)
                .font(SurveyType(14, .medium))
                .foregroundStyle(SurveyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button(field.isDownloading ? "保存中" : "この範囲を端末に保存") {
                field.downloadVisibleArea()
            }
            .buttonStyle(DisasterButtonStyle(fill: SurveyColor.card))
            .disabled(field.isDownloading || field.batterySaver)
        }
        .padding(12)
        .background(SurveyColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func measureField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SurveyType(12, .heavy))
                .foregroundStyle(SurveyColor.muted)
            TextField("m", text: text)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
        }
    }

    @ViewBuilder
    private var photoPicker: some View {
        #if canImport(PhotosUI)
        PhotosPicker(selection: $photo, matching: .images) {
            Text(photoData == nil ? "写真を選ぶ" : "写真を選び直す")
                .font(SurveyType(15, .heavy))
                .foregroundStyle(SurveyColor.text)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(SurveyColor.background)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                await MainActor.run { photoData = data }
            }
        }
        #else
        EmptyView()
        #endif
    }

    private func measure(_ text: String) -> MeasureField {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")) else { return .invalid }
        return .value(value)
    }

    private func siteLine(_ site: DisasterSite) -> String {
        let length = site.measure.lengthMeters.map { String(format: "延長 %.1fm", $0) } ?? "延長 未記録"
        let width = site.measure.widthMeters.map { String(format: "幅 %.1fm", $0) } ?? "幅 未記録"
        let height = site.measure.heightMeters.map { String(format: "高さ %.1fm", $0) } ?? "高さ 未記録"
        let photo = site.photoFile == nil ? "写真なし" : "写真あり"
        return "\(length) \(width) \(height) \(photo) \(site.note)"
    }
}

private enum MeasureField: Equatable {
    case empty
    case value(Double)
    case invalid

    var value: Double? {
        if case .value(let meters) = self { return meters }
        return nil
    }
}

struct DisasterButtonStyle: ButtonStyle {
    var fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SurveyType(16, .heavy))
            .foregroundStyle(SurveyColor.text)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(fill.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

final class DisasterSiteAnnotation: NSObject, MKAnnotation {
    let siteID: UUID
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let title: String?
    let kind: DisasterKind

    init(site: DisasterSite) {
        siteID = site.id
        coordinate = CLLocationCoordinate2D(latitude: site.latitudeDegrees, longitude: site.longitudeDegrees)
        title = site.kind.label
        kind = site.kind
        super.init()
    }
}

final class DisasterPeerAnnotation: NSObject, MKAnnotation {
    let deviceID: String
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let title: String?

    init(position: DisasterPosition) {
        deviceID = position.deviceID
        coordinate = CLLocationCoordinate2D(latitude: position.latitudeDegrees, longitude: position.longitudeDegrees)
        title = position.name
        super.init()
    }
}

final class PassageMarkAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let title: String?
    let state: PassageState

    init(point: PassagePoint, state: PassageState, author: String) {
        coordinate = CLLocationCoordinate2D(latitude: point.latitudeDegrees, longitude: point.longitudeDegrees)
        title = "\(state.label) \(author)"
        self.state = state
        super.init()
    }
}
