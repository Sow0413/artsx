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
    @State private var customMount = ""
    @State private var mounts: [String] = []
    @State private var mountNote = ""
    @State private var listing = false
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
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    labeled("ViDoc", session.vidocLine, id: "vidoc-status")
                    labeled("NTRIP", session.ntripLine, id: "ntrip-status")
                }

                Section {
                    Toggle("補正", isOn: $enabled)
                        .font(SurveyType(16, .heavy))
                    field("接続先", text: $host)
                    field("ポート", text: $portText, numbers: true)
                    Picker("マウント", selection: Binding(get: { mountpoint }, set: { mountpoint = $0; customMount = "" })) {
                        ForEach(RTKMountpoint.allCases) { point in
                            Text(point.rawValue).tag(point)
                        }
                    }
                    .font(SurveyType(16, .heavy))
                    field("マウント名", text: $customMount)
                    Button(action: fetchMounts) {
                        Text(listing ? "一覧を取得中" : "マウント一覧を取得")
                            .font(SurveyType(16, .heavy))
                    }
                    .disabled(listing)
                    if !mountNote.isEmpty {
                        Text(mountNote)
                            .font(SurveyType(13, .semibold))
                            .foregroundStyle(SurveyColor.amber)
                    }
                    ForEach(mounts, id: \.self) { name in
                        Button(name) {
                            customMount = name
                            if let known = RTKMountpoint(rawValue: name) { mountpoint = known }
                        }
                        .font(SurveyType(16, .heavy))
                    }
                    field("ID", text: $user)
                    LabeledContent("パスワード") {
                        SecureField("パスワード", text: $password)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(SurveyType(16, .heavy))
                    Text(password.isEmpty ? "未入力" : "入力済み（欄は伏せます）")
                        .font(SurveyType(13, .semibold))
                        .foregroundStyle(SurveyColor.muted)
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

                if !session.ntripLine.isEmpty, session.ntripLine != "未接続", session.ntripLine != "認証中", !session.ntripLine.hasPrefix("補正受信中"), !session.ntripLine.hasPrefix("NTRIP 接続") {
                    Section {
                        Text(session.ntripLine)
                            .font(SurveyType(14, .heavy))
                            .foregroundStyle(SurveyColor.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle("RTK")
            .accessibilityIdentifier("rtk-settings")
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

    private func labeled(_ title: String, _ value: String, id: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(SurveyType(15, .heavy))
                .foregroundStyle(SurveyColor.muted)
            Text(value)
                .font(SurveyType(15, .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .accessibilityIdentifier(id)
            Spacer(minLength: 0)
        }
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
        if session.mode == .rtk, !session.deviceConnected { return session.vidocLine }
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
        customMount = stored.customMount ?? ""
        user = stored.user
        if password.isEmpty { password = RTKKeychain.load(user: stored.user) }
    }

    private func connect() {
        let port = UInt16(portText) ?? 2101
        let typed = password.isEmpty ? RTKKeychain.load(user: user) : password
        password = typed
        let settings = RTKSettings(correctionsEnabled: enabled, host: host, port: port,
                                   mountpoint: mountpoint,
                                   customMount: customMount.trimmingCharacters(in: .whitespacesAndNewlines),
                                   user: user)
        RTKSettingsStore.save(settings, to: siteDirectory)
        if !typed.isEmpty { RTKKeychain.save(user: user, password: typed) }
        session.connectRTK(settings: settings, password: typed)
    }

    private func fetchMounts() {
        listing = true
        let port = UInt16(portText) ?? 2101
        let typed = password.isEmpty ? RTKKeychain.load(user: user) : password
        let config = NTRIPClient.Config(host: host, port: port, mountpoint: "", user: user, password: typed)
        NTRIPClient.fetchMounts(config: config) { names, failure in
            DispatchQueue.main.async {
                listing = false
                mounts = names
                mountNote = names.isEmpty ? (failure ?? "") : ""
            }
        }
    }
}
#endif
