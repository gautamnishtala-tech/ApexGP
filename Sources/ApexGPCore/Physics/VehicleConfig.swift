import simd

/// Static, tunable parameters of an F1-style car. All defaults are ballparked
/// to real F1 figures (≈798 kg minimum mass, low CG, high downforce). Public
/// and mutable so tests and the app can build variants, but the sim never
/// mutates it — dynamics live in `VehiclePhysics`.
public struct VehicleConfig: Sendable {
    // MARK: Mass & geometry
    /// Total mass incl. driver (kg).
    public var mass: Float = 800
    /// Yaw moment of inertia about the vertical axis (kg·m²).
    public var yawInertia: Float = 1000
    /// Arcade yaw-stability assist (N·m per rad/s of EXCESS yaw rate). A restoring
    /// yaw moment is applied only when the car rotates FASTER than the kinematic
    /// reference implied by steer + forward speed (v·δ/wheelbase) — i.e. only when
    /// it is over-rotating / spinning. It never adds understeer to a car that is
    /// cornering normally (which sits at or below that reference), so it removes
    /// the snap-spin "ice" feel without deadening turn-in. Set 0 for a pure
    /// bicycle model. This is the key knob that makes the velocity vector follow
    /// the heading instead of the tail stepping out uncatchably.
    public var yawStability: Float = 11000
    /// Wheelbase, front axle to rear axle (m).
    public var wheelbase: Float = 3.6
    /// Track width, left wheel to right wheel (m).
    public var trackWidth: Float = 1.6
    /// Height of the center of gravity above the road (m).
    public var cgHeight: Float = 0.30
    /// Fraction of static weight carried by the FRONT axle (0…1).
    public var frontWeightFraction: Float = 0.46
    /// Loaded wheel radius (m).
    public var wheelRadius: Float = 0.33
    /// Effective circumscribing radius for planar collision (m).
    public var collisionRadius: Float = 1.5

    // MARK: Tires
    public var tire = TireModel()
    /// Lateral tire relaxation floor: forward speed used in slip-angle
    /// denominators is clamped to at least this (m/s) to avoid a singularity
    /// and jitter at very low speed. Keeps standstill/launch stable.
    public var slipSpeedFloor: Float = 2.5

    // MARK: Steering
    /// Maximum front road-wheel steer angle at full lock (rad, ≈14°). Trimmed
    /// from 0.28 so full stick/keyboard steer no longer drives the front tire
    /// far past its peak slip angle — the car turns in cleanly instead of
    /// darting and washing the front, which reads as a more planted feel.
    public var maxSteerAngle: Float = 0.25

    // MARK: Aerodynamics
    /// Air density (kg/m³).
    public var airDensity: Float = 1.225
    /// Downforce coefficient · frontal area, ClA. Downforce = ½·ρ·ClA·v².
    public var downforceClA: Float = 3.4
    /// Drag coefficient · frontal area, CdA. Drag = ½·ρ·CdA·v².
    public var dragCdA: Float = 1.05
    /// Multiplier applied to CdA when DRS is open (cuts drag on straights).
    public var drsDragMultiplier: Float = 0.75
    /// Fraction of aero downforce acting on the FRONT axle (aero balance).
    public var aeroFrontFraction: Float = 0.45

    // MARK: Drivetrain (rear-wheel drive)
    /// Engine torque curve, sampled at `torqueRPM` (N·m at full throttle).
    public var torqueRPM: [Float]    = [0,   4000, 6000, 8000, 10000, 11500, 13000, 14200]
    public var torqueNm:  [Float]    = [140,  300,  400,  470,   500,   485,   440,   360]
    /// Global scale on engine torque — the single knob for power tuning.
    public var enginePowerScale: Float = 1.0
    /// Idle / redline / shift thresholds (rpm).
    public var idleRPM: Float = 4000
    public var redlineRPM: Float = 14200
    public var upshiftRPM: Float = 13200
    public var downshiftRPM: Float = 8500
    /// Minimum time between automatic shifts (s) to stop gearbox hunting.
    public var shiftCooldown: Float = 0.25
    /// Forward gear ratios, index 0 = 1st gear … index 7 = 8th gear.
    public var gearRatios: [Float] = [2.85, 2.30, 1.95, 1.68, 1.47, 1.30, 1.14, 1.00]
    public var finalDrive: Float = 4.9
    public var drivetrainEfficiency: Float = 0.94
    /// Engine-braking torque at redline with a closed throttle (N·m).
    public var engineBrakingTorque: Float = 90

    // MARK: Brakes
    /// Maximum total brake force the pedal can command (N). Sized so that at
    /// high speed (huge aero load) braking is pedal-limited — which keeps the
    /// 300→0 distance in the realistic F1 window now that mechanical grip is
    /// higher — while at low speed, where grip falls below this, braking becomes
    /// grip/lockup limited so the wheels can still be locked and caught.
    public var maxBrakeForce: Float = 17500
    /// Fraction of brake force to the FRONT axle (brake bias).
    public var brakeBias: Float = 0.58
    /// Rolling resistance coefficient (× vertical load, opposes motion).
    public var rollingResistance: Float = 0.015

    public init() {}

    // Derived geometry.
    /// Distance from CG to front axle (m).
    var a: Float { wheelbase * (1 - frontWeightFraction) }
    /// Distance from CG to rear axle (m).
    var b: Float { wheelbase * frontWeightFraction }

    /// Full-throttle engine torque (N·m) at a given rpm via linear interpolation
    /// of the torque curve, scaled by `enginePowerScale`.
    func engineTorque(rpm: Float) -> Float {
        let r = simd_clamp(rpm, torqueRPM.first!, torqueRPM.last!)
        var t: Float = torqueNm.last!
        for i in 1..<torqueRPM.count where r <= torqueRPM[i] {
            let u = (r - torqueRPM[i-1]) / max(torqueRPM[i] - torqueRPM[i-1], 1e-3)
            t = torqueNm[i-1] + (torqueNm[i] - torqueNm[i-1]) * u
            break
        }
        return t * enginePowerScale
    }
}

/// Per-wheel physical readout for the telemetry overlay.
public struct WheelTelemetry: Sendable {
    /// Slip angle (rad): angle between the wheel's heading and its velocity.
    public var slipAngle: Float = 0
    /// Slip ratio (dimensionless): >0 spinning up under power, −1 fully locked.
    public var slipRatio: Float = 0
    /// Vertical load on the tire (N).
    public var load: Float = 0
    /// Lateral force produced (N).
    public var lateralForce: Float = 0
    /// Longitudinal force produced (N).
    public var longitudinalForce: Float = 0
    /// True when the tire is saturated (spinning up or locked).
    public var slipping: Bool = false
    /// True when a braked wheel has locked (rotation ≈ 0 vs. ground).
    public var locked: Bool = false
}

/// Everything the HUD/overlay needs for one frame. Read after `step`.
public struct Telemetry: Sendable {
    public var speed: Float = 0          // m/s
    public var speedKmh: Float = 0
    public var gear: Int = 1
    public var rpm: Float = 0
    public var engineTorque: Float = 0   // N·m at the crank (after throttle)
    public var throttle: Float = 0
    public var brake: Float = 0
    public var steer: Float = 0
    public var downforce: Float = 0      // N (total)
    public var drag: Float = 0           // N
    public var drsOpen: Bool = false
    public var longitudinalG: Float = 0  // g (forward +)
    public var lateralG: Float = 0       // g (right +)
    /// Front-left, front-right, rear-left, rear-right.
    public var frontLeft = WheelTelemetry()
    public var frontRight = WheelTelemetry()
    public var rearLeft = WheelTelemetry()
    public var rearRight = WheelTelemetry()

    public init() {}

    /// All four wheels in FL, FR, RL, RR order.
    public var wheels: [WheelTelemetry] { [frontLeft, frontRight, rearLeft, rearRight] }
}
