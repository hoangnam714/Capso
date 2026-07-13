// App/Sources/MenuBar/MenuBarController.swift
import AppKit
import CoreGraphics
import SharedKit
import KeyboardShortcuts

extension Notification.Name {
    /// Posted when `AppSettings.showMenuBarIcon` changes so the menu bar can show/hide live.
    static let menuBarVisibilityChanged = Notification.Name("menuBarVisibilityChanged")
}

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private let settings: AppSettings
    private let captureCoordinator: CaptureCoordinator
    private let recordingCoordinator: RecordingCoordinator
    private let ocrCoordinator: OCRCoordinator
    private let translationCoordinator: TranslationCoordinator
    private let historyCoordinator: HistoryCoordinator
    private let onShowPreferences: () -> Void

    init(settings: AppSettings, captureCoordinator: CaptureCoordinator, recordingCoordinator: RecordingCoordinator, ocrCoordinator: OCRCoordinator, translationCoordinator: TranslationCoordinator, historyCoordinator: HistoryCoordinator, onShowPreferences: @escaping () -> Void) {
        self.settings = settings
        self.captureCoordinator = captureCoordinator
        self.recordingCoordinator = recordingCoordinator
        self.ocrCoordinator = ocrCoordinator
        self.translationCoordinator = translationCoordinator
        self.historyCoordinator = historyCoordinator
        self.onShowPreferences = onShowPreferences
        super.init()
        applyVisibility()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVisibilityChange),
            name: .menuBarVisibilityChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleVisibilityChange() {
        applyVisibility()
    }

    /// Installs or removes the status item based on `settings.showMenuBarIcon`.
    private func applyVisibility() {
        if settings.showMenuBarIcon {
            guard statusItem == nil else { return }
            setupStatusItem()
        } else {
            guard let item = statusItem else { return }
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = true
        }
        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let captureAllInOne = menuItem(String(localized: "All-in-One"), action: #selector(captureAllInOne))
        captureAllInOne.setShortcut(for: .captureAllInOne)
        menu.addItem(captureAllInOne)

        menu.addItem(.separator())

        let captureArea = menuItem(String(localized: "Capture Area"), action: #selector(captureArea))
        captureArea.setShortcut(for: .captureArea)
        menu.addItem(captureArea)

        menu.addItem(fullscreenMenuItem())

        let captureWindow = menuItem(String(localized: "Capture Window"), action: #selector(captureWindow))
        captureWindow.setShortcut(for: .captureWindow)
        menu.addItem(captureWindow)

        menu.addItem(.separator())

        let captureText = menuItem(String(localized: "Capture Text (OCR)"), action: #selector(captureText))
        captureText.setShortcut(for: .captureText)
        menu.addItem(captureText)

        let captureAndTranslate = menuItem(String(localized: "Capture & Translate"), action: #selector(self.captureAndTranslate))
        captureAndTranslate.setShortcut(for: .captureAndTranslate)
        menu.addItem(captureAndTranslate)

        let translateSelectedText = menuItem(String(localized: "Translate Selected Text"), action: #selector(self.translateSelectedText))
        translateSelectedText.setShortcut(for: .translateSelectedText)
        menu.addItem(translateSelectedText)

        let captureScrolling = menuItem(String(localized: "Scrolling Capture"), action: #selector(captureScrolling))
        captureScrolling.setShortcut(for: .captureScrolling)
        menu.addItem(captureScrolling)

        let selfTimer = selfTimerMenuItem()
        menu.addItem(selfTimer)

        menu.addItem(.separator())

        let recordScreen = menuItem(String(localized: "Record Screen"), action: #selector(recordScreen))
        recordScreen.setShortcut(for: .recordScreen)
        menu.addItem(recordScreen)

        menu.addItem(.separator())

        let annotateClipboard = menuItem(String(localized: "Open from Clipboard"), action: #selector(annotateFromClipboard))
        menu.addItem(annotateClipboard)

        let screenshotHistory = menuItem(String(localized: "Screenshot History..."), action: #selector(openHistory))
        screenshotHistory.setShortcut(for: .screenshotHistory)
        menu.addItem(screenshotHistory)
        menu.addItem(.separator())

        menu.addItem(menuItem(String(localized: "Preferences..."), action: #selector(openPreferences), key: ",", modifiers: [.command]))
        menu.addItem(menuItem(String(localized: "About Capso"), action: #selector(openAbout)))
        menu.addItem(.separator())
        menu.addItem(menuItem(String(localized: "Quit Capso"), action: #selector(quitApp), key: "q", modifiers: [.command]))

        return menu
    }

    private func menuItem(_ title: String, action: Selector?, key: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    /// Self-Timer menu row. Title is "Self-Timer" with the saved duration
    /// rendered in tertiary color as a trailing tag (e.g. "Self-Timer  5s").
    /// Refreshed in `menuWillOpen` so the tag stays in sync with Preferences.
    private func selfTimerMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "", action: #selector(captureSelfTimer), keyEquivalent: "")
        item.target = self
        refreshSelfTimerTitle(item)
        item.setShortcut(for: .selfTimerCapture)
        return item
    }

    private func refreshSelfTimerTitle(_ item: NSMenuItem) {
        let label = String(localized: "Self-Timer")
        let duration = "\(settings.selfTimerDurationSeconds)s"
        let attributed = NSMutableAttributedString(
            string: label,
            attributes: [.font: NSFont.menuFont(ofSize: 0)]
        )
        attributed.append(NSAttributedString(
            string: "   \(duration)",
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
        ))
        item.attributedTitle = attributed
    }

    private func fullscreenMenuItem() -> NSMenuItem {
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            let item = menuItem(String(localized: "Capture Fullscreen"), action: #selector(captureFullscreen))
            item.setShortcut(for: .captureFullscreen)
            return item
        }

        let parent = NSMenuItem(title: String(localized: "Capture Fullscreen"), action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: String(localized: "Capture Fullscreen"))

        let current = menuItem(String(localized: "Current Display"), action: #selector(captureFullscreen))
        current.setShortcut(for: .captureFullscreen)
        submenu.addItem(current)
        submenu.addItem(.separator())

        for (index, screen) in screens.enumerated() {
            let title: String
            if screen == NSScreen.main {
                title = String(format: String(localized: "Display %d (Main)"), index + 1)
            } else {
                title = String(format: String(localized: "Display %d"), index + 1)
            }
            let item = menuItem(title, action: #selector(captureSpecificDisplay(_:)))
            item.representedObject = screen.displayID
            if !screen.localizedName.isEmpty {
                item.toolTip = screen.localizedName
            }
            submenu.addItem(item)
        }

        submenu.addItem(.separator())
        submenu.addItem(menuItem(String(localized: "All Displays"), action: #selector(captureAllDisplays)))

        parent.submenu = submenu
        return parent
    }

    @objc private func captureArea() {
        captureCoordinator.captureArea()
    }

    @objc private func captureAllInOne() {
        captureCoordinator.captureAllInOne()
    }

    @objc private func captureFullscreen() {
        captureCoordinator.captureFullscreen()
    }

    @objc private func captureSpecificDisplay(_ sender: NSMenuItem) {
        guard let displayID = sender.representedObject as? CGDirectDisplayID else {
            captureCoordinator.captureFullscreen()
            return
        }
        let screen = NSScreen.screens.first { $0.displayID == displayID }
        captureCoordinator.captureFullscreen(displayID: displayID, screen: screen)
    }

    @objc private func captureAllDisplays() {
        captureCoordinator.captureAllDisplays()
    }

    @objc private func captureWindow() {
        captureCoordinator.captureWindow()
    }

    @objc private func captureText() {
        ocrCoordinator.startInstantOCR()
    }

    @objc private func captureAndTranslate() {
        translationCoordinator.startCaptureAndTranslate()
    }

    @objc private func translateSelectedText() {
        translationCoordinator.translateSelectedText()
    }

    @objc private func captureScrolling() {
        captureCoordinator.captureScrolling()
    }

    @objc private func captureSelfTimer() {
        captureCoordinator.captureAreaWithSelfTimer()
    }

    @objc private func recordScreen() {
        recordingCoordinator.startRecordingFlow()
    }

    @objc private func openHistory() {
        historyCoordinator.showWindow()
    }

    @objc private func annotateFromClipboard() {
        captureCoordinator.annotateFromClipboard()
    }

    @objc private func openPreferences() {
        onShowPreferences()
    }

    @objc private func openAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - Update shortcut display when menu opens

extension MenuBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Refresh shortcut display from KeyboardShortcuts in case user changed them
        for item in menu.items {
            switch item.action {
            case #selector(captureAllInOne): item.setShortcut(for: .captureAllInOne)
            case #selector(captureArea): item.setShortcut(for: .captureArea)
            case #selector(captureFullscreen): item.setShortcut(for: .captureFullscreen)
            case #selector(captureWindow): item.setShortcut(for: .captureWindow)
            case #selector(captureText): item.setShortcut(for: .captureText)
            case #selector(captureAndTranslate): item.setShortcut(for: .captureAndTranslate)
            case #selector(translateSelectedText): item.setShortcut(for: .translateSelectedText)
            case #selector(recordScreen): item.setShortcut(for: .recordScreen)
            case #selector(captureScrolling): item.setShortcut(for: .captureScrolling)
            case #selector(captureSelfTimer):
                item.setShortcut(for: .selfTimerCapture)
                refreshSelfTimerTitle(item)
            case #selector(openHistory): item.setShortcut(for: .screenshotHistory)
            default: break
            }
        }
    }
}
