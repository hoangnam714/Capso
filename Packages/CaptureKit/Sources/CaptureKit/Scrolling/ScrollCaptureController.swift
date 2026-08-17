// Packages/CaptureKit/Sources/CaptureKit/Scrolling/ScrollCaptureController.swift
import CoreGraphics
import Foundation
import Vision
@preconcurrency import ScreenCaptureKit

public struct ScrollCaptureConfig: Sendable {
    public let captureRect: CGRect
    public let displayID: CGDirectDisplayID
    public let mode: ScrollMode
    public let maxHeight: Int

    public init(
        captureRect: CGRect,
        displayID: CGDirectDisplayID,
        mode: ScrollMode = .manual,
        maxHeight: Int = 30_000
    ) {
        self.captureRect = captureRect
        self.displayID = displayID
        self.mode = mode
        self.maxHeight = maxHeight
    }
}

public enum ScrollMode: Sendable {
    case auto
    case manual
}

public struct ScrollCaptureProgress: Sendable {
    public let currentHeight: Int
    public let maxHeight: Int
    public let frameCount: Int
}

public final class ScrollCaptureController: @unchecked Sendable {
    private enum FinishReason {
        case running
        case completed
        case cancelled
    }

    private let config: ScrollCaptureConfig
    private let stitcher = ScrollStitcher()
    private var isCancelled = false
    private var finishReason: FinishReason = .running
    private var frameCount = 0

    /// A/B frame model
    private var shotA: CGImage?

    /// Sticky chrome detected on first real scroll delta.
    private var headerHeight = 0
    private var scrollbarWidth = 0
    private var chromeDetected = false
    /// Once the user starts scrolling, lock that direction as "forward".
    /// `true` means Vision `ty < 0` is downward scroll (typical).
    private var forwardScrollIsNegativeTY: Bool?

    /// Cached ScreenCaptureKit objects (created once, reused)
    private var cachedFilter: SCContentFilter?
    private var cachedStreamConfig: SCStreamConfiguration?

    public var currentMergedImage: CGImage? { stitcher.mergedImage }

    public init(config: ScrollCaptureConfig) {
        self.config = config
    }

    public func start(
        onProgress: @escaping @Sendable (ScrollCaptureProgress) -> Void,
        onComplete: @escaping @Sendable (CGImage?) -> Void
    ) {
        Task.detached(priority: .utility) { [self] in
            let result = await self.runCaptureLoop(onProgress: onProgress)
            onComplete(result)
        }
    }

    /// User tapped Done — stop looping and return the stitched image.
    public func complete() {
        finishReason = .completed
        isCancelled = true
    }

    /// User cancelled — stop looping and discard the result.
    public func cancel() {
        finishReason = .cancelled
        isCancelled = true
    }

    /// Legacy alias for `complete()` (Done).
    public func stop() {
        complete()
    }

    // MARK: - Capture Loop

    private func runCaptureLoop(
        onProgress: @escaping @Sendable (ScrollCaptureProgress) -> Void
    ) async -> CGImage? {
        guard let firstFrame = await captureFrame() else {
            return nil
        }
        stitcher.setInitialFrame(firstFrame)
        shotA = firstFrame
        frameCount = 1

        onProgress(ScrollCaptureProgress(
            currentHeight: stitcher.totalHeight,
            maxHeight: config.maxHeight,
            frameCount: frameCount
        ))

        while !isCancelled {
            if stitcher.totalHeight >= config.maxHeight { break }

            try? await Task.sleep(for: .milliseconds(120))
            guard !isCancelled else { break }

            guard let shotB = await captureFrame() else { continue }

            // Skip if identical (user not scrolling)
            if framesAppearIdentical(shotA, shotB) {
                continue
            }

            guard let imageA = shotA else {
                shotA = shotB
                continue
            }

            if !chromeDetected {
                scrollbarWidth = ScrollbarDetector.detectScrollbarWidth(
                    frame1: imageA, frame2: shotB
                )
                headerHeight = HeaderDetector.detectHeaderHeight(
                    frame1: imageA, frame2: shotB
                )
                stitcher.applyChrome(headerHeight: headerHeight, scrollbarWidth: scrollbarWidth)
                chromeDetected = true
            }

            let visionA = ScrollStitcher.cropForRegistration(
                imageA,
                headerHeight: headerHeight,
                scrollbarWidth: scrollbarWidth
            )
            let visionB = ScrollStitcher.cropForRegistration(
                shotB,
                headerHeight: headerHeight,
                scrollbarWidth: scrollbarWidth
            )

            guard let rawOffset = detectOffset(imageA: visionA, imageB: visionB) else {
                shotA = shotB
                continue
            }

            if abs(rawOffset) < 3 {
                continue
            }

            // Lock the first meaningful scroll direction as "forward" so Vision
            // polarity differences across macOS versions don't break stitching.
            if forwardScrollIsNegativeTY == nil {
                forwardScrollIsNegativeTY = rawOffset < 0
            }
            let newRows: Int
            if forwardScrollIsNegativeTY == true {
                newRows = -rawOffset
            } else {
                newRows = rawOffset
            }
            // Opposite direction (scroll back up) — ignore, don't reverse-stitch.
            guard newRows >= 3 else {
                shotA = shotB
                continue
            }

            let result = stitcher.stitch(newFrame: shotB, detectedOffset: newRows)

            if case .stitched = result {
                frameCount += 1
                onProgress(ScrollCaptureProgress(
                    currentHeight: stitcher.totalHeight,
                    maxHeight: config.maxHeight,
                    frameCount: frameCount
                ))
            }

            shotA = shotB
        }

        if finishReason == .cancelled {
            return nil
        }
        return stitcher.mergedImage
    }

    private func framesAppearIdentical(_ a: CGImage?, _ b: CGImage?) -> Bool {
        guard let a, let b,
              a.width == b.width, a.height == b.height,
              let dataA = a.dataProvider?.data,
              let dataB = b.dataProvider?.data,
              CFDataGetLength(dataA) == CFDataGetLength(dataB),
              let ptrA = CFDataGetBytePtr(dataA),
              let ptrB = CFDataGetBytePtr(dataB) else {
            return false
        }
        return memcmp(ptrA, ptrB, CFDataGetLength(dataA)) == 0
    }

    // MARK: - Frame Capture

    private func captureFrame() async -> CGImage? {
        do {
            if cachedFilter == nil {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true
                )
                guard let display = content.displays.first(where: {
                    $0.displayID == config.displayID
                }) ?? content.displays.first else {
                    return nil
                }

                let myBundleID = Bundle.main.bundleIdentifier ?? ""
                let myWindows = content.windows.filter {
                    $0.owningApplication?.bundleIdentifier == myBundleID
                }

                let filter = SCContentFilter(display: display, excludingWindows: myWindows)
                let streamConfig = SCStreamConfiguration()
                streamConfig.captureResolution = .best
                streamConfig.showsCursor = false
                streamConfig.sourceRect = config.captureRect
                let scale = CGFloat(filter.pointPixelScale)
                streamConfig.width = Int(config.captureRect.width * scale)
                streamConfig.height = Int(config.captureRect.height * scale)

                cachedFilter = filter
                cachedStreamConfig = streamConfig
            }

            guard let filter = cachedFilter, let cfg = cachedStreamConfig else {
                return nil
            }

            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: cfg
            )
        } catch {
            return nil
        }
    }

    // MARK: - Vision Offset Detection

    /// Detect Y offset between two frames using VNTranslationalImageRegistrationRequest.
    /// Returns Vision's raw `ty` (upper-left origin). Negative ≈ scrolled down.
    private func detectOffset(imageA: CGImage, imageB: CGImage) -> Int? {
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: imageA)
        let handler = VNImageRequestHandler(cgImage: imageB, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first
                as? VNImageTranslationAlignmentObservation else {
            return nil
        }

        return Int(round(observation.alignmentTransform.ty))
    }
}
