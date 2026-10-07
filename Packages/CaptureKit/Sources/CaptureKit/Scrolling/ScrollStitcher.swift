// Packages/CaptureKit/Sources/CaptureKit/Scrolling/ScrollStitcher.swift
import CoreGraphics
import AppKit

public enum StitchResult: Sendable {
    case stitched(yOffset: Int)
    case noChange
    case reversedScroll
    case alignmentFailed
}

/// Incrementally stitches captured frames into a single tall image.
///
/// Algorithm (downward scroll):
/// 1. Grow the canvas by `detectedOffset` rows.
/// 2. Draw the previous merged image in the upper portion of the canvas.
/// 3. Append the bottom `detectedOffset` rows of the new frame in the lower portion.
///
/// Because in `CGImage` origin (0, 0) is top-left, the newly revealed content at the bottom
/// of the viewport is at row (frameHeight - detectedOffset) ... frameHeight.
public final class ScrollStitcher: @unchecked Sendable {
    private(set) var mergedImage: CGImage?
    private(set) var headerHeight: Int = 0
    private(set) var scrollbarWidth: Int = 0
    private(set) var totalHeight: Int = 0
    private var chromeApplied = false

    public init() {}

    public func setInitialFrame(_ frame: CGImage) {
        mergedImage = frame
        totalHeight = frame.height
        headerHeight = 0
        scrollbarWidth = 0
        chromeApplied = false
    }

    /// Apply sticky-chrome insets discovered by the capture loop (once).
    public func applyChrome(headerHeight: Int, scrollbarWidth: Int) {
        guard !chromeApplied else { return }
        self.headerHeight = max(0, headerHeight)
        self.scrollbarWidth = max(0, scrollbarWidth)
        chromeApplied = true
    }

    /// Stitch a new frame with a pre-computed offset.
    /// `detectedOffset` is the number of **new** pixel rows at the bottom (always positive).
    public func stitch(newFrame: CGImage, detectedOffset: Int) -> StitchResult {
        guard let baseMerged = mergedImage else {
            setInitialFrame(newFrame)
            return .stitched(yOffset: 0)
        }

        guard detectedOffset > 0 else { return .noChange }

        let frameHeight = newFrame.height
        let maxAppend = max(1, frameHeight - headerHeight - 1)
        let clampedRows = min(detectedOffset, maxAppend)
        guard clampedRows > 0 else { return .noChange }

        let mergedWidth = min(baseMerged.width, newFrame.width)
        let newMergedHeight = totalHeight + clampedRows

        guard let ctx = CGContext(
            data: nil,
            width: mergedWidth,
            height: newMergedHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: baseMerged.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return .alignmentFailed
        }

        // In CGContext, (0, 0) is bottom-left:
        // Upper canvas (y = clampedRows ..< newMergedHeight): previous merged image
        // Lower canvas (y = 0 ..< clampedRows): new bottom strip
        ctx.draw(baseMerged, in: CGRect(
            x: 0,
            y: clampedRows,
            width: mergedWidth,
            height: totalHeight
        ))

        // In CGImage, origin (0, 0) is top-left.
        // The bottom `clampedRows` of the new frame are at y = frameHeight - clampedRows!
        guard let strip = newFrame.cropping(to: CGRect(
            x: 0,
            y: frameHeight - clampedRows,
            width: mergedWidth,
            height: clampedRows
        )) else {
            return .alignmentFailed
        }

        ctx.draw(strip, in: CGRect(
            x: 0,
            y: 0,
            width: mergedWidth,
            height: clampedRows
        ))

        guard let result = ctx.makeImage() else {
            return .alignmentFailed
        }

        self.mergedImage = result
        self.totalHeight = newMergedHeight
        return .stitched(yOffset: clampedRows)
    }

    /// Crop content used for Vision registration (exclude sticky header + scrollbar).
    /// In CGImage (top-left origin), the sticky header is at the top (y = 0..<headerHeight).
    /// To exclude it, we crop starting at y = headerHeight!
    public static func cropForRegistration(
        _ image: CGImage,
        headerHeight: Int,
        scrollbarWidth: Int
    ) -> CGImage {
        let width = image.width - max(0, scrollbarWidth)
        let height = image.height - max(0, headerHeight)
        guard width > 40, height > 40 else { return image }
        if width == image.width && headerHeight == 0 { return image }

        return image.cropping(to: CGRect(
            x: 0,
            y: max(0, headerHeight),
            width: width,
            height: height
        )) ?? image
    }
}
