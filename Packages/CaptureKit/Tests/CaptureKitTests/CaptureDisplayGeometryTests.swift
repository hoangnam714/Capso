import Testing
import CoreGraphics
@testable import CaptureKit

@Suite("CaptureDisplayGeometry")
struct CaptureDisplayGeometryTests {
    @Test("Converts top-left capture rect to bottom-left screen-local rect")
    func screenLocalRectFromCaptureRect() {
        let captureRect = CGRect(x: 120, y: 80, width: 400, height: 240)

        let rect = CaptureDisplayGeometry.screenLocalRect(
            fromTopLeftCaptureRect: captureRect,
            screenHeight: 900
        )

        #expect(rect == CGRect(x: 120, y: 580, width: 400, height: 240))
    }

    @Test("Computes display scale from image pixels to screen points")
    func displayScaleForImageInScreenRect() {
        let scale = CaptureDisplayGeometry.displayScale(
            imageSize: CGSize(width: 800, height: 480),
            screenRect: CGRect(x: 0, y: 0, width: 400, height: 240)
        )

        #expect(scale == 0.5)
    }

    @Test("Positions preset badge below the physical top on screens without a notch")
    func presetBadgeYWithoutSafeAreaInset() {
        let y = CaptureDisplayGeometry.presetBadgeY(
            viewHeight: 1117,
            badgeHeight: 29,
            safeAreaTopInset: 0
        )

        #expect(y == 1068)
    }

    @Test("Positions preset badge below the notch safe area")
    func presetBadgeYWithSafeAreaInset() {
        let y = CaptureDisplayGeometry.presetBadgeY(
            viewHeight: 1117,
            badgeHeight: 29,
            safeAreaTopInset: 32
        )

        #expect(y == 992)
    }

    @Test("Rejects invalid geometry")
    func invalidGeometry() {
        #expect(CaptureDisplayGeometry.displayScale(
            imageSize: CGSize(width: 0, height: 480),
            screenRect: CGRect(x: 0, y: 0, width: 400, height: 240)
        ) == nil)
    }

    @Test("Maps a screen-local selection to frozen screenshot pixels")
    func frozenImageCropRect() {
        let crop = CaptureDisplayGeometry.frozenImageCropRect(
            screenLocalRect: CGRect(x: 120, y: 180, width: 320, height: 160),
            screenSize: CGSize(width: 800, height: 600),
            imageSize: CGSize(width: 1600, height: 1200)
        )

        #expect(crop == CGRect(x: 240, y: 520, width: 640, height: 320))
    }

    @Test("Rejects invalid frozen screenshot crop geometry")
    func invalidFrozenImageCropRect() {
        let crop = CaptureDisplayGeometry.frozenImageCropRect(
            screenLocalRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            screenSize: .zero,
            imageSize: CGSize(width: 1600, height: 1200)
        )

        #expect(crop.isNull)
    }

    @Test("Converts global top-left window frame to display-local rect")
    func displayLocalRectFromGlobalWindowFrame() {
        let rect = CaptureDisplayGeometry.displayLocalRect(
            fromGlobalTopLeftRect: CGRect(x: 1540, y: 140, width: 500, height: 320),
            displayBounds: CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        )

        #expect(rect == CGRect(x: 100, y: 140, width: 500, height: 320))
    }

    @Test("Clamps display-local window frame to visible display area")
    func displayLocalRectClampsPartiallyOffscreenWindow() {
        let rect = CaptureDisplayGeometry.displayLocalRect(
            fromGlobalTopLeftRect: CGRect(x: -20, y: 10, width: 100, height: 80),
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )

        #expect(rect == CGRect(x: 0, y: 10, width: 80, height: 80))
    }

    @Test("Normalizes a drag defined by two global points")
    func normalizedRectFromPoints() {
        let rect = CaptureDisplayGeometry.normalizedRect(
            from: CGPoint(x: 500, y: 400),
            to: CGPoint(x: 100, y: 200)
        )
        #expect(rect == CGRect(x: 100, y: 200, width: 400, height: 200))
    }

    @Test("Converts between global AppKit and screen-local rects")
    func globalAndScreenLocalConversion() {
        let screenFrame = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        let local = CGRect(x: 100, y: 50, width: 300, height: 200)
        let global = CaptureDisplayGeometry.globalAppKitRect(
            fromScreenLocalRect: local,
            screenFrame: screenFrame
        )
        #expect(global == CGRect(x: 1540, y: -150, width: 300, height: 200))
        #expect(
            CaptureDisplayGeometry.screenLocalRect(
                fromGlobalAppKitRect: global,
                screenFrame: screenFrame
            ) == local
        )
    }

    @Test("Intersects a cross-display selection with one screen")
    func intersectingScreenLocalRectAcrossDisplays() {
        let left = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let right = CGRect(x: 1440, y: -90, width: 1920, height: 1080)
        let selection = CGRect(x: 1200, y: 100, width: 500, height: 300)

        let leftLocal = CaptureDisplayGeometry.intersectingScreenLocalRect(
            globalAppKitRect: selection,
            screenFrame: left
        )
        let rightLocal = CaptureDisplayGeometry.intersectingScreenLocalRect(
            globalAppKitRect: selection,
            screenFrame: right
        )

        #expect(leftLocal == CGRect(x: 1200, y: 100, width: 240, height: 300))
        #expect(rightLocal == CGRect(x: 0, y: 190, width: 260, height: 300))
    }

    @Test("Flips screen-local bottom-left rect to display top-left")
    func displayTopLeftFromScreenLocal() {
        let rect = CaptureDisplayGeometry.displayTopLeftRect(
            fromScreenLocalRect: CGRect(x: 120, y: 180, width: 320, height: 160),
            screenHeight: 900
        )
        #expect(rect == CGRect(x: 120, y: 560, width: 320, height: 160))
    }

    @Test("Unions screen frames into a virtual desktop bounds")
    func virtualDesktopBoundsUnion() {
        let bounds = CaptureDisplayGeometry.virtualDesktopBounds(
            screenFrames: [
                CGRect(x: 0, y: 0, width: 1440, height: 900),
                CGRect(x: 1440, y: -90, width: 1920, height: 1080),
            ]
        )
        #expect(bounds == CGRect(x: 0, y: -90, width: 3360, height: 1080))
    }

    @Test("Stitches differently scaled display crops into one canvas")
    func stitchMultiDisplaySlices() {
        let left = makeSolidImage(width: 200, height: 100, red: 1, green: 0, blue: 0)!
        let right = makeSolidImage(width: 100, height: 50, red: 0, green: 0, blue: 1)!

        let stitched = MultiDisplayImageStitcher.stitch(
            slices: [
                MultiDisplayCaptureSlice(
                    image: left,
                    originInSelection: .zero,
                    sizeInPoints: CGSize(width: 100, height: 50),
                    scale: 2
                ),
                MultiDisplayCaptureSlice(
                    image: right,
                    originInSelection: CGPoint(x: 100, y: 0),
                    sizeInPoints: CGSize(width: 100, height: 50),
                    scale: 1
                ),
            ],
            selectionSize: CGSize(width: 200, height: 50),
            outputScale: 2
        )

        #expect(stitched?.width == 400)
        #expect(stitched?.height == 100)
    }

    private func makeSolidImage(
        width: Int,
        height: Int,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat
    ) -> CGImage? {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage()
    }
}
