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
    let onAnnotate: () -> Void
    let onOCR: () -> Void
    let onTranslate: () -> Void
    let onPin: () -> Void
    let onPreview: () -> Void
    let onClose: () -> Void
    /// Notifies the hosting panel so auto-dismiss can pause while hovered.
    var onHoveringChanged: ((Bool) -> Void)? = nil

    @State private var isHovering = false
    @State private var hoveredAction: HoverAction?
    @State private var visualState: PanelUploadState = .idle
    @FocusState private var isFocused: Bool

    private enum PanelUploadState: Equatable {
        case idle
        case uploading
        case succeeded
        case failed(ShareError)
    }

    private enum HoverAction: Hashable {
        case copy, save, share, delete, annotate, ocr, translate, pin, upload, linkCopied
    }

    private var isRevealed: Bool { isHovering || isFocused }
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
            .frame(minHeight: 72)
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
            onHoveringChanged?(hovering)
        }
        .focusable()
        .focused($isFocused)
        .overlay(alignment: .bottom) {
            if case .failed(let err) = visualState {
                FailureToast(error: err) {
                    Task { await performUpload() }  // retry
                } onDismiss: {
                    visualState = .idle
                }
                .padding(.bottom, 8)
            }
        }
    }

    private var panelStroke: Color {
        isRevealed ? Color.primary.opacity(0.14) : Color.primary.opacity(0.08)
    }

    // MARK: - Thumbnail

    private var thumbnailFrame: some View {
        ZStack(alignment: .topTrailing) {
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
                Text(hoveredAction.map(label) ?? String(localized: "Captured"))
                    .font(.system(size: 13, weight: .semibold))
            } icon: {
                Image(systemName: hoveredAction == nil ? "checkmark.circle.fill" : "hand.tap")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(hoveredAction == nil ? .green : .secondary)
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

    private var metaLine: String {
        "\(dimensions) · \(relativeTime)"
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: capturedAt, relativeTo: Date())
    }

    private var hoveredShortcutKey: String? {
        guard let action = hoveredAction else { return nil }
        switch action {
        case .copy:      return "⌘C"
        case .save:      return "⌘S"
        case .share:     return "⌘⇧I"
        case .delete:    return "⌫"
        case .annotate:  return "⌘E"
        case .ocr:       return "⌘⇧O"
        case .translate: return "⌘⇧T"
        case .pin:       return "⌘P"
        case .upload, .linkCopied: return nil
        }
    }

    /// All primary actions visible below the thumbnail (no overflow menu).
    private var toolbar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                toolButton(.copy, icon: "doc.on.doc", action: onCopy)
                toolButton(.annotate, icon: "pencil.tip.crop.circle", isPrimary: true, action: onAnnotate)
                toolButton(.save, icon: "square.and.arrow.down", action: onSave)
                toolButton(.share, icon: "square.and.arrow.up", action: onShare)
            }
            HStack(spacing: 4) {
                toolButton(.pin, icon: "pin", action: onPin)
                toolButton(.ocr, icon: "text.viewfinder", action: onOCR)
                toolButton(.translate, icon: "character.bubble", action: onTranslate)
                toolButton(.delete, icon: "trash", action: onDelete)
                if shareCoordinator != nil {
                    uploadButton
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Quick Access actions"))
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var uploadButton: some View {
        switch visualState {
        case .idle, .failed:
            toolButton(.upload, icon: "icloud.and.arrow.up", action: {
                Task { await performUpload() }
            })
        case .uploading:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 29, height: 28)
                .symbolEffect(.rotate, options: .repeating)
                .help(String(localized: "Uploading…"))
        case .succeeded:
            toolButton(.linkCopied, icon: "checkmark.circle.fill", action: {})
                .disabled(true)
        }
    }

    private func performUpload() async {
        guard let coord = shareCoordinator else { return }
        let image = captureImage  // capture into local for the detached closure

        // Encode + write off main actor — large PNGs block UI for hundreds of ms otherwise
        let tempURL: URL? = await Task.detached(priority: .userInitiated) { () -> URL? in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("png")
            guard let data = ImageUtilities.pngData(from: image) else { return nil }
            do {
                try data.write(to: url)
                return url
            } catch {
                return nil
            }
        }.value

        guard let tempURL else {
            // Encode/write failed — show as failure
            visualState = .failed(.unknown("Failed to encode capture for upload"))
            return
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        visualState = .uploading
        do {
            let cloudURL = try await coord.upload(file: tempURL, contentType: "image/png")
            onUploadSucceeded?(cloudURL.absoluteString)
            visualState = .succeeded
            try? await Task.sleep(for: .seconds(3))
            if case .succeeded = visualState {
                visualState = .idle
            }
        } catch let err as ShareError {
            visualState = .failed(err)
        } catch {
            visualState = .failed(.unknown(error.localizedDescription))
        }
    }

    @ViewBuilder
    private func toolButton(
        _ kind: HoverAction,
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

    private func toolForeground(_ kind: HoverAction, isPrimary: Bool) -> Color {
        if isPrimary { return .white }
        if kind == .linkCopied { return .green }
        if kind == .delete { return Color.red.opacity(hoveredAction == kind ? 0.96 : 0.78) }
        return Color.primary.opacity(hoveredAction == kind ? 0.96 : 0.78)
    }

    private func toolBackground(_ kind: HoverAction, isPrimary: Bool) -> Color {
        if isPrimary {
            return Color.accentColor.opacity(hoveredAction == kind ? 0.92 : 0.78)
        }
        return hoveredAction == kind ? Color.primary.opacity(0.12) : Color.clear
    }

    private func shortcut(for kind: HoverAction) -> (key: KeyEquivalent, modifiers: EventModifiers)? {
        switch kind {
        case .copy:      return ("c", [.command])
        case .save:      return ("s", [.command])
        case .share:     return ("i", [.command, .shift])
        case .delete:    return (.delete, [])
        case .annotate:  return ("e", [.command])
        case .ocr:       return ("o", [.command, .shift])
        case .translate: return ("t", [.command, .shift])
        case .pin:       return ("p", [.command])
        case .upload, .linkCopied: return nil
        }
    }

    private var hiddenEscapeButton: some View {
        Button(action: onClose) { EmptyView() }
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
    }

    private func label(_ kind: HoverAction) -> String {
        switch kind {
        case .copy: return String(localized: "Copy")
        case .save: return String(localized: "Save")
        case .share: return String(localized: "Share")
        case .delete: return String(localized: "Delete")
        case .annotate: return String(localized: "Annotate")
        case .ocr: return String(localized: "Extract Text")
        case .translate: return String(localized: "Translate")
        case .pin: return String(localized: "Pin")
        case .upload: return String(localized: "Upload to Cloud")
        case .linkCopied: return String(localized: "Link Copied!")
        }
    }

    private func hintForAccessibility(_ kind: HoverAction) -> String {
        switch kind {
        case .copy: return String(localized: "Copy to clipboard")
        case .save: return String(localized: "Save screenshot")
        case .share: return String(localized: "Share to other apps")
        case .delete: return String(localized: "Discard capture and restore previous clipboard")
        case .annotate: return String(localized: "Open annotation editor")
        case .ocr: return String(localized: "Extract text from screenshot")
        case .translate: return String(localized: "Translate text in screenshot")
        case .pin: return String(localized: "Pin to screen")
        case .upload: return String(localized: "Upload screenshot to cloud and copy link")
        case .linkCopied: return String(localized: "Link has been copied to clipboard")
        }
    }
}

// MARK: - Failure toast

private struct FailureToast: View {
    let error: ShareError
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 12))
            Button(String(localized: "Retry"), action: onRetry)
                .controlSize(.small)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }

    private var message: String {
        switch error {
        case .invalidCredentials:
            return String(localized: "Cloud credentials are invalid. Open Settings to fix.")
        case .network(let underlying):
            return String(localized: "Upload failed — network error: \(underlying)")
        case .quotaExceeded:
            return String(localized: "Cloud quota exceeded.")
        case .publicAccessUnreachable:
            return String(localized: "Upload OK but public URL unreachable. Check bucket settings.")
        case .invalidURLPrefix(let reason):
            return String(localized: "Cloud URL prefix is invalid: \(reason)")
        case .notConfigured:
            return String(localized: "Cloud sharing is not configured.")
        case .unknown(let detail):
            return String(localized: "Upload failed: \(detail)")
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
