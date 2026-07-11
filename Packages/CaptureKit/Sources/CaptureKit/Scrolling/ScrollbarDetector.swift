// Packages/CaptureKit/Sources/CaptureKit/Scrolling/ScrollbarDetector.swift
import CoreGraphics

/// Detects scrollbar width on the right edge of captured frames using
/// Sum of Absolute Differences (SAD). The scrollbar thumb moves independently
/// of content and would confuse the Vision offset detector if not cropped.
enum ScrollbarDetector {
    /// Number of columns to scan from the right edge.
    private static let scanColumns = 50
    /// Number of rows to sample per column (across middle 60% of image).
    private static let sampleRows = 40
    /// SAD threshold below which a column is considered static (window chrome, not scrollbar).
    private static let staticThreshold: CGFloat = 8

    /// Detect the scrollbar width by comparing two consecutive frames.
    /// Returns the number of pixel columns to crop from the right edge.
    static func detectScrollbarWidth(frame1: CGImage, frame2: CGImage) -> Int {
        let width = min(frame1.width, frame2.width)
        let height = min(frame1.height, frame2.height)
        guard width > scanColumns, height > sampleRows else { return 0 }

        guard let data1 = frame1.dataProvider?.data,
              let data2 = frame2.dataProvider?.data else { return 0 }

        let ptr1 = CFDataGetBytePtr(data1)!
        let ptr2 = CFDataGetBytePtr(data2)!
        let bpr1 = frame1.bytesPerRow
        let bpr2 = frame2.bytesPerRow
        let bpp = frame1.bitsPerPixel / 8

        // Sample rows in the middle 60% of the image
        let startRow = Int(Double(height) * 0.2)
        let endRow = Int(Double(height) * 0.8)
        let rowStep = max(1, (endRow - startRow) / sampleRows)

        var scrollbarStart = width // no scrollbar by default

        // Scan columns from right edge inward
        for colOffset in 0..<min(scanColumns, width) {
            let col = width - 1 - colOffset
            var totalDiff: CGFloat = 0
            var sampleCount = 0

            var row = startRow
            while row < endRow {
                let offset1 = row * bpr1 + col * bpp
                let offset2 = row * bpr2 + col * bpp

                // Compare RGB channels
                let dr = abs(Int(ptr1[offset1]) - Int(ptr2[offset2]))
                let dg = abs(Int(ptr1[offset1 + 1]) - Int(ptr2[offset2 + 1]))
                let db = abs(Int(ptr1[offset1 + 2]) - Int(ptr2[offset2 + 2]))
                totalDiff += CGFloat(dr + dg + db) / 3.0
                sampleCount += 1
                row += rowStep
            }

            let avgDiff = sampleCount > 0 ? totalDiff / CGFloat(sampleCount) : 0

            if avgDiff > staticThreshold {
                // This column has changing content — likely scrollbar or real content
                scrollbarStart = col
            } else if scrollbarStart < width {
                // We found static columns after scrollbar columns — this is the boundary
                break
            }
        }

        let scrollbarWidth = width - scrollbarStart
        // Only crop if we detected a reasonable scrollbar width (4-30px)
        return (scrollbarWidth >= 4 && scrollbarWidth <= 60) ? scrollbarWidth : 0
    }
}
