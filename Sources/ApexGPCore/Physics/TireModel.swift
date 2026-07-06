import simd

/// A simplified Pacejka "Magic Formula" tire.
///
/// The magic formula maps a normalized slip quantity `x` (slip angle in radians
/// for lateral force, slip ratio for longitudinal force) to a force:
///
///     F(x) = D · sin( C · atan( B·x − E·(B·x − atan(B·x)) ) )
///
/// with `D = μ·load` the peak force. Because `E < 1`, the curve rises to a peak
/// near the optimum slip and then **falls off** past the limit — the defining
/// feature we want so a car can be driven past the grip limit and caught again.
///
/// `μ` is made mildly **load sensitive** (grip coefficient drops as vertical
/// load rises above a reference), which is what makes lateral load transfer
/// cost an axle net grip and produces realistic understeer/oversteer balance.
///
/// Pure math, no state, deterministic — safe for the fixed-timestep sim.
public struct TireModel: Sendable {
    // Lateral (cornering) coefficients. Peak near ~7.5° slip angle.
    public var lateralB: Float = 38.0
    public var lateralC: Float = 1.5
    public var lateralE: Float = 0.9

    // Longitudinal (drive/brake) coefficients. Peak near ~0.12 slip ratio.
    public var longitudinalB: Float = 16.0
    public var longitudinalC: Float = 1.65
    public var longitudinalE: Float = 0.6

    /// Peak grip coefficient at the reference load (slick tire ≈ 1.5–1.8).
    public var mu: Float = 1.55
    /// Reference vertical load per tire for the load-sensitivity curve (N).
    public var referenceLoad: Float = 2500
    /// Fractional grip loss per unit of `(load/referenceLoad − 1)`.
    public var loadSensitivity: Float = 0.10

    public init() {}

    /// Load-sensitive peak grip coefficient for a given vertical load (N).
    /// Clamped so a very lightly loaded tire can't produce runaway grip and a
    /// very heavily loaded one keeps a sane floor.
    public func gripCoefficient(load: Float) -> Float {
        let rel = load / referenceLoad - 1
        let adjusted = mu * (1 - loadSensitivity * rel)
        // Guard against runaway/negative grip at extreme loads.
        return simd_clamp(adjusted, mu * 0.6, mu * 1.25)
    }

    /// Core magic formula (odd function of `x`).
    @inline(__always)
    private func magic(_ x: Float, _ B: Float, _ C: Float, _ E: Float, peak D: Float) -> Float {
        let bx = B * x
        let inner = bx - E * (bx - atan(bx))
        return D * sin(C * atan(inner))
    }

    /// Lateral (cornering) force magnitude produced at a given slip angle.
    /// Returns an **odd** function of `slipAngle`; callers apply the restoring
    /// sign. Peak occurs at the optimum slip angle, then falls off.
    public func lateralForce(slipAngle: Float, load: Float) -> Float {
        guard load > 0 else { return 0 }
        let D = gripCoefficient(load: load) * load
        return magic(slipAngle, lateralB, lateralC, lateralE, peak: D)
    }

    /// Longitudinal (drive/brake) force at a given slip ratio. Odd in `slipRatio`.
    public func longitudinalForce(slipRatio: Float, load: Float) -> Float {
        guard load > 0 else { return 0 }
        let D = gripCoefficient(load: load) * load
        return magic(slipRatio, longitudinalB, longitudinalC, longitudinalE, peak: D)
    }
}
