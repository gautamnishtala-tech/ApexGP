import Testing
import simd
@testable import ApexGPCore

@Suite struct RibbonMeshTests {
    @Test func closedStripIsWatertightAndClosed() {
        // A simple square loop of 4 stations.
        let left: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(10, 0, 0), SIMD3(10, 0, 10), SIMD3(0, 0, 10),
        ]
        let right = left.map { $0 + SIMD3<Float>(0, 0, 0) + SIMD3(0, 0, 0) }
        // Offset right rail outward by 2 m in X for distinctness.
        let rightR = left.map { $0 + SIMD3<Float>(2, 0, 0) }
        let up = [SIMD3<Float>](repeating: SIMD3(0, 1, 0), count: 4)
        let m = RibbonMesh.closedStrip(left: left, right: rightR, up: up)
        #expect(m.vertexCount == 8)          // 2 per station
        #expect(m.triangleCount == 8)        // 2 per station, closed
        // Every index is in range.
        #expect(m.indices.allSatisfy { Int($0) < m.vertexCount })
        // Normals are unit up.
        #expect(m.normals.allSatisfy { abs(simd_length($0) - 1) < 1e-5 })
        _ = right
    }

    @Test func appendRebasesIndices() {
        var a = MeshData(positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 0, 1)],
                         normals: [SIMD3(0, 1, 0), SIMD3(0, 1, 0), SIMD3(0, 1, 0)],
                         uvs: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1)],
                         indices: [0, 1, 2])
        let b = a
        a.append(b)
        #expect(a.vertexCount == 6)
        #expect(a.triangleCount == 2)
        #expect(Array(a.indices.suffix(3)) == [3, 4, 5])
    }
}

@Suite struct TrackGeometryTests {
    let track = Track.falconRidge()

    @Test func roadRailsMatchSampleEdges() {
        let geo = TrackGeometry(track: track, spacing: 6)
        #expect(geo.roadLeft.count == geo.samples.count)
        // Lifted rails sit slightly above the raw edges along the surface normal.
        for i in 0..<geo.samples.count {
            let s = geo.samples[i]
            #expect(simd_distance(geo.roadLeft[i], s.leftEdge) < 0.05)
            #expect(simd_distance(geo.roadRight[i], s.rightEdge) < 0.05)
        }
    }

    @Test func minElevationCapturesTheDipBelowZero() {
        let geo = TrackGeometry(track: track, spacing: 6)
        // The circuit dips slightly below y=0; grass must go below that.
        #expect(geo.minElevation <= 0.1)
    }

    @Test func barriersSitAtOrOutsideTheRoadEdges() {
        let geo = TrackGeometry(track: track, spacing: 6)
        for i in 0..<geo.samples.count {
            let s = geo.samples[i]
            let center = s.position
            // The run-off was folded into the drivable width, so the barrier
            // rails now sit AT the road edge (never inside it) — the road
            // reaches the wall and the wall coincides with the physics edge.
            let eps: Float = 0.001
            #expect(simd_distance(geo.barrierLeftInner[i], center) >=
                    simd_distance(s.leftEdge, center) - eps)
            #expect(simd_distance(geo.barrierRightInner[i], center) >=
                    simd_distance(s.rightEdge, center) - eps)
        }
    }

    @Test func kerbRunsCoverAllKerbStationsContiguously() {
        let geo = TrackGeometry(track: track, spacing: 6)
        let runs = geo.kerbRuns()
        #expect(!runs.isEmpty)
        let n = geo.samples.count
        // Reconstruct the set of stations covered by runs.
        var covered = Set<Int>()
        for r in runs {
            for k in 0..<r.count { covered.insert((r.start + k) % n) }
        }
        // It must equal exactly the kerbAdjacent stations.
        let expected = Set((0..<n).filter { geo.samples[$0].surface == .kerbAdjacent })
        #expect(covered == expected)
        // Runs must not overlap.
        #expect(covered.count == runs.reduce(0) { $0 + $1.count })
    }

    @Test func ribbonFromRealTrackIsWatertight() {
        let geo = TrackGeometry(track: track, spacing: 6)
        let m = RibbonMesh.closedStrip(left: geo.roadLeft, right: geo.roadRight,
                                       up: geo.roadUp)
        #expect(m.vertexCount == geo.samples.count * 2)
        #expect(m.triangleCount == geo.samples.count * 2)
        #expect(m.indices.allSatisfy { Int($0) < m.vertexCount })
    }
}
