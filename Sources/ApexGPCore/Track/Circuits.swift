import simd

// Circuit data. Everything here is plain literal data fed through Track's
// designated initializer — no I/O, no randomness, fully deterministic.

extension Track {
    /// Phase-0 placeholder oval: two straights joined by semicircles, flat,
    /// constant width. Kept so early rendering/tests have a trivial circuit.
    ///
    /// The control points are *generated clockwise* (an authoring artifact),
    /// but the lap is driven **counter-clockwise** — the placeholder car in
    /// the app spawns on the z = +radius straight facing +X, which is
    /// counter-clockwise. That mismatch is resolved explicitly here with
    /// `direction: .againstControlPoints`; sample tangents therefore point
    /// the way the car actually travels.
    public static func testOval(straight: Float = 300, radius: Float = 80,
                                width: Float = 12, samplesPerArc: Int = 24,
                                samplesPerStraight: Int = 12) -> Track {
        var pts: [TrackControlPoint] = []
        let half = straight / 2
        // Each section omits its end point — the next section starts there.
        func arc(center: SIMD3<Float>, from: Float, to: Float) {
            for i in 0..<samplesPerArc {
                let t = from + (to - from) * Float(i) / Float(samplesPerArc)
                pts.append(TrackControlPoint(
                    position: center + SIMD3(radius * cos(t), 0, radius * sin(t)),
                    width: width))
            }
        }
        func line(from a: SIMD3<Float>, to b: SIMD3<Float>) {
            for i in 0..<samplesPerStraight {
                let t = Float(i) / Float(samplesPerStraight)
                pts.append(TrackControlPoint(
                    position: simd_mix(a, b, SIMD3(repeating: t)), width: width))
            }
        }
        arc(center: SIMD3(half, 0, 0), from: -.pi / 2, to: .pi / 2)
        line(from: SIMD3(half, 0, radius), to: SIMD3(-half, 0, radius))
        arc(center: SIMD3(-half, 0, 0), from: .pi / 2, to: 3 * .pi / 2)
        line(from: SIMD3(-half, 0, -radius), to: SIMD3(half, 0, -radius))
        return Track(name: "Test Oval", points: pts,
                     direction: .againstControlPoints)
    }

    /// Convenience initializer used by generated circuits where the points
    /// are already dense and sector gates default to thirds of the lap.
    init(name: String, points: [TrackControlPoint], direction: TravelDirection) {
        self.init(name: name, controlPoints: points, direction: direction,
                  sectorGates: nil)
    }

    /// **Falcon Ridge Circuit** — Phase 1's fictional grand-prix track.
    ///
    /// ~4.1 km, 14 corners of varied radius, one left-right chicane (T2–T3),
    /// an uphill run climbing ~15 m to a crest hairpin (T7) and back down,
    /// and a ~900 m start/finish straight that hosts the 20-slot grid.
    /// Lap distance 0 (start/finish line) is mid-straight at the world origin;
    /// travel is in control-point order, heading +X off the line.
    ///
    /// Corner guide (in travel order): T1 medium 90°, T2–T3 chicane,
    /// T4 long banked uphill sweep, T5–T6 kinks over the ridge, T7 crest
    /// hairpin, T8 downhill kink, T9–T10 esses, T11 banked medium,
    /// T12–T13 double-apex final corner onto the straight.
    public static func falconRidge() -> Track {
        // Plan-view scale applied to the hand-drawn layout (x/z only —
        // elevations are authored in final meters).
        let k: Float = 1.85
        // (x, y, z, width m, banking deg, surface)
        let raw: [(Float, Float, Float, Float, Float, SurfaceType)] = [
            (   0,  0,   0, 14, 0, .asphalt),       // 0  start/finish line
            ( 150,  0,   0, 14, 0, .asphalt),       // 1  S/F straight
            ( 280,  0,   0, 14, 0, .asphalt),       // 2  braking zone
            ( 360,  0,  18, 13, 3, .kerbAdjacent),  // 3  T1 entry (right 90°)
            ( 395,  0,  75, 13, 3, .kerbAdjacent),  // 4  T1 exit
            ( 400,  1, 150, 13, 0, .asphalt),       // 5  short run
            ( 372,  2, 195, 11, 0, .kerbAdjacent),  // 6  T2 chicane (left)
            ( 398,  3, 238, 11, 0, .kerbAdjacent),  // 7  T3 chicane (right)
            ( 390,  4, 290, 12, 0, .asphalt),       // 8  chicane exit
            ( 364,  6, 350, 13, 4, .kerbAdjacent),  // 9  T4 long uphill sweep
            ( 296,  9, 400, 13, 4, .kerbAdjacent),  // 10 T4 apex (banked)
            ( 200, 11, 420, 13, 0, .asphalt),       // 11 T4 exit, climbing
            (  90, 13, 425, 14, 0, .asphalt),       // 12 back straight (uphill)
            (  10, 14, 437, 12, 0, .kerbAdjacent),  // 13 T5 kink
            ( -65, 15, 465, 12, 0, .kerbAdjacent),  // 14 T6 kink (ridge top)
            (-130, 14, 500, 13, 0, .asphalt),       // 15 approach to hairpin
            (-185, 12, 515, 12, 2, .kerbAdjacent),  // 16 T7 crest hairpin entry
            (-222, 11, 492, 12, 2, .kerbAdjacent),  // 17 T7 hairpin apex
            (-228, 10, 450, 12, 0, .asphalt),       // 18 T7 exit, downhill
            (-218,  8, 385, 13, 0, .asphalt),       // 19 downhill run
            (-243,  6, 330, 12, 0, .kerbAdjacent),  // 20 T8 kink
            (-230,  5, 272, 12, 0, .kerbAdjacent),  // 21 T9 ess (right)
            (-258,  4, 215, 12, 0, .kerbAdjacent),  // 22 T10 ess (left)
            (-247,  2, 157, 13, 0, .asphalt),       // 23 short run
            (-280,  1, 105, 12, 3, .kerbAdjacent),  // 24 T11 (banked)
            (-300,  0,  50, 12, 0, .kerbAdjacent),  // 25 T12 final-corner entry
            (-286,  0,   8, 13, 0, .kerbAdjacent),  // 26 T13 final-corner exit
            (-215,  0,   0, 14, 0, .asphalt),       // 27 onto S/F straight
            (-110,  0,   0, 14, 0, .asphalt),       // 28 grid zone
        ]
        // Widen the whole circuit uniformly for a roomier, more forgiving track,
        // then add the former barrier run-off (3 m per side) into the drivable
        // width so the road reaches the walls and the car can use it.
        let widthScale: Float = 1.4
        let runoffPerSide: Float = 3.0
        let points = raw.map { x, y, z, width, bankDeg, surface in
            TrackControlPoint(position: SIMD3(x * k, y, z * k),
                              width: width * widthScale + 2 * runoffPerSide,
                              banking: bankDeg * .pi / 180,
                              surface: surface)
        }
        return Track(name: "Falcon Ridge Circuit",
                     controlPoints: points,
                     direction: .alongControlPoints,
                     sectorGates: [1350, 2700])
    }
}
