// Packages/SharedKit/Sources/SharedKit/Utilities/ImageUtilities.swift
import AppKit
import CoreGraphics
import ImageIO

public enum ImageUtilities {
    public static func nsImage(from cgImage: CGImage) -> NSImage {
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
    }

    public static func cgImage(from nsImage: NSImage) -> CGImage? {
        if let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cgImage
        }
        return rasterizedCGImage(from: nsImage)
    }

    /// Reads the first image on the pasteboard, including PNG/JPEG/TIFF and file URLs
    /// from external apps (Finder, browsers, Preview, etc.).
    public static func cgImageFromPasteboard(_ pasteboard: NSPasteboard = .general) -> CGImage? {
        for item in pasteboard.pasteboardItems ?? [] {
            if let cgImage = cgImage(fromPasteboardItem: item) {
                return cgImage
            }
        }

        if let objects = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            for image in objects {
                if let cgImage = cgImage(from: image) {
                    return cgImage
                }
            }
        }

        for type in Self.legacyPasteboardImageTypes {
            guard let data = pasteboard.data(forType: type),
                  let cgImage = cgImage(fromImageData: data) else { continue }
            return cgImage
        }

        return nil
    }

    private static let legacyPasteboardImageTypes: [NSPasteboard.PasteboardType] = [
        .png,
        NSPasteboard.PasteboardType("public.png"),
        .tiff,
        NSPasteboard.PasteboardType("public.tiff"),
        NSPasteboard.PasteboardType("public.jpeg"),
        NSPasteboard.PasteboardType("JPEG"),
        NSPasteboard.PasteboardType("public.image"),
        NSPasteboard.PasteboardType("com.compuserve.gif"),
        NSPasteboard.PasteboardType("public.heic"),
        NSPasteboard.PasteboardType("public.heif"),
    ]

    private static func cgImage(fromPasteboardItem item: NSPasteboardItem) -> CGImage? {
        let availableTypes = Set(item.types)

        for type in legacyPasteboardImageTypes where availableTypes.contains(type) {
            guard let data = item.data(forType: type),
                  let cgImage = cgImage(fromImageData: data) else { continue }
            return cgImage
        }

        if availableTypes.contains(.fileURL),
           let urlString = item.string(forType: .fileURL),
           let url = URL(string: urlString),
           let cgImage = cgImage(fromFileURL: url) {
            return cgImage
        }

        return nil
    }

    private static func cgImage(fromImageData data: Data) -> CGImage? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return cgImage
        }

        if let rep = NSBitmapImageRep(data: data) {
            return rep.cgImage
        }

        if let image = NSImage(data: data) {
            return cgImage(from: image)
        }

        return nil
    }

    private static func cgImage(fromFileURL url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return cgImage(fromImageData: data)
    }

    private static func rasterizedCGImage(from nsImage: NSImage) -> CGImage? {
        var proposedRect = CGRect(origin: .zero, size: nsImage.size)
        if let cgImage = nsImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            return cgImage
        }

        if let rep = nsImage.representations.first as? NSBitmapImageRep,
           let cgImage = rep.cgImage {
            return cgImage
        }

        let pixelSize = pixelSize(for: nsImage)
        guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize.width,
            pixelsHigh: pixelSize.height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        nsImage.draw(
            in: NSRect(x: 0, y: 0, width: pixelSize.width, height: pixelSize.height),
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    private static func pixelSize(for nsImage: NSImage) -> (width: Int, height: Int) {
        if let rep = nsImage.representations.first as? NSBitmapImageRep,
           rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return (rep.pixelsWide, rep.pixelsHigh)
        }

        let size = nsImage.size
        let width = max(Int(size.width.rounded()), 1)
        let height = max(Int(size.height.rounded()), 1)
        return (width, height)
    }

    public static func pngData(from cgImage: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }

    public static func jpegData(from cgImage: CGImage, quality: Double = 0.85) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    public static func dimensionString(for cgImage: CGImage) -> String {
        "\(cgImage.width) x \(cgImage.height)"
    }

    public static func scaled(_ cgImage: CGImage, maxWidth: Int, maxHeight: Int) -> CGImage? {
        let widthRatio = Double(maxWidth) / Double(cgImage.width)
        let heightRatio = Double(maxHeight) / Double(cgImage.height)
        let scale = min(widthRatio, heightRatio, 1.0)

        let newWidth = Int(Double(cgImage.width) * scale)
        let newHeight = Int(Double(cgImage.height) * scale)

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: cgImage.bitsPerComponent,
            bytesPerRow: 0,
            space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: cgImage.bitmapInfo.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }

    public static func resized(_ cgImage: CGImage, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
