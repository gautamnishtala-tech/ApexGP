import simd

// Mesh *math* for the track world. This file deliberately has NO SceneKit /
// AppKit dependency: it computes vertex/normal/UV/index arrays from the
// `Track` sampling contract so the geometry can be unit-tested in core. The
// app target turns these buffers into `SCNGeometry` (see TrackMeshBuilder in
// ApexGPApp) — only the API-specific assembly lives there.

/// A plain, renderer-agnostic indexed triangle mesh: positions, per-vertex
/// normals, 2D texture coordinates, and a triangle index list. Triangles wind
/// counter-clockwise when viewed from the side the normal points to.
public struct MeshData: Sendable {
    public var positions: [SIMD3<Float>]
    public var normals: [SIMD3<Float>]
    public var uvs: [SIMD2<Float>]
    /// Flat triangle index list (3 entries per triangle).
    public var indices: [UInt32]

    public init(positions: [SIMD3<Float>] = [],
                normals: [SIMD3<Float>] = [],
                uvs: [SIMD2<Float>] = [],
                indices: [UInt32] = []) {
        self.positions = positions
        self.normals = normals
        self.uvs = uvs
        self.indices = indices
    }

    public var vertexCount: Int { positions.count }
    public var triangleCount: Int { indices.count / 3 }

    /// Append `other`'s geometry, re-basing its indices onto this mesh's
    /// vertex array. Used to merge ribbons/kerbs into one draw call.
    public mutating func append(_ other: MeshData) {
        let base = UInt32(positions.count)
        positions += other.positions
        normals += other.normals
        uvs += other.uvs
        indices += other.indices.map { $0 + base }
    }
}

/// Closed-loop quad strip between two parallel edge rails. `count` is the
/// number of samples around the lap; rail arrays must each have `count`
/// entries and are connected last→first to close the loop. Normals are taken
/// from `up` per sample. `vCoord` maps to the texture's V axis at each rail
/// (e.g. 0 on the left rail, 1 on the right) and `uScale` stretches the U
/// (along-track) coordinate so striped/repeating textures tile sanely.
public enum RibbonMesh {
    /// Build a closed ribbon between `left` and `right` rails. `up` supplies
    /// the surface normal at each station. The U coordinate runs with
    /// cumulative along-rail distance times `uScale`.
    public static func closedStrip(left: [SIMD3<Float>],
                                   right: [SIMD3<Float>],
                                   up: [SIMD3<Float>],
                                   vLeft: Float = 0, vRight: Float = 1,
                                   uScale: Float = 1) -> MeshData {
        precondition(left.count == right.count && left.count == up.count)
        let n = left.count
        precondition(n >= 3)
        var m = MeshData()
        m.positions.reserveCapacity(n * 2)
        m.normals.reserveCapacity(n * 2)
        m.uvs.reserveCapacity(n * 2)
        m.indices.reserveCapacity(n * 6)

        var u: Float = 0
        for i in 0..<n {
            if i > 0 {
                // advance U by the average of the two rail edge lengths
                let dl = simd_distance(left[i], left[i - 1])
                let dr = simd_distance(right[i], right[i - 1])
                u += 0.5 * (dl + dr) * uScale
            }
            m.positions.append(left[i])
            m.normals.append(up[i])
            m.uvs.append(SIMD2(u, vLeft))
            m.positions.append(right[i])
            m.normals.append(up[i])
            m.uvs.append(SIMD2(u, vRight))
        }
        // Two triangles per station, wrapping the last station to the first.
        for i in 0..<n {
            let a = UInt32(i * 2)            // left[i]
            let b = UInt32(i * 2 + 1)        // right[i]
            let j = (i + 1) % n
            let c = UInt32(j * 2)            // left[j]
            let d = UInt32(j * 2 + 1)        // right[j]
            // CCW when viewed from above (normal up).
            m.indices += [a, c, b,  b, c, d]
        }
        return m
    }
}

/// Pre-derived geometry rails for a circuit, all computed from the sampling
/// contract. The app consumes these to build SceneKit nodes.
public struct TrackGeometry: Sendable {
    /// Evenly spaced samples used for every rail (one per station).
    public let samples: [TrackSample]
    /// Road surface inner edges, lifted a hair to sit above the grass.
    public let roadLeft: [SIMD3<Float>]
    public let roadRight: [SIMD3<Float>]
    public let roadUp: [SIMD3<Float>]
    /// Lowest road elevation on the lap (for placing grass beneath it).
    public let minElevation: Float

    /// Outer barrier wall base rails (offset outside each road edge).
    public let barrierLeftInner: [SIMD3<Float>]
    public let barrierRightInner: [SIMD3<Float>]

    public init(track: Track, spacing: Float) {
        let s = track.samples(spacing: spacing)
        self.samples = s
        // Lift the visible road 2 cm along its own normal so it never
        // z-fights the grass plane underneath it.
        let lift: Float = 0.02
        self.roadLeft = s.map { $0.leftEdge + $0.up * lift }
        self.roadRight = s.map { $0.rightEdge + $0.up * lift }
        self.roadUp = s.map { $0.up }
        self.minElevation = s.map { $0.position.y }.min() ?? 0

        // Barriers: a couple of meters of clearance outside each edge.
        let clearance: Float = 3.0
        self.barrierLeftInner = s.map { $0.leftEdge - $0.right * clearance }
        self.barrierRightInner = s.map { $0.rightEdge + $0.right * clearance }
    }

    /// Indices into `samples` that begin a contiguous `kerbAdjacent` run.
    /// Returned as half-open `[start, end)` ranges over the sample array
    /// (end may wrap past the array — caller mods by count).
    public func kerbRuns() -> [(start: Int, count: Int)] {
        let n = samples.count
        let flags = samples.map { $0.surface == .kerbAdjacent }
        guard flags.contains(true) else { return [] }
        // Find a non-kerb station to start scanning from so a run that
        // straddles the seam is captured as one piece.
        guard let firstFalse = flags.firstIndex(of: false) else {
            return [(0, n)]   // entire lap is kerbed
        }
        var runs: [(Int, Int)] = []
        var i = 0
        while i < n {
            let idx = (firstFalse + i) % n
            if flags[idx] {
                let start = idx
                var len = 0
                while i < n, flags[(firstFalse + i) % n] {
                    len += 1; i += 1
                }
                runs.append((start, len))
            } else {
                i += 1
            }
        }
        return runs
    }
}
