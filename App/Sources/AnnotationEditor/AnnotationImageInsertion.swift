import AppKit
import ImageIO
import UniformTypeIdentifiers
import AnnotationKit
import SharedKit

@MainActor
enum AnnotationImageInsertion {
    static func imageFromClipboard() -> CGImage? {
        ImageUtilities.cgImageFromPasteboard()
    }

    static func imageFromOpenPanel() -> CGImage? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .gif, .webP, .tiff, .bmp]
        panel.title = String(localized: "Insert Image")
        panel.prompt = String(localized: "Insert")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return cgImage(from: url)
    }

    @discardableResult
    static func insertIntoDocument(_ document: AnnotationDocument, image: CGImage) -> Bool {
        document.insertImage(image) != nil
    }

    private static func cgImage(from url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return image
        }
        guard let nsImage = NSImage(data: data) else { return nil }
        return ImageUtilities.cgImage(from: nsImage)
    }
}
