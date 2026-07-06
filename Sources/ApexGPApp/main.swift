import AppKit
import SceneKit
import ApexGPCore
import simd

// Phase 2: Falcon Ridge, now drivable. Opens a SceneKit window showing the full
// circuit and a physics-driven player F1 car spawned on pole. A render-loop
// driver steps the fixed-step vehicle sim from keyboard/gamepad input, the
// camera rig (chase / cockpit / TV / free, C key) follows the real car, and a
// SpriteKit HUD shows live telemetry.

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var rig: CameraRig!
    private var driver: PhysicsDriver!
    private var input: InputController!
    private var hud: HUD!
    private var keyMonitor: Any?

    private let track = Track.falconRidge()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let scene = SCNScene()
        configureAtmosphere(scene)

        // World.
        scene.rootNode.addChildNode(TrackWorld.build(for: track))

        // Player car (physics-driven). The driver seats it on the grid.
        let car = PlayerCar()
        scene.rootNode.addChildNode(car.node)

        // Lighting.
        addLighting(scene)

        // View.
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
        view.scene = scene
        view.showsStatistics = true
        view.backgroundColor = .black
        view.isPlaying = true                 // drive the render loop continuously
        view.rendersContinuously = true

        // Input + HUD + render-loop driver.
        input = InputController()
        hud = HUD(size: view.bounds.size)
        view.overlaySKScene = hud.scene
        driver = PhysicsDriver(car: car, hud: hud, input: input, track: track)
        view.delegate = driver

        // Camera rig — chase/cockpit are car-parented; TV cams track the car.
        rig = CameraRig(view: view, car: car.node, track: track, target: car.node)
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

    // Handles: camera keys (C/V), gearbox mode toggle (G), HUD toggle (H),
    // reset (R), and held driving keys (WASD/arrows, E/Q gears, F DRS) which are
    // forwarded to the InputController for the render loop to poll.
    private func installKeyHandling() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            // Let system shortcuts (Cmd+Q, Cmd+W, …) through untouched.
            if event.modifierFlags.intersection([.command, .control]).isEmpty == false {
                return event
            }
            let code = event.keyCode

            if event.type == .keyUp {
                self.input.keyUp(code)
                return nil
            }

            // keyDown. Discrete actions first, then held-key tracking.
            if !event.isARepeat {
                switch code {
                case 8:   self.rig.cycle();  self.updateTitle();  return nil   // C
                case 9:   self.rig.nextTVCam(); self.updateTitle(); return nil // V
                case 5:   self.input.toggleGearbox(); return nil               // G
                case 4:   self.hud.isVisible.toggle(); return nil              // H
                case 15:  self.driver.requestReset(); return nil               // R
                default: break
                }
            }
            self.input.keyDown(code)
            return nil
        }
    }

    private func updateTitle() {
        let cam = rig?.mode.label ?? "Chase"
        window.title = "ApexGP — Phase 2: Falcon Ridge   |   Cam: \(cam)   "
            + "(WASD/Arrows drive, C/V camera, F DRS, G gearbox, H HUD, R reset)"
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
