// App/Sources/AnnotationEditor/AnnotationToolbar.swift
import AppKit
import SwiftUI
import AnnotationKit

struct AnnotationToolbar: View {
    @Binding var currentTool: AnnotationTool
    @Binding var currentColor: AnnotationColor
    @Binding var lineWidth: CGFloat
    @Binding var strokePattern: StrokePattern
    @Binding var filled: Bool
    @Binding var textFillEnabled: Bool
    @Binding var textOutlineEnabled: Bool
    @Binding var textStrokeEnabled: Bool
    @Binding var textBoldEnabled: Bool
    @Binding var textItalicEnabled: Bool
    @Binding var textUnderlineEnabled: Bool
    @Binding var textAlignment: AnnotationTextAlignment
    @Binding var redactionMode: RedactionMode
    @Binding var showBeautifyPanel: Bool
    @Binding var penStyle: PenStyle
    /// Dim overlay opacity for Highlight Focus (0…1).
    @Binding var highlightFocusOpacity: CGFloat
    /// True when an inline text edit is active (either via the text tool or
    /// by double-clicking an existing TextObject in select mode). When set,
    /// the size slider behaves as a Font Size control regardless of the
    /// currently selected tool — so users can keep tuning size while typing.
    var isEditingText: Bool = false
    /// Tool whose size the slider should control. When a concrete object is
    /// selected (often while `currentTool == .select`), pass that object's
    /// type so the slider keeps its per-kind range / label.
    var sizeControlTool: AnnotationTool? = nil
    let canUndo: Bool
    let canRedo: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onSave: () -> Void
    let onCopy: () -> Void
    let onCancel: () -> Void
    let onCrop: () -> Void
    var onInsertImageFromClipboard: (() -> Void)? = nil
    var onInsertImageFromFile: (() -> Void)? = nil

    /// Tool that owns the size slider (selection overrides the active tool).
    private var effectiveSizeTool: AnnotationTool {
        sizeControlTool ?? currentTool
    }

    /// The size slider serves multiple tools: in text / editing mode it means
    /// font size; for other tools it retains its existing role.
    private var isFontSizeMode: Bool {
        effectiveSizeTool == .text || isEditingText
    }

    var body: some View {
        VStack(spacing: 6) {
            // Pick the richest layout that still fits the available width so
            // small MacBook windows can shrink instead of locking min-width.
            ViewThatFits(in: .horizontal) {
                toolbarRow(density: .full)
                toolbarRow(density: .compact)
                toolbarRow(density: .minimal)
            }

            if isFontSizeMode {
                textEffectsGroup
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minWidth: 0, maxWidth: .infinity)
        .onHover { hovering in
            if hovering {
                NSCursor.arrow.set()
            }
        }
        .onChange(of: currentTool) { _, _ in
            NSCursor.arrow.set()
        }
    }

    private enum ToolbarDensity {
        /// All drawing tools inline (preferred).
        case full
        /// Same tools as full, but compact color row for mid-width windows.
        case compact
        /// Current tool + overflow menu only when the window is very narrow.
        case minimal
    }

    private func toolbarRow(density: ToolbarDensity) -> some View {
        HStack(spacing: density == .minimal ? 8 : 10) {
            toolsSection(density: density)
            toolbarDivider
            colorSection(density: density)
            toolbarDivider
            strokeGroup
            toolbarDivider
            cropGroup
            toolbarDivider
            beautifyGroup
            toolbarDivider
            undoGroup
            Spacer(minLength: 4)
            actionGroup
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func toolsSection(density: ToolbarDensity) -> some View {
        switch density {
        case .full, .compact:
            // Always keep Line / Counter / Highlighter / Focus / Insert visible.
            HStack(spacing: 4) {
                ForEach(Self.allToolItems, id: \.tool) { item in
                    toolItemButton(item)
                }
                toolbarDivider
                insertImageButtons
            }
        case .minimal:
            HStack(spacing: 4) {
                if let current = Self.allToolItems.first(where: { $0.tool == currentTool }) {
                    toolItemButton(current)
                }
                moreToolsMenu(items: Self.allToolItems, includeInsertImage: true)
            }
        }
    }

    @ViewBuilder
    private func colorSection(density: ToolbarDensity) -> some View {
        switch density {
        case .full:
            AnnotationColorControls(currentColor: $currentColor)
        case .compact, .minimal:
            AnnotationColorControls(
                currentColor: $currentColor,
                swatchSize: 16,
                spacing: 2,
                compact: density == .minimal
            )
        }
    }

    private struct ToolItem {
        let tool: AnnotationTool
        let icon: String
        let label: LocalizedStringKey
        var isText: Bool = false
    }

    private static let allToolItems: [ToolItem] = [
        ToolItem(tool: .select, icon: "cursorarrow", label: "Select"),
        ToolItem(tool: .arrow, icon: "arrow.up.right", label: "Arrow"),
        ToolItem(tool: .line, icon: "line.diagonal", label: "Line"),
        ToolItem(tool: .rectangle, icon: "rectangle", label: "Rectangle (⌃: square)"),
        ToolItem(tool: .ellipse, icon: "circle", label: "Ellipse (⌃: circle)"),
        ToolItem(tool: .text, icon: "textformat", label: "Text", isText: true),
        ToolItem(tool: .freehand, icon: "pencil.tip", label: "Draw"),
        ToolItem(tool: .pixelate, icon: "eye.slash.fill", label: "Pixelate / Blur"),
        ToolItem(tool: .counter, icon: "number.circle.fill", label: "Counter"),
        ToolItem(tool: .highlighter, icon: "highlighter", label: "Highlighter"),
        ToolItem(tool: .highlightFocus, icon: "circle.lefthalf.filled", label: "Highlight Focus"),
    ]

    @ViewBuilder
    private func toolItemButton(_ item: ToolItem) -> some View {
        if item.isText {
            textToolButton
        } else {
            toolButton(item.tool, icon: item.icon, label: item.label)
        }
    }

    private func moreToolsMenu(items: [ToolItem], includeInsertImage: Bool) -> some View {
        Menu {
            ForEach(items, id: \.tool) { item in
                Button {
                    currentTool = item.tool
                } label: {
                    if item.isText {
                        Text(item.label)
                    } else {
                        Label(item.label, systemImage: item.icon)
                    }
                }
            }
            if includeInsertImage {
                Divider()
                Button("Paste Image from Clipboard") {
                    onInsertImageFromClipboard?()
                }
                Button("Insert Image from File…") {
                    onInsertImageFromFile?()
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(toolbarIconForeground(isActive: isOverflowToolSelected(items)))
                .frame(width: 30, height: 26)
                .background(toolbarButtonBackground(isActive: isOverflowToolSelected(items)))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(toolbarButtonStroke)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("More Tools")
    }

    private func isOverflowToolSelected(_ items: [ToolItem]) -> Bool {
        // In minimal mode the current tool also has its own button, so only
        // highlight "More" when that button isn't already showing the same tool.
        items.contains { $0.tool == currentTool }
    }

    private var insertImageButtons: some View {
        HStack(spacing: 4) {
            insertImageButton(
                icon: "doc.on.clipboard",
                help: "Paste Image from Clipboard",
                action: { onInsertImageFromClipboard?() }
            )
            insertImageButton(
                icon: "photo.badge.plus",
                help: "Insert Image from File…",
                action: { onInsertImageFromFile?() }
            )
        }
    }

    private func insertImageButton(
        icon: String,
        help: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(toolbarIconForeground(isActive: false))
                .frame(width: 30, height: 26)
                .background(toolbarButtonBackground(isActive: false))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(toolbarButtonStroke)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func toolButton(_ tool: AnnotationTool, icon: String, label: LocalizedStringKey) -> some View {
        Button(action: { currentTool = tool }) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(toolbarIconForeground(isActive: currentTool == tool))
                .frame(width: 30, height: 26)
                .background(toolbarButtonBackground(isActive: currentTool == tool))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(toolbarButtonStroke)
        }
        .buttonStyle(.plain)
        .help(label)
    }

    /// Text-tool button. Rendered as a literal "Aa" glyph rather than the
    /// SF Symbol `textformat`, because Apple localizes that symbol's
    /// appearance per language (en: "Aa", zh: "格式", ja: "書式", …) and
    /// we want a consistent look across all locales — the iconic "Aa"
    /// shorthand is the industry convention for a text tool.
    ///
    /// `Text(verbatim:)` prevents SwiftUI from treating "Aa" as a
    /// LocalizedStringKey lookup.
    private var textToolButton: some View {
        Button(action: { currentTool = .text }) {
            Text(verbatim: "Aa")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(toolbarIconForeground(isActive: currentTool == .text))
                .frame(width: 30, height: 26)
                .background(toolbarButtonBackground(isActive: currentTool == .text))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(toolbarButtonStroke)
        }
        .buttonStyle(.plain)
        .help("Text")
    }

    private var strokeGroup: some View {
        HStack(spacing: 8) {
            if isFontSizeMode {
                FontSizeControl(size: $lineWidth)
            } else if effectiveSizeTool == .pixelate {
                Picker("", selection: $redactionMode) {
                    ForEach(RedactionMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(minWidth: 120, idealWidth: 160, maxWidth: 184)
                .help("Redaction Mode")

                if redactionMode != .solid {
                    Slider(value: $lineWidth, in: 4...48, step: 2)
                        .frame(minWidth: 48, idealWidth: 80, maxWidth: 80)
                        .help("Block Size: \(Int(lineWidth))")
                }
            } else if effectiveSizeTool == .counter {
                Slider(value: $lineWidth, in: 12...40, step: 1)
                    .frame(minWidth: 48, idealWidth: 80, maxWidth: 80)
                    .help("Counter Size: \(Int(lineWidth))")
            } else if effectiveSizeTool == .highlighter {
                Slider(value: $lineWidth, in: 10...100, step: 2)
                    .frame(minWidth: 48, idealWidth: 80, maxWidth: 80)
                    .help("Highlighter Width: \(Int(lineWidth))")
            } else if effectiveSizeTool == .highlightFocus {
                LabeledSlider(
                    title: "Dim",
                    value: $highlightFocusOpacity,
                    range: 0.15...0.90,
                    step: 0.05,
                    width: 64,
                    valueText: "\(Int(highlightFocusOpacity * 100))%"
                )
                LabeledSlider(
                    title: "Radius",
                    value: $lineWidth,
                    range: 0...40,
                    step: 1,
                    width: 64,
                    valueText: "\(Int(lineWidth))"
                )
            } else if effectiveSizeTool != .select {
                Slider(value: $lineWidth, in: 1...40, step: 1)
                    .frame(minWidth: 48, idealWidth: 80, maxWidth: 80)
                    .help("Line Width: \(Int(lineWidth))")
            }

            if showsStrokePatternPicker {
                StrokePatternPicker(pattern: $strokePattern)
            }

            if effectiveSizeTool == .freehand {
                PenStylePicker(penStyle: $penStyle)
            }

            // Fill toggle is meaningless for counter / highlighter / text / freehand.
            if effectiveSizeTool != .counter
                && effectiveSizeTool != .arrow
                && effectiveSizeTool != .line
                && effectiveSizeTool != .highlighter
                && effectiveSizeTool != .highlightFocus
                && effectiveSizeTool != .freehand
                && effectiveSizeTool != .select
                && !isFontSizeMode {
                Toggle(isOn: $filled) {
                    Image(systemName: filled ? "square.fill" : "square")
                        .font(.system(size: 12))
                }
                .toggleStyle(.button)
                .help("Fill Shape")
            }
        }
        .frame(minWidth: 0)
        .layoutPriority(-1)
    }

    private var showsStrokePatternPicker: Bool {
        switch effectiveSizeTool {
        case .arrow, .line, .rectangle, .ellipse:
            return !filled || effectiveSizeTool == .arrow || effectiveSizeTool == .line
        default:
            return false
        }
    }

    private var textEffectsGroup: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                textEffectToggle("Fill", isOn: $textFillEnabled, help: "Text Fill")
                textEffectToggle("Outline", isOn: $textOutlineEnabled, help: "Text Box Outline")
                textEffectToggle("Trace", isOn: $textStrokeEnabled, help: "Text Trace")
                textEffectToggle("Bold", isOn: $textBoldEnabled, help: "Bold")
                textEffectToggle("Italic", isOn: $textItalicEnabled, help: "Italic")
                textEffectToggle("Underline", isOn: $textUnderlineEnabled, help: "Underline")

                Picker("", selection: $textAlignment) {
                    Image(systemName: "text.alignleft").tag(AnnotationTextAlignment.left)
                    Image(systemName: "text.aligncenter").tag(AnnotationTextAlignment.center)
                    Image(systemName: "text.alignright").tag(AnnotationTextAlignment.right)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 96)
                .help("Text Alignment")
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func textEffectToggle(
        _ title: LocalizedStringKey,
        isOn: Binding<Bool>,
        help: LocalizedStringKey
    ) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .frame(minWidth: 46, minHeight: 20)
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .help(help)
    }

    private var cropGroup: some View {
        Button(action: onCrop) {
            Image(systemName: "crop")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(toolbarIconForeground(isActive: false))
                .frame(width: 30, height: 26)
                .background(toolbarButtonBackground(isActive: false))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(toolbarButtonStroke)
        }
        .buttonStyle(.plain)
        .help("Crop")
        .disabled(isEditingText)
    }

    private var beautifyGroup: some View {
        Button(action: { showBeautifyPanel.toggle() }) {
            Image(systemName: showBeautifyPanel ? "sparkles.rectangle.stack.fill" : "sparkles")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(toolbarIconForeground(isActive: showBeautifyPanel))
                .frame(width: 30, height: 26)
                .background(toolbarButtonBackground(isActive: showBeautifyPanel))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(toolbarButtonStroke)
        }
        .buttonStyle(.plain)
        .help("Beautify")
    }

    private var undoGroup: some View {
        HStack(spacing: 4) {
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!canUndo)
            .keyboardShortcut("z", modifiers: .command)
            .help("Undo")
            Button(action: onRedo) {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .help("Redo")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var actionGroup: some View {
        HStack(spacing: 6) {
            actionButton(icon: "xmark", help: "Close", isDestructive: true, action: onCancel)
                .keyboardShortcut(.escape, modifiers: [])

            copyActionButton

            saveActionButton
                .keyboardShortcut("s", modifiers: .command)
        }
    }

    @ViewBuilder
    private var copyActionButton: some View {
        let button = actionButton(icon: "doc.on.doc", help: "Copy", action: onCopy)
            .keyboardShortcut("c", modifiers: .command)
        if isEditingText {
            button
        } else {
            button.keyboardShortcut(.return, modifiers: [])
        }
    }

    private var saveActionButton: some View {
        Button(action: onSave) {
            SaveIcon()
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(actionIconForeground(isPrimary: true, isDestructive: false))
                .frame(width: 34, height: 26)
                .background(actionButtonBackground(isPrimary: true, isDestructive: false))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(actionButtonStroke(isPrimary: true))
        }
        .buttonStyle(.plain)
        .help("Save")
    }

    private func actionButton(
        icon: String,
        help: LocalizedStringKey,
        isPrimary: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(actionIconForeground(isPrimary: isPrimary, isDestructive: isDestructive))
                .frame(width: 34, height: 26)
                .background(actionButtonBackground(isPrimary: isPrimary, isDestructive: isDestructive))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(actionButtonStroke(isPrimary: isPrimary))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 24)
    }

    private func toolbarButtonBackground(isActive: Bool) -> Color {
        isActive ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04)
    }

    private func toolbarIconForeground(isActive: Bool) -> Color {
        isActive ? Color.accentColor : Color.primary.opacity(0.82)
    }

    private var toolbarButtonStroke: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
    }

    private func actionButtonBackground(isPrimary: Bool, isDestructive: Bool) -> Color {
        if isPrimary {
            return Color.accentColor
        }
        if isDestructive {
            return Color.primary.opacity(0.045)
        }
        return Color.primary.opacity(0.055)
    }

    private func actionIconForeground(isPrimary: Bool, isDestructive: Bool) -> Color {
        if isPrimary {
            return .white
        }
        if isDestructive {
            return Color.primary.opacity(0.72)
        }
        return Color.primary.opacity(0.84)
    }

    private func actionButtonStroke(isPrimary: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(isPrimary ? Color.white.opacity(0.18) : Color.primary.opacity(0.08), lineWidth: 0.5)
    }
}

struct StrokePatternGlyph: View {
    let pattern: StrokePattern
    var width: CGFloat = 28
    var height: CGFloat = 14

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let y = size.height / 2
            path.move(to: CGPoint(x: 2, y: y))
            path.addLine(to: CGPoint(x: size.width - 2, y: y))

            let style: SwiftUI.StrokeStyle
            switch pattern {
            case .solid:
                style = SwiftUI.StrokeStyle(lineWidth: 2.4, lineCap: .round)
            case .dashed:
                style = SwiftUI.StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [6, 4])
            case .longDashed:
                style = SwiftUI.StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [11, 5])
            case .dotted:
                style = SwiftUI.StrokeStyle(lineWidth: 2.8, lineCap: .round, dash: [0.1, 4.5])
            case .dashDot:
                style = SwiftUI.StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [7, 3.5, 0.1, 3.5])
            }
            context.stroke(path, with: .foreground, style: style)
        }
        .frame(width: width, height: height)
    }
}
