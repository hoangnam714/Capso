// App/Sources/QuickAccess/QuickAccessWindow.swift
import AppKit
import SwiftUI
import CaptureKit
import SharedKit
import ShareKit

@MainActor
final class QuickAccessWindow: NSPanel {
    private static let cornerRadius: CGFloat = 14

    override var canBecomeKey: Bool { true }

    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onShare: (() -> Void)?
    var onDelete: (() -> Void)?
    var onAnnotate: (() -> Void)?
    var onOCR: (() -> Void)?
    var onTranslate: (() -> Void)?
    var onPin: (() -> Void)?
    var onPreview: (() -> Void)?
    var onClose: (() -> Void)?
    /// Called with the public URL string when a cloud upload succeeds.
    var onUploadSucceeded: ((String) -> Void)?

    private var autoDismissTimer: Timer?
    private let settings: AppSettings
    /// The screen this preview is anchored to (where the capture originated).
    let targetScreen: NSScreen
    /// True while the pointer is over the panel — blocks auto-dismiss.
    private var isPointerInside = false

    init(result: CaptureResult, settings: AppSettings, screen: NSScreen?, shareCoordinator: ShareCoordinator?) {
        self.settings = settings
        self.targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first!

        let windowWidth: CGFloat = 288
        let windowHeight: CGFloat = 210

        let screenFrame = targetScreen.visibleFrame
        let x: CGFloat = switch settings.quickAccessPosition {
        case .bottomLeft: screenFrame.minX + 16
        case .bottomRight: screenFrame.maxX - windowWidth - 16
        }
        let y = screenFrame.minY + 16

        let contentRect = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)

        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .transient]
        self.isMovableByWindowBackground = true
        self.animationBehavior = .utilityWindow
        self.hidesOnDeactivate = false

        let nsImage = NSImage(cgImage: result.image, size: NSSize(
            width: result.image.width, height: result.image.height
        ))

        let dimensions = "\(result.image.width)×\(result.image.height)"
        let targetDisplay = Self.targetLanguageDisplay(settings: settings)

        let view = QuickAccessView(
            thumbnail: nsImage,
            captureImage: result.image,
            dimensions: dimensions,
            capturedAt: Date(),
            targetLanguageDisplay: targetDisplay,
            shareCoordinator: shareCoordinator,
            onUploadSucceeded: { [weak self] url in self?.onUploadSucceeded?(url) },
            onCopy:      { [weak self] in self?.onCopy?() },
            onSave:      { [weak self] in self?.onSave?() },
            onShare:     { [weak self] in self?.onShare?() },
            onDelete:    { [weak self] in self?.onDelete?() },
            onAnnotate:  { [weak self] in self?.onAnnotate?() },
            onOCR:       { [weak self] in self?.onOCR?() },
            onTranslate: { [weak self] in self?.onTranslate?() },
            onPin:       { [weak self] in self?.onPin?() },
            onPreview:   { [weak self] in self?.onPreview?() },
            onClose:     { [weak self] in self?.onClose?() },
            onHoveringChanged: { [weak self] hovering in
                self?.handlePointerHover(hovering)
            }
        )

        let hostingView = NSHostingView(rootView: view)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.cornerRadius = Self.cornerRadius
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true

        self.contentView = hostingView
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private static func targetLanguageDisplay(settings: AppSettings) -> String? {
        let target = settings.translationTargetLanguage
        return Locale.current.localizedString(forIdentifier: target) ?? target
    }

    func show() {
        let finalFrame = frame
        var startFrame = finalFrame
        startFrame.origin.y -= 20
        setFrame(startFrame, display: false)
        alphaValue = 0

        makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(finalFrame, display: true)
            self.animator().alphaValue = 1
        }

        scheduleAutoDismissIfNeeded()
    }

    /// Cancel the auto-dismiss timer (e.g. while presenting the share sheet).
    func cancelAutoDismiss() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
    }

    /// Temporarily hide this preview during a new capture/recording session
    /// so it isn't frozen into the selection backdrop or recorded video.
    /// Auto-dismiss is paused while hidden and resumes on restore.
    func setTemporarilyHidden(_ hidden: Bool) {
        if hidden {
            cancelAutoDismiss()
            orderOut(nil)
        } else {
            guard !isVisible else { return }
            orderFrontRegardless()
            scheduleAutoDismissIfNeeded()
        }
    }

    private func handlePointerHover(_ hovering: Bool) {
        isPointerInside = hovering
        if hovering {
            cancelAutoDismiss()
        } else {
            scheduleAutoDismissIfNeeded()
        }
    }

    private func scheduleAutoDismissIfNeeded() {
        cancelAutoDismiss()
        guard settings.quickAccessAutoClose, !isPointerInside else { return }
        autoDismissTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(settings.quickAccessAutoCloseInterval),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isPointerInside else { return }
                self.onClose?()
            }
        }
    }

    override func close() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            self.animator().alphaValue = 0
        }, completionHandler: {
            super.close()
        })
    }

    /// Evict this preview off-screen to the left with a slide animation.
    func slideOffLeftAndClose() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        var target = frame
        target.origin.x = -(target.width + 40)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.38
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().setFrame(target, display: true)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // Must fully close (not just orderOut) so hosting views / CGImages release.
            self?.close()
        })
    }

    /// Spacing between stacked preview windows.
    private static let stackSpacing: CGFloat = 12

    /// Animate this window's y-position to occupy a given slot in the preview stack.
    func repositionForStackIndex(_ index: Int, animated: Bool = true) {
        let screenFrame = targetScreen.visibleFrame
        let windowWidth = frame.width
        let windowHeight = frame.height
        let x: CGFloat = switch settings.quickAccessPosition {
        case .bottomLeft: screenFrame.minX + 16
        case .bottomRight: screenFrame.maxX - windowWidth - 16
        }
        let baseY = screenFrame.minY + 16
        let y = baseY + CGFloat(index) * (windowHeight + Self.stackSpacing)
        let newFrame = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().setFrame(newFrame, display: true)
            }
        } else {
            setFrame(newFrame, display: true)
        }
    }
}
