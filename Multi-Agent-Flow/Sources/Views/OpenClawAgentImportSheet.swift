//
//  OpenClawAgentImportSheet.swift
//  Multi-Agent-Flow
//

import SwiftUI

private struct OpenClawAgentImportDraft: Hashable {
    let recordID: String
    let resolution: AgentImportNameResolution
    var selectedOptionID: String
    var customFunctionDescription: String

    init(recordID: String, resolution: AgentImportNameResolution) {
        self.recordID = recordID
        self.resolution = resolution
        if resolution.requiresCustomFunctionDescription {
            self.selectedOptionID = AgentImportNamingService.manualOptionID
        } else if let recommendedTemplateID = resolution.recommendedTemplateID,
                  let recommendedOption = resolution.options.first(where: { $0.templateID == recommendedTemplateID }) {
            self.selectedOptionID = recommendedOption.id
        } else if let firstOption = resolution.options.first {
            self.selectedOptionID = firstOption.id
        } else {
            self.selectedOptionID = AgentImportNamingService.manualOptionID
        }
        self.customFunctionDescription = ""
    }

    var usesManualFunctionDescription: Bool {
        selectedOptionID == AgentImportNamingService.manualOptionID
    }

    func selectedOption() -> AgentImportFunctionDescriptionOption? {
        resolution.options.first { $0.id == selectedOptionID }
    }

    func resolvedFunctionDescription() -> String {
        if usesManualFunctionDescription {
            return customFunctionDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return selectedOption()?.label.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func resolvedTemplateID() -> String? {
        usesManualFunctionDescription ? nil : selectedOption()?.templateID
    }

    func isValidSelection() -> Bool {
        !resolvedFunctionDescription().isEmpty
    }

    func toSelection() -> AgentImportSelection? {
        let functionDescription = resolvedFunctionDescription()
        guard !functionDescription.isEmpty else { return nil }
        return AgentImportSelection(
            recordID: recordID,
            functionDescription: functionDescription,
            selectedTemplateID: resolvedTemplateID()
        )
    }
}

struct OpenClawAgentImportSheet: View {
    let records: [ProjectOpenClawDetectedAgentRecord]
    let actionTitle: String
    let onImport: ([AgentImportSelection]) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var templateLibrary = AgentTemplateLibraryStore.shared
    @State private var selectedIDs: Set<String> = []
    @State private var draftsByRecordID: [String: OpenClawAgentImportDraft] = [:]

    private var importableRecords: [ProjectOpenClawDetectedAgentRecord] {
        records.filter { $0.directoryValidated && $0.configValidated && $0.directoryPath != nil }
    }

    private var importableIDs: Set<String> {
        Set(importableRecords.map(\.id))
    }

    private var selectedImportableRecords: [ProjectOpenClawDetectedAgentRecord] {
        importableRecords.filter { selectedIDs.contains($0.id) }
    }

    private var selectedImportableCount: Int {
        selectedImportableRecords.count
    }

    private var hasInvalidSelections: Bool {
        selectedImportableRecords.contains { record in
            guard let draft = draftsByRecordID[record.id] else { return true }
            return !draft.isValidSelection()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(actionTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("导入时会强制把 agent 重命名为“功能描述-任务领域-数字”。系统会优先根据 SOUL.md 匹配模板；只有模板明显不合适时，才需要手动填写功能描述。")
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
            .frame(minHeight: 280)

            if hasInvalidSelections {
                Text("仍有已选 agent 缺少功能描述。请从模板候选中选择，或在“手动命名”里填写后再导入。")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            HStack {
                Button(LocalizedString.cancel) {
                    dismiss()
                }

                Spacer(minLength: 0)

                Button(LocalizedString.text("import_selected_items")) {
                    let selections = selectedImportableRecords.compactMap { record in
                        draftsByRecordID[record.id]?.toSelection()
                    }
                    onImport(selections)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedImportableCount == 0 || hasInvalidSelections)
            }
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            if selectedIDs.isEmpty {
                selectedIDs = importableIDs
            }
            synchronizeDrafts()
        }
    }

    @ViewBuilder
    private func agentRow(for record: ProjectOpenClawDetectedAgentRecord) -> some View {
        let canImport = record.directoryValidated && record.configValidated && record.directoryPath != nil
        let draft = draftsByRecordID[record.id]

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

            VStack(alignment: .leading, spacing: 8) {
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

                    if let draft {
                        Text(confidenceLabel(for: draft.resolution.confidence))
                            .font(.caption2)
                            .foregroundColor(confidenceColor(for: draft.resolution.confidence))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(confidenceColor(for: draft.resolution.confidence).opacity(0.12))
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

                if let draft, canImport {
                    importDecisionSection(for: draft, recordID: record.id)
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

    @ViewBuilder
    private func importDecisionSection(for draft: OpenClawAgentImportDraft, recordID: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if draft.resolution.requiresCustomFunctionDescription {
                Text("未找到足够贴合的模板。请优先检查候选项；如果都不合适，再手动填写功能描述。")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else if let recommended = draft.resolution.recommendedFunctionDescription, !recommended.isEmpty {
                Text("SOUL 推荐功能描述：\(recommended)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Picker("功能描述", selection: binding(for: recordID, keyPath: \.selectedOptionID)) {
                ForEach(draft.resolution.options) { option in
                    Text(optionLabel(option)).tag(option.id)
                }
                Text("手动命名").tag(AgentImportNamingService.manualOptionID)
            }
            .pickerStyle(.menu)
            .labelsHidden()

            if draft.usesManualFunctionDescription {
                TextField("仅当模板明显不合适时填写功能描述", text: binding(for: recordID, keyPath: \.customFunctionDescription))
                    .textFieldStyle(.roundedBorder)
            }

            if !draft.resolution.reasons.isEmpty {
                Text("识别依据：\(draft.resolution.reasons.joined(separator: " · "))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text("导入后名称：\(previewName(for: draft))")
                .font(.caption2)
                .foregroundColor(draft.isValidSelection() ? .secondary : .orange)
        }
    }

    private func optionLabel(_ option: AgentImportFunctionDescriptionOption) -> String {
        switch option.source {
        case .template:
            return "\(option.label)（模板）"
        case .custom:
            return "\(option.label)（已保存自定义）"
        case .existingName:
            return "\(option.label)（原始名称提取）"
        }
    }

    private func previewName(for draft: OpenClawAgentImportDraft) -> String {
        let functionDescription = draft.resolvedFunctionDescription()
        let preview = functionDescription.isEmpty ? "功能描述" : functionDescription
        return "\(preview)-任务领域-1"
    }

    private func confidenceLabel(for confidence: AgentImportNameResolution.Confidence) -> String {
        switch confidence {
        case .high:
            return "高匹配"
        case .medium:
            return "可复核"
        case .low:
            return "需确认"
        }
    }

    private func confidenceColor(for confidence: AgentImportNameResolution.Confidence) -> Color {
        switch confidence {
        case .high:
            return .green
        case .medium:
            return .blue
        case .low:
            return .orange
        }
    }

    private func synchronizeDrafts() {
        var nextDrafts: [String: OpenClawAgentImportDraft] = draftsByRecordID

        for record in importableRecords {
            if nextDrafts[record.id] == nil {
                let resolution = AgentImportNamingService.resolveOpenClawRecord(
                    record,
                    templates: templateLibrary.templates,
                    customFunctionDescriptions: templateLibrary.customFunctionDescriptions
                )
                nextDrafts[record.id] = OpenClawAgentImportDraft(recordID: record.id, resolution: resolution)
            }
        }

        let validRecordIDs = Set(importableRecords.map(\.id))
        nextDrafts = nextDrafts.filter { validRecordIDs.contains($0.key) }
        draftsByRecordID = nextDrafts
    }

    private func binding<Value>(
        for recordID: String,
        keyPath: WritableKeyPath<OpenClawAgentImportDraft, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                draftsByRecordID[recordID]?[keyPath: keyPath]
                    ?? OpenClawAgentImportDraft(
                        recordID: recordID,
                        resolution: AgentImportNameResolution(
                            recommendedTemplateID: nil,
                            recommendedFunctionDescription: nil,
                            options: [],
                            confidence: .low,
                            reasons: []
                        )
                    )[keyPath: keyPath]
            },
            set: { newValue in
                guard var draft = draftsByRecordID[recordID] else { return }
                draft[keyPath: keyPath] = newValue
                draftsByRecordID[recordID] = draft
            }
        )
    }
}
