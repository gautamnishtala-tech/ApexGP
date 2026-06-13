import simd

/// Centripetal Catmull-Rom interpolation (Barry–Goldman pyramidal formulation,
/// alpha = 0.5). Centripetal knot spacing is used because it never produces
/// loops or cusps inside a segment even when control points are unevenly
/// spaced — important for hand-authored circuit data with tight chicanes next
/// to long straights.
enum CatmullRom {
    /// Position on the segment p1 → p2, with p0/p3 as the outer neighbors.
    /// `u` is the normalized segment parameter in [0, 1]. The curve passes
    /// exactly through p1 (u = 0) and p2 (u = 1).
    static func position(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>,
                         _ p2: SIMD3<Float>, _ p3: SIMD3<Float>,
                         u: Float) -> SIMD3<Float> {
        // Centripetal knots: t_{i+1} = t_i + |P_{i+1} - P_i|^0.5.
        // Clamp each interval away from zero so coincident points cannot
        // divide by zero (track validation forbids them anyway).
        let eps: Float = 1e-4
        let t0: Float = 0
        let t1 = t0 + max(eps, simd_distance(p0, p1).squareRoot())
        let t2 = t1 + max(eps, simd_distance(p1, p2).squareRoot())
        let t3 = t2 + max(eps, simd_distance(p2, p3).squareRoot())
        let t = t1 + u * (t2 - t1)

        func lerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>,
                  _ ta: Float, _ tb: Float) -> SIMD3<Float> {
            let w = (t - ta) / (tb - ta)
            return a * (1 - w) + b * w
        }
        let a1 = lerp(p0, p1, t0, t1)
        let a2 = lerp(p1, p2, t1, t2)
        let a3 = lerp(p2, p3, t2, t3)
        let b1 = lerp(a1, a2, t0, t2)
        let b2 = lerp(a2, a3, t1, t3)
        return lerp(b1, b2, t1, t2)
    }
}
