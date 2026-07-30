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

/// One-way / two-way arrow tip preview drawn as a line with tip(s).
struct ArrowHeadGlyph: View {
    let style: ArrowHeadStyle
    var width: CGFloat = 28
    var height: CGFloat = 14

    var body: some View {
        Canvas { context, size in
            let y = size.height / 2
            let inset: CGFloat = 3
            let tip: CGFloat = 5
            let start = CGPoint(x: inset, y: y)
            let end = CGPoint(x: size.width - inset, y: y)

            var shaft = Path()
            shaft.move(to: start)
            shaft.addLine(to: end)
            context.stroke(shaft, with: .foreground, style: StrokeStyle(lineWidth: 2, lineCap: .round))

            func drawTip(at tipPoint: CGPoint, pointingRight: Bool) {
                let dir: CGFloat = pointingRight ? 1 : -1
                var head = Path()
                head.move(to: tipPoint)
                head.addLine(to: CGPoint(x: tipPoint.x - dir * tip, y: tipPoint.y - tip * 0.7))
                head.move(to: tipPoint)
                head.addLine(to: CGPoint(x: tipPoint.x - dir * tip, y: tipPoint.y + tip * 0.7))
                context.stroke(head, with: .foreground, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            drawTip(at: end, pointingRight: true)
            if style == .double {
                drawTip(at: start, pointingRight: false)
            }
        }
        .frame(width: width, height: height)
    }
}

struct ArrowHeadStylePicker: View {
    @Binding var headStyle: ArrowHeadStyle
    var emphasizesOnDark: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ArrowHeadStyle.allCases, id: \.self) { style in
                Button {
                    headStyle = style
                } label: {
                    ArrowHeadGlyph(style: style, width: 30, height: 14)
                        .foregroundStyle(
                            headStyle == style
                                ? (emphasizesOnDark ? Color.white : Color.accentColor)
                                : (emphasizesOnDark ? Color.white.opacity(0.55) : Color.primary.opacity(0.55))
                        )
                        .frame(width: 36, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(headStyle == style
                                      ? Color.accentColor.opacity(emphasizesOnDark ? 0.48 : 0.22)
                                      : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(style.label)
            }
        }
        .padding(2)
        .background(emphasizesOnDark ? Color.white.opacity(0.09) : Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help("Arrow Style")
    }
}

/// Popover content for choosing one-way vs two-way arrow from the tool button.
struct ArrowHeadStyleMenu: View {
    @Binding var headStyle: ArrowHeadStyle
    var onSelect: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Arrow Style"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(ArrowHeadStyle.allCases, id: \.self) { style in
                Button {
                    headStyle = style
                    onSelect?()
                } label: {
                    HStack(spacing: 10) {
                        ArrowHeadGlyph(style: style, width: 44, height: 16)
                            .foregroundStyle(Color.primary)
                        Text(style.label)
                            .font(.system(size: 12, weight: .medium))
                        Spacer(minLength: 8)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .opacity(headStyle == style ? 1 : 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(headStyle == style
                                  ? Color.accentColor.opacity(0.16)
                                  : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(width: 180)
    }
}

struct ShapeKindPicker: View {
    @Binding var kind: ShapeKind
    var emphasizesOnDark: Bool = false
    /// Compact trigger without chevron (used inside Style popover rows).
    var compactTrigger: Bool = false

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(emphasizesOnDark ? Color.white : Color.primary)
                if !compactTrigger {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(emphasizesOnDark ? Color.white.opacity(0.7) : Color.secondary)
                }
            }
            .frame(width: compactTrigger ? 30 : 44, height: 26)
            .background(Color.accentColor.opacity(emphasizesOnDark ? 0.48 : 0.22))
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
        .padding(compactTrigger ? 0 : 2)
        .background(compactTrigger
                    ? Color.clear
                    : (emphasizesOnDark ? Color.white.opacity(0.09) : Color.primary.opacity(0.06)))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(kind.label)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ShapeKindMenu(kind: $kind) {
                isPresented = false
            }
        }
    }
}

/// Shared shape grid used by the toolbar tool button and the Style popover.
struct ShapeKindMenu: View {
    @Binding var kind: ShapeKind
    var onSelect: (() -> Void)? = nil

    @AppStorage("annotationShapeRecentKinds") private var recentKindsRaw: String = ""

    static let favorites: [ShapeKind] = [
        .cloud, .speechBubble, .cloudSpeechBubble, .thoughtBubble, .star, .heart
    ]

    private var recentKinds: [ShapeKind] {
        let parsed = recentKindsRaw
            .split(separator: ",")
            .compactMap { ShapeKind(rawValue: String($0)) }
            .filter { !Self.favorites.contains($0) }
        var seen = Set<ShapeKind>()
        return parsed.filter { seen.insert($0).inserted }.prefix(4).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            quickPicksSection(title: String(localized: "Favorites"), kinds: Self.favorites)
            if !recentKinds.isEmpty {
                quickPicksSection(title: String(localized: "Recent"), kinds: recentKinds)
            }

            Text(String(localized: "All Shapes"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6)
                    ],
                    spacing: 6
                ) {
                    ForEach(ShapeKind.allCases, id: \.self) { option in
                        shapeCell(option)
                    }
                }
            }
            .frame(maxHeight: 240)
        }
        .padding(10)
        .frame(width: 260)
    }

    private func quickPicksSection(title: String, kinds: [ShapeKind]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            HStack(spacing: 6) {
                ForEach(kinds, id: \.self) { option in
                    Button {
                        select(option)
                    } label: {
                        Image(systemName: option.systemImage)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 34, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(kind == option
                                          ? Color.accentColor.opacity(0.18)
                                          : Color.primary.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(
                                        kind == option ? Color.accentColor.opacity(0.7) : Color.clear,
                                        lineWidth: 1.2
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(option.label)
                }
            }
        }
    }

    private func shapeCell(_ option: ShapeKind) -> some View {
        Button {
            select(option)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .frame(height: 20)
                Text(option.label)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(kind == option
                          ? Color.accentColor.opacity(0.16)
                          : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        kind == option ? Color.accentColor.opacity(0.7) : Color.clear,
                        lineWidth: 1.2
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(option.label)
    }

    private func select(_ option: ShapeKind) {
        kind = option
        rememberRecent(option)
        onSelect?()
    }

    private func rememberRecent(_ option: ShapeKind) {
        var kinds = recentKindsRaw
            .split(separator: ",")
            .compactMap { ShapeKind(rawValue: String($0)) }
            .filter { $0 != option }
        kinds.insert(option, at: 0)
        recentKindsRaw = kinds.prefix(8).map(\.rawValue).joined(separator: ",")
    }
}

/// Collapses pattern / arrow / shape / fill into one control for narrow toolbars.
struct AnnotationStylePopover: View {
    @Binding var strokePattern: StrokePattern
    @Binding var filled: Bool
    @Binding var arrowHeadStyle: ArrowHeadStyle
    @Binding var shapeKind: ShapeKind

    var showsPattern: Bool
    var showsArrowHead: Bool
    var showsShapeKind: Bool
    var showsFill: Bool
    var emphasizesOnDark: Bool = false

    @State private var isPresented = false

    private var hasAnyControl: Bool {
        showsPattern || showsArrowHead || showsShapeKind || showsFill
    }

    var body: some View {
        if hasAnyControl {
            Button {
                isPresented.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "paintbrush.pointed")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(emphasizesOnDark ? Color.white : Color.primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(emphasizesOnDark ? Color.white.opacity(0.7) : Color.secondary)
                }
                .frame(width: 44, height: 26)
                .background(Color.accentColor.opacity(emphasizesOnDark ? 0.48 : 0.22))
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
            .background(emphasizesOnDark ? Color.white.opacity(0.09) : Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .help("Style")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                styleMenu
            }
        }
    }

    private var styleMenu: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsPattern {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Stroke"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    StrokePatternPicker(pattern: $strokePattern)
                }
            }
            if showsArrowHead {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Arrow"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ArrowHeadStylePicker(headStyle: $arrowHeadStyle)
                }
            }
            if showsShapeKind {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Shape"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ShapeKindPicker(kind: $shapeKind)
                }
            }
            if showsFill {
                Toggle(isOn: $filled) {
                    Label(
                        String(localized: "Fill"),
                        systemImage: filled ? "square.fill" : "square"
                    )
                    .font(.system(size: 12, weight: .medium))
                }
                .toggleStyle(.button)
            }
        }
        .padding(12)
        .frame(minWidth: 180)
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
