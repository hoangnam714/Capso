// App/Sources/AnnotationEditor/AnnotationEditorWindow.swift
import AppKit
import SwiftUI
import AnnotationKit

@MainActor
final class AnnotationEditorWindow: NSPanel {
    private let document: AnnotationDocument
    private let interactionState = AnnotationEditorInteractionState()

    init(
        image: CGImage,
        sidecar: AnnotationSidecar? = nil,
        anchorScreen: NSScreen? = nil,
        onSave: @escaping (CGImage, CGImage, AnnotationDocument) -> Void,
        onCopy: @escaping (CGImage, CGImage, AnnotationDocument) -> Void,
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
        let screen = anchorScreen ?? NSScreen.main ?? NSScreen.screens.first!
        let maxW = screen.visibleFrame.width * 0.8
        let maxH = screen.visibleFrame.height * 0.8
        let chromeH: CGFloat = 110

        let scale = min(1.0, min(maxW / imgW, (maxH - chromeH) / imgH))
        let winW = imgW * scale
        let winH = imgH * scale + chromeH

        // Center inside the target screen's visibleFrame. `visibleFrame` is
        // already in absolute desktop coordinates, so this puts the window on
        // the correct display even when that display isn't the primary one.
        let x = screen.visibleFrame.midX - winW / 2
        let y = screen.visibleFrame.midY - winH / 2

        let targetFrame = NSRect(x: x, y: y, width: winW, height: winH)

        super.init(
            contentRect: targetFrame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        self.title = "Annotate"
        self.isReleasedWhenClosed = false
        self.level = .floating
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
            onPin: { [weak self] rendered in
                onPin(rendered, self?.frame)
                self?.close()
            },
            onCancel: { [weak self] in
                onClose()
                self?.close()
            }
        )

        self.contentView = NSHostingView(rootView: view)
    }

    func show() {
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if interactionState.isEditingText {
            return super.performKeyEquivalent(with: event)
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
