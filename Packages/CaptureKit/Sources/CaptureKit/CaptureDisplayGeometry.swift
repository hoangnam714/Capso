import CoreGraphics

public enum CaptureDisplayGeometry {
    public static func screenLocalRect(
        fromTopLeftCaptureRect captureRect: CGRect,
        screenHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: captureRect.origin.x,
            y: screenHeight - captureRect.origin.y - captureRect.height,
            width: captureRect.width,
            height: captureRect.height
        )
    }

    public static func displayScale(imageSize: CGSize, screenRect: CGRect) -> CGFloat? {
        guard imageSize.width > 0,
              imageSize.height > 0,
              screenRect.width > 0,
              screenRect.height > 0 else {
            return nil
        }

        return min(screenRect.width / imageSize.width, screenRect.height / imageSize.height)
    }

    public static func presetBadgeY(
        viewHeight: CGFloat,
        badgeHeight: CGFloat,
        safeAreaTopInset: CGFloat
    ) -> CGFloat {
        let topMargin: CGFloat = safeAreaTopInset > 0 ? 64 : 20
        return viewHeight - badgeHeight - safeAreaTopInset - topMargin
    }

    public static func frozenImageCropRect(
        screenLocalRect: CGRect,
        screenSize: CGSize,
        imageSize: CGSize
    ) -> CGRect {
        guard screenLocalRect.width > 0,
              screenLocalRect.height > 0,
              screenSize.width > 0,
              screenSize.height > 0,
              imageSize.width > 0,
              imageSize.height > 0 else {
            return .null
        }

        let scaleX = imageSize.width / screenSize.width
        let scaleY = imageSize.height / screenSize.height

        return CGRect(
            x: screenLocalRect.origin.x * scaleX,
            y: (screenSize.height - screenLocalRect.origin.y - screenLocalRect.height) * scaleY,
            width: screenLocalRect.width * scaleX,
            height: screenLocalRect.height * scaleY
        ).integral
    }

    public static func displayLocalRect(
        fromGlobalTopLeftRect globalRect: CGRect,
        displayBounds: CGRect
    ) -> CGRect {
        guard globalRect.width > 0,
              globalRect.height > 0,
              displayBounds.width > 0,
              displayBounds.height > 0 else {
            return .null
        }

        let localRect = CGRect(
            x: globalRect.origin.x - displayBounds.origin.x,
            y: globalRect.origin.y - displayBounds.origin.y,
            width: globalRect.width,
            height: globalRect.height
        )
        let localBounds = CGRect(origin: .zero, size: displayBounds.size)
        let visibleRect = localRect.intersection(localBounds)
        return visibleRect.isNull || visibleRect.isEmpty ? .null : visibleRect
    }

    /// Normalize a rect defined by two points into a positive-size rectangle.
    public static func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    /// Convert a screen-local bottom-left rect into a global AppKit bottom-left rect.
    public static func globalAppKitRect(
        fromScreenLocalRect localRect: CGRect,
        screenFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: localRect.origin.x + screenFrame.origin.x,
            y: localRect.origin.y + screenFrame.origin.y,
            width: localRect.width,
            height: localRect.height
        )
    }

    /// Convert a global AppKit bottom-left rect into screen-local bottom-left coords.
    /// The result may extend outside the screen when the selection spans displays.
    public static func screenLocalRect(
        fromGlobalAppKitRect globalRect: CGRect,
        screenFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: globalRect.origin.x - screenFrame.origin.x,
            y: globalRect.origin.y - screenFrame.origin.y,
            width: globalRect.width,
            height: globalRect.height
        )
    }

    /// Visible intersection of a global AppKit selection with one screen, in
    /// that screen's local bottom-left coordinates. Returns `nil` when empty.
    public static func intersectingScreenLocalRect(
        globalAppKitRect: CGRect,
        screenFrame: CGRect
    ) -> CGRect? {
        let intersection = globalAppKitRect.intersection(screenFrame)
        guard !intersection.isNull, !intersection.isEmpty else { return nil }
        return CGRect(
            x: intersection.origin.x - screenFrame.origin.x,
            y: intersection.origin.y - screenFrame.origin.y,
            width: intersection.width,
            height: intersection.height
        )
    }

    /// Flip a screen-local bottom-left rect into display-local top-left coords
    /// for ScreenCaptureKit `sourceRect`.
    public static func displayTopLeftRect(
        fromScreenLocalRect localRect: CGRect,
        screenHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: localRect.origin.x,
            y: screenHeight - localRect.origin.y - localRect.height,
            width: localRect.width,
            height: localRect.height
        )
    }

    /// Union of the provided screen frames (AppKit bottom-left space).
    public static func virtualDesktopBounds(screenFrames: [CGRect]) -> CGRect {
        guard let first = screenFrames.first else { return .null }
        return screenFrames.dropFirst().reduce(first) { $0.union($1) }
    }
}

/// One captured slice of a cross-display area selection, placed in selection-
/// relative AppKit bottom-left point coordinates.
public struct MultiDisplayCaptureSlice: Sendable {
    public let image: CGImage
    public let originInSelection: CGPoint
    public let sizeInPoints: CGSize
    public let scale: CGFloat

    public init(
        image: CGImage,
        originInSelection: CGPoint,
        sizeInPoints: CGSize,
        scale: CGFloat
    ) {
        self.image = image
        self.originInSelection = originInSelection
        self.sizeInPoints = sizeInPoints
        self.scale = scale
    }
}

public enum MultiDisplayImageStitcher {
    /// Composite per-display crops into one image covering `selectionSize`
    /// points. Uses `outputScale` (typically the max participating display
    /// scale) so Retina content stays sharp when mixed with 1x monitors.
    public static func stitch(
        slices: [MultiDisplayCaptureSlice],
        selectionSize: CGSize,
        outputScale: CGFloat
    ) -> CGImage? {
        guard !slices.isEmpty,
              selectionSize.width > 0,
              selectionSize.height > 0,
              outputScale > 0 else {
            return nil
        }

        if slices.count == 1,
           let only = slices.first,
           abs(only.originInSelection.x) < 0.5,
           abs(only.originInSelection.y) < 0.5,
           abs(only.sizeInPoints.width - selectionSize.width) < 0.5,
           abs(only.sizeInPoints.height - selectionSize.height) < 0.5 {
            return only.image
        }

        let canvasWidth = max(1, Int((selectionSize.width * outputScale).rounded()))
        let canvasHeight = max(1, Int((selectionSize.height * outputScale).rounded()))
        let colorSpace = slices.first?.image.colorSpace ?? CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: canvasWidth,
            height: canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))

        for slice in slices {
            let drawRect = CGRect(
                x: slice.originInSelection.x * outputScale,
                y: slice.originInSelection.y * outputScale,
                width: slice.sizeInPoints.width * outputScale,
                height: slice.sizeInPoints.height * outputScale
            )
            context.interpolationQuality = slice.scale >= outputScale ? .default : .high
            context.draw(slice.image, in: drawRect)
        }

        return context.makeImage()
    }
}
