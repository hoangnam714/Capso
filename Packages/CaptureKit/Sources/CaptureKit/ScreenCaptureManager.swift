import Foundation
import CoreGraphics
@preconcurrency import ScreenCaptureKit

/// Core screenshot capture engine wrapping ScreenCaptureKit.
public enum ScreenCaptureManager {

    // MARK: - Fullscreen Capture

    public static func captureFullscreen(
        displayID: CGDirectDisplayID = CGMainDisplayID(),
        showsCursor: Bool = false
    ) async throws -> CaptureResult {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == displayID })
            ?? content.displays.first(where: { $0.displayID == CGMainDisplayID() })
            ?? content.displays.first else {
            throw CaptureError.noDisplayFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        // Use the display's actual point-to-pixel scale rather than hardcoding
        // @2x — otherwise a non-Retina external monitor gets captured at 2x its
        // native resolution (blurry upscale), and if Apple ever ships a @3x
        // display we silently under-sample.
        let scaleFactor = CGFloat(filter.pointPixelScale)
        config.width = Int(CGFloat(display.width) * scaleFactor)
        config.height = Int(CGFloat(display.height) * scaleFactor)
        config.captureResolution = .best
        config.showsCursor = showsCursor

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        return CaptureResult(
            image: image,
            mode: .fullscreen,
            captureRect: display.frame,
            displayID: display.displayID
        )
    }

    // MARK: - Window Capture

    public static func captureWindow(
        windowID: CGWindowID,
        includeShadow: Bool = true,
        showsCursor: Bool = false
    ) async throws -> CaptureResult {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound(windowID)
        }

        // Find which display this window is on (needed for displayID metadata
        // and for the no-shadow display-based capture path).
        let windowCenter = CGPoint(x: scWindow.frame.midX, y: scWindow.frame.midY)
        guard let display = content.displays.first(where: { $0.frame.contains(windowCenter) })
            ?? content.displays.first else {
            throw CaptureError.noDisplayFound
        }

        let filter: SCContentFilter
        let config = SCStreamConfiguration()
        config.captureResolution = .best
        config.showsCursor = showsCursor

        if includeShadow {
            // Desktop-independent window filter: ScreenCaptureKit renders the
            // window with its shadow on a transparent background. The filter's
            // contentRect automatically includes the shadow bounds.
            filter = SCContentFilter(desktopIndependentWindow: scWindow)
            config.ignoreShadowsSingleWindow = false
            let scaleFactor = CGFloat(filter.pointPixelScale)
            config.width = Int(filter.contentRect.width * scaleFactor)
            config.height = Int(filter.contentRect.height * scaleFactor)
        } else {
            // Display-based capture including only this window, cropped to the
            // window frame. This avoids the shadow and renders GPU content
            // in-place on the display (no distortion).
            filter = SCContentFilter(display: display, including: [scWindow])

            // `config.sourceRect` must be in the content filter's LOCAL
            // coordinate space — relative to the display's top-left at (0,0).
            var localRect = CGRect(
                x: scWindow.frame.origin.x - display.frame.origin.x,
                y: scWindow.frame.origin.y - display.frame.origin.y,
                width: scWindow.frame.width,
                height: scWindow.frame.height
            )
            let displayBounds = CGRect(x: 0, y: 0, width: display.frame.width, height: display.frame.height)
            localRect = localRect.intersection(displayBounds)
            guard !localRect.isEmpty else {
                throw CaptureError.captureFailed("Window is not visible on the target display")
            }
            config.sourceRect = localRect
            let scaleFactor = CGFloat(filter.pointPixelScale)
            config.width = Int(localRect.width * scaleFactor)
            config.height = Int(localRect.height * scaleFactor)
        }

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        return CaptureResult(
            image: image,
            mode: .window,
            captureRect: scWindow.frame,
            windowName: scWindow.title,
            appName: scWindow.owningApplication?.applicationName,
            appBundleIdentifier: scWindow.owningApplication?.bundleIdentifier,
            displayID: display.displayID
        )
    }

    // MARK: - Desktop Background Capture (for window shadow compositing)

    /// Capture the desktop behind a window (excluding the window itself),
    /// cropped to the window area with extra padding for the shadow region.
    public static func captureDesktopBehindWindow(
        windowID: CGWindowID,
        padding: CGFloat
    ) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound(windowID)
        }

        let windowCenter = CGPoint(x: scWindow.frame.midX, y: scWindow.frame.midY)
        guard let display = content.displays.first(where: { $0.frame.contains(windowCenter) })
            ?? content.displays.first else {
            throw CaptureError.noDisplayFound
        }

        // Capture the entire display EXCLUDING the target window.
        let filter = SCContentFilter(display: display, excludingWindows: [scWindow])
        let config = SCStreamConfiguration()
        config.captureResolution = .best
        config.showsCursor = false

        // Crop to the window area + padding, in display-local coordinates.
        var cropRect = CGRect(
            x: scWindow.frame.origin.x - display.frame.origin.x - padding,
            y: scWindow.frame.origin.y - display.frame.origin.y - padding,
            width: scWindow.frame.width + padding * 2,
            height: scWindow.frame.height + padding * 2
        )
        let displayBounds = CGRect(x: 0, y: 0, width: display.frame.width, height: display.frame.height)
        cropRect = cropRect.intersection(displayBounds)
        guard !cropRect.isEmpty else {
            throw CaptureError.captureFailed("Window background is not visible")
        }

        config.sourceRect = cropRect
        let scaleFactor = CGFloat(filter.pointPixelScale)
        config.width = Int(cropRect.width * scaleFactor)
        config.height = Int(cropRect.height * scaleFactor)

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
    }

    // MARK: - Area Capture

    public static func captureArea(
        rect: CGRect,
        displayID: CGDirectDisplayID = CGMainDisplayID(),
        showsCursor: Bool = false
    ) async throws -> CaptureResult {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplayFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.captureResolution = .best
        config.showsCursor = showsCursor
        config.sourceRect = rect
        let scaleFactor = CGFloat(filter.pointPixelScale)
        config.width = Int(rect.width * scaleFactor)
        config.height = Int(rect.height * scaleFactor)

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        return CaptureResult(
            image: image,
            mode: .area,
            captureRect: rect,
            displayID: displayID
        )
    }

    /// Capture one or more display-local regions and stitch them into a single
    /// image covering `selectionSize` (AppKit points). Used for area selections
    /// that span differently sized / scaled monitors.
    public static func captureMultiDisplayArea(
        targets: [DisplayAreaCaptureTarget],
        selectionSize: CGSize,
        showsCursor: Bool = false
    ) async throws -> CaptureResult {
        guard let primary = targets.first else {
            throw CaptureError.captureFailed("No display regions to capture")
        }

        if targets.count == 1 {
            return try await captureArea(
                rect: primary.sourceRect,
                displayID: primary.displayID,
                showsCursor: showsCursor
            )
        }

        var slices: [MultiDisplayCaptureSlice] = []
        slices.reserveCapacity(targets.count)

        for target in targets {
            let result = try await captureArea(
                rect: target.sourceRect,
                displayID: target.displayID,
                showsCursor: showsCursor
            )
            let scale: CGFloat
            if target.sizeInPoints.width > 0 {
                scale = CGFloat(result.image.width) / target.sizeInPoints.width
            } else {
                scale = 1
            }
            slices.append(
                MultiDisplayCaptureSlice(
                    image: result.image,
                    originInSelection: target.originInSelection,
                    sizeInPoints: target.sizeInPoints,
                    scale: scale
                )
            )
        }

        let outputScale = slices.map(\.scale).max() ?? 1
        guard let stitched = MultiDisplayImageStitcher.stitch(
            slices: slices,
            selectionSize: selectionSize,
            outputScale: outputScale
        ) else {
            throw CaptureError.captureFailed("Failed to stitch multi-display capture")
        }

        return CaptureResult(
            image: stitched,
            mode: .area,
            captureRect: CGRect(origin: .zero, size: selectionSize),
            displayID: primary.displayID
        )
    }
}

/// A display-local crop to include in a cross-monitor area capture.
public struct DisplayAreaCaptureTarget: Sendable {
    public let displayID: CGDirectDisplayID
    /// ScreenCaptureKit `sourceRect` in display-local top-left coordinates.
    public let sourceRect: CGRect
    /// Placement of this crop inside the global selection (AppKit points).
    public let originInSelection: CGPoint
    public let sizeInPoints: CGSize

    public init(
        displayID: CGDirectDisplayID,
        sourceRect: CGRect,
        originInSelection: CGPoint,
        sizeInPoints: CGSize
    ) {
        self.displayID = displayID
        self.sourceRect = sourceRect
        self.originInSelection = originInSelection
        self.sizeInPoints = sizeInPoints
    }
}

// MARK: - Errors

public enum CaptureError: Error, LocalizedError {
    case noDisplayFound
    case windowNotFound(CGWindowID)
    case capturePermissionDenied
    case captureFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noDisplayFound:
            return "No display found for capture."
        case .windowNotFound(let id):
            return "Window with ID \(id) not found."
        case .capturePermissionDenied:
            return "Screen recording permission is required."
        case .captureFailed(let reason):
            return "Capture failed: \(reason)"
        }
    }
}
