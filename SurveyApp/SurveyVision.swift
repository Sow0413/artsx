import Foundation
import SurveyCore

struct VisionFrame {
    var up: Double
    var x: Double
    var z: Double
    var forwardX: Double
    var forwardZ: Double
    var quality: RelativeQuality
}

/// 背面カメラの視覚慣性は一つだけ動かす。丁張の相対高と歩行推測が分け合う。映像は保存しない。実機は未確認。
final class SurveyVision {
    static let shared = SurveyVision()
    private var listeners: [UUID: (VisionFrame) -> Void] = [:]

    #if !SURVEY_PLAYGROUND && canImport(ARKit)
    private let session = ARSessionBox()
    #endif

    private init() {}

    func add(_ id: UUID, _ handler: @escaping (VisionFrame) -> Void) {
        listeners[id] = handler
        #if !SURVEY_PLAYGROUND && canImport(ARKit)
        if listeners.count == 1 {
            session.start { [weak self] frame in
                self?.listeners.values.forEach { $0(frame) }
            }
        }
        #endif
    }

    func remove(_ id: UUID) {
        listeners.removeValue(forKey: id)
        #if !SURVEY_PLAYGROUND && canImport(ARKit)
        if listeners.isEmpty {
            session.stop()
        }
        #endif
    }
}

#if !SURVEY_PLAYGROUND && canImport(ARKit)
import ARKit

private final class ARSessionBox: NSObject, ARSessionDelegate {
    let session = ARSession()
    private var onFrame: ((VisionFrame) -> Void)?
    private var last = Date.distantPast
    private var running = false

    func start(_ onFrame: @escaping (VisionFrame) -> Void) {
        self.onFrame = onFrame
        guard !running, ARWorldTrackingConfiguration.isSupported else { return }
        running = true
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        session.delegate = self
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        guard running else { return }
        running = false
        session.pause()
        onFrame = nil
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = Date()
        guard now.timeIntervalSince(last) >= 0.1 else { return }
        last = now
        let column = frame.camera.transform.columns.3
        let backward = frame.camera.transform.columns.2
        let sample = VisionFrame(
            up: Double(column.y),
            x: Double(column.x),
            z: Double(column.z),
            forwardX: -Double(backward.x),
            forwardZ: -Double(backward.z),
            quality: Self.quality(frame.camera.trackingState)
        )
        DispatchQueue.main.async { [weak self] in
            self?.onFrame?(sample)
        }
    }

    private static func quality(_ state: ARCamera.TrackingState) -> RelativeQuality {
        switch state {
        case .normal: return .normal
        case .limited: return .limited
        case .notAvailable: return .lost
        }
    }
}
#endif
