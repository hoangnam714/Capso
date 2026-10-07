// App/Sources/Shared/StorageErrorHandler.swift
import AppKit
import Foundation
@preconcurrency import UserNotifications

public enum StorageErrorHandler: Sendable {
    public enum SaveContext: Sendable {
        case screenshot
        case recording(String)
        case history
    }

    /// Minimum free space threshold (in bytes) required to safely save (15 MB).
    public static let minimumRequiredBytes: Int64 = 15 * 1024 * 1024

    /// Check if the target volume has enough available space for the specified number of bytes.
    public static func hasEnoughDiskSpace(at url: URL, requiredBytes: Int64 = minimumRequiredBytes) -> Bool {
        let directory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        guard let available = availableDiskSpace(at: directory) else {
            return true
        }
        return available >= requiredBytes
    }

    /// Retrieve available disk space in bytes for a given directory or file URL.
    public static func availableDiskSpace(at url: URL) -> Int64? {
        let directory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        if let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]) {
            if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 {
                return important
            }
            if let available = values.volumeAvailableCapacity, available > 0 {
                return Int64(available)
            }
        }
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: directory.path),
           let freeSize = attrs[.systemFreeSize] as? Int64 {
            return freeSize
        }
        return nil
    }

    /// Determines if an error represents out of disk space.
    public static func isOutOfSpaceError(_ error: Error, at url: URL? = nil) -> Bool {
        // 1. Cocoa error: NSFileWriteOutOfSpaceError = 640
        if let cocoa = error as? CocoaError, cocoa.code == .fileWriteOutOfSpace {
            return true
        }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == CocoaError.fileWriteOutOfSpace.rawValue {
            return true
        }

        // 2. POSIX error: ENOSPC = 28 ("No space left on device"), EDQUOT = 69
        if let posix = error as? POSIXError, posix.code == .ENOSPC || posix.code == .EDQUOT {
            return true
        }
        if ns.domain == NSPOSIXErrorDomain && (ns.code == POSIXError.ENOSPC.rawValue || ns.code == 28 || ns.code == 69) {
            return true
        }

        // 3. Underlying error check
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            if isOutOfSpaceError(underlying, at: url) {
                return true
            }
        }

        // 4. Low space detection
        if let url {
            let directory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
            if let available = availableDiskSpace(at: directory), available < minimumRequiredBytes {
                return true
            }
        }

        // 5. Description heuristics
        let desc = ns.localizedDescription.lowercased()
        if desc.contains("space") || desc.contains("storage") || desc.contains("no space") || desc.contains("dung lượng") {
            return true
        }

        return false
    }

    /// Posts a user notification or alert indicating insufficient storage space or save failure.
    public static func handleSaveFailure(
        error: Error? = nil,
        url: URL? = nil,
        context: SaveContext,
        interactive: Bool = false
    ) {
        let isSpaceIssue: Bool
        if let error {
            isSpaceIssue = isOutOfSpaceError(error, at: url)
        } else if let url {
            isSpaceIssue = !hasEnoughDiskSpace(at: url)
        } else {
            isSpaceIssue = false
        }

        let title: String
        let message: String

        if isSpaceIssue {
            title = String(localized: "Not enough storage space")
            switch context {
            case .screenshot:
                message = String(localized: "Cannot save screenshot because disk storage is full. Please free up disk space and try again.")
            case .recording(let kind):
                message = String(localized: "Cannot save \(kind) because disk storage is full. Please free up disk space and try again.")
            case .history:
                message = String(localized: "Cannot save file because disk storage is full. Please free up disk space and try again.")
            }
        } else {
            title = String(localized: "Save failed")
            let detail = error?.localizedDescription ?? ""
            message = detail.isEmpty
                ? String(localized: "Failed to save file to disk.")
                : String(localized: "Failed to save file: \(detail)")
        }

        postNotification(title: title, body: message)

        if interactive {
            Task { @MainActor in
                showAlert(title: title, message: message)
            }
        }
    }

    /// Post a macOS user notification. Requests authorization on the first call.
    public static func postNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.add(request, withCompletionHandler: nil)
        }
    }

    /// Shows a modal alert on the main actor.
    @MainActor
    public static func showAlert(title: String, message: String, window: NSWindow? = nil) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK"))
        if let window {
            alert.beginSheetModal(for: window)
        } else if let keyWin = NSApp.keyWindow {
            alert.beginSheetModal(for: keyWin)
        } else {
            alert.runModal()
        }
    }
}
