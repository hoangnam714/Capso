import AppKit
import SwiftUI
import SharedKit

@MainActor
final class QuickAccessPreviewWindow: NSPanel {
    var onClose: (() -> Void)?
    var shouldRestoreSourceOnClose = true
    var onAnnotate: (() -> Void)?
    var onPin: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onShare: (() -> Void)?
    var onDelete: (() -> Void)?
    var onCopyPath: (() -> Void)?
    var onDuplicate: (() -> Void)?
    var onShowInFinder: (() -> Void)?
    var onOCR: (() -> Void)?
    var onTranslate: (() -> Void)?
    var onUpload: (() -> Void)?

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
        let minContentWidth: CGFloat = 460
        let contentWidth = max(minContentWidth, previewSize.width)
        let contentHeight = max(260, previewSize.height) + toolbarHeight
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
        self.minSize = NSSize(width: minContentWidth, height: 260)
        self.collectionBehavior = [.canJoinAllSpaces]

        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let view = QuickAccessPreviewView(
            image: nsImage,
            onClose: { [weak self] in self?.close() },
            onAnnotate: { [weak self] in self?.onAnnotate?() },
            onPin: { [weak self] in self?.onPin?() },
            onCopy: { [weak self] in self?.onCopy?() },
            onSave: { [weak self] in self?.onSave?() },
            onShare: { [weak self] in self?.onShare?() },
            onDelete: { [weak self] in self?.onDelete?() },
            onCopyPath: { [weak self] in self?.onCopyPath?() },
            onDuplicate: { [weak self] in self?.onDuplicate?() },
            onShowInFinder: { [weak self] in self?.onShowInFinder?() },
            onOCR: { [weak self] in self?.onOCR?() },
            onTranslate: { [weak self] in self?.onTranslate?() },
            onUpload: { [weak self] in self?.onUpload?() }
        )
        self.contentView = NSHostingView(rootView: view)
    }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func close() {
        onClose?()
        super.close()
    }
}

private struct QuickAccessPreviewView: View {
    let image: NSImage
    let onClose: () -> Void
    let onAnnotate: (() -> Void)?
    let onPin: (() -> Void)?
    let onCopy: () -> Void
    let onSave: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void
    let onCopyPath: () -> Void
    let onDuplicate: () -> Void
    let onShowInFinder: () -> Void
    let onOCR: () -> Void
    let onTranslate: () -> Void
    let onUpload: (() -> Void)?

    @State private var isOptionHeld = false

    private var showsAdvancedToolbar: Bool { isOptionHeld }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .onTapGesture(count: 2) {
                    onAnnotate?()
                }
                .onHover { hovering in
                    if hovering {
                        isOptionHeld = NSEvent.modifierFlags.contains(.option)
                    }
                }

            HStack(spacing: 4) {
                if showsAdvancedToolbar {
                    previewActionButton(
                        title: String(localized: "Copy Path"),
                        systemImage: "link",
                        action: onCopyPath
                    )
                    previewActionButton(
                        title: String(localized: "Duplicate"),
                        systemImage: "plus.square.on.square",
                        action: onDuplicate
                    )
                    previewActionButton(
                        title: String(localized: "Show in Finder"),
                        systemImage: "folder",
                        action: onShowInFinder
                    )
                    previewActionButton(
                        title: String(localized: "OCR"),
                        systemImage: "text.viewfinder",
                        action: onOCR
                    )
                    previewActionButton(
                        title: String(localized: "Translate"),
                        systemImage: "character.bubble",
                        action: onTranslate
                    )
                    if let onUpload {
                        previewActionButton(
                            title: String(localized: "Upload to Cloud"),
                            systemImage: "icloud.and.arrow.up",
                            action: onUpload
                        )
                    }
                } else {
                    if let onAnnotate {
                        previewActionButton(
                            title: String(localized: "Edit"),
                            systemImage: "pencil.tip.crop.circle",
                            action: onAnnotate
                        )
                        .keyboardShortcut("e", modifiers: .command)
                    }

                    previewActionButton(
                        title: String(localized: "Copy"),
                        systemImage: "doc.on.doc",
                        action: onCopy
                    )
                    .keyboardShortcut("c", modifiers: .command)

                    previewActionButton(
                        title: String(localized: "Save"),
                        systemImage: "square.and.arrow.down",
                        action: onSave
                    )
                    .keyboardShortcut("s", modifiers: .command)

                    if let onPin {
                        previewActionButton(
                            title: String(localized: "Pin"),
                            systemImage: "pin",
                            action: onPin
                        )
                        .keyboardShortcut("p", modifiers: .command)
                    }

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
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
            .animation(.easeOut(duration: 0.18), value: showsAdvancedToolbar)
        }
        .background(hiddenEscapeButton)
        .onModifierKeysChanged(mask: .option) { _, new in
            isOptionHeld = new.contains(.option)
        }
    }

    private var hiddenEscapeButton: some View {
        Button("") { onClose() }
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .frame(width: 0, height: 0)
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
