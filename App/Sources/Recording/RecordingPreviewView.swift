import SwiftUI
import Observation

/// Reactive state for the recording preview window. The coordinator
/// flips `isSaving = true` when Save is clicked and feeds `saveProgress`
/// from the export pipeline. The view observes both via `@Observable`
/// tracking and re-renders the right column accordingly.
@MainActor
@Observable
final class RecordingPreviewState {
    var isSaving: Bool = false
    var saveProgress: Double = 0
    var progressLabel: String = String(localized: "Saving…")
}

struct RecordingPreviewView: View {
    let thumbnail: NSImage?
    let duration: String
    let fileSize: String
    let state: RecordingPreviewState
    let onCopy: () -> Void
    let onSave: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false
    @State private var hoveredAction: HoverAction?

    private enum HoverAction: Hashable {
        case copy, save, share, delete
    }

    private static let panelCornerRadius: CGFloat = 14
    private static let thumbnailSize = CGSize(width: 268, height: 116)

    private var isRevealed: Bool { isHovering }

    var body: some View {
        VStack(spacing: 9) {
            thumbnailFrame

            VStack(spacing: 6) {
                captionRow
                if state.isSaving {
                    savingOverlay
                } else {
                    actionToolbar
                }
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
                .stroke(Color.primary.opacity(isRevealed ? 0.14 : 0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .onHover { isHovering = $0 }
    }

    private var thumbnailFrame: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(Color.black.opacity(0.3))
                        .overlay(
                            Image(systemName: "video.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white.opacity(0.5))
                        )
                }
            }
            .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
            .background(Color.black.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            )

            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.red)
                    Text(duration)
                }
                Text(fileSize)
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(7)

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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(7)
                .help(String(localized: "Close"))
            }
        }
    }

    private var captionRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label {
                Text(hoveredAction.map(label) ?? String(localized: "Recording ready"))
                    .font(.system(size: 13, weight: .semibold))
            } icon: {
                Image(systemName: hoveredAction == nil ? "checkmark.circle.fill" : "hand.tap")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(hoveredAction == nil ? .green : .secondary)
            }
            Spacer()
            Text("\(duration) · \(fileSize)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 6)
    }

    private var actionToolbar: some View {
        HStack(spacing: 4) {
            toolButton(.copy, icon: "doc.on.doc", action: onCopy)
            toolButton(.save, icon: "square.and.arrow.down", isPrimary: true, action: onSave)
            toolButton(.share, icon: "square.and.arrow.up", action: onShare)
            toolButton(.delete, icon: "trash", action: onDelete)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var savingOverlay: some View {
        VStack(spacing: 6) {
            ProgressView(value: state.saveProgress)
                .progressViewStyle(.linear)
                .controlSize(.small)
                .tint(.accentColor)
            Text("\(state.progressLabel) \(Int(state.saveProgress * 100))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private var hiddenEscapeButton: some View {
        Button(action: onClose) { EmptyView() }
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
    }

    private func toolButton(
        _ kind: HoverAction,
        icon: String,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(toolForeground(kind, isPrimary: isPrimary))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(toolBackground(kind, isPrimary: isPrimary))
                )
        }
        .buttonStyle(.plain)
        .onHover { hoveredAction = $0 ? kind : nil }
        .help(Text(label(kind)))
    }

    private func toolForeground(_ kind: HoverAction, isPrimary: Bool) -> Color {
        if isPrimary { return .white }
        if kind == .delete { return Color.red.opacity(hoveredAction == kind ? 0.96 : 0.78) }
        return Color.primary.opacity(hoveredAction == kind ? 0.96 : 0.78)
    }

    private func toolBackground(_ kind: HoverAction, isPrimary: Bool) -> Color {
        if isPrimary {
            return Color.accentColor.opacity(hoveredAction == kind ? 0.92 : 0.78)
        }
        return hoveredAction == kind ? Color.primary.opacity(0.12) : Color.clear
    }

    private func label(_ kind: HoverAction) -> String {
        switch kind {
        case .copy: return String(localized: "Copy")
        case .save: return String(localized: "Save")
        case .share: return String(localized: "Share")
        case .delete: return String(localized: "Delete")
        }
    }
}
