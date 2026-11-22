import SwiftUI
import SurveyCore

// RTK の接続。受信機と NTRIP の値だけを出し、測地系の注意は (i) の中。
// 画面の精度は、つながったあとの位置が既存のバッジへそのまま入る。

#if !SURVEY_PLAYGROUND && canImport(CoreBluetooth) && canImport(Network)
struct RTKSettingsView: View {
    @ObservedObject var session: RTKPositionSession
    let siteDirectory: URL
    @Environment(\.dismiss) private var dismiss

    @State private var enabled = true
    @State private var host = "d-gnss.jp"
    @State private var portText = "2101"
    @State private var mountpoint: RTKMountpoint = .rrsgd2024
    @State private var user = ""
    @State private var password = ""
    @State private var showsNote = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(statusLine)
                        .font(SurveyType(20, .heavy))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Section {
                    Toggle("補正", isOn: $enabled)
                        .font(SurveyType(16, .heavy))
                    field("接続先", text: $host)
                    field("ポート", text: $portText, numbers: true)
                    Picker("マウント", selection: $mountpoint) {
                        ForEach(RTKMountpoint.allCases) { point in
                            Text(point.rawValue).tag(point)
                        }
                    }
                    .font(SurveyType(16, .heavy))
                    field("ID", text: $user)
                    LabeledContent("パスワード") {
                        SecureField("パスワード", text: $password)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(SurveyType(16, .heavy))
                    Button {
                        showsNote = true
                    } label: {
                        Label("測地系", systemImage: "info.circle")
                            .font(SurveyType(16, .heavy))
                    }
                } header: {
                    Text("NTRIP")
                }

                Section {
                    if session.mode == .rtk {
                        Button(role: .destructive) {
                            session.disconnectRTK()
                        } label: {
                            Text("切断").frame(maxWidth: .infinity).font(SurveyType(18, .heavy))
                        }
                    } else {
                        Button(action: connect) {
                            Text("接続").frame(maxWidth: .infinity).font(SurveyType(18, .heavy))
                        }
                        .disabled(enabled && (user.isEmpty || password.isEmpty))
                    }
                }

                if session.message.contains("NG") {
                    Section {
                        Text(session.message)
                            .font(SurveyType(14, .heavy))
                            .foregroundStyle(SurveyColor.amber)
                    }
                }
            }
            .navigationTitle("RTK")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                        .font(SurveyType(17, .heavy))
                }
            }
            .onAppear(perform: loadSettings)
            .alert("RTK", isPresented: $showsNote) {
                Button("閉じる", role: .cancel) {}
            } message: {
                Text(note)
            }
        }
        .modifier(SurveyScheme())
    }

    private func field(_ title: String, text: Binding<String>, numbers: Bool = false) -> some View {
        LabeledContent(title) {
            TextField(title, text: text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(numbers ? .numberPad : .default)
        }
        .font(SurveyType(16, .heavy))
    }

    private var statusLine: String {
        if session.mode == .rtk, !session.deviceConnected { return "探索中" }
        guard let meters = session.horizontalAccuracyMeters, meters.isFinite, meters >= 0 else { return fixLabel }
        let approximate = !(session.mode == .rtk && session.fix == .rtkFix)
        return "\(fixLabel)　\(AccuracyFormat.label(meters: meters, approximate: approximate))"
    }

    private var fixLabel: String {
        switch session.fix {
        case .rtkFix: return "FIX"
        case .float: return "FLOAT"
        case .dgps: return "DGPS"
        case .clas: return "CLAS"
        case .standalone: return "単独"
        case .none: return "—"
        }
    }

    private var statusColor: Color {
        switch session.fix {
        case .rtkFix: return SurveyColor.green
        case .float, .dgps, .clas: return SurveyColor.amber
        default: return SurveyColor.text
        }
    }

    private var note: String {
        var lines = [
            mountpoint.datum2024 ? "測地成果2024。2011とは混ぜない。" : "測地成果2011。新規は2024。"
        ]
        if let count = session.satelliteCount { lines.append("衛星 \(count)") }
        if let age = session.correctionAgeSeconds { lines.append(String(format: "補正 %.0f秒", age)) }
        lines.append(session.ntripConnected ? "補正 受信中" : "補正 なし")
        if !session.message.isEmpty { lines.append(session.message) }
        return lines.joined(separator: "\n")
    }

    private func loadSettings() {
        let stored = RTKSettingsStore.load(from: siteDirectory)
        enabled = stored.correctionsEnabled
        host = stored.host
        portText = String(stored.port)
        mountpoint = stored.mountpoint
        user = stored.user
        if password.isEmpty { password = RTKKeychain.load(user: stored.user) }
    }

    private func connect() {
        let port = UInt16(portText) ?? 2101
        let settings = RTKSettings(correctionsEnabled: enabled, host: host, port: port,
                                   mountpoint: mountpoint, user: user)
        RTKSettingsStore.save(settings, to: siteDirectory)
        RTKKeychain.save(user: user, password: password)
        session.connectRTK(settings: settings, password: password)
    }
}
#endif
