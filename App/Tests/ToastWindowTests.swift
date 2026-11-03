import AppKit
import SwiftUI
import XCTest
import SharedKit

final class ToastWindowTests: XCTestCase {
    @MainActor
    func testActionToastsDisplayReplaceAndDismiss() async throws {
        _ = NSApplication.shared
        let suite = "capso.toast.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let keyWindow = NSApp.keyWindow

        let locations: [ToastWindow.ActionLocation] = [.preview, .history, .editor]
        for (index, location) in locations.enumerated() {
            let message = "Copied to clipboard \(index)"
            ToastWindow.showAction(message, at: location, settings: settings)
            try await Task.sleep(for: .milliseconds(100))
            let windows = visibleToasts()
            XCTAssertEqual(windows.count, 1)
            let label = windows.first?.contentView?.subviews.compactMap { $0 as? NSTextField }.first
            XCTAssertEqual(label?.stringValue, message)
            XCTAssertTrue(windows.first?.ignoresMouseEvents == true)
            XCTAssertFalse(windows.first?.hidesOnDeactivate ?? true)
            XCTAssertTrue(NSApp.keyWindow === keyWindow)
        }

        // Exercise rapid replacement and bounded layout with a long localized message.
        for index in 0..<20 {
            ToastWindow.showAction(String(repeating: "Đã sao chép \(index) ", count: 30), at: .preview, settings: settings)
        }
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(visibleToasts().count, 1)
        XCTAssertLessThanOrEqual(visibleToasts().first?.frame.width ?? .infinity, 500)
        try await Task.sleep(for: .seconds(2))
        XCTAssertTrue(visibleToasts().isEmpty)

        for location in locations {
            settings.previewActionToastsEnabled = true
            settings.historyActionToastsEnabled = true
            settings.editorActionToastsEnabled = true
            switch location {
            case .preview: settings.previewActionToastsEnabled = false
            case .history: settings.historyActionToastsEnabled = false
            case .editor: settings.editorActionToastsEnabled = false
            }
            ToastWindow.showAction("Disabled", at: location, settings: settings)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(visibleToasts().isEmpty)
        }

    }

    @MainActor
    func testDirectToastUsedByOCRDismisses() async throws {
        _ = NSApplication.shared
        let toast = ToastWindow(message: "Text copied")
        toast.show(autoDismissAfter: 0.2)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(toast.isVisible)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(visibleToasts().isEmpty)
    }

    @MainActor
    func testToastSurvivesClosingSwiftUIPreview() async throws {
        _ = NSApplication.shared
        let suite = "capso.toast.preview-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preview = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 320, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        preview.isReleasedWhenClosed = false
        preview.contentView = NSHostingView(rootView: Text("Preview").frame(width: 320, height: 200))
        preview.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(100))
        ToastWindow.showAction("Copied to clipboard", at: .preview, settings: AppSettings(defaults: defaults))
        preview.close()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(visibleToasts().count, 1)
        XCTAssertGreaterThan(visibleToasts().first?.alphaValue ?? 0, 0.9)
        try await Task.sleep(for: .seconds(2))
        XCTAssertTrue(visibleToasts().isEmpty)
    }

    @MainActor
    private func visibleToasts() -> [ToastWindow] {
        NSApp.windows.compactMap { $0 as? ToastWindow }.filter(\.isVisible)
    }
}
