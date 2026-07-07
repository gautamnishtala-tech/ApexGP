import simd

/// The fixed-timestep 4-wheel vehicle simulation.
///
/// Model summary (planar, in the world X–Z ground plane; Y is elevation and is
/// carried but not dynamically simulated in Phase 2):
/// - **Rigid body**: body-frame longitudinal/lateral velocity + yaw rate,
///   integrated semi-implicitly at a fixed `dt` for stability.
/// - **Tires**: a simplified Pacejka model per wheel (see `TireModel`). Lateral
///   force from slip angle; longitudinal force from drive/brake demand; the two
///   share each tire's grip through a **friction circle** (μ·load), so power
///   spin and brake lockup both bleed cornering grip.
/// - **Weight transfer**: longitudinal + lateral load transfer (using the
///   previous step's accelerations) redistributes vertical load across the four
///   wheels, and load-sensitive grip turns that into understeer/oversteer.
/// - **Aero**: downforce ∝ v² adds vertical load; drag ∝ v² opposes motion; a
///   DRS flag cuts drag.
/// - **Drivetrain**: interpolated torque curve → 8-speed gearbox (auto or
///   manual) → rear wheels, with engine braking on a closed throttle.
///
/// ## Public usage
/// ```
/// let physics = VehiclePhysics(config: .init(), barriers: barriers)
/// physics.step(input: input, dt: 1/240)   // advance one fixed step
/// let s = physics.state                    // read state (or interpolatedState)
/// let t = physics.telemetry                // read HUD telemetry
/// ```
/// `step` is the only mutation entry point; call it once per fixed timestep.
///
/// ## Coordinate conventions
/// World is right-handed with Y up. `VehicleState.heading` is yaw about world Y,
/// with heading 0 facing −Z. The forward and right unit vectors used throughout
/// (and which the renderer should reuse to orient the car) are:
/// ```
/// forward(h) = ( sin h, 0, −cos h )
/// right(h)   = ( cos h, 0,  sin h )
/// ```
public final class VehiclePhysics {
    public var config: VehicleConfig

    /// Current simulation state (position, world velocity, heading, gear).
    public private(set) var state: VehicleState
    /// State at the start of the last `step`, for render interpolation.
    public private(set) var previousState: VehicleState
    /// Telemetry from the last `step`.
    public private(set) var telemetry: Telemetry

    /// When true, the gearbox shifts automatically; when false, use
    /// `DriverInput.gearUp`/`gearDown` (edge-triggered).
    public var automaticGearbox: Bool = true
    /// When true, DRS opens (drag cut) — the app decides when it's allowed.
    public var drsRequested: Bool = false

    /// Optional barrier collider; when set, `step` keeps the car on track.
    public var barriers: TrackBarriers?

    // Body-frame velocity and yaw rate (the true integrated state).
    private var vx: Float = 0          // forward (m/s)
    private var vy: Float = 0          // rightward (m/s)
    private var yawRate: Float = 0     // rad/s
    // Accelerations from the previous step, for weight transfer.
    private var lastAx: Float = 0
    private var lastAy: Float = 0
    // Gearbox bookkeeping.
    private var shiftTimer: Float = 0
    private var prevGearUp = false
    private var prevGearDown = false

    public init(config: VehicleConfig = VehicleConfig(),
                initialState: VehicleState = VehicleState(),
                barriers: TrackBarriers? = nil) {
        self.config = config
        self.state = initialState
        self.previousState = initialState
        self.telemetry = Telemetry()
        self.barriers = barriers
        // Seed body-frame velocity from any initial world velocity.
        let f = VehiclePhysics.forward(initialState.heading)
        let r = VehiclePhysics.right(initialState.heading)
        self.vx = simd_dot(initialState.velocity, f)
        self.vy = simd_dot(initialState.velocity, r)
        self.state.gear = max(1, initialState.gear)
    }

    // MARK: - Frame helpers

    @inline(__always) static func forward(_ h: Float) -> SIMD3<Float> {
        SIMD3(sin(h), 0, -cos(h))
    }
    @inline(__always) static func right(_ h: Float) -> SIMD3<Float> {
        SIMD3(cos(h), 0, sin(h))
    }

    /// A render-ready state interpolated between the previous and current step
    /// (`alpha` in [0,1] from `FixedStepClock.alpha`).
    public func interpolatedState(alpha: Float) -> VehicleState {
        let a = simd_clamp(alpha, 0, 1)
        var s = state
        s.position = simd_mix(previousState.position, state.position, SIMD3(repeating: a))
        s.velocity = simd_mix(previousState.velocity, state.velocity, SIMD3(repeating: a))
        // Shortest-arc heading interpolation.
        var dh = state.heading - previousState.heading
        while dh > .pi { dh -= 2 * .pi }
        while dh < -.pi { dh += 2 * .pi }
        s.heading = previousState.heading + dh * a
        return s
    }

    // MARK: - The fixed step

    /// Advance the simulation by exactly `dt` seconds using `input`.
    public func step(input: DriverInput, dt: Float) {
        previousState = state
        let c = config

        handleGearbox(input: input, dt: dt)

        let steer = simd_clamp(input.steer, -1, 1)
        let throttle = simd_clamp(input.throttle, 0, 1)
        let brake = simd_clamp(input.brake, 0, 1)
        let delta = steer * c.maxSteerAngle

        let speed = sqrt(vx * vx + vy * vy)

        // --- Aero ---
        let q = 0.5 * c.airDensity * speed * speed
        let downforce = q * c.downforceClA
        let drsOpen = drsRequested
        let dragCdA = drsOpen ? c.dragCdA * c.drsDragMultiplier : c.dragCdA
        let dragForce = q * dragCdA

        // --- Vertical loads with weight transfer (uses last step's accel) ---
        let m = c.mass, g: Float = 9.81
        let staticFront = m * g * (c.b / c.wheelbase)   // front axle static (N)
        let staticRear  = m * g * (c.a / c.wheelbase)
        let aeroFront = downforce * c.aeroFrontFraction
        let aeroRear  = downforce * (1 - c.aeroFrontFraction)
        // Longitudinal transfer: accelerating (ax>0) loads the rear.
        let longTransfer = m * lastAx * c.cgHeight / c.wheelbase
        var frontAxle = staticFront + aeroFront - longTransfer
        var rearAxle  = staticRear  + aeroRear  + longTransfer
        frontAxle = max(frontAxle, 0); rearAxle = max(rearAxle, 0)
        // Lateral transfer: split each axle L/R; outer wheel gains.
        let latTransfer = m * lastAy * c.cgHeight / c.trackWidth
        let frontShare = frontAxle / max(frontAxle + rearAxle, 1e-3)
        let flLoad = max(frontAxle * 0.5 - latTransfer * frontShare, 0)
        let frLoad = max(frontAxle * 0.5 + latTransfer * frontShare, 0)
        let rlLoad = max(rearAxle  * 0.5 - latTransfer * (1 - frontShare), 0)
        let rrLoad = max(rearAxle  * 0.5 + latTransfer * (1 - frontShare), 0)

        // --- Slip angles (bicycle geometry, low-speed guarded) ---
        let vxg = max(abs(vx), c.slipSpeedFloor) * (vx < 0 ? -1 : 1)
        let vxDen = max(abs(vxg), c.slipSpeedFloor)
        let alphaFront = atan((vy + c.a * yawRate) / vxDen) - delta
        let alphaRear  = atan((vy - c.b * yawRate) / vxDen)

        // --- Drivetrain: engine force demand at the rear wheels ---
        let rpm = engineRPM(forwardSpeed: vx, gear: state.gear)
        var crankTorque: Float
        if throttle > 0.02 {
            crankTorque = c.engineTorque(rpm: rpm) * throttle
        } else {
            // Engine braking on a closed throttle: a purely RESISTIVE torque that
            // may only ever OPPOSE forward motion. It is faded out as forward
            // speed approaches zero so it vanishes at rest. Without this fade the
            // idle-clamped rpm (`engineRPM` floors rpm at `idleRPM` even at v=0)
            // produced a constant negative crank torque, i.e. a steady BACKWARD
            // drive force that accelerated a stopped car into reverse. Fading it
            // in with speed means it can only decelerate, never reverse the car
            // through zero.
            let brakingFade = simd_clamp(vx / c.slipSpeedFloor, 0, 1)
            crankTorque = -c.engineBrakingTorque
                * simd_clamp(rpm / c.redlineRPM, 0, 1) * brakingFade
        }
        let gearRatio = c.gearRatios[state.gear - 1]
        let driveForceDemand = crankTorque * gearRatio * c.finalDrive
            * c.drivetrainEfficiency / c.wheelRadius

        // --- Brake force demand per axle (opposes forward motion) ---
        let brakeForce = brake * c.maxBrakeForce
        let frontBrake = brakeForce * c.brakeBias
        let rearBrake  = brakeForce * (1 - c.brakeBias)

        // --- Per-wheel force resolution through the friction circle ---
        var flT = WheelTelemetry(), frT = WheelTelemetry()
        var rlT = WheelTelemetry(), rrT = WheelTelemetry()

        // Front wheels: brake only (no drive), lateral from alphaFront.
        resolveWheel(load: flLoad, slipAngle: alphaFront,
                     longitudinalDemand: -0.5 * frontBrake, brakingBiased: true,
                     out: &flT)
        resolveWheel(load: frLoad, slipAngle: alphaFront,
                     longitudinalDemand: -0.5 * frontBrake, brakingBiased: true,
                     out: &frT)
        // Rear wheels: drive + brake, lateral from alphaRear.
        resolveWheel(load: rlLoad, slipAngle: alphaRear,
                     longitudinalDemand: 0.5 * driveForceDemand - 0.5 * rearBrake,
                     brakingBiased: brake > throttle, out: &rlT)
        resolveWheel(load: rrLoad, slipAngle: alphaRear,
                     longitudinalDemand: 0.5 * driveForceDemand - 0.5 * rearBrake,
                     brakingBiased: brake > throttle, out: &rrT)

        // Sum tire forces. Front lateral force acts along the steered wheel;
        // resolve into body axes. Longitudinal front force ≈ along body x.
        let fyFront = flT.lateralForce + frT.lateralForce
        let fyRear  = rlT.lateralForce + rrT.lateralForce
        let fxFront = flT.longitudinalForce + frT.longitudinalForce
        let fxRear  = rlT.longitudinalForce + rrT.longitudinalForce

        let cosD = cos(delta), sinD = sin(delta)
        // Body-frame total forces.
        var fxBody = fxRear + fxFront * cosD - fyFront * sinD
        let fyBody = fyRear + fyFront * cosD + fxFront * sinD
        // Resistances (drag + rolling) may only ever OPPOSE motion. Their sign is
        // keyed off the sign of forward velocity — and is exactly zero at rest, so
        // they can't push a stationary car backward — and their combined magnitude
        // is capped to the force that would bring the car to a dead stop this step,
        // so they can never accelerate it past zero into reverse.
        let rollForce = c.rollingResistance * (flLoad + frLoad + rlLoad + rrLoad)
        let resistForce = dragForce + rollForce
        let maxResistToRest = abs(vx) * m / dt
        let appliedResist = min(resistForce, maxResistToRest)
        let vxSign: Float = vx > 0 ? 1 : (vx < 0 ? -1 : 0)
        fxBody -= appliedResist * vxSign

        // Yaw moment about CG.
        var mz = c.a * (fyFront * cosD + fxFront * sinD) - c.b * fyRear
        // Arcade anti-spin yaw damping: compare the actual yaw rate with the
        // kinematic reference the driver's steer is asking for at this forward
        // speed. Only damp EXCESS rotation (over-rotating / spinning) so we never
        // fight normal steady cornering — the car carves at the reference and the
        // assist only fires when the tail tries to overtake it.
        let refYawRate = delta * max(vx, 0) / c.wheelbase
        let yawExcess = yawRate - refYawRate
        if yawExcess * yawRate > 0 {
            mz -= c.yawStability * yawExcess
        }

        // --- Semi-implicit integration in the body frame ---
        let ax = fxBody / m
        let ay = fyBody / m
        vx += (ax + vy * yawRate) * dt
        vy += (ay - vx * yawRate) * dt
        yawRate += (mz / c.yawInertia) * dt

        // Snap to rest to kill micro-creep/jitter when nearly stopped with no
        // forward drive demand — i.e. coasting or braking down to a standstill.
        // (Under throttle we never snap, so launches are unaffected.)
        if abs(vx) < 0.05 && throttle < 0.02 && driveForceDemand < 1 { vx = 0 }
        if abs(vx) < 1e-3 && abs(vy) < 1e-3 { yawRate *= 0.98 }

        lastAx = ax
        lastAy = ay

        // --- Integrate pose in the world frame ---
        state.heading += yawRate * dt
        let f = VehiclePhysics.forward(state.heading)
        let r = VehiclePhysics.right(state.heading)
        let worldVel = f * vx + r * vy
        state.position += worldVel * dt
        state.velocity = worldVel

        // --- Collision against barriers ---
        if let barriers {
            let result = barriers.resolve(position: state.position,
                                          velocity: state.velocity,
                                          radius: c.collisionRadius)
            if result.hit {
                state.position = result.position
                state.velocity = result.velocity
                // Re-project corrected world velocity back into the body frame.
                vx = simd_dot(state.velocity, f)
                vy = simd_dot(state.velocity, r)
            }
        }

        // --- Telemetry ---
        var t = Telemetry()
        t.speed = sqrt(vx * vx + vy * vy)
        t.speedKmh = t.speed * 3.6
        t.gear = state.gear
        t.rpm = rpm
        t.engineTorque = crankTorque
        t.throttle = throttle
        t.brake = brake
        t.steer = steer
        t.downforce = downforce
        t.drag = dragForce
        t.drsOpen = drsOpen
        t.longitudinalG = ax / g
        t.lateralG = ay / g
        flT.slipAngle = alphaFront; frT.slipAngle = alphaFront
        rlT.slipAngle = alphaRear;  rrT.slipAngle = alphaRear
        t.frontLeft = flT; t.frontRight = frT
        t.rearLeft = rlT;  t.rearRight = rrT
        telemetry = t
    }

    // MARK: - Wheel force resolution

    /// Resolve one tire's lateral + longitudinal force through its friction
    /// circle (grip = μ(load)·load). If the combined demand exceeds grip, the
    /// whole force vector is scaled to the limit and the wheel is flagged as
    /// slipping (spinning under power) or locked (under braking).
    private func resolveWheel(load: Float, slipAngle: Float,
                              longitudinalDemand: Float, brakingBiased: Bool,
                              out: inout WheelTelemetry) {
        out.load = load
        guard load > 0 else { out = WheelTelemetry(); out.load = 0; return }
        let tire = config.tire
        // Restoring lateral force (opposes slip angle).
        var fy = -tire.lateralForce(slipAngle: slipAngle, load: load)
        var fx = longitudinalDemand

        let grip = tire.gripCoefficient(load: load) * load
        let mag = sqrt(fx * fx + fy * fy)
        if mag > grip && mag > 1e-3 {
            let scale = grip / mag
            fx *= scale
            fy *= scale
            out.slipping = true
            out.locked = brakingBiased && fx < 0
        }
        // Slip-ratio estimate for telemetry: linear region below the limit,
        // saturated (spin +) / locked (−1) at the limit.
        let stiffness: Float = 12  // grip per unit slip ratio ≈ B·C
        if out.locked {
            out.slipRatio = -1
        } else if out.slipping {
            out.slipRatio = fx >= 0 ? 0.25 : -0.6
        } else {
            out.slipRatio = simd_clamp(fx / max(stiffness * load, 1), -1, 1)
        }
        out.lateralForce = fy
        out.longitudinalForce = fx
    }

    // MARK: - Drivetrain helpers

    /// Engine rpm implied by forward speed and the selected gear (clamped to
    /// idle…redline for torque lookup and shift decisions).
    private func engineRPM(forwardSpeed: Float, gear: Int) -> Float {
        let c = config
        let wheelOmega = max(forwardSpeed, 0) / c.wheelRadius       // rad/s
        let ratio = c.gearRatios[gear - 1] * c.finalDrive
        let rpm = wheelOmega * ratio * 60 / (2 * .pi)
        return simd_clamp(rpm, c.idleRPM, c.redlineRPM)
    }

    private func handleGearbox(input: DriverInput, dt: Float) {
        let c = config
        shiftTimer = max(0, shiftTimer - dt)
        if automaticGearbox {
            let rpm = engineRPM(forwardSpeed: vx, gear: state.gear)
            if shiftTimer == 0 {
                if rpm >= c.upshiftRPM && state.gear < c.gearRatios.count {
                    state.gear += 1; shiftTimer = c.shiftCooldown
                } else if rpm <= c.downshiftRPM && state.gear > 1 {
                    state.gear -= 1; shiftTimer = c.shiftCooldown
                }
            }
        } else {
            if input.gearUp && !prevGearUp && state.gear < c.gearRatios.count {
                state.gear += 1
            }
            if input.gearDown && !prevGearDown && state.gear > 1 {
                state.gear -= 1
            }
        }
        prevGearUp = input.gearUp
        prevGearDown = input.gearDown
    }
}
