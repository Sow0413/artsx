import SwiftUI
import SurveyCore

#if !SURVEY_PLAYGROUND && canImport(AVFoundation)
import AVFoundation
#endif

/// 計画高との差を、画面中央の縦ゲージで出す。読み上げは実機未確認。
struct BatterSheet: View {
    @ObservedObject var field: FieldModel
    @ObservedObject var drawing: DrawingSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cadence = BatterCadence()
    @StateObject private var relative = RelativeFollower()
    @State private var designText = ""
    @State private var offsetText = ""
    @State private var slopeText = ""
    @State private var azimuthText = ""
    @State private var toleranceText = ""
    @State private var poleText = ""
    @State private var knownName = ""
    @State private var knownPick: KnownHeight?
    @State private var bookHits: [KnownHeight] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                badgeRow
                gaugeSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                settings
                recordButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .background(SurveyColor.background)
            .foregroundStyle(SurveyColor.text)
            .navigationTitle("丁張")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .font(SurveyType(17, .heavy))
                }
            }
        }
        .modifier(SurveyScheme())
        .onAppear {
            field.setCrosshairSession(true)
            loadFields()
            syncRelative()
            cadence.update(phrase: spoken, interval: speechInterval)
        }
        .onDisappear {
            field.setCrosshairSession(false)
            relative.stop()
            cadence.stop()
        }
        .onChange(of: voiceKey) { _, _ in
            cadence.update(phrase: spoken, interval: speechInterval)
        }
        .onChange(of: field.batter.source) { _, _ in
            syncRelative()
        }
        .onChange(of: surveyKey) { _, _ in
            pushSurvey()
        }
    }

    private var badgeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsRelativeBadge {
                RelativeStageBadge(badge: relativeBadge)
            } else {
                AccuracyBadgeView(badge: field.badge, stage: field.stageTransition.stage)
                if guide {
                    Text(BatterMath.guideWord)
                        .font(SurveyType(22, .heavy))
                        .foregroundStyle(SurveyColor.color(OutdoorContrast.black))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(SurveyColor.color(OutdoorContrast.yellow), in: Capsule())
                        .accessibilityLabel("目安。iPhone単体の高さです。")
                }
            }
        }
    }

    private var gaugeSection: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 4)
            HStack(alignment: .center, spacing: 16) {
                BatterGauge(fraction: fraction, ink: move == nil ? SurveyColor.text : phraseInk)
                    .frame(width: 72, height: 260)
                VStack(alignment: .leading, spacing: 8) {
                    Text(move.map(BatterMath.arrow) ?? "–")
                        .font(SurveyType(64, .heavy))
                        .foregroundStyle(move == nil ? SurveyColor.text : SurveyColor.onAccent)
                        .frame(maxWidth: .infinity)
                    Text(spoken ?? blocker ?? "高さを比べています")
                        .font(SurveyType(36, .heavy))
                        .foregroundStyle(move == nil ? SurveyColor.text : SurveyColor.onAccent)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                .background(phraseInk, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            if let note = targetNote {
                Text(note)
                    .font(SurveyType(16, .heavy, mono: true))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let measured {
                Text("測定 \(meter(measured))m　\(field.batter.source.label)")
                    .font(SurveyType(16, .heavy, mono: true))
            }
            if field.batter.source == .relative, let fix = relative.fix {
                Text(RelativeHeight.statusText(fix))
                    .font(SurveyType(16, .heavy))
                    .fixedSize(horizontal: false, vertical: true)
                if fix.needsRealign {
                    Text(RelativeHeight.realignWord)
                        .font(SurveyType(28, .heavy))
                        .foregroundStyle(SurveyColor.color(OutdoorContrast.black))
                        .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                        .background(SurveyColor.color(OutdoorContrast.yellow))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            if let notice = relative.notice, field.batter.source == .relative {
                Text(notice)
                    .font(SurveyType(14, .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(planLine)
                .font(SurveyType(20, .heavy))
                .fixedSize(horizontal: false, vertical: true)
            if field.batter.slope != 0, field.batter.slopeAzimuthDegrees == nil {
                Text("勾配の向きが無いので、勾配は足しません。")
                    .font(SurveyType(14, .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLine)
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Picker("測る高さ", selection: sourceBinding) {
                    Text(BatterSource.poleTip.label).tag(BatterSource.poleTip)
                    Text(BatterSource.crosshair.label).tag(BatterSource.crosshair)
                    Text(BatterSource.relative.label).tag(BatterSource.relative)
                }
                .pickerStyle(.segmented)
                switch field.batter.source {
                case .poleTip:
                    fieldRow("ポール高 m", text: $poleText, commit: commitPole)
                case .crosshair:
                    Text(crosshairLevel == true ? "十字線は水平です。器械高は地盤高に目の高さを足した値です。" : "十字線は、水平（±0.1°）のときだけ高さに使います。")
                        .font(SurveyType(14, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                case .relative:
                    relativeSettings
                }
                fieldRow("計画高 m", text: $designText, commit: commitDesign)
                fieldRow("オフセット m（+0.50 で貫は 50cm 上）", text: $offsetText, commit: commitOffset)
                fieldRow("勾配（1m あたり。+0.02 は 2%）", text: $slopeText, commit: commitSlope)
                fieldRow("勾配の向き °（空なら足さない）", text: $azimuthText, commit: commitAzimuth)
                if planAzimuth != nil {
                    Button("目標の方向を使う") { usePlanAzimuth() }
                        .buttonStyle(SurveyPlainButton())
                }
                fieldRow("許容 ±mm（既定 5）", text: $toleranceText, commit: commitTolerance)
            }
        }
        .frame(maxHeight: field.batter.source == .relative ? 300 : 220)
    }

    private var relativeSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("楕円体高のある基準点か、座標簿の点でゼロを合わせます。標高だけしか無い点は使いません。")
                .font(SurveyType(14, .semibold))
                .foregroundStyle(SurveyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(controlHeights.prefix(8)) { item in
                knownButton(item)
            }
            if controlHeights.isEmpty {
                Text("楕円体高のある基準点は、まだありません。")
                    .font(SurveyType(14, .semibold))
                    .foregroundStyle(SurveyColor.muted)
            }
            TextField("座標簿の点名", text: $knownName)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onChange(of: knownName) { _, text in
                    bookHits = field.knownBookHeights(matching: text)
                }
            ForEach(bookHits) { item in
                knownButton(item)
            }
            Button(zeroTitle) {
                guard let knownPick else { return }
                relative.align(name: knownPick.name, knownHeight: knownPick.heightMeters)
            }
            .buttonStyle(SurveyPlainButton())
            .disabled(knownPick == nil || !relative.readyToAlign)
        }
    }

    private func knownButton(_ item: KnownHeight) -> some View {
        Button {
            knownPick = item
        } label: {
            Text("\(item.name)　\(meter(item.heightMeters))m　\(item.source.label)\(knownPick?.id == item.id ? "　選択" : "")")
                .font(SurveyType(16, .heavy))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(SurveyPlainButton())
    }

    private var recordButton: some View {
        Button {
            guard let measured else { return }
            if field.batter.source == .relative, let fix = relative.fix, !RelativeHeight.usesReceiverStage(fix.channel) {
                field.registerBatter(measuredHeight: measured, note: "相対。\(RelativeHeight.estimateText(fix.sigmaMeters))。")
            } else {
                field.registerBatter(measuredHeight: measured)
            }
        } label: {
            Text(recordTitle)
                .font(SurveyType(20, .heavy))
                .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                .background(canRecord ? phraseInk : SurveyColor.card)
                .foregroundStyle(canRecord ? SurveyColor.onAccent : SurveyColor.muted)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canRecord)
        .accessibilityLabel(recordTitle)
    }

    private func fieldRow(_ title: String, text: Binding<String>, commit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SurveyType(13, .heavy))
                .foregroundStyle(SurveyColor.muted)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .font(SurveyType(18, .heavy, mono: true))
                .onChange(of: text.wrappedValue) { _, _ in commit() }
        }
    }

    private var sourceBinding: Binding<BatterSource> {
        Binding(
            get: { field.batter.source },
            set: { source in
                var next = field.batter
                next.source = source
                field.saveBatter(next)
            }
        )
    }

    private var position: GeodeticPosition? { field.workingReading.position }

    private var design: Double? { drawing.designHeightMeters }

    private var targetPoint: (latitude: Double, longitude: Double)? {
        guard let inspection = drawing.inspection,
              let latitude = inspection.latitudeDegrees,
              let longitude = inspection.longitudeDegrees else { return nil }
        return (latitude, longitude)
    }

    private var along: Double {
        guard let azimuth = field.batter.slopeAzimuthDegrees,
              let here = position,
              let origin = targetPoint,
              let meters = BatterMath.alongMeters(
                hereLatitude: here.latitudeDegrees,
                hereLongitude: here.longitudeDegrees,
                originLatitude: origin.latitude,
                originLongitude: origin.longitude,
                azimuthDegrees: azimuth
              ) else { return 0 }
        return meters
    }

    private var target: Double? {
        guard let design else { return nil }
        return BatterMath.targetHeight(
            design: design,
            offset: field.batter.offsetMeters,
            slope: field.batter.slope,
            alongMeters: along
        )
    }

    private var crosshairLevel: Bool? {
        guard let elevation = field.crosshairElevation else { return nil }
        return CrosshairMath.isLevel(elevation)
    }

    private var measured: Double? {
        switch field.batter.source {
        case .poleTip:
            guard let device = position?.ellipsoidalHeightMeters else { return nil }
            return BatterMath.poleTip(deviceEllipsoidal: device, poleMeters: field.poleHeight.meters)
        case .crosshair:
            guard BatterMath.acceptsCrosshair(isLevel: crosshairLevel),
                  let ground = field.crosshairGroundHeight(),
                  let eye = StatureMath.eyeHeight(field.stature) else { return nil }
            return BatterMath.crosshairLine(ground: ground, eye: eye)
        case .relative:
            return relative.fix?.heightMeters
        }
    }

    private var difference: Double? {
        guard let measured, let target else { return nil }
        return BatterMath.delta(measured: measured, target: target)
    }

    private var move: BatterMove? {
        guard let difference else { return nil }
        return BatterMath.move(deltaMeters: difference, toleranceMeters: field.batter.toleranceMeters)
    }

    private var spoken: String? {
        guard let difference else { return nil }
        return BatterMath.phrase(deltaMeters: difference, toleranceMeters: field.batter.toleranceMeters)
    }

    private var speechInterval: TimeInterval {
        BatterMath.speechInterval(remainingMeters: difference ?? 1)
    }

    private var voiceKey: String {
        let bucket = Int((speechInterval * 20).rounded())
        return "\(spoken ?? "")#\(bucket)"
    }

    private var fraction: Double {
        guard let difference else { return 0.5 }
        return BatterMath.gaugeFraction(deltaMeters: difference)
    }

    private var phraseInk: Color {
        guard let move else { return SurveyColor.card }
        switch BatterMath.ink(move) {
        case .blue: return SurveyColor.blue
        case .red: return SurveyColor.red
        case .green: return SurveyColor.green
        }
    }

    private var guide: Bool {
        if let position {
            return BatterMath.showsGuide(stage: position.stage, receiver: position.receiver)
        }
        return field.stageTransition.stage == .iphone
    }

    private var showsRelativeBadge: Bool {
        guard field.batter.source == .relative else { return false }
        if let fix = relative.fix, RelativeHeight.usesReceiverStage(fix.channel) { return false }
        return true
    }

    private var relativeBadge: RelativeBadge {
        if let fix = relative.fix, !RelativeHeight.usesReceiverStage(fix.channel) {
            return RelativeHeight.badge(for: fix)
        }
        return RelativeHeight.waitingBadge()
    }

    private var controlHeights: [KnownHeight] {
        field.controlPoints.compactMap(KnownHeightPick.control)
    }

    private var zeroTitle: String {
        if let knownPick {
            return "\(knownPick.name)でゼロを合わせる"
        }
        return "点を選んでゼロを合わせる"
    }

    private var surveyKey: String {
        let here = field.workingReading.position
        let height = here?.ellipsoidalHeightMeters ?? .nan
        let trusted = here?.isTrustedRTKFix == true
        let pole = field.poleHeight.meters ?? .nan
        return "\(height)|\(trusted)|\(pole)"
    }

    private func syncRelative() {
        if field.batter.source == .relative {
            relative.start()
            pushSurvey()
        } else {
            relative.stop()
        }
    }

    private func pushSurvey() {
        guard field.batter.source == .relative else { return }
        let here = field.workingReading.position
        relative.setSurvey(
            ellipsoidal: here?.ellipsoidalHeightMeters,
            trusted: here?.isTrustedRTKFix == true,
            vertical: here?.verticalAccuracyMeters,
            pole: field.poleHeight.meters
        )
    }

    private var blocker: String? {
        if design == nil { return "計画高が無いので、比べられません。" }
        switch field.batter.source {
        case .poleTip:
            if position?.ellipsoidalHeightMeters == nil { return "高さが無いので、先端は出せません。" }
            if field.poleHeight.meters == nil { return "ポール高が無いので、先端の高さは出せません。" }
            if measured == nil { return "ポール高が範囲外です。" }
        case .crosshair:
            if crosshairLevel == nil { return "傾きが無いので、十字線の水平は未確認です。" }
            if crosshairLevel == false { return "水平ではないので、十字線は高さになりません。" }
            if field.crosshairGroundHeight() == nil { return "地盤高が無いので、十字線の高さは出せません。" }
            if StatureMath.eyeHeight(field.stature) == nil { return "目の高さが無いので、十字線の高さは出せません。" }
        case .relative:
            if relative.fix == nil { return "既知の高さでゼロを合わせてください。" }
            return nil
        }
        return "目標の高さが出せません。"
    }

    private var targetNote: String? {
        guard let design else { return nil }
        return BatterMath.targetNote(
            design: design,
            offset: field.batter.offsetMeters,
            slope: field.batter.slopeAzimuthDegrees == nil ? 0 : field.batter.slope,
            alongMeters: along
        )
    }

    private var planLine: String {
        guard let here = position, let target = targetPoint,
              let plan = BatterMath.plan(
                hereLatitude: here.latitudeDegrees,
                hereLongitude: here.longitudeDegrees,
                targetLatitude: target.latitude,
                targetLongitude: target.longitude
              ) else {
            return BatterMath.planText(distanceMeters: nil, azimuthDegrees: nil, precision: .meters)
        }
        let precision = StakeoutPrecision.decide(drawing.stakeoutAccuracy)
        return BatterMath.planText(distanceMeters: plan.distanceMeters, azimuthDegrees: plan.azimuthDegrees, precision: precision)
    }

    private var planAzimuth: Double? {
        guard let here = position, let target = targetPoint else { return nil }
        return BatterMath.plan(
            hereLatitude: here.latitudeDegrees,
            hereLongitude: here.longitudeDegrees,
            targetLatitude: target.latitude,
            targetLongitude: target.longitude
        )?.azimuthDegrees
    }

    private var canRecord: Bool {
        guard measured != nil, target != nil else { return false }
        if field.batter.source == .relative {
            guard let fix = relative.fix else { return false }
            return RelativeHeight.canRecord(fix)
        }
        return true
    }

    private var recordTitle: String {
        if let name = field.nextPointName, canRecord {
            return "\(name)を丁張で残す"
        }
        return "この高さを残す"
    }

    private var accessibilityLine: String {
        var parts = [spoken ?? blocker ?? "丁張"]
        if showsRelativeBadge {
            parts.append(relativeBadge.accessibilityText)
        } else {
            if guide { parts.append(BatterMath.guideWord) }
            parts.append("段階\(field.stageTransition.stage.rawValue)")
        }
        parts.append(planLine)
        return parts.joined(separator: "。")
    }

    private func meter(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func loadFields() {
        designText = drawing.designHeightMeters.map { number($0) } ?? ""
        offsetText = number(field.batter.offsetMeters)
        slopeText = number(field.batter.slope)
        azimuthText = field.batter.slopeAzimuthDegrees.map { number($0) } ?? ""
        toleranceText = number(field.batter.toleranceMeters * 1000)
        poleText = field.poleHeight.meters.map { number($0) } ?? ""
    }

    private func number(_ value: Double) -> String {
        String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func commitDesign() {
        drawing.setDesignHeight(designText)
    }

    private func commitOffset() {
        guard let value = parsed(offsetText), abs(value) <= 50 else { return }
        var next = field.batter
        next.offsetMeters = value
        field.saveBatter(next)
    }

    private func commitSlope() {
        guard let value = parsed(slopeText), abs(value) <= 2 else { return }
        var next = field.batter
        next.slope = value
        field.saveBatter(next)
    }

    private func commitAzimuth() {
        var next = field.batter
        let trimmed = azimuthText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            next.slopeAzimuthDegrees = nil
        } else if let value = parsed(trimmed), value.isFinite {
            next.slopeAzimuthDegrees = value
        } else {
            return
        }
        field.saveBatter(next)
    }

    private func commitTolerance() {
        guard let millimeters = parsed(toleranceText), millimeters >= 0, millimeters <= 1000 else { return }
        var next = field.batter
        next.toleranceMeters = millimeters / 1000
        field.saveBatter(next)
    }

    private func commitPole() {
        let trimmed = poleText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            field.savePoleMeters(nil)
            return
        }
        guard let value = parsed(trimmed), value > 0, value <= 10 else { return }
        field.savePoleMeters(value)
    }

    private func usePlanAzimuth() {
        guard let planAzimuth else { return }
        azimuthText = number(planAzimuth)
        commitAzimuth()
    }

    private func parsed(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed), value.isFinite else { return nil }
        return value
    }
}

private struct BatterGauge: View {
    var fraction: Double
    var ink: Color

    var body: some View {
        GeometryReader { geo in
            let y = geo.size.height * (1 - min(max(fraction, 0), 1))
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(SurveyColor.card)
                Rectangle()
                    .fill(SurveyColor.text)
                    .frame(height: SurveyColor.stroke)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(ink)
                    .frame(width: max(8, geo.size.width - 16), height: 12)
                    .position(x: geo.size.width / 2, y: min(max(y, 10), geo.size.height - 10))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SurveyColor.line, lineWidth: SurveyColor.stroke)
            )
        }
    }
}

/// 残差が小さいほど短い間隔で、同じ文を読む。実機の声とマナーモードは未確認。
final class BatterCadence: ObservableObject {
    private var phrase: String?
    private var interval: TimeInterval = BatterMath.farSpeechSeconds
    private var timer: Timer?

    func update(phrase: String?, interval: TimeInterval) {
        guard let phrase else {
            stop()
            return
        }
        let changed = phrase != self.phrase
        let intervalChanged = abs(interval - self.interval) > 0.04 || timer == nil
        self.phrase = phrase
        self.interval = interval
        if changed {
            BatterVoice.say(phrase)
        }
        if changed || intervalChanged {
            schedule()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        phrase = nil
        BatterVoice.stop()
    }

    private func schedule() {
        timer?.invalidate()
        let wait = interval
        let timer = Timer(timeInterval: wait, repeats: true) { [weak self] _ in
            guard let self, let phrase = self.phrase else { return }
            BatterVoice.say(phrase)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

enum BatterVoice {
    static func say(_ text: String) {
        #if !SURVEY_PLAYGROUND && canImport(AVFoundation)
        speaker.stopSpeaking(at: .immediate)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
        )
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = 0.5
        speaker.speak(utterance)
        #else
        _ = text
        #endif
    }

    static func stop() {
        #if !SURVEY_PLAYGROUND && canImport(AVFoundation)
        speaker.stopSpeaking(at: .immediate)
        #endif
    }

    #if !SURVEY_PLAYGROUND && canImport(AVFoundation)
    private static let speaker = AVSpeechSynthesizer()
    #endif
}
