// App/Sources/Capture/CaptureCoordinator.swift
import AppKit
import CoreImage
import Observation
import UserNotifications
import AnnotationKit
import CaptureKit
import OCRKit
import SharedKit
import ShareKit

@MainActor
@Observable
final class CaptureCoordinator {
    private let settings: AppSettings
    private var overlayWindows: [CaptureOverlayWindow] = []
    /// Stack of active preview windows:
    /// - `[0]` is the OLDEST preview, anchored at the bottom-left primary slot
    /// - `[N]` is the NEWEST preview, sitting at the top of the visual stack
    /// - New captures append to the end, growing the stack upward
    /// - When the stack overflows, `[0]` (the oldest) slides off-screen to
    ///   the left and the rest shift down one slot
    private var quickAccessWindows: [QuickAccessWindow] = []
    /// Maximum previews kept on-screen. Oldest is evicted when exceeded.
    private let maxQuickAccessStackSize = 5
    private var quickAccessPreviewWindow: QuickAccessPreviewWindow?
    private var annotationWindow: AnnotationEditorWindow?
    private var inlineAnnotationWindow: InlineAnnotationEditorWindow?
    /// History entry tied to the open annotation editor (Save/Copy write sidecar here).
    private var activeAnnotationHistoryEntryID: UUID?
    private var allInOneToolbarWindow: CaptureAllInOneToolbarWindow?
    private var pinnedControllers: [PinnedScreenshotController] = []
    /// Opaque freeze-screen windows (one per display) that replace the live desktop
    private var freezeWindows: [NSWindow] = []
    /// Frozen screenshots paired with the freeze windows, used for multi-display crops.
    private var activeFrozenScreens: [(NSScreen, CGImage)] = []
    private var scrollCaptureController: ScrollCaptureController?
    private var scrollCaptureOverlay: ScrollCaptureOverlay?
    private var selfTimerHUD: SelfTimerHUD?
    /// Invalidates in-flight capture Tasks / delayed overlays when a newer capture starts.
    private var captureSessionID = UUID()

    var lastCaptureResult: CaptureResult?
    var ocrCoordinator: OCRCoordinator?
    var translationCoordinator: TranslationCoordinator?
    var recordingCoordinator: RecordingCoordinator?
    var historyCoordinator: HistoryCoordinator?
    var shareCoordinator: ShareCoordinator?

    /// Post-capture action override. When set, ignores Settings toggles.
    private var pendingAction: PostCaptureAction = .default
    private var pendingSourceApplication: SourceApplication?

    private struct SourceApplication: Sendable {
        let name: String?
        let bundleIdentifier: String?
    }

    enum PostCaptureAction {
        case `default`    // Use Settings (Show Preview / Copy / Auto Save)
        case clipboard    // Copy to clipboard only, no preview
        case annotate     // Open the full annotation editor directly
        case inlineAnnotate // Open the All-in-One inline annotation editor
        case ocr          // Open visual OCR directly
        case pin          // Pin selected capture to screen
        case save         // Save to file only, no preview
        case share        // Upload to cloud, skip Quick Access, save to history

        var playsShutterSound: Bool {
            switch self {
            case .annotate, .inlineAnnotate:
                false
            case .default, .clipboard, .ocr, .pin, .save, .share:
                true
            }
        }

        var savesOriginalCaptureToHistory: Bool {
            switch self {
            case .annotate, .inlineAnnotate, .pin:
                // Annotate paths save History themselves before opening the editor
                // so the session can attach a sidecar to that entry.
                false
            case .default, .clipboard, .ocr, .save, .share:
                true
            }
        }
    }

    init(settings: AppSettings) {
        self.settings = settings
    }

    private func rememberSourceApplication() {
        pendingSourceApplication = currentSourceApplication()
    }

    private func currentSourceApplication() -> SourceApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            return nil
        }

        let name = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleIdentifier = app.bundleIdentifier
        guard !(name?.isEmpty ?? true) || bundleIdentifier != nil else { return nil }
        return SourceApplication(name: name, bundleIdentifier: bundleIdentifier)
    }

    private func captureResultWithPendingSource(_ result: CaptureResult) -> CaptureResult {
        defer { pendingSourceApplication = nil }
        guard let source = pendingSourceApplication,
              result.appName == nil || result.appBundleIdentifier == nil else {
            return result
        }

        return CaptureResult(
            image: result.image,
            mode: result.mode,
            captureRect: result.captureRect,
            windowName: result.windowName,
            appName: result.appName ?? source.name,
            appBundleIdentifier: result.appBundleIdentifier ?? source.bundleIdentifier,
            timestamp: result.timestamp,
            displayID: result.displayID
        )
    }

    private func timestampedResultIfNeeded(_ result: CaptureResult) -> CaptureResult {
        let options = settings.screenshotTimestampOptions
        guard options.isEnabled,
              let image = ScreenshotTimestampRenderer.render(
                image: result.image,
                date: result.timestamp,
                options: options
              ) else {
            return result
        }

        return CaptureResult(
            image: image,
            mode: result.mode,
            captureRect: result.captureRect,
            windowName: result.windowName,
            appName: result.appName,
            appBundleIdentifier: result.appBundleIdentifier,
            timestamp: result.timestamp,
            displayID: result.displayID
        )
    }

    func captureArea() {
        pendingAction = .default
        startAreaCapture()
    }

    func captureAreaToClipboard() {
        pendingAction = .clipboard
        startAreaCapture()
    }

    func captureAreaAndAnnotate() {
        pendingAction = .annotate
        startAreaCapture()
    }

    func captureAreaAndShare() {
        logDiagnostic("Capture and Share shortcut invoked")
        // Gate: Cloud Share not configured → ask AppDelegate (via notification) to
        // open Preferences → Cloud Share tab. We avoid `NSApp.delegate as? AppDelegate`
        // because the cast fails under SwiftUI's @NSApplicationDelegateAdaptor proxying.
        guard let coord = shareCoordinator else {
            logDiagnostic("Cloud Share shortcut blocked: coordinator not configured")
            NotificationCenter.default.post(
                name: .openScreenshotSettings,
                object: PreferencesTab.cloudShare
            )
            return
        }

        // Gate: upload already in flight → notify and bail
        if case .uploading = coord.state {
            logDiagnostic("Cloud Share shortcut blocked: upload already in progress")
            Self.postNotification(
                title: String(localized: "Cloud Share busy"),
                body: String(localized: "Previous upload still in progress — try again in a moment.")
            )
            return
        }

        // All clear: run area selection, upload on success
        pendingAction = .share
        startAreaCapture()
    }

    func captureAllInOne() {
        pendingAction = .default
        let session = beginCaptureSession("allInOne")
        rememberSourceApplication()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.isCurrentSession(session) else { return }
            self.showFrozenAllInOneOverlay()
        }
    }

    private func startAreaCapture() {
        let session = beginCaptureSession("area")
        rememberSourceApplication()
        // Always freeze the screen first, then show the selection overlay on top
        // of the frozen backdrop. Freezing captures the current frame (including
        // any open dropdowns/popovers/menus) BEFORE the overlay takes key-window
        // status and dismisses that transient UI. See showFrozenOverlay().
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.isCurrentSession(session) else { return }
            self.showFrozenOverlay()
        }
    }

    func captureFullscreen() {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let displayID = targetScreen?.displayID ?? CGMainDisplayID()
        captureFullscreen(displayID: displayID, screen: targetScreen)
    }

    /// Captures a specific display. Used by the multi-monitor fullscreen submenu.
    func captureFullscreen(displayID: CGDirectDisplayID, screen: NSScreen? = nil) {
        let session = beginCaptureSession("fullscreen")
        rememberSourceApplication()
        let targetScreen = screen
            ?? NSScreen.screens.first { $0.displayID == displayID }
            ?? NSScreen.main
        settings.lastCaptureSelection = .fullscreen(screenID: displayID)

        // Freeze the display synchronously BEFORE any focus change so open
        // dropdowns/popovers/menus are baked into the capture. CGDisplayCreateImage
        // does not include the cursor, so we draw it back onto the frozen frame
        // when the user has opted into cursor-inclusive screenshots.
        if let image = Self.syncCaptureDisplay(displayID) {
            let fullScreenRect = CGRect(origin: .zero, size: targetScreen?.frame.size ?? .zero)
            let outputImage = targetScreen.flatMap {
                cursorCompositedIfNeeded(on: image, selectionRect: fullScreenRect, screen: $0)
            } ?? image
            let result = CaptureResult(
                image: outputImage,
                mode: .fullscreen,
                captureRect: CGDisplayBounds(displayID),
                displayID: displayID
            )
            guard isCurrentSession(session) else { return }
            handleCaptureResult(result)
            return
        }

        Task {
            do {
                let result = try await ScreenCaptureManager.captureFullscreen(
                    displayID: displayID,
                    showsCursor: settings.screenshotShowsCursor
                )
                guard self.isCurrentSession(session) else { return }
                handleCaptureResult(result)
            } catch {
                guard self.isCurrentSession(session) else { return }
                logCaptureFailure("Fullscreen capture failed displayID=\(displayID)", error: error)
            }
        }
    }

    /// Captures every connected display as separate screenshots.
    func captureAllDisplays() {
        let screens = Self.uniqueScreens(from: NSScreen.screens)
        guard !screens.isEmpty else {
            captureFullscreen()
            return
        }

        let session = beginCaptureSession("fullscreenAll")
        rememberSourceApplication()

        Task { @MainActor in
            var results: [CaptureResult] = []
            for screen in screens {
                if let result = await self.captureFullscreenResult(for: screen) {
                    results.append(result)
                }
            }
            guard self.isCurrentSession(session) else { return }
            for result in results {
                self.handleCaptureResult(result)
            }
        }
    }

    /// Capture one display, preferring the synchronous CGDisplayCreateImage path
    /// and falling back to ScreenCaptureKit when sync capture is unavailable.
    private func captureFullscreenResult(for screen: NSScreen) async -> CaptureResult? {
        let displayID = screen.displayID
        if let image = Self.syncCaptureDisplay(displayID) {
            let fullScreenRect = CGRect(origin: .zero, size: screen.frame.size)
            let outputImage = cursorCompositedIfNeeded(
                on: image,
                selectionRect: fullScreenRect,
                screen: screen
            ) ?? image
            return CaptureResult(
                image: outputImage,
                mode: .fullscreen,
                captureRect: CGDisplayBounds(displayID),
                displayID: displayID
            )
        }

        do {
            return try await ScreenCaptureManager.captureFullscreen(
                displayID: displayID,
                showsCursor: settings.screenshotShowsCursor
            )
        } catch {
            logCaptureFailure("Fullscreen capture failed displayID=\(displayID)", error: error)
            return nil
        }
    }

    /// One entry per physical display. Mirrored or duplicate NSScreen entries
    /// share a displayID and should only be captured once.
    private static func uniqueScreens(from screens: [NSScreen]) -> [NSScreen] {
        var seen = Set<CGDirectDisplayID>()
        var unique: [NSScreen] = []
        for screen in screens {
            let id = screen.displayID
            if seen.insert(id).inserted {
                unique.append(screen)
            }
        }
        return unique
    }

    func captureScrolling() {
        let session = beginCaptureSession("scrolling")
        rememberSourceApplication()
        // Freeze first (preserves open dropdowns), then select area on the
        // frozen backdrop. After selection, dismiss the freeze layer and run
        // the live scrolling capture on the real desktop.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.isCurrentSession(session) else { return }
            self.showFrozenOverlay { rect, screen in
                self.startScrollingCapture(rect: rect, screen: screen)
            }
        }
    }

    /// Self-timer area capture: pick area, show countdown HUD, then capture.
    /// Uses `settings.selfTimerDurationSeconds` as the delay.
    func captureAreaWithSelfTimer() {
        pendingAction = .default
        let session = beginCaptureSession("selfTimer")
        rememberSourceApplication()
        let seconds = settings.selfTimerDurationSeconds
        // Freeze first (preserves open dropdowns), then select area on the
        // frozen backdrop. After selection, dismiss the freeze layer and run
        // the self-timer countdown + live capture.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.isCurrentSession(session) else { return }
            self.showFrozenOverlay { rect, screen in
                self.runSelfTimerThenCapture(rect: rect, screen: screen, seconds: seconds)
            }
        }
    }

    func captureWindow() {
        pendingSourceApplication = nil
        let session = beginCaptureSession("window")
        // Enumerate windows first (async, no focus change), then freeze the
        // screen and show the window-selection overlay on the frozen backdrop.
        // Freezing happens AFTER enumeration but BEFORE the overlay takes key
        // status, so any open dropdown/popover is baked into the frozen frame
        // and won't disappear when our overlay becomes key.
        Task {
            do {
                // Exclude only Capso's overlay windows (not all Capso windows
                // like Settings) so the user can still capture them.
                let overlayIDs = Set(overlayWindows.map { CGWindowID($0.windowNumber) })
                let windows = try await ContentEnumerator.windows()
                    .filter { !overlayIDs.contains($0.id) }

                guard self.isCurrentSession(session) else { return }

                guard !windows.isEmpty else {
                    logCaptureFailure("No windows found to capture")
                    return
                }

                showFrozenOverlay(mode: .windowSelection(windows))
            } catch {
                guard self.isCurrentSession(session) else { return }
                logCaptureFailure("Window enumeration failed", error: error)
            }
        }
    }

    /// Replay the last area or fullscreen capture without showing the
    /// selection overlay. Bound to the user-assignable "Capture Previous
    /// Area" global shortcut. Silent no-op when nothing has been captured
    /// yet, or when the saved display is no longer connected.
    ///
    /// `pendingAction` is reset to `.default` on every branch so a previous
    /// `Capture Area & Annotate` (or any other mode-specific entry point)
    /// that left `pendingAction` non-default can't leak into the replay.
    func replayLastCapture() {
        guard let selection = settings.lastCaptureSelection else { return }
        switch selection {
        case let .area(x, y, width, height, screenID):
            guard let screen = NSScreen.screens.first(where: { $0.displayID == screenID }) else {
                return
            }
            let rect = CGRect(x: x, y: y, width: width, height: height)
            pendingAction = .default
            performAreaCapture(rect: rect, screen: screen)
        case let .fullscreen(screenID):
            pendingAction = .default
            Task {
                do {
                    let result = try await ScreenCaptureManager.captureFullscreen(
                        displayID: screenID,
                        showsCursor: settings.screenshotShowsCursor
                    )
                    handleCaptureResult(result)
                } catch {
                    print("Fullscreen replay failed: \(error)")
                }
            }
        }
    }

    private func showOverlay(
        mode: CaptureOverlayMode = .area,
        isScrollingCapture: Bool = false,
        selfTimerSeconds: Int? = nil,
        isAllInOne: Bool = false,
        areaSelected: ((CGRect, NSScreen) -> Void)? = nil
    ) {
        dismissOverlay()
        dismissAllInOneToolbar()
        for screen in NSScreen.screens {
            let overlay = CaptureOverlayWindow(screen: screen, settings: settings)
            overlay.onAreaSelected = { [weak self] rect, screen in
                self?.dismissOverlay()
                if let areaSelected {
                    self?.settings.lastCaptureSelection = .area(rect: rect, screenID: screen.displayID)
                    areaSelected(rect, screen)
                } else if isAllInOne {
                    self?.settings.lastCaptureSelection = .area(rect: rect, screenID: screen.displayID)
                    if Self.selectionSpansMultipleDisplays(rect: rect, screen: screen) {
                        // All-in-one chrome is still single-display; capture the
                        // cross-monitor selection immediately.
                        self?.performAreaCapture(rect: rect, screen: screen)
                    } else {
                        self?.showAllInOneToolbar(selectionRect: rect, screen: screen)
                    }
                } else if isScrollingCapture {
                    self?.startScrollingCapture(rect: rect, screen: screen)
                } else if let seconds = selfTimerSeconds {
                    self?.runSelfTimerThenCapture(rect: rect, screen: screen, seconds: seconds)
                } else {
                    self?.settings.lastCaptureSelection = .area(rect: rect, screenID: screen.displayID)
                    self?.performAreaCapture(rect: rect, screen: screen)
                }
            }
            overlay.onWindowSelected = { [weak self] windowID in
                self?.dismissOverlay()
                // Window captures are intentionally not persisted for replay;
                // see `StoredCaptureSelection` docs for the rationale.
                self?.performWindowCapture(windowID: windowID)
            }
            overlay.onCancelled = { [weak self] in
                self?.pendingSourceApplication = nil
                self?.dismissOverlay()
            }
            overlay.activate(mode: mode)
            overlayWindows.append(overlay)
        }
    }

    private func showFrozenAllInOneOverlay() {
        dismissOverlay()

        let frozenScreens = captureFrozenScreens()
        guard !frozenScreens.isEmpty else {
            showOverlay(mode: .area, isAllInOne: true)
            return
        }

        showFreezeWindows(frozenScreens)
        let frozenScreensForCapture = frozenScreens
        let frozenImagesByDisplayID = Dictionary(
            uniqueKeysWithValues: frozenScreens.map { ($0.0.displayID, $0.1) }
        )

        for (screen, _) in frozenScreens {
            let overlay = CaptureOverlayWindow(screen: screen, settings: settings)
            overlay.onAreaSelected = { [weak self] rect, screen in
                guard let self else { return }
                self.dismissSelectionOverlays()
                self.settings.lastCaptureSelection = .area(rect: rect, screenID: screen.displayID)
                if Self.selectionSpansMultipleDisplays(rect: rect, screen: screen) {
                    if let result = self.frozenAreaResult(
                        rect: rect,
                        anchorScreen: screen,
                        frozenScreens: frozenScreensForCapture
                    ) {
                        self.handleCaptureResult(result)
                    }
                    self.dismissFreezeWindows()
                    return
                }
                self.showAllInOneToolbar(
                    selectionRect: rect,
                    screen: screen,
                    frozenImage: frozenImagesByDisplayID[screen.displayID]
                )
            }
            overlay.onWindowSelected = { [weak self] windowID in
                self?.dismissOverlay()
                self?.performWindowCapture(windowID: windowID)
            }
            overlay.onCancelled = { [weak self] in
                self?.pendingSourceApplication = nil
                self?.dismissOverlay()
            }
            overlay.activate(mode: .area)
            overlayWindows.append(overlay)
        }
    }

    private func showAllInOneToolbar(
        selectionRect: CGRect,
        screen: NSScreen,
        frozenImage: CGImage? = nil
    ) {
        dismissAllInOneToolbar()

        let visiblePresets = settings.capturePresetsEnabled ? settings.visiblePresets : [.freeform]
        let activePreset = settings.capturePresetsEnabled ? settings.capturePreset : .freeform
        let toolbar = CaptureAllInOneToolbarWindow(
            selectionRect: selectionRect,
            screen: screen,
            presets: visiblePresets,
            activePreset: activePreset,
            frozenImage: frozenImage
        )
        toolbar.onPresetChanged = { [weak self] preset in
            guard let self, self.settings.capturePresetsEnabled else { return }
            self.settings.capturePreset = preset
        }
        toolbar.onArea = { [weak self] _ in
            guard let self else { return }
            self.dismissAllInOneToolbar()
            self.dismissFreezeWindows()
            self.captureAllInOne()
        }
        toolbar.onFullscreen = { [weak self] in
            guard let self else { return }
            self.dismissAllInOneToolbar()
            self.dismissFreezeWindows()
            self.captureFullscreen()
        }
        toolbar.onWindow = { [weak self] in
            guard let self else { return }
            self.dismissAllInOneToolbar()
            self.dismissFreezeWindows()
            self.captureWindow()
        }
        toolbar.onScrolling = { [weak self] rect in
            guard let self else { return }
            self.dismissAllInOneToolbar()
            self.dismissFreezeWindows()
            self.settings.lastCaptureSelection = .area(rect: rect, screenID: screen.displayID)
            self.startScrollingCapture(rect: rect, screen: screen)
        }
        toolbar.onTimer = { [weak self] rect in
            guard let self else { return }
            self.dismissAllInOneToolbar()
            self.dismissFreezeWindows()
            self.settings.lastCaptureSelection = .area(rect: rect, screenID: screen.displayID)
            self.runSelfTimerThenCapture(
                rect: rect,
                screen: screen,
                seconds: self.settings.selfTimerDurationSeconds
            )
        }
        toolbar.onOCR = { [weak self] rect in
            guard let self else { return }
            if self.handleFrozenAllInOneAction(
                rect: rect,
                screen: screen,
                frozenImage: frozenImage,
                action: .ocr
            ) {
                return
            }
            self.dismissAllInOneToolbar()
            self.dismissFreezeWindows()
            self.settings.lastCaptureSelection = .area(rect: rect, screenID: screen.displayID)
            self.pendingAction = .ocr
            self.performAreaCapture(rect: rect, screen: screen)
        }
        toolbar.onOCRRendered = { [weak self] image, _ in
            guard let self else { return }
            self.dismissAllInOneToolbar()
            self.dismissFreezeWindows()
            self.ocrCoordinator?.startVisualOCR(image: image, anchorScreen: screen)
        }
        toolbar.onRecording = { [weak self] rect in
            guard let self else { return }
            self.dismissAllInOneToolbar()
            self.dismissFreezeWindows()
            self.settings.lastCaptureSelection = .area(rect: rect, screenID: screen.displayID)
            self.recordingCoordinator?.startRecordingFlow(withSelectedArea: rect, screen: screen)
        }
        toolbar.onAnnotate = { [weak self] rect in
            guard let self else { return }
            if self.handleFrozenAllInOneAction(
                rect: rect,
                screen: screen,
                frozenImage: frozenImage,
                action: .inlineAnnotate
            ) {
                return
            }
            self.dismissAllInOneToolbar()
            self.dismissFreezeWindows()
            self.settings.lastCaptureSelection = .area(rect: rect, screenID: screen.displayID)
            self.pendingAction = .inlineAnnotate
            self.performAreaCapture(rect: rect, screen: screen)
        }
        toolbar.onCopy = { [weak self] rect in
            guard let self else { return }
            if self.handleFrozenAllInOneAction(
                rect: rect,
                screen: screen,
                frozenImage: frozenImage,
                action: .clipboard
            ) {
                return
            }
            self.dismissAllInOneToolbar()
            self.dismissFreezeWindows()
            self.settings.lastCaptureSelection = .area(rect: rect, screenID: screen.displayID)
            self.pendingAction = .clipboard
            self.performAreaCapture(rect: rect, screen: screen)
        }
        toolbar.onCopyRendered = { [weak self] image, _ in
            guard let self else { return }
            self.dismissAllInOneToolbar()
            self.dismissFreezeWindows()
            self.copyRenderedImage(image)
        }
        toolbar.onSave = { [weak self] rect in
            guard let self else { return }
            if self.handleFrozenAllInOneAction(
                rect: rect,
                screen: screen,
                frozenImage: frozenImage,
                action: .save
            ) {
                return
            }
            self.dismissAllInOneToolbar()
            self.dismissFreezeWindows()
            self.settings.lastCaptureSelection = .area(rect: rect, screenID: screen.displayID)
            self.pendingAction = .save
            self.performAreaCapture(rect: rect, screen: screen)
        }
        toolbar.onSaveRendered = { [weak self] image, _ in
            guard let self else { return }
            self.dismissAllInOneToolbar()
            self.dismissFreezeWindows()
            self.saveRenderedImage(image, sourceAppName: self.pendingSourceApplication?.name)
            self.pendingSourceApplication = nil
        }
        toolbar.onPin = { [weak self] rect in
            guard let self else { return }
            if self.handleFrozenAllInOneAction(
                rect: rect,
                screen: screen,
                frozenImage: frozenImage,
                action: .pin
            ) {
                return
            }
            self.dismissAllInOneToolbar()
            self.dismissFreezeWindows()
            self.settings.lastCaptureSelection = .area(rect: rect, screenID: screen.displayID)
            self.pendingAction = .pin
            self.performAreaCapture(rect: rect, screen: screen)
        }
        toolbar.onPinRendered = { [weak self] image, rect in
            guard let self else { return }
            self.dismissAllInOneToolbar()
            self.dismissFreezeWindows()
            self.pinRenderedImage(
                image,
                anchor: self.globalRect(fromScreenLocalRect: rect, screen: screen),
                sourceAppName: self.pendingSourceApplication?.name
            )
            self.pendingSourceApplication = nil
        }
        toolbar.onCancel = { [weak self] in
            self?.pendingSourceApplication = nil
            self?.dismissAllInOneToolbar()
            self?.dismissFreezeWindows()
        }

        allInOneToolbarWindow = toolbar
        toolbar.show()
    }

    /// Show the Self-Timer HUD on the screen the user just selected an area
    /// on, then fire the capture once the countdown finishes. Esc / click on
    /// the HUD cancels the capture entirely (no fallback capture).
    private func runSelfTimerThenCapture(rect: CGRect, screen: NSScreen, seconds: Int) {
        // Tear down any stale HUD first (defensive — there shouldn't be one).
        selfTimerHUD?.dismiss()

        let hud = SelfTimerHUD()
        selfTimerHUD = hud
        hud.show(
            on: screen,
            selectionRect: rect,
            duration: seconds,
            playTickSound: settings.selfTimerPlayTickSound,
            savedPosition: settings.selfTimerHUDPosition,
            persistPosition: { [weak self] origin in
                self?.settings.selfTimerHUDPosition = origin
            },
            onComplete: { [weak self] in
                self?.selfTimerHUD = nil
                self?.performAreaCapture(rect: rect, screen: screen)
            },
            onCancel: { [weak self] in
                self?.selfTimerHUD = nil
                // Reset pendingAction; the user explicitly bailed.
                self?.pendingAction = .default
            }
        )
    }

    /// Two-window freeze architecture for preserving popups/dropdowns:
    ///
    /// 1. Bottom window: OPAQUE, shows frozen image, completely replaces the
    ///    live desktop. isOpaque=true means no compositing with what's behind
    ///    → no sub-pixel mismatch → no shaking. Pre-rendered before showing.
    ///
    /// 2. Top window: TRANSPARENT overlay for crosshair + selection + dark tint.
    ///
    /// `areaSelected` is invoked when the user confirms an area selection for
    /// flows that should use the live desktop after selection, such as
    /// scrolling capture or the self-timer.
    private func showFrozenOverlay(
        mode: CaptureOverlayMode = .area,
        areaSelected: ((CGRect, NSScreen) -> Void)? = nil
    ) {
        dismissOverlay()

        let frozenScreens = captureFrozenScreens()
        guard !frozenScreens.isEmpty else {
            showOverlay(mode: mode, areaSelected: areaSelected)
            return
        }

        showFreezeWindows(frozenScreens)

        // Step 2: Create transparent overlay windows (top layer) for selection
        let frozenScreensForCapture = frozenScreens
        for (screen, _) in frozenScreens {
            let overlay = CaptureOverlayWindow(screen: screen, settings: settings)
            overlay.onAreaSelected = { [weak self] rect, screen in
                guard let self else { return }
                self.dismissOverlay()
                self.settings.lastCaptureSelection = .area(rect: rect, screenID: screen.displayID)
                if let areaSelected {
                    areaSelected(rect, screen)
                } else if let result = self.frozenAreaResult(
                    rect: rect,
                    anchorScreen: screen,
                    frozenScreens: frozenScreensForCapture
                ) {
                    self.handleCaptureResult(result)
                }
            }
            overlay.onWindowSelected = { [weak self] windowID in
                self?.dismissOverlay()
                self?.performWindowCapture(windowID: windowID)
            }
            overlay.onCancelled = { [weak self] in
                self?.pendingSourceApplication = nil
                self?.dismissOverlay()
            }
            overlay.activate(mode: mode)
            overlayWindows.append(overlay)
        }
    }

    private func captureFrozenScreens() -> [(NSScreen, CGImage)] {
        NSScreen.screens.compactMap { screen in
            guard let image = Self.syncCaptureDisplay(screen.displayID) else { return nil }
            return (screen, image)
        }
    }

    private func showFreezeWindows(_ frozenScreens: [(NSScreen, CGImage)]) {
        activeFrozenScreens = frozenScreens
        for (screen, frozenImage) in frozenScreens {
            let freezeWin = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            freezeWin.level = .screenSaver - 1
            freezeWin.isOpaque = true
            freezeWin.hasShadow = false
            freezeWin.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            freezeWin.hidesOnDeactivate = false

            let imageView = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
            imageView.image = NSImage(cgImage: frozenImage, size: screen.frame.size)
            imageView.imageScaling = .scaleAxesIndependently
            freezeWin.contentView = imageView
            freezeWin.displayIfNeeded()
            freezeWin.orderFrontRegardless()
            freezeWindows.append(freezeWin)
        }
    }

    private func performWindowCapture(windowID: CGWindowID) {
        let session = captureSessionID
        Task {
            do {
                // Always capture without system shadow — we generate our own
                // uniform padding + frosted glass backdrop when the setting is on.
                let result = try await ScreenCaptureManager.captureWindow(
                    windowID: windowID,
                    includeShadow: false,
                    showsCursor: settings.screenshotShowsCursor
                )
                guard self.isCurrentSession(session) else { return }
                if settings.captureWindowShadow {
                    // Capture the real desktop behind the window (excluding the
                    // window itself) for the frosted glass background.
                    // Padding = 4% of the shorter side, plus room for shadow blur.
                    let shorter = min(CGFloat(result.image.width), CGFloat(result.image.height))
                    let padding = max(30, shorter * 0.04)
                    let totalPadding = padding + 20 // extra for shadow spread
                    let desktopBg = try await ScreenCaptureManager.captureDesktopBehindWindow(
                        windowID: windowID,
                        padding: totalPadding
                    )
                    guard self.isCurrentSession(session) else { return }
                    if let composited = Self.compositeWindowWithFrostedGlass(
                        windowImage: result.image,
                        desktopBackground: desktopBg
                    ) {
                        let enhanced = CaptureResult(
                            image: composited,
                            mode: result.mode,
                            captureRect: result.captureRect,
                            windowName: result.windowName,
                            appName: result.appName,
                            appBundleIdentifier: result.appBundleIdentifier,
                            timestamp: result.timestamp,
                            displayID: result.displayID
                        )
                        handleCaptureResult(enhanced)
                        return
                    }
                }
                handleCaptureResult(result)
            } catch {
                guard self.isCurrentSession(session) else { return }
                logCaptureFailure("Window capture failed", error: error)
            }
        }
    }

    /// Composite a window screenshot over a frosted-glass version of the real
    /// desktop background, with uniform padding, rounded corners, and a soft
    /// drop shadow.
    private static func compositeWindowWithFrostedGlass(
        windowImage: CGImage,
        desktopBackground: CGImage
    ) -> CGImage? {
        let outW = desktopBackground.width
        let outH = desktopBackground.height
        guard outW > 0, outH > 0 else { return nil }

        let imgW = CGFloat(windowImage.width)
        let imgH = CGFloat(windowImage.height)
        let canvasSize = CGSize(width: outW, height: outH)
        let shadowRadius: CGFloat = 20
        let cornerRadius: CGFloat = 12

        // Centre the window in the canvas
        let offsetX = (CGFloat(outW) - imgW) / 2
        let offsetY = (CGFloat(outH) - imgH) / 2
        let imageRect = CGRect(x: offsetX, y: offsetY, width: imgW, height: imgH)
        let roundedPath = CGPath(roundedRect: imageRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        // --- Blur the desktop background via CoreImage ---
        guard let backdrop = frostedGlassBackdrop(from: desktopBackground, targetSize: canvasSize) else { return nil }

        // --- Composite ---
        guard let ctx = CGContext(
            data: nil,
            width: outW,
            height: outH,
            bitsPerComponent: 8,
            bytesPerRow: outW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        let canvasRect = CGRect(x: 0, y: 0, width: outW, height: outH)

        // 1. Draw frosted desktop backdrop
        ctx.draw(backdrop, in: canvasRect)

        // 2. Draw soft shadow — clip to OUTSIDE the rounded rect so the
        //    white fill used to generate the shadow never bleeds into the
        //    corner area (which would show as white corner artifacts).
        ctx.saveGState()
        let outerPath = CGMutablePath()
        outerPath.addRect(canvasRect)
        outerPath.addPath(roundedPath)
        ctx.addPath(outerPath)
        ctx.clip(using: .evenOdd)
        ctx.setShadow(
            offset: CGSize(width: 0, height: -4),
            blur: shadowRadius,
            color: NSColor.black.withAlphaComponent(0.25).cgColor
        )
        ctx.addPath(roundedPath)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // 3. Draw window clipped to rounded corners
        ctx.saveGState()
        ctx.addPath(roundedPath)
        ctx.clip()
        ctx.draw(windowImage, in: imageRect)
        ctx.restoreGState()

        return ctx.makeImage()
    }

    /// Blur and slightly saturate a desktop background image for the frosted
    /// glass effect behind window captures.
    private static func frostedGlassBackdrop(from image: CGImage, targetSize: CGSize) -> CGImage? {
        let srcW = CGFloat(image.width)
        let srcH = CGFloat(image.height)
        guard srcW > 0, srcH > 0 else { return nil }

        var ci = CIImage(cgImage: image)

        // Aspect-fill to target size with slight overshoot to avoid blur edges.
        let coverScale = max(targetSize.width / srcW, targetSize.height / srcH) * 1.05
        ci = ci.transformed(by: CGAffineTransform(scaleX: coverScale, y: coverScale))
        let tx = (targetSize.width - ci.extent.width) / 2 - ci.extent.minX
        let ty = (targetSize.height - ci.extent.height) / 2 - ci.extent.minY
        ci = ci.transformed(by: CGAffineTransform(translationX: tx, y: ty))

        // Boost saturation slightly for richer colours.
        if let f = CIFilter(name: "CIColorControls", parameters: [
            kCIInputImageKey: ci,
            kCIInputSaturationKey: 1.4,
            kCIInputBrightnessKey: 0.0,
            kCIInputContrastKey: 0.98,
        ]), let out = f.outputImage {
            ci = out
        }

        // Heavy Gaussian blur for frosted glass look.
        let clamped = ci.clampedToExtent()
        if let f = CIFilter(name: "CIGaussianBlur", parameters: [
            kCIInputImageKey: clamped,
            kCIInputRadiusKey: 80.0,
        ]), let out = f.outputImage {
            ci = out
        }

        let ciCtx = CIContext(options: nil)
        return ciCtx.createCGImage(ci, from: CGRect(origin: .zero, size: targetSize))
    }

    private func dismissOverlay() {
        dismissSelectionOverlays()
        dismissFreezeWindows()
    }

    private func dismissSelectionOverlays() {
        for window in overlayWindows {
            window.deactivate()
        }
        overlayWindows.removeAll()
    }

    private func dismissFreezeWindows() {
        let windows = freezeWindows
        freezeWindows.removeAll()
        activeFrozenScreens = []
        if windows.isEmpty { return }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            for window in windows {
                window.animator().alphaValue = 0
            }
        }
        // Clean up after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            for window in windows {
                window.orderOut(nil)
            }
        }
    }

    private func dismissAllInOneToolbar() {
        allInOneToolbarWindow?.close()
        allInOneToolbarWindow = nil
    }

    // MARK: - Scrolling Capture

    /// Saved capture rect (ScreenCaptureKit coordinates) for deferred start.
    private var scrollCaptureRect: CGRect = .zero
    private var scrollCaptureDisplayID: CGDirectDisplayID = 0

    private func startScrollingCapture(rect: CGRect, screen: NSScreen) {
        let screenFrame = screen.frame
        // Convert from bottom-left (NSView) to top-left (ScreenCaptureKit) coordinates
        scrollCaptureRect = CGRect(
            x: rect.origin.x,
            y: screenFrame.height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
        scrollCaptureDisplayID = screen.displayID

        // Show persistent overlay: selection border + controls + preview
        let overlay = ScrollCaptureOverlay()
        self.scrollCaptureOverlay = overlay

        overlay.onStart = { [weak self] in
            self?.beginScrollingCaptureLoop()
        }

        overlay.onDone = { [weak self] in
            self?.finishScrollingCapture()
        }

        overlay.onCancel = { [weak self] in
            self?.cancelScrollingCapture()
        }

        overlay.show(selectionRect: rect, screen: screen)
    }

    /// Called when user clicks Start — begins the capture loop.
    private func beginScrollingCaptureLoop() {
        let captureRect = scrollCaptureRect
        let displayID = scrollCaptureDisplayID

        let config = ScrollCaptureConfig(
            captureRect: captureRect,
            displayID: displayID,
            mode: .manual
        )
        let controller = ScrollCaptureController(config: config)
        self.scrollCaptureController = controller

        scrollCaptureOverlay?.setCapturing(true)

        controller.start(
            onProgress: { [weak self] progress in
                Task { @MainActor in
                    if let mergedImage = controller.currentMergedImage {
                        self?.scrollCaptureOverlay?.updatePreview(
                            image: mergedImage,
                            height: progress.currentHeight,
                            frameCount: progress.frameCount
                        )
                    }
                }
            },
            onComplete: { [weak self] image in
                Task { @MainActor in
                    guard let self else { return }
                    // Ignore stale completions after cancel / newer capture session.
                    guard self.scrollCaptureController === controller else { return }

                    self.scrollCaptureOverlay?.close()
                    self.scrollCaptureOverlay = nil
                    self.scrollCaptureController = nil

                    guard let image else {
                        CaptureDiagnostics.breadcrumb("scroll.cancelledOrEmpty")
                        return
                    }

                    let result = CaptureResult(
                        image: image,
                        mode: .scrolling,
                        captureRect: captureRect,
                        displayID: displayID
                    )
                    self.handleCaptureResult(result)
                }
            }
        )
    }

    private func finishScrollingCapture() {
        scrollCaptureController?.complete()
    }

    private func cancelScrollingCapture() {
        scrollCaptureController?.cancel()
        scrollCaptureOverlay?.close()
        scrollCaptureOverlay = nil
        scrollCaptureController = nil
    }

    private func performAreaCapture(rect: CGRect, screen: NSScreen) {
        let session = captureSessionID
        let globalRect = CaptureDisplayGeometry.globalAppKitRect(
            fromScreenLocalRect: rect,
            screenFrame: screen.frame
        )
        let targets = Self.displayAreaTargets(forGlobalAppKitRect: globalRect)
        guard !targets.isEmpty else {
            logCaptureFailure("Area capture failed", error: CaptureError.captureFailed("Selection does not intersect any display"))
            return
        }

        Task {
            do {
                let result = try await ScreenCaptureManager.captureMultiDisplayArea(
                    targets: targets,
                    selectionSize: globalRect.size,
                    showsCursor: settings.screenshotShowsCursor
                )
                guard self.isCurrentSession(session) else { return }
                handleCaptureResult(result)
            } catch {
                guard self.isCurrentSession(session) else { return }
                logCaptureFailure("Area capture failed", error: error)
            }
        }
    }

    private func handleFrozenAllInOneAction(
        rect: CGRect,
        screen: NSScreen,
        frozenImage: CGImage?,
        action: PostCaptureAction
    ) -> Bool {
        let sources: [(NSScreen, CGImage)]
        if !activeFrozenScreens.isEmpty {
            sources = activeFrozenScreens
        } else if let frozenImage {
            sources = [(screen, frozenImage)]
        } else {
            return false
        }

        guard let result = frozenAreaResult(
            rect: rect,
            anchorScreen: screen,
            frozenScreens: sources
        ) else {
            return false
        }

        dismissAllInOneToolbar()
        settings.lastCaptureSelection = .area(rect: rect, screenID: screen.displayID)
        pendingAction = action
        handleCaptureResult(result)
        dismissFreezeWindows()
        return true
    }

    private func frozenAreaResult(
        rect: CGRect,
        anchorScreen: NSScreen,
        frozenScreens: [(NSScreen, CGImage)]
    ) -> CaptureResult? {
        let globalRect = CaptureDisplayGeometry.globalAppKitRect(
            fromScreenLocalRect: rect,
            screenFrame: anchorScreen.frame
        )

        var slices: [MultiDisplayCaptureSlice] = []
        for (screen, frozenImage) in frozenScreens {
            guard let local = CaptureDisplayGeometry.intersectingScreenLocalRect(
                globalAppKitRect: globalRect,
                screenFrame: screen.frame
            ) else {
                continue
            }

            let cropRect = CaptureDisplayGeometry.frozenImageCropRect(
                screenLocalRect: local,
                screenSize: screen.frame.size,
                imageSize: CGSize(width: frozenImage.width, height: frozenImage.height)
            )
            guard !cropRect.isEmpty,
                  let cropped = frozenImage.cropping(to: cropRect) else {
                continue
            }

            let scale: CGFloat
            if local.width > 0 {
                scale = CGFloat(cropped.width) / local.width
            } else {
                scale = 1
            }

            let originInSelection = CGPoint(
                x: (local.minX + screen.frame.minX) - globalRect.minX,
                y: (local.minY + screen.frame.minY) - globalRect.minY
            )

            let image = cursorCompositedIfNeeded(
                on: cropped,
                selectionRect: local,
                screen: screen
            ) ?? cropped

            slices.append(
                MultiDisplayCaptureSlice(
                    image: image,
                    originInSelection: originInSelection,
                    sizeInPoints: local.size,
                    scale: scale
                )
            )
        }

        guard !slices.isEmpty else { return nil }

        let outputScale = slices.map(\.scale).max() ?? 1
        guard let stitched = MultiDisplayImageStitcher.stitch(
            slices: slices,
            selectionSize: globalRect.size,
            outputScale: outputScale
        ) else {
            return nil
        }

        let captureRect = CaptureDisplayGeometry.displayTopLeftRect(
            fromScreenLocalRect: rect,
            screenHeight: anchorScreen.frame.height
        )

        return CaptureResult(
            image: stitched,
            mode: .area,
            captureRect: captureRect,
            displayID: anchorScreen.displayID
        )
    }

    /// Build ScreenCaptureKit targets for every display that intersects a
    /// global AppKit selection rectangle.
    private static func displayAreaTargets(
        forGlobalAppKitRect globalRect: CGRect
    ) -> [DisplayAreaCaptureTarget] {
        uniqueScreens(from: NSScreen.screens).compactMap { screen in
            guard let local = CaptureDisplayGeometry.intersectingScreenLocalRect(
                globalAppKitRect: globalRect,
                screenFrame: screen.frame
            ), local.width > 0.5, local.height > 0.5 else {
                return nil
            }

            let sourceRect = CaptureDisplayGeometry.displayTopLeftRect(
                fromScreenLocalRect: local,
                screenHeight: screen.frame.height
            )
            return DisplayAreaCaptureTarget(
                displayID: screen.displayID,
                sourceRect: sourceRect,
                originInSelection: CGPoint(
                    x: (local.minX + screen.frame.minX) - globalRect.minX,
                    y: (local.minY + screen.frame.minY) - globalRect.minY
                ),
                sizeInPoints: local.size
            )
        }
    }

    /// Whether a screen-local selection (relative to `screen`) intersects more
    /// than one connected display — including differently sized monitors.
    private static func selectionSpansMultipleDisplays(rect: CGRect, screen: NSScreen) -> Bool {
        let globalRect = CaptureDisplayGeometry.globalAppKitRect(
            fromScreenLocalRect: rect,
            screenFrame: screen.frame
        )
        let hitCount = uniqueScreens(from: NSScreen.screens).filter { candidate in
            CaptureDisplayGeometry.intersectingScreenLocalRect(
                globalAppKitRect: globalRect,
                screenFrame: candidate.frame
            ) != nil
        }.count
        return hitCount > 1
    }

    private func cursorCompositedIfNeeded(
        on image: CGImage,
        selectionRect: CGRect,
        screen: NSScreen
    ) -> CGImage? {
        guard settings.screenshotShowsCursor else { return image }

        let mouseLocation = NSEvent.mouseLocation
        guard screen.frame.contains(mouseLocation) else { return image }

        let screenLocalMouse = CGPoint(
            x: mouseLocation.x - screen.frame.minX,
            y: mouseLocation.y - screen.frame.minY
        )
        guard selectionRect.contains(screenLocalMouse) else { return image }

        return Self.compositeCursor(
            on: image,
            cursorLocation: screenLocalMouse,
            selectionRect: selectionRect
        )
    }

    private static func compositeCursor(
        on image: CGImage,
        cursorLocation: CGPoint,
        selectionRect: CGRect
    ) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, selectionRect.width > 0, selectionRect.height > 0 else {
            return nil
        }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let canvasRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image, in: canvasRect)

        let cursor = NSCursor.arrow
        var cursorImageRect = NSRect(origin: .zero, size: cursor.image.size)
        guard let cursorImage = cursor.image.cgImage(
            forProposedRect: &cursorImageRect,
            context: nil,
            hints: nil
        ) else {
            return context.makeImage()
        }

        let scaleX = CGFloat(width) / selectionRect.width
        let scaleY = CGFloat(height) / selectionRect.height
        let cursorSize = cursor.image.size
        let cursorWidth = cursorSize.width * scaleX
        let cursorHeight = cursorSize.height * scaleY
        let pointX = (cursorLocation.x - selectionRect.minX) * scaleX
        let pointY = (cursorLocation.y - selectionRect.minY) * scaleY
        let hotSpot = cursor.hotSpot
        let drawRect = CGRect(
            x: pointX - hotSpot.x * scaleX,
            y: pointY - (cursorSize.height - hotSpot.y) * scaleY,
            width: cursorWidth,
            height: cursorHeight
        )

        context.draw(cursorImage, in: drawRect)
        return context.makeImage()
    }

    private func handleCaptureResult(_ capturedResult: CaptureResult) {
        let result = captureResultWithPendingSource(capturedResult)
        let outputResult = timestampedResultIfNeeded(result)
        lastCaptureResult = result

        let action = pendingAction
        pendingAction = .default

        if settings.playShutterSound, action.playsShutterSound {
            Self.shutterSound?.stop()
            Self.shutterSound?.play()
        }

        // Pre-generate the history entry ID so we can wire the cloud URL callback
        // before the async save completes.
        let entryID = UUID()

        switch action {
        case .clipboard:
            copyImageToClipboard(outputResult.image)
        case .annotate:
            // Keep the original capture in History so Save/Copy from the editor
            // can write a re-editable annotation sidecar against this entry.
            historyCoordinator?.saveCapture(result: outputResult, entryID: entryID)
            openAnnotationEditor(
                outputResult,
                anchorScreen: screenFor(result: result),
                historyEntryID: entryID
            )
        case .inlineAnnotate:
            historyCoordinator?.saveCapture(result: outputResult, entryID: entryID)
            openInlineAnnotationEditor(outputResult, anchorScreen: screenFor(result: result))
        case .ocr:
            ocrCoordinator?.startVisualOCR(image: result.image, anchorScreen: screenFor(result: result))
        case .pin:
            pinToScreen(outputResult, anchor: anchorRect(for: result))
        case .save:
            saveImageToFile(outputResult)
        case .share:
            // Skip Quick Access, save to history, then upload in background.
            logDiagnostic("Cloud Share capture completed mode=\(outputResult.mode) displayID=\(outputResult.displayID)")
            historyCoordinator?.saveCapture(result: outputResult, entryID: entryID)
            if let coord = shareCoordinator {
                Task { await self.performShareAfterCapture(result: outputResult, entryID: entryID, coord: coord) }
            } else {
                logDiagnostic("Cloud Share capture completed but coordinator is nil")
                Self.postNotification(
                    title: String(localized: "Cloud share failed"),
                    body: String(localized: "Cloud Share is not configured.")
                )
            }
            return  // history already saved above; skip the call below
        case .default:
            // Snapshot before auto-copy so Delete can restore the prior clipboard.
            let clipboardBackup = settings.screenshotShowPreview
                ? ClipboardSnapshot.capture()
                : nil
            if settings.screenshotAutoCopy {
                copyImageToClipboard(outputResult.image)
            }
            var autoSavedURL: URL?
            if settings.screenshotAutoSave {
                autoSavedURL = saveImageToFileReturningURL(outputResult)
            }
            if settings.screenshotShowPreview {
                showQuickAccess(
                    for: outputResult,
                    entryID: entryID,
                    clipboardBackup: clipboardBackup,
                    autoSavedURL: autoSavedURL
                )
            }
        }

        if action.savesOriginalCaptureToHistory {
            historyCoordinator?.saveCapture(result: action == .ocr ? result : outputResult, entryID: entryID)
        }
    }

    /// The real camera-shutter sound macOS itself plays for Cmd+Shift+3/4.
    /// Loaded from the built-in CoreAudio system sounds bundle. If the file
    /// ever moves or is renamed in a future macOS release we fall back to a
    /// subtler "Pop" alert sound (which is at least not the "Tink" error
    /// ding we used to use).
    private static let shutterSound: NSSound? = {
        let shutterPath = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        if FileManager.default.fileExists(atPath: shutterPath),
           let sound = NSSound(contentsOf: URL(fileURLWithPath: shutterPath), byReference: true) {
            return sound
        }
        return NSSound(named: "Pop")
    }()

    private func showQuickAccess(
        for result: CaptureResult,
        entryID: UUID,
        clipboardBackup: ClipboardSnapshot?,
        autoSavedURL: URL?
    ) {
        // If the stack is full, evict the oldest (the one anchored at the
        // bottom slot) with a slide-off-left animation. The remaining
        // previews will slide down one slot as part of the restack below.
        while quickAccessWindows.count >= maxQuickAccessStackSize {
            let oldest = quickAccessWindows.removeFirst()
            oldest.slideOffLeftAndClose()
        }

        let captureScreen = screenFor(result: result) ?? screenAtMouse()
        let window = QuickAccessWindow(result: result, settings: settings, screen: captureScreen, shareCoordinator: shareCoordinator)

        // Persist the cloud URL to history when an upload succeeds from Quick Access.
        window.onUploadSucceeded = { [weak self] urlString in
            self?.historyCoordinator?.setCloudURL(id: entryID, url: urlString)
        }

        // All callbacks capture the specific `window` weakly so the right
        // stack slot gets dismissed — not whichever one happens to be newest.
        window.onCopy = { [weak self, weak window] in
            guard let self, let window else { return }
            self.copyImageToClipboard(result.image)
            self.dismissQuickAccessWindow(window)
        }
        window.onSave = { [weak self, weak window] in
            guard let self, let window else { return }
            self.saveImageToFile(result)
            self.dismissQuickAccessWindow(window)
        }
        window.onShare = { [weak self, weak window] in
            guard let self, let window else { return }
            window.cancelAutoDismiss()
            SystemSharePresenter.present(image: result.image, from: window)
        }
        window.onDelete = { [weak self, weak window] in
            guard let self, let window else { return }
            self.discardQuickAccessCapture(
                entryID: entryID,
                clipboardBackup: clipboardBackup,
                autoSavedURL: autoSavedURL
            )
            self.quickAccessPreviewWindow?.close()
            self.dismissQuickAccessWindow(window)
        }
        window.onAnnotate = { [weak self, weak window] in
            guard let self, let window else { return }
            let anchor = window.targetScreen
            self.dismissQuickAccessWindow(window)
            self.openAnnotationEditor(result, anchorScreen: anchor, historyEntryID: entryID)
        }
        window.onPreview = { [weak self, weak window] in
            guard let self, let window else { return }
            self.openQuickAccessPreview(
                result,
                entryID: entryID,
                anchorScreen: window.targetScreen,
                clipboardBackup: clipboardBackup,
                autoSavedURL: autoSavedURL,
                sourceQuickAccess: window
            )
        }
        window.onPin = { [weak self, weak window] in
            guard let self, let window else { return }
            let anchor = window.frame
            self.dismissQuickAccessWindow(window)
            self.pinToScreen(result, anchor: anchor)
        }
        window.onOCR = { [weak self, weak window] in
            guard let self, let window else { return }
            let anchor = window.targetScreen
            self.dismissQuickAccessWindow(window)
            self.ocrCoordinator?.startVisualOCR(image: result.image, anchorScreen: anchor)
        }
        window.onTranslate = { [weak self, weak window] in
            guard let self, let window else { return }
            let anchor = window.targetScreen
            self.dismissQuickAccessWindow(window)
            self.translationCoordinator?.translate(image: result.image, anchorScreen: anchor)
        }
        window.onClose = { [weak self, weak window] in
            guard let self, let window else { return }
            self.dismissQuickAccessWindow(window)
        }

        quickAccessWindows.append(window)
        restackQuickAccessWindows(excluding: window)
        window.show()
    }

    private func discardQuickAccessCapture(
        entryID: UUID,
        clipboardBackup: ClipboardSnapshot?,
        autoSavedURL: URL?
    ) {
        historyCoordinator?.discardCapture(id: entryID)
        if let autoSavedURL {
            try? FileManager.default.removeItem(at: autoSavedURL)
        }
        if let clipboardBackup {
            clipboardBackup.restore()
        }
    }

    private func openQuickAccessPreview(
        _ result: CaptureResult,
        entryID: UUID,
        anchorScreen: NSScreen?,
        clipboardBackup: ClipboardSnapshot?,
        autoSavedURL: URL?,
        sourceQuickAccess: QuickAccessWindow?
    ) {
        quickAccessPreviewWindow?.close()
        let previewWindow = QuickAccessPreviewWindow(image: result.image, anchorScreen: anchorScreen)
        previewWindow.onCopy = { [weak self] in
            self?.copyImageToClipboard(result.image)
        }
        previewWindow.onSave = { [weak self] in
            self?.saveImageToFile(result)
        }
        previewWindow.onShare = { [weak previewWindow] in
            SystemSharePresenter.present(image: result.image, from: previewWindow)
        }
        previewWindow.onDelete = { [weak self, weak previewWindow, weak sourceQuickAccess] in
            guard let self else { return }
            self.discardQuickAccessCapture(
                entryID: entryID,
                clipboardBackup: clipboardBackup,
                autoSavedURL: autoSavedURL
            )
            previewWindow?.close()
            if let sourceQuickAccess {
                self.dismissQuickAccessWindow(sourceQuickAccess)
            }
        }
        previewWindow.onClose = { [weak self, weak previewWindow] in
            guard let self, self.quickAccessPreviewWindow === previewWindow else { return }
            self.quickAccessPreviewWindow = nil
        }
        quickAccessPreviewWindow = previewWindow
        previewWindow.show()
    }

    /// Remove a specific preview from the stack and close it, then slide the
    /// remaining previews on the same screen down to collapse the gap.
    private func dismissQuickAccessWindow(_ window: QuickAccessWindow) {
        guard let idx = quickAccessWindows.firstIndex(where: { $0 === window }) else {
            return
        }
        quickAccessWindows.remove(at: idx)
        window.close()
        restackQuickAccessWindows()
    }

    /// Reposition all preview windows using per-screen stacking: windows on
    /// the same screen share a stack (index 0 at the bottom, 1 above it, …),
    /// independent of windows on other screens.
    ///
    /// - Parameter skipAnimation: A window to position without animation
    ///   (used for the newly-created preview so it appears at the correct
    ///   slot immediately before its show() fade-in).
    private func restackQuickAccessWindows(excluding skipAnimation: QuickAccessWindow? = nil) {
        // Group windows by their target screen's displayID, preserving order
        // (oldest → newest within each group) so the oldest sits at index 0.
        var perScreen: [CGDirectDisplayID: [QuickAccessWindow]] = [:]
        for win in quickAccessWindows {
            let id = win.targetScreen.displayID
            perScreen[id, default: []].append(win)
        }
        for (_, windows) in perScreen {
            for (i, win) in windows.enumerated() {
                let animated = (win !== skipAnimation)
                win.repositionForStackIndex(i, animated: animated)
            }
        }
    }

    private func openAnnotationEditor(_ result: CaptureResult, anchorScreen: NSScreen? = nil, historyEntryID: UUID? = nil) {
        openAnnotationEditor(
            image: result.image,
            anchorScreen: anchorScreen ?? screenFor(result: result),
            sourceAppName: result.appName,
            sourceWindowTitle: result.windowName,
            date: result.timestamp,
            historyEntryID: historyEntryID
        )
    }

    func openAnnotationEditor(
        image: CGImage,
        anchorScreen: NSScreen? = nil,
        sourceAppName: String? = nil,
        sourceWindowTitle: String? = nil,
        date: Date = Date(),
        sidecar: AnnotationSidecar? = nil,
        historyEntryID: UUID? = nil
    ) {
        let screen = anchorScreen ?? screenAtMouse() ?? NSScreen.main
        activeAnnotationHistoryEntryID = historyEntryID

        inlineAnnotationWindow?.close()
        inlineAnnotationWindow = nil
        annotationWindow = AnnotationEditorWindow(
            image: image,
            sidecar: sidecar,
            anchorScreen: screen,
            onSave: { [weak self] (rendered: CGImage, source: CGImage, document: AnnotationDocument) in
                guard let self else { return }
                self.saveRenderedImage(
                    rendered,
                    sourceAppName: sourceAppName,
                    sourceWindowTitle: sourceWindowTitle,
                    date: date
                )
                self.persistOpenAnnotation(
                    rendered: rendered,
                    source: source,
                    document: document,
                    sourceAppName: sourceAppName,
                    sourceWindowTitle: sourceWindowTitle,
                    date: date
                )
                self.activeAnnotationHistoryEntryID = nil
                self.annotationWindow = nil
            },
            onCopy: { [weak self] (rendered: CGImage, source: CGImage, document: AnnotationDocument) in
                guard let self else { return }
                self.copyRenderedImage(rendered)
                self.persistOpenAnnotation(
                    rendered: rendered,
                    source: source,
                    document: document,
                    sourceAppName: sourceAppName,
                    sourceWindowTitle: sourceWindowTitle,
                    date: date
                )
                self.activeAnnotationHistoryEntryID = nil
                self.annotationWindow = nil
            },
            onShare: { [weak self] (rendered: CGImage) in
                SystemSharePresenter.present(image: rendered, from: self?.annotationWindow)
            },
            onPin: { [weak self] (rendered: CGImage, anchor: CGRect?) in
                self?.pinRenderedImage(
                    rendered,
                    anchor: anchor,
                    sourceAppName: sourceAppName,
                    sourceWindowTitle: sourceWindowTitle,
                    date: date
                )
                self?.activeAnnotationHistoryEntryID = nil
                self?.annotationWindow = nil
            },
            onClose: { [weak self] in
                self?.activeAnnotationHistoryEntryID = nil
                self?.annotationWindow = nil
            }
        )
        annotationWindow?.show()
    }

    /// Always writes annotation objects into History so reopen can continue editing.
    private func persistOpenAnnotation(
        rendered: CGImage,
        source: CGImage,
        document: AnnotationDocument,
        sourceAppName: String?,
        sourceWindowTitle: String?,
        date: Date
    ) {
        let entryID = activeAnnotationHistoryEntryID
        let persistedID = historyCoordinator?.persistAnnotationEdit(
            entryID: entryID,
            baseImage: source,
            renderedImage: rendered,
            sidecar: document.exportSidecar(),
            sourceAppName: sourceAppName,
            sourceWindowTitle: sourceWindowTitle,
            date: date
        )
        if let persistedID {
            activeAnnotationHistoryEntryID = persistedID
        }
    }

    func annotateFromClipboard() {
        guard let image = ImageUtilities.cgImageFromPasteboard() else {
            Self.postNotification(
                title: String(localized: "No image on clipboard"),
                body: String(localized: "Copy an image first, then try again.")
            )
            return
        }
        openAnnotationEditor(image: image, anchorScreen: NSScreen.main)
    }

    private func openInlineAnnotationEditor(_ result: CaptureResult, anchorScreen: NSScreen? = nil) {
        let screen = anchorScreen ?? screenFor(result: result)
        guard result.mode == .area,
              let screen,
              openInlineAnnotationEditor(result, screen: screen) else {
            openAnnotationEditor(result, anchorScreen: screen)
            return
        }
    }

    private func openInlineAnnotationEditor(_ result: CaptureResult, screen: NSScreen) -> Bool {
        let screenLocalRect = CaptureDisplayGeometry.screenLocalRect(
            fromTopLeftCaptureRect: result.captureRect,
            screenHeight: screen.frame.height
        )
        guard screenLocalRect.width > 0,
              screenLocalRect.height > 0,
              CaptureDisplayGeometry.displayScale(
                imageSize: CGSize(width: result.image.width, height: result.image.height),
                screenRect: screenLocalRect
              ) != nil else {
            return false
        }

        annotationWindow?.close()
        annotationWindow = nil
        inlineAnnotationWindow?.close()
        inlineAnnotationWindow = InlineAnnotationEditorWindow(
            image: result.image,
            screen: screen,
            screenLocalRect: screenLocalRect,
            onSave: { [weak self] rendered in
                self?.saveRenderedImage(
                    rendered,
                    sourceAppName: result.appName,
                    sourceWindowTitle: result.windowName,
                    date: result.timestamp
                )
                self?.inlineAnnotationWindow = nil
            },
            onCopy: { [weak self] rendered in
                self?.copyRenderedImage(rendered)
                self?.inlineAnnotationWindow = nil
            },
            onShare: { [weak self] rendered in
                SystemSharePresenter.present(image: rendered, from: self?.inlineAnnotationWindow)
            },
            onPin: { [weak self] rendered, anchor in
                self?.pinRenderedImage(
                    rendered,
                    anchor: anchor,
                    sourceAppName: result.appName,
                    sourceWindowTitle: result.windowName,
                    date: result.timestamp
                )
                self?.inlineAnnotationWindow = nil
            },
            onClose: { [weak self] in
                self?.inlineAnnotationWindow = nil
            }
        )
        inlineAnnotationWindow?.show()
        return true
    }

    /// Look up the NSScreen whose displayID matches the capture. Falls back to
    /// geometry overlap and the current mouse screen when the display ID does
    /// not resolve (e.g. ScreenCaptureKit vs NSScreen mismatch).
    private func screenFor(result: CaptureResult) -> NSScreen? {
        if let screen = NSScreen.screens.first(where: { $0.displayID == result.displayID }) {
            return screen
        }

        let captureRect = result.captureRect.standardized
        if !captureRect.isEmpty {
            for screen in NSScreen.screens {
                let displayBounds = CGDisplayBounds(screen.displayID)
                if displayBounds.equalTo(captureRect)
                    || displayBounds.intersects(captureRect) {
                    return screen
                }
            }
        }

        return screenAtMouse()
    }

    private func screenAtMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
    }

    private func anchorRect(for result: CaptureResult) -> CGRect {
        guard let screen = screenFor(result: result) else {
            return result.captureRect
        }
        let screenLocalRect = CaptureDisplayGeometry.screenLocalRect(
            fromTopLeftCaptureRect: result.captureRect,
            screenHeight: screen.frame.height
        )
        return globalRect(fromScreenLocalRect: screenLocalRect, screen: screen)
    }

    private func globalRect(fromScreenLocalRect rect: CGRect, screen: NSScreen) -> CGRect {
        CGRect(
            x: rect.origin.x + screen.frame.origin.x,
            y: rect.origin.y + screen.frame.origin.y,
            width: rect.width,
            height: rect.height
        )
    }

    /// If the currently-focused Quick Access panel can handle the Translate
    /// action, fire it and return true. Otherwise return false so the caller
    /// (a global shortcut handler) can fall through to its default behavior.
    ///
    /// This exists because the `KeyboardShortcuts` package registers a
    /// SYSTEM-wide hotkey for the Capture & Translate shortcut, which always
    /// wins over a SwiftUI `.keyboardShortcut` attached to the Translate button
    /// in the Quick Access panel. Without this fall-through, pressing the
    /// global shortcut while hovering a Quick Access preview would trigger a
    /// fresh capture-and-translate flow instead of translating the capture the
    /// user was already looking at.
    @discardableResult
    func invokeQuickAccessTranslateIfKey() -> Bool {
        guard let key = NSApp.keyWindow as? QuickAccessWindow,
              quickAccessWindows.contains(where: { $0 === key }),
              let handler = key.onTranslate else {
            return false
        }
        handler()
        return true
    }

    private func pinToScreen(_ result: CaptureResult, anchor: CGRect) {
        pinRenderedImage(
            result.image,
            anchor: anchor,
            sourceAppName: result.appName,
            sourceWindowTitle: result.windowName,
            date: result.timestamp
        )
    }

    private func pinRenderedImage(
        _ image: CGImage,
        anchor: CGRect?,
        sourceAppName: String? = nil,
        sourceWindowTitle: String? = nil,
        date: Date = Date()
    ) {
        let controller = PinnedScreenshotController(
            image: image,
            anchorRect: anchor,
            onCopy: { [weak self] in
                self?.copyImageToClipboard(image)
            },
            onSave: { [weak self] in
                self?.saveImageToFile(
                    image,
                    sourceAppName: sourceAppName,
                    sourceWindowTitle: sourceWindowTitle,
                    date: date
                )
            },
            onDidClose: { [weak self] controllerID in
                self?.pinnedControllers.removeAll { $0.id == controllerID }
            }
        )
        pinnedControllers.append(controller)
        controller.show()
    }

    private func copyImageToClipboard(_ image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        pasteboard.writeObjects([nsImage])
    }

    private func saveImageToFile(_ result: CaptureResult) {
        _ = saveImageToFileReturningURL(result)
    }

    @discardableResult
    private func saveImageToFileReturningURL(_ result: CaptureResult) -> URL? {
        saveImageToFileReturningURL(
            result.image,
            sourceAppName: result.appName,
            sourceWindowTitle: result.windowName,
            date: result.timestamp
        )
    }

    private func saveImageToFile(
        _ image: CGImage,
        sourceAppName: String? = nil,
        sourceWindowTitle: String? = nil,
        date: Date = Date()
    ) {
        _ = saveImageToFileReturningURL(
            image,
            sourceAppName: sourceAppName,
            sourceWindowTitle: sourceWindowTitle,
            date: date
        )
    }

    @discardableResult
    private func saveImageToFileReturningURL(
        _ image: CGImage,
        sourceAppName: String? = nil,
        sourceWindowTitle: String? = nil,
        date: Date = Date()
    ) -> URL? {
        guard let encoded = screenshotData(from: image) else { return nil }
        let directory = settings.screenshotMonthlyFolders
            ? FileNaming.monthlyDirectory(in: settings.exportLocation)
            : settings.exportLocation
        let url = FileNaming.generateFileURL(
            in: directory,
            type: .screenshot,
            format: encoded.format,
            date: date,
            sourceAppName: sourceAppName,
            sourceWindowTitle: sourceWindowTitle,
            template: settings.screenshotFilenameTemplate
        )
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try encoded.data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private func screenshotData(from image: CGImage) -> (data: Data, format: FileFormat)? {
        let preset = settings.screenshotOutputPreset
        let data: Data? = switch preset.fileFormat {
        case .png:
            ImageUtilities.pngData(from: image)
        case .jpeg:
            ImageUtilities.jpegData(from: image, quality: preset.jpegQuality ?? 0.85)
        case .mp4, .gif, .mov:
            nil
        }
        guard let data else { return nil }
        return (data, preset.fileFormat)
    }

    private func saveRenderedImage(
        _ image: CGImage,
        sourceAppName: String? = nil,
        sourceWindowTitle: String? = nil,
        date: Date = Date()
    ) {
        saveImageToFile(
            image,
            sourceAppName: sourceAppName,
            sourceWindowTitle: sourceWindowTitle,
            date: date
        )
    }

    private func copyRenderedImage(_ image: CGImage) {
        copyImageToClipboard(image)
    }

    // MARK: - Cloud Share Upload

    private func performShareAfterCapture(
        result: CaptureResult,
        entryID: UUID,
        coord: ShareCoordinator
    ) async {
        let image = result.image

        // Encode + write off the main actor so large PNGs don't block the UI.
        logDiagnostic("Cloud Share encode starting size=\(image.width)x\(image.height)")
        let tempURL: URL? = await Task.detached(priority: .userInitiated) { () -> URL? in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("png")
            guard let data = ImageUtilities.pngData(from: image) else { return nil }
            do {
                try data.write(to: url)
                return url
            } catch {
                return nil
            }
        }.value

        guard let tempURL else {
            logDiagnostic("Cloud Share encode failed")
            Self.postNotification(
                title: String(localized: "Cloud share failed"),
                body: String(localized: "Couldn't encode capture for upload.")
            )
            return
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            logDiagnostic("Cloud Share upload starting")
            let url = try await coord.upload(file: tempURL, contentType: "image/png")
            // ShareCoordinator already copied the URL to clipboard on success.
            logDiagnostic("Cloud Share upload succeeded host=\(url.host ?? "unknown")")
            historyCoordinator?.setCloudURL(id: entryID, url: url.absoluteString)
            logDiagnostic("Cloud Share history URL persisted")
            Self.postNotification(
                title: String(localized: "Cloud share ready"),
                body: String(localized: "Link copied to clipboard.")
            )
        } catch let err as ShareError {
            logDiagnostic("Cloud Share upload failed shareError=\(Self.humanizeShareError(err))")
            Self.postNotification(
                title: String(localized: "Cloud share failed"),
                body: Self.humanizeShareError(err)
            )
        } catch {
            logDiagnostic("Cloud Share upload failed error=\(error.localizedDescription)")
            Self.postNotification(
                title: String(localized: "Cloud share failed"),
                body: error.localizedDescription
            )
        }
    }

    private func logDiagnostic(_ message: String) {
        CaptureDiagnostics.breadcrumb(message)
        guard settings.diagnosticLoggingEnabled else { return }
        DiagnosticLogger.append(message, category: "Capture")
    }

    /// Always records capture failures (even when verbose diagnostics are off).
    private func logCaptureFailure(_ context: String, error: Error? = nil) {
        let detail = error.map { "\($0.localizedDescription)" } ?? ""
        let message = detail.isEmpty ? context : "\(context): \(detail)"
        CaptureDiagnostics.breadcrumb(message)
        DiagnosticLogger.append(message, category: "Capture")
    }

    @discardableResult
    private func beginCaptureSession(_ phase: String) -> UUID {
        let id = UUID()
        captureSessionID = id
        CaptureDiagnostics.breadcrumb(
            "session.begin \(phase) id=\(id.uuidString.prefix(8)) displays=\(NSScreen.screens.count)"
        )
        cancelInFlightCaptureUI()
        return id
    }

    private func isCurrentSession(_ id: UUID) -> Bool {
        id == captureSessionID
    }

    /// Tear down selection/scroll/timer chrome so a new capture can't overlap.
    private func cancelInFlightCaptureUI() {
        cancelScrollingCapture()
        selfTimerHUD?.dismiss()
        selfTimerHUD = nil
        allInOneToolbarWindow?.close()
        allInOneToolbarWindow = nil
        dismissOverlay()
    }

    private static func humanizeShareError(_ err: ShareError) -> String {
        switch err {
        case .invalidCredentials:
            return String(localized: "Cloud credentials are invalid.")
        case .network(let underlying):
            return String(localized: "Network error: \(underlying)")
        case .quotaExceeded:
            return String(localized: "Cloud quota exceeded.")
        case .publicAccessUnreachable:
            return String(localized: "Upload OK but public URL unreachable.")
        case .invalidURLPrefix(let reason):
            return String(localized: "Invalid URL prefix: \(reason)")
        case .notConfigured:
            return String(localized: "Cloud Share is not configured.")
        case .unknown(let detail):
            return detail
        }
    }

    /// Post a macOS user notification. Requests authorization on the first call.
    private static func postNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.add(request, withCompletionHandler: nil)
        }
    }

    // MARK: - Synchronous Display Capture

    /// Synchronously capture a display using CGDisplayCreateImage.
    /// Deprecated in macOS 14+ but still functional — loaded via dlsym
    /// to bypass the compile-time unavailability annotation.
    /// Required for freeze-screen: must capture before any window appears.
    private static func syncCaptureDisplay(_ displayID: CGDirectDisplayID) -> CGImage? {
        typealias CGDisplayCreateImageFunc = @convention(c) (CGDirectDisplayID) -> CGImage?
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let sym = dlsym(handle, "CGDisplayCreateImage") else {
            return nil
        }
        defer { dlclose(handle) }
        let fn = unsafeBitCast(sym, to: CGDisplayCreateImageFunc.self)
        return fn(displayID)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? CGMainDisplayID()
    }
}
