// Packages/AnnotationKit/Sources/AnnotationKit/AnnotationDocument.swift
import Foundation
import CoreGraphics
import Observation

@MainActor
@Observable
public final class AnnotationDocument {
    public private(set) var imageSize: CGSize
    public private(set) var objects: [any AnnotationObject] = []
    public private(set) var selectedObjectID: ObjectID?
    public private(set) var cropRect: CGRect?

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    private struct Snapshot {
        let objects: [any AnnotationObject]
        let cropRect: CGRect?
        let imageSize: CGSize
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public init(imageSize: CGSize) {
        self.imageSize = imageSize
    }

    public func addObject(_ object: any AnnotationObject) {
        pushUndo()
        if let counter = object as? CounterObject {
            let maxNumber = objects.compactMap { ($0 as? CounterObject)?.number }.max() ?? 0
            counter.number = maxNumber + 1
        }
        objects.append(object)
        selectedObjectID = object.id
    }

    public func removeObject(id: ObjectID) {
        pushUndo()
        objects.removeAll { $0.id == id }
        if selectedObjectID == id { selectedObjectID = nil }
        renumberCounters()
    }

    public func removeSelected() {
        guard let id = selectedObjectID else { return }
        removeObject(id: id)
    }

    /// In-memory clipboard for annotation objects (⌘C / ⌘V). Not the system pasteboard.
    private var objectClipboard: (any AnnotationObject)?
    private var pasteCount = 0

    private static let clipboardOffset = CGSize(width: 32, height: 32)

    public var canPasteObject: Bool { objectClipboard != nil }

    /// Copies the selected object into the document clipboard. Returns `false` if nothing is selected.
    @discardableResult
    public func copySelected() -> Bool {
        guard let selected = selectedObject else { return false }
        objectClipboard = selected.copy()
        pasteCount = 0
        return true
    }

    /// Duplicates the selected object with a small offset and selects the duplicate.
    @discardableResult
    public func duplicateSelected() -> Bool {
        guard let selected = selectedObject else { return false }
        let duplicate = selected.copy()
        duplicate.move(by: Self.clipboardOffset)
        addObject(duplicate)
        return true
    }

    /// Pastes the clipboard object with a cascading offset. Returns `false` if the clipboard is empty.
    @discardableResult
    public func pasteClipboard() -> Bool {
        guard let objectClipboard else { return false }
        pasteCount += 1
        let pasted = objectClipboard.copy()
        let offset = CGSize(
            width: Self.clipboardOffset.width * CGFloat(pasteCount),
            height: Self.clipboardOffset.height * CGFloat(pasteCount)
        )
        pasted.move(by: offset)
        addObject(pasted)
        return true
    }

    public func selectObject(id: ObjectID?) {
        selectedObjectID = id
    }

    public func clearSelection() {
        selectedObjectID = nil
    }

    public var selectedObject: (any AnnotationObject)? {
        guard let id = selectedObjectID else { return nil }
        return objects.first { $0.id == id }
    }

    public func objectAt(point: CGPoint, threshold: CGFloat = 8) -> (any AnnotationObject)? {
        for object in objects.reversed() {
            if object.hitTest(point: point, threshold: threshold) {
                return object
            }
        }
        return nil
    }

    public func moveObject(id: ObjectID, by delta: CGSize) {
        guard let obj = objects.first(where: { $0.id == id }) else { return }
        obj.move(by: delta)
    }

    public func beginDrag() {
        pushUndo()
    }

    public func setCropRect(_ rect: CGRect?) {
        pushUndo()
        cropRect = rect
    }

    /// Called after the crop editor replaces the working image (e.g. after
    /// rotate + commit). Updates `imageSize`, clears any stored crop rect
    /// (coordinates are no longer meaningful), and pushes an undo snapshot.
    /// Callers are expected to avoid calling this when `objects` is non-empty
    /// — the annotations' coordinates would be invalidated.
    public func replaceImage(size: CGSize) {
        pushUndo()
        imageSize = size
        cropRect = nil
    }

    /// Updates the backing image size while keeping annotation coordinates meaningful.
    /// Used when the visible canvas grows or shifts around already-created objects.
    public func updateImageSizePreservingObjects(size: CGSize, objectOffset: CGSize = .zero) {
        imageSize = size
        cropRect = nil
        if objectOffset != .zero {
            for object in objects {
                object.move(by: objectOffset)
            }
        }
    }

    private func currentSnapshot() -> Snapshot {
        Snapshot(objects: objects.map { $0.copy() }, cropRect: cropRect, imageSize: imageSize)
    }

    private func apply(_ snapshot: Snapshot) {
        objects = snapshot.objects
        cropRect = snapshot.cropRect
        imageSize = snapshot.imageSize
        selectedObjectID = nil
    }

    private func pushUndo() {
        undoStack.append(currentSnapshot())
        redoStack.removeAll()
    }

    /// Keeps counter badges sequential (1, 2, 3…) in creation order after deletions.
    private func renumberCounters() {
        var nextNumber = 1
        for object in objects {
            guard let counter = object as? CounterObject else { continue }
            counter.number = nextNumber
            nextNumber += 1
        }
    }

    public func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot())
        apply(snapshot)
    }

    public func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot())
        apply(snapshot)
    }
}
