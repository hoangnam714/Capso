// Packages/CaptureKit/Tests/CaptureKitTests/ScrollStitcherTests.swift
import CoreGraphics
import Foundation
import Testing
@testable import CaptureKit

@Suite("ScrollStitcher")
struct ScrollStitcherTests {
    @Test("appends only the bottom strip for each offset")
    func appendsBottomStrip() throws {
        let stitcher = ScrollStitcher()
        let first = try makeFrame(width: 40, height: 60, topColor: 10, bottomColor: 20)
        stitcher.setInitialFrame(first)

        // Second frame: top matches previous bottom region conceptually; bottom is new.
        let second = try makeFrame(width: 40, height: 60, topColor: 20, bottomColor: 30)
        let result = stitcher.stitch(newFrame: second, detectedOffset: 20)
        guard case .stitched(let rows) = result else {
            Issue.record("Expected stitched result")
            return
        }
        #expect(rows == 20)
        #expect(stitcher.totalHeight == 80)
        #expect(stitcher.mergedImage?.width == 40)
        #expect(stitcher.mergedImage?.height == 80)
    }

    @Test("cropChrome removes trailing scrollbar using bottom-left coords")
    func cropScrollbar() throws {
        let image = try makeFrame(width: 50, height: 40, topColor: 1, bottomColor: 2)
        let cropped = try #require(ScrollStitcher.cropChrome(image, headerHeight: 0, scrollbarWidth: 10))
        #expect(cropped.width == 40)
        #expect(cropped.height == 40)
    }

    @Test("cropChrome removes sticky header from the visual top")
    func cropHeader() throws {
        let image = try makeFrame(width: 40, height: 50, topColor: 9, bottomColor: 4)
        // Visual top sticky header of 10px → keep bottom 40 rows (y=0..<40 in CG coords).
        let cropped = try #require(ScrollStitcher.cropChrome(image, headerHeight: 10, scrollbarWidth: 0))
        #expect(cropped.width == 40)
        #expect(cropped.height == 40)
    }

    private func makeFrame(width: Int, height: Int, topColor: UInt8, bottomColor: UInt8) throws -> CGImage {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        // Fill assuming top-down buffer for the test pattern; CGImage still
        // stores with bottom-left crop semantics for cropping(to:).
        for y in 0..<height {
            let isTopHalf = y < height / 2
            let color = isTopHalf ? topColor : bottomColor
            for x in 0..<width {
                let i = y * bytesPerRow + x * bytesPerPixel
                data[i] = color
                data[i + 1] = color
                data[i + 2] = color
                data[i + 3] = 255
            }
        }
        let provider = try #require(CGDataProvider(data: Data(data) as CFData))
        let image = try #require(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        return image
    }
}
