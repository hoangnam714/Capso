// App/Sources/Preferences/Tabs/ShortcutSettingsView.swift
import SwiftUI
import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    // Defaults mirror macOS Screenshots shortcuts so Capso can replace them
    // after the user disables System Settings → Keyboard → Screenshots.
    static let captureAllInOne = Self("captureAllInOne", default: .init(.five, modifiers: [.shift, .command]))
    static let captureArea = Self("captureArea", default: .init(.four, modifiers: [.shift, .command]))
    static let captureFullscreen = Self("captureFullscreen", default: .init(.three, modifiers: [.shift, .command]))
    static let captureWindow = Self("captureWindow")
    static let captureText = Self("captureText")
    static let recordScreen = Self("recordScreen")
    static let captureScrolling = Self("captureScrolling")
    static let captureAreaToClipboard = Self("captureAreaToClipboard", default: .init(.four, modifiers: [.control, .shift, .command]))
    static let captureAreaAndShare = Self("captureAreaAndShare")
    static let captureAreaAndAnnotate = Self("captureAreaAndAnnotate")
    static let screenshotHistory = Self("screenshotHistory")
    static let captureAndTranslate = Self("captureAndTranslate")
    static let translateSelectedText = Self("translateSelectedText")
    /// No default binding — opt-in. Self-Timer is discoverable from the
    /// menu bar; shipping a default risks colliding with whatever the user
    /// has already bound in macOS or third-party apps.
    static let selfTimerCapture = Self("selfTimerCapture")
    /// Replays the last capture (area / window / fullscreen) without showing
    /// the selection overlay. Unbound by default — user must assign a key.
    static let captureLastArea = Self("captureLastArea")
}

struct ShortcutSettingsView: View {
    private struct ContextualShortcut: Identifiable {
        let id: String
        let scope: LocalizedStringKey
        let action: LocalizedStringKey
        let shortcut: String
    }

    private let contextualShortcuts: [ContextualShortcut] = [
        ContextualShortcut(id: "all-in-one-copy", scope: "All-in-One", action: "Copy selected area", shortcut: "⌘C"),
        ContextualShortcut(id: "all-in-one-save", scope: "All-in-One", action: "Save selected area", shortcut: "⌘S"),
        ContextualShortcut(id: "all-in-one-pin", scope: "All-in-One", action: "Pin selected area", shortcut: "⌘P"),
        ContextualShortcut(id: "all-in-one-cancel", scope: "All-in-One", action: "Cancel", shortcut: "Esc"),
        ContextualShortcut(id: "quick-access-copy", scope: "Quick Access", action: "Copy", shortcut: "⌘C"),
        ContextualShortcut(id: "quick-access-save", scope: "Quick Access", action: "Save", shortcut: "⌘S"),
        ContextualShortcut(id: "quick-access-annotate", scope: "Quick Access", action: "Annotate", shortcut: "⌘E"),
        ContextualShortcut(id: "quick-access-pin", scope: "Quick Access", action: "Pin", shortcut: "⌘P")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Shortcuts")
                .font(.system(size: 20, weight: .bold))

            // macOS Screenshots conflict note
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Capso defaults use the same keys as macOS Screenshots (⇧⌘3 / ⇧⌘4 / ⌃⇧⌘4 / ⇧⌘5). Disable those system shortcuts first, or Capso won’t receive them.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Text("System Settings → Keyboard → Keyboard Shortcuts → Screenshots")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Open Settings") {
                        openScreenshotShortcutSettings()
                    }
                    .controlSize(.small)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.25), lineWidth: 0.5)
            )

            // Info banner
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                Text("Click a customizable shortcut to record a new combination. Press Esc to cancel or Delete to remove. Contextual shortcuts are fixed and work only while that panel is active.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.2), lineWidth: 0.5)
            )

            SettingGroup(title: "Customizable Shortcuts") {
                SettingCard {
                    shortcutRow("All-in-One", name: .captureAllInOne)
                    shortcutRow("Capture Area", name: .captureArea, showDivider: true)
                    shortcutRow("Capture Fullscreen", name: .captureFullscreen, showDivider: true)
                    shortcutRow("Capture Window", name: .captureWindow, showDivider: true)
                    shortcutRow("Capture Text (OCR)", name: .captureText, showDivider: true)
                    shortcutRow("Scrolling Capture", name: .captureScrolling, showDivider: true)
                    shortcutRow("Self-Timer", name: .selfTimerCapture, showDivider: true)
                    shortcutRow("Capture Area to Clipboard", name: .captureAreaToClipboard, showDivider: true)
                    shortcutRow("Capture and Share to Cloud", name: .captureAreaAndShare, showDivider: true)
                    shortcutRow("Capture Area & Annotate", name: .captureAreaAndAnnotate, showDivider: true)
                    shortcutRow("Capture & Translate", name: .captureAndTranslate, showDivider: true)
                    shortcutRow("Translate Selected Text", name: .translateSelectedText, showDivider: true)
                    shortcutRow("Capture Previous Area", name: .captureLastArea, showDivider: true)
                    shortcutRow("Start / Stop Recording", name: .recordScreen, showDivider: true)
                    shortcutRow("Screenshot History", name: .screenshotHistory)
                }
            }

            SettingGroup(title: "Contextual Shortcuts") {
                SettingCard {
                    ForEach(Array(contextualShortcuts.enumerated()), id: \.element.id) { index, item in
                        contextualShortcutRow(item, showDivider: index > 0)
                    }
                }
            }
        }
    }

    private func openScreenshotShortcutSettings() {
        // Opens Keyboard settings; user then selects Screenshots in the sidebar.
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func shortcutRow(_ label: LocalizedStringKey, name: KeyboardShortcuts.Name, showDivider: Bool = false) -> some View {
        SettingRow(label: label, showDivider: showDivider) {
            KeyboardShortcuts.Recorder(for: name)
                .controlSize(.small)
        }
    }

    private func contextualShortcutRow(_ item: ContextualShortcut, showDivider: Bool = false) -> some View {
        SettingRow(label: item.action, sublabel: item.scope, showDivider: showDivider) {
            ShortcutKeycap(text: item.shortcut)
        }
    }
}

private struct ShortcutKeycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
    }
}
