import SceneKit
import ApexGPCore
import simd

/// The set of cameras the player can cycle through with the C key.
enum CameraMode: Int, CaseIterable {
    case chase
    case cockpit
    case tv
    case free

    var label: String {
        switch self {
        case .chase:   return "Chase"
        case .cockpit: return "Cockpit"
        case .tv:      return "TV"
        case .free:    return "Free"
        }
    }
}

/// Owns every camera node and switches the active point of view. Chase and
/// cockpit cams are parented to the followed car; TV cams are static nodes
/// placed around the lap that track a target via look-at constraints; free cam
/// is the orbit camera (SCNView.allowsCameraControl).
@MainActor
final class CameraRig {
    let chase = SCNNode()
    let cockpit = SCNNode()
    let free = SCNNode()
    private(set) var tvCams: [SCNNode] = []

    private(set) var mode: CameraMode = .chase
    private var tvIndex = 0

    private unowned let view: SCNView

    init(view: SCNView, car: SCNNode, track: Track, target: SCNNode) {
        self.view = view

        // Chase: behind & above the car (car-local forward is -Z).
        chase.camera = makeCamera()
        chase.position = SCNVector3(0, 2.8, 9.5)
        chase.eulerAngles.x = -0.12
        car.addChildNode(chase)

        // Cockpit: at driver-eye height, slightly behind the nose.
        cockpit.camera = makeCamera()
        cockpit.camera!.fieldOfView = 65
        cockpit.position = SCNVector3(0, 1.1, 0.2)
        cockpit.eulerAngles.x = -0.02
        car.addChildNode(cockpit)

        // Free: orbit camera, positioned to take in the start/finish area.
        free.camera = makeCamera()
        let line = track.sample(atDistance: 0)
        free.simdPosition = line.position + SIMD3(0, 60, 120)
        free.simdLook(at: line.position, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))

        // TV cams: a handful of static trackside cameras at points around the
        // lap, each tracking the moving target. Placed off the outside edge,
        // raised on a "tower".
        let stations: [Float] = [0.06, 0.22, 0.40, 0.58, 0.78, 0.92]
        for frac in stations {
            let s = track.sample(atDistance: track.length * frac)
            let cam = SCNNode()
            cam.camera = makeCamera()
            cam.camera!.fieldOfView = 38   // long lens look
            // Place outside the right edge, up on a tower.
            cam.simdPosition = s.rightEdge + s.right * 18 + SIMD3(0, 12, 0)
            let look = SCNLookAtConstraint(target: target)
            look.isGimbalLockEnabled = true
            cam.constraints = [look]
            tvCams.append(cam)
        }

        apply()
    }

    private func makeCamera() -> SCNCamera {
        let c = SCNCamera()
        c.zFar = 4000
        c.zNear = 0.3
        c.fieldOfView = 55
        return c
    }

    /// Attach the TV cameras to the scene graph (they are not car-parented).
    func installTVCams(in root: SCNNode) {
        for cam in tvCams { root.addChildNode(cam) }
    }

    /// Cycle to the next camera mode (C key).
    func cycle() {
        let all = CameraMode.allCases
        mode = all[(mode.rawValue + 1) % all.count]
        apply()
    }

    /// Within TV mode, jump to the next trackside camera (V key).
    func nextTVCam() {
        guard mode == .tv, !tvCams.isEmpty else { return }
        tvIndex = (tvIndex + 1) % tvCams.count
        apply()
    }

    private func apply() {
        switch mode {
        case .chase:
            view.pointOfView = chase
            view.allowsCameraControl = false
        case .cockpit:
            view.pointOfView = cockpit
            view.allowsCameraControl = false
        case .tv:
            view.pointOfView = tvCams.isEmpty ? chase : tvCams[tvIndex]
            view.allowsCameraControl = false
        case .free:
            view.pointOfView = free
            view.allowsCameraControl = true
        }
    }
}
