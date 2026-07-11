import AppKit

@MainActor
final class PinnedScreenshotChromeView: NSView {
    let closeButton = NSButton()
    let lockButton = NSButton()
    let zoomBadge = NSTextField(labelWithString: "100%")

    override var isFlipped: Bool { true }

    var isLocked = false {
        didSet {
            let imageName = isLocked ? "lock.fill" : "lock.open.fill"
            lockButton.image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
        closeButton.contentTintColor = .black
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        closeButton.frame = NSRect(x: 12, y: 12, width: 32, height: 32)
        closeButton.wantsLayer = true
        closeButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        closeButton.layer?.cornerRadius = 16
        addSubview(closeButton)

        lockButton.bezelStyle = .circular
        lockButton.isBordered = false
        lockButton.contentTintColor = .black
        lockButton.image = NSImage(systemSymbolName: "lock.open.fill", accessibilityDescription: nil)
        lockButton.frame = NSRect(x: frameRect.width - 44, y: 12, width: 32, height: 32)
        lockButton.autoresizingMask = [.minXMargin]
        lockButton.wantsLayer = true
        lockButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        lockButton.layer?.cornerRadius = 16
        addSubview(lockButton)

        zoomBadge.alignment = .center
        zoomBadge.font = .systemFont(ofSize: 14, weight: .bold)
        zoomBadge.textColor = .white
        zoomBadge.backgroundColor = NSColor.black.withAlphaComponent(0.55)
        zoomBadge.drawsBackground = true
        zoomBadge.isBordered = false
        zoomBadge.isBezeled = false
        zoomBadge.isEditable = false
        zoomBadge.wantsLayer = true
        zoomBadge.layer?.cornerRadius = 14
        zoomBadge.layer?.masksToBounds = true
        zoomBadge.frame = NSRect(x: frameRect.midX - 34, y: 14, width: 68, height: 28)
        zoomBadge.autoresizingMask = [.minXMargin, .maxXMargin]
        zoomBadge.alphaValue = 0
        addSubview(zoomBadge)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showZoom(_ scalePercent: Int) {
        zoomBadge.stringValue = "\(scalePercent)%"
        zoomBadge.alphaValue = 1

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            zoomBadge.animator().alphaValue = 1
        }

        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideZoomBadge), object: nil)
        perform(#selector(hideZoomBadge), with: nil, afterDelay: 0.9)
    }

    @objc private func hideZoomBadge() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            zoomBadge.animator().alphaValue = 0
        }
    }
}
