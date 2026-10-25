import Foundation
import simd

/// A flattened, world-space triangle soup grouped by display color.
struct ColoredMesh {
    /// RGBA color -> triangle vertex positions (3 per triangle).
    var groups: [SIMD4<Float>: [SIMD3<Float>]] = [:]
    var boundsMin = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
    var boundsMax = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

    var isEmpty: Bool { groups.isEmpty }
    var triangleCount: Int { groups.values.reduce(0) { $0 + $1.count / 3 } }
}

/// Loads a 3MF package: core spec meshes, components, build items and transforms, plus
/// colors from 3MF materials, Bambu Studio / OrcaSlicer and PrusaSlicer extruder settings and paint.
final class ThreeMFModel {
    let zip: ZipArchive

    init(url: URL) throws {
        zip = try ZipArchive(url: url)
    }

    // MARK: - Embedded thumbnail

    /// The best preview image the slicer stored inside the package, if any.
    func embeddedThumbnailData() -> Data? {
        var candidates = ["Metadata/plate_1.png", "Metadata/thumbnail.png"]
        if let rels = try? zip.read("_rels/.rels"), let text = String(data: rels, encoding: .utf8),
           let target = Self.relationshipTarget(in: text, typeSuffix: "/thumbnail") {
            candidates.append(target)
        }
        candidates.append(contentsOf: zip.names.filter {
            $0.lowercased().hasPrefix("metadata/") && ($0.lowercased().hasSuffix(".png") || $0.lowercased().hasSuffix(".jpg"))
                && !$0.contains("pick_") && !$0.contains("no_light") && !$0.contains("small")
        }.sorted())
        for name in candidates {
            if let d = try? zip.read(name), !d.isEmpty { return d }
        }
        return nil
    }

    private static func relationshipTarget(in xml: String, typeSuffix: String) -> String? {
        for rel in xml.components(separatedBy: "<Relationship").dropFirst() {
            guard let type = attr("Type", in: rel), type.hasSuffix(typeSuffix) else { continue }
            return attr("Target", in: rel)
        }
        return nil
    }

    private static func attr(_ name: String, in s: String) -> String? {
        guard let r = s.range(of: name + "=\"") else { return nil }
        guard let end = s[r.upperBound...].firstIndex(of: "\"") else { return nil }
        return String(s[r.upperBound..<end])
    }

    // MARK: - Geometry

    private struct Component { var path: String?; var objectID: Int; var transform: simd_float4x4 }

    private final class Object {
        var positions: [SIMD3<Float>] = []
        var triangles: [SIMD3<Int32>] = []
        /// Per triangle: 0 = inherit, >0 = filament/extruder number, <0 = -(explicit color index + 1).
        var triColor: [Int32] = []
        var components: [Component] = []
        var defaultColor: Int32 = 0
    }

    private struct Item { var path: String?; var objectID: Int; var transform: simd_float4x4 }

    private var files: [String: [Int: Object]] = [:]
    private var items: [Item] = []
    private var explicitColors: [SIMD4<Float>] = []
    private var materialGroups: [Int: [Int32]] = [:]   // resource id -> explicit color indices
    private static let mainPath = "/3D/3dmodel.model"

    func buildMesh() throws -> ColoredMesh {
        let main = mainModelPath()
        try parseModel(path: main, isMain: true)

        let settings = SlicerSettings(zip: zip)
        var mesh = ColoredMesh()

        func resolve(_ code: Int32, extruder: Int) -> SIMD4<Float> {
            if code < 0 { return explicitColors[Int(-code - 1)] }
            let n = code > 0 ? Int(code) : extruder
            return settings.color(forExtruder: n)
        }

        func emit(path: String, objectID: Int, transform: simd_float4x4, buildObjectID: Int, depth: Int) throws {
            guard depth < 32 else { return }
            if files[path] == nil { try parseModel(path: path, isMain: false) }
            guard let obj = files[path]?[objectID] else { return }

            if !obj.triangles.isEmpty {
                let world = obj.positions.map { p -> SIMD3<Float> in
                    let v = transform * SIMD4<Float>(p, 1)
                    return SIMD3(v.x, v.y, v.z)
                }
                let base = settings.extruder(buildObject: buildObjectID, part: objectID)
                for (t, tri) in obj.triangles.enumerated() {
                    let a = Int(tri.x), b = Int(tri.y), c = Int(tri.z)
                    guard a < world.count, b < world.count, c < world.count else { continue }
                    var code = obj.triColor[t]
                    if code == 0 { code = obj.defaultColor }
                    let ext = settings.rangeExtruder(object: buildObjectID, triangle: t) ?? base
                    let color = resolve(code, extruder: ext)
                    let pa = world[a], pb = world[b], pc = world[c]
                    mesh.groups[color, default: []].append(contentsOf: [pa, pb, pc])
                    mesh.boundsMin = simd_min(mesh.boundsMin, simd_min(pa, simd_min(pb, pc)))
                    mesh.boundsMax = simd_max(mesh.boundsMax, simd_max(pa, simd_max(pb, pc)))
                }
            }
            for c in obj.components {
                // 3MF transforms apply child-first: world = parent * child.
                try emit(path: c.path ?? path, objectID: c.objectID, transform: transform * c.transform,
                         buildObjectID: buildObjectID, depth: depth + 1)
            }
        }

        let buildItems = items.isEmpty ? (files[main] ?? [:]).keys.sorted().map {
            Item(path: nil, objectID: $0, transform: matrix_identity_float4x4)
        } : items
        for item in buildItems {
            try emit(path: item.path ?? main, objectID: item.objectID, transform: item.transform,
                     buildObjectID: item.objectID, depth: 0)
        }
        return mesh
    }

    private func mainModelPath() -> String {
        if let rels = try? zip.read("_rels/.rels"), let text = String(data: rels, encoding: .utf8),
           let target = Self.relationshipTarget(in: text, typeSuffix: "/3dmodel") {
            return target.hasPrefix("/") ? target : "/" + target
        }
        if zip.contains(Self.mainPath) { return Self.mainPath }
        if let any = zip.names.first(where: { $0.lowercased().hasSuffix(".model") }) { return "/" + any }
        return Self.mainPath
    }

    // MARK: - XML scanning
    //
    // Model files can be 100MB+ of XML, so this is a hand-rolled tag scanner rather than XMLParser.

    private func parseModel(path: String, isMain: Bool) throws {
        guard var data = try zip.read(path) else { files[path] = [:]; return }
        data.append(0) // terminator so strtof/strtol never run off the end
        var objects: [Int: Object] = [:]

        data.withUnsafeBytes { raw in
            let buf = raw.bindMemory(to: UInt8.self)
            let base = buf.baseAddress!
            let n = buf.count - 1
            var i = 0
            var current: Object?
            var currentGroup: Int?

            while i < n {
                guard let lt = memchr(base + i, 0x3C /* < */, n - i) else { break }
                let start = base.distance(to: lt.assumingMemoryBound(to: UInt8.self)) + 1
                guard let gt = memchr(base + start, 0x3E /* > */, n - start) else { break }
                let end = base.distance(to: gt.assumingMemoryBound(to: UInt8.self))
                i = end + 1

                var nameEnd = start
                while nameEnd < end, base[nameEnd] > 0x20, base[nameEnd] != 0x2F || nameEnd == start { nameEnd += 1 }
                let tag = Tag(base: base, nameStart: start, nameEnd: nameEnd, end: end)

                switch tag.localName {
                case "vertex":
                    guard let o = current else { break }
                    var x: Float = 0, y: Float = 0, z: Float = 0
                    tag.forEachAttribute { name, v in
                        switch name {
                        case "x": x = strtof(v, nil)
                        case "y": y = strtof(v, nil)
                        case "z": z = strtof(v, nil)
                        default: break
                        }
                    }
                    o.positions.append(SIMD3(x, y, z))
                case "triangle":
                    guard let o = current else { break }
                    var v = SIMD3<Int32>(0, 0, 0)
                    var code: Int32 = 0
                    var pid = -1, p1 = -1
                    tag.forEachAttribute { name, val in
                        switch name {
                        case "v1": v.x = Int32(strtol(val, nil, 10))
                        case "v2": v.y = Int32(strtol(val, nil, 10))
                        case "v3": v.z = Int32(strtol(val, nil, 10))
                        case "pid": pid = strtol(val, nil, 10)
                        case "p1": p1 = strtol(val, nil, 10)
                        case "paint_color", "slic3rpe:mmu_segmentation", "mmu_segmentation":
                            code = Int32(PaintDecoder.dominantState(val))
                        default: break
                        }
                    }
                    if code == 0, p1 >= 0 {
                        let group = pid >= 0 ? pid : nil
                        if let g = group ?? self.defaultGroup(of: o), let colors = self.materialGroups[g], p1 < colors.count {
                            code = colors[p1]
                        }
                    }
                    o.triangles.append(v)
                    o.triColor.append(code)
                case "object":
                    if tag.isClosing { current = nil; break }
                    let o = Object()
                    var id = 0, pid = -1, pindex = 0
                    tag.forEachAttribute { name, v in
                        switch name {
                        case "id": id = strtol(v, nil, 10)
                        case "pid": pid = strtol(v, nil, 10)
                        case "pindex": pindex = strtol(v, nil, 10)
                        default: break
                        }
                    }
                    if pid >= 0, let colors = self.materialGroups[pid], pindex < colors.count {
                        o.defaultColor = colors[pindex]
                        self.objectGroups[ObjectIdentifier(o)] = pid
                    }
                    objects[id] = o
                    current = tag.isSelfClosing ? nil : o
                case "component":
                    guard let o = current else { break }
                    var c = Component(path: nil, objectID: 0, transform: matrix_identity_float4x4)
                    tag.forEachAttribute { name, v in
                        switch name {
                        case "objectid": c.objectID = strtol(v, nil, 10)
                        case "p:path", "path": c.path = quotedString(v)
                        case "transform": c.transform = Self.parseTransform(v)
                        default: break
                        }
                    }
                    o.components.append(c)
                case "item":
                    guard isMain else { break }
                    var it = Item(path: nil, objectID: 0, transform: matrix_identity_float4x4)
                    tag.forEachAttribute { name, v in
                        switch name {
                        case "objectid": it.objectID = strtol(v, nil, 10)
                        case "p:path", "path": it.path = quotedString(v)
                        case "transform": it.transform = Self.parseTransform(v)
                        default: break
                        }
                    }
                    self.items.append(it)
                case "basematerials", "colorgroup":
                    if tag.isClosing { currentGroup = nil; break }
                    var id = 0
                    tag.forEachAttribute { name, v in if name == "id" { id = strtol(v, nil, 10) } }
                    self.materialGroups[id] = []
                    currentGroup = id
                case "base", "color":
                    guard let g = currentGroup else { break }
                    tag.forEachAttribute { name, v in
                        if name == "displaycolor" || name == "color" {
                            let hex = quotedString(v)
                            self.explicitColors.append(SlicerSettings.parseHex(String(hex)) ?? SlicerSettings.fallback)
                            self.materialGroups[g, default: []].append(-Int32(self.explicitColors.count))
                        }
                    }
                default:
                    break
                }
            }
        }
        files[path] = objects
    }

    private var objectGroups: [ObjectIdentifier: Int] = [:]
    private func defaultGroup(of o: Object) -> Int? { objectGroups[ObjectIdentifier(o)] }

    /// 3MF transform: 12 numbers, row-major 4x3 with translation in the last row (row-vector convention).
    private static func parseTransform(_ p: UnsafePointer<CChar>) -> simd_float4x4 {
        var v = [Float](repeating: 0, count: 12)
        var cur = UnsafeMutablePointer(mutating: p)
        for k in 0..<12 {
            var next: UnsafeMutablePointer<CChar>?
            v[k] = strtof(cur, &next)
            guard let nx = next, nx != cur else { return matrix_identity_float4x4 }
            cur = nx
        }
        // Convert to column-vector convention: columns are the basis vectors and translation.
        return simd_float4x4(columns: (
            SIMD4(v[0], v[1], v[2], 0),
            SIMD4(v[3], v[4], v[5], 0),
            SIMD4(v[6], v[7], v[8], 0),
            SIMD4(v[9], v[10], v[11], 1)))
    }
}

/// One XML tag in the raw buffer, with zero-copy attribute iteration.
private struct Tag {
    let base: UnsafePointer<UInt8>
    let nameStart: Int
    let nameEnd: Int
    let end: Int

    var isClosing: Bool { base[nameStart] == 0x2F }
    var isSelfClosing: Bool { end > nameStart && base[end - 1] == 0x2F }

    /// Element name without any namespace prefix or leading slash.
    var localName: Substring {
        var s = nameStart
        if base[s] == 0x2F { s += 1 }
        var e = nameEnd
        while e > s, base[e - 1] == 0x2F { e -= 1 }
        var colon = s
        for k in s..<e where base[k] == 0x3A { colon = k + 1 }
        let str = String(decoding: UnsafeBufferPointer(start: base + colon, count: max(0, e - colon)), as: UTF8.self)
        return Substring(str)
    }

    /// Calls `body` with each attribute's name and a C-string pointer at its value (terminated by `"`).
    func forEachAttribute(_ body: (Substring, UnsafePointer<CChar>) -> Void) {
        var k = nameEnd
        while k < end {
            while k < end, base[k] <= 0x20 { k += 1 }
            let ns = k
            while k < end, base[k] != 0x3D /* = */, base[k] > 0x20 { k += 1 }
            let ne = k
            while k < end, base[k] != 0x22, base[k] != 0x27 { k += 1 }
            guard k < end else { return }
            let quote = base[k]
            k += 1
            let vs = k
            while k < end, base[k] != quote { k += 1 }
            if ne > ns {
                let name = String(decoding: UnsafeBufferPointer(start: base + ns, count: ne - ns), as: UTF8.self)
                UnsafeRawPointer(base + vs).withMemoryRebound(to: CChar.self, capacity: k - vs + 1) { body(Substring(name), $0) }
            }
            k += 1
        }
    }
}

/// Decodes PrusaSlicer/Bambu TriangleSelector paint strings (hex nibbles, read from the end)
/// and returns the state covering the most area: 0 = unpainted, n = extruder n.
enum PaintDecoder {
    static func dominantState(_ p: UnsafePointer<CChar>) -> Int {
        var len = 0
        while p[len] != 0, p[len] != 0x22 { len += 1 }
        guard len > 0 else { return 0 }
        var nibbles = [UInt8]()
        nibbles.reserveCapacity(len)
        for k in stride(from: len - 1, through: 0, by: -1) {
            let c = UInt8(bitPattern: p[k])
            switch c {
            case 0x30...0x39: nibbles.append(c - 0x30)
            case 0x41...0x46: nibbles.append(c - 0x41 + 10)
            case 0x61...0x66: nibbles.append(c - 0x61 + 10)
            default: return 0
            }
        }
        if nibbles.count == 1 {
            let n = nibbles[0]
            return n & 3 == 0 ? Int(n >> 2) : 0
        }
        var weights = [Int: Float]()
        var i = 0
        func node(_ w: Float, _ depth: Int) {
            guard i < nibbles.count, depth < 64 else { return }
            let n = nibbles[i]; i += 1
            let split = Int(n & 3)
            if split == 0 {
                var state = Int(n >> 2)
                if state == 3, i < nibbles.count { state = Int(nibbles[i]) + 3; i += 1 }
                weights[state, default: 0] += w
            } else {
                let children = split + 1
                for _ in 0..<children { node(w / Float(children), depth + 1) }
            }
        }
        node(1, 0)
        return weights.max { $0.value < $1.value }?.key ?? 0
    }
}

/// Reads an attribute value up to its closing quote.
func quotedString(_ p: UnsafePointer<CChar>) -> String {
    var len = 0
    while p[len] != 0, p[len] != 0x22, p[len] != 0x27 { len += 1 }
    return p.withMemoryRebound(to: UInt8.self, capacity: len) {
        String(decoding: UnsafeBufferPointer(start: $0, count: len), as: UTF8.self)
    }
}
