import SceneKit
import ApexGPCore
import simd

/// The render-loop driver: an `SCNSceneRendererDelegate` that each frame reads
/// the real frame delta, gathers `DriverInput`, advances the fixed-step physics
/// clock, steps `VehiclePhysics`, and positions/orients the car node from the
/// interpolated state — then animates the wheels and refreshes the HUD.
///
/// It owns no gameplay logic: all dynamics live in `ApexGPCore`; this only feeds
/// input in and renders state out. SceneKit calls `renderer(_:updateAtTime:)` on
/// its render thread, which is the sanctioned place to mutate scene nodes.
final class PhysicsDriver: NSObject, SCNSceneRendererDelegate {
    private var physics: VehiclePhysics
    private var clock = FixedStepClock(hz: 240)

    private let car: PlayerCar
    private let hud: HUD          // @MainActor (SpriteKit) — updated via a main hop
    private let input: InputController

    // Immutable spawn data, so R can rebuild the sim at the grid.
    private let config: VehicleConfig
    private let barriers: TrackBarriers
    private let spawn: VehicleState

    // The circuit, kept so `place` can ride the car on the real road surface
    // (elevation + banking) — the planar sim only tracks X/Z.
    private let track: Track

    private var lastTime: TimeInterval = 0
    private let resetLock = NSLock()
    private var pendingReset = false

    // Along-track arc length of the car's surface point last frame. Feeding it
    // back into the windowed `surfaceFrame` keeps the height query on the car's
    // own level so it can't snap through a crossover/bridge to another level.
    // `nil` forces a global search (first frame / after reset); it's re-seeded
    // from that global result. The window must cover one frame's travel at top
    // speed yet stay under a crossover's arc-length separation.
    private var surfaceDistance: Float? = nil
    private let surfaceWindow: Float = 50

    init(car: PlayerCar, hud: HUD, input: InputController, track: Track) {
        self.car = car
        self.hud = hud
        self.input = input
        self.config = VehicleConfig()
        self.barriers = TrackBarriers(track: track)
        self.track = track

        // Spawn on pole (grid slot 0), facing the direction of travel.
        let pole = track.gridSlots()[0]
        let heading = atan2(pole.forward.x, -pole.forward.z)
        self.spawn = VehicleState(position: pole.position, velocity: .zero,
                                  heading: heading, gear: 1)
        self.physics = VehiclePhysics(config: config, initialState: spawn, barriers: barriers)
        super.init()
        place(physics.state)   // seat the car on the grid before the first frame
    }

    /// Rebuild the sim back at the grid (R key). Deferred to the render thread.
    func requestReset() { resetLock.lock(); pendingReset = true; resetLock.unlock() }

    // MARK: - Render loop

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        resetLock.lock()
        if pendingReset {
            pendingReset = false
            physics = VehiclePhysics(config: config, initialState: spawn, barriers: barriers)
            clock = FixedStepClock(hz: 240)
            surfaceDistance = nil   // re-seed the height query globally at the grid
        }
        resetLock.unlock()

        if lastTime == 0 { lastTime = time; place(physics.state); return }
        let frameDelta = Float(min(time - lastTime, 0.1))   // clamp big hitches
        lastTime = time

        let di = input.poll(frameDelta: frameDelta)
        physics.drsRequested = input.drsRequested
        physics.automaticGearbox = input.automaticGearbox

        let n = clock.advance(frameDelta: frameDelta)
        for _ in 0..<n { physics.step(input: di, dt: clock.dt) }

        let s = physics.interpolatedState(alpha: clock.alpha)
        place(s)

        let fwd = SIMD3<Float>(sin(s.heading), 0, -cos(s.heading))
        let forwardSpeed = simd_dot(s.velocity, fwd)
        car.update(steer: di.steer, braking: di.brake,
                   forwardSpeed: forwardSpeed, frameDelta: frameDelta)

        // HUD is SpriteKit (main-actor bound); hand it a Sendable snapshot.
        let snapshot = physics.telemetry
        let auto = input.automaticGearbox
        let hud = self.hud
        DispatchQueue.main.async {
            MainActor.assumeIsolated { hud.update(telemetry: snapshot, automaticGearbox: auto) }
        }
    }

    /// Position + orient the car node from a physics state. The sim is planar
    /// (X–Z only), so the vertical placement comes from the road itself: query
    /// the track surface under the car's X–Z, seat its node at that elevation
    /// (the node origin already sits at wheel-contact height), and orient it to
    /// the banked surface normal so it pitches onto climbs and rolls with
    /// banking instead of staying flat at spawn height.
    private func place(_ s: VehicleState) {
        let fwd = SIMD3<Float>(sin(s.heading), 0, -cos(s.heading))
        // Windowed query around last frame's along-track distance (global on the
        // first frame, when surfaceDistance is nil) so the height stays on the
        // car's own level; track the returned distance for next frame.
        let surface = track.surfaceFrame(nearX: s.position.x, z: s.position.z,
                                         aroundDistance: surfaceDistance,
                                         window: surfaceWindow)
        surfaceDistance = surface.distance
        car.node.simdPosition = SIMD3(s.position.x, surface.elevation, s.position.z)
        car.node.simdOrientation = TrackWorld.orientation(forward: fwd, up: surface.up)
    }
}
