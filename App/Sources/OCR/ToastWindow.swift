// App/Sources/OCR/ToastWindow.swift
import AppKit
import QuartzCore
import SharedKit

/// A reusable Liquid Glass toast notification that slides up from bottom-center.
@MainActor
final class ToastWindow: NSPanel {
    private var dismissTimer: Timer?
    private static var actionToast: ToastWindow?

    enum ActionLocation {
        case preview, history, editor
    }

    static func showAction(
        _ message: String,
        at location: ActionLocation,
        settings: AppSettings,
        success: Bool = true,
        screen: NSScreen? = nil
    ) {
        let enabled: Bool = switch location {
        case .preview: settings.previewActionToastsEnabled
        case .history: settings.historyActionToastsEnabled
        case .editor: settings.editorActionToastsEnabled
        }
        guard enabled else { return }
        actionToast?.dismissTimer?.invalidate()
        actionToast?.orderOut(nil)
        let toast = ToastWindow(
            message: message,
            icon: success ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
            iconColor: success ? .systemGreen : .systemOrange,
            screen: screen
        )
        actionToast = toast
        toast.show()
    }

    init(message: String, icon: String = "checkmark.circle.fill", iconColor: NSColor = .systemGreen, screen: NSScreen? = nil) {
        let horizontalPadding: CGFloat = 12
        let verticalPadding: CGFloat = 8
        let iconSize: CGFloat = 14
        let iconSpacing: CGFloat = 6
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Measure the actual text control, including its insets, rather than
        // reserving a minimum width that leaves short messages mostly empty.
        let textSize = label.fittingSize
        let windowWidth = min(ceil(textSize.width) + horizontalPadding * 2 + iconSize + iconSpacing, 500)
        let windowHeight = ceil(max(textSize.height, iconSize)) + verticalPadding * 2

        let screenFrame = (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let x = screenFrame.midX - windowWidth / 2
        let y = screenFrame.minY + 60

        super.init(
            contentRect: NSRect(x: x, y: y, width: windowWidth, height: windowHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.ignoresMouseEvents = true
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = false
        self.animationBehavior = .utilityWindow

        // This panel owns its size. Keep its content entirely in AppKit so a
        // SwiftUI hosting view cannot resize it during the display constraint pass.
        let background = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = windowHeight / 2
        background.layer?.masksToBounds = true

        let image = NSImageView()
        image.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: iconSize, weight: .medium))
        image.contentTintColor = iconColor
        image.translatesAutoresizingMaskIntoConstraints = false

        background.addSubview(image)
        background.addSubview(label)
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: horizontalPadding),
            image.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: iconSize),
            image.heightAnchor.constraint(equalToConstant: iconSize),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: iconSpacing),
            label.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -horizontalPadding),
            label.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])
        contentView = background
    }

    func show(autoDismissAfter: TimeInterval = 1.5) {
        let finalFrame = frame
        var startFrame = finalFrame
        startFrame.origin.y -= 20
        setFrame(startFrame, display: false)
        alphaValue = 0

        dismissTimer?.invalidate()
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(finalFrame, display: true)
            self.animator().alphaValue = 1
        }

        dismissTimer = Timer.scheduledTimer(withTimeInterval: autoDismissAfter, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }

    private func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            self.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                self.orderOut(nil)
                if Self.actionToast === self {
                    Self.actionToast = nil
                }
            }
        })
    }
}
