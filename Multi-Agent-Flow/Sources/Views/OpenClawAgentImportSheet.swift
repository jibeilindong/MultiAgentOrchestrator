//
//  OpenClawAgentImportSheet.swift
//  Multi-Agent-Flow
//

import SwiftUI

struct OpenClawAgentImportSheet: View {
    let records: [ProjectOpenClawDetectedAgentRecord]
    let actionTitle: String
    let onImport: (Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<String> = []

    private var importableRecords: [ProjectOpenClawDetectedAgentRecord] {
        records.filter { $0.directoryValidated && $0.configValidated && $0.directoryPath != nil }
    }

    private var importableIDs: Set<String> {
        Set(importableRecords.map(\.id))
    }

    private var selectedImportableCount: Int {
        selectedIDs.intersection(importableIDs).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(actionTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(LocalizedString.text("import_sheet_description"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                Button(LocalizedString.text("select_all_importable")) {
                    selectedIDs = importableIDs
                }
                .disabled(importableIDs.isEmpty)

                Button(LocalizedString.text("clear_selection")) {
                    selectedIDs.removeAll()
                }
                .disabled(selectedIDs.isEmpty)

                Spacer(minLength: 0)

                Text(LocalizedString.format("selected_import_count", selectedImportableCount, importableIDs.count))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(records) { record in
                        agentRow(for: record)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 220)

            HStack {
                Button(LocalizedString.cancel) {
                    dismiss()
                }

                Spacer(minLength: 0)

                Button(LocalizedString.text("import_selected_items")) {
                    onImport(selectedIDs.intersection(importableIDs))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedImportableCount == 0)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 420)
        .onAppear {
            if selectedIDs.isEmpty {
                selectedIDs = importableIDs
            }
        }
    }

    @ViewBuilder
    private func agentRow(for record: ProjectOpenClawDetectedAgentRecord) -> some View {
        let canImport = record.directoryValidated && record.configValidated && record.directoryPath != nil

        HStack(alignment: .top, spacing: 12) {
            Toggle(isOn: Binding(
                get: { selectedIDs.contains(record.id) },
                set: { isOn in
                    if isOn {
                        selectedIDs.insert(record.id)
                    } else {
                        selectedIDs.remove(record.id)
                    }
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .disabled(!canImport)
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(record.name)
                        .font(.headline)
                    if canImport {
                        Text(LocalizedString.text("importable"))
                            .font(.caption2)
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    } else {
                        Text(LocalizedString.text("not_importable"))
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                if record.issues.isEmpty {
                    Text(LocalizedString.text("openclaw_validation_passed"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(record.issues.joined(separator: " · "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let soulPath = record.soulPath {
                    Text(soulPath)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                } else if let path = record.directoryPath {
                    Text(path)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(canImport ? 1.0 : 0.7)
    }
}
