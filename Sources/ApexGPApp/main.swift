import AppKit
import SceneKit
import ApexGPCore
import simd

// Phase 1: Falcon Ridge. Opens a SceneKit window showing the full circuit —
// asphalt ribbon, kerbs, grass, barriers, start/finish line, grid boxes — with
// a camera rig (chase / cockpit / TV / free) cycled with the C key, sky + fog
// atmosphere, and a dummy centerline runner for TV cameras to track.

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var rig: CameraRig!
    private var runner: CenterlineRunner!
    private var keyMonitor: Any?

    private let track = Track.falconRidge()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let scene = SCNScene()
        configureAtmosphere(scene)

        // World.
        scene.rootNode.addChildNode(TrackWorld.build(for: track))

        // Placeholder car parked on pole (grid slot 0).
        let car = Self.placeholderCar()
        let pole = track.gridSlots()[0]
        let poleUp = simd_normalize(simd_cross(pole.right, pole.forward))
        car.simdPosition = pole.position
        car.simdOrientation = TrackWorld.orientation(forward: pole.forward, up: poleUp)
        scene.rootNode.addChildNode(car)

        // Dummy centerline runner (Phase 1 scaffolding) + render loop.
        runner = CenterlineRunner(track: track, speed: 50)
        scene.rootNode.addChildNode(runner.node)

        // Lighting.
        addLighting(scene)

        // View.
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
        view.scene = scene
        view.showsStatistics = true
        view.backgroundColor = .black
        view.delegate = runner
        view.isPlaying = true                 // drive the render loop continuously
        view.rendersContinuously = true

        // Camera rig — TV cams track the runner.
        rig = CameraRig(view: view, car: car, track: track, target: runner.node)
        rig.installTVCams(in: scene.rootNode)

        // Window.
        window = NSWindow(contentRect: view.frame,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        updateTitle()

        installKeyHandling()

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Atmosphere

    private func configureAtmosphere(_ scene: SCNScene) {
        // Procedural-ish sky: vertical gradient from deep blue to pale horizon.
        scene.background.contents = skyGradient()
        scene.lightingEnvironment.contents = skyGradient()
        scene.lightingEnvironment.intensity = 0.6

        // Distance fog blending the far track/barriers into the horizon.
        scene.fogColor = NSColor(red: 0.72, green: 0.80, blue: 0.90, alpha: 1)
        scene.fogStartDistance = 350
        scene.fogEndDistance = 1600
        scene.fogDensityExponent = 2
    }

    private func skyGradient() -> NSImage {
        let w = 8, h = 256
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        let top = NSColor(red: 0.18, green: 0.36, blue: 0.66, alpha: 1)
        let bottom = NSColor(red: 0.78, green: 0.86, blue: 0.95, alpha: 1)
        let gradient = NSGradient(starting: bottom, ending: top)!
        gradient.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: 90)
        img.unlockFocus()
        return img
    }

    private func addLighting(_ scene: SCNScene) {
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light!.type = .directional
        sun.light!.intensity = 1000
        sun.light!.castsShadow = true
        sun.light!.shadowMode = .deferred
        sun.light!.shadowSampleCount = 8
        sun.light!.maximumShadowDistance = 250
        sun.eulerAngles = SCNVector3(-Float.pi / 3, .pi / 4, 0)
        scene.rootNode.addChildNode(sun)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 350
        ambient.light!.color = NSColor(red: 0.7, green: 0.78, blue: 0.9, alpha: 1)
        scene.rootNode.addChildNode(ambient)
    }

    // MARK: Input

    private func installKeyHandling() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c":
                self.rig.cycle()
                self.updateTitle()
                return nil
            case "v":
                self.rig.nextTVCam()
                self.updateTitle()
                return nil
            default:
                return event
            }
        }
    }

    private func updateTitle() {
        let cam = rig?.mode.label ?? "Chase"
        window.title = "ApexGP — Phase 1: Falcon Ridge   |   Cam: \(cam)   "
            + "(C: cycle camera, V: next TV cam, drag/scroll in Free cam)"
    }

    // MARK: Placeholder car (box + wheels stand-in)

    static func placeholderCar() -> SCNNode {
        let car = SCNNode()
        car.name = "playerCar"
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
        return car
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
