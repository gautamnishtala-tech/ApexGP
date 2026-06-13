import SceneKit
import ApexGPCore
import simd

// Builds the full Phase 1 track world from the `Track` sampling contract:
// asphalt ribbon, kerbs on corner stretches, grass floor, perimeter barriers,
// start/finish line, grid-box markings, and a cosmetic pit apron.
//
// Node budget is kept low: road, kerbs, and each barrier wall are single
// merged geometries (one draw call each) rather than thousands of nodes.

enum TrackWorld {

    static func build(for track: Track) -> SCNNode {
        let root = SCNNode()
        root.name = "trackWorld"
        let geo = TrackGeometry(track: track, spacing: 6)

        root.addChildNode(grassNode(geo))
        root.addChildNode(roadNode(geo))
        root.addChildNode(edgeLinesNode(geo))
        if let kerbs = kerbsNode(geo) { root.addChildNode(kerbs) }
        root.addChildNode(barriersNode(geo))
        root.addChildNode(startFinishNode(track))
        root.addChildNode(gridBoxesNode(track))
        root.addChildNode(pitApronNode(track))   // cosmetic only
        return root
    }

    // MARK: Road ribbon

    private static func roadNode(_ geo: TrackGeometry) -> SCNNode {
        // Tile the asphalt texture roughly every 8 m along the lap so future
        // road textures look sane; uScale keeps U in texel-friendly units.
        let mesh = RibbonMesh.closedStrip(left: geo.roadLeft, right: geo.roadRight,
                                          up: geo.roadUp,
                                          vLeft: 0, vRight: 1, uScale: 0.125)
        let node = SCNNode(geometry: SceneGeometry.geometry(from: mesh,
                                                            material: SceneGeometry.roadMaterial()))
        node.name = "road"
        node.castsShadow = false
        return node
    }

    // MARK: Lane edge lines

    /// Crisp white lines running just inside each road edge around the whole
    /// lap — the marking that makes the grey track read as racing "lanes".
    /// Two thin closed strips, merged into one geometry, lifted a hair above
    /// the asphalt so they never z-fight the road.
    private static func edgeLinesNode(_ geo: TrackGeometry) -> SCNNode {
        let lineWidth: Float = 0.18
        let lift: Float = 0.015
        var leftOuter: [SIMD3<Float>] = [], leftInner: [SIMD3<Float>] = []
        var rightInner: [SIMD3<Float>] = [], rightOuter: [SIMD3<Float>] = []
        var up: [SIMD3<Float>] = []
        for sample in geo.samples {
            let u = sample.up
            up.append(u)
            // Left line hugs the left edge and runs inward toward the centerline.
            leftOuter.append(sample.leftEdge + u * lift)
            leftInner.append(sample.leftEdge + sample.right * lineWidth + u * lift)
            // Right line hugs the right edge and runs inward (-right).
            rightInner.append(sample.rightEdge - sample.right * lineWidth + u * lift)
            rightOuter.append(sample.rightEdge + u * lift)
        }
        var merged = MeshData()
        merged.append(RibbonMesh.closedStrip(left: leftOuter, right: leftInner, up: up, uScale: 0))
        merged.append(RibbonMesh.closedStrip(left: rightInner, right: rightOuter, up: up, uScale: 0))
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor.white
        mat.isDoubleSided = true
        let node = SCNNode(geometry: SceneGeometry.geometry(from: merged, material: mat))
        node.name = "edgeLines"
        node.castsShadow = false
        return node
    }

    // MARK: Kerbs

    /// Red/white kerb ribbons hugging the outside of each road edge on
    /// `kerbAdjacent` stretches. One merged geometry for all kerb segments.
    private static func kerbsNode(_ geo: TrackGeometry) -> SCNNode? {
        let runs = geo.kerbRuns()
        guard !runs.isEmpty else { return nil }
        let s = geo.samples
        let n = s.count
        let kerbWidth: Float = 0.9
        var merged = MeshData()

        for run in runs {
            // Build left and right kerb ribbons for this run, plus one station
            // of overlap each side so adjacent asphalt meets the kerb cleanly.
            var leftInner: [SIMD3<Float>] = [], leftOuter: [SIMD3<Float>] = []
            var rightInner: [SIMD3<Float>] = [], rightOuter: [SIMD3<Float>] = []
            var up: [SIMD3<Float>] = []
            for k in 0...run.count {                 // inclusive to close the strip end
                let idx = (run.start + k) % n
                let sample = s[idx]
                up.append(sample.up)
                // Left edge kerb (outside = away from centerline = -right).
                leftInner.append(sample.leftEdge + sample.up * 0.02)
                leftOuter.append(sample.leftEdge - sample.right * kerbWidth + sample.up * 0.02)
                // Right edge kerb (outside = +right).
                rightInner.append(sample.rightEdge + sample.up * 0.02)
                rightOuter.append(sample.rightEdge + sample.right * kerbWidth + sample.up * 0.02)
            }
            merged.append(openStrip(left: leftOuter, right: leftInner, up: up, uScale: 0.7))
            merged.append(openStrip(left: rightInner, right: rightOuter, up: up, uScale: 0.7))
        }
        let node = SCNNode(geometry: SceneGeometry.geometry(from: merged,
                                                           material: SceneGeometry.kerbMaterial()))
        node.name = "kerbs"
        node.castsShadow = false
        return node
    }

    /// An open (non-closed) quad strip between two rails of equal length.
    private static func openStrip(left: [SIMD3<Float>], right: [SIMD3<Float>],
                                  up: [SIMD3<Float>], uScale: Float) -> MeshData {
        precondition(left.count == right.count && left.count == up.count)
        let n = left.count
        var m = MeshData()
        var u: Float = 0
        for i in 0..<n {
            if i > 0 { u += simd_distance(left[i], left[i - 1]) * uScale }
            m.positions.append(left[i]);  m.normals.append(up[i]); m.uvs.append(SIMD2(u, 0))
            m.positions.append(right[i]); m.normals.append(up[i]); m.uvs.append(SIMD2(u, 1))
        }
        for i in 0..<(n - 1) {
            let a = UInt32(i * 2), b = UInt32(i * 2 + 1)
            let c = UInt32((i + 1) * 2), d = UInt32((i + 1) * 2 + 1)
            m.indices += [a, c, b,  b, c, d]
        }
        return m
    }

    // MARK: Grass / runoff

    /// A large grass plane placed just below the lowest point of the road so
    /// it never z-fights the asphalt (the circuit dips a touch below y=0).
    private static func grassNode(_ geo: TrackGeometry) -> SCNNode {
        let floor = SCNFloor()
        floor.reflectivity = 0
        let node = SCNNode(geometry: floor)
        node.geometry!.firstMaterial = SceneGeometry.grassMaterial()
        node.simdPosition = SIMD3(0, geo.minElevation - 0.15, 0)
        node.name = "grass"
        return node
    }

    // MARK: Barriers

    /// Two perimeter walls (one outside each road edge) as merged vertical
    /// ribbons. One geometry per side = 2 draw calls for the whole lap.
    private static func barriersNode(_ geo: TrackGeometry) -> SCNNode {
        let parent = SCNNode()
        parent.name = "barriers"
        let height: Float = 1.2

        func wall(base: [SIMD3<Float>], name: String) -> SCNNode {
            let top = base.map { $0 + SIMD3<Float>(0, height, 0) }
            // Vertical strip: closed loop around the lap. Normals face inward
            // toward the track for lighting; material is double-sided anyway.
            let n = base.count
            var m = MeshData()
            var u: Float = 0
            for i in 0..<n {
                if i > 0 { u += simd_distance(base[i], base[i - 1]) * 0.15 }
                m.positions.append(base[i]); m.uvs.append(SIMD2(u, 0))
                m.positions.append(top[i]);  m.uvs.append(SIMD2(u, 1))
                m.normals.append(SIMD3(0, 0, 0)); m.normals.append(SIMD3(0, 0, 0))
            }
            for i in 0..<n {
                let j = (i + 1) % n
                let a = UInt32(i * 2), b = UInt32(i * 2 + 1)
                let c = UInt32(j * 2), d = UInt32(j * 2 + 1)
                m.indices += [a, c, b,  b, c, d]
            }
            // Approximate normals from triangles (flat-ish wall).
            recomputeNormals(&m)
            let node = SCNNode(geometry: SceneGeometry.geometry(from: m,
                                                               material: SceneGeometry.barrierMaterial()))
            node.name = name
            return node
        }

        parent.addChildNode(wall(base: geo.barrierLeftInner, name: "barrierLeft"))
        parent.addChildNode(wall(base: geo.barrierRightInner, name: "barrierRight"))
        return parent
    }

    private static func recomputeNormals(_ m: inout MeshData) {
        var acc = [SIMD3<Float>](repeating: .zero, count: m.positions.count)
        var t = 0
        while t < m.indices.count {
            let i0 = Int(m.indices[t]), i1 = Int(m.indices[t + 1]), i2 = Int(m.indices[t + 2])
            let n = simd_cross(m.positions[i1] - m.positions[i0],
                               m.positions[i2] - m.positions[i0])
            acc[i0] += n; acc[i1] += n; acc[i2] += n
            t += 3
        }
        m.normals = acc.map { simd_length($0) > 1e-6 ? simd_normalize($0) : SIMD3(0, 1, 0) }
    }

    // MARK: Start/finish line + grid boxes

    private static func startFinishNode(_ track: Track) -> SCNNode {
        let line = track.sample(atDistance: 0)
        let plane = SCNPlane(width: CGFloat(line.width), height: 1.0)
        let mat = SCNMaterial()
        mat.diffuse.contents = checkerImage()
        mat.diffuse.wrapS = .repeat
        mat.diffuse.wrapT = .repeat
        plane.firstMaterial = mat
        let node = SCNNode(geometry: plane)
        node.name = "startFinishLine"
        node.simdPosition = line.position + line.up * 0.02
        node.simdOrientation = flatOrientation(forward: line.forward, up: line.up)
        return node
    }

    /// White outline boxes painted at each grid slot.
    private static func gridBoxesNode(_ track: Track) -> SCNNode {
        let parent = SCNNode()
        parent.name = "gridBoxes"
        // Share one geometry across all 20 slots (clone = shared geometry).
        let plane = SCNPlane(width: 2.2, height: 5.5)
        plane.firstMaterial = gridBoxMaterial()
        let template = SCNNode(geometry: plane)
        for slot in track.gridSlots() {
            let up = simd_normalize(simd_cross(slot.right, slot.forward))
            let box = template.clone()
            box.simdPosition = slot.position + up * 0.03
            box.simdOrientation = flatOrientation(forward: slot.forward, up: up)
            parent.addChildNode(box)
        }
        return parent
    }

    private static func gridBoxMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = gridBoxImage()
        m.isDoubleSided = true
        return m
    }

    // MARK: Pit apron (cosmetic)

    /// A flat grey apron strip running alongside the start/finish straight.
    /// The core model has no pit spline yet, so this is purely decorative —
    /// placed just outside the left road edge over the grid zone.
    private static func pitApronNode(_ track: Track) -> SCNNode {
        let length = track.length
        var inner: [SIMD3<Float>] = [], outer: [SIMD3<Float>] = [], up: [SIMD3<Float>] = []
        // Cover roughly the last 250 m of the lap (the S/F straight).
        var d = length - 260
        let apronWidth: Float = 12
        while d <= length - 10 {
            let s = track.sample(atDistance: d)
            inner.append(s.leftEdge - s.right * 1.0 + s.up * 0.01)
            outer.append(s.leftEdge - s.right * apronWidth + s.up * 0.01)
            up.append(s.up)
            d += 8
        }
        guard inner.count >= 2 else { return SCNNode() }
        let m = openStrip(left: outer, right: inner, up: up, uScale: 0.1)
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor(white: 0.32, alpha: 1)
        let node = SCNNode(geometry: SceneGeometry.geometry(from: m, material: mat))
        node.name = "pitApron"
        return node
    }

    // MARK: Helpers

    /// Quaternion that maps local -Z (SCN front) to `forward` and local +Y to `up`.
    /// Use for upright objects (cars): their "up" stays vertical.
    static func orientation(forward: SIMD3<Float>, up: SIMD3<Float>) -> simd_quatf {
        let f = simd_normalize(forward)
        let u = simd_normalize(up)
        let r = simd_normalize(simd_cross(u, -f))   // local +X
        let u2 = simd_cross(-f, r)
        let m = simd_float3x3(columns: (r, u2, -f))
        return simd_quatf(m)
    }

    /// Quaternion that lays a flat `SCNPlane` onto the road surface: the plane's
    /// normal (local +Z) points along `up`, its width (local +X) along `right`,
    /// and its height (local +Y) along `forward`. Use for ground markings
    /// (start/finish line, grid boxes) so they paint flat instead of standing up.
    static func flatOrientation(forward: SIMD3<Float>, up: SIMD3<Float>) -> simd_quatf {
        let f = simd_normalize(forward)
        let u = simd_normalize(up)
        let r = simd_normalize(simd_cross(f, u))    // local +X (right)
        let m = simd_float3x3(columns: (r, f, u))
        return simd_quatf(m)
    }

    private static func checkerImage() -> NSImage {
        let s = 32
        let img = NSImage(size: NSSize(width: s, height: s))
        img.lockFocus()
        for i in 0..<4 {
            for j in 0..<4 {
                ((i + j) % 2 == 0 ? NSColor.white : NSColor.black).setFill()
                NSRect(x: CGFloat(i) * CGFloat(s) / 4, y: CGFloat(j) * CGFloat(s) / 4,
                       width: CGFloat(s) / 4, height: CGFloat(s) / 4).fill()
            }
        }
        img.unlockFocus()
        return img
    }

    private static func gridBoxImage() -> NSImage {
        let s = 64
        let img = NSImage(size: NSSize(width: s, height: s))
        img.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: s, height: s).fill()
        NSColor.white.setStroke()
        let path = NSBezierPath(rect: NSRect(x: 4, y: 4, width: s - 8, height: s - 8))
        path.lineWidth = 6
        path.stroke()
        img.unlockFocus()
        return img
    }
}
