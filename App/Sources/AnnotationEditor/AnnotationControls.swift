import SwiftUI
import AnnotationKit

/// Font size field with a preset dropdown — replaces the text-size slider.
struct FontSizeControl: View {
    @Binding var size: CGFloat

    static let presets: [CGFloat] = [12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 64, 72, 96, 120]

    @State private var draftText: String = ""

    var body: some View {
        HStack(spacing: 2) {
            TextField("", text: $draftText)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 48)
                .multilineTextAlignment(.trailing)
                .help("Font Size")
                .onAppear { draftText = "\(Int(size))" }
                .onChange(of: size) { _, newValue in
                    let next = "\(Int(newValue))"
                    if draftText != next { draftText = next }
                }
                .onSubmit { commitDraft() }
                .onChange(of: draftText) { _, _ in
                    // Live-commit when typing valid numbers.
                    if let value = Int(draftText), value > 0 {
                        size = CGFloat(min(max(value, 8), 200))
                    }
                }

            Menu {
                ForEach(Self.presets, id: \.self) { preset in
                    Button {
                        size = preset
                        draftText = "\(Int(preset))"
                    } label: {
                        HStack {
                            Text("\(Int(preset))")
                            if Int(size) == Int(preset) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Common Font Sizes")

            Text("pt")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }

    private func commitDraft() {
        if let value = Int(draftText), value > 0 {
            size = CGFloat(min(max(value, 8), 200))
        }
        draftText = "\(Int(size))"
    }
}

struct StrokePatternPicker: View {
    @Binding var pattern: StrokePattern
    /// When true, use light-on-dark chrome (inline / all-in-one toolbars).
    var emphasizesOnDark: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(StrokePattern.allCases, id: \.self) { option in
                Button {
                    pattern = option
                } label: {
                    StrokePatternGlyph(pattern: option)
                        .foregroundStyle(emphasizesOnDark ? Color.white : Color.primary)
                        .frame(width: 32, height: 26)
                        .background(optionBackground(isSelected: pattern == option))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(
                                    pattern == option
                                        ? Color.accentColor.opacity(emphasizesOnDark ? 0.9 : 0.85)
                                        : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                }
                .buttonStyle(.plain)
                .help(option.label)
            }
        }
        .padding(2)
        .background(groupBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help("Stroke Pattern")
    }

    private var groupBackground: Color {
        emphasizesOnDark ? Color.white.opacity(0.09) : Color.primary.opacity(0.06)
    }

    private func optionBackground(isSelected: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(emphasizesOnDark ? 0.48 : 0.22)
        }
        return emphasizesOnDark ? Color.white.opacity(0.001) : Color.clear
    }
}

struct PenStylePicker: View {
    @Binding var penStyle: PenStyle

    var body: some View {
        Picker("", selection: $penStyle) {
            ForEach(PenStyle.allCases, id: \.self) { style in
                Image(systemName: style.systemImage)
                    .tag(style)
                    .help(style.label)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 108)
        .help("Pen Style")
    }
}
