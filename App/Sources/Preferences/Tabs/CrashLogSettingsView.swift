import AppKit
import SwiftUI
import SharedKit
import UniformTypeIdentifiers

struct CrashLogSettingsView: View {
    @State private var entries: [CrashLogEntry] = []
    @State private var selectedID: CrashLogEntry.ID?
    @State private var exportMessage: String?

    private var selectedEntry: CrashLogEntry? {
        entries.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Crash Log")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button("Refresh") { reload() }
                    .controlSize(.small)
                Button("Export…") { exportSelectedOrAll() }
                    .controlSize(.small)
                    .disabled(entries.isEmpty)
            }

            Text("Newest crashes first. Select a row to inspect the reason and stack details.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if entries.isEmpty {
                emptyState
            } else {
                HStack(alignment: .top, spacing: 12) {
                    crashList
                        .frame(width: 220)
                    detailPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(minHeight: 340)
            }
        }
        .onAppear(perform: reload)
        .alert(
            "Export",
            isPresented: Binding(
                get: { exportMessage != nil },
                set: { if !$0 { exportMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { exportMessage = nil }
        } message: {
            Text(exportMessage ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            Text("No crash reports found")
                .font(.system(size: 14, weight: .semibold))
            Text("When Capso crashes, reports appear here automatically.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var crashList: some View {
        List(selection: $selectedID) {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                    Text(entry.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(formattedDate(entry.date))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Text(sourceLabel(entry.source))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
                .tag(entry.id)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let entry = selectedEntry {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                            .font(.system(size: 15, weight: .semibold))
                        Text(entry.summary)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text(formattedDate(entry.date))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if entry.fileURL != nil {
                        Button("Show in Finder") {
                            reveal(entry)
                        }
                        .controlSize(.small)
                    }
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.detail, forType: .string)
                    }
                    .controlSize(.small)
                }

                ScrollView {
                    Text(entry.detail)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
            } else {
                Text("Select a crash to see details")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func reload() {
        entries = CrashLogStore.loadEntries()
        if selectedID == nil || !entries.contains(where: { $0.id == selectedID }) {
            selectedID = entries.first?.id
        }
    }

    private func reveal(_ entry: CrashLogEntry) {
        guard let url = entry.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func exportSelectedOrAll() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.zip]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        panel.nameFieldStringValue = "Capso-CrashLog-\(formatter.string(from: Date())).zip"
        panel.title = String(localized: "Export Crash Log")

        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            _ = try DiagnosticLogger.exportCrashLogPackage(to: destination)
            exportMessage = String(localized: "Exported to \(destination.lastPathComponent)")
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            exportMessage = String(localized: "Export failed: \(error.localizedDescription)")
        }
    }

    private func formattedDate(_ date: Date) -> String {
        if date == .distantPast { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func sourceLabel(_ source: CrashLogEntry.Source) -> String {
        switch source {
        case .ips: return "IPS"
        case .crash: return "CRASH"
        case .capsoLog: return "CAPSO"
        }
    }
}
