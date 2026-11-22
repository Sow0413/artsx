import Foundation
import SurveyCore

#if canImport(Darwin)
import Darwin
#endif

#if !SURVEY_PLAYGROUND && canImport(ARKit)
import ARKit
#endif

/// hw.machine。シミュレータは arm64 などになり、アンテナ差は既定 0.060m。
enum DeviceIdentity {
    static let machine: String = {
        #if canImport(Darwin)
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        #else
        return "unknown"
        #endif
    }()
}

/// 画面の角度のときだけ、前面で傾きと顔までの距離を見る。映像は保存しない。
enum PhoneSight {
    static func setEnabled(
        _ on: Bool,
        onTilt: @escaping (Double?) -> Void,
        onDistance: @escaping (Double?) -> Void
    ) {
        #if !SURVEY_PLAYGROUND && canImport(CoreMotion)
        if on {
            SystemMotion.shared.onPitchRadians = { pitch in
                onTilt(StatureMath.tiltFromVertical(pitchRadians: pitch))
            }
            SystemMotion.shared.setPitch(true)
        } else {
            SystemMotion.shared.setPitch(false)
            SystemMotion.shared.onPitchRadians = nil
            onTilt(nil)
        }
        #else
        onTilt(nil)
        #endif
        FaceRange.setEnabled(on, onDistance: onDistance)
    }
}

enum FaceRange {
    static func setEnabled(_ on: Bool, onDistance: @escaping (Double?) -> Void) {
        #if !SURVEY_PLAYGROUND && canImport(ARKit)
        FaceSession.shared.setEnabled(on, onDistance: onDistance)
        #else
        onDistance(nil)
        #endif
    }
}

#if !SURVEY_PLAYGROUND && canImport(ARKit)
/// TrueDepth の顔追跡。カメラから顔までの距離を d にする。画面中心ではない。実機は未確認。
final class FaceSession: NSObject, ARSessionDelegate {
    static let shared = FaceSession()
    private var session: ARSession?
    private var onDistance: ((Double?) -> Void)?
    private var lastDistance: Double?
    private var lastAt = Date.distantPast
    private var lastDelivered = Date.distantPast

    func setEnabled(_ on: Bool, onDistance: @escaping (Double?) -> Void) {
        self.onDistance = onDistance
        guard on else {
            session?.pause()
            session = nil
            lastDistance = nil
            onDistance(nil)
            return
        }
        guard ARFaceTrackingConfiguration.isSupported else {
            onDistance(nil)
            return
        }
        if session != nil { return }
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = false
        let session = ARSession()
        session.delegateQueue = .main
        session.delegate = self
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        self.session = session
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let distance = frame.anchors.compactMap { $0 as? ARFaceAnchor }.first.map { face in
            let faceColumn = face.transform.columns.3
            let cameraColumn = frame.camera.transform.columns.3
            let dx = faceColumn.x - cameraColumn.x
            let dy = faceColumn.y - cameraColumn.y
            let dz = faceColumn.z - cameraColumn.z
            return Double((dx * dx + dy * dy + dz * dz).squareRoot())
        }
        let now = Date()
        if let distance {
            lastDistance = distance
            lastAt = now
            guard now.timeIntervalSince(lastDelivered) >= 0.1 else { return }
            lastDelivered = now
            onDistance?(distance)
        } else if now.timeIntervalSince(lastAt) > 0.5 {
            lastDistance = nil
            guard now.timeIntervalSince(lastDelivered) >= 0.1 else { return }
            lastDelivered = now
            onDistance?(nil)
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        lastDistance = nil
        onDistance?(nil)
    }
}
#endif
