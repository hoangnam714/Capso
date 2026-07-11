// App/Sources/Recording/SelectionBorderWindow.swift
import AppKit

/// Shows the selected recording area with a border and corner handles.
/// Persists while the toolbar is visible.
@MainActor
final class SelectionBorderWindow: NSPanel {
    init(selectionRect: CGRect, screen: NSScreen) {
        // Add padding for corner handles that extend outside the selection
        let handleSize: CGFloat = 20
        let padding: CGFloat = handleSize / 2
        let paddedRect = selectionRect.insetBy(dx: -padding, dy: -padding)

        super.init(
            contentRect: paddedRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let borderView = SelectionBorderView(
            frame: NSRect(origin: .zero, size: paddedRect.size),
            padding: padding
        )
        self.contentView = borderView
    }

    func show() { makeKeyAndOrderFront(nil) }
}

private class SelectionBorderView: NSView {
    private let padding: CGFloat

    init(frame: NSRect, padding: CGFloat) {
        self.padding = padding
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let selectionRect = bounds.insetBy(dx: padding, dy: padding)
        let borderColor = NSColor.white.withAlphaComponent(0.8).cgColor
        let handleLength: CGFloat = 16
        let lineWidth: CGFloat = 2.5

        // Draw selection border (thin, subtle)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(1.0)
        context.stroke(selectionRect)

        // Draw corner handles (L-shaped).
        context.setStrokeColor(borderColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)

        let minX = selectionRect.minX
        let maxX = selectionRect.maxX
        let minY = selectionRect.minY
        let maxY = selectionRect.maxY

        // Top-left corner
        drawCorner(context: context, x: minX, y: maxY, dx: handleLength, dy: -handleLength)
        // Top-right corner
        drawCorner(context: context, x: maxX, y: maxY, dx: -handleLength, dy: -handleLength)
        // Bottom-left corner
        drawCorner(context: context, x: minX, y: minY, dx: handleLength, dy: handleLength)
        // Bottom-right corner
        drawCorner(context: context, x: maxX, y: minY, dx: -handleLength, dy: handleLength)

        // Draw edge midpoint handles (small lines)
        let midHandleLength: CGFloat = 8

        // Top edge center
        let topMidX = selectionRect.midX
        context.move(to: CGPoint(x: topMidX - midHandleLength, y: maxY))
        context.addLine(to: CGPoint(x: topMidX + midHandleLength, y: maxY))
        context.strokePath()

        // Bottom edge center
        context.move(to: CGPoint(x: topMidX - midHandleLength, y: minY))
        context.addLine(to: CGPoint(x: topMidX + midHandleLength, y: minY))
        context.strokePath()

        // Left edge center
        let leftMidY = selectionRect.midY
        context.move(to: CGPoint(x: minX, y: leftMidY - midHandleLength))
        context.addLine(to: CGPoint(x: minX, y: leftMidY + midHandleLength))
        context.strokePath()

        // Right edge center
        context.move(to: CGPoint(x: maxX, y: leftMidY - midHandleLength))
        context.addLine(to: CGPoint(x: maxX, y: leftMidY + midHandleLength))
        context.strokePath()
    }

    private func drawCorner(context: CGContext, x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat) {
        // Horizontal arm
        context.move(to: CGPoint(x: x, y: y))
        context.addLine(to: CGPoint(x: x + dx, y: y))
        context.strokePath()

        // Vertical arm
        context.move(to: CGPoint(x: x, y: y))
        context.addLine(to: CGPoint(x: x, y: y + dy))
        context.strokePath()
    }
}
