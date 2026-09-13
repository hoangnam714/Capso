import Foundation
import AnnotationKit

/// Per-tool stroke colors persisted across editor sessions.
/// Fixes the bug where drawing a second stroke reset to the global default
/// because `annotationLastColor` was shared across every tool.
enum AnnotationToolColorStore {
    private static let storageKey = "annotationToolColors"
    private static let legacyKey = "annotationLastColor"

    static func color(for tool: AnnotationTool) -> AnnotationColor {
        switch tool {
        case .select, .pixelate:
            return .red
        case .highlightFocus:
            return storedColor(for: tool) ?? .black
        case .highlighter:
            return storedColor(for: tool) ?? .yellow
        default:
            return storedColor(for: tool) ?? legacyColor ?? .red
        }
    }

    static func setColor(_ color: AnnotationColor, for tool: AnnotationTool) {
        guard tool != .select, tool != .pixelate else { return }
        var dict = loadDict()
        dict[tool.rawValue] = color.rawValue
        UserDefaults.standard.set(dict, forKey: storageKey)
        UserDefaults.standard.set(color.rawValue, forKey: legacyKey)
    }

    /// Which tool owns the color swatch right now (selected object type or active tool).
    static func activeColorTool(currentTool: AnnotationTool, sizeControlTool: AnnotationTool?) -> AnnotationTool {
        if currentTool == .select, let sizeControlTool {
            return sizeControlTool
        }
        return currentTool
    }

    private static func storedColor(for tool: AnnotationTool) -> AnnotationColor? {
        guard let raw = loadDict()[tool.rawValue] else { return nil }
        return AnnotationColor(rawValue: raw)
    }

    private static var legacyColor: AnnotationColor? {
        guard let raw = UserDefaults.standard.string(forKey: legacyKey) else { return nil }
        return AnnotationColor(rawValue: raw)
    }

    private static func loadDict() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] ?? [:]
    }
}

/// Last-used stroke colors shown as quick picks on the annotation toolbar (max 3).
enum AnnotationRecentColorStore {
    private static let storageKey = "annotationRecentColors"
    private static let maxCount = 3

    private static let defaultColors: [AnnotationColor] = [.red, .yellow, .black]

    static func recentColors() -> [AnnotationColor] {
        guard let rawValues = UserDefaults.standard.stringArray(forKey: storageKey),
              !rawValues.isEmpty else {
            return defaultColors
        }
        let colors = rawValues.compactMap { AnnotationColor(rawValue: $0) }
        return colors.isEmpty ? defaultColors : Array(colors.prefix(maxCount))
    }

    static func record(_ color: AnnotationColor) {
        var colors = recentColors().filter { $0 != color }
        colors.insert(color, at: 0)
        if colors.count > maxCount {
            colors = Array(colors.prefix(maxCount))
        }
        UserDefaults.standard.set(colors.map(\.rawValue), forKey: storageKey)
    }
}
