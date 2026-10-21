import SwiftUI
import SurveyCore

/// 画面に置ききれない説明。設定と、各画面の (i) から同じ文を出す。
enum FieldHelp: String, CaseIterable, Identifiable {
    case gps
    case benchmark
    case coordinates
    case accuracy
    case level
    case ar
    case batter
    case stature
    case pace
    case extras
    case delivery
    case points
    case stakeout
    case alignment
    case sima
    case arbitrary

    var id: String { rawValue }

    static let groups: [FieldHelpGroup] = [
        FieldHelpGroup(title: "GPS精度", items: [.gps, .accuracy, .benchmark]),
        FieldHelpGroup(title: "図面合わせ", items: [.alignment]),
        FieldHelpGroup(title: "SIMA", items: [.sima]),
        FieldHelpGroup(title: "丁張", items: [.batter, .stakeout, .arbitrary]),
        FieldHelpGroup(title: "記録", items: [.points, .delivery]),
        FieldHelpGroup(title: "測り方", items: [.coordinates, .level, .ar, .stature, .pace]),
        FieldHelpGroup(title: "その他", items: [.extras])
    ]

    var title: String {
        switch self {
        case .gps: return "測位"
        case .benchmark: return "三角点"
        case .coordinates: return "座標"
        case .accuracy: return "要求精度"
        case .level: return "水準器"
        case .ar: return "AR位置出し"
        case .batter: return "丁張"
        case .stature: return "身長"
        case .pace: return "歩測"
        case .extras: return "追加機能"
        case .delivery: return "書き出し"
        case .points: return "点の記録"
        case .stakeout: return "測設"
        case .alignment: return "2点合わせ"
        case .sima: return "SIMA"
        case .arbitrary: return "任意点"
        }
    }

    var body: String {
        switch self {
        case .gps:
            return "上の1行は解と水平の自己推定です。iPhone の ± は端末の見積もりで、実際の誤差は既知点で確認します。色は今の作業の要求に対する色で、緑は要求以内、黄は2倍以内、赤はそれより粗いです。足りない長さと届く手段は、その行をタップすると出ます。iPhone の GPS は単独で、数mの下見に使います。"
        case .benchmark:
            return "三角点をタップすると、検証の記録を始めます。近くに見本の点が無いときは、地図を引いて探します。毎回、置き直して向きを変えます。1秒に1点取り、選んだ時間で止まります。"
        case .coordinates:
            return "\(CoordinateText.previewNote)。\(CoordinateText.storageNote)。"
        case .accuracy:
            return "仮の既定値です。現場に合わせて直すと、SitePack の work-requirements.json に残ります。三角点で報告が楽観的だった機器は、この倍率をかけてから要求と比べます。"
        case .level:
            return "±0.1°以内のとき、十字線は目の高さの水平線です。傾斜は、同じ傾きのまま端末を180°回して二回読み、ゼロ点をその平均にします。未校正だと20mの誤差は校正後より大きく出ます。器械高は、自分の標高に目の高さを足した値です。読み値が目の高さなら高低差は 0 です。距離が空欄のときは、LiDAR か ARKit の距離を使います。距離と仰角が揃うと高低差を出します。"
        case .ar:
            return "座標簿の点か、図面でタップした点に仮想の杖を立てます。既知点を選び、その点の地面を画面でタップします。2点以上が推奨です。声は画面の上を前にし、方向が変わったときだけです。RTK FIX のあいだは、向きを保って位置を足し続けます。"
        case .batter:
            return "楕円体高のある基準点か、座標簿の点でゼロを合わせます。標高だけしか無い点は使いません。オフセット +0.50 で貫は 50cm 上です。勾配は 1m あたりで、+0.02 は 2% です。向きが空なら勾配は足しません。許容は既定 ±5mm です。十字線は水平（±0.1°）のときだけ高さに使い、器械高は標高に目の高さを足した値です。"
        case .stature:
            return "iPhone だけで、端末の高さから持ち高さを引いてから、ジオイドを引いて標高にします。既定は画面の角度です。鉛直で視線が水平のときは、端末の高さを目の高さにします。肘より上は代わりです。外部GNSSのポール高とは別にします。身長を一度入れると、歩幅の初期値も身長×0.45で入ります。この値は端末の中だけに残し、共有しません。画面の角度は目の高さ（身長から引く長さ）を使います。肘より上と胸の前は身長×係数。運転席は、オペ画面の視線高とは別に、既定 2m です。既知の楕円体高の点で、今の持ち方のまま1回観測すると、端末の高さと既知高さの差が肘より上の係数になります。歩幅は、平らな所で分かっている距離を歩いて合わせます。"
        case .pace:
            return "歩数は実機で数えます。歩数が取れない端末では手で入れ、歩行推測は始めません。勾配は 1m あたりで、平らなら 0 です。補正係数が空なら勾配から決めます。校正は「自分の校正」です。段階は 0 で、測設の合格にはしません。"
        case .extras:
            return "測量の画面が先です。座標簿、図面、測設、基準点、出力、オペ画面は、ここのスイッチに関係なく動きます。無線、接近、転倒、SOS、災害、中継、統計は追加機能です。既定ではオフで、測量の画面には出ません。オンにした機能だけが、その画面に足されます。"
        case .delivery:
            return "受取手が今受け取れる形だけ出します。\(CoordinateDelivery.pointCloudNote) 平面直角座標で書きます。JGD2024 の元期補正は、まだ掛けていません。絞り込みの条件はすべて同時に効きます。空欄は無視します。"
        case .points:
            return "下の記録は、今の緯度・経度・標高・精度・時刻を残します。詳細には楕円体高と使ったジオイドを残します。場所と日付のフォルダと、出す画面の座標簿に入ります。場所は設定で直せます。測る画面の点名は、頭のアルファベットと連番です。"
        case .stakeout:
            return "追加距離を張り、現在地を No.23+5.0m 左 3.2m のように出します。座標簿で合わせてある図面は cm で出します。この点がオペの目標です。作業半径の内と外を色で出します。声は画面の上を前にし、方向が変わったときだけです。"
        case .alignment:
            return "図面の2点と SIMA の2点で、移動・回転・縮尺を決めます。図面の距離と SIMA の距離、差（mm）、比を出します。許容は mm と 1/N です。両方に入ると OK、外れると要確認です。保存は止めません。合わせた図面は、その系で地図に載ります。"
        case .sima:
            return "A01 の北・東を、現場の系（既定は VII）で緯度経度にします。点名の GL / FH、別の点、高さの列から地盤高と計画高を分けます。列の意味が決まらないときは、取り込みのときに選びます。地図の札に FH を出せます。丁張では FH、標高、その差を盛土または切土で出します。"
        case .arbitrary:
            return "合わせた図面で、端点・交点・線上、または長押しの位置に任意点を置けます。平面直角の X Y と、入れた計画高を現場に残します。丁張へで、距離と方向の案内に送ります。"
        }
    }
}

struct InfoButton: View {
    let help: FieldHelp
    @State private var shown = false

    var body: some View {
        Button {
            shown = true
        } label: {
            Image(systemName: "info.circle")
                .font(SurveyType(18, .bold))
                .frame(width: 44, height: 44)
                .foregroundStyle(SurveyColor.text)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(help.title)の説明")
        .sheet(isPresented: $shown) {
            NavigationStack {
                HelpPage(help: help)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") { shown = false }
                                .font(SurveyType(17, .heavy))
                        }
                    }
            }
            .modifier(SurveyScheme())
        }
    }
}

struct HelpLabel: View {
    let title: String
    let help: FieldHelp

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(SurveyType(18, .heavy))
            InfoButton(help: help)
            Spacer(minLength: 0)
        }
    }
}

struct HelpPage: View {
    let help: FieldHelp

    var body: some View {
        ScrollView {
            Text(help.body)
                .font(SurveyType(16, .semibold))
                .foregroundStyle(SurveyColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .background(SurveyColor.background)
        .navigationTitle(help.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FieldHelpGroup: Identifiable {
    var title: String
    var items: [FieldHelp]
    var id: String { title }
}

enum FieldMenuNext {
    case stature
    case extras
    case tools
    case privacy
    case crosshair
    case batter
    case ar
    case pace
    case download
}

struct FieldMenuSheet: View {
    @ObservedObject var field: FieldModel
    @ObservedObject var appearance: SurveyAppearance
    @Binding var next: FieldMenuNext?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    functionRow("プロジェクト", icon: "folder") {
                        field.showsProjects = true
                        dismiss()
                    }
                    functionLink("表示", icon: "circle.lefthalf.filled") {
                        DisplaySettings(field: field, appearance: appearance)
                    }
                    functionRow(field.statureNotice ?? "身長", icon: "figure.stand") { handoff(.stature) }
                    functionLink("許容範囲", icon: "ruler") {
                        ToleranceSettings(drawing: field.drawing)
                    }
                    functionLink("場所名", icon: "mappin") {
                        PlaceSettings(field: field)
                    }
                    functionLink("外部受信機", icon: "antenna.radiowaves.left.and.right") {
                        ExternalReceiverSettings(field: field)
                    }
                    functionRow("追加機能", icon: "switch.2") { handoff(.extras) }
                    functionRow("ボタンの並び", icon: "square.grid.2x2") { handoff(.tools) }
                    functionRow("位置の共有", icon: "location") { handoff(.privacy) }
                    if field.extras.disaster {
                        functionRow("災害", icon: "exclamationmark.triangle") {
                            field.showsDisaster = true
                            dismiss()
                        }
                    }
                    if field.extras.stats || field.extras.accidentReport {
                        functionRow(field.extras.stats ? "統計" : "事故報告", icon: "chart.bar") {
                            field.showsIncidentStats = true
                            dismiss()
                        }
                    }
                    if field.extras.pushToTalk {
                        Toggle(isOn: Binding(
                            get: { field.radio.spaceAudio },
                            set: { field.radio.setSpaceAudio($0) }
                        )) {
                            Label("定位", systemImage: "ear")
                                .font(SurveyType(18, .heavy))
                        }
                        .tint(SurveyColor.blue)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    Text("説明")
                        .font(SurveyType(15, .heavy))
                        .foregroundStyle(SurveyColor.muted)
                        .padding(.top, 12)
                    ForEach(FieldHelp.groups) { group in
                        DisclosureGroup(group.title) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(group.items) { help in
                                    Text(help.title)
                                        .font(SurveyType(15, .heavy))
                                        .foregroundStyle(SurveyColor.text)
                                    Text(help.body)
                                        .font(SurveyType(14, .semibold))
                                        .foregroundStyle(SurveyColor.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.top, 6)
                        }
                        .font(SurveyType(17, .heavy))
                        .foregroundStyle(SurveyColor.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(16)
            }
            .background(SurveyColor.background)
            .navigationTitle("設定")
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

    private func functionRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            functionLabel(title, icon: icon, trailing: "chevron.right")
        }
        .buttonStyle(.plain)
    }

    private func functionLink<Destination: View>(_ title: String, icon: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            functionLabel(title, icon: icon, trailing: "chevron.right")
        }
        .buttonStyle(.plain)
    }

    private func functionLabel(_ title: String, icon: String, trailing: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(SurveyType(18, .bold))
                .frame(width: 28)
            Text(title)
                .font(SurveyType(18, .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            Image(systemName: trailing)
                .font(SurveyType(14, .bold))
                .foregroundStyle(SurveyColor.muted)
        }
        .foregroundStyle(SurveyColor.text)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func handoff(_ next: FieldMenuNext) {
        self.next = next
        dismiss()
    }
}

private struct DisplaySettings: View {
    @ObservedObject var field: FieldModel
    @ObservedObject var appearance: SurveyAppearance

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Button(appearance.label) { appearance.cycle() }
                    .buttonStyle(SurveyPlainButton())
                if let position = field.reading.position, position.isPlottable {
                    let height = field.liveSurveyHeight(position)
                    Text(height.primaryLine)
                        .font(SurveyType(18, .heavy, mono: true))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    ForEach(height.detailLines, id: \.self) { line in
                        Text(line)
                            .font(SurveyType(15, .semibold))
                            .foregroundStyle(SurveyColor.muted)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    if let orthometric = position.meanSeaLevelMeters,
                       let gsi = height.orthometricMeters,
                       let line = NMEA.receiverGapLine(receiverOrthometricMeters: orthometric, gsiOrthometricMeters: gsi),
                       position.receiver != .iphoneGPS {
                        Text(line)
                            .font(SurveyType(15, .semibold))
                            .foregroundStyle(SurveyColor.muted)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }
            }
            .padding(16)
        }
        .background(SurveyColor.background)
        .navigationTitle("表示")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ToleranceSettings: View {
    @ObservedObject var drawing: DrawingSession
    @State private var millimeters = ""
    @State private var denominator = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("mm", text: $millimeters)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
            TextField("1/N", text: $denominator)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
            Spacer()
        }
        .padding(16)
        .background(SurveyColor.background)
        .navigationTitle("許容範囲")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            millimeters = String(format: "%g", drawing.tolerance.millimeters)
            denominator = String(format: "%g", drawing.tolerance.denominator)
        }
        .onChange(of: millimeters) { _, _ in commit() }
        .onChange(of: denominator) { _, _ in commit() }
    }

    private func commit() {
        guard let mm = Double(millimeters), let ratio = Double(denominator) else { return }
        drawing.setTolerance(millimeters: mm, denominator: ratio)
    }
}

private struct PlaceSettings: View {
    @ObservedObject var field: FieldModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("場所名", text: Binding(
                get: { field.recordPlace },
                set: { field.setRecordPlace($0) }
            ))
            .font(SurveyType(18, .heavy))
            .padding(10)
            .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button("現在地") { field.useNearbyPlaceName() }
                .buttonStyle(SurveyPlainButton())
            Spacer()
        }
        .padding(16)
        .background(SurveyColor.background)
        .navigationTitle("場所名")
        .navigationBarTitleDisplayMode(.inline)
    }
}
