import AppKit

/// Presents the macOS system share sheet (Messages, Mail, AirDrop, Slack, etc.).
@MainActor
public enum SystemSharePresenter {
    /// Shares a screenshot/image via `NSSharingServicePicker`.
    public static func present(image: CGImage, from window: NSWindow? = nil) {
        // Prefer a temp PNG file so more third-party apps accept the item;
        // keep NSImage as a fallback when encoding fails.
        if let fileURL = writeTemporaryPNG(image) {
            present(items: [fileURL], from: window)
            return
        }
        let nsImage = NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
        present(items: [nsImage], from: window)
    }

    /// Shares an existing file (screenshot PNG, video, GIF, …).
    public static func present(fileURL: URL, from window: NSWindow? = nil) {
        present(items: [fileURL], from: window)
    }

    public static func present(items: [Any], from window: NSWindow? = nil) {
        guard !items.isEmpty else { return }

        let picker = NSSharingServicePicker(items: items)
        let hostWindow = window ?? NSApp.keyWindow ?? NSApp.mainWindow
        guard let view = hostWindow?.contentView else { return }

        let anchor: NSRect
        if let event = NSApp.currentEvent, event.window === hostWindow {
            let point = event.locationInWindow
            anchor = NSRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2)
        } else {
            anchor = NSRect(
                x: view.bounds.midX - 1,
                y: view.bounds.midY - 1,
                width: 2,
                height: 2
            )
        }

        picker.show(relativeTo: anchor, of: view, preferredEdge: .minY)
    }

    private static func writeTemporaryPNG(_ image: CGImage) -> URL? {
        guard let data = ImageUtilities.pngData(from: image) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Capso-Share-\(UUID().uuidString)")
            .appendingPathExtension("png")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
