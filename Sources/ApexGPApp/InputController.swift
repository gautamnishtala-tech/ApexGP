import AppKit
import GameController
import simd
import ApexGPCore

/// Turns keyboard (WASD + arrows) and a GameController-framework gamepad into a
/// `DriverInput`. Keyboard steering (and pedals) run through a small smoothing
/// ramp so digital keys feel analog instead of snapping. Analog gamepad axes
/// bypass the ramp and are used directly.
///
/// Held-key state is mutated on the main thread (from the `NSEvent` monitor) and
/// read on the SceneKit render thread, so the key set is guarded by a lock.
/// This class only produces input; it never touches gameplay state.
final class InputController: @unchecked Sendable {

    // Virtual key codes (layout-independent) for the held driving keys.
    private enum K {
        static let a: UInt16 = 0,  s: UInt16 = 1,  d: UInt16 = 2,  w: UInt16 = 13
        static let q: UInt16 = 12, e: UInt16 = 14, f: UInt16 = 3
        static let left: UInt16 = 123, right: UInt16 = 124
        static let down: UInt16 = 125, up: UInt16 = 126
    }

    private let lock = NSLock()
    private var held = Set<UInt16>()

    // Smoothed axes (persist between frames).
    private var steer: Float = 0
    private var throttle: Float = 0
    private var brake: Float = 0

    /// DRS request this frame (read by the driver after `poll`).
    private(set) var drsRequested = false
    /// Auto/manual gearbox toggle (flipped by the G key on the main thread).
    private let modeLock = NSLock()
    private var _automaticGearbox = true
    var automaticGearbox: Bool {
        get { modeLock.lock(); defer { modeLock.unlock() }; return _automaticGearbox }
    }
    func toggleGearbox() { modeLock.lock(); _automaticGearbox.toggle(); modeLock.unlock() }

    init() {
        // Let a wireless pad pair without an explicit UI.
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
    }

    // MARK: - Held-key tracking (main thread)

    func keyDown(_ code: UInt16) { lock.lock(); held.insert(code); lock.unlock() }
    func keyUp(_ code: UInt16)   { lock.lock(); held.remove(code); lock.unlock() }

    // MARK: - Per-frame input (render thread)

    /// Produce this frame's `DriverInput`, applying steering/pedal smoothing.
    func poll(frameDelta: Float) -> DriverInput {
        lock.lock(); let keys = held; lock.unlock()

        var targetSteer: Float = 0
        if keys.contains(K.a) || keys.contains(K.left)  { targetSteer -= 1 }
        if keys.contains(K.d) || keys.contains(K.right) { targetSteer += 1 }
        var targetThrottle: Float = (keys.contains(K.w) || keys.contains(K.up)) ? 1 : 0
        var targetBrake: Float    = (keys.contains(K.s) || keys.contains(K.down)) ? 1 : 0
        var drs = keys.contains(K.f)
        var gearUp = keys.contains(K.e)
        var gearDown = keys.contains(K.q)

        // Gamepad overrides / augments the keyboard when present.
        if let gp = GCController.controllers().first?.extendedGamepad {
            let ax = gp.leftThumbstick.xAxis.value
            if abs(ax) > 0.12 { targetSteer = ax }            // analog, direct
            targetThrottle = max(targetThrottle, gp.rightTrigger.value)
            targetBrake    = max(targetBrake, gp.leftTrigger.value)
            if gp.rightShoulder.isPressed { gearUp = true }
            if gp.leftShoulder.isPressed  { gearDown = true }
            if gp.buttonA.isPressed { drs = true }
        }

        // Smooth toward the targets (analog feel; instant snap avoided).
        let dt = max(frameDelta, 1e-4)
        steer    = ramp(steer, targetSteer, rate: 3.5, dt: dt)
        throttle = ramp(throttle, targetThrottle, rate: 6, dt: dt)
        brake    = ramp(brake, targetBrake, rate: 8, dt: dt)
        drsRequested = drs

        var input = DriverInput()
        input.steer = simd_clamp(steer, -1, 1)
        input.throttle = simd_clamp(throttle, 0, 1)
        input.brake = simd_clamp(brake, 0, 1)
        input.gearUp = gearUp
        input.gearDown = gearDown
        return input
    }

    private func ramp(_ cur: Float, _ target: Float, rate: Float, dt: Float) -> Float {
        let d = target - cur
        let step = rate * dt
        return abs(d) <= step ? target : cur + (d > 0 ? step : -step)
    }
}
