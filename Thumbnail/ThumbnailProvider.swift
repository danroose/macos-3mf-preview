import AppKit
import QuickLookThumbnailing

/// Finder icons: the slicer's embedded plate image, or a 3D render when the file has none. No "3MF" badge.
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        do {
            let model = try ThreeMFModel(url: request.fileURL)
            var image: NSImage?
            if let data = model.embeddedThumbnailData() { image = NSImage(data: data) }
            if image == nil {
                let side = max(request.maximumSize.width, request.maximumSize.height) * request.scale
                image = SnapshotRenderer.image(for: try model.buildMesh(), size: CGSize(width: side, height: side))
            }
            guard let image, image.size.width > 0, image.size.height > 0 else {
                handler(nil, CocoaError(.fileReadCorruptFile)); return
            }

            let max = request.maximumSize
            let scale = min(max.width / image.size.width, max.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let reply = QLThumbnailReply(contextSize: size) {
                image.draw(in: NSRect(origin: .zero, size: size))
                return true
            }
            reply.extensionBadge = ""
            handler(reply, nil)
        } catch {
            handler(nil, error)
        }
    }
}
