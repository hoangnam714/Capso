import AppKit
import RecordingKit

/// Apple-style menu bar control: a red stop affordance visible while recording.
@MainActor
final class RecordingStatusBarIndicator {
    private var statusItem: NSStatusItem?
    private var elapsedTimer: Timer?
    private weak var recorder: ScreenRecorder?
    private let onStop: () -> Void

    init(onStop: @escaping () -> Void) {
        self.onStop = onStop
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStateChanged(_:)),
            name: .recordingActiveStateChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func bind(recorder: ScreenRecorder) {
        self.recorder = recorder
    }

    @objc private func handleStateChanged(_ notification: Notification) {
        let active = notification.userInfo?["active"] as? Bool ?? false
        setVisible(active)
    }

    func setVisible(_ visible: Bool) {
        if visible {
            installIfNeeded()
            startElapsedTimer()
            refreshButton()
        } else {
            stopElapsedTimer()
            removeStatusItem()
        }
    }

    private func installIfNeeded() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(stopClicked)
        item.button?.sendAction(on: [.leftMouseUp])
        item.button?.toolTip = String(localized: "Stop Recording")
        statusItem = item
    }

    private func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshButton()
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func refreshButton() {
        guard let button = statusItem?.button else { return }

        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        if let image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            image.isTemplate = false
            button.image = image
            button.contentTintColor = .systemRed
        }

        if let elapsed = recorder?.elapsedTime, recorder?.state.isActive == true {
            button.title = " \(formatTime(elapsed))"
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        } else {
            button.title = ""
        }
    }

    @objc private func stopClicked() {
        onStop()
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
