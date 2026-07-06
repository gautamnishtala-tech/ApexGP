import SceneKit
import ApexGPCore
import simd

/// Placeholder-quality F1 car assembled from box/wedge primitives. Gameplay
/// readable and low-poly: a floor + tapered nose, a cockpit wedge, an airbox,
/// two sidepods, front and rear wings, plus four wheels that spin (roll with
/// road speed) and steer (front pair rotates with steering input). A brake-light
/// panel on the rear wing lights up under braking.
///
/// The four wheels share one geometry via node cloning. `node` is placed and
/// oriented every frame by `PhysicsDriver`; `update` handles wheel animation and
/// the brake light — nothing here owns gameplay logic, it only visualizes state.
/// Built on the main thread; animated from the SceneKit render thread (the
/// sanctioned place to mutate scene nodes), so it is not actor-isolated.
final class PlayerCar {
    /// Root node — position/orient this from the interpolated physics state.
    let node = SCNNode()

    // Wheel rig: a steer pivot (rotates about Y) containing a spin node
    // (rolls about X). Front wheels steer, all four spin.
    private struct Wheel { let pivot: SCNNode; let spin: SCNNode; let steers: Bool }
    private var wheels: [Wheel] = []

    private let brakeMaterial = SCNMaterial()
    private var spinAngle: Float = 0

    // Geometry constants (roughly F1-scaled; match the physics wheelbase ~3.6 m).
    private let wheelRadius: Float = 0.33
    private let wheelWidth: Float = 0.36
    private let halfTrack: Float = 0.82     // wheel centre X offset
    private let axleFront: Float = -1.75    // local -Z is forward
    private let axleRear: Float = 1.75
    /// Visual steer angle at full lock (rad) — a touch exaggerated for read.
    private let visualSteer: Float = 0.35

    init() {
        node.name = "playerCar"
        buildBody()
        buildWheels()
    }

    // MARK: - Per-frame update (called from the render loop)

    /// Roll + steer the wheels and drive the brake light.
    /// - Parameters:
    ///   - steer: current steering input (-1…1).
    ///   - braking: current brake input (0…1) for the brake light.
    ///   - forwardSpeed: longitudinal ground speed (m/s), sign = travel direction.
    ///   - frameDelta: real seconds since the last frame.
    func update(steer: Float, braking: Float, forwardSpeed: Float, frameDelta: Float) {
        // Roll: angular velocity = v / r, integrated in render time.
        spinAngle += (forwardSpeed / wheelRadius) * frameDelta
        let steerAngle = -simd_clamp(steer, -1, 1) * visualSteer
        for w in wheels {
            w.spin.simdEulerAngles = SIMD3(spinAngle, 0, 0)
            if w.steers { w.pivot.simdEulerAngles = SIMD3(0, steerAngle, 0) }
        }
        // Brake light: dark red at rest, hot red under braking.
        let g = CGFloat(max(0, min(1, braking)))
        brakeMaterial.emission.contents = NSColor(calibratedRed: 0.15 + 0.85 * g,
                                                  green: 0, blue: 0, alpha: 1)
    }

    // MARK: - Body

    private func buildBody() {
        let red = NSColor.systemRed
        let dark = NSColor(white: 0.10, alpha: 1)
        let carbon = NSColor(white: 0.06, alpha: 1)

        // Floor / monocoque — the main tub.
        addBox(w: 0.9, h: 0.28, l: 3.6, at: SIMD3(0, 0.34, 0.1),
               color: red, chamfer: 0.08)
        // Tapered nose: a slimmer box reaching forward past the front axle.
        addBox(w: 0.42, h: 0.20, l: 1.7, at: SIMD3(0, 0.34, axleFront - 0.4),
               color: red, chamfer: 0.06)
        // Cockpit wedge: a raised block behind the nose.
        addBox(w: 0.7, h: 0.32, l: 1.2, at: SIMD3(0, 0.58, 0.35),
               color: red, chamfer: 0.06)
        // Airbox / roll hoop above and behind the cockpit.
        addBox(w: 0.34, h: 0.42, l: 0.6, at: SIMD3(0, 0.78, 0.95),
               color: carbon, chamfer: 0.05)

        // Sidepods flanking the tub.
        for x: Float in [-0.72, 0.72] {
            addBox(w: 0.34, h: 0.30, l: 1.6, at: SIMD3(x, 0.40, 0.4),
                   color: dark, chamfer: 0.06)
        }

        // Front wing: wide, low, thin, ahead of the front axle.
        addBox(w: 1.7, h: 0.06, l: 0.5, at: SIMD3(0, 0.16, axleFront - 1.05),
               color: carbon, chamfer: 0.02)
        // Rear wing plane on two posts.
        addBox(w: 1.5, h: 0.08, l: 0.5, at: SIMD3(0, 0.95, axleRear + 0.55),
               color: carbon, chamfer: 0.02)
        for x: Float in [-0.45, 0.45] {
            addBox(w: 0.05, h: 0.55, l: 0.08, at: SIMD3(x, 0.68, axleRear + 0.55),
                   color: carbon, chamfer: 0)
        }

        // Brake-light panel under the rear wing (its own material, animated).
        brakeMaterial.diffuse.contents = NSColor(white: 0.1, alpha: 1)
        brakeMaterial.emission.contents = NSColor(calibratedRed: 0.15, green: 0, blue: 0, alpha: 1)
        let light = SCNNode(geometry: SCNBox(width: 0.30, height: 0.16,
                                             length: 0.06, chamferRadius: 0.01))
        light.geometry!.firstMaterial = brakeMaterial
        light.simdPosition = SIMD3(0, 0.66, axleRear + 0.62)
        node.addChildNode(light)
    }

    private func addBox(w: Float, h: Float, l: Float, at p: SIMD3<Float>,
                        color: NSColor, chamfer: Float) {
        let box = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(l),
                         chamferRadius: CGFloat(chamfer))
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.roughness.contents = NSNumber(value: 0.5)
        box.firstMaterial = mat
        let n = SCNNode(geometry: box)
        n.simdPosition = p
        node.addChildNode(n)
    }

    // MARK: - Wheels (one geometry, cloned four times)

    private func buildWheels() {
        // Master wheel geometry: a cylinder whose height axis is rotated to lie
        // along local X (the axle), so rolling is a rotation about X.
        let cyl = SCNCylinder(radius: CGFloat(wheelRadius), height: CGFloat(wheelWidth))
        let tyre = SCNMaterial()
        tyre.diffuse.contents = NSColor(white: 0.05, alpha: 1)
        tyre.roughness.contents = NSNumber(value: 0.9)
        cyl.firstMaterial = tyre
        let master = SCNNode(geometry: cyl)
        master.eulerAngles.z = .pi / 2

        let placements: [(x: Float, z: Float, steers: Bool)] = [
            (-halfTrack, axleFront, true),
            ( halfTrack, axleFront, true),
            (-halfTrack, axleRear, false),
            ( halfTrack, axleRear, false),
        ]
        for p in placements {
            let pivot = SCNNode()
            pivot.simdPosition = SIMD3(p.x, wheelRadius, p.z)
            let spin = SCNNode()
            spin.addChildNode(master.clone())   // clone shares the geometry
            pivot.addChildNode(spin)
            node.addChildNode(pivot)
            wheels.append(Wheel(pivot: pivot, spin: spin, steers: p.steers))
        }
    }
}
