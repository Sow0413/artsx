import SwiftUI
import SurveyCore

#if !SURVEY_PLAYGROUND && canImport(ARKit)
import ARKit
#endif

/// 目標の点に仮想の杖を立てる。合わせと誤差は SurveyCore。実機の映像は未確認。
struct ARStakeoutSheet: View {
    @ObservedObject var field: FieldModel
    @StateObject private var model = ARStakeoutModel()
    @Environment(\.dismiss) private var dismiss
    @State private var listener: UUID?
    @State private var viewport = CGSize(width: 1, height: 1)
    @State private var targets: [ARStakeoutTarget] = []

    var body: some View {
        let picture = model.picture(
            targets: targets,
            facing: facing,
            stride: field.pace.strideMeters,
            unit: field.stakeoutUnit.unit,
            switchMeters: field.arHandoff.meters
        )
        NavigationStack {
            ZStack {
                SurveyColor.background
                camera
                staffCanvas(picture)
                VStack(spacing: 8) {
                    AccuracyBadgeView(badge: field.badge, stage: field.stageTransition.stage)
                        .padding(10)
                        .background(SurveyColor.card.opacity(0.94))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    if let picture, picture.numeric {
                        numericGuide(picture)
                    }
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                    panel(targets: targets, picture: picture)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .foregroundStyle(SurveyColor.text)
            .navigationTitle("AR位置出し")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .font(SurveyType(17, .heavy))
                }
            }
        }
        .modifier(SurveyScheme())
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { viewport = geo.size }
                    .onChange(of: geo.size) { _, size in viewport = size }
            }
        }
        .contentShape(Rectangle())
        .gesture(tap)
        .onAppear {
            targets = field.arTargets()
            handoffText = String(format: "%g", field.arHandoff.meters)
            start()
        }
        .onDisappear(perform: stop)
        .onChange(of: picture?.mode) { _, next in
            guard let next, next != model.mode else { return }
            model.mode = next
            ARHandoffCue.play()
        }
    }

    private var camera: some View {
        #if !SURVEY_PLAYGROUND && canImport(ARKit)
        ARPreview()
            .ignoresSafeArea()
        #else
        SurveyColor.background
            .ignoresSafeArea()
        #endif
    }

    private func staffCanvas(_ picture: ARStakeoutPicture?) -> some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard let picture, let frame = model.frame, frame.camera.count == 16 else { return }
                for staff in picture.staffs {
                    guard let base = ARStakeoutMath.project(
                        camera: frame.camera, fx: frame.fx, fy: frame.fy, cx: frame.cx, cy: frame.cy,
                        imageWidth: frame.imageWidth, imageHeight: frame.imageHeight,
                        viewportWidth: size.width, viewportHeight: size.height,
                        worldX: staff.arX, worldY: staff.groundY, worldZ: staff.arZ
                    ), let top = ARStakeoutMath.project(
                        camera: frame.camera, fx: frame.fx, fy: frame.fy, cx: frame.cx, cy: frame.cy,
                        imageWidth: frame.imageWidth, imageHeight: frame.imageHeight,
                        viewportWidth: size.width, viewportHeight: size.height,
                        worldX: staff.arX, worldY: staff.groundY + staff.heightMeters, worldZ: staff.arZ
                    ), base.visible, top.visible else { continue }
                    var path = Path()
                    path.move(to: CGPoint(x: base.x, y: base.y))
                    path.addLine(to: CGPoint(x: top.x, y: top.y))
                    let ink = staff.primary ? SurveyColor.color(OutdoorContrast.yellow) : SurveyColor.text.opacity(0.35)
                    context.stroke(path, with: .color(ink), lineWidth: staff.primary ? 8 : 3)
                    context.fill(Path(ellipseIn: CGRect(x: base.x - 8, y: base.y - 8, width: 16, height: 16)), with: .color(ink))
                    context.draw(
                        Text(staff.label).font(SurveyType(staff.primary ? 28 : 18, .heavy)).foregroundStyle(ink),
                        at: CGPoint(x: top.x, y: top.y - 18)
                    )
                }
            }
            .allowsHitTesting(false)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func panel(targets: [ARStakeoutTarget], picture: ARStakeoutPicture?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let picture {
                Text(picture.errorText)
                    .font(SurveyType(18, .heavy))
                    .foregroundStyle(picture.realign ? SurveyColor.color(OutdoorContrast.black) : SurveyColor.text)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(picture.realign ? SurveyColor.color(OutdoorContrast.yellow) : SurveyColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                if let residual = picture.residualText {
                    Text(residual)
                        .font(SurveyType(16, .heavy))
                }
            }
            Text(groundLine)
                .font(SurveyType(14, .semibold))
                .foregroundStyle(SurveyColor.muted)
            if targets.isEmpty {
                Text("座標簿の点か、図面でタップした点がありません。")
                    .font(SurveyType(16, .heavy))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(targets.prefix(8).enumerated()), id: \.element.id) { offset, target in
                            Button(target.name) { model.index = offset }
                                .buttonStyle(.plain)
                                .font(SurveyType(16, .heavy))
                                .padding(.horizontal, 12)
                                .frame(minHeight: OutdoorContrast.primaryPoints)
                                .background(model.index == offset ? SurveyColor.blue : SurveyColor.card)
                                .foregroundStyle(model.index == offset ? SurveyColor.onAccent : SurveyColor.text)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
            Text(model.pending == nil ? "既知点を選び、その点の地面を画面でタップします。2点以上が推奨です。" : "\(model.pending?.name ?? "")の地面をタップしてください。")
                .font(SurveyType(15, .semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(targets.prefix(8))) { target in
                        Button(target.name) { model.pending = target }
                            .buttonStyle(.plain)
                            .font(SurveyType(15, .heavy))
                            .padding(.horizontal, 10)
                            .frame(minHeight: 48)
                            .background(model.pending?.name == target.name ? SurveyColor.color(OutdoorContrast.yellow) : SurveyColor.card)
                            .foregroundStyle(model.pending?.name == target.name ? SurveyColor.color(OutdoorContrast.black) : SurveyColor.text)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            Text(model.pairs.isEmpty ? "まだ対応点がありません。" : "対応 \(model.pairs.count)点")
                .font(SurveyType(15, .heavy))
            HStack(spacing: 8) {
                Button("既知点で合わせる") { model.alignKnown() }
                    .buttonStyle(.plain)
                    .font(SurveyType(16, .heavy))
                    .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                    .background(model.pairs.count >= 2 ? SurveyColor.blue : SurveyColor.card)
                    .foregroundStyle(model.pairs.count >= 2 ? SurveyColor.onAccent : SurveyColor.muted)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Button("歩行で方位") { model.alignWalk() }
                    .buttonStyle(.plain)
                    .font(SurveyType(16, .heavy))
                    .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                    .background(SurveyColor.card)
                    .foregroundStyle(SurveyColor.text)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            HStack(spacing: 8) {
                ForEach(StakeoutSpeechStyle.allCases, id: \.self) { style in
                    Button(style.label) { field.setStakeoutSpeech(style) }
                        .buttonStyle(.plain)
                        .font(SurveyType(16, .heavy))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(field.stakeoutSpeechStyle.style == style ? SurveyColor.blue : SurveyColor.background)
                        .foregroundStyle(field.stakeoutSpeechStyle.style == style ? SurveyColor.onAccent : SurveyColor.text)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            Text("声は画面の上を前にします。方向が変わったときだけです。")
                .font(SurveyType(14, .semibold))
                .foregroundStyle(SurveyColor.muted)
            Text("切替 \(String(format: "%g", field.arHandoff.meters))m。\(String(format: "%g", field.arHandoff.resumeMeters))mでARに戻ります。")
                .font(SurveyType(15, .heavy))
            HStack(spacing: 8) {
                TextField("切替距離 m", text: $handoffText)
                    .textFieldStyle(.roundedBorder)
                    .font(SurveyType(16, .semibold))
                Button("反映") {
                    handoffNote = field.setARHandoff(handoffText)
                }
                .buttonStyle(.plain)
                .font(SurveyType(16, .heavy))
                .frame(minWidth: 72, minHeight: OutdoorContrast.primaryPoints)
                .background(SurveyColor.blue)
                .foregroundStyle(SurveyColor.onAccent)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if !handoffNote.isEmpty {
                Text(handoffNote)
                    .font(SurveyType(14, .semibold))
            }
            Text("RTK FIXのあいだは、向きを保って位置を足し続けます。")
                .font(SurveyType(13, .semibold))
                .foregroundStyle(SurveyColor.muted)
        }
        .padding(12)
        .background(SurveyColor.card.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @State private var handoffText = ""
    @State private var handoffNote = ""

    private func numericGuide(_ picture: ARStakeoutPicture) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let speech = picture.speech {
                Text(speech)
                    .font(SurveyType(40, .heavy))
                    .foregroundStyle(SurveyColor.text)
            }
            if let detail = picture.detail {
                Text(detail)
                    .font(SurveyType(22, .heavy))
            }
            ARPlanGauge(
                alongCentimeters: picture.alongCentimeters,
                acrossCentimeters: picture.acrossCentimeters,
                spanCentimeters: max(1, Int((field.arHandoff.meters * 100).rounded()))
            )
            .frame(maxWidth: .infinity)
            Text("\(String(format: "%g", field.arHandoff.meters))m未満なので、前後左右をセンチで出します。")
                .font(SurveyType(16, .heavy))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SurveyColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var groundLine: String {
        let source = model.frame?.groundSource ?? ""
        if source.isEmpty { return "地面はまだ検出していません。根元は高さ0に仮定します。" }
        return "杖の根元は\(source)に置きます。"
    }

    private var facing: Double? {
        let position = field.navigationReading.position
        return StakeoutSpeech.screenForward(headingDegrees: position?.headingDegrees)
    }

    private var tap: some Gesture {
        SpatialTapGesture().onEnded { value in
            guard let frame = model.frame, let pending = model.pending else { return }
            let size = viewport
            let ground = ARStakeoutMath.ground(
                lidarY: frame.groundSource == "LiDAR" ? frame.groundY : nil,
                planeY: frame.groundSource == "平面" ? frame.groundY : nil
            )
            guard let hit = ARStakeoutMath.groundHit(
                tapX: value.location.x,
                tapY: value.location.y,
                viewportWidth: size.width,
                viewportHeight: size.height,
                camera: frame.camera,
                fx: frame.fx,
                fy: frame.fy,
                cx: frame.cx,
                cy: frame.cy,
                imageWidth: frame.imageWidth,
                imageHeight: frame.imageHeight,
                groundY: ground.y
            ) else { return }
            model.add(pending, arX: hit.x, arZ: hit.z)
        }
    }

    private func start() {
        let id = UUID()
        listener = id
        SurveyVision.shared.add(id) { frame in
            let position = field.workingReading.position
            let plane = position.flatMap {
                PlaneRectangular.forward(latitudeDegrees: $0.latitudeDegrees, longitudeDegrees: $0.longitudeDegrees, zone: field.drawing.zone)
            }
            model.note(
                frame: frame,
                easting: plane?.eastingMeters,
                northing: plane?.northingMeters,
                rtk: position?.fixQuality == .rtkFix,
                gnssMeters: position?.horizontalAccuracyMeters ?? 0
            )
        }
        SurveyVision.shared.enableGround()
    }

    private func stop() {
        if let listener {
            SurveyVision.shared.remove(listener)
        }
        StakeoutVoice.stop()
    }
}

struct ARPlanGauge: View {
    var alongCentimeters: Int
    var acrossCentimeters: Int
    var spanCentimeters: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(SurveyColor.background)
            Rectangle()
                .fill(SurveyColor.text)
                .frame(height: 3)
            Rectangle()
                .fill(SurveyColor.text)
                .frame(width: 3)
            Circle()
                .fill(SurveyColor.color(OutdoorContrast.yellow))
                .frame(width: 22, height: 22)
                .offset(x: lateral, y: -forward)
            Text("前").font(SurveyType(14, .heavy)).frame(maxHeight: .infinity, alignment: .top)
            Text("うしろ").font(SurveyType(14, .heavy)).frame(maxHeight: .infinity, alignment: .bottom)
            Text("左").font(SurveyType(14, .heavy)).frame(maxWidth: .infinity, alignment: .leading)
            Text("右").font(SurveyType(14, .heavy)).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: 200, height: 200)
        .accessibilityLabel(label)
    }

    private var forward: CGFloat {
        CGFloat(clamped(alongCentimeters))
    }

    private var lateral: CGFloat {
        CGFloat(clamped(acrossCentimeters))
    }

    private func clamped(_ centimeters: Int) -> Double {
        let span = Double(max(spanCentimeters, 1))
        let ratio = min(1, max(-1, Double(centimeters) / span))
        return ratio * 72
    }

    private var label: String {
        let fore = alongCentimeters >= 0 ? "前 \(alongCentimeters)cm" : "うしろ \(-alongCentimeters)cm"
        let side = acrossCentimeters >= 0 ? "右 \(acrossCentimeters)cm" : "左 \(-acrossCentimeters)cm"
        return "\(fore)、\(side)"
    }
}

final class ARStakeoutModel: ObservableObject {
    @Published var pairs: [ARStakeoutPair] = []
    @Published var alignment: ARStakeoutAlignment?
    @Published var index = 0
    @Published var frame: VisionFrame?
    @Published var pending: ARStakeoutTarget?
    @Published var mode = ARGuidanceMode.augmented
    @Published private(set) var walkedMeters = 0.0
    private var lastStep: (Double, Double)?
    private var track: [(Double, Double)] = []

    func note(frame: VisionFrame, easting: Double?, northing: Double?, rtk: Bool, gnssMeters: Double) {
        if alignment != nil, let previous = lastStep {
            let step = ((frame.x - previous.0) * (frame.x - previous.0) + (frame.z - previous.1) * (frame.z - previous.1)).squareRoot()
            if step.isFinite, step < 2 { walkedMeters += step }
        }
        lastStep = (frame.x, frame.z)
        if let easting, let northing {
            if let last = track.last {
                let moved = ((easting - last.0) * (easting - last.0) + (northing - last.1) * (northing - last.1)).squareRoot()
                if moved >= 1 { track.append((easting, northing)) }
            } else {
                track.append((easting, northing))
            }
            if track.count > 8 { track.removeFirst(track.count - 8) }
        }
        self.frame = frame
        if rtk, let alignment, let easting, let northing,
           let corrected = ARStakeoutMath.correct(
            alignment,
            cameraX: frame.x,
            cameraZ: frame.z,
            eastingMeters: easting,
            northingMeters: northing,
            gnssMeters: gnssMeters,
            at: Date()
           ) {
            self.alignment = corrected
            walkedMeters = 0
        }
    }

    func add(_ target: ARStakeoutTarget, arX: Double, arZ: Double) {
        pairs.removeAll { $0.name == target.name }
        pairs.append(ARStakeoutPair(
            name: target.name,
            arX: arX,
            arZ: arZ,
            eastingMeters: target.eastingMeters,
            northingMeters: target.northingMeters
        ))
        pending = nil
    }

    func alignKnown() {
        guard let aligned = ARStakeoutMath.align(pairs: pairs, at: Date()) else { return }
        alignment = aligned
        walkedMeters = 0
    }

    func alignWalk() {
        guard let frame, track.count >= 2, let easting = track.last?.0, let northing = track.last?.1,
              let azimuth = ARStakeoutMath.trackAzimuth(
                fromEasting: track.first?.0 ?? easting,
                fromNorthing: track.first?.1 ?? northing,
                toEasting: easting,
                toNorthing: northing
              ),
              let aligned = ARStakeoutMath.alignWalk(
                cameraX: frame.x,
                cameraZ: frame.z,
                forwardX: frame.forwardX,
                forwardZ: frame.forwardZ,
                eastingMeters: easting,
                northingMeters: northing,
                azimuthDegrees: azimuth,
                at: Date()
              ) else { return }
        alignment = aligned
        walkedMeters = 0
    }

    func picture(targets: [ARStakeoutTarget], facing: Double?, stride: Double?, unit: StakeoutUnit, switchMeters: Double) -> ARStakeoutPicture? {
        guard let alignment else { return nil }
        let current = min(max(0, index), max(0, targets.count - 1))
        let here: (Double, Double)
        if let frame {
            let mapped = alignment.transform.apply(PlanarPoint(x: frame.x, y: frame.z))
            here = (mapped.x, mapped.y)
        } else if let last = track.last {
            here = last
        } else {
            return nil
        }
        let ground = ARStakeoutMath.ground(
            lidarY: frame?.groundSource == "LiDAR" ? frame?.groundY : nil,
            planeY: frame?.groundSource == "平面" ? frame?.groundY : nil
        )
        let seconds = Date().timeIntervalSince(alignment.alignedAt)
        return ARStakeoutMath.picture(
            alignment: alignment,
            targets: targets,
            currentIndex: current,
            groundY: ground.y,
            hereEasting: here.0,
            hereNorthing: here.1,
            facingDegrees: facing,
            strideMeters: stride,
            unit: unit,
            seconds: seconds,
            walkedMeters: walkedMeters,
            current: mode,
            switchMeters: switchMeters
        )
    }
}

#if !SURVEY_PLAYGROUND && canImport(ARKit)
private struct ARPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.automaticallyUpdatesLighting = true
        SurveyVision.shared.attachPreview(view)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: ()) {
        SurveyVision.shared.detachPreview()
    }
}
#endif
