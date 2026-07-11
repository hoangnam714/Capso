// Packages/CameraKit/Tests/CameraKitTests/CameraManagerTests.swift
import Testing
@testable import CameraKit

@Suite("CameraManager")
struct CameraManagerTests {
    @Test("CameraClipShape has expected cases")
    func shapes() {
        let shapes: [CameraClipShape] = [.circle, .roundedRect]
        #expect(shapes.count == 2)
    }

    @Test("CameraPosition has expected cases")
    func positions() {
        let positions: [CameraPosition] = [.bottomLeft, .bottomRight, .topLeft, .topRight]
        #expect(positions.count == 4)
    }
}
