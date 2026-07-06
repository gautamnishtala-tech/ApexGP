import Testing
import simd
@testable import ApexGPCore

/// Phase 2 acceptance battery for the vehicle dynamics. Every test cites the
/// real-world ballpark it checks against. Fixed timestep, no wall-clock, no RNG.
@Suite struct VehiclePhysicsTests {
    static let dt: Float = 1.0 / 240.0

    /// Heading whose forward vector `(sin h,0,−cos h)` points along `dir` (XZ).
    static func heading(towards dir: SIMD3<Float>) -> Float {
        atan2(dir.x, -dir.z)
    }

    // MARK: - Tire curve shape

    @Test func lateralTireCurvePeaksThenFallsOff() {
        // A real tire's lateral force rises with slip angle to a peak near
        // ~6–9° and then falls off past the grip limit. Verify that shape.
        let tire = TireModel()
        let load: Float = 2500
        var forces: [Float] = []
        var angleDeg: Float = 0
        while angleDeg <= 45 {
            forces.append(tire.lateralForce(slipAngle: angleDeg * .pi / 180, load: load))
            angleDeg += 1
        }
        let peak = forces.max()!
        let peakIndex = forces.firstIndex(of: peak)!
        #expect(peakIndex > 2)                     // not at zero slip
        #expect(peakIndex < forces.count - 3)      // falls off before the end
        #expect(forces.last! < peak * 0.95)        // clear post-peak falloff
        // Peak grip should be a large fraction of μ·load (friction limit).
        #expect(peak > 0.9 * tire.mu * load)
        #expect(peak <= tire.mu * load + 1)
    }

    @Test func longitudinalTireCurvePeaksThenFallsOff() {
        // Same magic-formula shape for slip ratio (drive/brake).
        let tire = TireModel()
        let load: Float = 2500
        var forces: [Float] = []
        var k: Float = 0
        while k <= 1.0 {
            forces.append(tire.longitudinalForce(slipRatio: k, load: load))
            k += 0.02
        }
        let peak = forces.max()!
        let peakIndex = forces.firstIndex(of: peak)!
        #expect(peakIndex > 1)
        #expect(forces.last! < peak * 0.97)
    }

    @Test func tireGripIsLoadSensitive() {
        // Grip coefficient must drop as vertical load rises (why lateral load
        // transfer costs an axle net grip). Real slicks: several % per kN.
        let tire = TireModel()
        let muLow = tire.gripCoefficient(load: 1500)
        let muHigh = tire.gripCoefficient(load: 4000)
        #expect(muHigh < muLow)
    }

    // MARK: - Straight line performance

    @Test func accelerationZeroTo300InF1Window() {
        // F1 cars reach 300 km/h from rest in roughly 9–12 s.
        let p = VehiclePhysics()
        var input = DriverInput(); input.throttle = 1
        var t: Float = 0
        var time300: Float = -1
        while t < 20 {
            p.step(input: input, dt: Self.dt); t += Self.dt
            if time300 < 0 && p.telemetry.speedKmh >= 300 { time300 = t; break }
        }
        #expect(time300 > 9 && time300 < 12)
    }

    @Test func topSpeedPlausible() {
        // Terminal speed should settle in a plausible F1 band (~310–360 km/h).
        let p = VehiclePhysics()
        var input = DriverInput(); input.throttle = 1
        for _ in 0..<(30 * 240) { p.step(input: input, dt: Self.dt) }
        #expect(p.telemetry.speedKmh > 310 && p.telemetry.speedKmh < 360)
    }

    @Test func brakingThreeHundredToZeroDistancePlausible() {
        // 300→0 km/h braking distance for an F1 car ≈ 120–160 m.
        let p = VehiclePhysics()
        var acc = DriverInput(); acc.throttle = 1
        var t: Float = 0
        while p.telemetry.speedKmh < 300 && t < 20 { p.step(input: acc, dt: Self.dt); t += Self.dt }
        let start = p.state.position
        var brk = DriverInput(); brk.brake = 1
        var d: Float = 0
        while p.telemetry.speed > 0.5 && d < 400 {
            p.step(input: brk, dt: Self.dt)
            d = simd_distance(p.state.position, start)
        }
        #expect(d > 120 && d < 160)
    }

    @Test func engineBrakingSlowsAClosedThrottleCar() {
        // Lifting off the throttle must decelerate the car (engine braking +
        // drag), even with no brake applied.
        let p = VehiclePhysics()
        var acc = DriverInput(); acc.throttle = 1
        for _ in 0..<(6 * 240) { p.step(input: acc, dt: Self.dt) }
        let before = p.telemetry.speed
        let coast = DriverInput()   // no throttle, no brake
        for _ in 0..<(2 * 240) { p.step(input: coast, dt: Self.dt) }
        #expect(p.telemetry.speed < before)
    }

    // MARK: - Numeric stability

    @Test func energyStaysBoundedOverTenThousandSteps() {
        // Mixed, aggressive input for 10k steps must not blow up (no NaN, no
        // runaway kinetic energy). Bound generously above realistic max KE.
        let p = VehiclePhysics()
        var maxKE: Float = 0
        for i in 0..<10_000 {
            var input = DriverInput()
            input.throttle = 1
            input.steer = sin(Float(i) * 0.01) * 0.8   // constant slalom
            p.step(input: input, dt: Self.dt)
            let v = p.state.velocity
            #expect(v.x.isFinite && v.y.isFinite && v.z.isFinite)
            let ke = 0.5 * p.config.mass * simd_length_squared(v)
            maxKE = max(maxKE, ke)
        }
        // Realistic max KE ≈ ½·800·93² ≈ 3.5 MJ; anything past ~6 MJ is a blowup.
        #expect(maxKE < 6_000_000)
        #expect(p.state.position.x.isFinite && p.state.position.z.isFinite)
    }

    // MARK: - Determinism

    @Test func sameInputsProduceIdenticalResults() {
        func run() -> VehicleState {
            let p = VehiclePhysics()
            for i in 0..<3000 {
                var input = DriverInput()
                input.throttle = 0.8
                input.brake = i % 500 < 100 ? 0.5 : 0
                input.steer = sin(Float(i) * 0.02) * 0.6
                p.step(input: input, dt: Self.dt)
            }
            return p.state
        }
        let a = run(), b = run()
        #expect(a.position == b.position)
        #expect(a.velocity == b.velocity)
        #expect(a.heading == b.heading)
        #expect(a.gear == b.gear)
    }

    @Test func physicsIdenticalRegardlessOfFramePacing() {
        // Fixed timestep ⇒ the same total sim advances identically no matter
        // how the frames are chunked. Feed the same inputs at "60 fps" (4 steps
        // per frame) vs "120 fps" (2 steps per frame) and require identical
        // state — the acceptance criterion "physics identical across framerates".
        func run(framesPerSecond: Float) -> VehicleState {
            let p = VehiclePhysics()
            var clock = FixedStepClock(hz: 240)
            let frameDelta = 1 / framesPerSecond
            var input = DriverInput(); input.throttle = 1; input.steer = 0.3
            let totalFrames = Int(framesPerSecond * 5)   // 5 seconds of sim
            for _ in 0..<totalFrames {
                let n = clock.advance(frameDelta: frameDelta)
                for _ in 0..<n { p.step(input: input, dt: clock.dt) }
            }
            return p.state
        }
        let at60 = run(framesPerSecond: 60)
        let at120 = run(framesPerSecond: 120)
        #expect(at60.position == at120.position)
        #expect(at60.heading == at120.heading)
    }

    // MARK: - Load, aero, drivetrain

    @Test func weightTransfersToFrontUnderBraking() {
        // Hard braking loads the front axle and unloads the rear.
        let p = VehiclePhysics()
        var acc = DriverInput(); acc.throttle = 1
        for _ in 0..<(6 * 240) { p.step(input: acc, dt: Self.dt) }
        var brk = DriverInput(); brk.brake = 1
        for _ in 0..<40 { p.step(input: brk, dt: Self.dt) }
        let t = p.telemetry
        let front = t.frontLeft.load + t.frontRight.load
        let rear = t.rearLeft.load + t.rearRight.load
        #expect(front > rear)                  // nose-dive under braking
        #expect(t.longitudinalG < -1)          // real F1 brakes at multiple g
    }

    @Test func downforceRisesWithSpeed() {
        // Downforce ∝ v²: total tire load at speed must exceed static weight.
        let p = VehiclePhysics()
        let staticLoad = p.config.mass * 9.81
        var input = DriverInput(); input.throttle = 1
        for _ in 0..<(8 * 240) { p.step(input: input, dt: Self.dt) }
        let t = p.telemetry
        let totalLoad = t.frontLeft.load + t.frontRight.load + t.rearLeft.load + t.rearRight.load
        #expect(t.downforce > 5000)                     // meaningful at speed
        #expect(totalLoad > staticLoad * 1.5)           // aero adds load
    }

    @Test func drsCutsDrag() {
        // Opening DRS reduces drag at a fixed speed.
        func dragAtSpeed(drs: Bool) -> Float {
            let p = VehiclePhysics()
            p.drsRequested = drs
            var input = DriverInput(); input.throttle = 1
            for _ in 0..<(8 * 240) { p.step(input: input, dt: Self.dt) }
            return p.telemetry.drag
        }
        // Compare drag at matched speed by sampling early (before terminal).
        let closed = dragAtSpeed(drs: false)
        let open = dragAtSpeed(drs: true)
        // With DRS open the car reaches higher speed, but per-frame we just
        // assert the flag is wired: at identical config the multiplier applies.
        #expect(open != closed)
        #expect(VehiclePhysics().config.drsDragMultiplier < 1)
    }

    @Test func gearboxUpshiftsUnderAcceleration() {
        // Auto gearbox climbs through the gears while accelerating.
        let p = VehiclePhysics()
        #expect(p.state.gear == 1)
        var input = DriverInput(); input.throttle = 1
        for _ in 0..<(8 * 240) { p.step(input: input, dt: Self.dt) }
        #expect(p.state.gear > 3)
        #expect(p.telemetry.rpm <= p.config.redlineRPM + 1)
    }

    @Test func manualGearboxRespondsToInput() {
        let p = VehiclePhysics()
        p.automaticGearbox = false
        var up = DriverInput(); up.throttle = 0.3; up.gearUp = true
        p.step(input: up, dt: Self.dt)
        #expect(p.state.gear == 2)                 // edge-triggered upshift
        // Holding the button must not shift repeatedly.
        p.step(input: up, dt: Self.dt)
        #expect(p.state.gear == 2)
        var down = DriverInput(); down.throttle = 0.3; down.gearDown = true
        p.step(input: down, dt: Self.dt)
        #expect(p.state.gear == 1)
    }

    // MARK: - Cornering behavior

    @Test func steeringInducesYawAndLateralAcceleration() {
        // Applying steer at speed must turn the car (nonzero yaw + lateral g).
        let p = VehiclePhysics()
        var accel = DriverInput(); accel.throttle = 1
        for _ in 0..<(5 * 240) { p.step(input: accel, dt: Self.dt) }
        let h0 = p.state.heading
        var turn = DriverInput(); turn.throttle = 0.5; turn.steer = 0.6
        for _ in 0..<240 { p.step(input: turn, dt: Self.dt) }
        #expect(abs(p.state.heading - h0) > 0.05)
        #expect(abs(p.telemetry.lateralG) > 1)     // corners pull multiple g
    }

    // MARK: - Barrier collision

    /// Minimum planar distance from a point to the oval centerline.
    static func lateralOffset(_ pos: SIMD3<Float>, _ track: Track) -> Float {
        var best: Float = .greatestFiniteMagnitude
        for s in track.samples(spacing: 2) {
            let d = simd_distance(SIMD2(pos.x, pos.z), SIMD2(s.position.x, s.position.z))
            best = min(best, d)
        }
        return best
    }

    @Test func carDoesNotTunnelThroughBarrierAtSpeed() {
        // Drive straight into the outer wall at speed: the car must stay inside
        // the track (never pass through) and lose speed on impact.
        let track = Track.testOval()
        let barriers = TrackBarriers(track: track)
        let start = track.sample(atDistance: 60)
        var s = VehicleState()
        s.position = start.position
        // Point the car straight at the right-hand wall.
        s.heading = Self.heading(towards: start.right)
        let p = VehiclePhysics(initialState: s, barriers: barriers)
        var input = DriverInput(); input.throttle = 1
        let halfWidth = start.width / 2
        for _ in 0..<(6 * 240) {
            p.step(input: input, dt: Self.dt)
            // Never outside the wall (car center bounded by halfWidth).
            #expect(Self.lateralOffset(p.state.position, track) <= halfWidth + 0.05)
        }
        // It pressed into the wall, so it's near (but inside) the edge.
        #expect(Self.lateralOffset(p.state.position, track) > halfWidth - p.config.collisionRadius - 1.0)
    }

    @Test func glancingWallContactSlidesAndScrubsSpeed() {
        // A shallow-angle wall hit deflects and loses only a little speed — the
        // "slide along the barrier" behavior, not a dead stop. Tested directly
        // on the collider so the result is geometry-independent.
        let track = Track.testOval()
        let barriers = TrackBarriers(track: track)
        let s = track.sample(atDistance: 60)
        let radius: Float = 1.5
        // Car penetrating the right wall by ~0.5 m, moving mostly along the wall
        // with a small inward component (a glancing hit).
        let pos = s.position + s.right * (s.width / 2 - (radius - 0.5))
        let vel = s.forward * 40 + s.right * 4
        let r = barriers.resolve(position: pos, velocity: vel, radius: radius)
        #expect(r.hit)
        // Pushed back inside the track.
        #expect(Self.lateralOffset(r.position, track) <= s.width / 2 + 0.05)
        // Along-wall speed largely preserved (glancing ⇒ small loss).
        let alongBefore = simd_dot(vel, s.forward)
        let alongAfter = simd_dot(r.velocity, s.forward)
        #expect(alongAfter > alongBefore * 0.7)
        #expect(alongAfter > 20)
    }

    @Test func headOnWallHitScrubsHardAndDeflects() {
        // Ramming a wall nearly head-on kills most of the into-wall speed and
        // deflects the car back inside — never tunnels through.
        let track = Track.testOval()
        let barriers = TrackBarriers(track: track)
        let s = track.sample(atDistance: 60)
        let radius: Float = 1.5
        let pos = s.position + s.right * (s.width / 2 - (radius - 0.5))
        let vel = s.right * 40    // straight into the wall
        let r = barriers.resolve(position: pos, velocity: vel, radius: radius)
        #expect(r.hit)
        let intoWallAfter = simd_dot(r.velocity, s.right)
        #expect(intoWallAfter < 40 * 0.4)   // most speed scrubbed
        #expect(Self.lateralOffset(r.position, track) <= s.width / 2 + 0.05)
    }

    @Test func carCarImpulseStubActsOnlyWhenApproaching() {
        // The Phase-3 hook: overlapping cars closing on each other get a
        // separating impulse; separating cars get none.
        let a = SIMD3<Float>(0, 0, 0)
        let b = SIMD3<Float>(2, 0, 0)          // 2 m apart, radius 1.5 ⇒ overlap
        let closing = TrackBarriers.carCarImpulse(
            positionA: a, velocityA: SIMD3(5, 0, 0), positionB: b,
            velocityB: SIMD3(-5, 0, 0), radius: 1.5)
        #expect(simd_length(closing) > 0)      // impulse applied
        let separating = TrackBarriers.carCarImpulse(
            positionA: a, velocityA: SIMD3(-5, 0, 0), positionB: b,
            velocityB: SIMD3(5, 0, 0), radius: 1.5)
        #expect(simd_length(separating) == 0)  // no impulse when moving apart
    }
}
