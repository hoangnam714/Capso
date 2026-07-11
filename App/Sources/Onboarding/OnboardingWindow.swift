// App/Sources/Onboarding/OnboardingWindow.swift
import AppKit
import SwiftUI
import SharedKit

@MainActor
final class OnboardingWindow: NSPanel {
    private let permissionManager: PermissionManager
    private let settings: AppSettings
    private var onCompleteAction: (() -> Void)?

    init(
        permissionManager: PermissionManager,
        settings: AppSettings,
        onComplete: @escaping () -> Void
    ) {
        self.permissionManager = permissionManager
        self.settings = settings
        self.onCompleteAction = onComplete

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        title = String(localized: "Welcome to Capso")
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        center()

        let view = OnboardingView(
            permissionManager: permissionManager,
            settings: settings,
            onContinue: { [weak self] in
                self?.finish()
            }
        )
        contentView = NSHostingView(rootView: view)
    }

    func show() {
        // Show in Dock while onboarding so the window is easy to find.
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish() {
        settings.permissionsOnboardingShown = true
        onCompleteAction?()
        onCompleteAction = nil
        close()
        // Drop back to menu-bar style unless Preferences is open.
        if NSApp.windows.filter({ $0.isVisible && $0 !== self }).isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    override func close() {
        // Closing via traffic light still completes onboarding so we don't loop.
        if !settings.permissionsOnboardingShown {
            settings.permissionsOnboardingShown = true
            onCompleteAction?()
            onCompleteAction = nil
        }
        super.close()
        if NSApp.windows.filter({ $0.isVisible && $0 !== self }).isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
