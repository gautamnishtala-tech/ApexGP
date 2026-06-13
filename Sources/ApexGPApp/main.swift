import AppKit
import SceneKit
import ApexGPCore

// Phase 0 skeleton: opens a SceneKit window showing the test-oval track ribbon
// and a placeholder car, with free camera orbit (drag to look, scroll to zoom).
// Run with `swift run ApexGPApp` or open Package.swift in Xcode.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let scene = SCNScene()
        scene.background.contents = NSColor(red: 0.35, green: 0.55, blue: 0.85, alpha: 1)

        let grass = SCNNode(geometry: SCNFloor())
        (grass.geometry as! SCNFloor).reflectivity = 0
        grass.geometry!.firstMaterial!.diffuse.contents = NSColor(red: 0.18, green: 0.42, blue: 0.16, alpha: 1)
        scene.rootNode.addChildNode(grass)

        scene.rootNode.addChildNode(Self.trackNode(for: Track.testOval()))
        let car = Self.placeholderCar()
        scene.rootNode.addChildNode(car)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light!.type = .directional
        sun.light!.castsShadow = true
        sun.eulerAngles = SCNVector3(-Float.pi / 3, .pi / 4, 0)
        scene.rootNode.addChildNode(sun)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 400
        scene.rootNode.addChildNode(ambient)

        // Chase camera, parented to the car: sits behind and above (car-local
        // forward is -Z), tilted down to frame the car and the road ahead.
        // Because it's a child node it follows automatically once Phase 2
        // makes the car drivable.
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera!.zFar = 2000
        camera.position = SCNVector3(0, 2.8, 9.5)
        camera.eulerAngles.x = -0.12
        car.addChildNode(camera)

        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
        view.scene = scene
        view.pointOfView = camera
        view.allowsCameraControl = true
        view.showsStatistics = true

        window = NSWindow(contentRect: view.frame,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "ApexGP — Phase 0"
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Flat asphalt ribbon along the track centerline. Phase 1 replaces this
    /// with proper mesh generation (kerbs, banking, barriers) built from the
    /// same `Track.samples(spacing:)` contract used here.
    static func trackNode(for track: Track) -> SCNNode {
        let parent = SCNNode()
        let samples = track.samples(spacing: 8)
        let n = samples.count
        for i in 0..<n {
            let a = samples[i].position
            let b = samples[(i + 1) % n].position
            let mid = (a + b) / 2
            let segmentLength = simd_distance(a, b)
            let segment = SCNNode(geometry: SCNBox(width: CGFloat(samples[i].width),
                                                   height: 0.1,
                                                   length: CGFloat(segmentLength) + 0.5,
                                                   chamferRadius: 0))
            segment.geometry!.firstMaterial!.diffuse.contents = NSColor.darkGray
            segment.simdPosition = mid
            segment.simdLook(at: b, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, 1))
            parent.addChildNode(segment)
        }
        return parent
    }

    /// Box-and-wheels stand-in so there is something car-shaped on the grid.
    static func placeholderCar() -> SCNNode {
        let car = SCNNode()
        let body = SCNNode(geometry: SCNBox(width: 1.9, height: 0.6, length: 4.5, chamferRadius: 0.15))
        body.geometry!.firstMaterial!.diffuse.contents = NSColor.systemRed
        body.position = SCNVector3(0, 0.5, 0)
        car.addChildNode(body)
        for (x, z): (Float, Float) in [(-0.95, -1.5), (0.95, -1.5), (-0.95, 1.5), (0.95, 1.5)] {
            let wheel = SCNNode(geometry: SCNCylinder(radius: 0.33, height: 0.35))
            wheel.geometry!.firstMaterial!.diffuse.contents = NSColor.black
            wheel.eulerAngles.z = .pi / 2
            wheel.position = SCNVector3(x, 0.33, z)
            car.addChildNode(wheel)
        }
        // Park it on the bottom straight of the test oval, facing the
        // counter-clockwise direction so the lap is all left turns.
        car.position = SCNVector3(0, 0, 80)
        car.eulerAngles.y = -.pi / 2
        return car
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
