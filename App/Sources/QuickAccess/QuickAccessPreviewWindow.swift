import AppKit
import SwiftUI
import SharedKit

@MainActor
final class QuickAccessPreviewWindow: NSPanel {
    var onClose: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onShare: (() -> Void)?
    var onDelete: (() -> Void)?

    private let image: CGImage

    init(image: CGImage, anchorScreen: NSScreen?) {
        self.image = image
        let screen = anchorScreen ?? NSScreen.main ?? NSScreen.screens.first!
        let imageSize = CGSize(width: image.width, height: image.height)
        let previewSize = QuickAccessPreviewGeometry.contentSize(
            imagePixelSize: imageSize,
            availableSize: screen.visibleFrame.size,
            maxViewportFraction: 0.82
        )
        let toolbarHeight: CGFloat = 52
        let contentWidth = max(320, previewSize.width)
        let contentHeight = max(220, previewSize.height) + toolbarHeight
        let contentRect = NSRect(
            x: screen.visibleFrame.midX - contentWidth / 2,
            y: screen.visibleFrame.midY - contentHeight / 2,
            width: contentWidth,
            height: contentHeight
        )

        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        self.title = String(localized: "Preview")
        self.level = .normal
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.isRestorable = false
        self.minSize = NSSize(width: 320, height: 220)
        self.collectionBehavior = [.canJoinAllSpaces]

        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let view = QuickAccessPreviewView(
            image: nsImage,
            onCopy: { [weak self] in self?.onCopy?() },
            onSave: { [weak self] in self?.onSave?() },
            onShare: { [weak self] in self?.onShare?() },
            onDelete: { [weak self] in self?.onDelete?() }
        )
        self.contentView = NSHostingView(rootView: view)
    }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func close() {
        onClose?()
        super.close()
    }
}

private struct QuickAccessPreviewView: View {
    let image: NSImage
    let onCopy: () -> Void
    let onSave: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

            HStack(spacing: 10) {
                previewActionButton(
                    title: String(localized: "Copy"),
                    systemImage: "doc.on.doc",
                    action: onCopy
                )
                .keyboardShortcut("c", modifiers: .command)

                previewActionButton(
                    title: String(localized: "Share"),
                    systemImage: "square.and.arrow.up",
                    action: onShare
                )
                .keyboardShortcut("i", modifiers: [.command, .shift])

                previewActionButton(
                    title: String(localized: "Delete"),
                    systemImage: "trash",
                    isDestructive: true,
                    action: onDelete
                )
                .keyboardShortcut(.delete, modifiers: [])

                Spacer()

                previewSaveButton(action: onSave)
                .keyboardShortcut("s", modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func previewSaveButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(String(localized: "Save"))
            } icon: {
                SaveIcon()
                    .font(.system(size: 13, weight: .semibold))
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(buttonFill(isPrimary: true, isDestructive: false))
            )
            .foregroundStyle(buttonForeground(isPrimary: true, isDestructive: false))
        }
        .buttonStyle(.plain)
        .help(String(localized: "Save"))
    }

    private func previewActionButton(
        title: String,
        systemImage: String,
        isPrimary: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(buttonFill(isPrimary: isPrimary, isDestructive: isDestructive))
                )
                .foregroundStyle(buttonForeground(isPrimary: isPrimary, isDestructive: isDestructive))
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func buttonFill(isPrimary: Bool, isDestructive: Bool) -> Color {
        if isPrimary { return Color.accentColor }
        if isDestructive { return Color.red.opacity(0.14) }
        return Color.primary.opacity(0.08)
    }

    private func buttonForeground(isPrimary: Bool, isDestructive: Bool) -> Color {
        if isPrimary { return .white }
        if isDestructive { return .red }
        return .primary
    }
}
