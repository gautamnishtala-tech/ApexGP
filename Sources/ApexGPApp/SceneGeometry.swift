import SceneKit
import ApexGPCore
import simd

// SceneKit-specific assembly. All mesh *math* lives in ApexGPCore
// (TrackMesh.swift); this file only turns those plain vertex buffers into
// `SCNGeometry`. Keep gameplay logic out of here.

enum SceneGeometry {

    /// Build an `SCNGeometry` from a renderer-agnostic `MeshData`.
    static func geometry(from mesh: MeshData, material: SCNMaterial) -> SCNGeometry {
        let positions = mesh.positions.map { SCNVector3($0.x, $0.y, $0.z) }
        let normals = mesh.normals.map { SCNVector3($0.x, $0.y, $0.z) }
        let uvs = mesh.uvs.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }

        let vSource = SCNGeometrySource(vertices: positions)
        let nSource = SCNGeometrySource(normals: normals)
        let tSource = SCNGeometrySource(textureCoordinates: uvs)
        let element = SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)

        let geo = SCNGeometry(sources: [vSource, nSource, tSource], elements: [element])
        geo.firstMaterial = material
        return geo
    }

    // MARK: Materials

    static func roadMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = NSColor.black
        // Keep it reading as black: ambient/specular/environment light otherwise
        // lift a dark diffuse to a washed-out blue-grey under the sky lighting.
        m.ambient.contents = NSColor.black
        m.specular.contents = NSColor.black
        m.metalness.contents = NSColor.black
        m.roughness.contents = NSColor.white
        m.isDoubleSided = false
        return m
    }

    // Ground around the circuit — everything that isn't track is green grass.
    static func grassMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = NSColor(red: 0.24, green: 0.46, blue: 0.18, alpha: 1)
        m.roughness.contents = NSColor(white: 1, alpha: 1)
        return m
    }

    static func barrierMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = barrierStripeImage()
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .clamp
        m.isDoubleSided = true
        return m
    }

    static func kerbMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = kerbStripeImage()
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .clamp
        m.isDoubleSided = false
        return m
    }

    // MARK: Procedural stripe textures

    /// Red/white diagonal-free alternating stripe (kerb).
    static func kerbStripeImage() -> NSImage {
        let w = 64, h = 8
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        for i in 0..<8 {
            (i % 2 == 0 ? NSColor.systemRed : NSColor.white).setFill()
            NSRect(x: CGFloat(i) * CGFloat(w) / 8, y: 0,
                   width: CGFloat(w) / 8, height: CGFloat(h)).fill()
        }
        img.unlockFocus()
        return img
    }

    /// Red/white barrier panel stripe.
    static func barrierStripeImage() -> NSImage {
        let w = 64, h = 16
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        for i in 0..<4 {
            (i % 2 == 0 ? NSColor.systemRed : NSColor.white).setFill()
            NSRect(x: CGFloat(i) * CGFloat(w) / 4, y: 0,
                   width: CGFloat(w) / 4, height: CGFloat(h)).fill()
        }
        img.unlockFocus()
        return img
    }
}
