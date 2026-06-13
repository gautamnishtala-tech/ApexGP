import simd

/// Driver inputs, normalized. Player input and AI control output both produce
/// this — AI cars get no other channel into the physics (no cheating).
public struct DriverInput: Sendable {
    /// -1 (full left) ... 1 (full right)
    public var steer: Float = 0
    /// 0 ... 1
    public var throttle: Float = 0
    /// 0 ... 1
    public var brake: Float = 0
    public var gearUp: Bool = false
    public var gearDown: Bool = false

    public init() {}
}

/// Snapshot of one car's physical state. Phase 2 builds the full 4-wheel
/// dynamics that evolves this (see docs/phases/phase-2); Phase 0 only needs
/// the type so rendering and agents have a shared vocabulary.
public struct VehicleState: Sendable {
    public var position: SIMD3<Float>
    public var velocity: SIMD3<Float>
    /// Yaw around the world Y axis, radians. 0 faces -Z.
    public var heading: Float
    public var gear: Int

    public init(position: SIMD3<Float> = .zero, velocity: SIMD3<Float> = .zero,
                heading: Float = 0, gear: Int = 1) {
        self.position = position
        self.velocity = velocity
        self.heading = heading
        self.gear = gear
    }

    public var speed: Float { simd_length(velocity) }
}
