import AppKit

/// Presents the macOS system share sheet (Messages, Mail, AirDrop, Slack, etc.).
@MainActor
public enum SystemSharePresenter {
    /// Shares a screenshot/image via `NSSharingServicePicker`.
    /// - Parameters:
    ///   - relativeTo: Optional rect in the window's `contentView` coordinates.
    ///     Pass the share button's frame so the picker anchors correctly even
    ///     when presentation is deferred (e.g. after an async render).
    ///   - preferredEdge: Edge of the anchor the picker should appear next to.
    ///     Use `.maxY` for bottom-bar buttons so the sheet opens upward.
    public static func present(
        image: CGImage,
        from window: NSWindow? = nil,
        relativeTo rectInContentView: NSRect? = nil,
        preferredEdge: NSRectEdge = .minY
    ) {
        // Prefer a temp PNG file so more third-party apps accept the item;
        // keep NSImage as a fallback when encoding fails.
        if let fileURL = writeTemporaryPNG(image) {
            present(
                items: [fileURL],
                from: window,
                relativeTo: rectInContentView,
                preferredEdge: preferredEdge
            )
            return
        }
        let nsImage = NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
        present(
            items: [nsImage],
            from: window,
            relativeTo: rectInContentView,
            preferredEdge: preferredEdge
        )
    }

    /// Shares an existing file (screenshot PNG, video, GIF, …).
    public static func present(
        fileURL: URL,
        from window: NSWindow? = nil,
        relativeTo rectInContentView: NSRect? = nil,
        preferredEdge: NSRectEdge = .minY
    ) {
        present(
            items: [fileURL],
            from: window,
            relativeTo: rectInContentView,
            preferredEdge: preferredEdge
        )
    }

    public static func present(
        items: [Any],
        from window: NSWindow? = nil,
        relativeTo rectInContentView: NSRect? = nil,
        preferredEdge: NSRectEdge = .minY
    ) {
        guard !items.isEmpty else { return }

        let picker = NSSharingServicePicker(items: items)
        let hostWindow = window ?? NSApp.keyWindow ?? NSApp.mainWindow
        guard let view = hostWindow?.contentView else { return }

        let anchor = resolveAnchor(
            rectInContentView: rectInContentView,
            hostWindow: hostWindow,
            contentView: view
        )

        picker.show(relativeTo: anchor, of: view, preferredEdge: preferredEdge)
    }

    private static func resolveAnchor(
        rectInContentView: NSRect?,
        hostWindow: NSWindow?,
        contentView: NSView
    ) -> NSRect {
        if let rectInContentView, rectInContentView.width > 0, rectInContentView.height > 0 {
            return rectInContentView
        }

        if let event = NSApp.currentEvent, event.window === hostWindow {
            let point = contentView.convert(event.locationInWindow, from: nil)
            return NSRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16)
        }

        return NSRect(
            x: contentView.bounds.midX - 1,
            y: contentView.bounds.midY - 1,
            width: 2,
            height: 2
        )
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
