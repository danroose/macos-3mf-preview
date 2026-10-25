import SwiftUI

/// Host app. Its only job is to carry the Quick Look extensions and declare the .3mf file type.
@main
struct ThreeMFPreviewApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text("3MF Preview is installed").font(.title2.bold())
                Text("Select a .3mf file in Finder and press Space for an interactive 3D preview.\nDrag to rotate, scroll or pinch to zoom.")
                Text("Finder icons show the slicer's plate image, or a 3D render if the file has none.")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(width: 460)
        }
        .windowResizability(.contentSize)
    }
}
