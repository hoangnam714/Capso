// App/Sources/Onboarding/OnboardingView.swift
import SwiftUI
import AppKit
import LaunchAtLogin
import SharedKit

struct OnboardingView: View {
    let permissionManager: PermissionManager
    let settings: AppSettings
    let onContinue: () -> Void

    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var screenRecordingGranted = false
    @State private var accessibilityGranted = false
    @State private var cameraGranted = false
    @State private var microphoneGranted = false
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            SettingGroup(title: "Required Access") {
                SettingCard {
                    permissionRow(
                        title: "Screen Recording",
                        subtitle: "Needed for screenshots and screen recording",
                        isGranted: screenRecordingGranted,
                        isRequired: true,
                        showDivider: false,
                        openSettings: { permissionManager.openSettings(for: .screenRecording) }
                    ) {
                        await permissionManager.requestScreenRecordingPermission()
                        await refreshPermissions()
                    }
                    permissionRow(
                        title: "Accessibility",
                        subtitle: "Needed for selected-text translation shortcuts",
                        isGranted: accessibilityGranted,
                        isRequired: false,
                        showDivider: true,
                        openSettings: { permissionManager.openSettings(for: .accessibility) }
                    ) {
                        permissionManager.requestAccessibilityPermission()
                        await refreshPermissions()
                    }
                }
            }

            SettingGroup(title: "Optional for Recording") {
                SettingCard {
                    permissionRow(
                        title: "Camera",
                        subtitle: "Webcam overlay during recordings",
                        isGranted: cameraGranted,
                        isRequired: false,
                        showDivider: false,
                        openSettings: { permissionManager.openSettings(for: .camera) }
                    ) {
                        await permissionManager.requestCameraPermission()
                        await refreshPermissions()
                    }
                    permissionRow(
                        title: "Microphone",
                        subtitle: "Record system / mic audio",
                        isGranted: microphoneGranted,
                        isRequired: false,
                        showDivider: true,
                        openSettings: { permissionManager.openSettings(for: .microphone) }
                    ) {
                        await permissionManager.requestMicrophonePermission()
                        await refreshPermissions()
                    }
                }
            }

            SettingGroup(title: "Startup") {
                SettingCard {
                    SettingRow(
                        label: "Launch at Login",
                        sublabel: "Start Capso automatically when you log in"
                    ) {
                        Toggle("", isOn: launchAtLoginBinding)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }

            footer
        }
        .padding(28)
        .frame(width: 560)
        .task {
            await refreshPermissions()
            // Default Launch at Login on for first-run onboarding.
            if !LaunchAtLogin.isEnabled {
                launchAtLoginEnabled = true
                LaunchAtLogin.isEnabled = true
                settings.startAtLogin = true
            }
            UserDefaults.standard.set(true, forKey: "didApplyDefaultLaunchAtLogin")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshPermissions() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome to Capso")
                .font(.system(size: 24, weight: .bold))
            Text("Grant a few permissions so capture, recording, and translation work. You can change these later in Settings.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if !screenRecordingGranted {
                Label("Screen Recording is required to capture", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            } else {
                Label("Ready to capture", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
            }

            Spacer()

            Button("Refresh") {
                Task { await refreshPermissions() }
            }
            .controlSize(.small)
            .disabled(isRefreshing)

            Button(screenRecordingGranted ? "Continue" : "Continue Anyway") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 4)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginEnabled },
            set: { newValue in
                launchAtLoginEnabled = newValue
                LaunchAtLogin.isEnabled = newValue
                settings.startAtLogin = newValue
            }
        )
    }

    private func permissionRow(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        isGranted: Bool,
        isRequired: Bool,
        showDivider: Bool,
        openSettings: @escaping () -> Void,
        request: @escaping () async -> Void
    ) -> some View {
        SettingRow(label: title, sublabel: subtitle, showDivider: showDivider) {
            HStack(spacing: 10) {
                statusBadge(isGranted, isRequired: isRequired)
                Button {
                    if isGranted {
                        openSettings()
                    } else {
                        Task { await request() }
                    }
                } label: {
                    Label(
                        isGranted ? "Open Settings" : "Allow",
                        systemImage: isGranted ? "gearshape" : "hand.tap"
                    )
                }
                .controlSize(.small)
            }
        }
    }

    private func statusBadge(_ isGranted: Bool, isRequired: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isGranted ? Color.green : (isRequired ? Color.orange : Color.secondary.opacity(0.5)))
                .frame(width: 7, height: 7)
            Text(isGranted ? "Allowed" : (isRequired ? "Required" : "Optional"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isGranted ? .secondary : .primary)
        }
        .frame(width: 80, alignment: .leading)
    }

    private func refreshPermissions() async {
        isRefreshing = true
        await permissionManager.refreshAll()
        screenRecordingGranted = permissionManager.screenRecordingGranted
        accessibilityGranted = permissionManager.accessibilityGranted
        cameraGranted = permissionManager.cameraGranted
        microphoneGranted = permissionManager.microphoneGranted
        isRefreshing = false
    }
}
