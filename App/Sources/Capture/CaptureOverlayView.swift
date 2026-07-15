// App/Sources/Capture/CaptureOverlayView.swift
import AppKit
import CaptureKit
import SharedKit

// MARK: - Notification extensions

extension Notification.Name {
    static let openPreferencesTab = Notification.Name("openPreferencesTab")
    static let openScreenshotSettings = Notification.Name("openScreenshotSettings")
    static let capturePresetChanged = Notification.Name("capturePresetChanged")
    /// Broadcast while an area drag spans multiple displays so peer overlays
    /// can draw the intersection of the global selection with their screen.
    static let captureCrossScreenSelectionChanged = Notification.Name("captureCrossScreenSelectionChanged")
    /// Posted by PreferencesWindow when the window is already open and the
    /// caller wants the visible Preferences UI to switch to a specific tab.
    /// Only PreferencesView observes this — NOT AppDelegate (which would cause
    /// infinite recursion through show(tab:) → post → observer → show(tab:)).
    static let preferencesSwitchTab = Notification.Name("preferencesSwitchTab")
}

enum CaptureOverlayMode {
    case area
    case windowSelection([WindowInfo])
}

@MainActor
final class CaptureOverlayView: NSView {
    var onSelectionComplete: ((CGRect) -> Void)?
    var onWindowSelected: ((CGWindowID) -> Void)?
    var onCancel: (() -> Void)?
    var onSpaceToggle: (() -> Void)?

    private let settings: AppSettings
    private let safeAreaTopInset: CGFloat
    /// When true, preset features (badge, R-key, right-click menu, ratio lock) are disabled.
    /// Used by OCR and Recording overlays which always use freeform selection.
    private let presetsDisabled: Bool

    private var mode: CaptureOverlayMode = .area
    private var isDragging = false
    /// True when this overlay owns the active cross-screen drag.
    private var isDragSource = false
    /// Global AppKit (bottom-left) drag anchors for cross-display selection.
    private var dragStartGlobal: NSPoint = .zero
    private var dragEndGlobal: NSPoint = .zero
    /// Mirrored global selection from another overlay while it is dragging.
    private var remoteGlobalSelection: CGRect?
    private var currentMouseLocation: NSPoint?
    private var crossScreenDragMonitor: Any?

    /// The currently active capture preset. Starts from settings and can be
    /// changed at runtime via R-key cycling or the right-click context menu.
    private var activePreset: CapturePreset

    /// Object identity of the overlay currently owning a multi-screen drag.
    private static var activeDragSourceID: ObjectIdentifier?

    // Window selection state
    private var hoveredWindowID: CGWindowID?
    private var hoveredWindowFrame: CGRect = .zero
    private var hoveredWindowName: String = ""
    private var availableWindows: [WindowInfo] = []

    private var cursorHidden = false

    /// Pre-captured frozen screenshot. When set, drawn as the background
    /// instead of being transparent, preserving dropdown menus/popups.
    var frozenBackground: CGImage?

    // Overlay appearance
    private let overlayColor = NSColor.black.withAlphaComponent(0.3)
    private let selectionBorderColor = NSColor.white
    // Use a neutral gray glass tint instead of pure white so the selected
    // region still reads against bright backgrounds while remaining soft on
    // dark ones.
    private let selectionFillColor = NSColor(white: 0.78, alpha: 0.20)
    private let selectionInnerStrokeColor = NSColor.white.withAlphaComponent(0.30)
    private let windowHighlightColor = NSColor.systemBlue.withAlphaComponent(0.3)
    private let windowBorderColor = NSColor.systemBlue
    private let dimensionFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    private let dimensionBgColor = NSColor.black.withAlphaComponent(0.7)
    private let dimensionTextColor = NSColor.white

    // MARK: - Context menu

    /// Maps NSMenuItem tag values to presets for the right-click menu.
    private var presetMenuMap: [Int: CapturePreset] = [:]

    nonisolated(unsafe) private var presetObserver: Any?
    nonisolated(unsafe) private var crossScreenSelectionObserver: Any?

    init(
        frame: NSRect,
        settings: AppSettings,
        safeAreaTopInset: CGFloat,
        presetsDisabled: Bool = false
    ) {
        self.settings = settings
        self.safeAreaTopInset = safeAreaTopInset
        // Presets are disabled when explicitly requested (OCR/Recording) or when
        // the user has turned off the feature in Settings.
        self.presetsDisabled = presetsDisabled || !settings.capturePresetsEnabled
        self.activePreset = self.presetsDisabled ? .freeform : settings.capturePreset
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))

        crossScreenSelectionObserver = NotificationCenter.default.addObserver(
            forName: .captureCrossScreenSelectionChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let sourceID = notification.userInfo?["sourceID"] as? ObjectIdentifier
            let hasRect = notification.userInfo?["x"] != nil
            let globalRect: CGRect? = hasRect ? CGRect(
                x: notification.userInfo?["x"] as? CGFloat ?? 0,
                y: notification.userInfo?["y"] as? CGFloat ?? 0,
                width: notification.userInfo?["width"] as? CGFloat ?? 0,
                height: notification.userInfo?["height"] as? CGFloat ?? 0
            ) : nil
            MainActor.assumeIsolated {
                self?.handleRemoteSelectionChange(sourceID: sourceID, globalRect: globalRect)
            }
        }

        // Listen for preset changes from other overlay views (multi-screen sync)
        guard !self.presetsDisabled else { return }
        presetObserver = NotificationCenter.default.addObserver(
            forName: .capturePresetChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let newPreset = self.settings.capturePreset
                guard newPreset != self.activePreset else { return }
                self.activePreset = newPreset

                if self.activePreset.isFixedSize {
                    self.restoreCursorIfNeeded()
                } else if !self.cursorHidden, case .area = self.mode {
                    NSCursor.hide()
                    self.cursorHidden = true
                }

                self.setNeedsDisplay(self.bounds)
                self.display()
            }
        }
    }

    deinit {
        if let presetObserver {
            NotificationCenter.default.removeObserver(presetObserver)
        }
        if let crossScreenSelectionObserver {
            NotificationCenter.default.removeObserver(crossScreenSelectionObserver)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func resetSelection() {
        endCrossScreenDrag(broadcastClear: isDragSource)
        isDragging = false
        isDragSource = false
        dragStartGlobal = .zero
        dragEndGlobal = .zero
        remoteGlobalSelection = nil
        hoveredWindowID = nil
        currentMouseLocation = nil
        needsDisplay = true
    }

    /// Prepare the overlay after the window is on-screen and key so the
    /// cursor/reticle are initialized from the current mouse position instead
    /// of waiting for the first mouse-moved event.
    func prepareForPresentation() {
        syncCurrentMouseLocation()

        // Only hide cursor in area mode — we draw our own crosshair reticle.
        // In window selection mode, keep the normal cursor visible so
        // the user can see where they're pointing.
        if case .area = mode {
            if activePreset.isFixedSize {
                // Fixed-size mode: keep system cursor visible (the rectangle replaces the reticle)
                restoreCursorIfNeeded()
            } else if !cursorHidden {
                NSCursor.hide()
                cursorHidden = true
            }
        } else {
            restoreCursorIfNeeded()
        }

        window?.invalidateCursorRects(for: self)
        needsDisplay = true
        displayIfNeeded()
    }

    /// Restore cursor if hidden — safe to call multiple times
    func restoreCursorIfNeeded() {
        if cursorHidden {
            NSCursor.unhide()
            cursorHidden = false
        }
    }

    private func restoreCursor() {
        restoreCursorIfNeeded()
    }

    /// Seed the reticle from the current pointer location so area capture
    /// starts with the crosshair under the cursor even before the first
    /// mouse-moved event arrives.
    private func syncCurrentMouseLocation() {
        guard let window else {
            currentMouseLocation = nil
            return
        }

        let screenLocation = NSEvent.mouseLocation
        guard let screenFrame = window.screen?.frame,
              screenFrame.contains(screenLocation) else {
            currentMouseLocation = nil
            return
        }

        let windowPoint = window.convertPoint(fromScreen: screenLocation)
        currentMouseLocation = convert(windowPoint, from: nil)
    }

    func setMode(_ mode: CaptureOverlayMode) {
        self.mode = mode
        switch mode {
        case .windowSelection(let windows):
            self.availableWindows = windows
        case .area:
            self.availableWindows = []
        }
        needsDisplay = true
    }

    // MARK: - Preset Cycling

    /// Cycle through visible presets. `forward == true` means +1, `false` means -1.
    private func cyclePreset(forward: Bool) {
        let presets = settings.visiblePresets
        guard !presets.isEmpty else { return }

        let currentIndex = presets.firstIndex(of: activePreset) ?? 0
        let count = presets.count
        let newIndex = forward
            ? (currentIndex + 1) % count
            : (currentIndex - 1 + count) % count

        activePreset = presets[newIndex]
        settings.capturePreset = activePreset

        // Update cursor visibility: fixed-size shows system cursor, others hide it
        if activePreset.isFixedSize {
            restoreCursorIfNeeded()
        } else if !cursorHidden {
            NSCursor.hide()
            cursorHidden = true
        }

        // Force synchronous redraw — needsDisplay alone may not flush
        // at .screenSaver window level without a mouse event to drive the run loop
        setNeedsDisplay(bounds)
        display()

        // Notify other overlay views (multi-screen) to sync their preset
        NotificationCenter.default.post(name: .capturePresetChanged, object: self)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        switch mode {
        case .area:
            drawAreaMode(in: context)
        case .windowSelection:
            drawWindowSelectionMode(in: context)
        }
    }

    private func drawAreaMode(in context: CGContext) {
        if isDragging || remoteGlobalSelection != nil {
            let selectionRect = self.selectionRect

            drawDimmedBackdrop(clearing: selectionRect.isEmpty ? nil : selectionRect, in: context)

            if !selectionRect.isEmpty {
                // Inner edge to help the fill read on bright backgrounds.
                context.saveGState()
                context.setStrokeColor(selectionInnerStrokeColor.cgColor)
                context.setLineWidth(1.0)
                context.stroke(selectionRect.insetBy(dx: 1, dy: 1))
                context.restoreGState()

                // Selection border with shadow glow — visible on any background.
                // Dark shadow makes it clear on light backgrounds,
                // white border makes it clear on dark backgrounds.
                context.saveGState()
                context.setShadow(
                    offset: .zero,
                    blur: 10,
                    color: NSColor.black.withAlphaComponent(0.5).cgColor
                )
                context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
                context.setLineWidth(1.5)
                context.stroke(selectionRect)
                context.restoreGState()

                // Dimension label only on the drag-source display to avoid duplicates.
                if isDragSource {
                    drawDimensionLabel(for: globalSelectionRect, localVisibleRect: selectionRect, in: context)
                }
            }

            if isDragSource, let currentMouseLocation, bounds.contains(currentMouseLocation) {
                drawReticle(at: currentMouseLocation, in: context)
            }
        } else {
            // Before dragging: either fixed-size rectangle preview or crosshair

            if let fixedSize = activePreset.fixedPixelSize {
                // Fixed-size mode: draw a centered rectangle at cursor position
                if let loc = currentMouseLocation {
                    let fixedRect = CGRect(
                        x: loc.x - CGFloat(fixedSize.width) / 2,
                        y: loc.y - CGFloat(fixedSize.height) / 2,
                        width: CGFloat(fixedSize.width),
                        height: CGFloat(fixedSize.height)
                    )

                    drawDimmedBackdrop(clearing: fixedRect, in: context)

                    context.saveGState()
                    context.setStrokeColor(selectionInnerStrokeColor.cgColor)
                    context.setLineWidth(1.0)
                    context.stroke(fixedRect.insetBy(dx: 1, dy: 1))
                    context.restoreGState()

                    context.saveGState()
                    context.setShadow(
                        offset: .zero,
                        blur: 10,
                        color: NSColor.black.withAlphaComponent(0.5).cgColor
                    )
                    context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
                    context.setLineWidth(1.5)
                    context.stroke(fixedRect)
                    context.restoreGState()

                    drawDimensionLabel(for: fixedRect, localVisibleRect: fixedRect, in: context)
                }
                // Still draw badge even without a mouse location
                drawPresetBadge(in: context)
            } else {
                drawDimmedBackdrop(clearing: nil, in: context)
                // Freeform or aspect-ratio mode: standard crosshair
                if let currentMouseLocation {
                    drawReticle(at: currentMouseLocation, in: context)
                    drawCoordinateLabel(at: currentMouseLocation, in: context)
                }
                drawPresetBadge(in: context)
            }
        }
    }

    private func drawDimmedBackdrop(clearing clearRect: CGRect?, in context: CGContext) {
        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.38).cgColor)
        context.fill(bounds)
        if let clearRect {
            context.setBlendMode(.clear)
            context.fill(clearRect)
        }
        context.restoreGState()
    }

    // MARK: - Preset Badge

    /// Draw a centered badge at the top of the screen showing the active
    /// preset and a hint to press R to change it.
    private func drawPresetBadge(in context: CGContext) {
        guard !presetsDisabled else { return }

        let presetName = activePreset.displayName
        let hintText = "   R to change"
        let fullText = "\(presetName)\(hintText)"

        let presetFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let hintFont = NSFont.systemFont(ofSize: 12, weight: .regular)

        let presetAttrs: [NSAttributedString.Key: Any] = [
            .font: presetFont,
            .foregroundColor: NSColor.white
        ]
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: hintFont,
            .foregroundColor: NSColor.white.withAlphaComponent(0.6)
        ]

        let presetStr = NSAttributedString(string: presetName, attributes: presetAttrs)
        let hintStr = NSAttributedString(string: hintText, attributes: hintAttrs)
        let combined = NSMutableAttributedString(attributedString: presetStr)
        combined.append(hintStr)

        let textSize = combined.size()
        let hPadding: CGFloat = 14
        let vPadding: CGFloat = 7
        let badgeWidth = textSize.width + hPadding * 2
        let badgeHeight = textSize.height + vPadding * 2

        let badgeX = (bounds.width - badgeWidth) / 2
        let badgeY = CaptureDisplayGeometry.presetBadgeY(
            viewHeight: bounds.height,
            badgeHeight: badgeHeight,
            safeAreaTopInset: safeAreaTopInset
        )

        let bgRect = CGRect(x: badgeX, y: badgeY, width: badgeWidth, height: badgeHeight)
        let pillRadius = badgeHeight / 2

        // Dark pill background
        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        let pillPath = CGPath(roundedRect: bgRect, cornerWidth: pillRadius, cornerHeight: pillRadius, transform: nil)
        context.addPath(pillPath)
        context.fillPath()
        context.restoreGState()

        // Draw text
        let textX = badgeX + hPadding
        let textY = badgeY + (badgeHeight - textSize.height) / 2
        combined.draw(at: NSPoint(x: textX, y: textY))
    }

    private func drawWindowSelectionMode(in context: CGContext) {
        // Fill entire screen with dim overlay
        context.setFillColor(overlayColor.cgColor)
        context.fill(bounds)

        // If a window is hovered, clear it and highlight with rounded corners
        if hoveredWindowID != nil {
            let viewRect = screenRectToViewRect(hoveredWindowFrame)
            let cornerRadius: CGFloat = 10 // macOS window corner radius

            let roundedPath = CGPath(roundedRect: viewRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

            // Clear the window area (rounded)
            context.setBlendMode(.clear)
            context.addPath(roundedPath)
            context.fillPath()
            context.setBlendMode(.normal)

            // Highlight border (rounded)
            context.setStrokeColor(windowBorderColor.cgColor)
            context.setLineWidth(3.0)
            context.addPath(roundedPath)
            context.strokePath()

            // Subtle fill (rounded)
            context.setFillColor(windowHighlightColor.cgColor)
            context.addPath(roundedPath)
            context.fillPath()

            // Window name label
            drawWindowLabel(name: hoveredWindowName, for: viewRect, in: context)
        }
    }

    private func drawWindowLabel(name: String, for rect: CGRect, in context: CGContext) {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: dimensionTextColor
        ]
        let size = (name as NSString).size(withAttributes: attributes)
        let padding: CGFloat = 8
        let labelWidth = size.width + padding * 2
        let labelHeight = size.height + padding

        let visibleRect = visibleScreenRectInViewCoordinates()
        let minLabelX = visibleRect.minX + 8
        let maxLabelX = max(minLabelX, visibleRect.maxX - labelWidth - 8)
        let labelX = min(max(rect.midX - labelWidth / 2, minLabelX), maxLabelX)

        let minLabelY = visibleRect.minY + 8
        let maxLabelY = max(minLabelY, visibleRect.maxY - labelHeight - 8)
        let preferredAboveY = rect.maxY + 8
        let preferredBelowY = rect.minY - labelHeight - 8
        let labelY: CGFloat
        if preferredAboveY <= maxLabelY {
            labelY = preferredAboveY
        } else if preferredBelowY >= minLabelY {
            labelY = preferredBelowY
        } else {
            labelY = min(max(preferredAboveY, minLabelY), maxLabelY)
        }

        let bgRect = CGRect(x: labelX, y: labelY, width: labelWidth, height: labelHeight)
        context.setFillColor(dimensionBgColor.cgColor)
        let path = CGPath(roundedRect: bgRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(path)
        context.fillPath()

        let textPoint = NSPoint(x: labelX + padding, y: labelY + (labelHeight - size.height) / 2)
        (name as NSString).draw(at: textPoint, withAttributes: attributes)
    }

    private func visibleScreenRectInViewCoordinates() -> CGRect {
        guard let screen = window?.screen else { return bounds }
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        return CGRect(
            x: visibleFrame.minX - screenFrame.minX,
            y: visibleFrame.minY - screenFrame.minY,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
    }

    /// Convert ScreenCaptureKit global top-left coordinates to view-local
    /// bottom-left coordinates for the overlay's display.
    private func screenRectToViewRect(_ screenRect: CGRect) -> CGRect {
        guard let screen = window?.screen else { return screenRect }
        let displayBounds = CGDisplayBounds(screen.displayID)
        let localTopLeftY = screenRect.origin.y - displayBounds.origin.y
        let viewY = displayBounds.height - localTopLeftY - screenRect.height
        return CGRect(
            x: screenRect.origin.x - displayBounds.origin.x,
            y: viewY,
            width: screenRect.width,
            height: screenRect.height
        )
    }

    private var globalSelectionRect: CGRect {
        if isDragSource {
            return CaptureDisplayGeometry.normalizedRect(from: dragStartGlobal, to: dragEndGlobal)
        }
        return remoteGlobalSelection ?? .null
    }

    /// Visible portion of the active selection on this screen, in view-local coords.
    private var selectionRect: CGRect {
        guard let screenFrame = window?.screen?.frame else { return .zero }
        let global = globalSelectionRect
        guard !global.isNull, !global.isEmpty else { return .zero }
        return CaptureDisplayGeometry.intersectingScreenLocalRect(
            globalAppKitRect: global,
            screenFrame: screenFrame
        ) ?? .zero
    }

    private func drawDimensionLabel(
        for globalOrLocalRect: CGRect,
        localVisibleRect: CGRect,
        in context: CGContext
    ) {
        let text = "\(Int(globalOrLocalRect.width)) x \(Int(globalOrLocalRect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: dimensionFont,
            .foregroundColor: dimensionTextColor
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding: CGFloat = 6
        let textLabelWidth = size.width + padding * 2
        let labelHeight = size.height + padding

        // Calculate badge dimensions if needed
        var badgeWidth: CGFloat = 0
        var badgeText: String? = nil
        var badgeColor: NSColor = .systemBlue

        if let badge = activePreset.badgeText {
            badgeText = badge
            badgeColor = activePreset.isFixedSize ? .systemGreen : .systemBlue
            let badgeFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
            let badgeAttrs: [NSAttributedString.Key: Any] = [.font: badgeFont]
            let badgeSize = (badge as NSString).size(withAttributes: badgeAttrs)
            badgeWidth = badgeSize.width + 8
        }

        let gap: CGFloat = badgeText != nil ? 6 : 0
        let totalWidth = textLabelWidth + gap + badgeWidth

        let labelX = localVisibleRect.midX - totalWidth / 2
        let labelY = localVisibleRect.minY - labelHeight - 8

        // Draw main dimension pill
        let bgRect = CGRect(x: labelX, y: labelY, width: textLabelWidth, height: labelHeight)
        context.setFillColor(dimensionBgColor.cgColor)
        let path = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(path)
        context.fillPath()

        let textPoint = NSPoint(x: labelX + padding, y: labelY + (labelHeight - size.height) / 2)
        (text as NSString).draw(at: textPoint, withAttributes: attributes)

        // Draw preset badge pill
        if let badge = badgeText {
            let badgeFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
            let badgeTextAttrs: [NSAttributedString.Key: Any] = [
                .font: badgeFont,
                .foregroundColor: NSColor.white
            ]
            let badgeX = labelX + textLabelWidth + gap
            let bRect = CGRect(x: badgeX, y: labelY, width: badgeWidth, height: labelHeight)
            context.setFillColor(badgeColor.cgColor)
            let bPath = CGPath(roundedRect: bRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
            context.addPath(bPath)
            context.fillPath()

            let badgeTextSize = (badge as NSString).size(withAttributes: badgeTextAttrs)
            let btPoint = NSPoint(
                x: badgeX + (badgeWidth - badgeTextSize.width) / 2,
                y: labelY + (labelHeight - badgeTextSize.height) / 2
            )
            (badge as NSString).draw(at: btPoint, withAttributes: badgeTextAttrs)
        }
    }

    /// Draw a small crosshair reticle at the cursor position.
    /// Short arms (~12px) with a gap in the center — no full-screen lines.
    private func drawReticle(at point: NSPoint, in context: CGContext) {
        let armLength: CGFloat = 12
        let gap: CGFloat = 2.5

        // Draw each arm with dark outline + white fill for visibility on any background
        let arms: [(CGPoint, CGPoint)] = [
            (CGPoint(x: point.x, y: point.y + gap), CGPoint(x: point.x, y: point.y + gap + armLength)),
            (CGPoint(x: point.x, y: point.y - gap), CGPoint(x: point.x, y: point.y - gap - armLength)),
            (CGPoint(x: point.x + gap, y: point.y), CGPoint(x: point.x + gap + armLength, y: point.y)),
            (CGPoint(x: point.x - gap, y: point.y), CGPoint(x: point.x - gap - armLength, y: point.y)),
        ]

        // Dark outline (draw first, thicker)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(2.5)
        for (start, end) in arms {
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
        }

        // White fill (draw on top, thinner)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1.25)
        for (start, end) in arms {
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
        }
    }

    /// Draw coordinate label near the cursor (before dragging starts).
    private func drawCoordinateLabel(at point: NSPoint, in context: CGContext) {
        let x = Int(point.x)
        let y = Int(bounds.height - point.y) // flip to screen coordinates
        let text = "\(x), \(y)"
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.8)
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding: CGFloat = 4
        let labelWidth = size.width + padding * 2
        let labelHeight = size.height + padding

        // Position to the bottom-right of the cursor
        let labelX = point.x + 24
        let labelY = point.y - labelHeight - 8

        // Background pill
        let bgRect = CGRect(x: labelX, y: labelY, width: labelWidth, height: labelHeight)
        context.setFillColor(dimensionBgColor.cgColor)
        let path = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(path)
        context.fillPath()

        // Text
        let textPoint = NSPoint(x: labelX + padding, y: labelY + (labelHeight - size.height) / 2)
        (text as NSString).draw(at: textPoint, withAttributes: attributes)
    }

    // MARK: - Window Hit Testing

    /// Find which window contains the given screen-coordinate point.
    private func windowUnderCursor(at screenPoint: CGPoint) -> WindowInfo? {
        // Windows are in z-order from front to back; return the first (topmost) match
        for window in availableWindows {
            if window.frame.contains(screenPoint) {
                return window
            }
        }
        return nil
    }

    /// Convert view-local bottom-left coordinates to ScreenCaptureKit global
    /// top-left coordinates.
    private func viewPointToScreenPoint(_ viewPoint: NSPoint) -> CGPoint {
        guard let screen = window?.screen else { return viewPoint }
        let displayBounds = CGDisplayBounds(screen.displayID)
        let screenX = viewPoint.x + displayBounds.origin.x
        let screenY = displayBounds.origin.y + displayBounds.height - viewPoint.y
        return CGPoint(x: screenX, y: screenY)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        switch mode {
        case .area:
            // Another overlay already owns a cross-screen drag.
            if let active = Self.activeDragSourceID, active != ObjectIdentifier(self) {
                return
            }

            // Fixed-size: no drag — capture immediately centered on cursor
            if let fixedSize = activePreset.fixedPixelSize {
                let loc = convert(event.locationInWindow, from: nil)
                let fixedRect = CGRect(
                    x: loc.x - CGFloat(fixedSize.width) / 2,
                    y: loc.y - CGFloat(fixedSize.height) / 2,
                    width: CGFloat(fixedSize.width),
                    height: CGFloat(fixedSize.height)
                )
                restoreCursorIfNeeded()
                onSelectionComplete?(fixedRect)
                return
            }

            beginCrossScreenDrag(at: NSEvent.mouseLocation)

        case .windowSelection:
            if let windowID = hoveredWindowID {
                restoreCursor()
                onWindowSelected?(windowID)
            }
        }
    }

    /// Apply aspect-ratio constraint in global AppKit coordinates, clamped to
    /// the virtual desktop union so the selection can span differently sized displays.
    private func constrainedGlobalDragEnd(rawEnd: NSPoint) -> NSPoint {
        guard let ratio = activePreset.ratio, !activePreset.isFixedSize else {
            return rawEnd
        }

        let desktop = CaptureDisplayGeometry.virtualDesktopBounds(
            screenFrames: NSScreen.screens.map(\.frame)
        )
        guard !desktop.isNull else { return rawEnd }

        let dx = rawEnd.x - dragStartGlobal.x
        let dy = rawEnd.y - dragStartGlobal.y

        var endX: CGFloat
        var endY: CGFloat

        if abs(dx) >= abs(dy) {
            let constrainedH = abs(dx) / ratio
            endX = dragStartGlobal.x + dx
            endY = dragStartGlobal.y + (dy >= 0 ? constrainedH : -constrainedH)
        } else {
            let constrainedW = abs(dy) * ratio
            endX = dragStartGlobal.x + (dx >= 0 ? constrainedW : -constrainedW)
            endY = dragStartGlobal.y + dy
        }

        let minX = desktop.minX
        let minY = desktop.minY
        let maxX = desktop.maxX
        let maxY = desktop.maxY

        if endX < minX {
            let clampedWidth = dragStartGlobal.x - minX
            let clampedHeight = clampedWidth / ratio
            endX = minX
            endY = dragStartGlobal.y + (endY >= dragStartGlobal.y ? clampedHeight : -clampedHeight)
        } else if endX > maxX {
            let clampedWidth = maxX - dragStartGlobal.x
            let clampedHeight = clampedWidth / ratio
            endX = maxX
            endY = dragStartGlobal.y + (endY >= dragStartGlobal.y ? clampedHeight : -clampedHeight)
        }

        if endY < minY {
            let clampedHeight = dragStartGlobal.y - minY
            let clampedWidth = clampedHeight * ratio
            endY = minY
            endX = dragStartGlobal.x + (endX >= dragStartGlobal.x ? clampedWidth : -clampedWidth)
        } else if endY > maxY {
            let clampedHeight = maxY - dragStartGlobal.y
            let clampedWidth = clampedHeight * ratio
            endY = maxY
            endX = dragStartGlobal.x + (endX >= dragStartGlobal.x ? clampedWidth : -clampedWidth)
        }

        return NSPoint(x: endX, y: endY)
    }

    override func mouseDragged(with event: NSEvent) {
        guard case .area = mode, isDragSource else { return }
        updateCrossScreenDrag(to: NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        guard case .area = mode else { return }
        // Fixed-size mode already captured in mouseDown — skip mouseUp
        guard !activePreset.isFixedSize else { return }
        guard isDragSource else { return }

        updateCrossScreenDrag(to: NSEvent.mouseLocation)
        let global = globalSelectionRect
        let dragDistance = hypot(
            dragEndGlobal.x - dragStartGlobal.x,
            dragEndGlobal.y - dragStartGlobal.y
        )
        endCrossScreenDrag(broadcastClear: true)

        // Click without dragging (press + release in place) cancels capture.
        let clickSlop: CGFloat = 5
        if dragDistance <= clickSlop || global.width <= clickSlop || global.height <= clickSlop {
            cancelOverlay()
            return
        }

        guard let screenFrame = window?.screen?.frame else {
            cancelOverlay()
            return
        }
        let localRect = CaptureDisplayGeometry.screenLocalRect(
            fromGlobalAppKitRect: global,
            screenFrame: screenFrame
        )
        if localRect.width > clickSlop && localRect.height > clickSlop {
            restoreCursorIfNeeded()
            onSelectionComplete?(localRect)
        } else {
            cancelOverlay()
        }
        needsDisplay = true
    }

    private func beginCrossScreenDrag(at globalPoint: NSPoint) {
        isDragging = true
        isDragSource = true
        Self.activeDragSourceID = ObjectIdentifier(self)
        remoteGlobalSelection = nil
        dragStartGlobal = globalPoint
        dragEndGlobal = globalPoint
        currentMouseLocation = viewLocalPoint(fromGlobal: globalPoint)
        installCrossScreenDragMonitor()
        broadcastCrossScreenSelection(globalSelectionRect)
        needsDisplay = true
    }

    private func updateCrossScreenDrag(to globalPoint: NSPoint) {
        dragEndGlobal = constrainedGlobalDragEnd(rawEnd: globalPoint)
        currentMouseLocation = viewLocalPoint(fromGlobal: dragEndGlobal)

        if !cursorHidden {
            NSCursor.hide()
            cursorHidden = true
        }

        broadcastCrossScreenSelection(globalSelectionRect)
        needsDisplay = true
    }

    private func endCrossScreenDrag(broadcastClear: Bool) {
        removeCrossScreenDragMonitor()
        if isDragSource, Self.activeDragSourceID == ObjectIdentifier(self) {
            Self.activeDragSourceID = nil
        }
        isDragging = false
        isDragSource = false
        if broadcastClear {
            broadcastCrossScreenSelection(nil)
        }
    }

    private func installCrossScreenDragMonitor() {
        removeCrossScreenDragMonitor()
        // Keep updating even when the cursor moves onto another overlay window.
        crossScreenDragMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            guard let self, self.isDragSource else { return event }
            if event.type == .leftMouseDragged {
                self.updateCrossScreenDrag(to: NSEvent.mouseLocation)
                return nil
            }
            if event.type == .leftMouseUp {
                // Defer so we don't remove this monitor from inside its callback.
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isDragSource else { return }
                    self.mouseUp(with: event)
                }
                return nil
            }
            return event
        }
    }

    private func removeCrossScreenDragMonitor() {
        if let crossScreenDragMonitor {
            NSEvent.removeMonitor(crossScreenDragMonitor)
            self.crossScreenDragMonitor = nil
        }
    }

    private func broadcastCrossScreenSelection(_ globalRect: CGRect?) {
        var userInfo: [AnyHashable: Any] = [
            "sourceID": ObjectIdentifier(self)
        ]
        if let globalRect, !globalRect.isNull, !globalRect.isEmpty {
            userInfo["x"] = globalRect.origin.x
            userInfo["y"] = globalRect.origin.y
            userInfo["width"] = globalRect.size.width
            userInfo["height"] = globalRect.size.height
        }
        NotificationCenter.default.post(
            name: .captureCrossScreenSelectionChanged,
            object: nil,
            userInfo: userInfo
        )
    }

    private func handleRemoteSelectionChange(sourceID: ObjectIdentifier?, globalRect: CGRect?) {
        if let sourceID, sourceID == ObjectIdentifier(self) { return }
        if isDragSource { return }

        remoteGlobalSelection = globalRect
        needsDisplay = true
    }

    private func viewLocalPoint(fromGlobal globalPoint: NSPoint) -> NSPoint? {
        guard let screenFrame = window?.screen?.frame,
              screenFrame.contains(globalPoint) else {
            return nil
        }
        return NSPoint(
            x: globalPoint.x - screenFrame.origin.x,
            y: globalPoint.y - screenFrame.origin.y
        )
    }

    override func mouseMoved(with event: NSEvent) {
        currentMouseLocation = convert(event.locationInWindow, from: nil)

        switch mode {
        case .area:
            break
        case .windowSelection:
            if let currentMouseLocation {
                let screenPoint = viewPointToScreenPoint(currentMouseLocation)
                if let window = windowUnderCursor(at: screenPoint) {
                    hoveredWindowID = window.id
                    hoveredWindowFrame = window.frame
                    if window.appName.isEmpty || window.title == window.appName {
                        hoveredWindowName = window.title
                    } else {
                        hoveredWindowName = "\(window.appName) — \(window.title)"
                    }
                } else {
                    hoveredWindowID = nil
                }
            } else {
                hoveredWindowID = nil
            }
        }

        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        switch mode {
        case .area:
            if isDragging {
                cancelCurrentSelection()
            } else if !presetsDisabled {
                // Show preset picker instead of cancelling
                let loc = convert(event.locationInWindow, from: nil)
                showPresetMenu(at: loc)
            } else {
                cancelOverlay()
            }

        case .windowSelection:
            cancelOverlay()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            cancelOverlay()
        } else if event.keyCode == 49 { // Space
            requestSpaceToggle()
        } else if event.keyCode == 15 { // R key
            guard case .area = mode, !isDragging, remoteGlobalSelection == nil, !presetsDisabled else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let backward = flags.contains(.shift)
            cyclePreset(forward: !backward)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func requestSpaceToggle() {
        guard !isDragging, onSpaceToggle != nil else { return }
        onSpaceToggle?()
    }

    private func cancelCurrentSelection() {
        endCrossScreenDrag(broadcastClear: isDragSource)
        isDragging = false
        isDragSource = false
        remoteGlobalSelection = nil
        if let currentMouseLocation,
           let screenFrame = window?.screen?.frame {
            let global = NSPoint(
                x: currentMouseLocation.x + screenFrame.origin.x,
                y: currentMouseLocation.y + screenFrame.origin.y
            )
            dragStartGlobal = global
            dragEndGlobal = global
        } else {
            dragStartGlobal = .zero
            dragEndGlobal = .zero
        }
        needsDisplay = true
    }

    private func cancelOverlay() {
        restoreCursorIfNeeded()
        onCancel?()
    }

    // MARK: - Right-click Preset Menu

    private func showPresetMenu(at location: NSPoint) {
        let menu = NSMenu(title: "")
        presetMenuMap.removeAll()
        var tagCounter = 1

        let presets = settings.visiblePresets

        // Collect visible ratios (freeform + aspect ratios) and fixed sizes
        let ratioPresets = presets.filter {
            if case .fixedSize = $0 { return false }
            return true
        }
        let fixedPresets = presets.filter {
            if case .fixedSize = $0 { return true }
            return false
        }

        // --- Aspect Ratios section ---
        if !ratioPresets.isEmpty {
            let ratioHeader = makeHeaderItem(String(localized: "ASPECT RATIOS"))
            menu.addItem(ratioHeader)

            for preset in ratioPresets {
                let item = NSMenuItem(
                    title: preset.displayName,
                    action: #selector(presetMenuItemSelected(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = tagCounter
                if preset == activePreset {
                    item.state = .on
                }
                presetMenuMap[tagCounter] = preset
                tagCounter += 1
                menu.addItem(item)
            }
        }

        // --- Fixed Sizes section ---
        if !fixedPresets.isEmpty {
            menu.addItem(.separator())
            let fixedHeader = makeHeaderItem(String(localized: "FIXED SIZES"))
            menu.addItem(fixedHeader)

            for preset in fixedPresets {
                let item = NSMenuItem(
                    title: preset.displayName,
                    action: #selector(presetMenuItemSelected(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = tagCounter
                if preset == activePreset {
                    item.state = .on
                }
                presetMenuMap[tagCounter] = preset
                tagCounter += 1
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let manageItem = NSMenuItem(
            title: String(localized: "Manage Presets\u{2026}"),
            action: #selector(openPresetSettings),
            keyEquivalent: ""
        )
        manageItem.target = self
        menu.addItem(manageItem)

        menu.popUp(positioning: nil, at: location, in: self)
    }

    /// Create a non-interactive section header menu item.
    private func makeHeaderItem(_ title: String) -> NSMenuItem {
        let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let attributed = NSAttributedString(string: title.uppercased(), attributes: attrs)
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.attributedTitle = attributed
        item.isEnabled = false
        return item
    }

    @objc private func presetMenuItemSelected(_ sender: NSMenuItem) {
        guard let preset = presetMenuMap[sender.tag] else { return }
        activePreset = preset
        settings.capturePreset = preset

        // Update cursor visibility after preset change
        if activePreset.isFixedSize {
            restoreCursorIfNeeded()
        } else if !cursorHidden {
            NSCursor.hide()
            cursorHidden = true
        }

        setNeedsDisplay(bounds)
        display()

        // Notify other overlay views (multi-screen) to sync their preset
        NotificationCenter.default.post(name: .capturePresetChanged, object: self)
    }

    @objc private func openPresetSettings() {
        // Cancel the overlay first so Settings isn't hidden behind the .screenSaver level window
        cancelOverlay()
        // Delay slightly to let the overlay dismiss before opening Settings
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .openScreenshotSettings, object: nil)
        }
    }
}
