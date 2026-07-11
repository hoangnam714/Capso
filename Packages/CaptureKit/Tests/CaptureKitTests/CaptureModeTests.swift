// Packages/CaptureKit/Tests/CaptureKitTests/CaptureModeTests.swift
import Testing
import Foundation
import CoreGraphics
@testable import CaptureKit

@Suite("CaptureMode")
struct CaptureModeTests {
    @Test("CaptureMode has three cases")
    func captureModes() {
        let modes: [CaptureMode] = [.area, .fullscreen, .window]
        #expect(modes.count == 3)
    }

    @Test("CaptureResult stores image and metadata")
    func captureResult() {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let image = context.makeImage()!

        let result = CaptureResult(
            image: image,
            mode: .fullscreen,
            captureRect: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )

        #expect(result.mode == .fullscreen)
        #expect(result.captureRect.width == 1920)
        #expect(result.windowName == nil)
        #expect(result.image.width == 1)
    }

    @Test("CaptureResult with window metadata")
    func captureResultWindow() {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let image = context.makeImage()!

        let result = CaptureResult(
            image: image,
            mode: .window,
            captureRect: CGRect(x: 100, y: 200, width: 800, height: 600),
            windowName: "Terminal",
            appName: "Terminal"
        )

        #expect(result.mode == .window)
        #expect(result.windowName == "Terminal")
        #expect(result.appName == "Terminal")
    }
}
