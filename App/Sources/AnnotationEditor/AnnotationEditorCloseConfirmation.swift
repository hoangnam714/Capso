import AppKit
import AnnotationKit

enum AnnotationEditorCloseConfirmation {
    /// Returns `true` when the user chose **Cancel** (caller should keep the editor open).
    @MainActor
    static func presentIfNeeded(
        document: AnnotationDocument,
        save: () -> Void,
        discard: () -> Void
    ) -> Bool {
        guard document.canUndo else {
            discard()
            return false
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Save your annotations?")
        alert.informativeText = String(localized: "Your changes will be lost if you don't save.")
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Don't Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            save()
            return false
        case .alertSecondButtonReturn:
            discard()
            return false
        default:
            return true
        }
    }
}
