import AppKit
import CoreGraphics
import Foundation
import Vision
@preconcurrency import ScreenCaptureKit

public struct ScrollCaptureConfig: Sendable {
    public let captureRect: CGRect
    public let displayID: CGDirectDisplayID
    public let mode: ScrollMode
    public let maxHeight: Int
    public let excludedWindowIDs: [CGWindowID]

    public init(
        captureRect: CGRect,
        displayID: CGDirectDisplayID,
        mode: ScrollMode = .manual,
        maxHeight: Int = 30_000,
        excludedWindowIDs: [CGWindowID] = []
    ) {
        self.captureRect = captureRect
        self.displayID = displayID
        self.mode = mode
        self.maxHeight = maxHeight
        self.excludedWindowIDs = excludedWindowIDs
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

    /// Reference frame for pairwise comparison
    private var shotA: CGImage?

    /// Sticky chrome detected once real scrolling occurs
    private var headerHeight = 0
    private var scrollbarWidth = 0
    private var chromeDetected = false

    /// Cached ScreenCaptureKit objects (created once, reused)
    private var cachedFilter: SCContentFilter?
    private var cachedStreamConfig: SCStreamConfiguration?

    /// Scroll distance event monitoring state
    private var globalScrollMonitor: Any?
    private var localScrollMonitor: Any?
    private var scrollSettleTimer: Timer?
    private var idleFallbackTimer: Timer?
    private var accumulatedScrollPoints: CGFloat = 0
    private var lastTriggerDate: Date = Date()
    private var triggerContinuation: AsyncStream<Void>.Continuation?

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
            await MainActor.run {
                self.removeScrollMonitor()
            }
            onComplete(result)
        }
    }

    /// User tapped Done — stop looping and return the stitched image.
    public func complete() {
        finishReason = .completed
        isCancelled = true
        triggerContinuation?.finish()
        Task { @MainActor [weak self] in
            self?.removeScrollMonitor()
        }
    }

    /// User cancelled — stop looping and discard the result.
    public func cancel() {
        finishReason = .cancelled
        isCancelled = true
        triggerContinuation?.finish()
        Task { @MainActor [weak self] in
            self?.removeScrollMonitor()
        }
    }

    /// Legacy alias for `complete()` (Done).
    public func stop() {
        complete()
    }

    // MARK: - Scroll Distance Monitoring

    @MainActor
    private func installScrollMonitor() {
        guard globalScrollMonitor == nil else { return }

        // Distance threshold to trigger capture (in points).
        // 36 points gives ~72 pixels on Retina (10-15% of typical viewport),
        // guaranteeing ~85-90% overlap between frames even on quick scrolls.
        let targetScrollPoints: CGFloat = 36.0

        let handleScroll: (NSEvent) -> Void = { [weak self] event in
            guard let self, !self.isCancelled else { return }

            let deltaY: CGFloat
            if event.hasPreciseScrollingDeltas {
                deltaY = event.scrollingDeltaY
            } else {
                deltaY = event.deltaY * 12.0
            }

            let magnitude = abs(deltaY)
            guard magnitude > 0.5 else { return }

            self.accumulatedScrollPoints += magnitude

            // 1. If accumulated scroll reached the target step, capture immediately
            if self.accumulatedScrollPoints >= targetScrollPoints {
                self.accumulatedScrollPoints = 0
                self.signalCaptureTrigger()
            }

            // 2. Settle timer (debounce 70ms):
            // When scrolling stops or slows down, captures the remaining offset
            self.scrollSettleTimer?.invalidate()
            self.scrollSettleTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: false) { [weak self] _ in
                guard let self, !self.isCancelled else { return }
                if self.accumulatedScrollPoints >= 6.0 {
                    self.accumulatedScrollPoints = 0
                    self.signalCaptureTrigger()
                }
            }
        }

        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: handleScroll)
        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            handleScroll(event)
            return event
        }

        // Safety fallback timer: every 180ms, ensures scrollbar dragging or keyboard scrolling
        // (PageDown / ArrowDown) still triggers captures when no scrollWheel events occur.
        idleFallbackTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            guard let self, !self.isCancelled else { return }
            let timeSinceLast = Date().timeIntervalSince(self.lastTriggerDate)
            if timeSinceLast >= 0.16 {
                self.signalCaptureTrigger()
            }
        }
    }

    @MainActor
    private func removeScrollMonitor() {
        if let monitor = globalScrollMonitor {
            NSEvent.removeMonitor(monitor)
            globalScrollMonitor = nil
        }
        if let monitor = localScrollMonitor {
            NSEvent.removeMonitor(monitor)
            localScrollMonitor = nil
        }
        scrollSettleTimer?.invalidate()
        scrollSettleTimer = nil
        idleFallbackTimer?.invalidate()
        idleFallbackTimer = nil
    }

    private func signalCaptureTrigger() {
        lastTriggerDate = Date()
        triggerContinuation?.yield(())
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

        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        self.triggerContinuation = continuation

        await MainActor.run {
            self.installScrollMonitor()
        }

        for await _ in stream {
            if isCancelled { break }
            if stitcher.totalHeight >= config.maxHeight { break }

            guard let shotB = await captureFrame() else { continue }
            if isCancelled { break }

            // Skip if identical (user not scrolling / content static)
            if framesAppearIdentical(shotA, shotB) {
                continue
            }

            guard let imageA = shotA else {
                shotA = shotB
                continue
            }

            // Detect scroll distance using hybrid Vision + SAD alignment
            guard let newRows = detectScrollOffset(
                imageA: imageA,
                imageB: shotB,
                headerHeight: headerHeight,
                scrollbarWidth: scrollbarWidth
            ) else {
                continue
            }

            // Require meaningful movement (at least 3 pixels)
            guard newRows >= 3 else {
                continue
            }

            // Detect sticky header and scrollbar once active scrolling is underway
            if !chromeDetected && newRows >= 12 {
                scrollbarWidth = ScrollbarDetector.detectScrollbarWidth(
                    frame1: imageA, frame2: shotB
                )
                headerHeight = HeaderDetector.detectHeaderHeight(
                    frame1: imageA, frame2: shotB, scrollbarWidth: scrollbarWidth
                )
                stitcher.applyChrome(headerHeight: headerHeight, scrollbarWidth: scrollbarWidth)
                chromeDetected = true
            }

            let result = stitcher.stitch(newFrame: shotB, detectedOffset: newRows)

            if case .stitched = result {
                frameCount += 1
                onProgress(ScrollCaptureProgress(
                    currentHeight: stitcher.totalHeight,
                    maxHeight: config.maxHeight,
                    frameCount: frameCount
                ))
                // Only advance reference frame when stitch was successful
                shotA = shotB
            }
        }

        await MainActor.run {
            self.removeScrollMonitor()
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

                let excludedIDs = Set(config.excludedWindowIDs)
                let myBundleID = Bundle.main.bundleIdentifier ?? ""
                let windowsToExclude = content.windows.filter {
                    excludedIDs.contains(CGWindowID($0.windowID))
                        || $0.owningApplication?.bundleIdentifier == myBundleID
                }

                let filter = SCContentFilter(display: display, excludingWindows: windowsToExclude)
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

    // MARK: - Offset Detection & Refinement

    private func detectScrollOffset(
        imageA: CGImage,
        imageB: CGImage,
        headerHeight: Int,
        scrollbarWidth: Int
    ) -> Int? {
        let visionA = ScrollStitcher.cropForRegistration(
            imageA,
            headerHeight: headerHeight,
            scrollbarWidth: max(scrollbarWidth, 20)
        )
        let visionB = ScrollStitcher.cropForRegistration(
            imageB,
            headerHeight: headerHeight,
            scrollbarWidth: max(scrollbarWidth, 20)
        )

        // 1. Initial translation estimate via Vision
        let visionEstimate = detectVisionOffset(imageA: visionA, imageB: visionB)

        // 2. Exact pixel-level refinement via SAD cross-check
        return refineOffset(imageA: visionA, imageB: visionB, estimated: visionEstimate)
    }

    private func detectVisionOffset(imageA: CGImage, imageB: CGImage) -> Int? {
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: imageA)
        let handler = VNImageRequestHandler(cgImage: imageB, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first as? VNImageTranslationAlignmentObservation else {
            return nil
        }

        // In Vision coordinates (bottom-left origin), content moving up gives ty < 0.
        // Downward scroll delta = -ty.
        let rawTY = observation.alignmentTransform.ty
        let delta = -rawTY
        return Int(round(delta))
    }

    /// Validates and snaps the offset to exact pixel boundary using Sum of Absolute Differences (SAD).
    private func refineOffset(imageA: CGImage, imageB: CGImage, estimated: Int?) -> Int? {
        let heightA = imageA.height
        let heightB = imageB.height
        let width = min(imageA.width, imageB.width)
        guard heightA > 40, heightB > 40, width > 40 else { return estimated }

        guard let dataA = imageA.dataProvider?.data,
              let dataB = imageB.dataProvider?.data,
              let ptrA = CFDataGetBytePtr(dataA),
              let ptrB = CFDataGetBytePtr(dataB) else {
            return estimated
        }

        let bprA = imageA.bytesPerRow
        let bprB = imageB.bytesPerRow
        let bpp = imageA.bitsPerPixel / 8
        guard bpp >= 3 else { return estimated }

        let sampleCols = 24
        let colStep = max(1, (width - 40) / sampleCols)

        func scoreOffset(_ d: Int) -> Double? {
            let overlapHeight = min(heightB, heightA - d)
            guard overlapHeight > 30 else { return nil }

            let row1 = 12
            let row2 = overlapHeight / 3
            let row3 = (2 * overlapHeight) / 3
            let row4 = overlapHeight - 12
            let testRows = [row1, row2, row3, row4]

            var totalDiff: Double = 0
            var points = 0

            for yB in testRows {
                let yA = yB + d
                guard yA < heightA else { continue }

                var col = 20
                while col < width - 20 {
                    let offsetB = yB * bprB + col * bpp
                    let offsetA = yA * bprA + col * bpp

                    let dr = abs(Int(ptrB[offsetB]) - Int(ptrA[offsetA]))
                    let dg = abs(Int(ptrB[offsetB + 1]) - Int(ptrA[offsetA + 1]))
                    let db = abs(Int(ptrB[offsetB + 2]) - Int(ptrA[offsetA + 2]))

                    totalDiff += Double(dr + dg + db)
                    points += 1
                    col += colStep
                }
            }

            guard points > 0 else { return nil }
            return totalDiff / Double(points)
        }

        // 1. If we have a Vision estimate, search within +-20 pixels of it
        if let est = estimated, est >= 3, est < heightA - 30 {
            let searchMin = max(3, est - 20)
            let searchMax = min(heightA - 30, est + 20)
            var bestOffset = est
            var minScore = scoreOffset(est) ?? Double.greatestFiniteMagnitude

            for d in searchMin...searchMax {
                if let score = scoreOffset(d), score < minScore {
                    minScore = score
                    bestOffset = d
                }
            }

            if minScore < 60 {
                return bestOffset
            }
            return est
        }

        // 2. No Vision estimate: do coarse-to-fine search over 3 ... min(heightA - 30, 450)
        let maxSearch = min(heightA - 30, 450)
        guard maxSearch >= 3 else { return nil }

        var coarseBest = 3
        var coarseMinScore = Double.greatestFiniteMagnitude

        // Coarse pass (step of 3)
        var d = 3
        while d <= maxSearch {
            if let score = scoreOffset(d), score < coarseMinScore {
                coarseMinScore = score
                coarseBest = d
            }
            d += 3
        }

        guard coarseMinScore < 90 else { return nil }

        // Fine pass (+-4 around coarseBest)
        let fineMin = max(3, coarseBest - 4)
        let fineMax = min(maxSearch, coarseBest + 4)
        var fineBest = coarseBest
        var fineMinScore = coarseMinScore

        for fineD in fineMin...fineMax {
            if let score = scoreOffset(fineD), score < fineMinScore {
                fineMinScore = score
                fineBest = fineD
            }
        }

        if fineMinScore < 60 {
            return fineBest
        }

        return nil
    }
}
