// Packages/CaptureKit/Sources/CaptureKit/Scrolling/ScrollbarDetector.swift
import CoreGraphics

/// Detects scrollbar width on the right edge of captured frames using
/// Sum of Absolute Differences (SAD).
enum ScrollbarDetector {
    private static let scanColumns = 36
    private static let sampleRows = 30
    private static let staticThreshold: CGFloat = 10

    static func detectScrollbarWidth(frame1: CGImage, frame2: CGImage) -> Int {
        let width = min(frame1.width, frame2.width)
        let height = min(frame1.height, frame2.height)
        guard width > scanColumns, height > sampleRows else { return 0 }

        guard let data1 = frame1.dataProvider?.data,
              let data2 = frame2.dataProvider?.data else { return 0 }

        guard let ptr1 = CFDataGetBytePtr(data1),
              let ptr2 = CFDataGetBytePtr(data2) else { return 0 }

        let bpr1 = frame1.bytesPerRow
        let bpr2 = frame2.bytesPerRow
        let bpp = frame1.bitsPerPixel / 8
        guard bpp >= 3 else { return 0 }

        let startRow = Int(Double(height) * 0.25)
        let endRow = Int(Double(height) * 0.75)
        let rowStep = max(1, (endRow - startRow) / sampleRows)

        var detectedWidth = 0

        // Scan columns from right edge inward up to 26px
        for colOffset in 0..<min(26, width) {
            let col = width - 1 - colOffset
            var totalDiff: CGFloat = 0
            var sampleCount = 0

            var row = startRow
            while row < endRow {
                let offset1 = row * bpr1 + col * bpp
                let offset2 = row * bpr2 + col * bpp

                let dr = abs(Int(ptr1[offset1]) - Int(ptr2[offset2]))
                let dg = abs(Int(ptr1[offset1 + 1]) - Int(ptr2[offset2 + 1]))
                let db = abs(Int(ptr1[offset1 + 2]) - Int(ptr2[offset2 + 2]))
                totalDiff += CGFloat(dr + dg + db) / 3.0
                sampleCount += 1
                row += rowStep
            }

            let avgDiff = sampleCount > 0 ? totalDiff / CGFloat(sampleCount) : 0
            if avgDiff > staticThreshold {
                detectedWidth = colOffset + 1
            }
        }

        return (detectedWidth >= 6 && detectedWidth <= 26) ? detectedWidth : 0
    }
}
