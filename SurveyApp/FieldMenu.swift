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

    var id: String { rawValue }

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
        }
    }

    var body: String {
        switch self {
        case .gps:
            return "上の1行は解と水平精度です。色は今の作業の要求に対する色で、緑は要求以内、黄は2倍以内、赤はそれより粗いです。足りない長さと届く手段は、その行をタップすると出ます。段階は機器の目安で、色とは別にします。iPhone の GPS は単独で、数mの下見に使います。"
        case .benchmark:
            return "三角点をタップすると、検証の記録を始めます。近くに見本の点が無いときは、地図を引いて探します。毎回、置き直して向きを変えます。1秒に1点取り、選んだ時間で止まります。"
        case .coordinates:
            return "\(CoordinateText.previewNote)。\(CoordinateText.storageNote)。"
        case .accuracy:
            return "仮の既定値です。現場に合わせて直すと、SitePack の work-requirements.json に残ります。三角点で報告が楽観的だった機器は、この倍率をかけてから要求と比べます。"
        case .level:
            return "±0.1°以内のとき、十字線は目の高さの水平線です。傾斜は、同じ傾きのまま端末を180°回して二回読み、ゼロ点をその平均にします。未校正だと20mの誤差は校正後より大きく出ます。器械高は、自分の地盤高に目の高さを足した値です。読み値が目の高さなら高低差は 0 です。距離が空欄のときは、LiDAR か ARKit の距離を使います。距離と仰角が揃うと高低差を出します。"
        case .ar:
            return "座標簿の点か、図面でタップした点に仮想の杖を立てます。既知点を選び、その点の地面を画面でタップします。2点以上が推奨です。声は画面の上を前にし、方向が変わったときだけです。RTK FIX のあいだは、向きを保って位置を足し続けます。"
        case .batter:
            return "楕円体高のある基準点か、座標簿の点でゼロを合わせます。標高だけしか無い点は使いません。オフセット +0.50 で貫は 50cm 上です。勾配は 1m あたりで、+0.02 は 2% です。向きが空なら勾配は足しません。許容は既定 ±5mm です。十字線は水平（±0.1°）のときだけ高さに使い、器械高は地盤高に目の高さを足した値です。"
        case .stature:
            return "iPhone だけで、端末の高さから持ち高さを引いて地盤高にします。既定は画面の角度です。鉛直で視線が水平のときは、端末の高さを目の高さにします。肘より上は代わりです。外部GNSSのポール高とは別にします。身長を一度入れると、歩幅の初期値も身長×0.45で入ります。この値は端末の中だけに残し、共有しません。画面の角度は目の高さ（身長から引く長さ）を使います。肘より上と胸の前は身長×係数。運転席は、オペ画面の視線高とは別に、既定 2m です。既知の楕円体高の点で、今の持ち方のまま1回観測すると、端末の高さと既知高さの差が肘より上の係数になります。歩幅は、平らな所で分かっている距離を歩いて合わせます。"
        case .pace:
            return "歩数は実機で数えます。歩数が取れない端末では手で入れ、歩行推測は始めません。勾配は 1m あたりで、平らなら 0 です。補正係数が空なら勾配から決めます。校正は「自分の校正」です。段階は 0 で、測設の合格にはしません。"
        case .extras:
            return "測量の画面が先です。座標簿、図面、測設、基準点、出力、オペ画面は、ここのスイッチに関係なく動きます。無線、接近、転倒、SOS、災害、中継、統計は追加機能です。既定ではオフで、測量の画面には出ません。オンにした機能だけが、その画面に足されます。"
        case .delivery:
            return "受取手が今受け取れる形だけ出します。\(CoordinateDelivery.pointCloudNote) 平面直角座標で書きます。JGD2024 の元期補正は、まだ掛けていません。絞り込みの条件はすべて同時に効きます。空欄は無視します。"
        case .points:
            return "今の作業で点を残します。点名は頭のアルファベットと連番です。下見で取った点は捨てず、あとから測量点の座標に乗せ替えられます。基準点は段階2の RTK FIX のあいだだけ残せます。解が落ちて段階が下がると記録は止まり、測位は続きます。iPhone の GPS では衛星数・PDOP・補正の遅れは出ません。"
        case .stakeout:
            return "追加距離を張り、現在地を No.23+5.0m 左 3.2m のように出します。座標簿で合わせてある図面は cm で出します。この点がオペの目標です。作業半径の内と外を色で出します。声は画面の上を前にし、方向が変わったときだけです。"
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

enum FieldMenuNext {
    case stature
    case extras
    case tools
    case privacy
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
                    menuButton(appearance.label) { appearance.cycle() }
                    menuButton("身長") { handoff(.stature) }
                    menuButton("追加機能") { handoff(.extras) }
                    menuButton("ボタンの並び") { handoff(.tools) }
                    menuButton("位置の共有") { handoff(.privacy) }
                    Text("説明")
                        .font(SurveyType(15, .heavy))
                        .foregroundStyle(SurveyColor.muted)
                        .padding(.top, 8)
                    ForEach(FieldHelp.allCases) { help in
                        NavigationLink {
                            HelpPage(help: help)
                        } label: {
                            Text(help.title)
                                .font(SurveyType(16, .heavy))
                                .foregroundStyle(SurveyColor.text)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .padding(.horizontal, 12)
                                .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
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

    private func menuButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(SurveyType(18, .heavy))
                .foregroundStyle(SurveyColor.text)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12)
                .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func handoff(_ next: FieldMenuNext) {
        self.next = next
        dismiss()
    }
}
