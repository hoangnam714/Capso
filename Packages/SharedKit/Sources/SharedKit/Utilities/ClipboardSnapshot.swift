import AppKit
import CoreGraphics

/// Snapshot of the general pasteboard so a discarded screenshot can restore
/// whatever was on the clipboard before Capso overwrote it.
public struct ClipboardSnapshot: Sendable {
    private let itemPayloads: [[String: Data]]

    public var isEmpty: Bool { itemPayloads.isEmpty }

    public static func capture(from pasteboard: NSPasteboard = .general) -> ClipboardSnapshot {
        let payloads = (pasteboard.pasteboardItems ?? []).compactMap { item -> [String: Data]? in
            var payload: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type), !data.isEmpty {
                    payload[type.rawValue] = data
                }
            }
            return payload.isEmpty ? nil : payload
        }
        return ClipboardSnapshot(itemPayloads: payloads)
    }

    /// Restores prior clipboard contents when available.
    /// If there was nothing to restore, leaves the pasteboard untouched so we
    /// don't invent a fake empty PNG that pollutes clipboard history.
    public func restore(to pasteboard: NSPasteboard = .general) {
        guard !itemPayloads.isEmpty else { return }

        pasteboard.clearContents()
        let items: [NSPasteboardItem] = itemPayloads.map { payload in
            let item = NSPasteboardItem()
            for (type, data) in payload {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
