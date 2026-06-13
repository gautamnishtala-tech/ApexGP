import simd

// MARK: - Building blocks

/// Surface classification for a stretch of track, authored per control point.
/// The mesh generator uses this to decide companion geometry (e.g. kerbs);
/// the racing line / AI can use it for grip or track-limits decisions later.
public enum SurfaceType: String, Sendable, CaseIterable {
    /// Plain racing asphalt — straights and gentle sections.
    case asphalt
    /// Corner sections that should be flanked by kerbs on their edges.
    /// The centerline itself is still asphalt; this is a hint that the mesh
    /// generator should add kerb ribbons along `leftEdge`/`rightEdge` here.
    case kerbAdjacent
    /// Pit lane surface (reserved for the Phase 4 pit lane; unused by the
    /// Phase 1 circuits but part of the vocabulary so data won't change shape).
    case pitLane
}

/// Direction of travel around the closed centerline, declared explicitly on
/// the track. Never infer racing direction from control-point order: authored
/// point order is a data-entry artifact, not a gameplay fact.
public enum TravelDirection: String, Sendable {
    /// The lap runs through the control points in array order
    /// (point 0 → 1 → 2 → … → 0).
    case alongControlPoints
    /// The lap runs through the control points in reverse array order
    /// (point 0 → n-1 → n-2 → … → 0). Lap distance 0 is still control point 0.
    case againstControlPoints
}

/// One authored control point of the circuit's centerline spline.
/// The spline passes exactly through every control point; width, banking and
/// surface are interpolated between consecutive points along each segment.
public struct TrackControlPoint: Sendable {
    /// Centerline position in meters. Y is elevation (world up).
    public var position: SIMD3<Float>
    /// Full track width in meters at this point (edge-to-edge).
    public var width: Float
    /// Banking angle in radians. Positive banking raises the *right-hand*
    /// edge of the road (right relative to the direction of travel) above
    /// the centerline. 0 = flat road.
    public var banking: Float
    /// Surface classification from this point until the next control point.
    public var surface: SurfaceType

    public init(position: SIMD3<Float>, width: Float,
                banking: Float = 0, surface: SurfaceType = .asphalt) {
        self.position = position
        self.width = width
        self.banking = banking
        self.surface = surface
    }
}

// MARK: - Sample (the consumption contract)

/// One evenly spaced sample of the centerline — **the contract** that the mesh
/// generator, cameras, and the future racing line consume. Obtain these from
/// `Track.samples(spacing:)` or `Track.sample(atDistance:)`.
///
/// Frame conventions (all vectors unit length, all units meters/radians):
/// - `forward` points in the direction of travel (banking-independent).
/// - `right` points to the driver's right *and is rotated by the banking
///   angle*, so `position ± right * width/2` are the actual 3D road edges.
/// - `up` (`cross(right, forward)`) is the banked road-surface normal.
/// - `distance` is cumulative lap distance from the start/finish line
///   (which is always at distance 0, i.e. control point 0).
///
/// A lap's samples form a closed loop: the array from `samples(spacing:)`
/// contains no duplicate closing sample — connect the last sample back to the
/// first to close the ribbon.
public struct TrackSample: Sendable {
    /// Cumulative centerline distance from the start/finish line, meters.
    public let distance: Float
    /// Centerline position (Y = elevation), meters.
    public let position: SIMD3<Float>
    /// Unit tangent in the direction of travel.
    public let forward: SIMD3<Float>
    /// Unit vector to the driver's right, tilted by the banking angle.
    public let right: SIMD3<Float>
    /// Full track width in meters at this sample.
    public let width: Float
    /// Banking in radians (positive = right edge raised). Already applied
    /// to `right`; exposed for shading/physics that want the raw angle.
    public let banking: Float
    /// Surface classification at this sample.
    public let surface: SurfaceType

    /// Banked road-surface normal (unit).
    public var up: SIMD3<Float> { simd_normalize(simd_cross(right, forward)) }
    /// Left road edge in 3D (includes banking and elevation).
    public var leftEdge: SIMD3<Float> { position - right * (width / 2) }
    /// Right road edge in 3D (includes banking and elevation).
    public var rightEdge: SIMD3<Float> { position + right * (width / 2) }
}

/// One starting-grid slot, derived from the centerline behind the
/// start/finish line. Slot 0 is pole position (closest to the line); slots
/// alternate sides, staggered 2-wide like a real F1 grid.
public struct GridSlot: Sendable {
    /// 0-based grid position (0 = pole).
    public let index: Int
    /// Grid row (two slots per row): `index / 2`.
    public let row: Int
    /// Car reference position (centerline elevation; place the car here).
    public let position: SIMD3<Float>
    /// Unit direction the car should face (track travel direction).
    public let forward: SIMD3<Float>
    /// Unit right vector at the slot (banking-aware).
    public let right: SIMD3<Float>
}

// MARK: - Track

/// A closed racing circuit: a centripetal Catmull-Rom centerline spline
/// through `controlPoints`, an explicit `direction` of travel, sector timing
/// gates, and a derivable starting grid.
///
/// The start/finish line is at control point 0 (lap distance 0). All distance
/// queries wrap around the lap, so callers may pass any real distance.
/// Geometry is precomputed once at init; `Track` is immutable and `Sendable`.
public struct Track: Sendable {
    public let name: String
    /// Authored spline control points (in authored order — see `direction`).
    public let controlPoints: [TrackControlPoint]
    /// Declared direction of travel around the loop. Use this, never the
    /// control-point winding, to know which way the lap runs.
    public let direction: TravelDirection
    /// The two intermediate sector boundaries as lap distances in meters:
    /// sector 1 = [0, gates[0]), sector 2 = [gates[0], gates[1]),
    /// sector 3 = [gates[1], length). Validated: 0 < gates[0] < gates[1] < length.
    public let sectorGates: [Float]
    /// Total lap length along the spline centerline, meters.
    public let length: Float

    /// Dense arc-length table the public sampling API interpolates from.
    private let dense: [DensePoint]

    private struct DensePoint: Sendable {
        var s: Float                  // cumulative arc length from S/F
        var position: SIMD3<Float>
        var width: Float
        var banking: Float
        var surface: SurfaceType
    }

    /// - Parameters:
    ///   - controlPoints: at least 4 points; consecutive points (including the
    ///     wrap-around pair) must be at least 0.5 m apart.
    ///   - direction: explicit travel direction; lap distance 0 stays at
    ///     control point 0 either way.
    ///   - sectorGates: the two intermediate sector-boundary distances. Pass
    ///     `nil` to place them at 1/3 and 2/3 of the lap.
    public init(name: String, controlPoints: [TrackControlPoint],
                direction: TravelDirection, sectorGates: [Float]? = nil) {
        precondition(controlPoints.count >= 4, "A closed spline needs at least 4 control points")
        precondition(controlPoints.allSatisfy { $0.width > 0 }, "Track widths must be positive")

        self.name = name
        self.controlPoints = controlPoints
        self.direction = direction

        // Apply travel direction: reorder so traversal order == travel order,
        // keeping control point 0 as the lap origin (start/finish).
        let ordered: [TrackControlPoint]
        switch direction {
        case .alongControlPoints:
            ordered = controlPoints
        case .againstControlPoints:
            ordered = [controlPoints[0]] + controlPoints.dropFirst().reversed()
        }
        let n = ordered.count
        for i in 0..<n {
            let d = simd_distance(ordered[i].position, ordered[(i + 1) % n].position)
            precondition(d > 0.5, "Consecutive control points must be > 0.5 m apart (pair \(i))")
        }

        // Tessellate every spline segment into a dense polyline (~1.5 m steps)
        // and accumulate arc length. All public queries interpolate this table.
        var table: [DensePoint] = []
        var s: Float = 0
        var previous: SIMD3<Float>? = nil
        for i in 0..<n {
            let p0 = ordered[(i + n - 1) % n], p1 = ordered[i]
            let p2 = ordered[(i + 1) % n], p3 = ordered[(i + 2) % n]
            let chord = simd_distance(p1.position, p2.position)
            let steps = max(12, Int((chord / 1.5).rounded(.up)))
            for j in 0..<steps {
                let u = Float(j) / Float(steps)
                let pos = CatmullRom.position(p0.position, p1.position,
                                              p2.position, p3.position, u: u)
                if let prev = previous { s += simd_distance(prev, pos) }
                previous = pos
                table.append(DensePoint(s: s,
                                        position: pos,
                                        width: p1.width + (p2.width - p1.width) * u,
                                        banking: p1.banking + (p2.banking - p1.banking) * u,
                                        surface: p1.surface))
            }
        }
        let total = s + simd_distance(table.last!.position, table[0].position)
        precondition(total > 1, "Degenerate track")
        self.dense = table
        self.length = total

        let gates = sectorGates ?? [total / 3, 2 * total / 3]
        precondition(gates.count == 2, "Exactly 2 sector gates define 3 sectors")
        precondition(gates[0] > 0 && gates[0] < gates[1] && gates[1] < total,
                     "Sector gates must satisfy 0 < g1 < g2 < lap length")
        self.sectorGates = gates
    }

    // MARK: Sampling API (mesh generator / racing line contract)

    /// Evenly spaced samples around the whole lap, in travel order, starting
    /// at the start/finish line (distance 0).
    ///
    /// The actual spacing is `length / count` with
    /// `count = round(length / spacing)`, so consecutive samples are *exactly*
    /// uniform in lap distance and the loop closes perfectly: the last
    /// sample's distance is `length - actualSpacing`, and connecting it back
    /// to the first sample closes the ribbon (no duplicate closing sample is
    /// emitted).
    ///
    /// - Parameter spacing: requested arc-length step in meters (e.g. 4–8 m
    ///   for mesh generation).
    public func samples(spacing: Float) -> [TrackSample] {
        precondition(spacing > 0)
        let count = max(8, Int((length / spacing).rounded()))
        let step = length / Float(count)
        return (0..<count).map { sample(atDistance: Float($0) * step) }
    }

    /// The sample at a given lap distance (meters from start/finish along the
    /// centerline, in the direction of travel). Any value is accepted and
    /// wrapped into [0, length) — negative and beyond-a-lap distances work.
    public func sample(atDistance distance: Float) -> TrackSample {
        let s = wrap(distance)
        let here = interpolated(at: s)
        // Tangent via symmetric finite difference along arc length. The dense
        // table is ~1.5 m resolution, so ±0.75 m straddles at most two cells
        // and stays smooth across the lap seam.
        let h: Float = 0.75
        let ahead = interpolated(at: wrap(s + h)).position
        let behind = interpolated(at: wrap(s - h)).position
        let forward = simd_normalize(ahead - behind)
        // Flat right vector, then rotate by banking about the tangent:
        // positive banking raises the right edge.
        let worldUp = SIMD3<Float>(0, 1, 0)
        let flatRight = simd_normalize(simd_cross(forward, worldUp))
        let localUp = simd_normalize(simd_cross(flatRight, forward))
        let right = flatRight * cos(here.banking) + localUp * sin(here.banking)
        return TrackSample(distance: s, position: here.position, forward: forward,
                           right: right, width: here.width, banking: here.banking,
                           surface: here.surface)
    }

    /// Sector index (0, 1, or 2) containing the given lap distance.
    public func sector(atDistance distance: Float) -> Int {
        let s = wrap(distance)
        if s < sectorGates[0] { return 0 }
        if s < sectorGates[1] { return 1 }
        return 2
    }

    // MARK: Starting grid

    /// Starting-grid slots derived from the centerline, staggered 2-wide
    /// behind the start/finish line (against the direction of travel).
    /// Slot 0 (pole) sits `firstSlotGap` meters before the line; each
    /// subsequent slot is `slotSpacing` meters further back on the opposite
    /// side of the centerline, F1-style. Cars should be placed at
    /// `position` facing `forward`.
    ///
    /// The default 20 slots occupy ~`firstSlotGap + 19 * slotSpacing` meters
    /// of road — keep the start/finish straight at least that long.
    public func gridSlots(count: Int = 20,
                          firstSlotGap: Float = 8,
                          slotSpacing: Float = 5) -> [GridSlot] {
        precondition(count > 0 && firstSlotGap > 0 && slotSpacing > 0)
        return (0..<count).map { i in
            let behind = firstSlotGap + Float(i) * slotSpacing
            let base = sample(atDistance: length - behind)
            // Alternate sides: pole on the right of the centerline.
            let side: Float = (i % 2 == 0) ? 1 : -1
            let lateral = side * base.width * 0.25
            return GridSlot(index: i, row: i / 2,
                            position: base.position + base.right * lateral,
                            forward: base.forward, right: base.right)
        }
    }

    // MARK: Private interpolation

    private func wrap(_ s: Float) -> Float {
        let r = s.truncatingRemainder(dividingBy: length)
        return r < 0 ? r + length : r
    }

    /// Linear interpolation of the dense table at wrapped arc length `s`.
    private func interpolated(at s: Float)
        -> (position: SIMD3<Float>, width: Float, banking: Float, surface: SurfaceType) {
        // Binary search: greatest index with dense[i].s <= s.
        var lo = 0, hi = dense.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if dense[mid].s <= s { lo = mid } else { hi = mid - 1 }
        }
        let a = dense[lo]
        let b = dense[(lo + 1) % dense.count]
        let segEnd = (lo + 1 == dense.count) ? length : b.s
        let segLen = max(segEnd - a.s, 1e-6)
        let u = min(max((s - a.s) / segLen, 0), 1)
        return (position: a.position + (b.position - a.position) * u,
                width: a.width + (b.width - a.width) * u,
                banking: a.banking + (b.banking - a.banking) * u,
                surface: a.surface)
    }
}
