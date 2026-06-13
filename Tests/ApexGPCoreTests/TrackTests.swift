import Testing
import simd
@testable import ApexGPCore

// MARK: - Shared geometry helpers

/// Signed-curvature corner detector shared by the layout tests. Returns the
/// corners found along the lap as (startDistance, endDistance, totalTurnAngle)
/// where the angle is signed (left vs right) and in radians.
private func detectCorners(in track: Track, spacing: Float = 5,
                           stepThreshold: Float = 0.01,
                           minTurnAngle: Float = 0.30) -> [(start: Float, end: Float, angle: Float)] {
    let samples = track.samples(spacing: spacing)
    let n = samples.count
    // Plan-view heading change between consecutive samples, wrapped to [-pi, pi].
    var steps: [Float] = []
    for i in 0..<n {
        let a = samples[i].forward, b = samples[(i + 1) % n].forward
        let ha = atan2(a.x, -a.z), hb = atan2(b.x, -b.z)
        var d = hb - ha
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        steps.append(d)
    }
    var corners: [(Float, Float, Float)] = []
    var i = 0
    while i < n {
        let d = steps[i]
        if abs(d) > stepThreshold {
            let sign: Float = d > 0 ? 1 : -1
            var total: Float = 0
            let start = samples[i].distance
            var j = i
            while j < n, steps[j] * sign > stepThreshold {
                total += steps[j]
                j += 1
            }
            if abs(total) >= minTurnAngle {
                corners.append((start, samples[(j - 1) % n].distance, total))
            }
            i = j
        } else {
            i += 1
        }
    }
    return corners
}

// MARK: - Test oval (compatibility circuit)

@Suite struct TestOvalTests {
    @Test func lengthMatchesAnalyticOval() {
        let track = Track.testOval(straight: 300, radius: 80)
        // 2 straights + full circle circumference.
        let expected: Float = 2 * 300 + 2 * .pi * 80
        #expect(abs(track.length - expected) < expected * 0.02)
    }

    @Test func travelDirectionIsCounterClockwiseAsDeclared() {
        // Control points are authored clockwise; direction is declared
        // .againstControlPoints, so the lap must run counter-clockwise.
        // The placeholder car spawns at (0, 0, +radius) facing +X — the
        // sample tangent there must agree with it.
        let track = Track.testOval(straight: 300, radius: 80)
        #expect(track.direction == .againstControlPoints)
        let samples = track.samples(spacing: 2)
        let nearSpawn = samples.min {
            simd_distance($0.position, SIMD3(0, 0, 80)) <
            simd_distance($1.position, SIMD3(0, 0, 80))
        }!
        #expect(nearSpawn.forward.x > 0.95)
        #expect(abs(nearSpawn.forward.y) < 0.05 && abs(nearSpawn.forward.z) < 0.2)
    }
}

// MARK: - Falcon Ridge circuit

@Suite struct FalconRidgeTests {
    let track = Track.falconRidge()

    @Test func lapLengthIsRoughlyFourKilometers() {
        #expect(track.length > 3500 && track.length < 4600,
                "lap length was \(track.length) m")
    }

    @Test func splineClosesSmoothly() {
        // First/last samples must meet: position gap of one step, and the
        // tangent must carry across the seam without a kink.
        let samples = track.samples(spacing: 5)
        let first = samples.first!, last = samples.last!
        let step = track.length / Float(samples.count)
        #expect(simd_distance(last.position, first.position) < step * 1.05)
        #expect(simd_dot(last.forward, first.forward) > 0.99)
        // Sampling exactly at the seam from both sides agrees too.
        let atZero = track.sample(atDistance: 0)
        let atLap = track.sample(atDistance: track.length)
        #expect(simd_distance(atZero.position, atLap.position) < 0.01)
    }

    @Test func samplesAreUniformInArcLength() {
        let spacing: Float = 5
        let samples = track.samples(spacing: spacing)
        let step = track.length / Float(samples.count)
        var maxDistanceDeviation: Float = 0
        var maxChordDeviation: Float = 0
        for i in 0..<samples.count {
            let a = samples[i], b = samples[(i + 1) % samples.count]
            // Lap-distance increments must be exactly uniform (mod wrap).
            var ds = b.distance - a.distance
            if ds < 0 { ds += track.length }
            maxDistanceDeviation = max(maxDistanceDeviation, abs(ds - step))
            // Euclidean chord between consecutive samples can only be shorter
            // than the arc, and only slightly on this circuit's radii.
            let chord = simd_distance(a.position, b.position)
            maxChordDeviation = max(maxChordDeviation, abs(chord - step))
        }
        #expect(maxDistanceDeviation < 0.01)
        #expect(maxChordDeviation < step * 0.1,
                "max chord deviation \(maxChordDeviation) m")
    }

    @Test func tangentsAreUnitLengthAndContinuous() {
        let samples = track.samples(spacing: 5)
        for i in 0..<samples.count {
            let a = samples[i], b = samples[(i + 1) % samples.count]
            #expect(abs(simd_length(a.forward) - 1) < 1e-3)
            #expect(abs(simd_length(a.right) - 1) < 1e-3)
            // Frame stays orthogonal even with banking applied.
            #expect(abs(simd_dot(a.forward, a.right)) < 0.02)
            // No sudden flips: over 5 m the heading can only turn so far
            // (tightest corner radius is well above 15 m).
            #expect(simd_dot(a.forward, b.forward) > 0.9,
                    "tangent kink at sample \(i), distance \(a.distance)")
            #expect(simd_dot(a.right, b.right) > 0.9)
        }
    }

    @Test func sectorGatesAreOrderedWithinLap() {
        #expect(track.sectorGates.count == 2)
        #expect(track.sectorGates[0] > 0)
        #expect(track.sectorGates[0] < track.sectorGates[1])
        #expect(track.sectorGates[1] < track.length)
        // The sector lookup agrees with the gates.
        #expect(track.sector(atDistance: 0) == 0)
        #expect(track.sector(atDistance: track.sectorGates[0] + 1) == 1)
        #expect(track.sector(atDistance: track.sectorGates[1] + 1) == 2)
        #expect(track.sector(atDistance: track.length - 1) == 2)
    }

    @Test func gridSlotsSitBehindStartLineAndDoNotOverlap() {
        let slots = track.gridSlots()
        #expect(slots.count == 20)
        // Project each slot back onto the centerline: every slot must be in
        // the last 150 m of the lap (i.e. behind the start/finish line).
        let fine = track.samples(spacing: 2)
        for slot in slots {
            let nearest = fine.min {
                simd_distance($0.position, slot.position) <
                simd_distance($1.position, slot.position)
            }!
            #expect(nearest.distance > track.length - 150,
                    "slot \(slot.index) is not behind the line (s=\(nearest.distance))")
            // Cars must face the direction of travel at their slot.
            #expect(simd_dot(slot.forward, nearest.forward) > 0.99)
            // And sit on the road, not in the grass.
            #expect(simd_distance(nearest.position, slot.position) < nearest.width / 2)
        }
        // Non-overlapping: an F1 car is ~5.3 x 2 m; require clear spacing.
        for i in 0..<slots.count {
            for j in (i + 1)..<slots.count {
                let d = simd_distance(slots[i].position, slots[j].position)
                #expect(d > 5, "slots \(i) and \(j) only \(d) m apart")
            }
        }
        // Staggered 2-wide: row mates sit on opposite sides of the centerline.
        let line = track.sample(atDistance: track.length - 10)
        let side0 = simd_dot(slots[0].position - line.position, slots[0].right)
        let side1 = simd_dot(slots[1].position - line.position, slots[1].right)
        #expect(side0 * side1 < 0)
    }

    @Test func layoutHasTenPlusCornersAndAChicane() {
        let corners = detectCorners(in: track)
        #expect(corners.count >= 10, "found \(corners.count) corners")
        // Chicane: two consecutive corners of opposite direction with at most
        // a short breath of straight between them.
        var foundChicane = false
        for i in 0..<corners.count {
            let a = corners[i], b = corners[(i + 1) % corners.count]
            var gap = b.start - a.end
            if gap < 0 { gap += track.length }
            if a.angle * b.angle < 0, gap < 80,
               abs(a.angle) > 0.25, abs(b.angle) > 0.25 {
                foundChicane = true
                break
            }
        }
        #expect(foundChicane, "no chicane detected")
    }

    @Test func layoutHasElevationChange() {
        let samples = track.samples(spacing: 5)
        let ys = samples.map(\.position.y)
        #expect(ys.max()! - ys.min()! > 10)
        // Elevation must come through the spline smoothly: no step exceeds
        // a plausible gradient (20% over 5 m).
        for i in 0..<samples.count {
            let dy = abs(samples[(i + 1) % samples.count].position.y - samples[i].position.y)
            #expect(dy < 1.0)
        }
    }

    @Test func bankingTiltsTheRightVector() {
        // T4 apex (control point 10) is banked 4 degrees: positive banking
        // must raise the right-hand edge above the centerline.
        let samples = track.samples(spacing: 2)
        let banked = samples.max { $0.banking < $1.banking }!
        #expect(banked.banking > 0.05)  // > ~3 degrees somewhere on the lap
        #expect(banked.rightEdge.y > banked.position.y)
        #expect(banked.leftEdge.y < banked.position.y)
        // Flat samples keep edges level with the centerline.
        let flat = track.sample(atDistance: 10)
        #expect(abs(flat.banking) < 1e-3)
        #expect(abs(flat.rightEdge.y - flat.position.y) < 0.05)
    }

    @Test func startFinishStraightIsStraightWhereTheGridLives() {
        // The 110 m of road occupied by the grid must be effectively straight.
        let lapEnd = track.length
        let reference = track.sample(atDistance: lapEnd - 5)
        var s = lapEnd - 110
        while s < lapEnd - 5 {
            let here = track.sample(atDistance: s)
            #expect(simd_dot(here.forward, reference.forward) > 0.995,
                    "grid zone bends at s=\(s)")
            s += 10
        }
    }
}
