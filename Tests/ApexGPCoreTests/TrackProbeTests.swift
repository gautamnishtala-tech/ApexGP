import Testing
import simd
@testable import ApexGPCore

// QA edge-probe tests for Phase 1. These attack the boundaries the phase doc
// implies but the implementer tests don't spell out: extreme sampling spacing,
// NaN/degenerate vertices from the spline, strict mesh closure, and sector-gate
// invariants on the real circuit.

@Suite struct TrackProbeTests {
    let track = Track.falconRidge()

    // MARK: samples(spacing:) at extremes

    @Test func samplesAtTinySpacingStayUniformAndFinite() {
        // 0.5 m spacing => thousands of samples. Must stay finite, uniform,
        // unit-tangent, and the loop must still close.
        let spacing: Float = 0.5
        let samples = track.samples(spacing: spacing)
        #expect(samples.count > 6000)
        let step = track.length / Float(samples.count)
        for s in samples {
            #expect(s.position.x.isFinite && s.position.y.isFinite && s.position.z.isFinite)
            #expect(abs(simd_length(s.forward) - 1) < 1e-3)
            #expect(abs(simd_length(s.right) - 1) < 1e-3)
            #expect(abs(simd_length(s.up) - 1) < 1e-3)
        }
        // First sample at distance 0; uniform increments.
        #expect(abs(samples[0].distance) < 1e-4)
        for i in 0..<samples.count {
            var ds = samples[(i + 1) % samples.count].distance - samples[i].distance
            if ds < 0 { ds += track.length }
            #expect(abs(ds - step) < 0.01)
        }
    }

    @Test func samplesAtHugeSpacingClampToFloor() {
        // Spacing far larger than the lap must clamp to the 8-sample floor,
        // not produce 0/1 samples or a crash.
        for spacing: Float in [track.length, track.length * 10, 1e6] {
            let samples = track.samples(spacing: spacing)
            #expect(samples.count == 8)
            #expect(samples.allSatisfy {
                $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite
            })
        }
    }

    @Test func sampleAtDistanceWrapsForNegativeAndOverLap() {
        // Negative and beyond-a-lap distances wrap to the same point.
        let base = track.sample(atDistance: 123.0)
        let plusLap = track.sample(atDistance: 123.0 + track.length)
        let minusLap = track.sample(atDistance: 123.0 - track.length)
        let plusTen = track.sample(atDistance: 123.0 + 10 * track.length)
        for other in [plusLap, minusLap, plusTen] {
            #expect(simd_distance(base.position, other.position) < 0.01)
            #expect(simd_dot(base.forward, other.forward) > 0.999)
        }
    }

    // MARK: no NaN / degenerate frames anywhere

    @Test func noNaNOrDegenerateFramesDenselyAroundLap() {
        // Walk the whole lap at fine resolution sampling the raw API; every
        // frame vector must be finite, unit, and orthogonal. This catches
        // cross-product blow-ups at near-vertical or doubled-back stretches.
        var d: Float = 0
        while d < track.length {
            let s = track.sample(atDistance: d)
            let v = [s.forward, s.right, s.up]
            for vec in v {
                #expect(vec.x.isFinite && vec.y.isFinite && vec.z.isFinite,
                        "non-finite frame at d=\(d)")
                #expect(abs(simd_length(vec) - 1) < 1e-2, "non-unit frame at d=\(d)")
            }
            #expect(abs(simd_dot(s.forward, s.right)) < 0.03, "non-orthogonal at d=\(d)")
            #expect(s.width > 0)
            d += 1.0
        }
    }

    // MARK: sector gates within lap and consistent with sector()

    @Test func falconRidgeSectorGatesStrictlyOrderedWithinLap() {
        #expect(track.sectorGates.count == 2)
        #expect(track.sectorGates[0] > 0)
        #expect(track.sectorGates[0] < track.sectorGates[1])
        #expect(track.sectorGates[1] < track.length)
        // sector() partitions [0, length) into exactly {0,1,2} with no gaps.
        #expect(track.sector(atDistance: 0) == 0)
        #expect(track.sector(atDistance: track.sectorGates[0] - 0.1) == 0)
        #expect(track.sector(atDistance: track.sectorGates[0]) == 1)
        #expect(track.sector(atDistance: track.sectorGates[1] - 0.1) == 1)
        #expect(track.sector(atDistance: track.sectorGates[1]) == 2)
        #expect(track.sector(atDistance: track.length - 0.1) == 2)
        // Wrapping: a distance one lap on lands in the same sector.
        #expect(track.sector(atDistance: track.length + 5) == track.sector(atDistance: 5))
    }

    // MARK: mesh closure — first really connects to last

    @Test func closedStripActuallyJoinsLastStationToFirst() {
        // The closed ribbon's index list must contain triangles bridging the
        // final station back to station 0 (vertices 0 and 1). Without this the
        // lap would have a visible seam/hole at the start/finish line.
        let geo = TrackGeometry(track: track, spacing: 6)
        let n = geo.samples.count
        let m = RibbonMesh.closedStrip(left: geo.roadLeft, right: geo.roadRight, up: geo.roadUp)
        // Last station indices are 2*(n-1) and 2*(n-1)+1; they must appear in a
        // triangle alongside vertex 0 or 1 (the first station).
        let lastL = UInt32((n - 1) * 2), lastR = UInt32((n - 1) * 2 + 1)
        var bridges = false
        var t = 0
        while t < m.indices.count {
            let tri = Set([m.indices[t], m.indices[t + 1], m.indices[t + 2]])
            if (tri.contains(lastL) || tri.contains(lastR)) && (tri.contains(0) || tri.contains(1)) {
                bridges = true
            }
            t += 3
        }
        #expect(bridges, "closed ribbon does not connect last station back to first")
        // And the geometric gap between first and last road rails is one step.
        let step = track.length / Float(n)
        #expect(simd_distance(geo.roadLeft[n - 1], geo.roadLeft[0]) < step * 1.2)
        #expect(simd_distance(geo.roadRight[n - 1], geo.roadRight[0]) < step * 1.2)
    }

    @Test func meshHasNoNaNVerticesOrNormals() {
        let geo = TrackGeometry(track: track, spacing: 6)
        let m = RibbonMesh.closedStrip(left: geo.roadLeft, right: geo.roadRight, up: geo.roadUp)
        #expect(m.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        #expect(m.normals.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        #expect(m.uvs.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        // No degenerate (zero-area) triangles: each tri's two edge vectors must
        // not be parallel.
        var t = 0
        while t < m.indices.count {
            let p0 = m.positions[Int(m.indices[t])]
            let p1 = m.positions[Int(m.indices[t + 1])]
            let p2 = m.positions[Int(m.indices[t + 2])]
            let area = simd_length(simd_cross(p1 - p0, p2 - p0)) * 0.5
            #expect(area > 1e-4, "degenerate triangle at index \(t), area \(area)")
            t += 3
        }
    }

    // MARK: grid never lands off the road regardless of slot count

    @Test func gridSlotsStayOnRoadForFullField() {
        let slots = track.gridSlots(count: 24)
        let fine = track.samples(spacing: 2)
        for slot in slots {
            let nearest = fine.min {
                simd_distance($0.position, slot.position) < simd_distance($1.position, slot.position)
            }!
            #expect(simd_distance(nearest.position, slot.position) < nearest.width / 2,
                    "slot \(slot.index) off the road")
        }
    }
}
