// Packages/CaptureKit/Sources/CaptureKit/Scrolling/HeaderDetector.swift
import CoreGraphics

/// Detects sticky/frozen headers at the top of captured frames by comparing
/// pixel rows between two consecutive frames when scrolling is active.
/// Rows that remain identical in both frames despite scrolling are part of a sticky header.
enum HeaderDetector {
    /// Maximum percentage of image height to scan for headers (e.g. 25%).
    private static let maxScanPercent = 0.25
    /// Number of columns to sample per row for comparison.
    private static let sampleColumns = 30
    /// Per-pixel difference tolerance (accounts for sub-pixel antialiasing/noise).
    private static let tolerance: Int = 12

    /// Detect the sticky header height by comparing two frames where scrolling has occurred.
    /// Returns the number of pixel rows at the top that are identical (frozen).
    static func detectHeaderHeight(frame1: CGImage, frame2: CGImage, scrollbarWidth: Int = 0) -> Int {
        let width = min(frame1.width, frame2.width)
        let height = min(frame1.height, frame2.height)
        let maxScanRows = Int(Double(height) * maxScanPercent)
        guard width > sampleColumns + 40, maxScanRows > 0 else { return 0 }

        guard let data1 = frame1.dataProvider?.data,
              let data2 = frame2.dataProvider?.data else { return 0 }

        guard let ptr1 = CFDataGetBytePtr(data1),
              let ptr2 = CFDataGetBytePtr(data2) else { return 0 }

        let bpr1 = frame1.bytesPerRow
        let bpr2 = frame2.bytesPerRow
        let bpp1 = frame1.bitsPerPixel / 8
        let bpp2 = frame2.bitsPerPixel / 8
        guard bpp1 >= 3, bpp2 >= 3 else { return 0 }

        // Avoid scrollbar on right and potential window border on left
        let startCol = 20
        let endCol = width - max(scrollbarWidth, 40)
        guard endCol > startCol + sampleColumns else { return 0 }

        let colStep = max(1, (endCol - startCol) / sampleColumns)
        var detectedHeader = 0
        var consecutiveFailures = 0

        for row in 0..<maxScanRows {
            var matchCount = 0
            var sampleCount = 0
            var col = startCol

            while col < endCol {
                let offset1 = row * bpr1 + col * bpp1
                let offset2 = row * bpr2 + col * bpp2

                let dr = abs(Int(ptr1[offset1]) - Int(ptr2[offset2]))
                let dg = abs(Int(ptr1[offset1 + 1]) - Int(ptr2[offset2 + 1]))
                let db = abs(Int(ptr1[offset1 + 2]) - Int(ptr2[offset2 + 2]))

                if dr <= tolerance && dg <= tolerance && db <= tolerance {
                    matchCount += 1
                }
                sampleCount += 1
                col += colStep
            }

            // A row is considered matching if >= 85% of sample points match
            let matchRatio = sampleCount > 0 ? Double(matchCount) / Double(sampleCount) : 0
            if matchRatio >= 0.85 {
                consecutiveFailures = 0
                detectedHeader = row + 1
            } else {
                consecutiveFailures += 1
                if consecutiveFailures >= 2 {
                    break
                }
            }
        }

        // If the detected header is very small (< 15px), it's likely just window chrome or padding, ignore
        return detectedHeader >= 15 ? detectedHeader : 0
    }
}
