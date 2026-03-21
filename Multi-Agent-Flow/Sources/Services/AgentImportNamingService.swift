//
//  AgentImportNamingService.swift
//  Multi-Agent-Flow
//

import Foundation

struct AgentImportSelection: Identifiable, Hashable {
    let recordID: String
    let functionDescription: String
    let selectedTemplateID: String?

    var id: String { recordID }
}

struct AgentImportFunctionDescriptionOption: Identifiable, Hashable {
    enum Source: Hashable {
        case template
        case custom
        case existingName
    }

    let id: String
    let label: String
    let source: Source
    let templateID: String?

    static func template(_ template: AgentTemplate) -> AgentImportFunctionDescriptionOption {
        AgentImportFunctionDescriptionOption(
            id: "template:\(template.id)",
            label: template.name.trimmingCharacters(in: .whitespacesAndNewlines),
            source: .template,
            templateID: template.id
        )
    }

    static func custom(_ label: String) -> AgentImportFunctionDescriptionOption {
        let sanitized = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return AgentImportFunctionDescriptionOption(
            id: "custom:\(sanitized.lowercased())",
            label: sanitized,
            source: .custom,
            templateID: nil
        )
    }

    static func existing(_ label: String) -> AgentImportFunctionDescriptionOption {
        let sanitized = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return AgentImportFunctionDescriptionOption(
            id: "existing:\(sanitized.lowercased())",
            label: sanitized,
            source: .existingName,
            templateID: nil
        )
    }
}

struct AgentImportNameResolution: Hashable {
    enum Confidence: String, Hashable {
        case high
        case medium
        case low

        var requiresManualDecision: Bool {
            self == .low
        }
    }

    let recommendedTemplateID: String?
    let recommendedFunctionDescription: String?
    let options: [AgentImportFunctionDescriptionOption]
    let confidence: Confidence
    let reasons: [String]

    var requiresCustomFunctionDescription: Bool {
        confidence.requiresManualDecision
    }
}

private struct AgentImportTemplateRecommendation {
    let template: AgentTemplate
    let score: Int
    let reasons: [String]
}

enum AgentImportNamingService {
    static let manualOptionID = "__manual_function_description__"

    static func resolveOpenClawRecord(
        _ record: ProjectOpenClawDetectedAgentRecord,
        templates: [AgentTemplate] = AgentTemplateLibraryStore.shared.templates,
        customFunctionDescriptions: [String] = AgentTemplateLibraryStore.shared.customFunctionDescriptions
    ) -> AgentImportNameResolution {
        let soulMD = loadSoulMarkdown(for: record) ?? ""
        return resolve(
            rawName: record.name,
            soulMD: soulMD,
            capabilities: [],
            templates: templates,
            customFunctionDescriptions: customFunctionDescriptions
        )
    }

    static func resolveImportedAgent(
        rawName: String,
        soulMD: String,
        capabilities: [String],
        templates: [AgentTemplate] = AgentTemplateLibraryStore.shared.templates,
        customFunctionDescriptions: [String] = AgentTemplateLibraryStore.shared.customFunctionDescriptions
    ) -> AgentImportNameResolution {
        resolve(
            rawName: rawName,
            soulMD: soulMD,
            capabilities: capabilities,
            templates: templates,
            customFunctionDescriptions: customFunctionDescriptions
        )
    }

    static func fallbackFunctionDescription(from rawName: String) -> String {
        let normalized = normalizeSegment(rawName)
        guard !normalized.isEmpty else { return "功能描述" }

        let parts = normalized
            .split(separator: "-", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return "功能描述" }

        if parts.count >= 3, Int(parts[parts.count - 1]) != nil {
            let value = parts.dropLast(2).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? "功能描述" : value
        }

        if parts.count >= 2 {
            let value = parts.dropLast().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? parts[0] : value
        }

        return normalized
    }

    static func loadSoulMarkdown(for record: ProjectOpenClawDetectedAgentRecord) -> String? {
        if let soulPath = nonEmptyPath(record.soulPath),
           let content = try? String(contentsOf: URL(fileURLWithPath: soulPath, isDirectory: false), encoding: .utf8),
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return content
        }

        guard let directoryPath = nonEmptyPath(record.directoryPath) else { return nil }
        let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
        guard let soulURL = existingOpenClawSoulURL(in: directoryURL, maxAncestorDepth: 0) else { return nil }
        return try? String(contentsOf: soulURL, encoding: .utf8)
    }

    private static func resolve(
        rawName: String,
        soulMD: String,
        capabilities: [String],
        templates: [AgentTemplate],
        customFunctionDescriptions: [String]
    ) -> AgentImportNameResolution {
        let context = makeSearchContext(rawName: rawName, soulMD: soulMD, capabilities: capabilities)
        let recommendations = templates
            .compactMap { recommendation(for: $0, context: context, rawName: rawName, soulMD: soulMD) }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.template.name.localizedCaseInsensitiveCompare(rhs.template.name) == .orderedAscending
                }
                return lhs.score > rhs.score
            }

        let topRecommendations = Array(recommendations.prefix(3))
        let confidence = classifyConfidence(recommendations: topRecommendations)
        let recommendedTemplate = topRecommendations.first?.template
        let fallbackDescription = fallbackFunctionDescription(from: rawName)

        var options: [AgentImportFunctionDescriptionOption] = []
        var seenOptionIDs = Set<String>()

        func appendOption(_ option: AgentImportFunctionDescriptionOption) {
            guard !option.label.isEmpty else { return }
            guard seenOptionIDs.insert(option.id).inserted else { return }
            options.append(option)
        }

        for recommendation in topRecommendations {
            appendOption(.template(recommendation.template))
        }

        let existingNameOption = AgentImportFunctionDescriptionOption.existing(fallbackDescription)
        if existingNameOption.label.localizedCaseInsensitiveCompare("功能描述") != .orderedSame {
            appendOption(existingNameOption)
        }

        for description in customFunctionDescriptions {
            appendOption(.custom(description))
        }

        let recommendedFunctionDescription = recommendedTemplate?.name ?? fallbackDescription
        let reasons = topRecommendations.first?.reasons ?? []

        return AgentImportNameResolution(
            recommendedTemplateID: recommendedTemplate?.id,
            recommendedFunctionDescription: recommendedFunctionDescription,
            options: options,
            confidence: confidence,
            reasons: reasons
        )
    }

    private static func classifyConfidence(
        recommendations: [AgentImportTemplateRecommendation]
    ) -> AgentImportNameResolution.Confidence {
        guard let first = recommendations.first else { return .low }
        let secondScore = recommendations.dropFirst().first?.score ?? 0
        let gap = first.score - secondScore

        if first.score >= 180 || (first.score >= 140 && gap >= 28) {
            return .high
        }
        if first.score >= 90 {
            return .medium
        }
        return .low
    }

    private static func recommendation(
        for template: AgentTemplate,
        context: String,
        rawName: String,
        soulMD: String
    ) -> AgentImportTemplateRecommendation? {
        var score = 0
        var reasons: [String] = []
        let normalizedRawName = normalizeSegment(rawName).lowercased()
        let parsedSoul = try? AgentTemplateSoulMarkdownParser.parse(soulMD)
        let soulTitle = parsedSoul?.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        if !soulTitle.isEmpty,
           soulTitle.localizedCaseInsensitiveCompare(template.name) == .orderedSame {
            score += 180
            reasons.append("SOUL 标题与模板完全一致")
        } else if !soulTitle.isEmpty, soulTitle.localizedCaseInsensitiveContains(template.name.lowercased()) {
            score += 72
            reasons.append("SOUL 标题与模板名称接近")
        }

        if normalizedRawName.localizedCaseInsensitiveCompare(template.name.lowercased()) == .orderedSame {
            score += 96
            reasons.append("原始 agent 名称与模板一致")
        } else if containsPhrase(template.name, in: normalizedRawName) {
            score += 30
            reasons.append("原始 agent 名称接近模板")
        }

        if containsPhrase(template.identity, in: context) {
            score += 54
            reasons.append("SOUL 内容命中模板身份")
        }

        let capabilityKeywords = Set(template.capabilities.map { normalizeSegment($0).lowercased() })
        let matchedCapabilities = capabilityKeywords.filter { !$0.isEmpty && context.localizedCaseInsensitiveContains($0) }
        if !matchedCapabilities.isEmpty {
            score += matchedCapabilities.count * 20
            reasons.append("SOUL 内容命中 \(matchedCapabilities.count) 个能力标签")
        }

        let matchedKeywords = searchPhrases(for: template).filter { containsPhrase($0, in: context) }
        if !matchedKeywords.isEmpty {
            score += min(matchedKeywords.count, 8) * 10
            reasons.append("SOUL 内容命中 \(matchedKeywords.count) 个模板关键词")
        }

        if let parsedSoul {
            let parsedFields = [
                parsedSoul.spec.role,
                parsedSoul.spec.mission
            ] + parsedSoul.spec.coreCapabilities
                + parsedSoul.spec.responsibilities
                + parsedSoul.spec.workflow
                + parsedSoul.spec.outputs
            let parsedText = parsedFields.joined(separator: " ").lowercased()

            if containsPhrase(template.summary, in: parsedText) {
                score += 26
                reasons.append("SOUL 使命描述接近模板摘要")
            }

            if containsPhrase(template.category.rawValue, in: parsedText) {
                score += 16
                reasons.append("SOUL 内容命中模板分类")
            }
        }

        if template.id == AgentTemplateCatalog.defaultTemplateID {
            score += 1
        }

        guard score > 0 else { return nil }
        return AgentImportTemplateRecommendation(
            template: template,
            score: score,
            reasons: Array(reasons.prefix(3))
        )
    }

    private static func makeSearchContext(rawName: String, soulMD: String, capabilities: [String]) -> String {
        let parsedSoul = try? AgentTemplateSoulMarkdownParser.parse(soulMD)

        let soulTitle = parsedSoul?.name ?? ""
        let role = parsedSoul?.spec.role ?? ""
        let mission = parsedSoul?.spec.mission ?? ""
        let coreCapabilities = parsedSoul?.spec.coreCapabilities.joined(separator: " ") ?? ""
        let responsibilities = parsedSoul?.spec.responsibilities.joined(separator: " ") ?? ""
        let workflow = parsedSoul?.spec.workflow.joined(separator: " ") ?? ""
        let outputs = parsedSoul?.spec.outputs.joined(separator: " ") ?? ""
        let capabilityText = capabilities.joined(separator: " ")

        let sections = [
            rawName,
            soulMD,
            soulTitle,
            role,
            mission,
            coreCapabilities,
            responsibilities,
            workflow,
            outputs,
            capabilityText
        ]

        return sections.joined(separator: " ").lowercased()
    }

    private static func searchPhrases(for template: AgentTemplate) -> [String] {
        let phrases = [
            template.name,
            template.summary,
            template.identity,
            template.category.rawValue,
            template.family.rawValue
        ]
        + template.capabilities
        + template.tags
        + template.applicableScenarios

        return phrases
            .map(normalizeSegment)
            .filter { $0.count >= 2 }
    }

    private static func containsPhrase(_ phrase: String, in text: String) -> Bool {
        let normalizedPhrase = normalizeSegment(phrase).lowercased()
        guard !normalizedPhrase.isEmpty else { return false }
        return text.localizedCaseInsensitiveContains(normalizedPhrase)
    }

    private static func normalizeSegment(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nonEmptyPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
