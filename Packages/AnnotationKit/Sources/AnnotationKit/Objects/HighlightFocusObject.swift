import Foundation
import CoreGraphics

/// Spotlight / dim-overlay annotation: fills `canvasRect` with a translucent
/// color and punches one or more rounded "focus" holes so those regions stay bright.
public final class HighlightFocusObject: AnnotationObject, @unchecked Sendable {
    public let id = ObjectID()
    public var style: StrokeStyle
    /// Full image bounds in annotation coordinates (top-left origin).
    public var canvasRect: CGRect
    public var focusRects: [CGRect]
    public var cornerRadius: CGFloat

    public static let defaultDimOpacity: CGFloat = 0.55
    public static let defaultCornerRadius: CGFloat = 12

    public init(
        canvasRect: CGRect,
        focusRects: [CGRect],
        cornerRadius: CGFloat = HighlightFocusObject.defaultCornerRadius,
        style: StrokeStyle = StrokeStyle(
            color: .black,
            lineWidth: 1,
            opacity: HighlightFocusObject.defaultDimOpacity,
            filled: true
        )
    ) {
        self.canvasRect = canvasRect
        self.focusRects = focusRects
        self.cornerRadius = max(0, cornerRadius)
        self.style = style
    }

    public var bounds: CGRect {
        guard let first = focusRects.first else { return .null }
        return focusRects.dropFirst().reduce(first) { $0.union($1) }
    }

    public func hitTest(point: CGPoint, threshold: CGFloat) -> Bool {
        focusRects.contains { rect in
            rect.insetBy(dx: -threshold, dy: -threshold).contains(point)
        }
    }

    public func focusIndex(at point: CGPoint, threshold: CGFloat) -> Int? {
        for (index, rect) in focusRects.enumerated().reversed() {
            if rect.insetBy(dx: -threshold, dy: -threshold).contains(point) {
                return index
            }
        }
        return nil
    }

    public func addFocusRect(_ rect: CGRect) {
        guard rect.width > 1, rect.height > 1 else { return }
        focusRects.append(rect)
    }

    public func focusRect(at index: Int) -> CGRect? {
        guard focusRects.indices.contains(index) else { return nil }
        return focusRects[index]
    }

    public func setFocusRect(_ rect: CGRect, at index: Int) {
        guard focusRects.indices.contains(index), rect.width > 1, rect.height > 1 else { return }
        focusRects[index] = rect
    }

    public func moveFocusRect(at index: Int, by delta: CGSize) {
        guard focusRects.indices.contains(index) else { return }
        focusRects[index].origin.x += delta.width
        focusRects[index].origin.y += delta.height
    }

    /// Removes one focus hole. Returns `true` when no holes remain.
    @discardableResult
    public func removeFocusRect(at index: Int) -> Bool {
        guard focusRects.indices.contains(index) else { return focusRects.isEmpty }
        focusRects.remove(at: index)
        return focusRects.isEmpty
    }

    public func render(in ctx: CGContext) {
        guard canvasRect.width > 0, canvasRect.height > 0 else { return }

        ctx.saveGState()
        // Build the dim overlay in a transparency layer, then punch holes with
        // `.clear`. Overlapping focus regions stay bright — unlike even-odd fill,
        // which re-darks intersections. Clearing inside the layer does not erase
        // the screenshot underneath.
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setFillColor(style.color.cgColor.copy(alpha: style.opacity) ?? style.color.cgColor)
        ctx.fill(canvasRect)

        if !focusRects.isEmpty {
            ctx.setBlendMode(.clear)
            let radius = min(cornerRadius, min(canvasRect.width, canvasRect.height) / 2)
            for rect in focusRects where rect.width > 0 && rect.height > 0 {
                let r = min(radius, min(rect.width, rect.height) / 2)
                if r > 0.5 {
                    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
                } else {
                    ctx.addRect(rect)
                }
                ctx.fillPath()
            }
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    public func move(by delta: CGSize) {
        focusRects = focusRects.map { rect in
            var moved = rect
            moved.origin.x += delta.width
            moved.origin.y += delta.height
            return moved
        }
    }

    /// Scale all focus rects so their union matches `newBounds`.
    public func replaceBounds(with newBounds: CGRect) {
        let old = bounds
        guard !old.isNull, old.width > 0.5, old.height > 0.5,
              newBounds.width > 0.5, newBounds.height > 0.5 else {
            return
        }
        let scaleX = newBounds.width / old.width
        let scaleY = newBounds.height / old.height
        focusRects = focusRects.map { rect in
            CGRect(
                x: newBounds.minX + (rect.minX - old.minX) * scaleX,
                y: newBounds.minY + (rect.minY - old.minY) * scaleY,
                width: rect.width * scaleX,
                height: rect.height * scaleY
            )
        }
    }

    public func copy() -> any AnnotationObject {
        HighlightFocusObject(
            canvasRect: canvasRect,
            focusRects: focusRects,
            cornerRadius: cornerRadius,
            style: style
        )
    }
}
