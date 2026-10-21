import SwiftUI
import SurveyCore

#if !SURVEY_PLAYGROUND && canImport(ARKit)
import ARKit
import SceneKit
import CoreVideo
#endif

/// 背面カメラの十字線。水平はスタッフ読み、ターゲットは距離と仰角。
struct CrosshairSheet: View {
    @ObservedObject var field: FieldModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode = CrosshairMode.level
    @State private var staffText = ""
    @State private var manualDistance = ""
    @State private var measuredDistance: Double?
    @State private var range: CrosshairRange = .manual
    @State private var firstReading: Double?
    @State private var secondReading: Double?
    @State private var problem = ""
    @State private var wasLevel = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    CrosshairCamera(onDistance: { distance, source in
                        measuredDistance = distance
                        if let source { range = source }
                    })
                    CrosshairMark(level: isLevel)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("モード", selection: $mode) {
                            Text("水平").tag(CrosshairMode.level)
                            Text("ターゲット").tag(CrosshairMode.target)
                        }
                        .pickerStyle(.segmented)
                        angleBlock
                        Text(CrosshairMath.exampleLabel(calibrated: field.tiltZero.calibrated))
                            .font(SurveyType(16, .heavy))
                        Text(field.tiltZero.calibrated ? "傾斜は反転法でゼロを合わせています。" : "傾斜は未校正です。20mの誤差は校正後より大きく出します。")
                            .font(SurveyType(14, .semibold))
                            .foregroundStyle(SurveyColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        calibrationBlock
                        if mode == .level {
                            levelBlock
                        } else {
                            targetBlock
                        }
                        if !problem.isEmpty {
                            Text(problem)
                                .font(SurveyType(15, .heavy))
                                .foregroundStyle(SurveyColor.amber)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let badge = stageBadge {
                            AccuracyBadgeView(badge: badge, stage: .iphone)
                        }
                    }
                    .padding(20)
                }
            }
            .background(SurveyColor.background)
            .foregroundStyle(SurveyColor.text)
            .navigationTitle("水準器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .font(SurveyType(17, .heavy))
                }
            }
        }
        .modifier(SurveyScheme())
        .onAppear { field.setCrosshairSession(true) }
        .onDisappear { field.setCrosshairSession(false) }
        .onChange(of: isLevel) { _, level in
            if level && !wasLevel { CrosshairCue.play() }
            wasLevel = level
        }
    }

    private var elevation: Double? { field.crosshairElevation }

    private var isLevel: Bool { elevation.map(CrosshairMath.isLevel) ?? false }

    private var angleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isLevel ? "水平" : "仰角")
                .font(SurveyType(15, .heavy))
            Text(elevation.map { "\(CrosshairMath.angleText($0))°" } ?? "傾きを待っています")
                .font(SurveyType(28, .heavy, mono: true))
            if isLevel {
                Text("±0.1°以内。十字線は目の高さの水平線です。")
                    .font(SurveyType(14, .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var calibrationBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("傾斜校正")
                .font(SurveyType(18, .heavy))
            Text("同じ傾きのまま端末を180°回し、二回読みます。ゼロ点はその平均です。")
                .font(SurveyType(14, .semibold))
                .foregroundStyle(SurveyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            if field.tiltZero.calibrated {
                Text("ゼロ点 \(CrosshairMath.angleText(field.tiltZero.biasRadians))°")
                    .font(SurveyType(16, .heavy, mono: true))
            }
            HStack(spacing: 8) {
                Button(firstReading == nil ? "1回目を読む" : "1回目 \(CrosshairMath.angleText(firstReading ?? 0))°") {
                    firstReading = field.crosshairTilt
                    if field.crosshairTilt == nil { problem = "傾きが無いので読めません。" }
                }
                .buttonStyle(CrosshairChip())
                Button(secondReading == nil ? "裏返して2回目" : "2回目 \(CrosshairMath.angleText(secondReading ?? 0))°") {
                    secondReading = field.crosshairTilt
                    applyReversal()
                }
                .buttonStyle(CrosshairChip())
            }
        }
    }

    private var levelBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("スタッフ読値 m")
                .font(SurveyType(15, .heavy))
            TextField("1.20", text: $staffText)
                .keyboardType(.decimalPad)
                .autocorrectionDisabled()
                .font(SurveyType(20, .heavy, mono: true))
                .padding(10)
                .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if let result = levelResult {
                Text("器械高 \(CrosshairMath.meterText(result.instrumentHeightMeters))m")
                    .font(SurveyType(22, .heavy, mono: true))
                Text("高低差 \(CrosshairMath.meterText(result.heightDifferenceMeters))m")
                    .font(SurveyType(28, .heavy, mono: true))
                Text("相手の地盤高 \(CrosshairMath.meterText(result.targetHeightMeters))m")
                    .font(SurveyType(16, .heavy, mono: true))
                Text("器械高は、自分の地盤高に目の高さを足した値です。読み値が目の高さなら高低差は 0 です。")
                    .font(SurveyType(14, .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(levelHint)
                    .font(SurveyType(15, .heavy))
                    .foregroundStyle(SurveyColor.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var targetBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("距離 m（\(range.label)）")
                .font(SurveyType(15, .heavy))
            TextField(measuredDistance.map { CrosshairMath.meterText($0) } ?? "20", text: $manualDistance)
                .keyboardType(.decimalPad)
                .autocorrectionDisabled()
                .font(SurveyType(20, .heavy, mono: true))
                .padding(10)
                .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("空欄のときは、LiDAR か ARKit の距離を使います。")
                .font(SurveyType(14, .semibold))
                .foregroundStyle(SurveyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let shot = targetResult {
                Text("高低差 \(CrosshairMath.meterText(shot.heightDifferenceMeters))m")
                    .font(SurveyType(28, .heavy, mono: true))
                Text("水平距離 \(CrosshairMath.meterText(shot.horizontalMeters))m")
                    .font(SurveyType(18, .heavy, mono: true))
                Text("この観測 \(CrosshairMath.centimeterText(shot.heightSigmaMeters))")
                    .font(SurveyType(16, .heavy))
                if let azimuth = shot.azimuthDegrees {
                    Text("方位 \(CrosshairMath.angleText(azimuth * .pi / 180))°")
                        .font(SurveyType(16, .heavy, mono: true))
                } else {
                    Text("方位が無いので、座標は出せません。")
                        .font(SurveyType(15, .heavy))
                        .foregroundStyle(SurveyColor.amber)
                }
                Button("座標簿に登録") {
                    if field.registerTarget(shot, rangeLabel: activeRange.label) {
                        dismiss()
                    } else {
                        problem = field.captureMessage ?? "登録できません。"
                    }
                }
                .buttonStyle(.plain)
                .font(SurveyType(18, .heavy))
                .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                .background(shot.latitudeDegrees == nil ? SurveyColor.card : SurveyColor.blue)
                .foregroundStyle(shot.latitudeDegrees == nil ? SurveyColor.muted : SurveyColor.onAccent)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(shot.latitudeDegrees == nil)
            } else {
                Text("距離と仰角が揃うと、高低差を出します。")
                    .font(SurveyType(15, .heavy))
                    .foregroundStyle(SurveyColor.amber)
            }
        }
    }

    private var levelResult: LevelResult? {
        guard let ground = field.crosshairGroundHeight(), let eye = StatureMath.eyeHeight(field.stature) else { return nil }
        guard let staff = Double(staffText.trimmingCharacters(in: .whitespaces)) else { return nil }
        return CrosshairMath.level(ground: ground, eye: eye, staff: staff)
    }

    private var levelHint: String {
        if StatureMath.eyeHeight(field.stature) == nil { return "身長が未登録です。" }
        if field.crosshairGroundHeight() == nil { return "地盤高が無いので、器械高を出せません。" }
        return "スタッフの読み値を入れてください。"
    }

    private var activeRange: CrosshairRange {
        manualDistance.trimmingCharacters(in: .whitespaces).isEmpty ? range : .manual
    }

    private var distanceMeters: Double? {
        let typed = manualDistance.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty { return measuredDistance }
        return Double(typed)
    }

    private var targetResult: TargetResult? {
        guard let elevation, let distance = distanceMeters else { return nil }
        let origin = field.reading.position
        let height = field.crosshairGroundHeight().flatMap { ground in
            StatureMath.eyeHeight(field.stature).map { ground + $0 }
        } ?? origin?.ellipsoidalHeightMeters
        guard let height else { return nil }
        let sigma = CrosshairMath.angleSigmaRadians(calibrated: field.tiltZero.calibrated)
        return CrosshairMath.target(
            originLatitude: origin?.latitudeDegrees,
            originLongitude: origin?.longitudeDegrees,
            originHeight: height,
            distance: distance,
            elevationRadians: elevation,
            azimuthDegrees: origin?.headingDegrees ?? origin?.courseDegrees,
            angleSigmaRadians: sigma,
            distanceSigma: CrosshairMath.distanceSigma(range: activeRange, distance: distance)
        )
    }

    private var stageBadge: AccuracyBadgeModel? {
        guard let shot = targetResult, let latitude = shot.latitudeDegrees, let longitude = shot.longitudeDegrees else {
            return AccuracyPolicy.badge(for: field.reading, operatingStage: .iphone)
        }
        let origin = field.reading.position
        let accuracy = CrosshairMath.storedAccuracy(
            originHorizontal: origin?.horizontalAccuracyMeters ?? shot.horizontalSigmaMeters,
            originVertical: origin?.verticalAccuracyMeters,
            aimHorizontal: shot.horizontalSigmaMeters,
            aimVertical: shot.heightSigmaMeters
        )
        let position = CrosshairMath.position(
            latitude: latitude,
            longitude: longitude,
            height: shot.targetHeightMeters,
            horizontalAccuracy: accuracy.horizontal,
            verticalAccuracy: accuracy.vertical,
            at: Date()
        )
        return AccuracyPolicy.badge(
            for: PositionReading(position: position, availability: .available),
            work: field.workCatalog.selected,
            operatingStage: .iphone
        )
    }

    private func applyReversal() {
        guard let first = firstReading, let second = secondReading else {
            if field.crosshairTilt == nil { problem = "傾きが無いので読めません。" }
            return
        }
        guard let bias = TiltZero.reversal(firstRadians: first, reversedRadians: second) else {
            problem = "この読みではゼロを合わせられません。"
            return
        }
        field.saveTiltZero(bias)
        problem = ""
    }
}

private enum CrosshairMode {
    case level
    case target
}

private struct CrosshairChip: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SurveyType(16, .heavy))
            .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
            .background(configuration.isPressed ? SurveyColor.pressed : SurveyColor.card)
            .foregroundStyle(SurveyColor.text)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(SurveyColor.line, lineWidth: SurveyColor.stroke)
            )
    }
}

/// 白と黒の十字。カメラの明暗どちらでも見える。
struct CrosshairMark: View {
    var level: Bool

    var body: some View {
        GeometryReader { geo in
            let midX = geo.size.width / 2
            let midY = geo.size.height / 2
            ZStack {
                cross(width: 5, color: SurveyColor.color(OutdoorContrast.black))
                cross(width: 3, color: level ? SurveyColor.green : SurveyColor.color(OutdoorContrast.white))
            }
            .position(x: midX, y: midY)
        }
        .allowsHitTesting(false)
        .accessibilityLabel(level ? "十字線。水平" : "十字線")
    }

    private func cross(width: CGFloat, color: Color) -> some View {
        ZStack {
            Rectangle().fill(color).frame(width: width, height: 140)
            Rectangle().fill(color).frame(width: 140, height: width)
        }
    }
}

struct CrosshairCamera: View {
    var onDistance: (Double?, CrosshairRange?) -> Void

    var body: some View {
        #if !SURVEY_PLAYGROUND && canImport(ARKit)
        CrosshairARView(onDistance: onDistance)
        #else
        ZStack {
            SurveyColor.card
            Text("カメラは実機で使います。距離は下に手入力できます。")
                .font(SurveyType(16, .heavy))
                .foregroundStyle(SurveyColor.text)
                .multilineTextAlignment(.center)
                .padding(16)
        }
        .onAppear { onDistance(nil, nil) }
        #endif
    }
}

#if !SURVEY_PLAYGROUND && canImport(ARKit)
/// 背面カメラ。中央の距離は LiDAR、無ければ ARKit のレイ。映像は保存しない。実機は未確認。
struct CrosshairARView: UIViewRepresentable {
    var onDistance: (Double?, CrosshairRange?) -> Void

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session.delegate = context.coordinator
        context.coordinator.view = view
        view.automaticallyUpdatesLighting = false
        let configuration = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        view.session.run(configuration)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.onDistance = onDistance
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDistance: onDistance)
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        var onDistance: (Double?, CrosshairRange?) -> Void
        weak var view: ARSCNView?

        init(onDistance: @escaping (Double?, CrosshairRange?) -> Void) {
            self.onDistance = onDistance
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            if let depth = CrosshairARView.centerDepth(frame.sceneDepth?.depthMap) {
                let report = onDistance
                DispatchQueue.main.async { report(depth, .lidar) }
                return
            }
            let camera = frame.camera.transform.columns.3
            let report = onDistance
            DispatchQueue.main.async { [weak view] in
                guard let view, view.bounds.width > 1, view.bounds.height > 1 else { return }
                let point = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
                guard let query = view.raycastQuery(from: point, allowing: .estimatedPlane, alignment: .any),
                      let hit = view.session.raycast(query).first else {
                    report(nil, nil)
                    return
                }
                let target = hit.worldTransform.columns.3
                let dx = target.x - camera.x
                let dy = target.y - camera.y
                let dz = target.z - camera.z
                let distance = Double((dx * dx + dy * dy + dz * dz).squareRoot())
                report(distance.isFinite && distance > 0 ? distance : nil, .arkit)
            }
        }
    }

    private static func centerDepth(_ map: CVPixelBuffer?) -> Double? {
        guard let map else { return nil }
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        guard width > 0, height > 0 else { return nil }
        let row = CVPixelBufferGetBytesPerRow(map)
        let x = width / 2
        let y = height / 2
        let pixel = base.advanced(by: y * row).assumingMemoryBound(to: Float32.self)[x]
        guard pixel.isFinite, pixel > 0 else { return nil }
        return Double(pixel)
    }
}
#endif
