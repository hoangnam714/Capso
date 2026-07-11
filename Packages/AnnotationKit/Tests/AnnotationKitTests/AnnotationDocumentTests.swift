// Packages/AnnotationKit/Tests/AnnotationKitTests/AnnotationDocumentTests.swift
import Testing
import Foundation
import CoreGraphics
@testable import AnnotationKit

@Suite("AnnotationDocument")
struct AnnotationDocumentTests {
    @Test("Add and remove objects")
    @MainActor
    func addRemove() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let arrow = ArrowObject(start: .zero, end: CGPoint(x: 100, y: 100))
        doc.addObject(arrow)
        #expect(doc.objects.count == 1)
        doc.removeObject(id: arrow.id)
        #expect(doc.objects.count == 0)
    }

    @Test("Undo and redo add")
    @MainActor
    func undoRedo() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let arrow = ArrowObject(start: .zero, end: CGPoint(x: 100, y: 100))
        doc.addObject(arrow)
        #expect(doc.objects.count == 1)
        #expect(doc.canUndo)

        doc.undo()
        #expect(doc.objects.count == 0)
        #expect(doc.canRedo)

        doc.redo()
        #expect(doc.objects.count == 1)
    }

    @Test("Selection")
    @MainActor
    func selection() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let arrow = ArrowObject(start: .zero, end: CGPoint(x: 100, y: 100))
        doc.addObject(arrow)
        doc.selectObject(id: arrow.id)
        #expect(doc.selectedObjectID == arrow.id)
        doc.clearSelection()
        #expect(doc.selectedObjectID == nil)
    }

    @Test("cropRect starts nil")
    @MainActor
    func cropRectDefaultNil() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        #expect(doc.cropRect == nil)
    }

    @Test("setCropRect updates value and pushes undo")
    @MainActor
    func setCropRectUndo() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let rect = CGRect(x: 100, y: 50, width: 400, height: 300)
        doc.setCropRect(rect)
        #expect(doc.cropRect == rect)
        #expect(doc.canUndo)

        doc.undo()
        #expect(doc.cropRect == nil)
        #expect(doc.canRedo)

        doc.redo()
        #expect(doc.cropRect == rect)
    }

    @Test("setCropRect with nil clears the crop")
    @MainActor
    func clearCropRect() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        doc.setCropRect(CGRect(x: 0, y: 0, width: 100, height: 100))
        doc.setCropRect(nil)
        #expect(doc.cropRect == nil)
    }

    @Test("undo restores objects AND cropRect together")
    @MainActor
    func undoRestoresBothObjectsAndCrop() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let arrow = ArrowObject(start: .zero, end: CGPoint(x: 50, y: 50))
        doc.addObject(arrow)
        doc.setCropRect(CGRect(x: 10, y: 10, width: 100, height: 100))

        #expect(doc.objects.count == 1)
        #expect(doc.cropRect != nil)

        doc.undo()
        #expect(doc.objects.count == 1)
        #expect(doc.cropRect == nil)

        doc.undo()
        #expect(doc.objects.count == 0)
        #expect(doc.cropRect == nil)
    }

    @Test("Update image size preserves and offsets objects without pushing undo")
    @MainActor
    func updateImageSizePreservesObjects() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 400, height: 300))
        let line = LineObject(start: CGPoint(x: 20, y: 30), end: CGPoint(x: 120, y: 30))
        doc.addObject(line)
        doc.setCropRect(CGRect(x: 5, y: 5, width: 50, height: 50))
        doc.undo()
        #expect(doc.canUndo)

        doc.updateImageSizePreservingObjects(
            size: CGSize(width: 520, height: 380),
            objectOffset: CGSize(width: 15, height: 25)
        )

        #expect(doc.imageSize == CGSize(width: 520, height: 380))
        #expect(doc.cropRect == nil)
        let movedLine = doc.objects[0] as? LineObject
        #expect(movedLine?.start == CGPoint(x: 35, y: 55))
        #expect(movedLine?.end == CGPoint(x: 135, y: 55))

        doc.undo()
        #expect(doc.objects.count == 0)
    }

    @Test("Deleting a counter renumbers remaining counters")
    @MainActor
    func counterRenumberOnDelete() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let c1 = CounterObject(center: CGPoint(x: 10, y: 10), number: 1)
        let c2 = CounterObject(center: CGPoint(x: 20, y: 20), number: 2)
        let c3 = CounterObject(center: CGPoint(x: 30, y: 30), number: 3)
        doc.addObject(c1)
        doc.addObject(c2)
        doc.addObject(c3)

        doc.removeObject(id: c2.id)

        let numbers = doc.objects.compactMap { ($0 as? CounterObject)?.number }
        #expect(numbers == [1, 2])
    }

    @Test("Copy selected stores a clipboard object")
    @MainActor
    func copySelected() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let arrow = ArrowObject(start: .zero, end: CGPoint(x: 100, y: 100))
        doc.addObject(arrow)
        doc.selectObject(id: arrow.id)

        #expect(doc.copySelected())
        #expect(doc.canPasteObject)
        #expect(doc.objects.count == 1)
    }

    @Test("Duplicate selected adds offset copy and selects it")
    @MainActor
    func duplicateSelected() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let rect = RectangleObject(rect: CGRect(x: 10, y: 20, width: 40, height: 30))
        doc.addObject(rect)
        doc.selectObject(id: rect.id)

        #expect(doc.duplicateSelected())
        #expect(doc.objects.count == 2)
        #expect(doc.selectedObjectID != rect.id)

        let duplicate = doc.objects[1] as? RectangleObject
        #expect(duplicate?.rect.origin == CGPoint(x: 42, y: 52))
        #expect(duplicate?.id != rect.id)
    }

    @Test("Paste clipboard cascades offset")
    @MainActor
    func pasteClipboardCascadesOffset() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let line = LineObject(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 50, y: 0))
        doc.addObject(line)
        doc.selectObject(id: line.id)
        #expect(doc.copySelected())

        #expect(doc.pasteClipboard())
        #expect(doc.pasteClipboard())
        #expect(doc.objects.count == 3)

        let firstPaste = doc.objects[1] as? LineObject
        let secondPaste = doc.objects[2] as? LineObject
        #expect(firstPaste?.start == CGPoint(x: 32, y: 32))
        #expect(secondPaste?.start == CGPoint(x: 64, y: 64))
    }

    @Test("Copy and paste with no selection or empty clipboard returns false")
    @MainActor
    func clipboardGuards() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        #expect(!doc.copySelected())
        #expect(!doc.duplicateSelected())
        #expect(!doc.pasteClipboard())
        #expect(!doc.canPasteObject)
    }

    @Test("Undo counter delete restores original numbers")
    @MainActor
    func counterRenumberUndo() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let c1 = CounterObject(center: CGPoint(x: 10, y: 10), number: 1)
        let c2 = CounterObject(center: CGPoint(x: 20, y: 20), number: 2)
        let c3 = CounterObject(center: CGPoint(x: 30, y: 30), number: 3)
        doc.addObject(c1)
        doc.addObject(c2)
        doc.addObject(c3)

        doc.removeObject(id: c2.id)
        #expect(doc.objects.compactMap { ($0 as? CounterObject)?.number } == [1, 2])

        doc.undo()
        #expect(doc.objects.count == 3)
        #expect(doc.objects.compactMap { ($0 as? CounterObject)?.number } == [1, 2, 3])
    }
}
