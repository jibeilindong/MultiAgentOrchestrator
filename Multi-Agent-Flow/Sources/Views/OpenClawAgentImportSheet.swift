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
                Text("勾选要导入到当前项目的 Agents。只有目录和配置都通过校验的项目可导入。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                Button("全选可导入") {
                    selectedIDs = importableIDs
                }
                .disabled(importableIDs.isEmpty)

                Button("清空") {
                    selectedIDs.removeAll()
                }
                .disabled(selectedIDs.isEmpty)

                Spacer(minLength: 0)

                Text("已选 \(selectedImportableCount) / \(importableIDs.count)")
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
                Button("取消") {
                    dismiss()
                }

                Spacer(minLength: 0)

                Button("导入选中项") {
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
                        Text("可导入")
                            .font(.caption2)
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    } else {
                        Text("不可导入")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                if record.issues.isEmpty {
                    Text("目录与 openclaw.json 已完成校验。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(record.issues.joined(separator: " · "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let path = record.directoryPath {
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
