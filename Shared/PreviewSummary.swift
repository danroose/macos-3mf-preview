import Foundation

enum PreviewSummary {
    /// Short caption for the preview, e.g. "239 × 130 × 133 mm · 500K triangles".
    /// Kept compact so it fits Finder's narrow preview pane.
    static func caption(for mesh: ColoredMesh) -> String {
        let size = mesh.boundsMax - mesh.boundsMin
        return "\(millimeters(size.x)) × \(millimeters(size.y)) × \(millimeters(size.z)) mm · \(count(mesh.triangleCount)) triangles"
    }

    static func millimeters(_ v: Float) -> String {
        v >= 100 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    static func count(_ n: Int) -> String {
        switch n {
        case ..<1_000: return "\(n)"
        case ..<10_000: return String(format: "%.1fK", Double(n) / 1_000)
        case ..<1_000_000: return "\(n / 1_000)K"
        default: return String(format: "%.1fM", Double(n) / 1_000_000)
        }
    }
}
