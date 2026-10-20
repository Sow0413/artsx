import SwiftUI
import SurveyCore

#if !SURVEY_PLAYGROUND && canImport(ARKit)
import ARKit
#endif

#if !SURVEY_PLAYGROUND && canImport(CoreMotion)
import CoreMotion
#endif

/// 丁張の相対高。視覚慣性を主に、気圧と IMU を補助にする。実機のドリフトは未測定。
final class RelativeFollower: ObservableObject {
    @Published private(set) var fix: RelativeFix?
    @Published private(set) var readyToAlign = false
    @Published private(set) var notice: String?

    private var track = RelativeTrack()
    private var visualUp: Double?
    private var visualX: Double?
    private var visualZ: Double?
    private var baro: Double?
    private var quality: RelativeQuality = .lost
    private var pendingAccel: Double?
    private var gnssHeight: Double?
    private var gnssTrusted = false
    private var gnssVertical: Double?
    private var pole: Double?
    private var lastPublish = Date.distantPast
    private var started = false

    #if !SURVEY_PLAYGROUND && canImport(ARKit)
    private let vision = RelativeVision()
    #endif
    #if !SURVEY_PLAYGROUND && canImport(CoreMotion)
    private let altimeter = CMAltimeter()
    private let altimeterQueue = OperationQueue()
    #endif

    func start() {
        guard !started else { return }
        started = true
        #if !SURVEY_PLAYGROUND && canImport(ARKit) && canImport(CoreMotion)
        vision.onFrame = { [weak self] up, x, z, quality in
            self?.noteVision(up: up, x: x, z: z, quality: quality)
        }
        vision.start()
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: altimeterQueue) { [weak self] data, _ in
                guard let meters = data?.relativeAltitude.doubleValue, meters.isFinite else { return }
                DispatchQueue.main.async { self?.noteBaro(meters) }
            }
        }
        SystemMotion.shared.onRelativeSample = { [weak self] userX, userY, userZ, gravityX, gravityY, gravityZ in
            guard let up = RelativeHeight.upAcceleration(
                userX: userX, userY: userY, userZ: userZ,
                gravityX: gravityX, gravityY: gravityY, gravityZ: gravityZ
            ) else { return }
            self?.noteAccel(up)
        }
        SystemMotion.shared.setRelativeMotion(true)
        notice = nil
        #else
        notice = "追跡は実機で使います。ゼロ合わせの計算は同じです。"
        #endif
    }

    func stop() {
        guard started else { return }
        started = false
        #if !SURVEY_PLAYGROUND && canImport(ARKit) && canImport(CoreMotion)
        vision.stop()
        altimeter.stopRelativeAltitudeUpdates()
        SystemMotion.shared.setRelativeMotion(false)
        #endif
    }

    func setSurvey(ellipsoidal: Double?, trusted: Bool, vertical: Double?, pole: Double?) {
        gnssHeight = ellipsoidal
        gnssTrusted = trusted
        gnssVertical = vertical
        self.pole = pole
        guard started else { return }
        publish(force: trusted != (fix?.channel == .gnssFix))
    }

    @discardableResult
    func align(name: String, knownHeight: Double) -> Bool {
        guard let visualUp, let visualX, let visualZ, quality == .normal else {
            notice = "追跡が安定してからゼロを合わせてください。"
            return false
        }
        guard track.align(
            name: name,
            knownHeight: knownHeight,
            visualUp: visualUp,
            visualX: visualX,
            visualZ: visualZ,
            baro: baro,
            at: Date()
        ) != nil else { return false }
        notice = "\(name)でゼロを合わせました。"
        publish(force: true)
        return true
    }

    private func noteVision(up: Double, x: Double, z: Double, quality: RelativeQuality) {
        visualUp = up
        visualX = x
        visualZ = z
        self.quality = quality
        publish(force: false)
    }

    private func noteBaro(_ meters: Double) {
        baro = meters
        publish(force: false)
    }

    private func noteAccel(_ metersPerSecondSquared: Double) {
        pendingAccel = metersPerSecondSquared
        publish(force: false)
    }

    private func publish(force: Bool) {
        let now = Date()
        let sample = RelativeSample(
            at: now,
            visualUp: visualUp,
            visualX: visualX,
            visualZ: visualZ,
            baro: baro,
            upAcceleration: pendingAccel,
            quality: quality,
            gnssEllipsoidal: gnssHeight,
            gnssTrustedFix: gnssTrusted,
            gnssVerticalAccuracy: gnssVertical,
            poleMeters: pole
        )
        pendingAccel = nil
        let next = track.consume(sample)
        let ready = quality == .normal && visualUp != nil
        if ready != readyToAlign { readyToAlign = ready }
        guard force || now.timeIntervalSince(lastPublish) >= 0.1 else { return }
        lastPublish = now
        fix = next
    }
}

struct RelativeStageBadge: View {
    let badge: RelativeBadge

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(badge.tone.mark)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 4) {
                Text(RelativeBadge.stageLabel)
                    .font(SurveyType(18, .heavy))
                    .foregroundStyle(SurveyColor.color(OutdoorContrast.black))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(SurveyColor.color(OutdoorContrast.yellow), in: Capsule())
                Text(badge.text)
                    .font(SurveyType(18, .heavy))
                    .fixedSize(horizontal: false, vertical: true)
                if badge.needsRealign {
                    Text(RelativeHeight.realignWord)
                        .font(SurveyType(22, .heavy))
                        .foregroundStyle(SurveyColor.color(OutdoorContrast.black))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(SurveyColor.color(OutdoorContrast.yellow))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints, alignment: .leading)
        .foregroundStyle(SurveyColor.text)
        .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SurveyColor.line, lineWidth: SurveyColor.stroke)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge.accessibilityText)
    }
}

#if !SURVEY_PLAYGROUND && canImport(ARKit)
private final class RelativeVision: NSObject, ARSessionDelegate {
    let session = ARSession()
    var onFrame: ((Double, Double, Double, RelativeQuality) -> Void)?
    private var last = Date.distantPast

    func start() {
        guard ARWorldTrackingConfiguration.isSupported else { return }
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        session.delegate = self
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        session.pause()
        onFrame = nil
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = Date()
        guard now.timeIntervalSince(last) >= 0.1 else { return }
        last = now
        let column = frame.camera.transform.columns.3
        let quality: RelativeQuality
        switch frame.camera.trackingState {
        case .normal:
            quality = .normal
        case .limited:
            quality = .limited
        case .notAvailable:
            quality = .lost
        }
        let up = Double(column.y)
        let x = Double(column.x)
        let z = Double(column.z)
        DispatchQueue.main.async { [weak self] in
            self?.onFrame?(up, x, z, quality)
        }
    }
}
#endif
