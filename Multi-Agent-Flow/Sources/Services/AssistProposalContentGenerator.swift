import Foundation

struct AssistGeneratedProposalContent {
    var textMutationPlan: AssistTextMutationPlan?

    init(
        textMutationPlan: AssistTextMutationPlan? = nil
    ) {
        self.textMutationPlan = textMutationPlan
    }
}

protocol AssistProposalContentGenerator {
    func generate(
        input: AssistSubmissionInput,
        request: AssistRequest,
        contextPack: AssistContextPack
    ) async throws -> AssistGeneratedProposalContent?
}

struct NoopAssistProposalContentGenerator: AssistProposalContentGenerator {
    func generate(
        input: AssistSubmissionInput,
        request: AssistRequest,
        contextPack: AssistContextPack
    ) async throws -> AssistGeneratedProposalContent? {
        nil
    }
}

enum AssistProposalContentGeneratorError: LocalizedError {
    case gatewayUnavailable
    case invalidResponse
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .gatewayUnavailable:
            return "Assist could not reach an available OpenClaw gateway for proposal generation."
        case .invalidResponse:
            return "Assist received an invalid structured response while generating the proposal."
        case .emptyResult:
            return "Assist did not receive usable content for this proposal."
        }
    }
}

final class GatewayAssistProposalContentGenerator: AssistProposalContentGenerator {
    private let openClawManager: OpenClawManager

    init(
        openClawManager: OpenClawManager
    ) {
        self.openClawManager = openClawManager
    }

    func generate(
        input: AssistSubmissionInput,
        request: AssistRequest,
        contextPack: AssistContextPack
    ) async throws -> AssistGeneratedProposalContent? {
        guard shouldGenerateTextMutationPlan(for: input, request: request) else {
            return nil
        }

        let connectionConfig = openClawManager.config
        guard let gatewayConfig = openClawManager.preferredGatewayConfig(using: connectionConfig) else {
            throw AssistProposalContentGeneratorError.gatewayUnavailable
        }

        let prompt = generationPrompt(
            input: input,
            request: request,
            contextPack: contextPack
        )
        let result = try await openClawManager.executeGatewayChatCommand(
            message: prompt,
            sessionKey: generationSessionKey(for: request.id),
            thinkingLevel: .off,
            timeoutSeconds: 120,
            using: gatewayConfig,
            onAssistantTextUpdated: { _ in }
        )

        let payload = try decodeResponsePayload(from: result.assistantText)
        let normalizedContent = payload.updatedContent.trimmingCharacters(in: .newlines)

        guard payload.updatedContent.isEmpty == false || (input.fileContent?.isEmpty ?? true) == false else {
            throw AssistProposalContentGeneratorError.emptyResult
        }

        let plan = AssistTextMutationPlan(
            relativeFilePath: input.relativeFilePath ?? request.scopeRef.relativeFilePath ?? "unknown",
            workspaceSurface: .draft,
            templateID: input.additionalMetadata["templateID"],
            templateName: input.additionalMetadata["templateName"],
            sourceDidExist: input.fileContent != nil,
            sourceContent: input.fileContent,
            resultingContent: normalizedContent.isEmpty ? payload.updatedContent : normalizedContent,
            summary: normalizedValue(payload.summary),
            rationale: normalizedValue(payload.rationale),
            warnings: payload.warnings.compactMap(normalizedValue)
        )

        return AssistGeneratedProposalContent(textMutationPlan: plan)
    }

    private func shouldGenerateTextMutationPlan(
        for input: AssistSubmissionInput,
        request: AssistRequest
    ) -> Bool {
        guard input.additionalMetadata["entrySurface"] == "template_workspace" else {
            return false
        }
        guard request.scopeType == .file,
              request.scopeRef.workspaceSurface == .draft else {
            return false
        }
        guard request.scopeRef.relativeFilePath?.isEmpty == false else {
            return false
        }
        switch request.intent {
        case .rewriteSelection, .completeTemplate, .modifyManagedContent, .custom:
            return true
        case .reorganizeWorkflow, .inspectConfiguration, .inspectPerformance, .explainIssue:
            return false
        }
    }

    private func generationSessionKey(
        for requestID: String
    ) -> String {
        "assist-proposal-\(requestID)"
    }

    private func generationPrompt(
        input: AssistSubmissionInput,
        request: AssistRequest,
        contextPack: AssistContextPack
    ) -> String {
        let relativeFilePath = request.scopeRef.relativeFilePath ?? input.relativeFilePath ?? "unknown"
        let templateName = input.additionalMetadata["templateName"] ?? "unknown template"
        let templateID = input.additionalMetadata["templateID"] ?? "unknown"
        let templateIdentity = input.additionalMetadata["templateIdentity"] ?? ""
        let templateTaxonomy = input.additionalMetadata["templateTaxonomy"] ?? ""
        let currentContent = input.fileContent ?? ""
        let filePresence = input.fileContent == nil ? "missing" : "present"
        let contextTitles = contextPack.entries.map(\.title).joined(separator: ", ")
        let sourceSummary = currentContent.isEmpty
            ? "(file is currently empty or missing)"
            : currentContent

        return """
        You are generating a structured Assist proposal for an internal desktop application.

        Return exactly one JSON object and nothing else.
        Do not use Markdown.
        Do not wrap the JSON in code fences.

        JSON schema:
        {"summary":"short summary","rationale":"short rationale","updatedContent":"full resulting file content","warnings":["optional warning"]}

        Rules:
        - `updatedContent` must contain the full final file content, not a diff and not an excerpt.
        - Keep the file format valid for its path.
        - Preserve the existing language unless the user explicitly asks to change it.
        - Stay within the current file only.
        - If the file is currently missing, generate the full file body that best fits the template context.
        - If the user's request is mostly diagnostic, keep the content conservative and avoid unnecessary rewrites.
        - `summary` and `rationale` must be concise.

        Request:
        - Intent: \(request.intent.rawValue)
        - Prompt: \(request.prompt)
        - File: \(relativeFilePath)
        - File Presence: \(filePresence)

        Template Context:
        - Template Name: \(templateName)
        - Template ID: \(templateID)
        - Template Identity: \(templateIdentity.isEmpty ? "(none)" : templateIdentity)
        - Template Taxonomy: \(templateTaxonomy.isEmpty ? "(none)" : templateTaxonomy)
        - Context Entries: \(contextTitles.isEmpty ? "(none)" : contextTitles)

        Current File Content:
        <<<CURRENT_FILE
        \(sourceSummary)
        CURRENT_FILE

        Produce the JSON now.
        """
    }

    private func decodeResponsePayload(
        from rawText: String
    ) throws -> GeneratedFileEditPayload {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AssistProposalContentGeneratorError.emptyResult
        }

        if let payload = decodePayload(from: trimmed) {
            return payload
        }

        guard let firstBrace = trimmed.firstIndex(of: "{"),
              let lastBrace = trimmed.lastIndex(of: "}") else {
            throw AssistProposalContentGeneratorError.invalidResponse
        }

        let candidate = String(trimmed[firstBrace...lastBrace])
        if let payload = decodePayload(from: candidate) {
            return payload
        }

        throw AssistProposalContentGeneratorError.invalidResponse
    }

    private func decodePayload(
        from text: String
    ) -> GeneratedFileEditPayload? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(GeneratedFileEditPayload.self, from: data)
    }

    private func normalizedValue(
        _ value: String?
    ) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct GeneratedFileEditPayload: Decodable {
    var summary: String?
    var rationale: String?
    var updatedContent: String
    var warnings: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        rationale = try container.decodeIfPresent(String.self, forKey: .rationale)
        updatedContent = try container.decode(String.self, forKey: .updatedContent)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case summary
        case rationale
        case updatedContent
        case warnings
    }
}
