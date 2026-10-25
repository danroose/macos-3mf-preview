import Foundation

/// Extruder assignments and filament colors written by Bambu Studio / OrcaSlicer and PrusaSlicer.
struct SlicerSettings {
    static let fallback = SIMD4<Float>(0.62, 0.66, 0.72, 1)

    private var colors: [SIMD4<Float>] = []
    private var objectExtruder: [Int: Int] = [:]
    private var partExtruder: [Int: [Int: Int]] = [:]
    /// PrusaSlicer volumes: triangle index ranges within an object, each with its own extruder.
    private var volumeRanges: [Int: [(ClosedRange<Int>, Int)]] = [:]

    init(zip: ZipArchive) {
        if let d = try? zip.read("Metadata/project_settings.config"),
           let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            colors = Self.colorList(json["filament_colour"])
        }
        if colors.isEmpty, let d = try? zip.read("Metadata/Slic3r_PE.config"), let text = String(data: d, encoding: .utf8) {
            let extruder = Self.iniList(text, key: "extruder_colour")
            let filament = Self.iniList(text, key: "filament_colour")
            colors = (0..<max(extruder.count, filament.count)).map { k in
                (k < extruder.count ? Self.parseHex(extruder[k]) : nil)
                    ?? (k < filament.count ? Self.parseHex(filament[k]) : nil) ?? Self.fallback
            }
        }
        for name in ["Metadata/model_settings.config", "Metadata/Slic3r_PE_model.config"] {
            if let d = try? zip.read(name) { parseModelConfig(d) }
        }
    }

    func color(forExtruder n: Int) -> SIMD4<Float> {
        if n >= 1, n <= colors.count { return colors[n - 1] }
        if colors.isEmpty { return n <= 1 ? Self.fallback : Self.palette[(n - 2) % Self.palette.count] }
        return colors[0]
    }

    func extruder(buildObject: Int, part: Int) -> Int {
        partExtruder[buildObject]?[part] ?? objectExtruder[buildObject] ?? 1
    }

    func rangeExtruder(object: Int, triangle: Int) -> Int? {
        guard let ranges = volumeRanges[object] else { return nil }
        return ranges.first { $0.0.contains(triangle) }?.1
    }

    // MARK: - Parsing

    private static let palette: [SIMD4<Float>] = [
        SIMD4(0.86, 0.32, 0.30, 1), SIMD4(0.30, 0.62, 0.86, 1), SIMD4(0.95, 0.78, 0.30, 1), SIMD4(0.40, 0.75, 0.45, 1),
    ]

    static func parseHex(_ s: String) -> SIMD4<Float>? {
        var hex = s.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let v = UInt64(hex, radix: 16) else { return nil }
        let rgba = hex.count == 6 ? (v << 8 | 0xFF) : v
        return SIMD4(Float((rgba >> 24) & 0xFF), Float((rgba >> 16) & 0xFF), Float((rgba >> 8) & 0xFF), 255) / 255
    }

    private static func colorList(_ any: Any?) -> [SIMD4<Float>] {
        let strings: [String]
        if let a = any as? [String] { strings = a } else if let s = any as? String { strings = s.components(separatedBy: ";") } else { return [] }
        return strings.map { parseHex($0) ?? fallback }
    }

    private static func iniList(_ text: String, key: String) -> [String] {
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: CharacterSet(charactersIn: "; \t"))
            guard t.hasPrefix(key), let eq = t.firstIndex(of: "=") else { continue }
            return t[t.index(after: eq)...].trimmingCharacters(in: .whitespaces).components(separatedBy: ";")
        }
        return []
    }

    private mutating func parseModelConfig(_ data: Data) {
        let delegate = ConfigParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        for (k, v) in delegate.objectExtruder { objectExtruder[k] = v }
        for (k, v) in delegate.partExtruder { partExtruder[k, default: [:]].merge(v) { $1 } }
        for (k, v) in delegate.volumeRanges { volumeRanges[k, default: []].append(contentsOf: v) }
    }
}

private final class ConfigParser: NSObject, XMLParserDelegate {
    var objectExtruder: [Int: Int] = [:]
    var partExtruder: [Int: [Int: Int]] = [:]
    var volumeRanges: [Int: [(ClosedRange<Int>, Int)]] = [:]

    private var object: Int?
    private var part: Int?
    private var volume: ClosedRange<Int>?
    private var volumeExtruder: Int?

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes a: [String: String] = [:]) {
        switch name {
        case "object":
            object = a["id"].flatMap(Int.init)
        case "part":
            part = a["id"].flatMap(Int.init)
        case "volume":
            if let f = a["firstid"].flatMap(Int.init), let l = a["lastid"].flatMap(Int.init), f <= l { volume = f...l }
            volumeExtruder = nil
        case "metadata":
            guard a["key"] == "extruder", let v = a["value"].flatMap(Int.init), v > 0, let o = object else { return }
            if volume != nil { volumeExtruder = v }
            else if let p = part { partExtruder[o, default: [:]][p] = v }
            else { objectExtruder[o] = v }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "object": object = nil
        case "part": part = nil
        case "volume":
            if let o = object, let r = volume, let e = volumeExtruder { volumeRanges[o, default: []].append((r, e)) }
            volume = nil
        default: break
        }
    }
}
