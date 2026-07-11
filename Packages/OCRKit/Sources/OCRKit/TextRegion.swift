// Packages/OCRKit/Sources/OCRKit/TextRegion.swift
import Foundation
import CoreGraphics

/// A recognized text region with its bounding box in image coordinates.
public struct TextRegion: Identifiable, Sendable {
    public let id: UUID
    public let text: String
    /// Bounding box in image coordinates (top-left origin, pixel dimensions).
    public let boundingBox: CGRect
    public let confidence: Float
    public let isURL: Bool

    public init(text: String, boundingBox: CGRect, confidence: Float, isURL: Bool = false) {
        self.id = UUID()
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.isURL = isURL
    }
}
