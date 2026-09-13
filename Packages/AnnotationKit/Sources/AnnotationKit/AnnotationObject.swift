// Packages/AnnotationKit/Sources/AnnotationKit/AnnotationObject.swift
import Foundation
import CoreGraphics
import AppKit

public enum AnnotationTool: String, CaseIterable, Sendable {
    case select, arrow, line, rectangle, ellipse, shape, text, freehand, pixelate, counter, highlighter, highlightFocus
}

/// Arrow tip style. `.single` is the classic tip-at-end; `.double` draws tips at both ends.
public enum ArrowHeadStyle: String, Codable, CaseIterable, Sendable {
    case single
    case double

    public var label: String {
        switch self {
        case .single: String(localized: "One Way")
        case .double: String(localized: "Two Way")
        }
    }

    public var systemImage: String {
        switch self {
        case .single: "arrow.up.right"
        case .double: "arrow.left.and.right"
        }
    }
}

/// Extra closed shapes drawn via the Shape tool (beyond rectangle / ellipse).
public enum ShapeKind: String, Codable, CaseIterable, Sendable {
    case triangle
    case rightTriangle
    case invertedTriangle
    case diamond
    case trapezoid
    case parallelogram
    case pentagon
    case hexagon
    case octagon
    case star
    case star6
    case plus
    case cross
    case chevron
    case blockArrow
    case semicircle
    case pill
    case heart
    case teardrop
    case crescent
    case cloud
    case speechBubble
    case cloudSpeechBubble
    case thoughtBubble
    case banner
    case cylinder
    case ring
    case lightning

    public var label: String {
        switch self {
        case .triangle: String(localized: "Triangle")
        case .rightTriangle: String(localized: "Right Triangle")
        case .invertedTriangle: String(localized: "Inverted Triangle")
        case .diamond: String(localized: "Diamond")
        case .trapezoid: String(localized: "Trapezoid")
        case .parallelogram: String(localized: "Parallelogram")
        case .pentagon: String(localized: "Pentagon")
        case .hexagon: String(localized: "Hexagon")
        case .octagon: String(localized: "Octagon")
        case .star: String(localized: "Star")
        case .star6: String(localized: "6-Point Star")
        case .plus: String(localized: "Plus")
        case .cross: String(localized: "Cross")
        case .chevron: String(localized: "Chevron")
        case .blockArrow: String(localized: "Block Arrow")
        case .semicircle: String(localized: "Semicircle")
        case .pill: String(localized: "Pill")
        case .heart: String(localized: "Heart")
        case .teardrop: String(localized: "Teardrop")
        case .crescent: String(localized: "Crescent")
        case .cloud: String(localized: "Cloud")
        case .speechBubble: String(localized: "Speech Bubble")
        case .cloudSpeechBubble: String(localized: "Cloud Speech")
        case .thoughtBubble: String(localized: "Thought Bubble")
        case .banner: String(localized: "Banner")
        case .cylinder: String(localized: "Cylinder")
        case .ring: String(localized: "Ring")
        case .lightning: String(localized: "Lightning")
        }
    }

    public var systemImage: String {
        switch self {
        case .triangle: "triangle"
        case .rightTriangle: "triangle"
        case .invertedTriangle: "triangle.tophalf.filled"
        case .diamond: "diamond"
        case .trapezoid: "rectangle.portrait"
        case .parallelogram: "parallelogram"
        case .pentagon: "pentagon"
        case .hexagon: "hexagon"
        case .octagon: "octagon"
        case .star: "star"
        case .star6: "seal"
        case .plus: "plus"
        case .cross: "xmark"
        case .chevron: "chevron.right"
        case .blockArrow: "arrowtriangle.right.fill"
        case .semicircle: "circle.bottomhalf.filled"
        case .pill: "capsule"
        case .heart: "heart"
        case .teardrop: "drop"
        case .crescent: "moon"
        case .cloud: "cloud"
        case .speechBubble: "bubble.left"
        case .cloudSpeechBubble: "cloud"
        case .thoughtBubble: "ellipsis.bubble"
        case .banner: "flag"
        case .cylinder: "oval"
        case .ring: "circle.circle"
        case .lightning: "bolt"
        }
    }

    /// Shapes whose fill uses even-odd so holes (e.g. ring) stay transparent.
    public var usesEvenOddFill: Bool {
        switch self {
        case .ring, .crescent: true
        default: false
        }
    }
}

public enum RedactionMode: Int, Codable, CaseIterable, Sendable {
    case pixelate
    case blur
    case solid

    public var label: String {
        switch self {
        case .pixelate: "Pixelate"
        case .blur: "Blur"
        case .solid: "Solid"
        }
    }
}

public struct ObjectID: Hashable, Sendable {
    public let value: UUID
    public init(value: UUID = UUID()) { self.value = value }
}

public enum StrokePattern: String, Codable, CaseIterable, Sendable {
    case solid
    case dashed
    case longDashed
    case dotted
    case dashDot

    public var label: String {
        switch self {
        case .solid: String(localized: "Solid")
        case .dashed: String(localized: "Dashed")
        case .longDashed: String(localized: "Long Dash")
        case .dotted: String(localized: "Dotted")
        case .dashDot: String(localized: "Dash Dot")
        }
    }

    public func apply(to context: CGContext, lineWidth: CGFloat) {
        switch self {
        case .solid:
            context.setLineDash(phase: 0, lengths: [])
        case .dashed:
            context.setLineDash(phase: 0, lengths: [lineWidth * 3, lineWidth * 2])
        case .longDashed:
            context.setLineDash(phase: 0, lengths: [lineWidth * 8, lineWidth * 3])
        case .dotted:
            context.setLineDash(phase: 0, lengths: [0, max(lineWidth * 2, 6)])
        case .dashDot:
            context.setLineDash(
                phase: 0,
                lengths: [lineWidth * 4, lineWidth * 1.8, 0, lineWidth * 1.8]
            )
        }
    }
}

public enum PenStyle: String, Codable, CaseIterable, Sendable {
    case pen
    case marker
    case pencil

    public var label: String {
        switch self {
        case .pen: String(localized: "Pen")
        case .marker: String(localized: "Marker")
        case .pencil: String(localized: "Pencil")
        }
    }

    public var systemImage: String {
        switch self {
        case .pen: "pencil.tip"
        case .marker: "paintbrush.pointed"
        case .pencil: "pencil"
        }
    }

    public var usesSmoothing: Bool {
        switch self {
        case .pen, .marker: true
        case .pencil: false
        }
    }

    public var blendMode: CGBlendMode {
        switch self {
        case .pen: .normal
        case .marker: .multiply
        case .pencil: .normal
        }
    }

    public var opacityMultiplier: CGFloat {
        switch self {
        case .pen: 1
        case .marker: 0.72
        case .pencil: 0.78
        }
    }
}

public struct StrokeStyle: Sendable, Codable {
    public var color: AnnotationColor
    public var lineWidth: CGFloat
    public var opacity: CGFloat
    public var filled: Bool
    public var pattern: StrokePattern

    public init(
        color: AnnotationColor = .red,
        lineWidth: CGFloat = 3,
        opacity: CGFloat = 1,
        filled: Bool = false,
        pattern: StrokePattern = .solid
    ) {
        self.color = color
        self.lineWidth = lineWidth
        self.opacity = opacity
        self.filled = filled
        self.pattern = pattern
    }
}

public struct AnnotationColor: RawRepresentable, Codable, CaseIterable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercase = trimmed.lowercased()
        if Self.presetColors.keys.contains(lowercase) {
            self.rawValue = lowercase
            return
        }

        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard hex.count == 6, UInt32(hex, radix: 16) != nil else { return nil }
        self.rawValue = "#\(hex.uppercased())"
    }

    public init(nsColor: NSColor) {
        guard let rgb = nsColor.usingColorSpace(.deviceRGB) else {
            self.rawValue = Self.black.rawValue
            return
        }

        self.rawValue = String(
            format: "#%02X%02X%02X",
            Int(round(rgb.redComponent * 255)),
            Int(round(rgb.greenComponent * 255)),
            Int(round(rgb.blueComponent * 255))
        )
    }

    public static let red = AnnotationColor(rawValue: "red")!
    public static let orange = AnnotationColor(rawValue: "orange")!
    public static let yellow = AnnotationColor(rawValue: "yellow")!
    public static let green = AnnotationColor(rawValue: "green")!
    public static let cyan = AnnotationColor(rawValue: "cyan")!
    public static let blue = AnnotationColor(rawValue: "blue")!
    public static let purple = AnnotationColor(rawValue: "purple")!
    public static let pink = AnnotationColor(rawValue: "pink")!
    public static let white = AnnotationColor(rawValue: "white")!
    public static let gray = AnnotationColor(rawValue: "gray")!
    public static let black = AnnotationColor(rawValue: "black")!
    public static let brown = AnnotationColor(rawValue: "brown")!

    public static let allCases: [AnnotationColor] = [
        .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink,
        .white, .gray, .black, .brown,
    ]

    /// Full preset grid shown in the color popover (not on the toolbar strip).
    public static let paletteCases: [AnnotationColor] = allCases

    public var cgColor: CGColor {
        if let preset = Self.presetColors[rawValue] {
            return preset
        }

        let hex = rawValue.dropFirst()
        guard let value = UInt32(hex, radix: 16) else {
            return Self.presetColors[Self.black.rawValue]!
        }

        return CGColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    public var hexRGB: String {
        if rawValue.hasPrefix("#") {
            return rawValue
        }

        guard let components = cgColor.components, components.count >= 3 else { return "#000000" }
        return String(
            format: "#%02X%02X%02X",
            Int(round(components[0] * 255)),
            Int(round(components[1] * 255)),
            Int(round(components[2] * 255))
        )
    }

    public var nsColor: NSColor { NSColor(cgColor: cgColor)! }

    /// Black or white label color that stays readable on top of this fill.
    public var contrastingLabelNSColor: NSColor {
        guard let rgb = nsColor.usingColorSpace(.deviceRGB) else { return .white }
        let luminance =
            (0.299 * rgb.redComponent) + (0.587 * rgb.greenComponent) + (0.114 * rgb.blueComponent)
        return luminance > 0.62 ? .black : .white
    }

    public var displayName: String {
        rawValue.hasPrefix("#") ? rawValue : rawValue.capitalized
    }

    private static let presetColors: [String: CGColor] = [
        "red": CGColor(red: 1, green: 0.23, blue: 0.19, alpha: 1),
        "orange": CGColor(red: 1, green: 0.58, blue: 0, alpha: 1),
        "yellow": CGColor(red: 1, green: 0.8, blue: 0, alpha: 1),
        "green": CGColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1),
        "cyan": CGColor(red: 0.2, green: 0.78, blue: 0.88, alpha: 1),
        "blue": CGColor(red: 0, green: 0.48, blue: 1, alpha: 1),
        "purple": CGColor(red: 0.69, green: 0.32, blue: 0.87, alpha: 1),
        "pink": CGColor(red: 1, green: 0.35, blue: 0.55, alpha: 1),
        "white": CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        "gray": CGColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1),
        "black": CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        "brown": CGColor(red: 0.55, green: 0.38, blue: 0.22, alpha: 1),
    ]
}

public protocol AnnotationObject: AnyObject, Sendable {
    var id: ObjectID { get }
    var style: StrokeStyle { get set }
    var bounds: CGRect { get }
    func hitTest(point: CGPoint, threshold: CGFloat) -> Bool
    func render(in context: CGContext)
    func move(by delta: CGSize)
    func copy() -> any AnnotationObject
}
