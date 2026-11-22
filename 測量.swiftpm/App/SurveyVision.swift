import Foundation
import SurveyCore

struct VisionFrame {
    var up: Double
    var x: Double
    var z: Double
    var forwardX: Double
    var forwardZ: Double
    var quality: RelativeQuality
    var groundY: Double? = nil
    var groundSource: String = ""
    var camera: [Double] = []
    var fx: Double = 0
    var fy: Double = 0
    var cx: Double = 0
    var cy: Double = 0
    var imageWidth: Double = 0
    var imageHeight: Double = 0
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

    /// 位置出しのあいだ、水平面と LiDAR のメッシュを足す。追跡はリセットしない。
    func enableGround() {
        #if !SURVEY_PLAYGROUND && canImport(ARKit)
        session.enableGround()
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
        session.delegate = self
        session.run(configuration(ground: false), options: [.resetTracking, .removeExistingAnchors])
    }

    func enableGround() {
        guard ARWorldTrackingConfiguration.isSupported else { return }
        if !running {
            running = true
            session.delegate = self
            session.run(configuration(ground: true), options: [.resetTracking, .removeExistingAnchors])
        } else {
            session.delegate = self
            session.run(configuration(ground: true), options: [])
        }
    }

    func attach(_ view: ARSCNView) {
        preview = view
        view.session = session
        session.delegate = self
        enableGround()
    }

    func detach() {
        preview = nil
    }

    private weak var preview: ARSCNView?

    private func configuration(ground: Bool) -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        if ground {
            configuration.planeDetection = [.horizontal]
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                configuration.sceneReconstruction = .mesh
            }
        }
        return configuration
    }

    func stop() {
        guard running else { return }
        running = false
        session.pause()
        onFrame = nil
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        (preview as (any ARSessionDelegate)?)?.session?(session, didUpdate: frame)
        let now = Date()
        guard now.timeIntervalSince(last) >= 0.1 else { return }
        last = now
        let transform = frame.camera.transform
        let column = transform.columns.3
        let backward = transform.columns.2
        var camera: [Double] = []
        for part in [transform.columns.0, transform.columns.1, transform.columns.2, transform.columns.3] {
            camera.append(Double(part.x))
            camera.append(Double(part.y))
            camera.append(Double(part.z))
            camera.append(Double(part.w))
        }
        let intrinsics = frame.camera.intrinsics
        let ground = Self.ground(in: frame, cameraX: column.x, cameraZ: column.z)
        let sample = VisionFrame(
            up: Double(column.y),
            x: Double(column.x),
            z: Double(column.z),
            forwardX: -Double(backward.x),
            forwardZ: -Double(backward.z),
            quality: Self.quality(frame.camera.trackingState),
            groundY: ground.y,
            groundSource: ground.source,
            camera: camera,
            fx: Double(intrinsics.columns.0.x),
            fy: Double(intrinsics.columns.1.y),
            cx: Double(intrinsics.columns.2.x),
            cy: Double(intrinsics.columns.2.y),
            imageWidth: Double(frame.camera.imageResolution.width),
            imageHeight: Double(frame.camera.imageResolution.height)
        )
        DispatchQueue.main.async { [weak self] in
            self?.onFrame?(sample)
        }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        (preview as (any ARSessionDelegate)?)?.session?(session, didAdd: anchors)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        (preview as (any ARSessionDelegate)?)?.session?(session, didUpdate: anchors)
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        (preview as (any ARSessionDelegate)?)?.session?(session, didRemove: anchors)
    }

    private static func ground(in frame: ARFrame, cameraX: Float, cameraZ: Float) -> (y: Double?, source: String) {
        var lidar: Double?
        var planeY: Double?
        var best = Double.greatestFiniteMagnitude
        for anchor in frame.anchors {
            if let mesh = anchor as? ARMeshAnchor {
                let origin = mesh.transform.columns.3
                let dx = Double(origin.x - cameraX)
                let dz = Double(origin.z - cameraZ)
                if dx * dx + dz * dz < 25 {
                    lidar = Double(origin.y)
                }
            }
            if let plane = anchor as? ARPlaneAnchor, plane.alignment == .horizontal {
                let origin = plane.transform.columns.3
                let dx = Double(origin.x - cameraX)
                let dz = Double(origin.z - cameraZ)
                let span = dx * dx + dz * dz
                if span < best {
                    best = span
                    planeY = Double(origin.y)
                }
            }
        }
        if lidar != nil { return (lidar, "LiDAR") }
        if planeY != nil { return (planeY, "平面") }
        return (nil, "")
    }

    private static func quality(_ state: ARCamera.TrackingState) -> RelativeQuality {
        switch state {
        case .normal: return .normal
        case .limited: return .limited
        case .notAvailable: return .lost
        }
    }
}

extension SurveyVision {
    func attachPreview(_ view: ARSCNView) {
        session.attach(view)
    }

    func detachPreview() {
        session.detach()
    }
}
#endif
