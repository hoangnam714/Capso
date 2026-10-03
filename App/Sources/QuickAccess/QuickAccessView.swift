// App/Sources/QuickAccess/QuickAccessView.swift
import SwiftUI
import AppKit
import CaptureKit
import SharedKit
import ShareKit

struct QuickAccessView: View {
    let thumbnail: NSImage
    let captureImage: CGImage           // used for cloud upload (temp-file write)
    let dimensions: String           // e.g. "1920×1080"
    let capturedAt: Date
    let targetLanguageDisplay: String?  // e.g. "Simplified Chinese"
    let shareCoordinator: ShareCoordinator?
    /// Called with the public URL string when a cloud upload succeeds.
    /// Use this to persist the URL to the history entry.
    let onUploadSucceeded: ((String) -> Void)?
    let onCopy: () -> Void
    let onSave: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void
    let onCopyPath: () -> Void
    let onDuplicate: () -> Void
    let onShowInFinder: () -> Void
    let onUpload: (() -> Void)?
    let onAnnotate: () -> Void
    let onOCR: () -> Void
    let onTranslate: () -> Void
    let onPin: () -> Void
    let onPreview: () -> Void
    let onClose: () -> Void
    /// Notifies the hosting panel so auto-dismiss can pause while hovered.
    var onHoveringChanged: ((Bool) -> Void)? = nil

    @State private var isHovering = false
    @State private var isOptionHeld = false
    @State private var hoveredAction: ToolbarAction?
    @FocusState private var isFocused: Bool

    private enum ToolbarAction: Hashable {
        case annotate, copy, save, share, delete, pin
        case copyPath, duplicate, showInFinder, ocr, translate, upload
    }

    private var isRevealed: Bool { isHovering || isFocused }
    private var showsAdvancedToolbar: Bool { isRevealed && isOptionHeld }
    private static let panelCornerRadius: CGFloat = 14
    private static let thumbnailSize = CGSize(width: 268, height: 116)

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        VStack(spacing: 9) {
            thumbnailFrame

            VStack(spacing: 6) {
                captionRow
                toolbar
            }
            .frame(minHeight: 50)
        }
        .padding(8)
        .background(hiddenEscapeButton)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                .stroke(panelStroke, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .offset(y: isRevealed ? -2 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.26), value: isRevealed)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                isOptionHeld = NSEvent.modifierFlags.contains(.option)
            }
            onHoveringChanged?(hovering)
        }
        .onModifierKeysChanged(mask: .option) { _, new in
            isOptionHeld = new.contains(.option)
        }
        .focusable()
        .focused($isFocused)
    }

    private var panelStroke: Color {
        isRevealed ? Color.primary.opacity(0.14) : Color.primary.opacity(0.08)
    }

    // MARK: - Thumbnail

    private var thumbnailFrame: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
                .background(Color.black.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .onTapGesture(count: 2, perform: onPreview)
                .onTapGesture(count: 1, perform: onAnnotate)
                .help("Click to annotate · Double-click to preview")
                .accessibilityLabel(Text("Screenshot preview"))
                .accessibilityHint(Text("Click to annotate, double-click to enlarge"))

            if isRevealed {
                Button(action: onPin) {
                    Image(systemName: "pin")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.78))
                        .frame(width: 24, height: 24)
                        .background(.regularMaterial, in: Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .padding(7)
                .help(String(localized: "Pin"))
                .keyboardShortcut("p", modifiers: .command)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isRevealed {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.78))
                        .frame(width: 24, height: 24)
                        .background(.regularMaterial, in: Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .padding(7)
                .transition(.opacity)
                .help("Close")
            }
        }
    }

    // MARK: - Caption (at rest)

    private var captionRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label {
                Text(captionTitle)
                    .font(.system(size: 13, weight: .semibold))
            } icon: {
                Image(systemName: captionIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(captionIconColor)
            }
            Spacer()
            if let key = hoveredShortcutKey {
                ShortcutKeyPill(text: key)
            } else {
                Text(metaLine)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
        }
        .padding(.horizontal, 6)
    }

    private var captionTitle: String {
        if let action = hoveredAction { return label(action) }
        if showsAdvancedToolbar { return String(localized: "Advanced") }
        return String(localized: "Captured")
    }

    private var captionIcon: String {
        if hoveredAction != nil { return "hand.tap" }
        if showsAdvancedToolbar { return "ellipsis.circle.fill" }
        return "checkmark.circle.fill"
    }

    private var captionIconColor: Color {
        if hoveredAction != nil { return .secondary }
        if showsAdvancedToolbar { return .secondary }
        return .green
    }

    private var metaLine: String {
        if isRevealed && !showsAdvancedToolbar {
            return "\(dimensions) · \(relativeTime) · ⌥"
        }
        return "\(dimensions) · \(relativeTime)"
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: capturedAt, relativeTo: Date())
    }

    private var hoveredShortcutKey: String? {
        guard let action = hoveredAction else { return nil }
        switch action {
        case .annotate:  return "⌘E"
        case .copy:      return "⌘C"
        case .save:      return "⌘S"
        case .share:     return "⌘⇧I"
        case .delete:    return "⌫"
        case .pin:       return "⌘P"
        case .copyPath, .duplicate, .showInFinder, .ocr, .translate, .upload:
            return nil
        }
    }

    /// Primary actions by default; hold ⌥ while focused/hovering for advanced actions.
    private var toolbar: some View {
        HStack(spacing: 4) {
            if showsAdvancedToolbar {
                advancedToolbar
            } else {
                primaryToolbar
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(showsAdvancedToolbar ? "Advanced actions" : "Quick Access actions"))
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: showsAdvancedToolbar)
    }

    private var primaryToolbar: some View {
        Group {
            toolButton(.annotate, icon: "pencil.tip.crop.circle", action: onAnnotate)
            toolButton(.copy, icon: "doc.on.doc", action: onCopy)
            toolButton(.save, icon: "square.and.arrow.down", action: onSave)
            toolButton(.delete, icon: "trash", action: onDelete)
            toolButton(.share, icon: "square.and.arrow.up", action: onShare)
        }
    }

    private var advancedToolbar: some View {
        Group {
            toolButton(.copyPath, icon: "link", action: onCopyPath)
            toolButton(.duplicate, icon: "plus.square.on.square", action: onDuplicate)
            toolButton(.showInFinder, icon: "folder", action: onShowInFinder)
            toolButton(.ocr, icon: "text.viewfinder", action: onOCR)
            toolButton(.translate, icon: "character.bubble", action: onTranslate)
            if onUpload != nil {
                toolButton(.upload, icon: "icloud.and.arrow.up", action: { onUpload?() })
            }
        }
    }

    @ViewBuilder
    private func toolButton(
        _ kind: ToolbarAction,
        icon: String,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(toolForeground(kind, isPrimary: isPrimary))
                .frame(width: 29, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(toolBackground(kind, isPrimary: isPrimary))
                )
        }
        .buttonStyle(.plain)
        .onHover { hoveredAction = $0 ? kind : nil }
        .help(Text(label(kind)))
        .accessibilityLabel(Text(label(kind)))
        .accessibilityHint(Text(hintForAccessibility(kind)))

        // Apply local keyboard shortcut so pressing the hinted key activates the action
        // whenever the Quick Access panel is key. `.nonactivatingPanel` + canBecomeKey=true
        // means shortcuts work while the panel is frontmost in our app, without stealing
        // focus from other apps.
        if let shortcut = shortcut(for: kind) {
            button.keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
        } else {
            button
        }
    }

    private func toolForeground(_ kind: ToolbarAction, isPrimary: Bool) -> Color {
        if isPrimary { return .white }
        if kind == .delete { return Color.red.opacity(hoveredAction == kind ? 0.96 : 0.78) }
        return Color.primary.opacity(hoveredAction == kind ? 0.96 : 0.78)
    }

    private func toolBackground(_ kind: ToolbarAction, isPrimary: Bool) -> Color {
        if isPrimary {
            return Color.accentColor.opacity(hoveredAction == kind ? 0.92 : 0.78)
        }
        return hoveredAction == kind ? Color.primary.opacity(0.12) : Color.clear
    }

    private func shortcut(for kind: ToolbarAction) -> (key: KeyEquivalent, modifiers: EventModifiers)? {
        switch kind {
        case .annotate:  return ("e", [.command])
        case .copy:      return ("c", [.command])
        case .save:      return ("s", [.command])
        case .share:     return ("i", [.command, .shift])
        case .delete:    return (.delete, [])
        case .pin:       return ("p", [.command])
        case .copyPath, .duplicate, .showInFinder, .ocr, .translate, .upload:
            return nil
        }
    }

    private var hiddenEscapeButton: some View {
        Button(action: onClose) { EmptyView() }
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
    }

    private func label(_ kind: ToolbarAction) -> String {
        switch kind {
        case .annotate: return String(localized: "Edit")
        case .copy: return String(localized: "Copy")
        case .save: return String(localized: "Save")
        case .share: return String(localized: "Share")
        case .delete: return String(localized: "Delete")
        case .pin: return String(localized: "Pin")
        case .copyPath: return String(localized: "Copy Path")
        case .duplicate: return String(localized: "Duplicate")
        case .showInFinder: return String(localized: "Show in Finder")
        case .ocr: return String(localized: "OCR")
        case .translate: return String(localized: "Translate")
        case .upload: return String(localized: "Upload to Cloud")
        }
    }

    private func hintForAccessibility(_ kind: ToolbarAction) -> String {
        switch kind {
        case .annotate: return String(localized: "Annotate screenshot")
        case .copy: return String(localized: "Copy to clipboard")
        case .save: return String(localized: "Save screenshot")
        case .share: return String(localized: "Share to other apps")
        case .delete: return String(localized: "Discard capture and restore previous clipboard")
        case .pin: return String(localized: "Pin to screen")
        case .copyPath: return String(localized: "Copy file path to clipboard")
        case .duplicate: return String(localized: "Save another copy")
        case .showInFinder: return String(localized: "Reveal saved file in Finder")
        case .ocr: return String(localized: "Extract text from screenshot")
        case .translate: return String(localized: "Translate screenshot text")
        case .upload: return String(localized: "Upload to cloud storage")
        }
    }
}

// MARK: - Shortcut keycap pill

/// Renders a keyboard shortcut (e.g. "⌘S", "⌘⇧T") as a compact, slightly
/// tinted pill — visually distinct from surrounding secondary text, which at
/// 9pt/secondary on ultraThinMaterial was too dim to read at a glance.
private struct ShortcutKeyPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.primary.opacity(0.85))
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
    }
}
