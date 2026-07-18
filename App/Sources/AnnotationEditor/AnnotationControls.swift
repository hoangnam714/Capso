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

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                StrokePatternGlyph(pattern: pattern, width: 36, height: 14)
                    .foregroundStyle(emphasizesOnDark ? Color.white : Color.primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(emphasizesOnDark ? Color.white.opacity(0.7) : Color.secondary)
            }
            .frame(width: 52, height: 26)
            .background(optionBackground(isSelected: true))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        Color.accentColor.opacity(emphasizesOnDark ? 0.9 : 0.85),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(2)
        .background(groupBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help("Stroke Pattern")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            patternMenu
        }
    }

    private var patternMenu: some View {
        VStack(spacing: 4) {
            ForEach(StrokePattern.allCases, id: \.self) { option in
                Button {
                    pattern = option
                    isPresented = false
                } label: {
                    HStack(spacing: 10) {
                        StrokePatternGlyph(pattern: option, width: 72, height: 16)
                            .foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .opacity(pattern == option ? 1 : 0)
                            .frame(width: 12)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(pattern == option
                                  ? Color.accentColor.opacity(0.16)
                                  : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(option.label)
            }
        }
        .padding(6)
        .frame(width: 120)
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

/// Compact labeled slider for toolbar parameter controls (e.g. Highlight Focus).
struct LabeledSlider: View {
    let title: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    var step: CGFloat = 1
    var width: CGFloat = 80
    var valueText: String
    var emphasizesOnDark: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(emphasizesOnDark ? Color.white.opacity(0.72) : Color.secondary)
                .lineLimit(1)
            Slider(value: $value, in: range, step: step)
                .frame(width: width)
                .help("\(title): \(valueText)")
        }
    }
}
