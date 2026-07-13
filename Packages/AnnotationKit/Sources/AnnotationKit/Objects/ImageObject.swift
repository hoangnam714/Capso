import Foundation
import CoreGraphics
import ImageIO
import SharedKit

public final class ImageObject: AnnotationObject, @unchecked Sendable {
    public let id = ObjectID()
    public var style: StrokeStyle
    public var rect: CGRect
    public var imageData: Data

    private var cachedImage: CGImage?

    public init(imageData: Data, rect: CGRect, style: StrokeStyle = StrokeStyle(opacity: 1)) {
        self.imageData = imageData
        self.rect = rect
        self.style = style
        self.cachedImage = Self.decodeImage(from: imageData)
    }

    public convenience init?(
        cgImage: CGImage,
        rect: CGRect,
        style: StrokeStyle = StrokeStyle(opacity: 1)
    ) {
        guard let data = ImageUtilities.pngData(from: cgImage) else { return nil }
        self.init(imageData: data, rect: rect, style: style)
        self.cachedImage = cgImage
    }

    public var cgImage: CGImage? {
        if let cachedImage { return cachedImage }
        let decoded = Self.decodeImage(from: imageData)
        cachedImage = decoded
        return decoded
    }

    /// Places the image centered on the canvas, scaled to at most `maxFraction` of either side.
    public static func fittingRect(
        forPixelSize pixelSize: CGSize,
        canvasSize: CGSize,
        center: CGPoint? = nil,
        maxFraction: CGFloat = 0.45
    ) -> CGRect {
        let maxWidth = max(canvasSize.width * maxFraction, 40)
        let maxHeight = max(canvasSize.height * maxFraction, 40)
        let scale = min(
            maxWidth / max(pixelSize.width, 1),
            maxHeight / max(pixelSize.height, 1),
            1
        )
        let width = max(pixelSize.width * scale, 20)
        let height = max(pixelSize.height * scale, 20)
        let mid = center ?? CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        return CGRect(
            x: mid.x - width / 2,
            y: mid.y - height / 2,
            width: width,
            height: height
        )
    }

    public var bounds: CGRect { rect }

    public func hitTest(point: CGPoint, threshold: CGFloat) -> Bool {
        rect.insetBy(dx: -threshold, dy: -threshold).contains(point)
    }

    public func render(in ctx: CGContext) {
        guard let image = cgImage else { return }
        ctx.saveGState()
        ctx.setAlpha(style.opacity)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: rect)
        ctx.restoreGState()
    }

    public func move(by delta: CGSize) {
        rect.origin.x += delta.width
        rect.origin.y += delta.height
    }

    public func copy() -> any AnnotationObject {
        ImageObject(imageData: imageData, rect: rect, style: style)
    }

    private static func decodeImage(from data: Data) -> CGImage? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return image
        }
        return nil
    }
}
