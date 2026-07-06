import simd

/// Planar barrier collision for a car modeled as a circle (a capsule collapses
/// to a circle in the X–Z plane) against the two edge polylines of a `Track`.
///
/// Both track edges are precomputed once as line segments. On `resolve` the car
/// circle is tested against nearby segments; on penetration it is pushed out
/// along the wall normal, the into-wall velocity component is removed (minus a
/// little restitution) and the along-wall component is scrubbed by friction —
/// i.e. the car **slides and loses speed** instead of stopping dead or passing
/// through. Pure math, deterministic, and independent of the sim so it can be
/// unit-tested on its own.
///
/// **No tunneling:** with the sim at 240 Hz a car at ~100 m/s moves only ~0.4 m
/// per step — far less than the collision radius — so it cannot skip past a wall
/// between steps. Callers must keep the fixed timestep for this guarantee.
public struct TrackBarriers: Sendable {
    /// A wall as a directed segment with a precomputed inward-facing normal
    /// (pointing toward the track center — the side the car should stay on).
    struct Segment: Sendable {
        var p0: SIMD2<Float>
        var p1: SIMD2<Float>
        var inwardNormal: SIMD2<Float>
    }
    private let segments: [Segment]

    /// Restitution of the barrier (0 = no bounce, 1 = perfect bounce).
    public var restitution: Float
    /// Coulomb friction coefficient against the wall: the along-wall scrub is
    /// proportional to the into-wall speed that gets killed, so a glancing
    /// slide loses little while a near head-on hit scrubs hard. Not a per-step
    /// fraction, so sustained contact doesn't pin the car.
    public var scrub: Float

    /// Build barriers from a track's left/right edges.
    /// - Parameters:
    ///   - track: the circuit to wall off.
    ///   - spacing: edge sampling step (m); finer = smoother walls.
    ///   - restitution / scrub: contact response tuning.
    public init(track: Track, spacing: Float = 3,
                restitution: Float = 0.25, scrub: Float = 0.30) {
        self.restitution = restitution
        self.scrub = scrub
        let samples = track.samples(spacing: spacing)
        let n = samples.count
        var segs: [Segment] = []
        segs.reserveCapacity(n * 2)
        func flat(_ v: SIMD3<Float>) -> SIMD2<Float> { SIMD2(v.x, v.z) }
        for i in 0..<n {
            let s = samples[i]
            let next = samples[(i + 1) % n]
            let center = flat(s.position)
            // Left edge segment; inward normal points toward centerline.
            let l0 = flat(s.leftEdge), l1 = flat(next.leftEdge)
            segs.append(Self.make(l0, l1, towards: center))
            // Right edge segment.
            let r0 = flat(s.rightEdge), r1 = flat(next.rightEdge)
            segs.append(Self.make(r0, r1, towards: center))
        }
        self.segments = segs
    }

    private static func make(_ p0: SIMD2<Float>, _ p1: SIMD2<Float>,
                             towards center: SIMD2<Float>) -> Segment {
        let d = p1 - p0
        var nrm = SIMD2(-d.y, d.x)
        let len = simd_length(nrm)
        nrm = len > 1e-6 ? nrm / len : SIMD2(0, 0)
        // Flip so the normal points toward the track center.
        let mid = (p0 + p1) * 0.5
        if simd_dot(nrm, center - mid) < 0 { nrm = -nrm }
        return Segment(p0: p0, p1: p1, inwardNormal: nrm)
    }

    public struct Resolution: Sendable {
        public var position: SIMD3<Float>
        public var velocity: SIMD3<Float>
        public var hit: Bool
    }

    /// Resolve a circle of `radius` at `position` moving at `velocity` against
    /// the barriers. Only X/Z are affected; Y passes through unchanged.
    public func resolve(position: SIMD3<Float>, velocity: SIMD3<Float>,
                        radius: Float) -> Resolution {
        var p = SIMD2(position.x, position.z)
        var v = SIMD2(velocity.x, velocity.z)
        var hit = false

        // A wall can be hit more than once when near a corner; a couple of
        // passes settle the car into the free region without oscillating.
        for _ in 0..<2 {
            var contacted = false
            for seg in segments {
                let (closest, _) = Self.closestPointOnSegment(p, seg.p0, seg.p1)
                let delta = p - closest
                let dist = simd_length(delta)
                guard dist < radius else { continue }
                // Contact normal: prefer the segment's inward normal, but if the
                // car is outside the wall use the actual separating direction.
                var n = seg.inwardNormal
                if dist > 1e-4 {
                    let dir = delta / dist
                    if simd_dot(dir, n) < 0 { n = dir } // car is on the outside
                }
                let penetration = radius - dist
                p += n * penetration                      // push out
                let vn = simd_dot(v, n)
                if vn < 0 {                               // moving into the wall
                    var tangent = v - n * vn
                    let tangentSpeed = simd_length(tangent)
                    // Coulomb friction: scrub ∝ normal speed removed.
                    let friction = min(tangentSpeed, scrub * -vn)
                    if tangentSpeed > 1e-5 {
                        tangent -= (tangent / tangentSpeed) * friction
                    }
                    v = tangent - n * vn * restitution    // bounce out a little
                }
                contacted = true
                hit = true
            }
            if !contacted { break }
        }

        return Resolution(position: SIMD3(p.x, position.y, p.y),
                          velocity: SIMD3(v.x, velocity.y, v.y),
                          hit: hit)
    }

    /// Closest point on segment [a,b] to point p, plus the parameter t∈[0,1].
    static func closestPointOnSegment(_ p: SIMD2<Float>, _ a: SIMD2<Float>,
                                      _ b: SIMD2<Float>) -> (SIMD2<Float>, Float) {
        let ab = b - a
        let denom = simd_dot(ab, ab)
        guard denom > 1e-9 else { return (a, 0) }
        let t = simd_clamp(simd_dot(p - a, ab) / denom, 0, 1)
        return (a + ab * t, t)
    }

    // MARK: - Car-vs-car (stub hook)

    /// Elastic-ish impulse between two circular cars. **Stub** — there is no
    /// multi-car sim in Phase 2; this is the documented hook Phase 3 will call
    /// once AI cars exist. Returns the velocity change (Δv) to apply to car A
    /// (apply the negation, mass-scaled, to car B).
    public static func carCarImpulse(positionA: SIMD3<Float>, velocityA: SIMD3<Float>,
                                     positionB: SIMD3<Float>, velocityB: SIMD3<Float>,
                                     radius: Float, restitution: Float = 0.2)
        -> SIMD3<Float> {
        let d = SIMD2(positionB.x - positionA.x, positionB.z - positionA.z)
        let dist = simd_length(d)
        guard dist < 2 * radius && dist > 1e-4 else { return .zero }
        let n = d / dist
        let relVel = SIMD2(velocityB.x - velocityA.x, velocityB.z - velocityA.z)
        let approaching = simd_dot(relVel, n)
        guard approaching < 0 else { return .zero }   // separating already
        let j = (1 + restitution) * approaching * 0.5  // equal masses
        let dv2 = n * j
        return SIMD3(dv2.x, 0, dv2.y)
    }
}
