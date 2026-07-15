// App/Sources/History/HistoryView.swift
import SwiftUI
import HistoryKit

struct HistoryView: View {
    let coordinator: HistoryCoordinator

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()

            if coordinator.entries.isEmpty {
                emptyState
            } else {
                GeometryReader { geo in
                    let columnCount = Self.columnCount(for: geo.size.width)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(Self.groupedSections(from: coordinator.entries)) { section in
                                sectionHeader(title: section.title, count: section.entries.count)

                                // Row-based laziness: LazyVGrid nested in LazyVStack
                                // expands every cell in a section, which freezes with
                                // large histories. Emit one lazy row at a time instead.
                                ForEach(section.rows(columnCount: columnCount)) { row in
                                    HStack(alignment: .top, spacing: 12) {
                                        ForEach(row.entries) { entry in
                                            HistoryItemView(entry: entry, coordinator: coordinator)
                                                .frame(maxWidth: .infinity)
                                        }
                                        if row.entries.count < columnCount {
                                            ForEach(0..<(columnCount - row.entries.count), id: \.self) { _ in
                                                Color.clear.frame(maxWidth: .infinity)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }

            Divider()
            statusBar
        }
        .onAppear { coordinator.loadEntries() }
    }

    // MARK: - Grouping

    private struct HistorySection: Identifiable {
        let id: String
        let title: String
        let entries: [HistoryEntry]

        func rows(columnCount: Int) -> [HistoryRow] {
            let columns = max(1, columnCount)
            return stride(from: 0, to: entries.count, by: columns).map { start in
                let end = min(start + columns, entries.count)
                let slice = Array(entries[start..<end])
                return HistoryRow(
                    id: "\(id)-\(start)",
                    entries: slice
                )
            }
        }
    }

    private struct HistoryRow: Identifiable {
        let id: String
        let entries: [HistoryEntry]
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    private static func groupedSections(from entries: [HistoryEntry]) -> [HistorySection] {
        let calendar = Calendar.current
        let now = Date()
        var groups: [String: [HistoryEntry]] = [:]
        var order: [String] = []

        for entry in entries {
            let key: String
            if calendar.isDateInToday(entry.createdAt) {
                key = String(localized: "Today")
            } else if calendar.isDateInYesterday(entry.createdAt) {
                key = String(localized: "Yesterday")
            } else if let daysAgo = calendar.dateComponents([.day], from: entry.createdAt, to: now).day, daysAgo < 7 {
                key = dayFormatter.string(from: entry.createdAt)
            } else {
                key = dateFormatter.string(from: entry.createdAt)
            }

            if groups[key] == nil {
                order.append(key)
            }
            groups[key, default: []].append(entry)
        }

        return order.compactMap { key in
            guard let entries = groups[key] else { return nil }
            return HistorySection(id: key, title: key, entries: entries)
        }
    }

    private static func columnCount(for width: CGFloat) -> Int {
        let contentWidth = max(0, width - 32)
        return max(1, Int(contentWidth / 177))
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 1) {
                filterButton("All", filter: .all, count: coordinator.entryCount(for: .all))
                filterButton("Screenshots", filter: .screenshots, count: coordinator.entryCount(for: .screenshots))
                filterButton("Recordings", filter: .recordings, count: coordinator.entryCount(for: .recordings))
            }
            .padding(2)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer()

            Button {
                coordinator.annotateFromClipboard()
            } label: {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(String(localized: "Annotate image from clipboard"))

            Button {
                coordinator.clearAll()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Clear History")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func filterButton(_ title: LocalizedStringKey, filter: HistoryFilter, count: Int) -> some View {
        Button {
            coordinator.setFilter(filter)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(coordinator.currentFilter == filter ? .secondary : .tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(coordinator.currentFilter == filter ? .white.opacity(0.1) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .foregroundStyle(coordinator.currentFilter == filter ? .primary : .secondary)
    }

    // MARK: - Section

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Rectangle()
                .fill(.quaternary)
                .frame(height: 0.5)

            Text("\(count)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
            Text("No captures yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Your screenshots and recordings will appear here")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Button(String(localized: "Annotate image from clipboard")) {
                coordinator.annotateFromClipboard()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 6) {
            Text("\(coordinator.entries.count) items")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Circle()
                .fill(.tertiary)
                .frame(width: 2.5, height: 2.5)

            Text(formattedSize(coordinator.totalSize))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer()

            let retention = HistoryRetention(rawValue: coordinator.settings.historyRetention) ?? .oneMonth
            Text("Keeping \(retention.label.lowercased())")
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
