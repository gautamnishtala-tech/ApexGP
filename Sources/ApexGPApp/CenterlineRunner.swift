import SceneKit
import ApexGPCore
import simd

/// PHASE 1 SCAFFOLDING — NOT A REAL CAR.
///
/// A simple object that laps the circuit along the centerline at a constant
/// speed, driven from `track.sample(atDistance:)` with distance advanced per
/// frame. It exists purely so the TV cameras have a moving target to track and
/// so the world can be verified visually. Phase 2 replaces this with real,
/// physics-driven cars; delete this file then.
final class CenterlineRunner: NSObject, SCNSceneRendererDelegate {
    let node: SCNNode
    private let track: Track
    private let speed: Float          // meters / second
    private var distance: Float = 0
    private var lastTime: TimeInterval = 0

    init(track: Track, speed: Float = 50) {
        self.track = track
        self.speed = speed

        // A bright marker so it's obvious this is scaffolding, not a car.
        let n = SCNNode()
        let body = SCNNode(geometry: SCNSphere(radius: 1.2))
        body.geometry!.firstMaterial!.diffuse.contents = NSColor.systemYellow
        body.geometry!.firstMaterial!.emission.contents = NSColor(red: 0.6, green: 0.6, blue: 0, alpha: 1)
        body.position = SCNVector3(0, 1.2, 0)
        n.addChildNode(body)
        let pole = SCNNode(geometry: SCNCylinder(radius: 0.08, height: 1.2))
        pole.geometry!.firstMaterial!.diffuse.contents = NSColor.black
        pole.position = SCNVector3(0, 0.6, 0)
        n.addChildNode(pole)
        n.name = "centerlineRunner"
        self.node = n
        super.init()
        place(at: 0)
    }

    private func place(at d: Float) {
        let s = track.sample(atDistance: d)
        node.simdPosition = s.position + s.up * 0.1
        node.simdOrientation = TrackWorld.orientation(forward: s.forward, up: s.up)
    }

    // MARK: SCNSceneRendererDelegate (the render loop)

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if lastTime == 0 { lastTime = time; return }
        let dt = Float(min(time - lastTime, 0.1))   // clamp big hitches
        lastTime = time
        distance += speed * dt
        place(at: distance)
    }
}
