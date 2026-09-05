// App/Sources/Recording/RecordingControlsWindow.swift
import AppKit
import SwiftUI
import RecordingKit

@MainActor
final class RecordingControlsWindow: NSPanel {
    override var canBecomeKey: Bool { true }

    init(recordingFrame: CGRect, screen: NSScreen, recorder: ScreenRecorder, onStop: @escaping () -> Void, onRestart: @escaping () -> Void, onDelete: @escaping () -> Void) {
        let panelSize = NSSize(width: 250, height: 52)
        let frame = Self.preferredFrame(
            recordingFrame: recordingFrame,
            panelSize: panelSize,
            screen: screen
        )

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver + 2
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.isMovableByWindowBackground = true
        self.acceptsMouseMovedEvents = true
        self.hidesOnDeactivate = false
        self.sharingType = .none

        let view = RecordingControlsView(recorder: recorder, onStop: onStop, onRestart: onRestart, onDelete: onDelete)
        self.contentView = NSHostingView(rootView: view)
    }

    /// Place controls where they stay clickable — fullscreen selections often
    /// cover the menu bar / dock, so anchoring below the capture rect fails.
    static func preferredFrame(recordingFrame: CGRect, panelSize: NSSize, screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let width = panelSize.width
        let height = panelSize.height

        let intersection = recordingFrame.intersection(visible)
        let visibleArea = max(visible.width * visible.height, 1)
        let coverage = (intersection.width * intersection.height) / visibleArea
        let isFullScreenLike = coverage > 0.90

        var x: CGFloat
        var y: CGFloat

        if isFullScreenLike {
            x = visible.midX - width / 2
            y = visible.minY + 16
        } else {
            x = recordingFrame.midX - width / 2
            y = recordingFrame.minY - height - 18
            if y < visible.minY + 8 {
                y = recordingFrame.maxY + 18
            }
        }

        x = max(visible.minX + 8, min(x, visible.maxX - width - 8))
        y = max(visible.minY + 8, min(y, visible.maxY - height - 8))

        return NSRect(x: x, y: y, width: width, height: height)
    }

    func show() {
        orderFrontRegardless()
        makeKey()
    }
}

private struct RecordingControlsView: View {
    let recorder: ScreenRecorder
    let onStop: () -> Void
    let onRestart: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.red.opacity(0.95))
                    .frame(width: 28, height: 28)
                    .background(.red.opacity(0.14))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Stop recording")

            Text(formatTime(recorder.elapsedTime))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.red.opacity(0.95))
                .frame(minWidth: 52, alignment: .leading)

            Divider().frame(height: 18)

            Button(action: {
                if recorder.state == .recording {
                    recorder.pause()
                } else if recorder.state == .paused {
                    recorder.resume()
                }
            }) {
                Image(systemName: recorder.state == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(recorder.state == .paused ? "Resume recording" : "Pause recording")

            Button(action: onRestart) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Restart recording")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Delete recording")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.78))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
