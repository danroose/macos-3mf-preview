import AppKit

// Command-line check: parses each 3MF, prints stats, and writes a 3D render PNG to the output folder.
// Usage: render-test <output-dir> <file.3mf>...
let out = URL(fileURLWithPath: CommandLine.arguments[1])
for path in CommandLine.arguments.dropFirst(2) {
    let url = URL(fileURLWithPath: path)
    let t0 = Date()
    do {
        let model = try ThreeMFModel(url: url)
        let mesh = try model.buildMesh()
        let t1 = Date()
        let colors = mesh.groups.map { (c, v) in String(format: "#%02X%02X%02X×%d", Int(c.x * 255), Int(c.y * 255), Int(c.z * 255), v.count / 3) }
        print(String(format: "%@: %d tris, parse %.2fs, thumb %@, colors %@", url.lastPathComponent, mesh.triangleCount,
                     t1.timeIntervalSince(t0), model.embeddedThumbnailData() != nil ? "yes" : "no", colors.joined(separator: " ")))
        if let img = SnapshotRenderer.image(for: mesh, size: CGSize(width: 512, height: 512)),
           let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: out.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".png"))
        }
    } catch {
        print("\(url.lastPathComponent): ERROR \(error)")
    }
}
