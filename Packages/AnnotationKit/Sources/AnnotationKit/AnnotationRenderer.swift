// Packages/AnnotationKit/Sources/AnnotationKit/AnnotationRenderer.swift
import Foundation
import CoreGraphics
import CoreImage

public enum AnnotationRenderer {
    /// Renders the source image with annotations drawn on top, optionally cropped.
    /// `cropRect` is in image coordinates with top-left origin (y grows down),
    /// matching AnnotationObject.bounds and `CGImage.cropping(to:)`.
    public static func render(
        sourceImage: CGImage,
        objects: [any AnnotationObject],
        cropRect: CGRect? = nil
    ) -> CGImage? {
        let width = sourceImage.width
        let height = sourceImage.height

        guard let ctx = CGContext(
            data: nil,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        ctx.draw(sourceImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        // Spotlight overlays always sit under arrows/text/shapes.
        let highlightFocus = objects.compactMap { $0 as? HighlightFocusObject }
        let foreground = objects.filter { !($0 is HighlightFocusObject) }
        for object in highlightFocus {
            object.render(in: ctx)
        }
        for object in foreground {
            if let pixelate = object as? PixelateObject {
                pixelate.renderWithSource(in: ctx, sourceImage: sourceImage)
            } else {
                object.render(in: ctx)
            }
        }
        ctx.restoreGState()

        guard var outputImage = ctx.makeImage() else { return nil }

        if let crop = cropRect {
            // `CGImage.cropping(to:)` already uses top-left / raster coordinates —
            // do not Y-flip `cropRect` (preview clipping uses the same space).
            let clamped = crop.intersection(
                CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
            )
            if !clamped.isEmpty, let cropped = outputImage.cropping(to: clamped) {
                outputImage = cropped
            }
        }

        return outputImage
    }
}
