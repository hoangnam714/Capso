// Packages/AnnotationKit/Tests/AnnotationKitTests/AnnotationPersistenceTests.swift
import Testing
import Foundation
import CoreGraphics
@testable import AnnotationKit

private func makeSolidImage(width: Int, height: Int) -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}

@Suite("AnnotationPersistence")
struct AnnotationPersistenceTests {
    @Test("Sidecar round-trips all object kinds")
    @MainActor
    func sidecarRoundTrip() throws {
        let doc = AnnotationDocument(imageSize: CGSize(width: 640, height: 480))
        doc.addObject(ArrowObject(
            start: CGPoint(x: 10, y: 20),
            end: CGPoint(x: 100, y: 120),
            style: StrokeStyle(color: .red, lineWidth: 4, pattern: .dashed)
        ))
        doc.addObject(LineObject(
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 50, y: 50),
            style: StrokeStyle(color: .blue, lineWidth: 2)
        ))
        doc.addObject(RectangleObject(
            rect: CGRect(x: 30, y: 40, width: 80, height: 60),
            style: StrokeStyle(color: .green, filled: true)
        ))
        doc.addObject(EllipseObject(
            rect: CGRect(x: 5, y: 5, width: 40, height: 20)
        ))
        doc.addObject(TextObject(
            text: "Hello",
            origin: CGPoint(x: 12, y: 34),
            fontSize: 18,
            fontName: "Helvetica",
            fillColor: .yellow,
            isBold: true,
            isItalic: true,
            isUnderline: true,
            alignment: .right
        ))
        let embedded = try #require(makeSolidImage(width: 16, height: 12))
        doc.addObject(try #require(ImageObject(
            cgImage: embedded,
            rect: CGRect(x: 50, y: 60, width: 40, height: 30)
        )))
        doc.addObject(FreehandObject(
            points: [CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4), CGPoint(x: 5, y: 6)],
            style: StrokeStyle(color: .orange, lineWidth: 5, opacity: 0.5)
        ))
        doc.addObject(PixelateObject(
            rect: CGRect(x: 100, y: 100, width: 64, height: 32),
            blockSize: 8,
            mode: .blur
        ))
        doc.addObject(CounterObject(
            center: CGPoint(x: 200, y: 150),
            number: 1,
            radius: 18
        ))
        doc.addObject(CounterObject(
            center: CGPoint(x: 240, y: 150),
            number: 2,
            radius: 18
        ))
        doc.setCropRect(CGRect(x: 10, y: 10, width: 400, height: 300))

        let data = try doc.exportSidecar().encoded()
        let decoded = try AnnotationSidecar.decode(from: data)

        let restored = AnnotationDocument(imageSize: .zero)
        restored.loadSidecar(decoded)

        #expect(restored.imageSize == CGSize(width: 640, height: 480))
        #expect(restored.cropRect == CGRect(x: 10, y: 10, width: 400, height: 300))
        #expect(restored.objects.count == 10)

        let arrow = try #require(restored.objects[0] as? ArrowObject)
        #expect(arrow.start == CGPoint(x: 10, y: 20))
        #expect(arrow.end == CGPoint(x: 100, y: 120))
        #expect(arrow.style.lineWidth == 4)
        #expect(arrow.style.pattern == .dashed)

        let text = try #require(restored.objects[4] as? TextObject)
        #expect(text.text == "Hello")
        #expect(text.fontSize == 18)
        #expect(text.isBold == true)
        #expect(text.isItalic == true)
        #expect(text.isUnderline == true)
        #expect(text.alignment == .right)

        let image = try #require(restored.objects[5] as? ImageObject)
        #expect(image.rect == CGRect(x: 50, y: 60, width: 40, height: 30))
        #expect(image.cgImage?.width == 16)
        #expect(image.cgImage?.height == 12)

        let pixelate = try #require(restored.objects[7] as? PixelateObject)
        #expect(pixelate.mode == .blur)
        #expect(pixelate.blockSize == 8)

        let counter1 = try #require(restored.objects[8] as? CounterObject)
        let counter2 = try #require(restored.objects[9] as? CounterObject)
        #expect(counter1.number == 1)
        #expect(counter2.number == 2)
    }

    @Test("loadSidecar does not renumber counters")
    @MainActor
    func loadSidecarPreservesCounterNumbers() throws {
        let counter = CounterObject(center: CGPoint(x: 10, y: 10), number: 7, radius: 12)
        let sidecar = AnnotationSidecar(
            imageSize: CGSize(width: 100, height: 100),
            objects: [counter]
        )
        let doc = AnnotationDocument(imageSize: CGSize(width: 100, height: 100))
        doc.loadSidecar(sidecar)
        let restored = try #require(doc.objects.first as? CounterObject)
        #expect(restored.number == 7)
    }
}
