import Foundation

private func capsoUncaughtExceptionHandler(_ exception: NSException) {
    // Always persist crashes — diagnostic toggle only gates verbose tracing.
    let crumbs = CaptureDiagnostics.breadcrumbSummary()
    DiagnosticLogger.append(
        """
        Uncaught NSException
        name=\(exception.name.rawValue)
        reason=\(exception.reason ?? "nil")
        breadcrumbs=\(crumbs)
        callStack=\(exception.callStackSymbols.joined(separator: "\n"))
        """,
        category: "Crash"
    )
    CaptureDiagnostics.markUncleanExit()
}

/// Lightweight capture/session breadcrumbs that survive hard crashes via UserDefaults.
public enum CaptureDiagnostics {
    private static let breadcrumbsKey = "capso.captureBreadcrumbs"
    private static let uncleanKey = "capso.sessionUncleanExit"
    private static let maxBreadcrumbs = 50
    private static let lock = NSLock()

    /// Call once at launch: dump prior unclean session, then mark this session unclean until quit.
    public static func noteLaunch() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: uncleanKey) {
            let crumbs = breadcrumbSummary()
            DiagnosticLogger.append(
                "Previous session did not exit cleanly.\n\(crumbs)",
                category: "Crash"
            )
        }
        defaults.set(true, forKey: uncleanKey)
        breadcrumb("app.launch")
    }

    public static func noteCleanExit() {
        breadcrumb("app.cleanExit")
        UserDefaults.standard.set(false, forKey: uncleanKey)
    }

    public static func markUncleanExit() {
        UserDefaults.standard.set(true, forKey: uncleanKey)
    }

    public static func breadcrumb(_ message: String) {
        lock.lock()
        defer { lock.unlock() }

        let stamp = ISO8601DateFormatter().string(from: Date())
        var items = UserDefaults.standard.stringArray(forKey: breadcrumbsKey) ?? []
        items.append("\(stamp) \(message)")
        if items.count > maxBreadcrumbs {
            items = Array(items.suffix(maxBreadcrumbs))
        }
        UserDefaults.standard.set(items, forKey: breadcrumbsKey)
    }

    public static func breadcrumbSummary() -> String {
        lock.lock()
        defer { lock.unlock() }
        let items = UserDefaults.standard.stringArray(forKey: breadcrumbsKey) ?? []
        return items.isEmpty ? "(none)" : items.joined(separator: "\n")
    }
}

public enum DiagnosticLogger {
    public static let maxLogBytes = 1_000_000

    private static let queue = DispatchQueue(label: "com.awesomemacapps.capso.diagnostic-logger")

    public static var logDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("com.awesomemacapps.capso", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
    }

    public static var logFileURL: URL {
        logDirectory.appendingPathComponent("capso.log")
    }

    public static var diagnosticReportDirectories: [URL] {
        [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true),
            URL(fileURLWithPath: "/Library/Logs/DiagnosticReports", isDirectory: true),
        ]
    }

    public static func installUncaughtExceptionHandler() {
        NSSetUncaughtExceptionHandler(capsoUncaughtExceptionHandler)
    }

    public static func append(
        _ message: String,
        category: String = "App",
        fileURL: URL = DiagnosticLogger.logFileURL
    ) {
        queue.sync {
            let line = "\(timestamp()) [\(category)] \(message)\n"
            write(line, to: fileURL)
        }
    }

    public static func append(
        error: Error,
        context: String,
        category: String = "Error",
        fileURL: URL = DiagnosticLogger.logFileURL
    ) {
        append("\(context): \(error.localizedDescription)", category: category, fileURL: fileURL)
    }

    @discardableResult
    public static func prepareLogFile(at fileURL: URL = DiagnosticLogger.logFileURL) -> URL {
        queue.sync {
            let fm = FileManager.default
            do {
                try fm.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if !fm.fileExists(atPath: fileURL.path) {
                    try Data().write(to: fileURL, options: [.atomic])
                }
            } catch {
                // Diagnostic helpers must never affect app behavior.
            }
            return fileURL
        }
    }

    public static func recentCrashReportURLs(limit: Int = 10) -> [URL] {
        let fm = FileManager.default
        let matches = diagnosticReportDirectories.flatMap { directory -> [URL] in
            guard let urls = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }

            return urls.filter { url in
                let name = url.lastPathComponent.lowercased()
                let ext = url.pathExtension.lowercased()
                return (name.contains("capso") || name.contains("com.awesomemacapps.capso"))
                    && ["crash", "ips", "diag"].contains(ext)
            }
        }

        return matches.sorted { lhs, rhs in
            modificationDate(lhs) > modificationDate(rhs)
        }
        .prefix(limit)
        .map { $0 }
    }

    /// Reads the current Capso log file (tail-trimmed when very large).
    public static func readLogContents(maxBytes: Int = 512_000) -> String {
        prepareLogFile()
        let url = logFileURL
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return String(localized: "(Log file is empty or unavailable.)")
        }
        defer { try? handle.close() }

        do {
            let size = try handle.seekToEnd()
            if size == 0 {
                return String(localized: "(Log file is empty.)")
            }
            let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
            try handle.seek(toOffset: start)
            guard let data = try handle.readToEnd(), !data.isEmpty else {
                return String(localized: "(Log file is empty.)")
            }
            var text = String(decoding: data, as: UTF8.self)
            if start > 0 {
                text = "…\n" + text
            }
            return text
        } catch {
            return String(localized: "(Failed to read log file.)")
        }
    }

    /// Builds a diagnostics export folder containing Capso logs, breadcrumbs,
    /// and recent macOS crash reports, then zips it to `destinationZIP`.
    /// - Returns: The ZIP URL on success.
    @discardableResult
    public static func exportCrashLogPackage(to destinationZIP: URL) throws -> URL {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("Capso-Diagnostics-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }

        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        let logURL = prepareLogFile()
        let stagedLog = staging.appendingPathComponent("capso.log")
        if fm.fileExists(atPath: logURL.path) {
            try fm.copyItem(at: logURL, to: stagedLog)
        } else {
            try Data().write(to: stagedLog)
        }

        let rotated = logURL.deletingPathExtension()
            .appendingPathExtension("old")
            .appendingPathExtension(logURL.pathExtension)
        if fm.fileExists(atPath: rotated.path) {
            try? fm.copyItem(
                at: rotated,
                to: staging.appendingPathComponent("capso.old.log")
            )
        }

        let breadcrumbURL = staging.appendingPathComponent("breadcrumbs.txt")
        try CaptureDiagnostics.breadcrumbSummary().write(
            to: breadcrumbURL,
            atomically: true,
            encoding: .utf8
        )

        let crashDir = staging.appendingPathComponent("CrashReports", isDirectory: true)
        try fm.createDirectory(at: crashDir, withIntermediateDirectories: true)
        let crashReports = recentCrashReportURLs(limit: 15)
        for report in crashReports {
            let dest = crashDir.appendingPathComponent(report.lastPathComponent)
            try? fm.copyItem(at: report, to: dest)
        }

        let readme = """
        Capso diagnostics export
        Generated: \(ISO8601DateFormatter().string(from: Date()))
        App Support logs: \(logDirectory.path)
        Crash reports included: \(crashReports.count)
        """
        try readme.write(
            to: staging.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )

        if fm.fileExists(atPath: destinationZIP.path) {
            try fm.removeItem(at: destinationZIP)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", staging.path, destinationZIP.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, fm.fileExists(atPath: destinationZIP.path) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return destinationZIP
    }

    private static func write(_ line: String, to fileURL: URL) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            rotateIfNeeded(fileURL: fileURL)
            let data = Data(line.utf8)
            if fm.fileExists(atPath: fileURL.path),
               let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: fileURL, options: [.atomic])
            }
        } catch {
            // Diagnostic logging must never affect app behavior.
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func rotateIfNeeded(fileURL: URL) {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? NSNumber,
              size.intValue > maxLogBytes else {
            return
        }

        let rotated = fileURL.deletingPathExtension()
            .appendingPathExtension("old")
            .appendingPathExtension(fileURL.pathExtension)
        try? fm.removeItem(at: rotated)
        try? fm.moveItem(at: fileURL, to: rotated)
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }
}
