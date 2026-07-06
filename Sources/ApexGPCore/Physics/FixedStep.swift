/// Decouples a fixed-rate physics sim from a variable-rate render loop.
///
/// The render layer feeds real frame durations in; this hands back the number
/// of fixed `dt` steps to run this frame and, afterwards, an `alpha` in [0,1)
/// for interpolating between the previous and current physics states so
/// rendering stays smooth regardless of framerate. Because the sim only ever
/// advances by the same `dt`, physics is **identical at any framerate** — the
/// determinism guarantee the phase requires.
///
/// Typical use in the app render callback:
/// ```
/// let n = clock.advance(frameDelta: dt)
/// for _ in 0..<n { physics.step(input: input, dt: clock.dt) }
/// render(physics.interpolatedState(alpha: clock.alpha))
/// ```
public struct FixedStepClock: Sendable {
    /// The fixed physics timestep in seconds (e.g. 1/240).
    public let dt: Float
    /// Safety cap on how many steps a single frame may run, so a huge stall
    /// (breakpoint, window drag) can't trigger a spiral-of-death.
    public let maxStepsPerFrame: Int
    private var accumulator: Float = 0

    public init(hz: Float = 240, maxStepsPerFrame: Int = 12) {
        precondition(hz > 0)
        self.dt = 1 / hz
        self.maxStepsPerFrame = maxStepsPerFrame
    }

    /// Accumulate a real frame duration and return how many fixed steps to run.
    public mutating func advance(frameDelta: Float) -> Int {
        accumulator += max(0, frameDelta)
        var steps = 0
        while accumulator >= dt && steps < maxStepsPerFrame {
            accumulator -= dt
            steps += 1
        }
        // Drop leftover backlog beyond the cap so we don't accrue lag forever.
        if steps == maxStepsPerFrame && accumulator > dt {
            accumulator = accumulator.truncatingRemainder(dividingBy: dt)
        }
        return steps
    }

    /// Interpolation factor in [0,1) toward the current physics state.
    public var alpha: Float { accumulator / dt }
}
