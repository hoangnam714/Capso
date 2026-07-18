// App/Sources/AnnotationEditor/AnnotationEditorView.swift
import SwiftUI
import AnnotationKit
import OCRKit
import SharedKit

struct AnnotationEditorView: View {
    let initialSourceImage: CGImage
    let document: AnnotationDocument
    let interactionState: AnnotationEditorInteractionState
    /// Save receives the flattened output, the editable base image, and the live document
    /// so History can persist both the preview PNG and a re-editable annotation sidecar.
    let onSave: (CGImage, CGImage, AnnotationDocument) -> Void
    let onCopy: (CGImage, CGImage, AnnotationDocument) -> Void
    let onShare: (CGImage) -> Void
    let onPin: (CGImage) -> Void
    let onCancel: () -> Void

    /// The working image shown in the canvas. Starts equal to
    /// `initialSourceImage` and is swapped if a crop commit includes a
    /// rotate or flip. Annotations live in this image's coordinate space.
    @State private var sourceImage: CGImage

    init(
        sourceImage: CGImage,
        document: AnnotationDocument,
        interactionState: AnnotationEditorInteractionState,
        onSave: @escaping (CGImage, CGImage, AnnotationDocument) -> Void,
        onCopy: @escaping (CGImage, CGImage, AnnotationDocument) -> Void,
        onShare: @escaping (CGImage) -> Void,
        onPin: @escaping (CGImage) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialSourceImage = sourceImage
        self.document = document
        self.interactionState = interactionState
        self.onSave = onSave
        self.onCopy = onCopy
        self.onShare = onShare
        self.onPin = onPin
        self.onCancel = onCancel
        self._sourceImage = State(initialValue: sourceImage)
    }

    // MARK: - Persisted tool preferences (issue #75)
    // Tool / color / filled / per-tool sizes survive across editor sessions
    // via UserDefaults. `lineWidth` itself is session-local because its
    // meaning changes with the active tool; it is synced on every change into
    // the correct per-tool store below.
    @AppStorage("annotationLastTool") private var currentTool: AnnotationTool = .arrow
    @AppStorage("annotationLastColor") private var currentColor: AnnotationColor = .red
    @AppStorage("annotationFilled") private var filled: Bool = false
    @AppStorage("annotationShapeWidth") private var savedLineWidth: Double = 3
    @AppStorage("annotationBlockSize") private var savedBlockSize: Double = 12
    @AppStorage("annotationCounterSize") private var savedCounterSize: Double = 20
    @AppStorage("annotationHighlighterWidth") private var savedHighlighterWidth: Double = 20
    @AppStorage("annotationHighlightFocusCornerRadius") private var savedHighlightFocusCornerRadius: Double = 12
    @AppStorage("annotationHighlightFocusOpacity") private var savedHighlightFocusOpacity: Double = 0.55
    @AppStorage("annotationRedactionMode") private var redactionMode: RedactionMode = .pixelate
    @AppStorage("annotationStrokePattern") private var savedStrokePattern: StrokePattern = .solid
    @AppStorage("annotationTextFillEnabled") private var textFillEnabled: Bool = false
    @AppStorage("annotationTextOutlineEnabled") private var textOutlineEnabled: Bool = false
    @AppStorage("annotationTextStrokeEnabled") private var textStrokeEnabled: Bool = true
    @AppStorage("annotationTextBoldEnabled") private var textBoldEnabled: Bool = false
    @AppStorage("annotationTextItalicEnabled") private var textItalicEnabled: Bool = false
    @AppStorage("annotationTextUnderlineEnabled") private var textUnderlineEnabled: Bool = false
    @AppStorage("annotationTextAlignment") private var textAlignment: AnnotationTextAlignment = .left
    @AppStorage("annotationPenStyle") private var penStyle: PenStyle = .pen
    /// Preserved font size for the Text tool. Swapped in/out of `lineWidth`
    /// as the user toggles tools — same pattern as savedBlockSize etc.
    @AppStorage("annotationTextFontSize") private var savedTextFontSize: Double = 48

    @State private var lineWidth: CGFloat = 3
    @State private var highlightFocusOpacity: CGFloat = HighlightFocusObject.defaultDimOpacity
    @State private var strokePattern: StrokePattern = .solid
    /// True while an inline text editor is active. Lets the toolbar show
    /// the font-size slider even when the tool is `.select` (happens when
    /// re-editing via double-click).
    @State private var isEditingText = false
    @State private var beautifySettings = BeautifySettings()
    @State private var showBeautifyPanel = false
    @State private var refreshTrigger = 0
    @State private var zoomScale: CGFloat = 1.0
    @State private var zoomPercentDraft: String = "100"
    @FocusState private var isZoomFieldFocused: Bool
    /// True when zoom should track the viewport (Fit). Cleared by manual zoom.
    @State private var isZoomFitted = true
    @State private var isCropMode = false
    @State private var isEditorFullscreen = false
    @State private var shareButtonFrameInWindow: CGRect = .zero
    @State private var outputSize: CGSize?
    @State private var commitEditingTrigger = 0
    @State private var chromeBindAttempts = 0
    /// Cached text line bounding boxes for smart highlighter snapping.
    @State private var textRegions: [CGRect] = []

    private static let minZoom: CGFloat = 0.1
    private static let maxZoom: CGFloat = 4.0
    private static let minZoomPercent: Double = 10
    private static let maxZoomPercent: Double = 400

    private var imageWidth: CGFloat { CGFloat(sourceImage.width) }
    private var imageHeight: CGFloat { CGFloat(sourceImage.height) }

    /// Visible image width after applying any committed crop. The canvas view
    /// is still rendered at full image size but clipped+offset to show only
    /// this region, so annotations stay in full-image coordinates while layout
    /// and Save output reflect the crop.
    private var effectiveImageWidth: CGFloat {
        document.cropRect?.width ?? imageWidth
    }

    private var effectiveImageHeight: CGFloat {
        document.cropRect?.height ?? imageHeight
    }

    private var cropOffsetX: CGFloat {
        -(document.cropRect?.minX ?? 0) * zoomScale
    }

    private var cropOffsetY: CGFloat {
        -(document.cropRect?.minY ?? 0) * zoomScale
    }

    private var previewContentWidth: CGFloat {
        beautifySettings.isEnabled ? effectiveImageWidth + beautifySettings.outerInset * 2 : effectiveImageWidth
    }

    private var previewContentHeight: CGFloat {
        beautifySettings.isEnabled ? effectiveImageHeight + beautifySettings.outerInset * 2 : effectiveImageHeight
    }

    private var previewOuterInset: CGFloat {
        beautifySettings.isEnabled ? beautifySettings.outerInset * zoomScale : 0
    }

    private var previewWidth: CGFloat {
        previewContentWidth * zoomScale
    }

    private var previewHeight: CGFloat {
        previewContentHeight * zoomScale
    }

    private var currentStyle: AnnotationKit.StrokeStyle {
        let opacity: CGFloat
        switch currentTool {
        case .highlighter:
            opacity = 0.35
        case .highlightFocus:
            opacity = highlightFocusOpacity
        default:
            opacity = 1.0
        }
        return AnnotationKit.StrokeStyle(
            color: currentColor,
            lineWidth: lineWidth,
            opacity: opacity,
            filled: filled || currentTool == .highlightFocus,
            pattern: strokePattern
        )
    }

    /// Font size currently pushed to the canvas. When the slider is in
    /// font-size mode (text tool active OR mid-edit), the live slider value
    /// wins so dragging it updates the editor in real time. Otherwise we
    /// fall back to the preserved value from the last text session.
    private var effectiveTextFontSize: CGFloat {
        (sizeControlTool == .text || currentTool == .text || isEditingText)
            ? lineWidth
            : CGFloat(savedTextFontSize)
    }

    /// Size slider owner: selected object type when one is selected, else the active tool.
    private var sizeControlTool: AnnotationTool? {
        guard let selected = document.selectedObject else { return nil }
        switch selected {
        case is TextObject: return .text
        case is CounterObject: return .counter
        case is PixelateObject: return .pixelate
        case is FreehandObject:
            return selected.style.opacity < 0.5 ? .highlighter : .freehand
        case is ArrowObject: return .arrow
        case is LineObject: return .line
        case is RectangleObject: return .rectangle
        case is EllipseObject: return .ellipse
        case is HighlightFocusObject: return .highlightFocus
        default: return nil
        }
    }

    private var sizeToolForPersistence: AnnotationTool {
        sizeControlTool ?? currentTool
    }

    private var textFillColor: AnnotationColor? {
        textFillEnabled ? .black : nil
    }

    private var textOutlineColor: AnnotationColor? {
        textOutlineEnabled ? .white : nil
    }

    private var textGlyphStrokeColor: AnnotationColor? {
        textStrokeEnabled ? .white : nil
    }

    /// Preserved width for the given tool. Bridges between the `Double`
    /// UserDefaults stores and the canvas's `CGFloat` slider value.
    private func savedWidth(for tool: AnnotationTool) -> CGFloat {
        switch tool {
        case .pixelate: return CGFloat(savedBlockSize)
        case .counter: return CGFloat(savedCounterSize)
        case .highlighter: return CGFloat(savedHighlighterWidth)
        case .highlightFocus: return CGFloat(savedHighlightFocusCornerRadius)
        case .text: return CGFloat(savedTextFontSize)
        default: return CGFloat(savedLineWidth)
        }
    }

    /// Persist the current slider value into the store that owns the given
    /// tool. Called on every slider change so a dragged-then-closed editor
    /// still saves the user's choice.
    private func persistWidth(_ width: CGFloat, for tool: AnnotationTool) {
        switch tool {
        case .pixelate: savedBlockSize = Double(width)
        case .counter: savedCounterSize = Double(width)
        case .highlighter: savedHighlighterWidth = Double(width)
        case .highlightFocus: savedHighlightFocusCornerRadius = Double(width)
        case .text: savedTextFontSize = Double(width)
        default: savedLineWidth = Double(width)
        }
    }

    /// Live preview of the Beautify background. For solid, just a filled Rect.
    /// For liquid glass, a blurred & saturation-boosted copy of the screenshot
    /// scaled to fill the background area — mirrors what `BeautifyRenderer`
    /// produces on export. Blur radius is scaled by `zoomScale` so that the
    /// perceived amount of blur matches the fixed 120-image-pixel blur used
    /// by the renderer at any zoom level.
    @ViewBuilder
    private var beautifyBackground: some View {
        switch beautifySettings.backgroundStyle {
        case .solid:
            Rectangle()
                .fill(beautifySettings.backgroundColor)
        case .liquidGlass:
            Image(decorative: sourceImage, scale: 1.0)
                .resizable()
                .scaledToFill()
                .saturation(1.9)
                .blur(radius: max(8, 120 * zoomScale), opaque: true)
                .overlay(Color.white.opacity(0.03))
                .clipped()
        }
    }

    var body: some View {
        if isCropMode {
            cropEditor
        } else {
            editorContent
        }
    }

    private var cropEditor: some View {
        CropEditorView(
            sourceImage: sourceImage,
            initialCropRect: document.cropRect,
            initialOutputSize: outputSize,
            canTransformImage: document.objects.isEmpty,
            onCancel: { isCropMode = false },
            onCommit: commitCrop
        )
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if showBeautifyPanel {
                BeautifyPanel(settings: $beautifySettings)
                Divider()
            }

            canvasArea
            zoomBar
        }
        .onAppear(perform: bindEditorWindowChrome)
    }

    private var toolbar: some View {
        AnnotationToolbar(
            currentTool: $currentTool,
            currentColor: $currentColor,
            lineWidth: $lineWidth,
            strokePattern: $strokePattern,
            filled: $filled,
            textFillEnabled: $textFillEnabled,
            textOutlineEnabled: $textOutlineEnabled,
            textStrokeEnabled: $textStrokeEnabled,
            textBoldEnabled: $textBoldEnabled,
            textItalicEnabled: $textItalicEnabled,
            textUnderlineEnabled: $textUnderlineEnabled,
            textAlignment: $textAlignment,
            redactionMode: $redactionMode,
            showBeautifyPanel: $showBeautifyPanel,
            penStyle: $penStyle,
            highlightFocusOpacity: $highlightFocusOpacity,
            isEditingText: isEditingText,
            sizeControlTool: sizeControlTool,
            canUndo: document.canUndo,
            canRedo: document.canRedo,
            onUndo: { document.undo(); refreshTrigger += 1 },
            onRedo: { document.redo(); refreshTrigger += 1 },
            onSave: { save() },
            onCopy: { copy() },
            onCancel: onCancel,
            onCrop: { isCropMode = true },
            onInsertImageFromClipboard: insertImageFromClipboard,
            onInsertImageFromFile: insertImageFromFile
        )
    }

    private var canvasArea: some View {
        GeometryReader { geo in
            let contentWidth = beautifySettings.isEnabled
                ? previewWidth
                : effectiveImageWidth * zoomScale
            let contentHeight = beautifySettings.isEnabled
                ? previewHeight
                : effectiveImageHeight * zoomScale
            // Expand the scroll content to at least the viewport, then center
            // the image so it sits in the middle when smaller than the window.
            let scrollWidth = max(geo.size.width, contentWidth)
            let scrollHeight = max(geo.size.height, contentHeight)

            ScrollView([.horizontal, .vertical]) {
                previewCanvas
                    .frame(width: contentWidth, height: contentHeight)
                    .frame(
                        width: scrollWidth,
                        height: scrollHeight,
                        alignment: .center
                    )
            }
            .background(Color(white: 0.12))
            .onAppear { handleCanvasAppear(size: geo.size) }
            .onChange(of: currentTool, handleToolChange)
            .onChange(of: currentColor) { _, _ in updateSelectedStyle() }
            .onChange(of: lineWidth, handleLineWidthChange)
            .onChange(of: highlightFocusOpacity, handleHighlightFocusOpacityChange)
            .onChange(of: strokePattern, handleStrokePatternChange)
            .onChange(of: filled) { _, _ in updateSelectedStyle() }
            .onChange(of: textFillEnabled) { _, _ in updateSelectedStyle() }
            .onChange(of: textOutlineEnabled) { _, _ in updateSelectedStyle() }
            .onChange(of: textStrokeEnabled) { _, _ in updateSelectedStyle() }
            .onChange(of: textBoldEnabled) { _, _ in updateSelectedStyle() }
            .onChange(of: textItalicEnabled) { _, _ in updateSelectedStyle() }
            .onChange(of: textUnderlineEnabled) { _, _ in updateSelectedStyle() }
            .onChange(of: textAlignment) { _, _ in updateSelectedStyle() }
            .onChange(of: penStyle) { _, _ in updateSelectedStyle() }
            .onChange(of: redactionMode) { _, _ in updateSelectedStyle() }
            .onChange(of: beautifySettings.isEnabled) { _, _ in
                refitToCurrentWindow()
            }
            .onChange(of: document.selectedObjectID, handleSelectionChange)
            .onChange(of: geo.size, handleCanvasSizeChange)
            .onChange(of: zoomScale) { _, newValue in
                syncZoomPercentDraft(from: newValue)
            }
        }
    }

    private var previewCanvas: some View {
        ZStack {
            if beautifySettings.isEnabled {
                beautifyBackground
                    .frame(width: previewWidth, height: previewHeight)
            }

            annotationCanvas
        }
        .frame(
            width: beautifySettings.isEnabled ? previewWidth : effectiveImageWidth * zoomScale,
            height: beautifySettings.isEnabled ? previewHeight : effectiveImageHeight * zoomScale
        )
    }

    private var annotationCanvas: some View {
        AnnotationCanvasView(
            document: document,
            sourceImage: sourceImage,
            currentTool: currentTool,
            currentStyle: currentStyle,
            redactionMode: redactionMode,
            textFontSize: effectiveTextFontSize,
            textFillColor: textFillColor,
            textOutlineColor: textOutlineColor,
            textGlyphStrokeColor: textGlyphStrokeColor,
            textBold: textBoldEnabled,
            textItalic: textItalicEnabled,
            textUnderline: textUnderlineEnabled,
            textAlignment: textAlignment,
            penStyle: penStyle,
            zoomScale: zoomScale,
            refreshTrigger: refreshTrigger,
            textRegions: textRegions,
            commitEditingTrigger: commitEditingTrigger,
            onSwitchToSelect: switchToSelectTool,
            onInteractionChanged: handleCanvasInteractionChanged,
            onTextEditingStarted: handleTextEditingStarted,
            onTextEditingEnded: handleTextEditingEnded
        )
        .frame(width: imageWidth * zoomScale, height: imageHeight * zoomScale)
        .offset(x: cropOffsetX, y: cropOffsetY)
        .frame(
            width: effectiveImageWidth * zoomScale,
            height: effectiveImageHeight * zoomScale,
            alignment: .topLeading
        )
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: canvasCornerRadius))
        .shadow(color: canvasShadowColor, radius: canvasShadowRadius, y: canvasShadowOffsetY)
        .padding(previewOuterInset)
    }

    private var zoomBar: some View {
        HStack(spacing: 8) {
            Button(action: zoomOut) {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("-", modifiers: .command)
            .help("Zoom Out (⌘−)")
            .disabled(zoomScale <= Self.minZoom)

            HStack(spacing: 2) {
                TextField("", text: $zoomPercentDraft)
                    .font(.system(size: 11, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
                    .frame(width: 36)
                    .focused($isZoomFieldFocused)
                    .onSubmit(commitZoomPercentDraft)
                    .onChange(of: isZoomFieldFocused) { _, focused in
                        if !focused { commitZoomPercentDraft() }
                    }
                Text("%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            .help("Enter zoom percentage")

            Button(action: zoomIn) {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("=", modifiers: .command)
            .help("Zoom In (⌘=)")
            .disabled(zoomScale >= Self.maxZoom)

            Slider(
                value: zoomPercentSliderBinding,
                in: Self.minZoomPercent...Self.maxZoomPercent
            )
            .frame(width: 140)
            .help("Drag to zoom (10%–400%)")

            Button("Fit", action: refitToCurrentWindow)
                .buttonStyle(.borderless)
                .keyboardShortcut("0", modifiers: .command)
                .help("Fit to Window (⌘0)")

            Button("100%", action: zoomToActualSize)
                .buttonStyle(.borderless)
                .keyboardShortcut("1", modifiers: .command)
                .help("Actual Size (⌘1)")
                .disabled(abs(zoomScale - 1) < 0.001)

            Spacer()

            Button(action: share) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .help("Share (⇧⌘I)")
            .background(ShareButtonAnchorReader { rect in
                shareButtonFrameInWindow = rect
            })

            Button(action: pin) {
                Image(systemName: "pin")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("p", modifiers: .command)
            .help("Pin (⌘P)")

            Button(action: toggleEditorFullscreen) {
                Image(systemName: isEditorFullscreen
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.borderless)
            .help(isEditorFullscreen
                  ? "Exit Full Screen (⌃⌘F)"
                  : "Enter Full Screen (⌃⌘F)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private var zoomPercentSliderBinding: Binding<Double> {
        Binding(
            get: { Double(zoomScale * 100) },
            set: { newPercent in
                setZoomScale(CGFloat(newPercent / 100), fitted: false)
            }
        )
    }

    private var canvasCornerRadius: CGFloat {
        beautifySettings.isEnabled ? beautifySettings.clampedCornerRadius * zoomScale : 0
    }

    private var canvasShadowColor: Color {
        .black.opacity(beautifySettings.isEnabled && beautifySettings.shadowEnabled ? 0.25 : 0)
    }

    private var canvasShadowRadius: CGFloat {
        beautifySettings.isEnabled && beautifySettings.shadowEnabled
            ? beautifySettings.clampedShadowRadius * zoomScale
            : 0
    }

    private var canvasShadowOffsetY: CGFloat {
        beautifySettings.isEnabled && beautifySettings.shadowEnabled ? 6 * zoomScale : 0
    }

    private func commitCrop(newImage: CGImage?, newRect: CGRect?, newOutputSize: CGSize?) {
        if let newImage {
            sourceImage = newImage
            document.replaceImage(size: CGSize(width: newImage.width, height: newImage.height))
            document.setCropRect(newRect)
        } else {
            document.setCropRect(newRect)
        }
        outputSize = newOutputSize
        isCropMode = false
    }

    private func handleCanvasAppear(size: CGSize) {
        fitToWindow(availableSize: size)
        lineWidth = savedWidth(for: currentTool)
        highlightFocusOpacity = CGFloat(savedHighlightFocusOpacity)
        strokePattern = savedStrokePattern
        if currentTool == .highlightFocus {
            if currentColor != .black && document.highlightFocusObject == nil {
                currentColor = .black
            }
            document.ensureHighlightFocusOverlay(
                cornerRadius: lineWidth,
                style: AnnotationKit.StrokeStyle(
                    color: currentColor,
                    lineWidth: 1,
                    opacity: highlightFocusOpacity,
                    filled: true
                )
            )
            refreshTrigger += 1
        }
        Task {
            if let regions = try? await TextRecognizer.recognize(
                image: sourceImage, level: .fast, detectURLs: false
            ) {
                textRegions = regions.map(\.boundingBox)
            }
        }
    }

    private func handleToolChange(oldTool: AnnotationTool, newTool: AnnotationTool) {
        document.clearSelection()
        persistWidth(lineWidth, for: oldTool)
        lineWidth = savedWidth(for: newTool)
        if oldTool == .highlightFocus, newTool != .highlightFocus {
            document.removeEmptyHighlightFocusOverlay()
            refreshTrigger += 1
        }
        if newTool == .highlightFocus {
            // Default spotlight color is black; user can change via the picker.
            if currentColor != .black && document.highlightFocusObject == nil {
                currentColor = .black
            }
            highlightFocusOpacity = CGFloat(savedHighlightFocusOpacity)
            document.ensureHighlightFocusOverlay(
                cornerRadius: lineWidth,
                style: AnnotationKit.StrokeStyle(
                    color: currentColor,
                    lineWidth: 1,
                    opacity: highlightFocusOpacity,
                    filled: true
                )
            )
            refreshTrigger += 1
        }
    }

    private func handleLineWidthChange(oldValue: CGFloat, newValue: CGFloat) {
        updateSelectedStyle()
        persistWidth(newValue, for: sizeToolForPersistence)
    }

    private func handleHighlightFocusOpacityChange(oldValue: CGFloat, newValue: CGFloat) {
        savedHighlightFocusOpacity = Double(newValue)
        updateSelectedStyle()
    }

    private func handleSelectionChange(oldValue: ObjectID?, newValue: ObjectID?) {
        guard let selected = document.selectedObject else { return }
        syncToolbar(from: selected)
    }

    private func syncToolbar(from object: any AnnotationObject) {
        if let text = object as? TextObject {
            if lineWidth != text.fontSize {
                lineWidth = text.fontSize
            }
            currentColor = text.style.color
            textFillEnabled = text.fillColor != nil
            textOutlineEnabled = text.outlineColor != nil
            textStrokeEnabled = text.glyphStrokeColor != nil
            textBoldEnabled = text.isBold
            textItalicEnabled = text.isItalic
            textUnderlineEnabled = text.isUnderline
            textAlignment = text.alignment
            return
        }
        if let counter = object as? CounterObject {
            if lineWidth != counter.radius {
                lineWidth = counter.radius
            }
            currentColor = counter.style.color
            return
        }
        if let pixelate = object as? PixelateObject {
            if lineWidth != pixelate.blockSize {
                lineWidth = pixelate.blockSize
            }
            redactionMode = pixelate.mode
            return
        }
        if let spotlight = object as? HighlightFocusObject {
            if lineWidth != spotlight.cornerRadius {
                lineWidth = spotlight.cornerRadius
            }
            if abs(highlightFocusOpacity - spotlight.style.opacity) > 0.001 {
                highlightFocusOpacity = spotlight.style.opacity
            }
            currentColor = spotlight.style.color
            return
        }
        if let freehand = object as? FreehandObject, freehand.style.opacity >= 0.5 {
            penStyle = freehand.penStyle
        }
        if lineWidth != object.style.lineWidth {
            lineWidth = object.style.lineWidth
        }
        currentColor = object.style.color
        filled = object.style.filled
        strokePattern = object.style.pattern
    }

    private func handleStrokePatternChange(oldValue: StrokePattern, newValue: StrokePattern) {
        savedStrokePattern = newValue
        updateSelectedStyle()
    }

    private func handleCanvasSizeChange(oldSize: CGSize, newSize: CGSize) {
        // Keep the image fitted when the viewport changes (resize / fullscreen)
        // if the user hasn't chosen a manual zoom level.
        if isZoomFitted {
            fitToWindow(availableSize: newSize)
        }
    }

    private func handleCanvasInteractionChanged(_ isInteracting: Bool) {
        interactionState.setCanvasInteraction(isInteracting)
    }

    private func switchToSelectTool() {
        document.clearSelection()
        currentTool = .select
    }

    private func handleTextEditingStarted(
        fontSize: CGFloat,
        hasFill: Bool,
        hasOutline: Bool,
        hasStroke: Bool,
        isBold: Bool,
        isItalic: Bool,
        isUnderline: Bool,
        alignment: AnnotationTextAlignment
    ) {
        isEditingText = true
        interactionState.isEditingText = true
        textFillEnabled = hasFill
        textOutlineEnabled = hasOutline
        textStrokeEnabled = hasStroke
        textBoldEnabled = isBold
        textItalicEnabled = isItalic
        textUnderlineEnabled = isUnderline
        textAlignment = alignment
        if lineWidth != fontSize {
            lineWidth = fontSize
        }
    }

    private func handleTextEditingEnded() {
        isEditingText = false
        interactionState.isEditingText = false
        savedTextFontSize = Double(lineWidth)
    }

    private func editorWindow() -> AnnotationEditorWindow? {
        if let key = NSApp.keyWindow as? AnnotationEditorWindow {
            return key
        }
        return NSApp.windows.compactMap { $0 as? AnnotationEditorWindow }.first { $0.isVisible }
    }

    /// Wire pinch / ⌘-scroll zoom and fullscreen callbacks onto the hosting panel.
    private func bindEditorWindowChrome() {
        guard let window = editorWindow() else {
            guard chromeBindAttempts < 10 else { return }
            chromeBindAttempts += 1
            DispatchQueue.main.async {
                bindEditorWindowChrome()
            }
            return
        }
        chromeBindAttempts = 0
        isEditorFullscreen = window.isEditorFullscreen
        window.onZoomByFactor = { factor in
            applyZoomFactor(factor)
        }
        window.onFullscreenChanged = { fullscreen in
            isEditorFullscreen = fullscreen
            // Viewport GeometryReader will refit via `isZoomFitted` + size change.
            // Also force a fit in case the size callback already fired mid-animation.
            if isZoomFitted {
                DispatchQueue.main.async {
                    refitToCurrentWindow()
                }
            }
        }
    }

    private func toggleEditorFullscreen() {
        guard let window = editorWindow() else { return }
        window.toggleEditorFullscreen()
        isEditorFullscreen = window.isEditorFullscreen
    }

    private func refitToCurrentWindow() {
        let window = editorWindow() ?? (NSApp.keyWindow as NSWindow?)
        guard let window else { return }
        let toolbarH: CGFloat = 90
        let available = CGSize(
            width: window.contentView?.bounds.width ?? 800,
            height: (window.contentView?.bounds.height ?? 600) - toolbarH
        )
        fitToWindow(availableSize: available)
    }

    private func fitScale(for size: CGSize) -> CGFloat {
        guard previewContentWidth > 0, previewContentHeight > 0 else { return 1 }
        let viewportPadding: CGFloat = 20
        let scaleX = (size.width - viewportPadding) / previewContentWidth
        let scaleY = (size.height - viewportPadding) / previewContentHeight
        return min(scaleX, scaleY, 1.0) // Never zoom above 100%
    }

    private func fitToWindow(availableSize: CGSize) {
        setZoomScale(fitScale(for: availableSize), fitted: true)
    }

    private func setZoomScale(_ scale: CGFloat, fitted: Bool) {
        let clamped = min(max(scale, Self.minZoom), Self.maxZoom)
        isZoomFitted = fitted
        zoomScale = clamped
        syncZoomPercentDraft(from: clamped)
    }

    private func applyZoomFactor(_ factor: CGFloat) {
        guard factor > 0, factor.isFinite else { return }
        setZoomScale(zoomScale * factor, fitted: false)
    }

    private func zoomIn() {
        applyZoomFactor(1.25)
    }

    private func zoomOut() {
        applyZoomFactor(1 / 1.25)
    }

    private func zoomToActualSize() {
        setZoomScale(1.0, fitted: false)
    }

    private func syncZoomPercentDraft(from scale: CGFloat) {
        guard !isZoomFieldFocused else { return }
        zoomPercentDraft = "\(Int((scale * 100).rounded()))"
    }

    private func commitZoomPercentDraft() {
        let trimmed = zoomPercentDraft
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%", with: "")
        guard let value = Double(trimmed), value.isFinite else {
            syncZoomPercentDraft(from: zoomScale)
            return
        }
        setZoomScale(CGFloat(value / 100), fitted: false)
    }

    /// Update the selected object's style when color/lineWidth/filled changes
    private func updateSelectedStyle() {
        if let spotlight = document.highlightFocusObject,
           currentTool == .highlightFocus || document.selectedObject is HighlightFocusObject {
            spotlight.cornerRadius = lineWidth
            spotlight.style = AnnotationKit.StrokeStyle(
                color: currentColor,
                lineWidth: 1,
                opacity: highlightFocusOpacity,
                filled: true
            )
            refreshTrigger += 1
            if document.selectedObject is HighlightFocusObject || document.selectedObject == nil {
                return
            }
        }
        if let obj = document.selectedObject {
            if let pixelate = obj as? PixelateObject {
                pixelate.blockSize = lineWidth
                pixelate.mode = redactionMode
                pixelate.style = currentStyle
            } else if let counter = obj as? CounterObject {
                counter.radius = lineWidth
                counter.style = AnnotationKit.StrokeStyle(color: currentColor, lineWidth: lineWidth, filled: filled)
            } else if let text = obj as? TextObject {
                text.fontSize = lineWidth
                text.fillColor = textFillColor
                text.outlineColor = textOutlineColor
                text.glyphStrokeColor = textGlyphStrokeColor
                text.isBold = textBoldEnabled
                text.isItalic = textItalicEnabled
                text.isUnderline = textUnderlineEnabled
                text.alignment = textAlignment
                text.style = currentStyle
            } else if let freehand = obj as? FreehandObject {
                freehand.penStyle = freehand.style.opacity < 0.5 ? .marker : penStyle
                freehand.style = currentStyle
            } else if obj is HighlightFocusObject {
                // Already handled above.
            } else {
                obj.style = currentStyle
            }
            refreshTrigger += 1
        }
    }

    private func insertImageFromClipboard() {
        guard let image = AnnotationImageInsertion.imageFromClipboard(),
              AnnotationImageInsertion.insertIntoDocument(document, image: image) else {
            return
        }
        currentTool = .select
        refreshTrigger += 1
    }

    private func insertImageFromFile() {
        guard let image = AnnotationImageInsertion.imageFromOpenPanel(),
              AnnotationImageInsertion.insertIntoDocument(document, image: image) else {
            return
        }
        currentTool = .select
        refreshTrigger += 1
    }

    private func renderedOutputImage() -> CGImage? {
        guard let annotated = AnnotationRenderer.render(
            sourceImage: sourceImage,
            objects: document.objects,
            cropRect: document.cropRect
        ) else {
            return nil
        }
        guard let rendered = BeautifyRenderer.render(image: annotated, settings: beautifySettings) else {
            return nil
        }
        guard let outputSize else { return rendered }

        let width = max(1, Int(outputSize.width.rounded()))
        let height = max(1, Int(outputSize.height.rounded()))
        guard width != rendered.width || height != rendered.height else {
            return rendered
        }
        return ImageUtilities.resized(rendered, width: width, height: height) ?? rendered
    }

    private func save() {
        commitEditingTrigger += 1
        DispatchQueue.main.async {
            if let rendered = renderedOutputImage() {
                onSave(rendered, sourceImage, document)
            }
        }
    }

    private func copy() {
        // Toolbar / explicit Copy must always export the image. Suppression is
        // only for ⌘C while dragging or editing so it doesn't steal object-clipboard.
        commitEditingTrigger += 1
        DispatchQueue.main.async {
            if let rendered = renderedOutputImage() {
                onCopy(rendered, sourceImage, document)
            }
        }
    }

    private func pin() {
        commitEditingTrigger += 1
        DispatchQueue.main.async {
            if let rendered = renderedOutputImage() {
                onPin(rendered)
            }
        }
    }

    private func share() {
        // Capture the Share control's location before async render — otherwise
        // `NSApp.currentEvent` is gone and the system sheet anchors elsewhere.
        if let window = editorWindow(),
           let content = window.contentView {
            let anchor: NSRect
            if let event = NSApp.currentEvent, event.window === window {
                let p = content.convert(event.locationInWindow, from: nil)
                anchor = NSRect(x: p.x - 14, y: p.y - 14, width: 28, height: 28)
            } else if shareButtonFrameInWindow.width > 0 {
                // Fallback: convert SwiftUI global frame → contentView.
                anchor = contentViewRect(fromGlobal: shareButtonFrameInWindow, window: window, content: content)
                    ?? .zero
            } else {
                anchor = .zero
            }
            if anchor.width > 0 {
                window.pendingShareAnchorInContentView = anchor
            }
        }

        commitEditingTrigger += 1
        DispatchQueue.main.async {
            if let rendered = renderedOutputImage() {
                onShare(rendered)
            }
        }
    }

    /// Converts a SwiftUI `.global` rect (top-left origin, screen space) into
    /// AppKit `contentView` coordinates (bottom-left origin).
    private func contentViewRect(
        fromGlobal global: CGRect,
        window: NSWindow,
        content: NSView
    ) -> NSRect? {
        guard let screen = window.screen ?? NSScreen.main else { return nil }
        // SwiftUI global Y grows downward from the primary-layout top; AppKit
        // screen Y grows upward from the bottom of the screen.
        let screenHeight = screen.frame.maxY
        let appKitScreenRect = NSRect(
            x: global.minX,
            y: screenHeight - global.maxY,
            width: global.width,
            height: global.height
        )
        let windowRect = window.convertFromScreen(appKitScreenRect)
        return content.convert(windowRect, from: nil)
    }
}

/// Reads a SwiftUI view's frame in global coordinates for share-sheet anchoring.
private struct ShareButtonAnchorReader: View {
    let onChange: (CGRect) -> Void

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { onChange(geo.frame(in: .global)) }
                .onChange(of: geo.frame(in: .global)) { _, newValue in
                    onChange(newValue)
                }
        }
    }
}
