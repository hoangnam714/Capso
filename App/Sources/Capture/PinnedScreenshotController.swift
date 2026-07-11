// App/Sources/Capture/PinnedScreenshotController.swift
import AppKit
import CaptureKit

@MainActor
final class PinnedScreenshotController {
    let id = UUID()
    private let image: CGImage
    private let onCopy: () -> Void
    private let onSave: () -> Void
    private let onDidClose: (UUID) -> Void

    private let contentWindow: PinnedScreenshotWindow
    private let chromeWindow: PinnedScreenshotChromeWindow

    private var isLocked = false
    private var isClosing = false
    private var currentScale: CGFloat = 1.0

    init(
        image: CGImage,
        anchorRect: CGRect?,
        onCopy: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onDidClose: @escaping (UUID) -> Void
    ) {
        self.image = image
        self.onCopy = onCopy
        self.onSave = onSave
        self.onDidClose = onDidClose

        contentWindow = PinnedScreenshotWindow(
            image: image,
            anchorRect: anchorRect,
            onCopy: onCopy,
            onSave: onSave,
            onDidClose: { _ in }
        )
        chromeWindow = PinnedScreenshotChromeWindow(frame: contentWindow.frame)

        contentWindow.onDidClose = { [weak self] _ in
            self?.closeAll(fromContentWindow: true)
        }

        contentWindow.onFrameChanged = { [weak self] frame in
            self?.chromeWindow.sync(to: frame)
        }
        contentWindow.onScaleChanged = { [weak self] percent in
            self?.chromeWindow.chromeView.showZoom(percent)
        }

        chromeWindow.chromeView.closeButton.target = self
        chromeWindow.chromeView.closeButton.action = #selector(closeOverlay)
        chromeWindow.chromeView.lockButton.target = self
        chromeWindow.chromeView.lockButton.action = #selector(toggleLock)
    }

    func show() {
        contentWindow.show()
        contentWindow.addChildWindow(chromeWindow, ordered: .above)
        chromeWindow.orderFront(nil)
    }

    func updateZoomHUD(scalePercent: Int) {
        chromeWindow.chromeView.showZoom(scalePercent)
    }

    @objc private func closeOverlay() {
        closeAll()
    }

    private func closeAll(fromContentWindow: Bool = false) {
        guard !isClosing else { return }
        isClosing = true

        contentWindow.removeChildWindow(chromeWindow)
        chromeWindow.close()

        if !fromContentWindow {
            contentWindow.close()
        }

        onDidClose(id)
    }

    @objc private func toggleLock() {
        isLocked.toggle()
        chromeWindow.chromeView.isLocked = isLocked
        contentWindow.alphaValue = isLocked ? 0.72 : 1.0
        contentWindow.ignoresMouseEvents = isLocked
        contentWindow.contentView.map { ($0 as? PinnedScreenshotContentView)?.isResizable = !isLocked }
    }

}
