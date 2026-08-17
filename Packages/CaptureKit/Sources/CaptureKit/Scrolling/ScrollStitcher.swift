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
/// Algorithm (downward scroll only):
/// 1. Grow the canvas by `detectedOffset` rows.
/// 2. Draw the previous merged image shifted up.
/// 3. Append **only** the bottom `detectedOffset` rows of the new frame.
///
/// Appending the bottom strip (instead of redrawing the whole frame) avoids
/// duplicating sticky headers and keeps overlap pixel-perfect.
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
    /// Crops the trailing scrollbar from the current merged image.
    public func applyChrome(headerHeight: Int, scrollbarWidth: Int) {
        guard !chromeApplied else { return }
        self.headerHeight = max(0, headerHeight)
        self.scrollbarWidth = max(0, scrollbarWidth)
        chromeApplied = true

        guard scrollbarWidth > 0, let merged = mergedImage,
              let cropped = Self.cropChrome(
                merged,
                headerHeight: 0,
                scrollbarWidth: scrollbarWidth
              ) else {
            return
        }
        mergedImage = cropped
        totalHeight = cropped.height
    }

    /// Stitch a new frame with a pre-computed offset (from Vision).
    /// `detectedOffset` is the number of **new** pixel rows at the bottom (always positive).
    public func stitch(newFrame: CGImage, detectedOffset: Int) -> StitchResult {
        guard let baseMerged = mergedImage else {
            setInitialFrame(newFrame)
            return .stitched(yOffset: 0)
        }

        guard detectedOffset > 0 else { return .noChange }

        let preparedNew = Self.cropChrome(
            newFrame,
            headerHeight: 0,
            scrollbarWidth: scrollbarWidth
        ) ?? newFrame

        let frameHeight = preparedNew.height
        let maxAppend = max(1, frameHeight - 1)
        let clampedRows = min(detectedOffset, maxAppend)
        guard clampedRows > 0 else { return .noChange }

        let mergedWidth = min(baseMerged.width, preparedNew.width)
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

        // CGContext / CGImage crop origin is bottom-left.
        // Canvas:
        //   top    → previous merged (shifted up by clampedRows)
        //   bottom → only the NEW strip from this frame
        ctx.draw(baseMerged, in: CGRect(
            x: 0,
            y: clampedRows,
            width: mergedWidth,
            height: totalHeight
        ))

        // Bottom `clampedRows` of the new frame = freshly scrolled-in content.
        guard let strip = preparedNew.cropping(to: CGRect(
            x: 0,
            y: 0,
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

    /// Crop a trailing scrollbar and/or leading sticky header from a frame.
    /// Header crop uses bottom-left CGImage coords: keep y=0..<height-header
    /// (content below the visual top sticky header).
    public static func cropChrome(
        _ image: CGImage,
        headerHeight: Int,
        scrollbarWidth: Int
    ) -> CGImage? {
        let width = image.width - max(0, scrollbarWidth)
        let height = image.height - max(0, headerHeight)
        guard width > 0, height > 0 else { return nil }
        if width == image.width && height == image.height { return image }

        return image.cropping(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    /// Crop content used for Vision registration (exclude sticky header + scrollbar).
    public static func cropForRegistration(
        _ image: CGImage,
        headerHeight: Int,
        scrollbarWidth: Int
    ) -> CGImage {
        cropChrome(image, headerHeight: headerHeight, scrollbarWidth: scrollbarWidth) ?? image
    }
}
