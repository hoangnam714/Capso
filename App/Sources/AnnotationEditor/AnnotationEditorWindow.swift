// App/Sources/AnnotationEditor/AnnotationEditorWindow.swift
import AppKit
import SwiftUI
import AnnotationKit

@MainActor
final class AnnotationEditorWindow: NSPanel {
    private let document: AnnotationDocument
    private let interactionState = AnnotationEditorInteractionState()
    private let targetFrame: NSRect

    /// Multiplies the current zoom (pinch / ⌘-scroll). Set by AnnotationEditorView.
    var onZoomByFactor: ((CGFloat) -> Void)?
    /// Fired after entering/exiting editor fullscreen so the canvas can refit.
    var onFullscreenChanged: ((Bool) -> Void)?
    /// Share-button frame in `contentView` coords, captured before async render.
    var pendingShareAnchorInContentView: NSRect?

    private(set) var isEditorFullscreen = false
    private var frameBeforeFullscreen: NSRect?

    func consumeShareAnchor() -> NSRect? {
        let rect = pendingShareAnchorInContentView
        pendingShareAnchorInContentView = nil
        return rect
    }

    init(
        image: CGImage,
        sidecar: AnnotationSidecar? = nil,
        anchorScreen: NSScreen? = nil,
        onSave: @escaping (CGImage, CGImage, AnnotationDocument) -> Void,
        onCopy: @escaping (CGImage, CGImage, AnnotationDocument) -> Void,
        onShare: @escaping (CGImage) -> Void,
        onPin: @escaping (CGImage, CGRect?) -> Void,
        onClose: @escaping () -> Void
    ) {
        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)
        let document = AnnotationDocument(imageSize: CGSize(width: imgW, height: imgH))
        if let sidecar {
            document.loadSidecar(sidecar)
        }
        self.document = document

        // Prefer the screen where the capture originated (the one the user was
        // focused on). Falling back to NSScreen.main unconditionally would
        // always open the editor on the primary display, even when the capture
        // came from a secondary one.
        let mouseScreen = NSScreen.screens.first {
            $0.frame.contains(NSEvent.mouseLocation)
        }
        let screen = anchorScreen ?? mouseScreen ?? NSScreen.main ?? NSScreen.screens.first!
        let maxW = screen.visibleFrame.width * 0.8
        let maxH = screen.visibleFrame.height * 0.8
        let chromeH: CGFloat = 110
        // Wide enough for the compact toolbar on a 13" MacBook (~1280pt wide).
        // Narrower windows still work via the minimal toolbar density, but we
        // never open below this so buttons don't overlap on first launch.
        let minimumWindowWidth: CGFloat = 680
        let minimumWindowHeight: CGFloat = 360

        let scale = min(1.0, min(maxW / max(imgW, 1), (maxH - chromeH) / max(imgH, 1)))
        let preferredW = max(imgW * scale, minimumWindowWidth)
        let winW = min(preferredW, maxW)
        let winH = max(imgH * scale + chromeH, minimumWindowHeight)

        // Center inside the target screen's visibleFrame. `visibleFrame` is
        // already in absolute desktop coordinates, so this puts the window on
        // the correct display even when that display isn't the primary one.
        let x = screen.visibleFrame.midX - winW / 2
        let y = screen.visibleFrame.midY - winH / 2
        let targetFrame = NSRect(x: x, y: y, width: winW, height: winH)
        self.targetFrame = targetFrame

        super.init(
            contentRect: targetFrame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        self.title = "Annotate"
        self.isReleasedWhenClosed = false
        self.level = .floating
        // Keep `.fullScreenAuxiliary` so the panel can appear over other apps'
        // fullscreen Spaces. Editor "fullscreen" is a custom fill-screen mode
        // (see `toggleEditorFullscreen`) because NSPanel + floating level does
        // not participate in macOS Spaces fullscreen cleanly.
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Keep the panel visible when the app loses focus — without this,
        // clicking another app's window hides the annotation editor.
        self.hidesOnDeactivate = false
        // Ensure tooltip tracking and key-window behaviour work correctly.
        self.becomesKeyOnlyIfNeeded = false
        self.acceptsMouseMovedEvents = true
        // AppKit re-applies window restoration + may snap `.titled` panels
        // back to main display on multi-monitor setups, ignoring the
        // contentRect passed to init. Disable restoration and explicitly
        // re-apply the target frame so we actually land on the right screen.
        self.isRestorable = false
        self.minSize = NSSize(width: minimumWindowWidth, height: minimumWindowHeight)
        self.setFrame(targetFrame, display: false)

        let view = AnnotationEditorView(
            sourceImage: image,
            document: document,
            interactionState: interactionState,
            onSave: { [weak self] rendered, source, document in
                onSave(rendered, source, document)
                self?.close()
            },
            onCopy: { [weak self] rendered, source, document in
                onCopy(rendered, source, document)
                self?.close()
            },
            onShare: { rendered in
                // Keep the editor open while the share sheet is presented.
                onShare(rendered)
            },
            onPin: { [weak self] rendered in
                onPin(rendered, self?.frame)
                self?.close()
            },
            onCancel: { [weak self] in
                onClose()
                self?.close()
            }
        )

        let hostingView = NSHostingView(rootView: view)
        hostingView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hostingView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        self.contentView = hostingView
        // Hosting-view layout can nudge the frame after contentView is set —
        // re-apply centering once more so the panel stays on the target screen.
        self.setFrame(targetFrame, display: false)
    }

    func show() {
        // Force the exact centered frame before ordering on screen.
        setFrame(targetFrame, display: false)
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
        // Apply frame again immediately after ordering — AppKit constraints
        // sometimes shift the panel a few points during makeKey / activate.
        setFrame(targetFrame, display: false)
        NSApp.activate(ignoringOtherApps: true)
        // Final centering pass after all AppKit layout settles.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setFrame(self.targetFrame, display: false)
        }
    }

    /// Expand the editor to fill its current screen, or restore the prior frame.
    func toggleEditorFullscreen() {
        if isEditorFullscreen {
            let restore = frameBeforeFullscreen ?? targetFrame
            frameBeforeFullscreen = nil
            isEditorFullscreen = false
            setFrame(restore, display: true, animate: true)
            // Post-animation cleanup.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.onFullscreenChanged?(false)
            }
        } else {
            frameBeforeFullscreen = frame
            let screen = self.screen
                ?? NSScreen.screens.first { $0.frame.intersects(frame) }
                ?? NSScreen.main
                ?? NSScreen.screens.first!
            // visibleFrame excludes menu bar & Dock. Inset by 1pt on all edges
            // so the window chrome stays visible and doesn't clip into notch area.
            let target = screen.visibleFrame.insetBy(dx: 1, dy: 1)
            isEditorFullscreen = true
            setFrame(target, display: true, animate: true)
            // Snap precisely after animation, then notify.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.isEditorFullscreen else { return }
                self.setFrame(target, display: false)
                self.onFullscreenChanged?(true)
            }
        }
    }

    /// Keep fullscreen frames pixel-exact; AppKit otherwise shrinks panels
    /// slightly so they don't touch screen edges.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        if isEditorFullscreen {
            return frameRect
        }
        return super.constrainFrameRect(frameRect, to: screen)
    }

    override func cancelOperation(_ sender: Any?) {
        if isEditorFullscreen {
            toggleEditorFullscreen()
            return
        }
        super.cancelOperation(sender)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if interactionState.isEditingText {
            return super.performKeyEquivalent(with: event)
        }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == [.control, .command],
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            toggleEditorFullscreen()
            return true
        }

        if let canvas = contentView?.firstSubview(of: AnnotationCanvasNSView.self),
           canvas.handleClipboardShortcut(event) {
            return true
        }

        if interactionState.shouldSuppressCopyShortcut(for: event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if !interactionState.isEditingText, handleZoomGesture(event) {
            return
        }

        // Swallow ⌘C only while interacting with the canvas so the toolbar's
        // image-copy shortcut does not fire mid-drag. Text editing and object
        // clipboard shortcuts are handled in performKeyEquivalent / keyDown.
        if event.type == .keyDown,
           !interactionState.isEditingText,
           interactionState.shouldSuppressCopyShortcut(for: event),
           contentView?.firstSubview(of: AnnotationCanvasNSView.self)?.handleClipboardShortcut(event) != true {
            return
        }
        super.sendEvent(event)
    }

    /// Pinch-to-zoom and ⌘-scroll zoom. Returns true when the event was consumed.
    private func handleZoomGesture(_ event: NSEvent) -> Bool {
        switch event.type {
        case .magnify:
            let factor = 1 + event.magnification
            guard abs(factor - 1) > 0.0001 else { return false }
            onZoomByFactor?(factor)
            return true
        case .scrollWheel:
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods.contains(.command) else { return false }
            let factor: CGFloat
            if event.hasPreciseScrollingDeltas {
                guard abs(event.scrollingDeltaY) > 0.01 else { return false }
                factor = 1 + event.scrollingDeltaY * 0.008
            } else {
                guard event.scrollingDeltaY != 0 else { return false }
                factor = event.scrollingDeltaY > 0 ? 1.1 : (1 / 1.1)
            }
            onZoomByFactor?(factor)
            return true
        default:
            return false
        }
    }
}

private extension NSView {
    func firstSubview<T: NSView>(of type: T.Type) -> T? {
        if let view = self as? T {
            return view
        }
        for subview in subviews {
            if let match = subview.firstSubview(of: type) {
                return match
            }
        }
        return nil
    }
}
