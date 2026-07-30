// Packages/AnnotationKit/Sources/AnnotationKit/Objects/ShapeObject.swift
import Foundation
import CoreGraphics

/// Closed decorative shapes (triangle, cloud, trapezoid, …) drawn inside a bounding rect.
public final class ShapeObject: AnnotationObject, @unchecked Sendable {
    public let id = ObjectID()
    public var style: StrokeStyle
    public var rect: CGRect
    public var kind: ShapeKind

    public init(rect: CGRect, kind: ShapeKind, style: StrokeStyle = StrokeStyle()) {
        self.rect = rect
        self.kind = kind
        self.style = style
    }

    public var bounds: CGRect { rect }

    public func hitTest(point: CGPoint, threshold: CGFloat) -> Bool {
        let path = Self.path(for: kind, in: rect)
        let fillRule: CGPathFillRule = kind.usesEvenOddFill ? .evenOdd : .winding
        if style.filled {
            if path.contains(point, using: fillRule, transform: .identity) {
                return true
            }
            let stroked = path.copy(
                strokingWithWidth: threshold * 2,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 10
            )
            return stroked.contains(point)
        }
        let stroked = path.copy(
            strokingWithWidth: style.lineWidth + threshold * 2,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 10
        )
        return stroked.contains(point)
    }

    public func render(in ctx: CGContext) {
        ctx.saveGState()
        ctx.setAlpha(style.opacity)
        let path = Self.path(for: kind, in: rect)
        if style.filled {
            ctx.setFillColor(style.color.cgColor)
            ctx.addPath(path)
            if kind.usesEvenOddFill {
                ctx.fillPath(using: .evenOdd)
            } else {
                ctx.fillPath()
            }
        } else {
            ctx.setStrokeColor(style.color.cgColor)
            ctx.setLineWidth(style.lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            style.pattern.apply(to: ctx, lineWidth: style.lineWidth)
            ctx.addPath(path)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    public func move(by delta: CGSize) {
        rect.origin.x += delta.width
        rect.origin.y += delta.height
    }

    public func copy() -> any AnnotationObject {
        ShapeObject(rect: rect, kind: kind, style: style)
    }

    // MARK: - Path builders

    public static func path(for kind: ShapeKind, in rect: CGRect) -> CGPath {
        switch kind {
        case .triangle: return trianglePath(in: rect)
        case .rightTriangle: return rightTrianglePath(in: rect)
        case .invertedTriangle: return invertedTrianglePath(in: rect)
        case .diamond: return diamondPath(in: rect)
        case .trapezoid: return trapezoidPath(in: rect)
        case .parallelogram: return parallelogramPath(in: rect)
        case .pentagon: return regularPolygonPath(sides: 5, in: rect)
        case .hexagon: return regularPolygonPath(sides: 6, in: rect)
        case .octagon: return regularPolygonPath(sides: 8, in: rect)
        case .star: return starPath(points: 5, in: rect)
        case .star6: return starPath(points: 6, in: rect)
        case .plus: return plusPath(in: rect)
        case .cross: return crossPath(in: rect)
        case .chevron: return chevronPath(in: rect)
        case .blockArrow: return blockArrowPath(in: rect)
        case .semicircle: return semicirclePath(in: rect)
        case .pill: return pillPath(in: rect)
        case .heart: return heartPath(in: rect)
        case .teardrop: return teardropPath(in: rect)
        case .crescent: return crescentPath(in: rect)
        case .cloud: return cloudPath(in: rect)
        case .speechBubble: return speechBubblePath(in: rect)
        case .cloudSpeechBubble: return cloudSpeechBubblePath(in: rect)
        case .thoughtBubble: return thoughtBubblePath(in: rect)
        case .banner: return bannerPath(in: rect)
        case .cylinder: return cylinderPath(in: rect)
        case .ring: return ringPath(in: rect)
        case .lightning: return lightningPath(in: rect)
        }
    }

    private static func trianglePath(in rect: CGRect) -> CGPath {
        polygon([
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ])
    }

    private static func rightTrianglePath(in rect: CGRect) -> CGPath {
        polygon([
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ])
    }

    private static func invertedTrianglePath(in rect: CGRect) -> CGPath {
        polygon([
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.maxY)
        ])
    }

    private static func diamondPath(in rect: CGRect) -> CGPath {
        polygon([
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.midY)
        ])
    }

    private static func trapezoidPath(in rect: CGRect) -> CGPath {
        let inset = rect.width * 0.18
        return polygon([
            CGPoint(x: rect.minX + inset, y: rect.minY),
            CGPoint(x: rect.maxX - inset, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ])
    }

    private static func parallelogramPath(in rect: CGRect) -> CGPath {
        let skew = rect.width * 0.22
        return polygon([
            CGPoint(x: rect.minX + skew, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX - skew, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ])
    }

    private static func regularPolygonPath(sides: Int, in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let cx = rect.midX
        let cy = rect.midY
        let rx = rect.width / 2
        let ry = rect.height / 2
        for i in 0..<sides {
            let angle = CGFloat(i) * 2 * .pi / CGFloat(sides) - .pi / 2
            let point = CGPoint(x: cx + rx * cos(angle), y: cy + ry * sin(angle))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private static func starPath(points: Int, in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let cx = rect.midX
        let cy = rect.midY
        let outerX = rect.width / 2
        let outerY = rect.height / 2
        let innerX = outerX * 0.42
        let innerY = outerY * 0.42
        let count = points * 2
        for i in 0..<count {
            let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let useOuter = i % 2 == 0
            let point = CGPoint(
                x: cx + (useOuter ? outerX : innerX) * cos(angle),
                y: cy + (useOuter ? outerY : innerY) * sin(angle)
            )
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private static func plusPath(in rect: CGRect) -> CGPath {
        let t = min(rect.width, rect.height) * 0.28
        let cx = rect.midX
        let cy = rect.midY
        return polygon([
            CGPoint(x: cx - t / 2, y: rect.minY),
            CGPoint(x: cx + t / 2, y: rect.minY),
            CGPoint(x: cx + t / 2, y: cy - t / 2),
            CGPoint(x: rect.maxX, y: cy - t / 2),
            CGPoint(x: rect.maxX, y: cy + t / 2),
            CGPoint(x: cx + t / 2, y: cy + t / 2),
            CGPoint(x: cx + t / 2, y: rect.maxY),
            CGPoint(x: cx - t / 2, y: rect.maxY),
            CGPoint(x: cx - t / 2, y: cy + t / 2),
            CGPoint(x: rect.minX, y: cy + t / 2),
            CGPoint(x: rect.minX, y: cy - t / 2),
            CGPoint(x: cx - t / 2, y: cy - t / 2)
        ])
    }

    private static func crossPath(in rect: CGRect) -> CGPath {
        let inset = min(rect.width, rect.height) * 0.18
        let path = CGMutablePath()
        // Thick X as a single closed polygon
        let w = rect.width
        let h = rect.height
        let x = rect.minX
        let y = rect.minY
        let t = inset
        return polygon([
            CGPoint(x: x + t, y: y),
            CGPoint(x: x + w / 2, y: y + h / 2 - t),
            CGPoint(x: x + w - t, y: y),
            CGPoint(x: x + w, y: y + t),
            CGPoint(x: x + w / 2 + t, y: y + h / 2),
            CGPoint(x: x + w, y: y + h - t),
            CGPoint(x: x + w - t, y: y + h),
            CGPoint(x: x + w / 2, y: y + h / 2 + t),
            CGPoint(x: x + t, y: y + h),
            CGPoint(x: x, y: y + h - t),
            CGPoint(x: x + w / 2 - t, y: y + h / 2),
            CGPoint(x: x, y: y + t)
        ])
    }

    private static func chevronPath(in rect: CGRect) -> CGPath {
        let notch = rect.width * 0.35
        return polygon([
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX - notch, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.maxX - notch, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.minX + notch, y: rect.midY)
        ])
    }

    private static func blockArrowPath(in rect: CGRect) -> CGPath {
        let shaftTop = rect.minY + rect.height * 0.28
        let shaftBottom = rect.maxY - rect.height * 0.28
        let headStart = rect.minX + rect.width * 0.55
        return polygon([
            CGPoint(x: rect.minX, y: shaftTop),
            CGPoint(x: headStart, y: shaftTop),
            CGPoint(x: headStart, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: headStart, y: rect.maxY),
            CGPoint(x: headStart, y: shaftBottom),
            CGPoint(x: rect.minX, y: shaftBottom)
        ])
    }

    private static func semicirclePath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let radiusX = rect.width / 2
        let radiusY = rect.height
        // Flat base at bottom, arc bulging toward top (image coords: minY = top).
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for i in 0...32 {
            let t = CGFloat(i) / 32
            let angle = t * .pi
            let px = rect.midX + radiusX * cos(.pi - angle)
            let py = rect.maxY - radiusY * sin(angle)
            path.addLine(to: CGPoint(x: px, y: py))
        }
        path.closeSubpath()
        return path
    }

    private static func pillPath(in rect: CGRect) -> CGPath {
        let radius = min(rect.width, rect.height) / 2
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private static func heartPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let w = rect.width
        let h = rect.height
        let x = rect.minX
        let y = rect.minY
        path.move(to: CGPoint(x: x + w * 0.5, y: y + h * 0.28))
        path.addCurve(
            to: CGPoint(x: x + w * 0.05, y: y + h * 0.28),
            control1: CGPoint(x: x + w * 0.5, y: y + h * 0.02),
            control2: CGPoint(x: x + w * 0.05, y: y + h * 0.02)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.5, y: y + h * 0.95),
            control1: CGPoint(x: x + w * 0.05, y: y + h * 0.58),
            control2: CGPoint(x: x + w * 0.5, y: y + h * 0.78)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.95, y: y + h * 0.28),
            control1: CGPoint(x: x + w * 0.5, y: y + h * 0.78),
            control2: CGPoint(x: x + w * 0.95, y: y + h * 0.58)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.5, y: y + h * 0.28),
            control1: CGPoint(x: x + w * 0.95, y: y + h * 0.02),
            control2: CGPoint(x: x + w * 0.5, y: y + h * 0.02)
        )
        path.closeSubpath()
        return path
    }

    private static func teardropPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let w = rect.width
        let h = rect.height
        let x = rect.minX
        let y = rect.minY
        path.move(to: CGPoint(x: x + w * 0.5, y: y))
        path.addCurve(
            to: CGPoint(x: x + w, y: y + h * 0.55),
            control1: CGPoint(x: x + w * 0.85, y: y + h * 0.12),
            control2: CGPoint(x: x + w, y: y + h * 0.32)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.5, y: y + h),
            control1: CGPoint(x: x + w, y: y + h * 0.82),
            control2: CGPoint(x: x + w * 0.72, y: y + h)
        )
        path.addCurve(
            to: CGPoint(x: x, y: y + h * 0.55),
            control1: CGPoint(x: x + w * 0.28, y: y + h),
            control2: CGPoint(x: x, y: y + h * 0.82)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.5, y: y),
            control1: CGPoint(x: x, y: y + h * 0.32),
            control2: CGPoint(x: x + w * 0.15, y: y + h * 0.12)
        )
        path.closeSubpath()
        return path
    }

    private static func crescentPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: rect)
        let hole = rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.08)
            .offsetBy(dx: rect.width * 0.16, dy: 0)
        path.addEllipse(in: hole)
        return path
    }

    private static func cloudPath(in rect: CGRect) -> CGPath {
        scallopedCloudPath(in: rect, lobes: 10)
    }

    /// Classic oval speech bubble with a pointed tail (bottom-left).
    private static func speechBubblePath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let bubble = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height * 0.72
        )
        let tip = CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY)
        let joinLeft = CGPoint(x: rect.minX + rect.width * 0.22, y: bubble.maxY)
        let joinRight = CGPoint(x: rect.minX + rect.width * 0.40, y: bubble.maxY)

        // Single closed silhouette: oval arc from joinRight → around → joinLeft, then tip.
        let cx = bubble.midX
        let cy = bubble.midY
        let rx = bubble.width / 2
        let ry = bubble.height / 2

        // Angles where the tail attaches (y-down: bottom ≈ +π/2).
        let startAngle = atan2(joinRight.y - cy, joinRight.x - cx)
        let endAngle = atan2(joinLeft.y - cy, joinLeft.x - cx)

        path.move(to: joinRight)
        appendEllipseArc(path, center: CGPoint(x: cx, y: cy), radiusX: rx, radiusY: ry,
                         from: startAngle, to: endAngle + 2 * .pi, clockwise: false)
        path.addLine(to: tip)
        path.closeSubpath()
        return path
    }

    /// Scalloped cloud body with a speech-bubble tail.
    private static func cloudSpeechBubblePath(in rect: CGRect) -> CGPath {
        let body = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height * 0.72
        )
        let tip = CGPoint(x: rect.minX + rect.width * 0.16, y: rect.maxY)
        let joinLeftX = rect.minX + rect.width * 0.20
        let joinRightX = rect.minX + rect.width * 0.42

        let path = scallopedCloudPath(in: body, lobes: 9)
        // Append a closed triangular tail as a second subpath (stroke + fill both look correct).
        path.move(to: CGPoint(x: joinLeftX, y: body.maxY - body.height * 0.02))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: joinRightX, y: body.maxY - body.height * 0.02))
        path.closeSubpath()
        return path
    }

    /// Scalloped thought cloud with a trail of descending circles.
    private static func thoughtBubblePath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let body = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height * 0.62
        )
        path.addPath(scallopedCloudPath(in: body, lobes: 10))

        let mid = CGRect(
            x: rect.minX + rect.width * 0.16,
            y: rect.minY + rect.height * 0.58,
            width: rect.width * 0.16,
            height: rect.height * 0.16
        )
        path.addEllipse(in: mid)

        let tip = CGRect(
            x: rect.minX + rect.width * 0.08,
            y: rect.minY + rect.height * 0.78,
            width: rect.width * 0.09,
            height: rect.height * 0.11
        )
        path.addEllipse(in: tip)

        let tip2 = CGRect(
            x: rect.minX + rect.width * 0.02,
            y: rect.minY + rect.height * 0.90,
            width: rect.width * 0.055,
            height: rect.height * 0.07
        )
        path.addEllipse(in: tip2)
        return path
    }

    /// Fluffy scalloped cloud silhouette filling `rect`.
    private static func scallopedCloudPath(in rect: CGRect, lobes: Int) -> CGMutablePath {
        let path = CGMutablePath()
        let pad = min(rect.width, rect.height) * 0.08
        let body = rect.insetBy(dx: pad, dy: pad)
        let cx = body.midX
        let cy = body.midY
        let rx = body.width / 2
        let ry = body.height / 2
        let bump = min(rx, ry) * max(0.28, 2.2 / CGFloat(lobes))

        for i in 0..<lobes {
            let angle = -CGFloat.pi / 2 + 2 * .pi * CGFloat(i) / CGFloat(lobes)
            // Pull lobe centers slightly inward so bumps sit on the oval rim.
            let lobeCenter = CGPoint(
                x: cx + cos(angle) * rx * 0.72,
                y: cy + sin(angle) * ry * 0.72
            )
            let span = .pi / CGFloat(lobes) + 0.35
            let startAngle = angle - span
            let endAngle = angle + span

            if i == 0 {
                path.move(to: CGPoint(
                    x: lobeCenter.x + cos(startAngle) * bump,
                    y: lobeCenter.y + sin(startAngle) * bump
                ))
            }
            path.addArc(
                center: lobeCenter,
                radius: bump,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: false
            )
        }
        path.closeSubpath()
        return path
    }

    /// Approximate an elliptical arc with line segments (CGPath has no native ellipse-arc API).
    private static func appendEllipseArc(
        _ path: CGMutablePath,
        center: CGPoint,
        radiusX: CGFloat,
        radiusY: CGFloat,
        from start: CGFloat,
        to end: CGFloat,
        clockwise: Bool
    ) {
        var delta = end - start
        if clockwise {
            while delta > 0 { delta -= 2 * .pi }
            if delta == 0 { delta = -2 * .pi }
        } else {
            while delta < 0 { delta += 2 * .pi }
            if delta == 0 { delta = 2 * .pi }
        }
        let steps = max(24, Int(abs(delta) / (CGFloat.pi / 24)))
        for i in 1...steps {
            let t = start + delta * CGFloat(i) / CGFloat(steps)
            path.addLine(to: CGPoint(
                x: center.x + radiusX * cos(t),
                y: center.y + radiusY * sin(t)
            ))
        }
    }

    private static func bannerPath(in rect: CGRect) -> CGPath {
        let notch = rect.height * 0.28
        return polygon([
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY - notch),
            CGPoint(x: rect.minX, y: rect.maxY)
        ])
    }

    private static func cylinderPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let topH = max(rect.height * 0.22, 1)
        let top = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: topH)
        let bottom = CGRect(x: rect.minX, y: rect.maxY - topH, width: rect.width, height: topH)

        // Closed silhouette: left side → bottom arc → right side → top arc back.
        path.move(to: CGPoint(x: rect.minX, y: top.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: bottom.midY))
        appendEllipseHalf(path, in: bottom, fromAngle: .pi, toAngle: 0)
        path.addLine(to: CGPoint(x: rect.maxX, y: top.midY))
        appendEllipseHalf(path, in: top, fromAngle: 0, toAngle: .pi)
        path.closeSubpath()
        return path
    }

    private static func appendEllipseHalf(
        _ path: CGMutablePath,
        in ellipse: CGRect,
        fromAngle: CGFloat,
        toAngle: CGFloat
    ) {
        let rx = ellipse.width / 2
        let ry = ellipse.height / 2
        let cx = ellipse.midX
        let cy = ellipse.midY
        let steps = 24
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let angle = fromAngle + (toAngle - fromAngle) * t
            path.addLine(to: CGPoint(x: cx + rx * cos(angle), y: cy + ry * sin(angle)))
        }
    }

    private static func ringPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: rect)
        let inset = min(rect.width, rect.height) * 0.22
        path.addEllipse(in: rect.insetBy(dx: inset, dy: inset))
        return path
    }

    private static func lightningPath(in rect: CGRect) -> CGPath {
        let w = rect.width
        let h = rect.height
        let x = rect.minX
        let y = rect.minY
        return polygon([
            CGPoint(x: x + w * 0.58, y: y),
            CGPoint(x: x + w * 0.28, y: y + h * 0.42),
            CGPoint(x: x + w * 0.48, y: y + h * 0.42),
            CGPoint(x: x + w * 0.22, y: y + h),
            CGPoint(x: x + w * 0.72, y: y + h * 0.48),
            CGPoint(x: x + w * 0.52, y: y + h * 0.48)
        ])
    }

    private static func polygon(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}
