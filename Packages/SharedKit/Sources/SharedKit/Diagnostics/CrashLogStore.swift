import Foundation

/// A single crash / unclean-exit record shown in Settings → Crash Log.
public struct CrashLogEntry: Identifiable, Hashable, Sendable {
    public enum Source: String, Sendable {
        case ips
        case crash
        case capsoLog
    }

    public let id: String
    public let date: Date
    public let title: String
    public let summary: String
    public let detail: String
    public let source: Source
    public let fileURL: URL?

    public init(
        id: String,
        date: Date,
        title: String,
        summary: String,
        detail: String,
        source: Source,
        fileURL: URL? = nil
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.summary = summary
        self.detail = detail
        self.source = source
        self.fileURL = fileURL
    }
}

public enum CrashLogStore {
    /// Newest-first crash list from macOS DiagnosticReports + Capso log.
    public static func loadEntries(limit: Int = 40) -> [CrashLogEntry] {
        var entries: [CrashLogEntry] = []
        entries.append(contentsOf: loadSystemCrashReports(limit: limit))
        entries.append(contentsOf: loadCapsoLogCrashEntries())
        return entries
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { $0 }
    }

    private static func loadSystemCrashReports(limit: Int) -> [CrashLogEntry] {
        DiagnosticLogger.recentCrashReportURLs(limit: limit).compactMap { url in
            parseSystemReport(at: url)
        }
    }

    private static func parseSystemReport(at url: URL) -> CrashLogEntry? {
        let ext = url.pathExtension.lowercased()
        let data = try? Data(contentsOf: url)
        let text = data.flatMap { String(data: $0, encoding: .utf8) }
            ?? data.flatMap { String(data: $0, encoding: .isoLatin1) }
            ?? ""

        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
            ?? Date.distantPast

        if ext == "ips", let parsed = parseIPS(text: text, url: url, fallbackDate: date) {
            return parsed
        }

        if !text.isEmpty {
            let title = parseLegacyCrashTitle(from: text) ?? url.deletingPathExtension().lastPathComponent
            let summary = parseLegacyCrashSummary(from: text) ?? String(localized: "macOS crash report")
            return CrashLogEntry(
                id: url.path,
                date: date,
                title: title,
                summary: summary,
                detail: text,
                source: ext == "ips" ? .ips : .crash,
                fileURL: url
            )
        }

        return CrashLogEntry(
            id: url.path,
            date: date,
            title: url.lastPathComponent,
            summary: String(localized: "Unable to read crash report"),
            detail: String(localized: "Could not decode \(url.lastPathComponent)"),
            source: ext == "ips" ? .ips : .crash,
            fileURL: url
        )
    }

    private static func parseIPS(text: String, url: URL, fallbackDate: Date) -> CrashLogEntry? {
        // .ips files often start with a one-line JSON header, then the full report JSON.
        let payloads = ipsJSONPayloads(from: text)
        var exceptionType = "Crash"
        var exceptionSignal = ""
        var terminationReason = ""
        var parsedDate = fallbackDate
        var detail = text

        for payload in payloads {
            if let timestamp = payload["timestamp"] as? String,
               let date = parseIPSDate(timestamp) {
                parsedDate = date
            }
            if let exception = payload["exception"] as? [String: Any] {
                if let type = exception["type"] as? String { exceptionType = type }
                if let signal = exception["signal"] as? String { exceptionSignal = signal }
            }
            if let termination = payload["termination"] as? [String: Any] {
                if let indicator = termination["indicator"] as? String {
                    terminationReason = indicator
                } else if let namespace = termination["namespace"] as? String {
                    terminationReason = namespace
                }
            }
            if let pretty = prettyJSON(payload) {
                detail = pretty
            }
        }

        let titleParts = [exceptionType, exceptionSignal].filter { !$0.isEmpty }
        let title = titleParts.isEmpty ? url.deletingPathExtension().lastPathComponent : titleParts.joined(separator: " / ")
        let summary = terminationReason.isEmpty
            ? String(localized: "System crash report")
            : terminationReason

        return CrashLogEntry(
            id: url.path,
            date: parsedDate,
            title: title,
            summary: summary,
            detail: detail.isEmpty ? text : detail,
            source: .ips,
            fileURL: url
        )
    }

    private static func ipsJSONPayloads(from text: String) -> [[String: Any]] {
        var payloads: [[String: Any]] = []
        // Try whole file first.
        if let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let dict = object as? [String: Any] {
            payloads.append(dict)
            return payloads
        }

        // Split concatenated JSON objects (common for .ips).
        var depth = 0
        var start: String.Index?
        for index in text.indices {
            let ch = text[index]
            if ch == "{" {
                if depth == 0 { start = index }
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0, let start {
                    let slice = String(text[start...index])
                    if let data = slice.data(using: .utf8),
                       let object = try? JSONSerialization.jsonObject(with: data),
                       let dict = object as? [String: Any] {
                        payloads.append(dict)
                    }
                }
            }
        }
        return payloads
    }

    private static func parseIPSDate(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS Z"
        return formatter.date(from: value)
    }

    private static func prettyJSON(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    private static func parseLegacyCrashTitle(from text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline).prefix(40) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Exception Type:") {
                return trimmed.replacingOccurrences(of: "Exception Type:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func parseLegacyCrashSummary(from text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline).prefix(60) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Termination Reason:") || trimmed.hasPrefix("Exception Codes:") {
                return trimmed
            }
        }
        return nil
    }

    private static func loadCapsoLogCrashEntries() -> [CrashLogEntry] {
        let contents = DiagnosticLogger.readLogContents(maxBytes: 1_000_000)
        guard contents.contains("[Crash]") else { return [] }

        var entries: [CrashLogEntry] = []
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < lines.count {
            let line = lines[index]
            guard line.contains("[Crash]") else {
                index += 1
                continue
            }

            let date = parseCapsoLogDate(from: line) ?? Date.distantPast
            var block = [line]
            index += 1
            while index < lines.count {
                let next = lines[index]
                // Next timestamped log line ends the crash block.
                if next.range(of: #"^\d{4}-\d{2}-\d{2}T"#, options: .regularExpression) != nil,
                   next.contains("[") {
                    break
                }
                block.append(next)
                index += 1
            }

            let detail = block.joined(separator: "\n")
            let reason = block
                .first { $0.contains("reason=") }
                .map { $0.replacingOccurrences(of: "reason=", with: "").trimmingCharacters(in: .whitespaces) }
            let name = block
                .first { $0.contains("name=") }
                .map { $0.replacingOccurrences(of: "name=", with: "").trimmingCharacters(in: .whitespaces) }

            let title = name?.isEmpty == false ? (name ?? "Capso crash") : "Capso crash"
            let summary = reason?.isEmpty == false
                ? (reason ?? String(localized: "Logged by Capso"))
                : (detail.contains("did not exit cleanly")
                   ? String(localized: "Previous session did not exit cleanly")
                   : String(localized: "Logged by Capso"))

            entries.append(
                CrashLogEntry(
                    id: "capso-log-\(date.timeIntervalSince1970)-\(entries.count)",
                    date: date,
                    title: title,
                    summary: summary,
                    detail: detail,
                    source: .capsoLog,
                    fileURL: DiagnosticLogger.logFileURL
                )
            )
        }
        return entries
    }

    private static func parseCapsoLogDate(from line: String) -> Date? {
        guard let space = line.firstIndex(of: " ") else { return nil }
        let stamp = String(line[..<space])
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: stamp) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: stamp)
    }
}
