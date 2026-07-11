import AppKit
import CoreGraphics
import Testing
@testable import SharedKit

@Suite("ImageUtilities")
struct ImageUtilitiesTests {
    @Test("Exact resize creates requested pixel dimensions")
    func exactResizeCreatesRequestedPixelDimensions() throws {
        let image = try makeSolidImage(width: 12, height: 8, color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))

        let resized = try #require(ImageUtilities.resized(image, width: 5, height: 7))

        #expect(resized.width == 5)
        #expect(resized.height == 7)
    }

    @Test("Exact resize can upscale")
    func exactResizeCanUpscale() throws {
        let image = try makeSolidImage(width: 4, height: 4, color: CGColor(red: 0, green: 0, blue: 1, alpha: 1))

        let resized = try #require(ImageUtilities.resized(image, width: 9, height: 6))

        #expect(resized.width == 9)
        #expect(resized.height == 6)
    }

    @Test("Pasteboard reader decodes PNG and JPEG payloads")
    func pasteboardReaderDecodesCommonFormats() throws {
        let pngImage = try makeSolidImage(width: 8, height: 6, color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        let jpegImage = try makeSolidImage(width: 10, height: 7, color: CGColor(red: 0, green: 1, blue: 0, alpha: 1))

        let pngData = try #require(ImageUtilities.pngData(from: pngImage))
        let jpegData = try #require(ImageUtilities.jpegData(from: jpegImage))

        let pngItem = NSPasteboardItem()
        pngItem.setData(pngData, forType: .png)
        let pngPasteboard = NSPasteboard.withUniqueName()
        pngPasteboard.writeObjects([pngItem])
        let decodedPNG = try #require(ImageUtilities.cgImageFromPasteboard(pngPasteboard))
        #expect(decodedPNG.width == 8)
        #expect(decodedPNG.height == 6)

        let jpegItem = NSPasteboardItem()
        jpegItem.setData(jpegData, forType: NSPasteboard.PasteboardType("public.jpeg"))
        let jpegPasteboard = NSPasteboard.withUniqueName()
        jpegPasteboard.writeObjects([jpegItem])
        let decodedJPEG = try #require(ImageUtilities.cgImageFromPasteboard(jpegPasteboard))
        #expect(decodedJPEG.width == 10)
        #expect(decodedJPEG.height == 7)
    }
}

private func makeSolidImage(width: Int, height: Int, color: CGColor) throws -> CGImage {
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(color)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(context.makeImage())
}
