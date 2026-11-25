import SwiftUI
import SurveyCore

/// 校正はアプリの中だけ。機器には書かない。
struct IMUCalibFlow: View {
    @ObservedObject var field: FieldModel
    var onClose: () -> Void
    @State private var step = 1
    @State private var aPitch = 0.0
    @State private var aRoll = 0.0
    @State private var bPitch = 0.0
    @State private var bRoll = 0.0
    @State private var aSigma = 0.0
    @State private var bSigma = 0.0
    @State private var aReady = false
    @State private var bReady = false
    @State private var aMag = IMUVector(0, 0, 0)
    @State private var bMag = IMUVector(0, 0, 0)
    @State private var message = ""
    @State private var sectors = Set<Int>()
    @State private var tiltSpan = 0.0
    @State private var headingText = "—"
    @State private var leanText = "—"
    @State private var bubbleText = "—"

    private var uiTest: Bool { ProcessInfo.processInfo.arguments.contains("-surveyUITest") }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if step == 1 { tiltCard }
            if step == 2 { magneticCard }
            if step == 3 { liveCard }
        }
    }

    private var tiltCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("傾きの校正（反転法）")
                .font(SurveyType(28, .heavy))
                .accessibilityIdentifier("screen-calib-tilt")
            Text(aReady ? "ポールを180°回して、また鉛直に" : "ポールを点に立て、気泡で鉛直に")
                .font(SurveyType(22, .heavy))
                .lineLimit(3)
            Text(aReady ? String(format: "B のばらつき %.3f°", bSigma) : String(format: "A のばらつき %.3f°", aSigma))
                .font(SurveyType(20, .heavy))
                .accessibilityIdentifier("calib-sigma")
            if !aReady {
                bigButton("A を読む", id: "calib-read-a") { readA() }
            } else if !bReady {
                bigButton("B を読む", id: "calib-read-b") { readB() }
            }
            if !message.isEmpty {
                Text(message).font(SurveyType(20, .heavy)).lineLimit(4).accessibilityIdentifier("calib-tilt-result")
            }
            if aReady && bReady {
                bigButton("保存", id: "calib-save", prominent: true) { saveTilt(overrideMagnet: false) }
                if message.contains("回して") {
                    Button("それでも使う") { saveTilt(overrideMagnet: true) }
                        .font(SurveyType(16, .heavy))
                        .accessibilityIdentifier("calib-override")
                }
            }
        }
    }

    private var magneticCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("方位の校正（磁気）")
                .font(SurveyType(28, .heavy))
                .accessibilityIdentifier("screen-calib-mag")
            Text("鉄・車・iPhone の近くを避けて。立てて1回転 → 傾けて1回転 → 逆に傾けて1回転")
                .font(SurveyType(20, .heavy))
                .lineLimit(4)
            sectorRing
            Text(String(format: "扇 %d/12　傾き幅 %.0f°", sectors.count, tiltSpan))
                .font(SurveyType(22, .heavy))
                .accessibilityIdentifier("calib-sectors")
            if !message.isEmpty {
                Text(message).font(SurveyType(20, .heavy)).lineLimit(3).accessibilityIdentifier("calib-mag-result")
            }
            if uiTest {
                bigButton("見本の回転", id: "calib-mock-spin") { mockSpin() }
            }
        }
    }

    private var liveCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("確かめ（ライブ）")
                .font(SurveyType(28, .heavy))
                .accessibilityIdentifier("screen-calib-live")
            Text("気泡 \(bubbleText)")
                .font(SurveyType(26, .heavy))
                .accessibilityIdentifier("calib-bubble")
            Text("方位 \(headingText)")
                .font(SurveyType(26, .heavy))
                .accessibilityIdentifier("calib-heading")
            Text("傾きの向き \(leanText)")
                .font(SurveyType(22, .heavy))
                .lineLimit(2)
            Text("直近5回の中央値。iPhone の方位との差が10°を超えたら、磁気の校正をやり直す。")
                .font(SurveyType(16, .semibold))
                .foregroundStyle(SurveyColor.muted)
                .lineLimit(3)
            bigButton("閉じる", id: "calib-close") { onClose() }
        }
    }

    private var sectorRing: some View {
        HStack(spacing: 4) {
            ForEach(0..<12, id: \.self) { index in
                Circle()
                    .fill(sectors.contains(index) ? SurveyColor.blue : SurveyColor.line)
                    .frame(width: 18, height: 18)
            }
        }
        .accessibilityIdentifier("calib-ring")
    }

    private func readA() {
        if uiTest {
            aPitch = 1.0
            aRoll = 0.2
            aSigma = 0.02
            aMag = IMUVector(0, 0, 200)
        } else if let tilt = field.tiltDegrees {
            aPitch = tilt
            aRoll = 0
            aSigma = 0
            aMag = IMUVector(0, 0, 0)
        }
        guard aSigma <= 0.1 else {
            message = "動かさずに読み直し"
            return
        }
        aReady = true
        message = ""
    }

    private func readB() {
        if uiTest {
            bPitch = 1.1
            bRoll = 0.1
            bSigma = 0.02
            bMag = IMUVector(100, 0, 200)
        } else if let tilt = field.tiltDegrees {
            bPitch = tilt
            bRoll = 0
            bSigma = 0
            bMag = IMUVector(0, 0, 0)
        }
        guard bSigma <= 0.1 else {
            message = "動かさずに読み直し"
            return
        }
        bReady = true
        let turned = IMUCalib.magnetometerSeparation(aMag, bMag)
        if turned < 60 {
            message = "回していないように見えます"
            return
        }
        let result = IMUCalib.reversal(aPitch: aPitch, aRoll: aRoll, bPitch: bPitch, bRoll: bRoll)
        message = String(format: "引かないと 2m で %.0fmm", result.missMillimetresAtTwoMeters)
    }

    private func saveTilt(overrideMagnet: Bool) {
        let turned = IMUCalib.magnetometerSeparation(aMag, bMag)
        if turned < 60, !overrideMagnet {
            message = "回していないように見えます"
            return
        }
        let result = IMUCalib.reversal(aPitch: aPitch, aRoll: aRoll, bPitch: bPitch, bRoll: bRoll)
        let record = IMUCalibrationRecord(
            hardwareID: DeviceIdentity.machine,
            bleName: "ViDoc",
            recordedAt: Date(),
            temperatureCelsius: nil,
            biasPitch: result.biasPitch,
            biasRoll: result.biasRoll,
            hardIronX: 0,
            hardIronY: 0,
            hardIronZ: 0,
            residualRatio: nil,
            magneticPassed: false
        )
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? IMUCalibrationStore.append(record, to: documents)
        }
        message = ""
        step = 2
    }

    private func mockSpin() {
        sectors = Set(0..<10)
        tiltSpan = 20
        message = ""
        step = 3
        bubbleText = "0.12°　2mで 4mm"
        headingText = "北 12°"
        leanText = "出さない（0.2°未満）"
    }

    private func bigButton(_ title: String, id: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(SurveyType(22, .heavy))
                .frame(maxWidth: .infinity, minHeight: 72)
                .background(prominent ? SurveyColor.blue : SurveyColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(prominent ? SurveyColor.onAccent : SurveyColor.text)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
