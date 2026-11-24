import SwiftUI
import SurveyCore

#if !SURVEY_PLAYGROUND && canImport(CoreMotion)
import CoreMotion
#endif

/// カメラ位置、アンテナ高、現場高さ補正。1画面。
struct InstrumentSetupForm: View {
    @ObservedObject var field: FieldModel
    @State private var hText = ""
    @State private var source = ""
    @State private var version = ""
    @State private var dateText = ""
    @State private var poleText = "2.000"
    @State private var laserText = ""
    @State private var customX = ""
    @State private var customY = ""
    @State private var customZ = ""

    private var customOnly: Bool { CameraOffset.customOnly(machine: DeviceIdentity.machine) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
        Text("カメラ位置とアンテナ高と現場高さ補正を残す。")
            .font(SurveyType(18, .heavy))
            .lineLimit(2)
            .accessibilityIdentifier("purpose-setup")
        Text(customOnly ? "この機種は Custom だけです。" : "SPC+ は iPhone 15 Pro Max の公開値です。")
            .font(SurveyType(16, .semibold))
            .foregroundStyle(SurveyColor.muted)
            .lineLimit(2)
        Picker("カメラ", selection: cameraKind) {
            if !customOnly {
                Text("SPC+").tag("spcPlus")
                Text("SPC").tag("spc")
            }
            Text("Custom").tag("custom")
        }
        .accessibilityIdentifier("camera-kind")
        Text(cameraLine)
            .font(SurveyType(16, .heavy))
            .lineLimit(2)
        if field.instrument.cameraKind == "custom" || field.instrument.cameraKind == "spc" {
            TextField("X m", text: $customX).textFieldStyle(.roundedBorder).accessibilityIdentifier("camera-x")
            TextField("Y m", text: $customY).textFieldStyle(.roundedBorder).accessibilityIdentifier("camera-y")
            TextField("Z m", text: $customZ).textFieldStyle(.roundedBorder).accessibilityIdentifier("camera-z")
        }
        Picker("アンテナ高", selection: antennaKind) {
            Text("ポール高").tag("pole")
            Text("下レーザー").tag("laser")
        }
        .accessibilityIdentifier("antenna-kind")
        if field.instrument.antennaMethod == "laser" {
            Text("筐体 0.1877m + 測った距離")
                .font(SurveyType(16, .semibold))
                .lineLimit(1)
            TextField("レーザー距離 m", text: $laserText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("laser-distance")
        } else {
            TextField("ポール高 m", text: $poleText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("pole-height")
        }
        Text(KBMCorrection.title)
            .font(SurveyType(18, .heavy))
            .accessibilityIdentifier("kbm-title")
        TextField("H の出典", text: $source).textFieldStyle(.roundedBorder).accessibilityIdentifier("kbm-source")
        TextField("版", text: $version).textFieldStyle(.roundedBorder).accessibilityIdentifier("kbm-version")
        TextField("日付", text: $dateText).textFieldStyle(.roundedBorder).accessibilityIdentifier("kbm-date")
        TextField("成果の高さ H m", text: $hText).textFieldStyle(.roundedBorder).accessibilityIdentifier("kbm-h")
        Toggle("準拠モード", isOn: compliance)
            .font(SurveyType(16, .heavy))
            .accessibilityIdentifier("compliance-switch")
        Text(tiltLine)
            .font(SurveyType(18, .heavy))
            .lineLimit(1)
            .accessibilityIdentifier("tilt-readout")
        Text("ファームウェア \(field.receiverFirmware ?? field.rtkSession?.firmwareVersion ?? "未取得")")
            .font(SurveyType(16, .heavy))
            .lineLimit(1)
            .accessibilityIdentifier("firmware-readout")
        Text(ViDocLaser.heldReason)
            .font(SurveyType(15, .semibold))
            .foregroundStyle(SurveyColor.muted)
            .lineLimit(2)
            .accessibilityIdentifier("laser-held")
        DeskTile(title: "この設定を残す", systemImage: "checkmark.circle", identifier: "setup-save", prominent: true) {
            applyFields()
            field.saveInstrument()
        }
        if let message = field.instrumentMessage {
            Text(message)
                .font(SurveyType(18, .heavy))
                .lineLimit(4)
                .accessibilityIdentifier("setup-result")
        }
        Button {
            field.tab = .map
        } label: {
            Text("地図で記録")
                .font(SurveyType(18, .heavy))
                .frame(maxWidth: .infinity, minHeight: 72)
                .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(SurveyColor.text)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("setup-next")
        }
        .onAppear {
            field.refreshInstrument()
            field.receiverFirmware = field.rtkSession?.firmwareVersion
            source = field.instrument.kbmSource
            version = field.instrument.kbmVersion
            dateText = field.instrument.kbmDate
            poleText = String(format: "%.3f", field.instrument.poleMeters)
            if let laser = field.instrument.laserMeters { laserText = String(format: "%.3f", laser) }
            customX = String(field.instrument.cameraX)
            customY = String(field.instrument.cameraY)
            customZ = String(field.instrument.cameraZ)
            startTilt()
        }
        .onDisappear {
            #if !SURVEY_PLAYGROUND && canImport(CoreMotion)
            SystemMotion.shared.setPitch(false)
            #endif
        }
    }

    private var cameraLine: String {
        let value = field.instrument
        return String(format: "X %.3f  Y %.3f  Z %.3f m", value.cameraX, value.cameraY, value.cameraZ)
    }

    private var tiltLine: String {
        guard let tilt = field.tiltDegrees else { return "傾きはまだありません。" }
        let gate = PrecisionGate.tiltAllowsStart(degrees: tilt) ? "観測可" : "0.5°超。観測を始めません"
        return String(format: "電子気泡 %.2f° %@", tilt, gate)
    }

    private var cameraKind: Binding<String> {
        Binding(
            get: { customOnly ? "custom" : field.instrument.cameraKind },
            set: { kind in
                field.instrument.cameraKind = customOnly ? "custom" : kind
                if field.instrument.cameraKind == "spcPlus" {
                    field.instrument.cameraX = CameraOffset.spcPlus15ProMax.x
                    field.instrument.cameraY = CameraOffset.spcPlus15ProMax.y
                    field.instrument.cameraZ = CameraOffset.spcPlus15ProMax.z
                }
            }
        )
    }

    private var antennaKind: Binding<String> {
        Binding(
            get: { field.instrument.antennaMethod },
            set: { field.instrument.antennaMethod = $0 }
        )
    }

    private var compliance: Binding<Bool> {
        Binding(
            get: { field.instrument.complianceEnabled },
            set: { field.instrument.complianceEnabled = $0 }
        )
    }

    private func applyFields() {
        field.instrument.kbmSource = source
        field.instrument.kbmVersion = version
        field.instrument.kbmDate = dateText
        field.instrument.kbmH = Double(hText)
        if field.instrument.antennaMethod == "laser" {
            field.instrument.laserMeters = Double(laserText)
        } else if let pole = Double(poleText) {
            field.instrument.poleMeters = pole
        }
        if field.instrument.cameraKind == "custom" || field.instrument.cameraKind == "spc" {
            if let x = Double(customX) { field.instrument.cameraX = x }
            if let y = Double(customY) { field.instrument.cameraY = y }
            if let z = Double(customZ) { field.instrument.cameraZ = z }
        }
        if let h = field.instrument.kbmH {
            let ellipsoidal = field.reading.position?.ellipsoidalHeightMeters ?? h
            field.recordKBMSample(ellipsoidal: ellipsoidal)
        }
    }

    private func startTilt() {
        #if !SURVEY_PLAYGROUND && canImport(CoreMotion)
        SystemMotion.shared.onPitchRadians = { pitch in
            let degrees = StatureMath.tiltFromVertical(pitchRadians: pitch).map { $0 * 180 / .pi }
            DispatchQueue.main.async { field.tiltDegrees = degrees }
        }
        SystemMotion.shared.setPitch(true)
        #endif
    }
}
