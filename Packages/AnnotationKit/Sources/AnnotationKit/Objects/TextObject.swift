import Foundation
import CoreGraphics
import AppKit

public enum AnnotationTextAlignment: String, Codable, CaseIterable, Sendable {
    case left
    case center
    case right

    public var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left: .left
        case .center: .center
        case .right: .right
        }
    }
}

public final class TextObject: AnnotationObject, @unchecked Sendable {
    private static let glyphTraceStrokeWidth: CGFloat = 3.0

    public let id = ObjectID()
    public var style: StrokeStyle
    public var text: String
    public var origin: CGPoint
    public var boxSize: CGSize?
    public var fontSize: CGFloat
    public var fontName: String
    public var fillColor: AnnotationColor?
    public var outlineColor: AnnotationColor?
    public var glyphStrokeColor: AnnotationColor?
    public var isBold: Bool
    public var isItalic: Bool
    public var isUnderline: Bool
    public var alignment: AnnotationTextAlignment

    public init(
        text: String,
        origin: CGPoint,
        boxSize: CGSize? = nil,
        fontSize: CGFloat = 48,
        fontName: String = ".AppleSystemUIFont",
        fillColor: AnnotationColor? = nil,
        outlineColor: AnnotationColor? = nil,
        glyphStrokeColor: AnnotationColor? = nil,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderline: Bool = false,
        alignment: AnnotationTextAlignment = .left,
        style: StrokeStyle = StrokeStyle()
    ) {
        self.text = text
        self.origin = origin
        self.boxSize = boxSize
        self.fontSize = fontSize
        self.fontName = fontName
        self.fillColor = fillColor
        self.outlineColor = outlineColor
        self.glyphStrokeColor = glyphStrokeColor
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderline = isUnderline
        self.alignment = alignment
        self.style = style
    }

    private func makeFont() -> NSFont {
        let baseFont = NSFont(name: fontName, size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize, weight: .medium)
        var traits = baseFont.fontDescriptor.symbolicTraits
        if isBold { traits.insert(.bold) }
        if isItalic { traits.insert(.italic) }
        guard traits != baseFont.fontDescriptor.symbolicTraits else { return baseFont }
        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: fontSize) ?? baseFont
    }

    private var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment.nsTextAlignment
        style.lineBreakMode = .byWordWrapping
        return style
    }

    private var fillAttributes: [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: makeFont(),
            .foregroundColor: style.color.nsColor.withAlphaComponent(style.opacity),
            .paragraphStyle: paragraphStyle,
        ]
        if isUnderline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attrs
    }

    private var traceAttributes: [NSAttributedString.Key: Any]? {
        guard let glyphStrokeColor else { return nil }
        var attrs = fillAttributes
        attrs[.strokeColor] = glyphStrokeColor.nsColor
        attrs[.strokeWidth] = Self.glyphTraceStrokeWidth
        return attrs
    }

    private var textBounds: CGRect {
        if let boxSize {
            return CGRect(origin: origin, size: boxSize)
        }
        let size = (text as NSString).size(withAttributes: fillAttributes)
        return CGRect(origin: origin, size: size)
    }

    private var boxPadding: CGFloat { 4 }

    private var effectPadding: CGFloat {
        let boxEffectPadding = (fillColor != nil || outlineColor != nil) ? boxPadding : 0
        let glyphStrokePadding = glyphStrokeColor == nil ? 0 : max(boxPadding, ceil(fontSize * 0.03))
        return max(boxEffectPadding, glyphStrokePadding)
    }

    private var effectBounds: CGRect {
        textBounds.insetBy(dx: -effectPadding, dy: -effectPadding)
    }

    private var boxedTextRect: CGRect {
        textBounds.insetBy(dx: boxPadding, dy: boxPadding)
    }

    public var bounds: CGRect {
        (fillColor != nil || outlineColor != nil || glyphStrokeColor != nil) ? effectBounds : textBounds
    }

    public func hitTest(point: CGPoint, threshold: CGFloat) -> Bool {
        bounds.insetBy(dx: -threshold, dy: -threshold).contains(point)
    }

    public func render(in ctx: CGContext) {
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        if fillColor != nil || outlineColor != nil {
            let path = NSBezierPath(roundedRect: effectBounds, xRadius: 4, yRadius: 4)
            if let fillColor {
                fillColor.nsColor.withAlphaComponent(0.5).setFill()
                path.fill()
            }
            if let outlineColor {
                outlineColor.nsColor.setStroke()
                path.lineWidth = 2
                path.stroke()
            }
        }
        if let traceAttributes {
            drawText(with: traceAttributes)
        }
        drawText(with: fillAttributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawText(with attributes: [NSAttributedString.Key: Any]) {
        if boxSize != nil {
            (text as NSString).draw(
                with: boxedTextRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes
            )
        } else {
            (text as NSString).draw(at: origin, withAttributes: attributes)
        }
    }

    public func move(by delta: CGSize) {
        origin.x += delta.width
        origin.y += delta.height
    }

    public func copy() -> any AnnotationObject {
        TextObject(
            text: text,
            origin: origin,
            boxSize: boxSize,
            fontSize: fontSize,
            fontName: fontName,
            fillColor: fillColor,
            outlineColor: outlineColor,
            glyphStrokeColor: glyphStrokeColor,
            isBold: isBold,
            isItalic: isItalic,
            isUnderline: isUnderline,
            alignment: alignment,
            style: style
        )
    }
}
