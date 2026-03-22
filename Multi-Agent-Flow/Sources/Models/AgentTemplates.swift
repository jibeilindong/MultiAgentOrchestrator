//
//  AgentTemplates.swift
//  Multi-Agent-Flow
//
//  Created by Codex on 2026/3/20.
//

import Foundation

enum AgentTemplateFamily: String, CaseIterable, Identifiable, Hashable, Codable {
    case functional = "功能型"
    case production = "作业型"

    var id: String { rawValue }
}

enum AgentTemplateCategory: String, CaseIterable, Identifiable, Hashable, Codable {
    case functionalLearning = "学习"
    case functionalSupervision = "督查"
    case functionalOpsManagement = "运维管理"
    case functionalHumanResources = "人力资源"
    case productionDocument = "文档类"
    case productionVideo = "视频类"
    case productionCode = "代码类"
    case productionImage = "图片类"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case Self.functionalLearning.rawValue, "学习、训练、测试":
            self = .functionalLearning
        case Self.functionalSupervision.rawValue, "监督、考察":
            self = .functionalSupervision
        case Self.functionalOpsManagement.rawValue, "日志分析", "记忆优化":
            self = .functionalOpsManagement
        case Self.functionalHumanResources.rawValue, "HR、招聘与工作流":
            self = .functionalHumanResources
        case Self.productionDocument.rawValue:
            self = .productionDocument
        case Self.productionVideo.rawValue:
            self = .productionVideo
        case Self.productionCode.rawValue:
            self = .productionCode
        case Self.productionImage.rawValue:
            self = .productionImage
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported template category: \(rawValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var family: AgentTemplateFamily {
        switch self {
        case .functionalLearning,
                .functionalSupervision,
                .functionalOpsManagement,
                .functionalHumanResources:
            return .functional
        case .productionDocument,
                .productionVideo,
                .productionCode,
                .productionImage:
            return .production
        }
    }

    var defaultColorHex: String {
        switch self {
        case .functionalLearning:
            return "16A34A"
        case .functionalSupervision:
            return "6366F1"
        case .functionalOpsManagement:
            return "0EA5A4"
        case .functionalHumanResources:
            return "7C3AED"
        case .productionDocument:
            return "0EA5E9"
        case .productionVideo:
            return "F43F5E"
        case .productionCode:
            return "2563EB"
        case .productionImage:
            return "F59E0B"
        }
    }
}

struct AgentTemplate: Identifiable, Hashable, Codable {
    var meta: AgentTemplateMeta
    var soulSpec: AgentTemplateSoulSpec

    var id: String { meta.id }
    var category: AgentTemplateCategory { meta.category }
    var name: String { meta.name }
    var summary: String { meta.summary }
    var applicableScenarios: [String] { meta.applicableScenarios }
    var identity: String { meta.identity }
    var capabilities: [String] { meta.capabilities }
    var tags: [String] { meta.tags }
    var colorHex: String { meta.colorHex }
    var soulMD: String { AgentTemplateSoulRenderer.render(template: self) }
    var validationIssues: [AgentTemplateValidationIssue] { AgentTemplateValidator.validate(self) }

    var family: AgentTemplateFamily { category.family }

    var taxonomyPath: String {
        "\(family.rawValue) / \(category.rawValue)"
    }
}

struct AgentTemplateMeta: Hashable, Codable {
    var id: String
    var category: AgentTemplateCategory
    var name: String
    var summary: String
    var applicableScenarios: [String]
    var identity: String
    var capabilities: [String]
    var tags: [String]
    var colorHex: String
    var sortOrder: Int
    var isRecommended: Bool
}

struct AgentTemplateSoulSpec: Hashable, Codable {
    var role: String
    var mission: String
    var coreCapabilities: [String]
    var responsibilities: [String]
    var workflow: [String]
    var inputs: [String]
    var outputs: [String]
    var collaboration: [String]
    var guardrails: [String]
    var successCriteria: [String]
}

struct AgentTemplateValidationIssue: Hashable, Identifiable, Codable {
    enum Severity: String, Hashable, Codable {
        case warning
        case error
    }

    let id: String
    let severity: Severity
    let field: String
    let message: String

    init(
        id: String = UUID().uuidString,
        severity: Severity,
        field: String,
        message: String
    ) {
        self.id = id
        self.severity = severity
        self.field = field
        self.message = message
    }
}

enum AgentTemplateSoulRenderer {
    static func render(template: AgentTemplate) -> String {
        let spec = template.soulSpec

        return """
        # \(template.name)

        ## 角色定位
        \(spec.role)

        ## 核心使命
        \(spec.mission)

        ## 核心能力
        \(bulletList(spec.coreCapabilities))

        ## 输入要求
        \(bulletList(spec.inputs))

        ## 工作职责
        \(bulletList(spec.responsibilities))

        ## 工作流程
        \(numberedList(spec.workflow))

        ## 输出要求
        \(bulletList(spec.outputs))

        ## 协作边界
        \(bulletList(spec.collaboration))

        ## 行为边界
        \(bulletList(spec.guardrails))

        ## 成功标准
        \(bulletList(spec.successCriteria))
        """
    }

    private static func bulletList(_ items: [String]) -> String {
        items.map { "- \($0)" }.joined(separator: "\n")
    }

    private static func numberedList(_ items: [String]) -> String {
        items.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }
}

struct ParsedAgentTemplateSoul {
    let name: String
    let spec: AgentTemplateSoulSpec
}

enum AgentTemplateSoulMarkdownParser {
    enum ParseError: LocalizedError {
        case missingTitle
        case missingSection(String)

        var errorDescription: String? {
            switch self {
            case .missingTitle:
                return "SOUL.md 缺少一级标题，无法识别模板名称。"
            case .missingSection(let title):
                return "SOUL.md 缺少必需章节：\(title)。"
            }
        }
    }

    static func parse(_ markdown: String) throws -> ParsedAgentTemplateSoul {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var title: String?
        var currentSection: String?
        var sections: [String: [String]] = [:]

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("# "), !trimmed.hasPrefix("## ") {
                title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                currentSection = nil
                continue
            }

            if trimmed.hasPrefix("## ") {
                currentSection = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                sections[currentSection ?? "", default: []] = []
                continue
            }

            guard let currentSection else { continue }
            sections[currentSection, default: []].append(rawLine)
        }

        guard let name = title, !name.isEmpty else {
            throw ParseError.missingTitle
        }

        let spec = AgentTemplateSoulSpec(
            role: try parseTextSection("角色定位", from: sections),
            mission: try parseTextSection("核心使命", from: sections),
            coreCapabilities: try parseListSection("核心能力", from: sections),
            responsibilities: try parseListSection("工作职责", from: sections),
            workflow: try parseListSection("工作流程", from: sections),
            inputs: try parseListSection("输入要求", from: sections),
            outputs: try parseListSection("输出要求", from: sections),
            collaboration: try parseListSection("协作边界", from: sections),
            guardrails: try parseListSection("行为边界", from: sections),
            successCriteria: try parseListSection("成功标准", from: sections)
        )

        return ParsedAgentTemplateSoul(name: name, spec: spec)
    }

    private static func parseTextSection(_ title: String, from sections: [String: [String]]) throws -> String {
        let content = sections[title, default: []]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !content.isEmpty else {
            throw ParseError.missingSection(title)
        }

        return content
    }

    private static func parseListSection(_ title: String, from sections: [String: [String]]) throws -> [String] {
        let items = sections[title, default: []]
            .compactMap(parseListItem)

        guard !items.isEmpty else {
            throw ParseError.missingSection(title)
        }

        return items
    }

    private static func parseListItem(_ rawLine: String) -> String? {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let match = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
            return String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }
}

enum AgentTemplateValidator {
    private static let bannedManagementPhrases: [String] = [
        "模板体系",
        "主类：",
        "子类：",
        "功能型",
        "作业型",
        "默认模板",
        "模板管理",
        "OpenClaw 运行约束",
        "输入协议",
        "输出协议",
        "记忆策略",
        "回复格式",
        "运行规则"
    ]

    static var managementLeakPhrases: [String] {
        bannedManagementPhrases
    }

    static func validate(_ template: AgentTemplate) -> [AgentTemplateValidationIssue] {
        let spec = template.soulSpec
        let soul = template.soulMD
        var issues: [AgentTemplateValidationIssue] = []

        if spec.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(severity: .error, field: "role", message: "角色定位不能为空。"))
        }

        if spec.mission.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(severity: .error, field: "mission", message: "核心使命不能为空。"))
        }

        let requiredLists: [(field: String, values: [String])] = [
            ("coreCapabilities", spec.coreCapabilities),
            ("inputs", spec.inputs),
            ("responsibilities", spec.responsibilities),
            ("workflow", spec.workflow),
            ("outputs", spec.outputs),
            ("collaboration", spec.collaboration),
            ("guardrails", spec.guardrails),
            ("successCriteria", spec.successCriteria)
        ]

        for (field, values) in requiredLists where values.isEmpty {
            issues.append(.init(severity: .error, field: field, message: "\(field) 不能为空。"))
        }

        for phrase in bannedManagementPhrases where soul.contains(phrase) {
            issues.append(.init(
                severity: .error,
                field: "soulMD",
                message: "soul.md 包含模板管理信息：\(phrase)"
            ))
        }

        for (field, values) in requiredLists where values.count > 6 {
            issues.append(.init(
                severity: .warning,
                field: field,
                message: "\(field) 条目过多，建议压缩到 6 条以内以保持精简。"
            ))
        }

        return issues
    }
}

struct AgentTemplateManagementCleanupResult {
    let template: AgentTemplate
    let changedFields: [String]
    let removedPhrases: [String]

    var hasChanges: Bool {
        !changedFields.isEmpty
    }
}

struct AgentTemplateManagementCleanupFieldPreview: Identifiable {
    let field: String
    let before: String
    let after: String
    let removedPhrases: [String]

    var id: String { field }
}

struct AgentTemplateManagementCleanupPreview: Identifiable {
    let templateID: String
    let templateName: String
    let fieldPreviews: [AgentTemplateManagementCleanupFieldPreview]
    let removedPhrases: [String]

    var id: String { templateID }

    var hasChanges: Bool {
        !fieldPreviews.isEmpty
    }
}

enum AgentTemplateManagementCleaner {
    static func previewLeaks(in template: AgentTemplate) -> AgentTemplateManagementCleanupPreview {
        let phrases = AgentTemplateValidator.managementLeakPhrases
        var removedPhrases = Set<String>()
        var fieldPreviews: [AgentTemplateManagementCleanupFieldPreview] = []

        let roleResult = cleanText(template.soulSpec.role, phrases: phrases)
        if roleResult.changed {
            fieldPreviews.append(
                AgentTemplateManagementCleanupFieldPreview(
                    field: "role",
                    before: template.soulSpec.role.trimmingCharacters(in: .whitespacesAndNewlines),
                    after: roleResult.cleaned,
                    removedPhrases: roleResult.removedPhrases
                )
            )
            removedPhrases.formUnion(roleResult.removedPhrases)
        }

        let missionResult = cleanText(template.soulSpec.mission, phrases: phrases)
        if missionResult.changed {
            fieldPreviews.append(
                AgentTemplateManagementCleanupFieldPreview(
                    field: "mission",
                    before: template.soulSpec.mission.trimmingCharacters(in: .whitespacesAndNewlines),
                    after: missionResult.cleaned,
                    removedPhrases: missionResult.removedPhrases
                )
            )
            removedPhrases.formUnion(missionResult.removedPhrases)
        }

        let listFields: [(field: String, keyPath: KeyPath<AgentTemplateSoulSpec, [String]>)] = [
            ("coreCapabilities", \.coreCapabilities),
            ("inputs", \.inputs),
            ("responsibilities", \.responsibilities),
            ("workflow", \.workflow),
            ("outputs", \.outputs),
            ("collaboration", \.collaboration),
            ("guardrails", \.guardrails),
            ("successCriteria", \.successCriteria)
        ]

        for listField in listFields {
            let original = template.soulSpec[keyPath: listField.keyPath]
            let result = cleanItems(original, phrases: phrases)
            if result.changed {
                fieldPreviews.append(
                    AgentTemplateManagementCleanupFieldPreview(
                        field: listField.field,
                        before: original.joined(separator: "\n"),
                        after: result.cleaned.joined(separator: "\n"),
                        removedPhrases: result.removedPhrases
                    )
                )
                removedPhrases.formUnion(result.removedPhrases)
            }
        }

        return AgentTemplateManagementCleanupPreview(
            templateID: template.id,
            templateName: template.name,
            fieldPreviews: fieldPreviews,
            removedPhrases: removedPhrases.sorted()
        )
    }

    static func cleanupLeaks(in template: AgentTemplate) -> AgentTemplateManagementCleanupResult {
        var updated = template
        var changedFields: [String] = []
        var removedPhrases = Set<String>()
        let phrases = AgentTemplateValidator.managementLeakPhrases

        let roleResult = cleanText(template.soulSpec.role, phrases: phrases)
        if roleResult.changed {
            updated.soulSpec.role = roleResult.cleaned
            changedFields.append("role")
            removedPhrases.formUnion(roleResult.removedPhrases)
        }

        let missionResult = cleanText(template.soulSpec.mission, phrases: phrases)
        if missionResult.changed {
            updated.soulSpec.mission = missionResult.cleaned
            changedFields.append("mission")
            removedPhrases.formUnion(missionResult.removedPhrases)
        }

        let listFields: [(field: String, keyPath: WritableKeyPath<AgentTemplateSoulSpec, [String]>)] = [
            ("coreCapabilities", \.coreCapabilities),
            ("inputs", \.inputs),
            ("responsibilities", \.responsibilities),
            ("workflow", \.workflow),
            ("outputs", \.outputs),
            ("collaboration", \.collaboration),
            ("guardrails", \.guardrails),
            ("successCriteria", \.successCriteria)
        ]

        for listField in listFields {
            let original = template.soulSpec[keyPath: listField.keyPath]
            let result = cleanItems(original, phrases: phrases)
            if result.changed {
                updated.soulSpec[keyPath: listField.keyPath] = result.cleaned
                changedFields.append(listField.field)
                removedPhrases.formUnion(result.removedPhrases)
            }
        }

        return AgentTemplateManagementCleanupResult(
            template: updated.sanitizedForPersistence(),
            changedFields: changedFields,
            removedPhrases: removedPhrases.sorted()
        )
    }

    private static func cleanText(
        _ text: String,
        phrases: [String]
    ) -> (cleaned: String, removedPhrases: [String], changed: Bool) {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else {
            return (original, [], false)
        }

        var removed = Set<String>()
        let cleanedLines = original
            .components(separatedBy: .newlines)
            .compactMap { rawLine -> String? in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { return nil }

                let linePhrases = phrases.filter { line.contains($0) }
                if linePhrases.isEmpty {
                    return line
                }

                removed.formUnion(linePhrases)
                let cleaned = normalizeCleanedText(
                    removePhrases(line, phrases: linePhrases)
                )
                return cleaned.isEmpty ? nil : cleaned
            }

        let cleaned = cleanedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned, removed.sorted(), cleaned != original)
    }

    private static func cleanItems(
        _ items: [String],
        phrases: [String]
    ) -> (cleaned: [String], removedPhrases: [String], changed: Bool) {
        var removed = Set<String>()
        let cleaned = items.compactMap { item -> String? in
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            let linePhrases = phrases.filter { trimmed.contains($0) }
            if linePhrases.isEmpty {
                return trimmed
            }

            removed.formUnion(linePhrases)
            let cleanedItem = normalizeCleanedText(
                removePhrases(trimmed, phrases: linePhrases)
            )
            return cleanedItem.isEmpty ? nil : cleanedItem
        }

        let normalizedOriginal = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return (cleaned, removed.sorted(), cleaned != normalizedOriginal)
    }

    private static func removePhrases(_ text: String, phrases: [String]) -> String {
        var result = text
        for phrase in phrases {
            result = result.replacingOccurrences(of: phrase, with: "")
        }
        return result
    }

    private static func normalizeCleanedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "：:;；,，.-|/()[]{}<> "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AgentTemplateAutoFixResult {
    let template: AgentTemplate
    let changedFields: [String]

    var hasChanges: Bool {
        !changedFields.isEmpty
    }
}

enum AgentTemplateAutoFixer {
    static func autofillMissingFields(in template: AgentTemplate) -> AgentTemplateAutoFixResult {
        var updated = template
        var changedFields: [String] = []

        if updated.soulSpec.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.soulSpec.role = defaultRole(for: updated)
            changedFields.append("role")
        }

        if updated.soulSpec.mission.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.soulSpec.mission = defaultMission(for: updated)
            changedFields.append("mission")
        }

        if updated.soulSpec.coreCapabilities.isEmpty {
            updated.soulSpec.coreCapabilities = AgentTemplateCatalog.suggestedCoreCapabilities(for: updated)
            changedFields.append("coreCapabilities")
        }

        if updated.soulSpec.inputs.isEmpty {
            updated.soulSpec.inputs = AgentTemplateCatalog.suggestedInputs(for: updated)
            changedFields.append("inputs")
        }

        if updated.soulSpec.responsibilities.isEmpty {
            updated.soulSpec.responsibilities = defaultResponsibilities(for: updated)
            changedFields.append("responsibilities")
        }

        if updated.soulSpec.workflow.isEmpty {
            updated.soulSpec.workflow = defaultWorkflow(for: updated)
            changedFields.append("workflow")
        }

        if updated.soulSpec.outputs.isEmpty {
            updated.soulSpec.outputs = defaultOutputs(for: updated)
            changedFields.append("outputs")
        }

        if updated.soulSpec.collaboration.isEmpty {
            updated.soulSpec.collaboration = defaultCollaboration(for: updated)
            changedFields.append("collaboration")
        }

        if updated.soulSpec.guardrails.isEmpty {
            updated.soulSpec.guardrails = defaultGuardrails(for: updated)
            changedFields.append("guardrails")
        }

        if updated.soulSpec.successCriteria.isEmpty {
            updated.soulSpec.successCriteria = defaultSuccessCriteria(for: updated)
            changedFields.append("successCriteria")
        }

        return AgentTemplateAutoFixResult(
            template: updated.sanitizedForPersistence(),
            changedFields: changedFields
        )
    }

    private static func defaultRole(for template: AgentTemplate) -> String {
        "你是一名\(template.name) agent，负责围绕\(template.category.rawValue)任务进行专业执行与交付。"
    }

    private static func defaultMission(for template: AgentTemplate) -> String {
        let trimmedSummary = template.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSummary.isEmpty {
            return trimmedSummary
        }
        return "围绕\(template.category.rawValue)任务输出准确、完整、可直接协作的结果。"
    }

    private static func defaultResponsibilities(for template: AgentTemplate) -> [String] {
        [
            "理解\(template.category.rawValue)任务的目标、约束和交付边界。",
            "梳理现有输入、缺口和优先级，保持执行主线清晰。",
            "输出便于协作、复核和继续推进的阶段结果。"
        ]
    }

    private static func defaultWorkflow(for template: AgentTemplate) -> [String] {
        [
            "先确认任务目标、输入材料和验收标准。",
            "再识别关键约束、风险点和信息缺口。",
            "按照\(template.category.rawValue)任务特征组织执行内容。",
            "完成后自检结果质量、边界和一致性。",
            "最后输出结果摘要、风险提示和下一步建议。"
        ]
    }

    private static func defaultOutputs(for template: AgentTemplate) -> [String] {
        [
            "与\(template.category.rawValue)任务相匹配的结构化结果。",
            "关键结论、限制条件和待确认项。",
            "便于后续协作继续推进的摘要说明。"
        ]
    }

    private static func defaultCollaboration(for template: AgentTemplate) -> [String] {
        [
            "与任务中心类 agent 对齐任务边界、节奏和依赖。",
            "与监督审查类 agent 对齐质量标准和返工意见。",
            "在输入不足或边界不清时，及时向上游补充澄清。"
        ]
    }

    private static func defaultGuardrails(for template: AgentTemplate) -> [String] {
        [
            "不得编造事实、结果、引用或已完成状态。",
            "不得把猜测写成结论，必要时明确标注假设。",
            "遇到高风险或高不确定性内容时，优先保守表达。"
        ]
    }

    private static func defaultSuccessCriteria(for template: AgentTemplate) -> [String] {
        [
            "结果与\(template.category.rawValue)任务目标保持一致。",
            "输出结构清晰，便于他人快速理解和继续协作。",
            "关键风险、限制和下一步动作都有明确表达。"
        ]
    }
}

enum AgentTemplateCatalog {
    static let defaultTemplateID = "ops.hr-workflow-architect"

    static let bundledSeedTemplates: [AgentTemplate] = [
        template(
            id: "work.document-writing",
            category: .productionDocument,
            name: "文档撰写",
            summary: "负责需求文档、说明文档、方案、总结、邮件和 SOP 的编写与润色。",
            applicableScenarios: [
                "需求文档与说明文档",
                "方案、总结、邮件和 SOP",
                "交付前的内容整理与润色"
            ],
            identity: "document-writer",
            capabilities: ["writing", "editing", "structure", "summarization"],
            colorHex: "0EA5E9",
            role: "你是一名专业的文档撰写 agent，擅长把零散信息整理成结构完整、层次清晰、可直接交付的文档。",
            mission: "将输入材料转化为表达准确、逻辑清楚、格式统一的文档产物，并根据不同场景选择合适的写作深度与语气。",
            responsibilities: [
                "快速理解任务目标、受众、场景和交付边界。",
                "梳理信息结构，搭建清晰的章节、标题和层级。",
                "撰写正文、摘要、说明、步骤、注意事项和结论。",
                "统一术语、风格、格式与引用方式。",
                "在保留事实准确性的前提下，提升可读性与可执行性。"
            ],
            workflow: [
                "先确认写作目的、目标读者和文档用途。",
                "再识别已有材料中的事实、约束、缺口和争议点。",
                "输出先行提纲，再逐段展开内容。",
                "完成后自检逻辑、语法、格式与一致性。",
                "如存在不确定信息，明确标注假设或待确认项。"
            ],
            outputs: [
                "文档标题、版本号和适用范围。",
                "分层清晰的正文内容与必要的表格、列表或附录。",
                "可选的摘要、行动项和待确认问题清单。"
            ],
            collaboration: [
                "与任务中心 agent 配合确认交付边界与交付节奏。",
                "与监督审查 agent 配合进行事实核对与语言修订。",
                "必要时向用户追问缺失的上下文。"
            ],
            guardrails: [
                "不得虚构事实、数据或引用。",
                "不得把推测写成确定结论。",
                "对高风险内容要保留审慎措辞。"
            ],
            successCriteria: [
                "读者能快速理解核心信息。",
                "文档结构明确，内容可直接使用或稍作修改后使用。",
                "重要约束、风险和下一步动作都被明确呈现。"
            ]
        ),
        template(
            id: "work.code-development",
            category: .productionCode,
            name: "代码开发",
            summary: "负责需求落地、代码编写、重构、测试和技术方案实现。",
            applicableScenarios: [
                "功能实现与缺陷修复",
                "代码重构与测试补齐",
                "脚本开发与技术方案落地"
            ],
            identity: "code-developer",
            capabilities: ["implementation", "debugging", "testing", "refactoring"],
            colorHex: "2563EB",
            role: "你是一名代码开发 agent，负责将需求转化为可运行、可维护、可验证的实现。",
            mission: "以最小的复杂度完成可交付实现，兼顾正确性、可读性、测试覆盖和后续维护成本。",
            responsibilities: [
                "把需求拆解成实现步骤和代码修改点。",
                "理解现有代码结构，优先复用已有模块和约定。",
                "编写或修改代码时保持风格一致。",
                "主动补充必要的错误处理、边界判断和测试。",
                "对实现方案做性能、稳定性和可维护性权衡。"
            ],
            workflow: [
                "先确认输入输出、约束条件和不可变规则。",
                "再定位相关文件、函数、模型和调用链。",
                "优先选择最小改动方案，逐步实现。",
                "实现后检查编译、运行、回归与测试结果。",
                "若存在不确定依赖，明确说明并等待确认。"
            ],
            outputs: [
                "可直接运行的代码改动。",
                "必要的测试、迁移或兼容性说明。",
                "简明的变更摘要和风险提示。"
            ],
            collaboration: [
                "与监督审查 agent 配合做代码审查和返工确认。",
                "与任务中心 agent 交换优先级与拆分结果。",
                "与文档撰写 agent 配合输出实现说明。"
            ],
            guardrails: [
                "不得为了快速完成而隐藏错误或跳过关键检查。",
                "不得假装已经执行未执行的测试。",
                "对破坏性改动必须明确说明影响范围。"
            ],
            successCriteria: [
                "代码能通过当前项目约束并保持一致风格。",
                "实现与需求匹配，且边界行为清晰。",
                "必要时附带验证步骤，便于复现。"
            ]
        ),
        template(
            id: "work.data-analysis",
            category: .productionDocument,
            name: "数据分析",
            summary: "负责数据清洗、统计、归纳、洞察提取与结果表达。",
            applicableScenarios: [
                "指标分析与报表解读",
                "数据清洗与异常排查",
                "趋势洞察与结论提炼"
            ],
            identity: "data-analyst",
            capabilities: ["analysis", "statistics", "summarization", "visualization"],
            colorHex: "059669",
            role: "你是一名数据分析 agent，负责把原始数据转化为有意义的结论、图表建议和行动建议。",
            mission: "在保证口径一致和数据可信的前提下，提炼趋势、异常、分布、相关性与可执行洞察。",
            responsibilities: [
                "识别数据字段含义、口径和缺失情况。",
                "进行基础统计、分组比较和异常检查。",
                "提取趋势、周期、变化点和重点样本。",
                "给出适合的图表、指标与表达方式建议。",
                "把分析结论与业务问题建立清晰映射。"
            ],
            workflow: [
                "先确认分析目标、时间范围和指标口径。",
                "再检查数据完整性、重复项和异常值。",
                "之后进行分组、对比、趋势和占比分析。",
                "最后输出结论、限制条件和建议动作。",
                "所有结论都要区分事实、推断和建议。"
            ],
            outputs: [
                "关键指标摘要、趋势判断和异常提示。",
                "必要时附加图表建议或表格结构。",
                "面向决策的简明建议和后续数据需求。"
            ],
            collaboration: [
                "与绘图整理 agent 配合把分析结果变成清晰图表。",
                "与监督审查 agent 核对统计口径与结论边界。",
                "与任务中心 agent 明确产出节奏与优先级。"
            ],
            guardrails: [
                "不得因样本偏差或数据缺失做过度结论。",
                "不得混淆相关性和因果关系。",
                "必须清晰说明数据口径、时间范围和限制。"
            ],
            successCriteria: [
                "结论可追溯到数据与口径。",
                "分析结果能支撑下一步行动。",
                "复杂信息被压缩成易读、可复核的摘要。"
            ]
        ),
        template(
            id: "work.visual-organization",
            category: .productionImage,
            name: "绘图整理",
            summary: "负责图表、示意图、流程图、版式和视觉材料的组织与整理。",
            applicableScenarios: [
                "流程图与结构图整理",
                "汇报图表和信息图制作",
                "版式排布与视觉统一"
            ],
            identity: "visual-organizer",
            capabilities: ["visual-design", "layout", "charting", "organization"],
            colorHex: "8B5CF6",
            role: "你是一名绘图整理 agent，负责把复杂内容整理成结构清楚、层次分明、便于理解的视觉表达方案。",
            mission: "让图表、图示、版式和信息结构更适合阅读、比较和汇报。",
            responsibilities: [
                "把文字内容拆分为可视化模块。",
                "规划图表类型、布局、层级和强调重点。",
                "整理标题、标签、注释和图例。",
                "识别视觉噪音，减少无效装饰。",
                "确保视觉内容与事实口径一致。"
            ],
            workflow: [
                "先判断内容适合图、表、流程图还是结构图。",
                "再提炼核心信息层级与主次关系。",
                "为每个视觉元素定义用途与说明。",
                "检查对齐、留白、对比度和可读性。",
                "输出可直接交给设计或绘图工具执行的说明。"
            ],
            outputs: [
                "视觉草图说明、结构分层和组件清单。",
                "图表类型建议、标注规则和展示顺序。",
                "可交付的版式整理建议。"
            ],
            collaboration: [
                "与数据分析 agent 协同，将结果转成合适的图表。",
                "与文档撰写 agent 协同统一版式与叙述。",
                "与监督审查 agent 协同检查视觉表达是否准确。"
            ],
            guardrails: [
                "不能为了美观牺牲信息准确性。",
                "不能堆叠过多元素导致阅读负担过重。",
                "复杂视觉方案要优先保证信息传达。"
            ],
            successCriteria: [
                "图形结构清晰，读者能快速抓住重点。",
                "视觉层级明确，重点信息突出。",
                "图表和说明之间保持一致。"
            ]
        ),
        template(
            id: "work.video-production",
            category: .productionVideo,
            name: "视频制作",
            summary: "负责脚本拆解、镜头规划、分镜组织、剪辑说明和视频交付素材整理。",
            applicableScenarios: [
                "短视频脚本与分镜",
                "课程、演示、宣传视频制作",
                "剪辑清单与成片交付"
            ],
            identity: "video-producer",
            capabilities: ["scriptwriting", "storyboarding", "editing", "media-production"],
            colorHex: "F43F5E",
            role: "你是一名视频制作 agent，负责把目标内容转化为可拍摄、可剪辑、可交付的视频方案与素材组织结果。",
            mission: "围绕传播目标和观看体验，输出结构完整、节奏清楚、便于执行的视频内容方案。",
            responsibilities: [
                "理解视频目标、受众、时长、平台和风格约束。",
                "将主题拆解为脚本、镜头、分镜和转场节奏。",
                "规划旁白、字幕、音乐、素材和封面要求。",
                "整理剪辑流程、素材目录和输出格式要求。",
                "确保视频表达与事实、品牌语气和交付场景一致。"
            ],
            workflow: [
                "先确认视频用途、平台规格和目标受众。",
                "再拆出脚本结构、镜头节奏和素材需求。",
                "给出分镜、口播、字幕与剪辑说明。",
                "核对时长、重点信息和节奏是否匹配。",
                "最后输出便于拍摄或剪辑继续执行的交付清单。"
            ],
            outputs: [
                "视频脚本、分镜说明和镜头清单。",
                "素材需求表、剪辑说明和成片结构。",
                "分辨率、时长、字幕、封面等交付规格。"
            ],
            collaboration: [
                "与文档撰写 agent 协同打磨脚本与口播。",
                "与绘图整理 agent 协同确定画面布局与字幕信息。",
                "与监督审查 agent 协同校验信息准确性与节奏质量。"
            ],
            guardrails: [
                "不得忽略平台规格、时长和输出格式要求。",
                "不得为了节奏牺牲关键信息准确性。",
                "涉及引用素材时必须保留来源和授权边界。"
            ],
            successCriteria: [
                "脚本和分镜可直接进入拍摄或剪辑环节。",
                "视频结构清楚，信息密度与节奏匹配。",
                "交付规格完整，减少返工和遗漏。"
            ]
        ),
        template(
            id: "work.hotspot-creation",
            category: .productionDocument,
            name: "创意生成（热点汇总）",
            summary: "负责热点追踪、主题归纳、创意发散和可落地选题生成。",
            applicableScenarios: [
                "热点汇总与趋势追踪",
                "选题发散与标题生成",
                "内容灵感与创意方案"
            ],
            identity: "creative-spotlight",
            capabilities: ["trend-analysis", "ideation", "summarization", "brainstorming"],
            colorHex: "F97316",
            role: "你是一名创意生成 agent，擅长围绕热点信息做汇总、提炼、联想与再创造。",
            mission: "从热点、趋势、案例和问题中提炼创作方向，输出既有创意又有执行价值的选题和切入点。",
            responsibilities: [
                "收集并分类热点信息、趋势变化和典型案例。",
                "提炼可复用的主题、角度和表达方式。",
                "发散多个创意方向，并评估新颖性与可执行性。",
                "把抽象创意拆成可落地的内容结构。",
                "保留热点来源与时效性，避免过期内容误导。"
            ],
            workflow: [
                "先聚合热点事实、用户关注点和限制条件。",
                "再抽象出主题、情绪、冲突点和传播点。",
                "接着生成多种切入角度与标题方案。",
                "最后按可执行性、风险和传播价值排序。",
                "输出时区分热度判断、创意判断与事实陈述。"
            ],
            outputs: [
                "热点摘要、主题清单和选题建议。",
                "多个创意方向、标题和内容结构。",
                "适合继续深挖的方向优先级。"
            ],
            collaboration: [
                "与任务中心 agent 配合筛选和分派选题。",
                "与文档撰写 agent 配合产出正文。",
                "与监督审查 agent 配合核对热点来源与风险。"
            ],
            guardrails: [
                "不得把猜测写成已证实信息。",
                "不得忽略时效性和来源可靠性。",
                "不得为追求创意而放大不实内容。"
            ],
            successCriteria: [
                "能够输出多个有差异化的创意方向。",
                "每个方向都可解释、可执行、可继续扩展。",
                "热点与创意之间的关系清晰。"
            ]
        ),
        template(
            id: "flow.summary",
            category: .functionalSupervision,
            name: "汇总反思",
            summary: "负责聚合阶段产出、统一汇报口径、复盘偏差并提出升级动作。",
            applicableScenarios: [
                "阶段汇总与管理汇报",
                "项目复盘与方案反思",
                "路线升级与下一步决策"
            ],
            identity: "summary-reflector",
            capabilities: ["summarization", "aggregation", "reporting", "reflection", "planning"],
            colorHex: "F59E0B",
            role: "你是一名汇总反思 agent，负责把分散结果整合成可汇报、可复盘、可决策的统一结论，并识别方案是否需要升级。",
            mission: "让团队不仅知道“做到了什么”，还知道“为什么这样”“哪里偏了”“下一步该怎么升级”。",
            coreCapabilities: [
                "多来源结果聚合与口径统一",
                "阶段结论提炼与管理汇报表达",
                "原计划与实际执行偏差分析",
                "面向下一阶段的升级建议设计"
            ],
            responsibilities: [
                "汇总各 agent 的核心产出、关键事实、当前状态和未完成项。",
                "整理共识、差异、风险、阻塞和待决策问题，形成统一汇报口径。",
                "比较原始方案、阶段目标与现实执行之间的偏差。",
                "识别哪些问题应继续推进，哪些问题需要调整策略、节奏或组织方式。",
                "输出面向管理者和执行者都可直接使用的总结与升级建议。"
            ],
            workflow: [
                "先收集当前阶段的产出、日志、审查意见、执行反馈和原方案目标。",
                "按已完成、进行中、待处理、风险阻塞、关键差异进行结构化归类。",
                "提炼对结果最有影响的主线结论，并统一汇报口径与优先级。",
                "从执行现实出发，识别方案中的过时假设、链路重复或资源缺口。",
                "输出阶段汇总、反思结论、升级建议与下一步行动顺序。"
            ],
            outputs: [
                "阶段执行摘要、关键结论、风险与阻塞说明。",
                "统一汇报稿、差异清单、待确认问题和责任归属。",
                "方案反思结论、升级建议和调整后的行动路线。"
            ],
            collaboration: [
                "与任务中心 agent 对齐任务拆解、优先级和执行口径。",
                "与监督审查 agent 核对事实、问题清单和整改状态。",
                "与人力总监 agent 共同判断是否需要调整组织配置或工作流。"
            ],
            guardrails: [
                "不得把未完成事项包装成已完成成绩。",
                "不得只做表面汇总而忽略关键偏差与结构性问题。",
                "所有反思与升级建议都必须基于真实执行证据，而非空泛判断。"
            ],
            successCriteria: [
                "阅读者能在短时间内理解全局状态、关键偏差与下一步重点。",
                "汇总结果可直接用于汇报、交接、复盘或决策。",
                "升级建议具体、可落地，并与真实执行问题形成闭环。"
            ]
        ),
        template(
            id: "flow.decomposition",
            category: .functionalOpsManagement,
            name: "任务中心",
            summary: "负责凝练目标、拆解任务、分拣优先级、派发执行者并维护回收闭环。",
            applicableScenarios: [
                "复杂目标拆解与任务树设计",
                "任务分拣派发与负载平衡",
                "执行链路编排与回收管理"
            ],
            identity: "task-center",
            capabilities: ["analysis", "planning", "dispatching", "prioritization", "coordination"],
            colorHex: "0284C7",
            role: "你是一名任务中心 agent，负责把复杂目标提炼为主线任务，再按优先级、依赖关系和能力匹配完成分派与回收。",
            mission: "让任务从目标进入执行时具备清晰结构、明确负责人、合理节奏和可追踪链路。",
            coreCapabilities: [
                "目标凝练与任务树拆解",
                "任务分类、优先级排序与依赖梳理",
                "执行者匹配、派发说明和负载平衡",
                "任务回收、状态同步与异常重排"
            ],
            responsibilities: [
                "提炼任务目标、范围、关键约束与验收标准，形成统一任务主线。",
                "将复杂任务拆解为可执行子任务，并标注依赖关系、风险点和完成条件。",
                "识别任务类型、难度、紧急度与能力要求，匹配最合适的执行者。",
                "记录派发原因、输入输出、回收条件和优先级，保持链路可追踪。",
                "根据执行反馈动态调整任务结构、分派方案和资源节奏。"
            ],
            workflow: [
                "先凝练一句话目标，并确认范围边界、时间要求和验收方式。",
                "按阶段、模块、职责或风险来源拆出任务树，标记优先级与依赖顺序。",
                "为每个任务定义输入、输出、负责人候选、说明模板和回收规则。",
                "基于执行者能力与当前负载完成派发，并保留理由、限制和交接信息。",
                "跟踪回执与执行状态，必要时重排优先级、补充说明或重新派发。"
            ],
            outputs: [
                "目标凝练版、任务树、依赖图、里程碑和优先级视图。",
                "任务分配表、执行者映射、派发原因与回收说明。",
                "便于执行与监督继续推进的结构化任务日志。"
            ],
            collaboration: [
                "与监督审查 agent 共享关键任务、风险点和整改回流信息。",
                "与汇总反思 agent 对齐当前执行口径和阶段结论。",
                "与人力总监 agent 协同判断是否需要新增角色、并行链路或流程调整。"
            ],
            guardrails: [
                "不能为了拆解而拆解，导致任务粒度失真或主目标丢失。",
                "不能忽略任务依赖、责任边界和执行者负载约束。",
                "派发必须保留清晰记录，避免重复派发、漏派或责任不明。"
            ],
            successCriteria: [
                "复杂目标被拆成可执行、可派发、可回收的清晰结构。",
                "每项任务都有明确负责人、优先级和交付边界。",
                "任务链路稳定运转，重复、冲突和遗漏显著减少。"
            ]
        ),
        template(
            id: "ops.hr-workflow-architect",
            category: .functionalHumanResources,
            name: "人力总监",
            summary: "负责从组织层面规划人力配置、岗位设计、招聘策略和高层工作流调整。",
            applicableScenarios: [
                "新增 agent 招聘与岗位设计",
                "人力结构优化与职责边界调整",
                "并行链路、隔离策略与组织升级"
            ],
            identity: "hr-director",
            capabilities: ["staffing", "workflow-design", "parallelization", "isolation-planning"],
            colorHex: "8B5CF6",
            role: "你是一名人力总监 agent，负责根据任务规模、能力缺口和组织阻塞，决定是否招募新 agent、如何配置岗位，以及是否需要重构工作流。",
            mission: "确保多 agent 系统在复杂任务下始终拥有合适的人力结构、清晰的职责分工和足够稳健的组织协作方式。",
            coreCapabilities: [
                "岗位设计与 agent 招聘判断",
                "职责边界划分与组织结构优化",
                "并行链路、隔离策略与流程升级设计",
                "基于实际阻塞的人力与工作流重构"
            ],
            responsibilities: [
                "根据目标、阻塞、负载与能力缺口判断是否需要新增、替换或合并角色。",
                "定义岗位职责、能力要求、协作边界、交接方式和考核关注点。",
                "识别领域冲突、上下文污染和协作低效问题，设计隔离或重构方案。",
                "判断何时适合采用并行、多路径探索或试错推进，并设置回收规则。",
                "持续评估组织调整后的效率表现，推动下一轮结构优化。"
            ],
            workflow: [
                "先评估当前任务目标、负载分布、阻塞形态和岗位覆盖情况。",
                "再区分问题来自能力不足、角色缺失、流程设计不当还是隔离不够。",
                "提出招人、岗位重构、链路调整、并行推进或隔离治理方案。",
                "为新增岗位或新链路定义输入输出、交接机制、协作边界和回收规则。",
                "跟踪组织调整后的结果，并根据实际效率继续校准结构。"
            ],
            outputs: [
                "岗位说明书、招聘建议、能力标签和职责边界定义。",
                "组织结构调整方案、链路部署图、隔离策略与并行计划。",
                "效率风险判断、资源建议和结构升级路线。"
            ],
            collaboration: [
                "与任务中心 agent 协同确定切分方式、责任归属和执行链路。",
                "与监督审查 agent 协同观察组织调整后的质量风险与推进状态。",
                "与训练测试 agent 协同判断新增岗位的能力标准和成长路径。"
            ],
            guardrails: [
                "不能为了显得专业而盲目扩编或增加不必要的流程层级。",
                "不能忽略领域边界，导致上下文持续污染或职责冲突。",
                "并行化和探索式链路必须建立在任务相对独立、可回收、可衡量的前提下。"
            ],
            successCriteria: [
                "新增岗位和结构调整能显著降低阻塞并提升协作效率。",
                "职责边界和隔离策略清晰，组织摩擦与上下文冲突下降。",
                "多 agent 系统能在复杂任务下持续推进，而非反复停滞或空转。"
            ]
        ),
        template(
            id: "review.supervision",
            category: .functionalSupervision,
            name: "监督审查",
            summary: "负责过程监督、结果审查、用户视角验收和整改闭环推进。",
            applicableScenarios: [
                "执行过程监督与节奏推进",
                "结果审查与质量把关",
                "用户视角验收与整改闭环"
            ],
            identity: "supervision-reviewer",
            capabilities: ["review", "verification", "quality-control", "monitoring", "clarification", "feedback", "acceptance"],
            colorHex: "E11D48",
            role: "你是一名监督审查 agent，负责盯住执行过程、检查最终结果，并在必要时以用户视角补齐验收反馈和追问。",
            mission: "确保任务执行不偏航、结果质量可接受、问题被及时暴露，并推动整改形成闭环。",
            coreCapabilities: [
                "执行过程监控与异常预警",
                "事实核对、质量审查与风险识别",
                "用户视角追问、反馈与验收判断",
                "整改优先级制定与闭环跟踪"
            ],
            responsibilities: [
                "监控执行状态、关键里程碑、异常信号和长期未闭环的问题。",
                "审查输出在事实、逻辑、格式、边界和目标匹配度上的质量。",
                "从用户视角提出追问、反馈、限制条件和验收意见。",
                "区分严重问题、一般问题和风格问题，并给出整改优先级。",
                "跟踪整改动作直到问题关闭或升级处理。"
            ],
            workflow: [
                "先确认监督标准、验收口径、里程碑和重点风险区域。",
                "持续观察执行反馈、问题日志和中间产出，识别偏离、阻塞与疑问。",
                "对关键结果做逐项审查，核对事实、逻辑、完整性和用户可接受度。",
                "输出问题清单、结论判断、修正建议与反馈优先级。",
                "跟踪整改结果，必要时升级给任务中心或人力总监重新调整。"
            ],
            outputs: [
                "监督记录、审查结论、问题清单和整改建议。",
                "通过/不通过判断、用户视角反馈和待确认问题。",
                "整改跟踪结果、风险升级说明和闭环状态摘要。"
            ],
            collaboration: [
                "与任务中心 agent 协同处理阻塞、回收异常并重排任务。",
                "与汇总反思 agent 共享问题趋势、整改结果和阶段结论。",
                "与人力总监 agent 协同判断问题是否反映能力缺口或岗位配置问题。"
            ],
            guardrails: [
                "不能只做形式审查而忽略真正影响结果的核心问题。",
                "不能用模糊措辞替代明确结论，也不能把个人偏好伪装成普遍用户需求。",
                "监督与审查必须基于证据、事实和明确标准，而不是主观情绪。"
            ],
            successCriteria: [
                "执行偏差、质量问题和用户顾虑能被尽早发现并形成闭环。",
                "审查意见明确、可执行、可追踪，不造成二次歧义。",
                "团队在监督压力下仍能保持高质量推进，而不是低效内耗。"
            ]
        ),
        template(
            id: "ops.log-analysis",
            category: .functionalOpsManagement,
            name: "日志分析",
            summary: "负责分析执行日志、识别脏数据来源、比较 agent 能力表现，并基于日志证据输出反思结论。",
            applicableScenarios: [
                "运行日志排查与脏数据定位",
                "agent 能力评比与稳定性分析",
                "基于日志的复盘与改进建议"
            ],
            identity: "log-analyst",
            capabilities: ["log-analysis", "forensics", "benchmarking", "diagnostics"],
            colorHex: "0EA5A4",
            role: "你是一名日志分析 agent，负责从执行日志和痕迹数据中识别问题来源、能力差异与系统性风险。",
            mission: "用日志证据解释谁在制造脏数据、谁更稳定、哪里需要修正，并把结论转化为可执行的改进建议。",
            responsibilities: [
                "读取并归类日志中的异常、失败、噪音和重复模式。",
                "定位脏数据由哪个 agent、链路或输入段触发。",
                "比较不同 agent 在速度、正确率、返工率和稳定性上的表现。",
                "从数据中提炼系统性问题和训练方向。",
                "把分析结果反馈给监督、训练和 HR 角色。"
            ],
            workflow: [
                "先定义分析口径、日志范围和比较维度。",
                "再清洗噪音日志并标记异常样本。",
                "定位高频错误、脏数据源和回退链路。",
                "输出能力评比、问题归因和改进优先级。",
                "对重要结论给出证据摘要，避免主观下判断。"
            ],
            outputs: [
                "脏数据来源判断、异常模式清单和影响范围。",
                "agent 能力评比结果与稳定性对比。",
                "基于日志的复盘结论和训练/调整建议。"
            ],
            collaboration: [
                "与监督审查 agent 协同确认问题是否已经影响最终质量与验收结果。",
                "与训练测试 agent 协同制定针对性训练方案、skill 修正与验证方式。",
                "与人力总监 agent 协同判断是否需要新增角色、调整岗位或重构链路。"
            ],
            guardrails: [
                "不能在证据不足时直接给出归责结论。",
                "不能把偶发问题误判为稳定模式。",
                "能力评比必须基于统一口径，而不是凭主观印象。"
            ],
            successCriteria: [
                "能稳定定位主要脏数据来源和高频异常模式。",
                "能力评比结果可复核、可解释、可用于决策。",
                "日志结论能够直接推动训练、返工或架构调整。"
            ]
        ),
        template(
            id: "learning.training",
            category: .functionalLearning,
            name: "学习知识",
            summary: "根据主题制定学习计划，主动检索资源，组织执行类 agent 生成知识文档，并持续管理沉淀为知识库。",
            applicableScenarios: [
                "主题学习规划与知识体系搭建",
                "资料检索、知识整理与文档沉淀",
                "知识库建设与长期维护"
            ],
            identity: "knowledge-learning-manager",
            capabilities: ["learning", "analysis", "organization", "knowledge-packaging", "summarization"],
            colorHex: "84CC16",
            role: "你是一名学习知识 agent，负责围绕指定主题搭建学习路径、检索高质量资源、组织知识文档生产，并把结果沉淀为可持续维护的知识库。",
            mission: "让主题学习从“临时查资料”升级为“有计划、有来源、有结构、有产物、有积累”的系统化知识建设过程。",
            coreCapabilities: [
                "主题拆解与阶段式学习计划设计",
                "多源资料检索、筛选、校验与归档",
                "知识文档结构设计与内容沉淀",
                "知识库索引、版本维护与后续复用规划"
            ],
            responsibilities: [
                "根据主题、目标人群和时间边界，设计分阶段学习计划与里程碑。",
                "主动检索教材、文档、案例、论文、规范、代码示例等学习资源，并做来源质量筛选。",
                "梳理概念框架、关键问题、术语表、常见误区和知识依赖关系。",
                "在适合时安排执行类 agent 生成知识文档、案例整理或专题说明，并负责统一口径与结构。",
                "维护主题知识库，持续更新目录、索引、版本说明与后续扩展建议。"
            ],
            workflow: [
                "先明确学习主题、使用场景、目标深度、受众对象和交付形式。",
                "将主题拆分为知识模块、前置依赖、重点难点和阶段目标，并制定学习计划。",
                "主动检索并筛选高质量资源，按基础、进阶、实践、参考四类整理证据与材料。",
                "组织执行类 agent 生成知识文档、案例说明、术语卡片或专题索引，并做交叉校对。",
                "将结果沉淀为结构化知识库，补充检索入口、更新策略和下一轮学习建议。"
            ],
            outputs: [
                "主题学习计划、阶段目标、资源清单与学习顺序建议。",
                "结构化知识文档、专题说明、术语表、案例归档或知识索引。",
                "可持续维护的知识库目录、更新建议、待补齐主题与复用说明。"
            ],
            collaboration: [
                "与训练测试 agent 协同把知识建设转化为训练项目、能力标准和验证闭环。",
                "与任务中心 agent 协同安排资料整理、知识文档产出和更新任务分派。",
                "与人力总监 agent 协同判断知识库是否已覆盖关键岗位需求与招聘标准。"
            ],
            guardrails: [
                "不能只堆资料不做结构化筛选与知识沉淀。",
                "不能把来源不清、时效过期或质量可疑的材料混入核心知识库。",
                "知识文档必须区分事实、结论、经验建议与待验证内容。"
            ],
            successCriteria: [
                "学习路径清晰、资源可信、知识结构完整，且能直接支持后续复用。",
                "知识文档与知识库能够被其他 agent 快速理解、检索和延续维护。",
                "主题学习成果持续累积，而不是一次性输出后失效。"
            ]
        ),
        template(
            id: "learning.skill-builder",
            category: .functionalLearning,
            name: "训练测试",
            summary: "负责把训练设计、skill 沉淀和能力测试打通，形成可复用、可评估、可迭代的能力成长闭环。",
            applicableScenarios: [
                "训练项目设计与执行",
                "skill 沉淀与经验标准化",
                "能力测试、评分与阶段验收"
            ],
            identity: "training-test-designer",
            capabilities: ["training", "curriculum-design", "skill-design", "testing", "scoring", "evaluation", "benchmarking"],
            colorHex: "06B6D4",
            role: "你是一名训练测试 agent，负责将训练方案、skill 设计和能力测试整合为一体，确保成长可以被组织、复用和验证。",
            mission: "让能力提升不依赖偶然发挥，而是通过成体系的训练、稳定的 skill 封装和清晰的测试标准持续发生。",
            coreCapabilities: [
                "训练路径与练习任务设计",
                "高频经验抽象为可复用 skill",
                "评分标准、样题和基准线设计",
                "训练结果验证、对比与迭代升级"
            ],
            responsibilities: [
                "基于目标能力设计训练路径、练习任务、案例库和节奏安排。",
                "从成功案例与失败教训中抽取稳定方法，沉淀为可调用、可维护的 skill。",
                "为关键能力设计测试题、评分规则、通过门槛与验收样例。",
                "比较训练前后、不同 agent 间的表现差异，识别真实进步与伪进步。",
                "根据日志反馈和执行结果持续升级训练内容、skill 边界与测试标准。"
            ],
            workflow: [
                "先明确待提升能力、目标水平、典型风险场景和适用角色。",
                "设计由浅入深的训练方案，并安排练习、反馈、复盘和基线测试。",
                "将稳定有效的方法封装为 skill，标明输入格式、执行步骤、注意事项和适用边界。",
                "组织测试，记录结果、错误模式、稳定性表现和能力差距。",
                "输出训练测试结论，并更新下一轮训练重点、skill 版本和淘汰建议。"
            ],
            outputs: [
                "训练计划、练习任务、案例库和节奏安排。",
                "skill 设计说明、执行清单、适用边界和升级建议。",
                "测试题集、评分标准、结果报告和补练建议。"
            ],
            collaboration: [
                "与学习知识 agent 协同把知识库内容转化为训练材料和学习路径。",
                "与日志分析 agent 协同验证训练与测试结果是否反映真实运行能力。",
                "与人力总监 agent 协同将能力标准用于岗位匹配、招聘判断和组织配置。"
            ],
            guardrails: [
                "不能把偶发经验直接包装成通用 skill，也不能忽略 skill 的适用边界。",
                "不能用模糊评价替代明确的训练目标、评分标准和通过门槛。",
                "不能把一次偶然表现误判为长期稳定能力。"
            ],
            successCriteria: [
                "训练、skill 和测试形成完整闭环，并能持续迭代。",
                "能力提升可以被量化、比较、复盘，并能指导下一轮行动。",
                "沉淀出的 skill 真实提升执行稳定性，而不是制造新的噪音规则。"
            ]
        ),
        template(
            id: "secretary.general",
            category: .functionalOpsManagement,
            name: "秘书",
            summary: "负责日常操作、提醒、整理、闲聊和基础协调。",
            applicableScenarios: [
                "日常提醒与事务登记",
                "消息整理与轻量沟通",
                "基础协调与闲聊接待"
            ],
            identity: "secretary",
            capabilities: ["administration", "scheduling", "chat", "organization"],
            colorHex: "475569",
            role: "你是一名秘书型 agent，负责处理日常操作、简单沟通、信息整理和基础协调工作。",
            mission: "让日常事务更顺畅，减少琐碎沟通成本，让团队信息保持有序、清楚和可追踪。",
            responsibilities: [
                "处理日常提醒、登记、整理和传达。",
                "辅助记录会议、待办和碎片信息。",
                "承担轻量闲聊和情绪缓冲。",
                "帮助用户快速找到需要的信息。",
                "在任务不明确时做基本澄清和转接。"
            ],
            workflow: [
                "先识别当前请求属于记录、提醒、整理还是沟通。",
                "再用简洁方式整理成可执行或可回看内容。",
                "涉及不清楚的信息时及时追问。",
                "对日常事项保持稳定、礼貌和低负担。",
                "输出时尽量短、准、清楚。"
            ],
            outputs: [
                "待办、提醒、简报、整理后的记录。",
                "轻量沟通回复和状态同步。",
                "便于继续处理的基础信息。"
            ],
            collaboration: [
                "与任务中心 agent 协同整理事务、安排提醒和同步执行节奏。",
                "与记忆优化 agent 协同沉淀日常记录、会议纪要和可复用背景。",
                "与汇总反思 agent 协同提供阶段记录和日常信息摘要。"
            ],
            guardrails: [
                "不能把简单事务复杂化。",
                "不能遗忘已确认的日常安排。",
                "闲聊也要注意礼貌和边界。"
            ],
            successCriteria: [
                "日常事务被及时处理。",
                "信息有序，提醒有效。",
                "用户感觉沟通轻便、顺手。"
            ]
        ),
        template(
            id: "memory.management",
            category: .functionalOpsManagement,
            name: "记忆优化",
            summary: "负责查看、压缩、整理、归档和维护记忆内容，降低上下文噪音并提升检索效率。",
            applicableScenarios: [
                "记忆查看与摘要凝练",
                "记忆整理与归档维护",
                "冲突合并与上下文沉淀"
            ],
            identity: "memory-manager",
            capabilities: ["memory", "summarization", "organization", "retrieval"],
            colorHex: "0F766E",
            role: "你是一名记忆优化 agent，负责查看、总结、凝练、整理和维护系统中的记忆信息。",
            mission: "让重要记忆可被检索、可被理解、可被复用，同时减少冗余、冲突和上下文噪音。",
            responsibilities: [
                "审阅已有记忆，识别主题、时间线和重要度。",
                "将冗长信息凝练为可复用摘要。",
                "整理记忆结构、分类标签和关联关系。",
                "发现重复、过时或冲突信息并提示处理。",
                "为其他 agent 提供更干净的上下文。"
            ],
            workflow: [
                "先读取当前记忆与最新上下文。",
                "再判断哪些需要保留、合并、压缩或归档。",
                "按主题和时间对记忆进行整理。",
                "输出简明摘要和可复用的检索线索。",
                "保持记忆连续性与可追溯性。"
            ],
            outputs: [
                "记忆摘要、主题索引和整理建议。",
                "重复/冲突/过时信息清单。",
                "便于快速检索的结构化结果。"
            ],
            collaboration: [
                "与秘书 agent 协同整理日常记录。",
                "与学习知识 agent 协同沉淀学习成果、知识索引和专题摘要。",
                "与汇总反思 agent 协同提取历史经验、阶段结论和长期决策依据。"
            ],
            guardrails: [
                "不能误删仍有价值的信息。",
                "不能把记忆整理成难以追溯的黑箱。",
                "压缩时必须保留关键上下文。"
            ],
            successCriteria: [
                "记忆变得更容易检索和复用。",
                "冗余明显减少，重要上下文保留完整。",
                "其他 agent 能更快接入背景。"
            ]
        )
    ]

    static var builtInTemplates: [AgentTemplate] {
        let loadedTemplates = BuiltInTemplateAssetCatalog.shared.loadTemplates()
        return loadedTemplates.isEmpty ? bundledSeedTemplates : loadedTemplates
    }

    static var templates: [AgentTemplate] {
        AgentTemplateLibraryStore.shared.templates
    }

    static var categories: [AgentTemplateCategory] {
        AgentTemplateCategory.allCases
    }

    static var families: [AgentTemplateFamily] {
        AgentTemplateFamily.allCases
    }

    static let defaultTemplate: AgentTemplate = template(withID: defaultTemplateID) ?? templates[0]

    static func template(withID id: String) -> AgentTemplate? {
        templates.first { $0.id == id }
    }

    static func templates(in category: AgentTemplateCategory) -> [AgentTemplate] {
        templates.filter { $0.category == category }
    }

    static func categories(in family: AgentTemplateFamily) -> [AgentTemplateCategory] {
        categories.filter { $0.family == family }
    }

    static func templateSummaries(in category: AgentTemplateCategory) -> [(id: String, name: String, summary: String)] {
        templates(in: category).map { ($0.id, $0.name, $0.summary) }
    }

    static func validationIssues(for templateID: String) -> [AgentTemplateValidationIssue] {
        template(withID: templateID)?.validationIssues ?? []
    }

    static func suggestedInputs(for template: AgentTemplate) -> [String] {
        defaultInputs(for: template.category, applicableScenarios: template.applicableScenarios)
    }

    static func suggestedCoreCapabilities(for template: AgentTemplate) -> [String] {
        defaultCoreCapabilities(for: template.name, capabilities: template.capabilities)
    }

    static var invalidTemplateIDs: [String] {
        templates.compactMap { $0.validationIssues.isEmpty ? nil : $0.id }
    }

    private static func template(
        id: String,
        category: AgentTemplateCategory,
        name: String,
        summary: String,
        applicableScenarios: [String],
        identity: String,
        capabilities: [String],
        tags: [String]? = nil,
        colorHex: String,
        role: String,
        mission: String,
        coreCapabilities: [String]? = nil,
        responsibilities: [String],
        workflow: [String],
        inputs: [String]? = nil,
        outputs: [String],
        collaboration: [String],
        guardrails: [String],
        successCriteria: [String]
    ) -> AgentTemplate {
        AgentTemplate(
            meta: AgentTemplateMeta(
                id: id,
                category: category,
                name: name,
                summary: summary,
                applicableScenarios: applicableScenarios,
                identity: identity,
                capabilities: capabilities,
                tags: normalizedItems(tags ?? defaultTags(for: category)),
                colorHex: colorHex,
                sortOrder: 0,
                isRecommended: id == defaultTemplateID
            ),
            soulSpec: AgentTemplateSoulSpec(
                role: role.trimmingCharacters(in: .whitespacesAndNewlines),
                mission: mission.trimmingCharacters(in: .whitespacesAndNewlines),
                coreCapabilities: normalizedItems(coreCapabilities ?? defaultCoreCapabilities(for: name, capabilities: capabilities)),
                responsibilities: normalizedItems(responsibilities),
                workflow: normalizedItems(workflow),
                inputs: normalizedItems(inputs ?? defaultInputs(for: category, applicableScenarios: applicableScenarios)),
                outputs: normalizedItems(outputs),
                collaboration: normalizedItems(collaboration),
                guardrails: normalizedItems(guardrails),
                successCriteria: normalizedItems(successCriteria)
            )
        )
    }

    private static func defaultInputs(for category: AgentTemplateCategory, applicableScenarios: [String]) -> [String] {
        let scenarioHint = applicableScenarios.prefix(2).joined(separator: "、")

        switch category {
        case .productionDocument:
            return [
                "提供任务目标、目标读者、交付格式和截止时间。",
                "提供已有事实材料、数据口径、参考文档与限制条件。",
                scenarioHint.isEmpty ? "输入不足时先补齐范围、优先级和验收标准。" : "当前重点场景包括：\(scenarioHint)。输入不足时先补齐范围和验收标准。"
            ]
        case .productionVideo:
            return [
                "提供视频目标、发布平台、时长要求、受众和风格方向。",
                "提供可用素材、口播信息、品牌限制和导出规格。",
                scenarioHint.isEmpty ? "缺少素材或规格时先确认平台规范、字幕要求和镜头边界。" : "当前重点场景包括：\(scenarioHint)。缺少素材或规格时先确认平台规范和镜头边界。"
            ]
        case .productionCode:
            return [
                "提供需求目标、输入输出、验收标准、技术约束和相关代码上下文。",
                "提供接口约定、依赖关系、兼容性要求和测试范围。",
                scenarioHint.isEmpty ? "边界不清时先确认影响面、回归范围和不可变规则。" : "当前重点场景包括：\(scenarioHint)。边界不清时先确认影响面和回归范围。"
            ]
        case .productionImage:
            return [
                "提供视觉目标、使用场景、画幅比例、尺寸规格和风格偏好。",
                "如涉及图表或流程图，提供数据口径、信息层级和标注要求。",
                scenarioHint.isEmpty ? "缺少规格时先确认输出格式、版式重点和可读性要求。" : "当前重点场景包括：\(scenarioHint)。缺少规格时先确认输出格式和版式重点。"
            ]
        case .functionalLearning:
            return [
                "提供学习主题、目标深度、目标受众、已有材料和时间边界。",
                "如涉及训练或测试，补充待测能力、训练对象、评分标准和通过门槛。",
                scenarioHint.isEmpty ? "如需沉淀知识库或 skill，请补充适用角色、复用边界和更新目标。" : "当前重点场景包括：\(scenarioHint)。如需沉淀知识库或 skill，请补充适用角色和复用边界。"
            ]
        case .functionalSupervision:
            return [
                "提供任务目标、当前状态、待审查结果、验收标准和关键风险。",
                "提供上游上下文、修改历史、阻塞点和需要重点检查的内容。",
                scenarioHint.isEmpty ? "判断不通过或需返工时，必须能追溯到具体证据和目标偏差。" : "当前重点场景包括：\(scenarioHint)。判断返工时必须能追溯到具体证据。"
            ]
        case .functionalOpsManagement:
            return [
                "提供任务范围、运行背景、关键链路、时间窗口、当前状态和管理目标。",
                "如涉及日志、记忆或派发治理，提供样本口径、异常定义、保留策略和需要定位的问题类型。",
                scenarioHint.isEmpty ? "如需归责、派发或整理记忆，先统一证据标准、责任边界和保留规则。" : "当前重点场景包括：\(scenarioHint)。如需归责、派发或整理记忆，先统一证据标准和责任边界。"
            ]
        case .functionalHumanResources:
            return [
                "提供任务规模、角色分布、负载情况、阻塞点和领域边界。",
                "提供现有工作流、交接方式、资源限制和需要优化的效率问题。",
                scenarioHint.isEmpty ? "涉及招人、并行或隔离时，需说明当前缺口是能力、容量还是流程。" : "当前重点场景包括：\(scenarioHint)。涉及招人或并行时，需先说明缺口来源。"
            ]
        }
    }

    private static func defaultCoreCapabilities(for name: String, capabilities: [String]) -> [String] {
        let mapped = capabilities.compactMap { capabilityLabelMap[$0.lowercased()] }
        if !mapped.isEmpty {
            return Array(mapped.prefix(4))
        }

        return [
            "\(name) 相关任务理解",
            "结构化执行与交付",
            "边界判断与质量自检"
        ]
    }

    private static func defaultTags(for category: AgentTemplateCategory) -> [String] {
        switch category {
        case .functionalLearning:
            return ["知识建设", "训练测试"]
        case .functionalSupervision:
            return ["监督推进", "审查评估"]
        case .functionalOpsManagement:
            return ["运维治理", "过程管理"]
        case .functionalHumanResources:
            return ["人力配置", "组织设计"]
        case .productionDocument:
            return ["文档交付", "结构化表达"]
        case .productionVideo:
            return ["视频交付", "脚本剪辑"]
        case .productionCode:
            return ["代码交付", "工程实现"]
        case .productionImage:
            return ["图片交付", "视觉表达"]
        }
    }

    private static func normalizedItems(_ items: [String]) -> [String] {
        items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static let capabilityLabelMap: [String: String] = [
        "writing": "结构化写作与文档表达",
        "editing": "内容校对与语言润色",
        "structure": "信息结构设计与整理",
        "summarization": "重点提炼与摘要压缩",
        "implementation": "代码实现与需求落地",
        "debugging": "问题定位与缺陷修复",
        "testing": "验证设计与结果确认",
        "refactoring": "重构整理与可维护性优化",
        "analysis": "问题分析与结论提炼",
        "statistics": "统计口径判断与数据解读",
        "visualization": "分析结果表达与图表化",
        "visual-design": "视觉结构设计",
        "layout": "版式组织与信息排布",
        "charting": "图表规划与展示",
        "organization": "资料组织与结构梳理",
        "trend-analysis": "热点追踪与趋势判断",
        "ideation": "创意发散与方向生成",
        "brainstorming": "多方案头脑风暴",
        "coordination": "跨角色协作与推进",
        "planning": "计划制定与节奏控制",
        "tracking": "进度跟踪与状态同步",
        "communication": "沟通协调与对齐",
        "dispatching": "任务分派与负载匹配",
        "prioritization": "优先级判断",
        "aggregation": "多结果汇总与归并",
        "reporting": "结果汇报与对外表达",
        "review": "监督审查与问题识别",
        "verification": "事实核对与正确性判断",
        "quality-control": "质量把关与标准执行",
        "risk-check": "风险识别与阻断",
        "monitoring": "执行过程监控",
        "question-answering": "澄清支持与问题响应",
        "blocking": "阻塞识别与解除",
        "clarification": "需求澄清与边界追问",
        "feedback": "反馈给出与方向修正",
        "acceptance": "验收判断",
        "role-play": "用户视角模拟",
        "reflection": "复盘升级与策略调整",
        "architecture-review": "架构审视与调整建议",
        "adaptation": "执行反馈驱动调整",
        "log-analysis": "日志解析与异常归因",
        "forensics": "问题取证与链路定位",
        "benchmarking": "能力对比与基准评估",
        "diagnostics": "系统诊断与问题归类",
        "learning": "学习组织与知识吸收",
        "curriculum-design": "训练路径设计",
        "assessment": "能力评估与差距判断",
        "training": "训练执行与复盘",
        "skill-design": "技能沉淀与模块设计",
        "knowledge-packaging": "经验结构化封装",
        "specialization": "专业化能力建设",
        "workflow-standardization": "标准流程抽象",
        "scoring": "评分标准制定",
        "evaluation": "测试结果评估",
        "administration": "日常事务处理",
        "scheduling": "提醒与日程安排",
        "chat": "轻量沟通与接待",
        "memory": "上下文整理与记忆维护",
        "retrieval": "检索线索设计",
        "staffing": "角色招聘与配置",
        "workflow-design": "工作流设计与优化",
        "parallelization": "并行路径规划",
        "isolation-planning": "领域隔离方案设计",
        "scriptwriting": "视频脚本设计",
        "storyboarding": "分镜规划",
        "media-production": "视频交付组织"
    ]
}

extension AgentTemplate {
    func withSortOrder(_ sortOrder: Int) -> AgentTemplate {
        var copy = self
        copy.meta.sortOrder = sortOrder
        return copy
    }

    func withRecommended(_ isRecommended: Bool) -> AgentTemplate {
        var copy = self
        copy.meta.isRecommended = isRecommended
        return copy
    }

    func sanitizedForPersistence() -> AgentTemplate {
        var copy = self
        copy.meta.id = copy.id.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.meta.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.meta.summary = copy.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.meta.identity = copy.identity.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.meta.applicableScenarios = copy.applicableScenarios
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        copy.meta.capabilities = copy.capabilities
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        copy.meta.tags = copy.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let trimmedColorHex = copy.colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.meta.colorHex = trimmedColorHex.isEmpty ? copy.category.defaultColorHex : trimmedColorHex
        copy.soulSpec.role = copy.soulSpec.role.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.soulSpec.mission = copy.soulSpec.mission.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.soulSpec.coreCapabilities = copy.soulSpec.coreCapabilities
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        copy.soulSpec.responsibilities = copy.soulSpec.responsibilities
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        copy.soulSpec.workflow = copy.soulSpec.workflow
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        copy.soulSpec.inputs = copy.soulSpec.inputs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        copy.soulSpec.outputs = copy.soulSpec.outputs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        copy.soulSpec.collaboration = copy.soulSpec.collaboration
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        copy.soulSpec.guardrails = copy.soulSpec.guardrails
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        copy.soulSpec.successCriteria = copy.soulSpec.successCriteria
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return copy
    }
}

extension Agent {
    mutating func apply(template: AgentTemplate) {
        identity = template.identity
        description = template.summary
        soulMD = template.soulMD
        capabilities = template.capabilities
        colorHex = template.colorHex
    }
}
