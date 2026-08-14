import Testing
import Foundation
import CoreGraphics
@testable import AnnotationKit

@Suite("AnnotationRenderer crop")
struct AnnotationRendererCropTests {
    @Test("cropRect uses top-left image coordinates without Y flip")
    func cropKeepsTopLeftRegion() throws {
        // Top half red, bottom half blue — in top-left image space.
        let source = try makeTopBottomImage(
            width: 16,
            height: 16,
            top: CGColor(red: 1, green: 0, blue: 0, alpha: 1),
            bottom: CGColor(red: 0, green: 0, blue: 1, alpha: 1)
        )

        let crop = CGRect(x: 0, y: 0, width: 16, height: 8)
        let rendered = try #require(
            AnnotationRenderer.render(sourceImage: source, objects: [], cropRect: crop)
        )

        #expect(rendered.width == 16)
        #expect(rendered.height == 8)

        // If Y were incorrectly flipped, this crop would return the blue half.
        #expect(sampleTopLeftRGBA(rendered, x: 4, y: 4) == RGBA(r: 255, g: 0, b: 0, a: 255))
    }
}

private struct RGBA: Equatable {
    let r, g, b, a: UInt8
}

/// Builds an image whose top half (y=0…h/2 in top-left space) is `top` and bottom is `bottom`.
private func makeTopBottomImage(
    width: Int,
    height: Int,
    top: CGColor,
    bottom: CGColor
) throws -> CGImage {
    let context = try #require(
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    )
    // Default CGContext: y=0 is bottom. Paint image-top (red) at high CG y.
    context.setFillColor(bottom)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
    context.setFillColor(top)
    context.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))
    return try #require(context.makeImage())
}

private func sampleTopLeftRGBA(_ image: CGImage, x: Int, y: Int) -> RGBA {
    let context = CGContext(
        data: nil,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // Draw so (x,y) in top-left image space lands on the 1×1 context.
    context.draw(
        image,
        in: CGRect(
            x: -x,
            y: -(image.height - 1 - y),
            width: image.width,
            height: image.height
        )
    )
    let data = context.data!.assumingMemoryBound(to: UInt8.self)
    return RGBA(r: data[0], g: data[1], b: data[2], a: data[3])
}
