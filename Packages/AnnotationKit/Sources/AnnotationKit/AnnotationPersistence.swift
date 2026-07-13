// Packages/AnnotationKit/Sources/AnnotationKit/AnnotationPersistence.swift
import Foundation
import CoreGraphics

/// JSON sidecar stored next to History captures so annotations stay editable.
public struct AnnotationSidecar: Codable, Sendable {
    public var version: Int
    public var imageWidth: Double
    public var imageHeight: Double
    public var cropRect: CodableRect?
    public var objects: [AnnotationRecord]

    public init(
        version: Int = 1,
        imageSize: CGSize,
        cropRect: CGRect? = nil,
        objects: [any AnnotationObject]
    ) {
        self.version = version
        self.imageWidth = imageSize.width
        self.imageHeight = imageSize.height
        self.cropRect = cropRect.map(CodableRect.init)
        self.objects = objects.compactMap(AnnotationRecord.init(object:))
    }

    public var imageSize: CGSize {
        CGSize(width: imageWidth, height: imageHeight)
    }

    public func makeObjects() -> [any AnnotationObject] {
        objects.compactMap { $0.makeObject() }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> AnnotationSidecar {
        try JSONDecoder().decode(AnnotationSidecar.self, from: data)
    }
}

public struct CodablePoint: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }

    public var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

public struct CodableSize: Codable, Sendable, Hashable {
    public var width: Double
    public var height: Double

    public init(_ size: CGSize) {
        self.width = size.width
        self.height = size.height
    }

    public var cgSize: CGSize { CGSize(width: width, height: height) }
}

public struct CodableRect: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(_ rect: CGRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.size.width
        self.height = rect.size.height
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

public enum AnnotationRecord: Codable, Sendable {
    case arrow(ArrowRecord)
    case line(LineRecord)
    case rectangle(RectangleRecord)
    case ellipse(EllipseRecord)
    case text(TextRecord)
    case freehand(FreehandRecord)
    case pixelate(PixelateRecord)
    case counter(CounterRecord)
    case image(ImageRecord)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init?(object: any AnnotationObject) {
        switch object {
        case let arrow as ArrowObject:
            self = .arrow(ArrowRecord(arrow))
        case let line as LineObject:
            self = .line(LineRecord(line))
        case let rectangle as RectangleObject:
            self = .rectangle(RectangleRecord(rectangle))
        case let ellipse as EllipseObject:
            self = .ellipse(EllipseRecord(ellipse))
        case let text as TextObject:
            self = .text(TextRecord(text))
        case let freehand as FreehandObject:
            self = .freehand(FreehandRecord(freehand))
        case let pixelate as PixelateObject:
            self = .pixelate(PixelateRecord(pixelate))
        case let counter as CounterObject:
            self = .counter(CounterRecord(counter))
        case let image as ImageObject:
            self = .image(ImageRecord(image))
        default:
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "arrow":
            self = .arrow(try ArrowRecord(from: decoder))
        case "line":
            self = .line(try LineRecord(from: decoder))
        case "rectangle":
            self = .rectangle(try RectangleRecord(from: decoder))
        case "ellipse":
            self = .ellipse(try EllipseRecord(from: decoder))
        case "text":
            self = .text(try TextRecord(from: decoder))
        case "freehand":
            self = .freehand(try FreehandRecord(from: decoder))
        case "pixelate":
            self = .pixelate(try PixelateRecord(from: decoder))
        case "counter":
            self = .counter(try CounterRecord(from: decoder))
        case "image":
            self = .image(try ImageRecord(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown annotation type \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .arrow(let record):
            try record.encode(to: encoder)
        case .line(let record):
            try record.encode(to: encoder)
        case .rectangle(let record):
            try record.encode(to: encoder)
        case .ellipse(let record):
            try record.encode(to: encoder)
        case .text(let record):
            try record.encode(to: encoder)
        case .freehand(let record):
            try record.encode(to: encoder)
        case .pixelate(let record):
            try record.encode(to: encoder)
        case .counter(let record):
            try record.encode(to: encoder)
        case .image(let record):
            try record.encode(to: encoder)
        }
    }

    public func makeObject() -> (any AnnotationObject)? {
        switch self {
        case .arrow(let record): return record.makeObject()
        case .line(let record): return record.makeObject()
        case .rectangle(let record): return record.makeObject()
        case .ellipse(let record): return record.makeObject()
        case .text(let record): return record.makeObject()
        case .freehand(let record): return record.makeObject()
        case .pixelate(let record): return record.makeObject()
        case .counter(let record): return record.makeObject()
        case .image(let record): return record.makeObject()
        }
    }
}

public struct ArrowRecord: Codable, Sendable {
    public var type: String = "arrow"
    public var style: StrokeStyle
    public var start: CodablePoint
    public var end: CodablePoint
    public var controlPoint: CodablePoint?
    public var headLength: Double

    public init(_ object: ArrowObject) {
        self.style = object.style
        self.start = CodablePoint(object.start)
        self.end = CodablePoint(object.end)
        self.controlPoint = object.controlPoint.map(CodablePoint.init)
        self.headLength = object.headLength
    }

    public func makeObject() -> ArrowObject {
        let object = ArrowObject(start: start.cgPoint, end: end.cgPoint, style: style)
        object.controlPoint = controlPoint?.cgPoint
        object.headLength = headLength
        return object
    }
}

public struct LineRecord: Codable, Sendable {
    public var type: String = "line"
    public var style: StrokeStyle
    public var start: CodablePoint
    public var end: CodablePoint

    public init(_ object: LineObject) {
        self.style = object.style
        self.start = CodablePoint(object.start)
        self.end = CodablePoint(object.end)
    }

    public func makeObject() -> LineObject {
        LineObject(start: start.cgPoint, end: end.cgPoint, style: style)
    }
}

public struct RectangleRecord: Codable, Sendable {
    public var type: String = "rectangle"
    public var style: StrokeStyle
    public var rect: CodableRect
    public var cornerRadius: Double

    public init(_ object: RectangleObject) {
        self.style = object.style
        self.rect = CodableRect(object.rect)
        self.cornerRadius = object.cornerRadius
    }

    public func makeObject() -> RectangleObject {
        let object = RectangleObject(rect: rect.cgRect, style: style)
        object.cornerRadius = cornerRadius
        return object
    }
}

public struct EllipseRecord: Codable, Sendable {
    public var type: String = "ellipse"
    public var style: StrokeStyle
    public var rect: CodableRect

    public init(_ object: EllipseObject) {
        self.style = object.style
        self.rect = CodableRect(object.rect)
    }

    public func makeObject() -> EllipseObject {
        EllipseObject(rect: rect.cgRect, style: style)
    }
}

public struct TextRecord: Codable, Sendable {
    public var type: String = "text"
    public var style: StrokeStyle
    public var text: String
    public var origin: CodablePoint
    public var boxSize: CodableSize?
    public var fontSize: Double
    public var fontName: String
    public var fillColor: AnnotationColor?
    public var outlineColor: AnnotationColor?
    public var glyphStrokeColor: AnnotationColor?
    public var isBold: Bool = false
    public var isItalic: Bool = false
    public var isUnderline: Bool = false
    public var alignment: AnnotationTextAlignment = .left

    public init(_ object: TextObject) {
        self.style = object.style
        self.text = object.text
        self.origin = CodablePoint(object.origin)
        self.boxSize = object.boxSize.map(CodableSize.init)
        self.fontSize = object.fontSize
        self.fontName = object.fontName
        self.fillColor = object.fillColor
        self.outlineColor = object.outlineColor
        self.glyphStrokeColor = object.glyphStrokeColor
        self.isBold = object.isBold
        self.isItalic = object.isItalic
        self.isUnderline = object.isUnderline
        self.alignment = object.alignment
    }

    public func makeObject() -> TextObject {
        TextObject(
            text: text,
            origin: origin.cgPoint,
            boxSize: boxSize?.cgSize,
            fontSize: fontSize,
            fontName: fontName,
            fillColor: fillColor,
            outlineColor: outlineColor,
            glyphStrokeColor: glyphStrokeColor,
            isBold: isBold,
            isItalic: isItalic,
            isUnderline: isUnderline,
            alignment: alignment,
            style: style
        )
    }
}

public struct FreehandRecord: Codable, Sendable {
    public var type: String = "freehand"
    public var style: StrokeStyle
    public var points: [CodablePoint]

    public init(_ object: FreehandObject) {
        self.style = object.style
        self.points = object.points.map(CodablePoint.init)
    }

    public func makeObject() -> FreehandObject {
        FreehandObject(points: points.map(\.cgPoint), style: style)
    }
}

public struct PixelateRecord: Codable, Sendable {
    public var type: String = "pixelate"
    public var style: StrokeStyle
    public var rect: CodableRect
    public var blockSize: Double
    public var mode: RedactionMode

    public init(_ object: PixelateObject) {
        self.style = object.style
        self.rect = CodableRect(object.rect)
        self.blockSize = object.blockSize
        self.mode = object.mode
    }

    public func makeObject() -> PixelateObject {
        let object = PixelateObject(rect: rect.cgRect, blockSize: blockSize, mode: mode)
        object.style = style
        return object
    }
}

public struct CounterRecord: Codable, Sendable {
    public var type: String = "counter"
    public var style: StrokeStyle
    public var center: CodablePoint
    public var radius: Double
    public var number: Int

    public init(_ object: CounterObject) {
        self.style = object.style
        self.center = CodablePoint(object.center)
        self.radius = object.radius
        self.number = object.number
    }

    public func makeObject() -> CounterObject {
        CounterObject(
            center: center.cgPoint,
            number: number,
            radius: radius,
            style: style
        )
    }
}

public struct ImageRecord: Codable, Sendable {
    public var type: String = "image"
    public var style: StrokeStyle
    public var rect: CodableRect
    public var imageData: Data

    public init(_ object: ImageObject) {
        self.style = object.style
        self.rect = CodableRect(object.rect)
        self.imageData = object.imageData
    }

    public func makeObject() -> ImageObject {
        ImageObject(imageData: imageData, rect: rect.cgRect, style: style)
    }
}
