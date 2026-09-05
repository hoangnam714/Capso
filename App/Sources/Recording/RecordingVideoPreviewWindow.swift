import AppKit
import SwiftUI
import AVKit

@MainActor
final class RecordingVideoPreviewWindow: NSPanel {
    var onClose: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onShare: (() -> Void)?
    var onDelete: (() -> Void)?

    private let player: AVPlayer

    init(videoURL: URL, anchorScreen: NSScreen?) {
        self.player = AVPlayer(url: videoURL)

        let screen = anchorScreen ?? NSScreen.main ?? NSScreen.screens.first!
        let contentWidth: CGFloat = min(max(480, screen.visibleFrame.width * 0.55), 900)
        let contentHeight: CGFloat = min(max(320, screen.visibleFrame.height * 0.55), 620)
        let toolbarHeight: CGFloat = 52
        let frame = NSRect(
            x: screen.visibleFrame.midX - contentWidth / 2,
            y: screen.visibleFrame.midY - (contentHeight + toolbarHeight) / 2,
            width: contentWidth,
            height: contentHeight + toolbarHeight
        )

        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        title = String(localized: "Preview")
        level = .normal
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isRestorable = false
        minSize = NSSize(width: 360, height: 260)
        collectionBehavior = [.canJoinAllSpaces]

        let view = RecordingVideoPreviewView(
            player: player,
            onCopy: { [weak self] in self?.onCopy?() },
            onSave: { [weak self] in self?.onSave?() },
            onShare: { [weak self] in self?.onShare?() },
            onDelete: { [weak self] in self?.onDelete?() }
        )
        contentView = NSHostingView(rootView: view)
    }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        player.play()
    }

    override func close() {
        player.pause()
        onClose?()
        super.close()
    }
}

private struct RecordingVideoPreviewView: View {
    let player: AVPlayer
    let onCopy: () -> Void
    let onSave: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VideoPlayer(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

            HStack(spacing: 4) {
                previewToolButton(icon: "doc.on.doc", title: String(localized: "Copy"), action: onCopy)
                    .keyboardShortcut("c", modifiers: .command)
                previewToolButton(icon: "square.and.arrow.down", title: String(localized: "Save"), isPrimary: true, action: onSave)
                    .keyboardShortcut("s", modifiers: .command)
                previewToolButton(icon: "square.and.arrow.up", title: String(localized: "Share"), action: onShare)
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                previewToolButton(icon: "trash", title: String(localized: "Delete"), isDestructive: true, action: onDelete)
                    .keyboardShortcut(.delete, modifiers: [])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func previewToolButton(
        icon: String,
        title: String,
        isPrimary: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isPrimary ? .white : (isDestructive ? .red : .primary))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isPrimary ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .help(Text(title))
    }
}
