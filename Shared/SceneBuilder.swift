import SceneKit
import simd

enum SceneBuilder {
    /// Builds a lit scene with the model centered at the origin, Y-up, sitting on the floor plane.
    static func scene(for mesh: ColoredMesh) -> (scene: SCNScene, radius: Float) {
        let scene = SCNScene()
        let center = (mesh.boundsMin + mesh.boundsMax) / 2
        let size = mesh.boundsMax - mesh.boundsMin
        let radius = max(simd_length(size) / 2, 0.001)

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        positions.reserveCapacity(mesh.triangleCount * 3)
        normals.reserveCapacity(mesh.triangleCount * 3)
        var elements: [SCNGeometryElement] = []
        var materials: [SCNMaterial] = []

        // Flat shading: each triangle gets its own three vertices with the face normal.
        for (color, verts) in mesh.groups.sorted(by: { $0.value.count > $1.value.count }) {
            let first = positions.count
            var t = 0
            while t + 2 < verts.count {
                // Slicer space is Z-up; SceneKit is Y-up.
                let a = yUp(verts[t] - center), b = yUp(verts[t + 1] - center), c = yUp(verts[t + 2] - center)
                var n = simd_cross(b - a, c - a)
                let len = simd_length(n)
                n = len > 0 ? n / len : SIMD3(0, 1, 0)
                positions.append(contentsOf: [a, b, c])
                normals.append(contentsOf: [n, n, n])
                t += 3
            }
            let count = positions.count - first
            guard count > 0 else { continue }
            let indices = (0..<count).map { UInt32(first + $0) }
            elements.append(SCNGeometryElement(indices: indices, primitiveType: .triangles))

            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = NSColor(srgbRed: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: 1)
            m.roughness.contents = 0.55
            m.metalness.contents = 0.0
            m.isDoubleSided = true
            materials.append(m)
        }

        let geometry = SCNGeometry(sources: [source(positions, semantic: .vertex), source(normals, semantic: .normal)],
                                   elements: elements)
        geometry.materials = materials
        let node = SCNNode(geometry: geometry)
        scene.rootNode.addChildNode(node)

        // Soft studio lighting: key, fill, rim and an ambient base.
        addLight(to: scene, type: .directional, intensity: 900, angles: SCNVector3(-0.9, 0.6, 0), shadows: false)
        addLight(to: scene, type: .directional, intensity: 400, angles: SCNVector3(-0.3, -2.2, 0), shadows: false)
        addLight(to: scene, type: .directional, intensity: 300, angles: SCNVector3(0.6, 3.0, 0), shadows: false)
        addLight(to: scene, type: .ambient, intensity: 350, angles: SCNVector3Zero, shadows: false)

        let camera = SCNCamera()
        camera.fieldOfView = 35
        camera.zNear = Double(radius) * 0.01
        camera.zFar = Double(radius) * 100
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        let distance = radius / Float(sin(Double(camera.fieldOfView) / 2 * .pi / 180)) * 1.05
        let dir = simd_normalize(SIMD3<Float>(0.55, 0.45, 1.0))
        cameraNode.simdPosition = dir * distance
        cameraNode.simdLook(at: .zero)
        cameraNode.name = "camera"
        scene.rootNode.addChildNode(cameraNode)
        return (scene, radius)
    }

    private static func yUp(_ p: SIMD3<Float>) -> SIMD3<Float> { SIMD3(p.x, p.z, -p.y) }

    private static func source(_ v: [SIMD3<Float>], semantic: SCNGeometrySource.Semantic) -> SCNGeometrySource {
        let data = v.withUnsafeBufferPointer { buf in
            Data(bytes: buf.baseAddress!, count: buf.count * MemoryLayout<SIMD3<Float>>.stride)
        }
        return SCNGeometrySource(data: data, semantic: semantic, vectorCount: v.count, usesFloatComponents: true,
                                 componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0,
                                 dataStride: MemoryLayout<SIMD3<Float>>.stride)
    }

    private static func addLight(to scene: SCNScene, type: SCNLight.LightType, intensity: CGFloat,
                                 angles: SCNVector3, shadows: Bool) {
        let light = SCNLight()
        light.type = type
        light.intensity = intensity
        light.castsShadow = shadows
        let node = SCNNode()
        node.light = light
        node.eulerAngles = angles
        scene.rootNode.addChildNode(node)
    }
}
