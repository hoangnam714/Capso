// App/Sources/Capture/ScrollCaptureHUD.swift
import AppKit
import SwiftUI
import CaptureKit

/// Persistent overlay shown during scrolling capture.
/// Shows: selection border, live preview, Cancel/Done controls.
@MainActor
final class ScrollCaptureOverlay {
    private var borderWindow: NSPanel?
    private var controlsWindow: NSPanel?
    private var previewWindow: NSPanel?
    private let viewModel = ScrollCaptureViewModel()
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var keyEventTap: CFMachPort?
    private var keyEventTapRunLoopSource: CFRunLoopSource?

    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?

    func show(selectionRect: CGRect, screen: NSScreen) {
        let screenOrigin = screen.frame.origin
        let screenRect = NSRect(
            x: screenOrigin.x + selectionRect.origin.x,
            y: screenOrigin.y + selectionRect.origin.y,
            width: selectionRect.width,
            height: selectionRect.height
        )

        showBorder(screenRect: screenRect)
        showControls(screenRect: screenRect, screen: screen)
        showPreview(screenRect: screenRect, screen: screen)
        installKeyHandlers()
    }

    func setCapturing(_ capturing: Bool) {
        viewModel.isCapturing = capturing
    }

    func updatePreview(image: CGImage, height: Int, maxHeight: Int, frameCount: Int) {
        viewModel.previewImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        viewModel.currentHeight = height
        viewModel.maxHeight = maxHeight
        viewModel.frameCount = frameCount
    }

    func close() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let source = keyEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            keyEventTapRunLoopSource = nil
        }
        if let tap = keyEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            keyEventTap = nil
        }
        borderWindow?.orderOut(nil)
        borderWindow = nil
        controlsWindow?.orderOut(nil)
        controlsWindow = nil
        previewWindow?.orderOut(nil)
        previewWindow = nil
    }

    /// CGWindowIDs of all overlay panels, for excluding from capture.
    var windowIDs: [CGWindowID] {
        var ids: [CGWindowID] = []
        if let w = borderWindow { ids.append(CGWindowID(w.windowNumber)) }
        if let w = controlsWindow { ids.append(CGWindowID(w.windowNumber)) }
        if let w = previewWindow { ids.append(CGWindowID(w.windowNumber)) }
        return ids
    }

    private func installKeyHandlers() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            switch event.keyCode {
            case 53: // ESC — always cancel / exit
                self.onCancel?()
                return nil
            case 36, 76: // Return, keypad Enter
                self.handlePrimaryKey()
                return nil
            default:
                return event
            }
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            switch event.keyCode {
            case 53:
                Task { @MainActor in self.onCancel?() }
            case 36, 76:
                Task { @MainActor in self.handlePrimaryKey() }
            default:
                break
            }
        }

        installKeyEventTap()
    }

    private func installKeyEventTap() {
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon in
                guard type == .keyDown,
                      let refcon else {
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                guard keyCode == 53 || keyCode == 36 || keyCode == 76 else {
                    return Unmanaged.passUnretained(event)
                }

                let overlay = Unmanaged<ScrollCaptureOverlay>.fromOpaque(refcon).takeUnretainedValue()
                Task { @MainActor in
                    if keyCode == 53 {
                        overlay.onCancel?()
                    } else {
                        overlay.handlePrimaryKey()
                    }
                }
                return nil
            },
            userInfo: refcon
        ) else {
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        keyEventTap = tap
        keyEventTapRunLoopSource = source
    }

    /// Enter: Done when capturing.
    private func handlePrimaryKey() {
        if viewModel.isCapturing {
            onDone?()
        }
    }

    // MARK: - Border

    private func showBorder(screenRect: NSRect) {
        let inset: CGFloat = 3
        let borderRect = screenRect.insetBy(dx: -inset, dy: -inset)

        let panel = NSPanel(
            contentRect: borderRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.sharingType = .none

        let borderView = ScrollCaptureBorderView(frame: NSRect(origin: .zero, size: borderRect.size))
        panel.contentView = borderView

        self.borderWindow = panel
        panel.orderFrontRegardless()
    }

    // MARK: - Controls

    private func showControls(screenRect: NSRect, screen: NSScreen) {
        let controlsWidth: CGFloat = 380
        let controlsHeight: CGFloat = 78
        let gap: CGFloat = 10

        // Try below the selection first
        var controlsY = screenRect.origin.y - controlsHeight - gap

        // If not enough space below (off-screen), show above the selection
        if controlsY < screen.frame.origin.y {
            controlsY = screenRect.maxY + gap
        }

        // If still off-screen (selection fills entire height), show inside at the bottom
        if controlsY + controlsHeight > screen.frame.maxY {
            controlsY = screenRect.origin.y + 8
        }

        let controlsRect = NSRect(
            x: screenRect.midX - controlsWidth / 2,
            y: controlsY,
            width: controlsWidth,
            height: controlsHeight
        )

        let panel = NSPanel(
            contentRect: controlsRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.sharingType = .none

        let hostingView = NSHostingView(rootView: ScrollCaptureControlsView(
            viewModel: viewModel,
            onCancel: { [weak self] in self?.onCancel?() },
            onDone: { [weak self] in self?.onDone?() }
        ))
        panel.contentView = hostingView

        self.controlsWindow = panel
        panel.orderFrontRegardless()
    }

    // MARK: - Preview

    private func showPreview(screenRect: NSRect, screen: NSScreen) {
        let previewWidth: CGFloat = 180
        let previewHeight: CGFloat = min(screenRect.height, 400)
        let gap: CGFloat = 12

        guard let previewRect = previewPlacement(
            screenRect: screenRect,
            screen: screen,
            width: previewWidth,
            height: previewHeight,
            gap: gap
        ) else {
            return
        }

        let panel = NSPanel(
            contentRect: previewRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.sharingType = .none

        let hostingView = NSHostingView(rootView: ScrollCapturePreviewView(viewModel: viewModel))
        panel.contentView = hostingView

        self.previewWindow = panel
        panel.orderFrontRegardless()
    }

    private func previewPlacement(
        screenRect: NSRect,
        screen: NSScreen,
        width: CGFloat,
        height: CGFloat,
        gap: CGFloat
    ) -> NSRect? {
        let screenFrame = screen.frame
        let clampedHeight = min(height, screen.visibleFrame.height - gap * 2)

        func clampedY(for midY: CGFloat) -> CGFloat {
            let y = midY - clampedHeight / 2
            return min(
                max(y, screen.visibleFrame.minY + gap),
                screen.visibleFrame.maxY - clampedHeight - gap
            )
        }

        // Left of selection
        let leftX = screenRect.origin.x - width - gap
        if leftX >= screenFrame.minX {
            return NSRect(x: leftX, y: clampedY(for: screenRect.midY), width: width, height: clampedHeight)
        }

        // Right of selection
        let rightX = screenRect.maxX + gap
        if rightX + width <= screenFrame.maxX {
            return NSRect(x: rightX, y: clampedY(for: screenRect.midY), width: width, height: clampedHeight)
        }

        // Above selection
        let aboveY = screenRect.maxY + gap
        if aboveY + clampedHeight <= screen.visibleFrame.maxY {
            let x = min(
                max(screenRect.midX - width / 2, screen.visibleFrame.minX + gap),
                screen.visibleFrame.maxX - width - gap
            )
            return NSRect(x: x, y: aboveY, width: width, height: clampedHeight)
        }

        // Below selection
        let belowY = screenRect.origin.y - clampedHeight - gap
        if belowY >= screen.visibleFrame.minY {
            let x = min(
                max(screenRect.midX - width / 2, screen.visibleFrame.minX + gap),
                screen.visibleFrame.maxX - width - gap
            )
            return NSRect(x: x, y: belowY, width: width, height: clampedHeight)
        }

        return nil
    }
}

// MARK: - Border View

final class ScrollCaptureBorderView: NSView {
    private var dashPhase: CGFloat = 0
    private nonisolated(unsafe) var animTimer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        animTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.dashPhase += 2
                self?.needsDisplay = true
            }
        }
    }

    required init?(coder: NSCoder) { nil }

    deinit { animTimer?.invalidate() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds.insetBy(dx: 3, dy: 3)
        ctx.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(2.5)
        ctx.setLineDash(phase: dashPhase, lengths: [6, 4])
        ctx.stroke(rect)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class ScrollCaptureViewModel {
    var previewImage: NSImage?
    var currentHeight: Int = 0
    var maxHeight: Int = 30_000
    var frameCount: Int = 0
    var isCapturing: Bool = false

    var progressFraction: Double {
        guard maxHeight > 0 else { return 0 }
        return min(1.0, Double(currentHeight) / Double(maxHeight))
    }

    var statusText: String {
        if frameCount <= 1 {
            return String(localized: "Scroll down slowly · Enter or Done when finished · Esc to cancel")
        }
        return String(localized: "\(currentHeight) px · \(frameCount) frames")
    }
}

// MARK: - Controls View

struct ScrollCaptureControlsView: View {
    let viewModel: ScrollCaptureViewModel
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                controlButton(
                    icon: "xmark",
                    label: String(localized: "Cancel"),
                    shortcut: "Esc",
                    color: .white.opacity(0.18),
                    action: onCancel
                )

                controlButton(
                    icon: "checkmark",
                    label: String(localized: "Done"),
                    shortcut: "⏎",
                    color: Color.accentColor,
                    action: onDone
                )
            }

            if viewModel.isCapturing {
                ProgressView(value: viewModel.progressFraction)
                    .tint(.accentColor)
                    .frame(maxWidth: .infinity)
            }

            Text(viewModel.statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .environment(\.colorScheme, .dark)
    }

    private func controlButton(
        icon: String,
        label: String,
        shortcut: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize()
                Text(shortcut)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("\(label) (\(shortcut))")
    }
}

// MARK: - Preview View

struct ScrollCapturePreviewView: View {
    let viewModel: ScrollCaptureViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let image = viewModel.previewImage {
                GeometryReader { geo in
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width)
                        .frame(maxHeight: geo.size.height, alignment: .top)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                    Text(String(localized: "Preview appears as you scroll"))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack {
                Text(viewModel.statusText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.bar)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .environment(\.colorScheme, .dark)
    }
}
