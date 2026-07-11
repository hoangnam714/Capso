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
/// The offset is detected externally (by ScrollCaptureController via Vision)
/// and passed in. This class only handles the pixel compositing.
public final class ScrollStitcher: @unchecked Sendable {
    private(set) var mergedImage: CGImage?
    private var previousFrame: CGImage?
    private(set) var headerHeight: Int = 0
    private(set) var scrollbarWidth: Int = 0
    private(set) var totalHeight: Int = 0
    private var isFirstStitch = true

    public init() {}

    public func setInitialFrame(_ frame: CGImage) {
        mergedImage = frame
        previousFrame = frame
        totalHeight = frame.height
        isFirstStitch = true
    }

    /// Stitch a new frame with a pre-computed offset (from Vision).
    /// `detectedOffset` is the absolute number of new pixel rows (always positive).
    public func stitch(newFrame: CGImage, detectedOffset: Int) -> StitchResult {
        guard let previousFrame, let mergedImage else {
            setInitialFrame(newFrame)
            return .stitched(yOffset: 0)
        }

        // Detect scrollbar and header on the first stitch only
        if isFirstStitch {
            scrollbarWidth = ScrollbarDetector.detectScrollbarWidth(
                frame1: previousFrame, frame2: newFrame
            )
            headerHeight = HeaderDetector.detectHeaderHeight(
                frame1: previousFrame, frame2: newFrame
            )
            isFirstStitch = false
        }

        let newRows = detectedOffset
        guard newRows > 0 else { return .noChange }

        let frameHeight = newFrame.height

        // If offset is larger than the frame, clamp to frame height
        // (this means the user scrolled past one full frame — no overlap)
        let clampedRows = min(newRows, frameHeight)

        let mergedWidth = mergedImage.width
        let newMergedHeight = totalHeight + clampedRows

        guard let ctx = CGContext(
            data: nil,
            width: mergedWidth,
            height: newMergedHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: mergedImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return .alignmentFailed
        }

        // CGContext origin is bottom-left.
        //
        // Canvas layout:
        //   top:    merged image (non-overlapping portion)
        //   bottom: entire new frame (covers overlap zone + new content)
        //
        // The overlap region is overwritten by the new frame's data,
        // which is pixel-perfect for the current scroll position.

        // 1. Draw existing merged image at the top
        ctx.draw(mergedImage, in: CGRect(
            x: 0,
            y: clampedRows,
            width: mergedWidth,
            height: totalHeight
        ))

        // 2. Prepare the new frame (exclude sticky header if detected)
        let drawFrame: CGImage
        let drawHeight: Int

        if headerHeight > 0 && headerHeight < frameHeight {
            // Crop header from the new frame
            let contentHeight = frameHeight - headerHeight
            if let cropped = newFrame.cropping(to: CGRect(
                x: 0, y: headerHeight, width: newFrame.width, height: contentHeight
            )) {
                drawFrame = cropped
                drawHeight = contentHeight
            } else {
                drawFrame = newFrame
                drawHeight = frameHeight
            }
        } else {
            drawFrame = newFrame
            drawHeight = frameHeight
        }

        // 3. Draw the entire new frame at the bottom of the canvas.
        //    This naturally overlaps with the merged image in the overlap zone,
        //    replacing it with the latest pixel data.
        ctx.draw(drawFrame, in: CGRect(
            x: 0,
            y: 0,
            width: mergedWidth,
            height: drawHeight
        ))

        if let result = ctx.makeImage() {
            self.mergedImage = result
            self.totalHeight = newMergedHeight
        }

        self.previousFrame = newFrame
        return .stitched(yOffset: clampedRows)
    }
}
