import MapKit
import SwiftUI
import SurveyCore

struct RepeaterSheet: View {
    @ObservedObject var field: FieldModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle(isOn: Binding(
                        get: { field.repeaterMode },
                        set: { field.setRepeaterMode($0) }
                    )) {
                        Text("中継専用")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(SurveyColor.text)
                    }
                    .tint(SurveyColor.amber)
                    Text(RepeaterPosture.condition)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SurveyColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(RepeaterPosture.powerNote)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SurveyColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(RepeaterPosture.sosNote)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SurveyColor.amber)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("ここに設置") {
                        field.installRepeaterHere()
                    }
                    .buttonStyle(DisasterButtonStyle(fill: SurveyColor.amber))
                    if let install = field.repeaterInstall {
                        Text("設置 \(install.name) \(String(format: "%.5f", install.latitudeDegrees)), \(String(format: "%.5f", install.longitudeDegrees))")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(SurveyColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("設置位置はまだありません。")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(SurveyColor.muted)
                    }
                    Text(batteryLine)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(SurveyColor.text)
                    Text("隣接の接続は、届いた時刻で見ます。電波の強さそのものではありません。")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SurveyColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if field.repeaterLinks.isEmpty {
                        Text("隣接の中継はまだ見えません。")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(SurveyColor.muted)
                    } else {
                        ForEach(field.repeaterLinks) { link in
                            Text("\(link.name) \(link.grade.label) 電池\(battery(link.batteryPercent))")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(SurveyColor.text)
                        }
                    }
                    Toggle(isOn: Binding(
                        get: { field.loraCertified },
                        set: { field.setLoRaCertified($0) }
                    )) {
                        Text("920MHz帯の技適品")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(SurveyColor.text)
                    }
                    .tint(SurveyColor.green)
                    Text(LoRaPolicy.certifiedNote)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SurveyColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(LoRaPolicy.voiceNote)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(SurveyColor.amber)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("位置・SOS・短文だけを、BLEでMeshtastic互換ノードへ渡します。ノード側のホップは3まで。")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SurveyColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(field.loraStatus)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SurveyColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let message = field.disasterMessage {
                        Text(message)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SurveyColor.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
            .background(SurveyColor.background)
            .navigationTitle("中継専用")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private var batteryLine: String {
        let percent = field.repeaterBattery.map { "\($0)%" } ?? "不明"
        let charging = field.repeaterCharging ? " 充電中" : ""
        return "この端末の電池 \(percent)\(charging)"
    }

    private func battery(_ percent: Int?) -> String {
        percent.map { "\($0)%" } ?? "不明"
    }
}

struct RepeaterCover: View {
    @ObservedObject var field: FieldModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("中継中")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(Color.white)
                Text(batteryLine)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Color.white)
                Text("隣接 \(field.repeaterLinks.filter { $0.grade != .lost }.count)台")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Color.white.opacity(0.8))
                Text(RepeaterPosture.condition)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                Button("地図を見る") {
                    field.repeaterDimmed = false
                }
                .buttonStyle(DisasterButtonStyle(fill: SurveyColor.card))
                Button("中継をやめる") {
                    field.setRepeaterMode(false)
                }
                .buttonStyle(DisasterButtonStyle(fill: SurveyColor.red))
            }
            .padding(24)
        }
    }

    private var batteryLine: String {
        let percent = field.repeaterBattery.map { "電池 \($0)%" } ?? "電池 不明"
        return field.repeaterCharging ? "\(percent) 充電中" : percent
    }
}

final class RepeaterInstallAnnotation: NSObject, MKAnnotation {
    let deviceID: String
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(deviceID: String, coordinate: CLLocationCoordinate2D, title: String, subtitle: String) {
        self.deviceID = deviceID
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        super.init()
    }
}

final class RepeaterPeerAnnotation: NSObject, MKAnnotation {
    let peerID: String
    let grade: LinkGrade
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(peerID: String, grade: LinkGrade, coordinate: CLLocationCoordinate2D, title: String, subtitle: String) {
        self.peerID = peerID
        self.grade = grade
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        super.init()
    }
}
