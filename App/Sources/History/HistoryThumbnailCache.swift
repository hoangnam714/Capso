import AppKit
import ImageIO

/// Shared, downsampled history thumbnails loaded off the main thread.
enum HistoryThumbnailCache {
    // NSCache is thread-safe; mark unsafe for Swift 6 static Sendable checks.
    nonisolated(unsafe) private static let cache = NSCache<NSURL, NSImage>()
    /// Display size ≈ 165pt cell @2x, with a little headroom.
    private static let maxPixelSize = 360

    static func image(for url: URL) async -> NSImage? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let maxSize = maxPixelSize
        let image: NSImage? = await Task.detached(priority: .utility) {
            downsample(url: url, maxPixelSize: maxSize)
        }.value

        if let image {
            cache.setObject(image, forKey: key)
        }
        return image
    }

    static func remove(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }

    private static func downsample(url: URL, maxPixelSize: Int) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
