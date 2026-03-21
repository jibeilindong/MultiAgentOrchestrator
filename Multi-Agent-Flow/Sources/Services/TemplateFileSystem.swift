//
//  TemplateFileSystem.swift
//  Multi-Agent-Flow
//
//  Created by Codex on 2026/3/22.
//

import Foundation

struct TemplateFileSystem {
    static let shared = TemplateFileSystem()

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        self.decoder = decoder
    }

    func templateLibraryRootDirectory(under appSupportRootDirectory: URL) -> URL {
        appSupportRootDirectory
            .appendingPathComponent("Libraries", isDirectory: true)
            .appendingPathComponent("Templates", isDirectory: true)
    }

    func templateManifestURL(under appSupportRootDirectory: URL) -> URL {
        templateLibraryRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("manifest.json", isDirectory: false)
    }

    func templatePreferencesURL(under appSupportRootDirectory: URL) -> URL {
        templateLibraryRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("preferences.json", isDirectory: false)
    }

    func templateIndexesRootDirectory(under appSupportRootDirectory: URL) -> URL {
        templateLibraryRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent("Indexes", isDirectory: true)
    }

    func templateRootDirectory(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateLibraryRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent(templateID, isDirectory: true)
    }

    func templateDocumentURL(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("template.json", isDirectory: false)
    }

    func templateSoulURL(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("SOUL.md", isDirectory: false)
    }

    func templateAgentsURL(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("AGENTS.md", isDirectory: false)
    }

    func templateIdentityURL(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("IDENTITY.md", isDirectory: false)
    }

    func templateUserURL(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("USER.md", isDirectory: false)
    }

    func templateToolsURL(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("TOOLS.md", isDirectory: false)
    }

    func templateBootstrapURL(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("BOOTSTRAP.md", isDirectory: false)
    }

    func templateHeartbeatURL(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("HEARTBEAT.md", isDirectory: false)
    }

    func templateMemoryURL(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("MEMORY.md", isDirectory: false)
    }

    func templateLineageURL(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("lineage.json", isDirectory: false)
    }

    func templateRevisionDirectory(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("revisions", isDirectory: true)
    }

    func templateRevisionURL(
        for templateID: String,
        revision: Int,
        under appSupportRootDirectory: URL
    ) -> URL {
        templateRevisionDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent(String(format: "r%04d.json", revision), isDirectory: false)
    }

    func templateExtensionsRootDirectory(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("extensions", isDirectory: true)
    }

    func templateExtensionsReadmeURL(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateExtensionsRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("README.md", isDirectory: false)
    }

    func templateExamplesRootDirectory(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateExtensionsRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("examples", isDirectory: true)
    }

    func templateExamplesReadmeURL(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateExamplesRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("README.md", isDirectory: false)
    }

    func templateExamplePromptURL(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateExamplesRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("default-prompt.md", isDirectory: false)
    }

    func templateTestsRootDirectory(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateExtensionsRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("tests", isDirectory: true)
    }

    func templateTestsReadmeURL(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateTestsRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("README.md", isDirectory: false)
    }

    func templateAcceptanceChecklistURL(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateTestsRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("acceptance-checklist.md", isDirectory: false)
    }

    func templateAssetsRootDirectory(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateExtensionsRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("assets", isDirectory: true)
    }

    func templateAssetsReadmeURL(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateAssetsRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("README.md", isDirectory: false)
    }

    func templateAssetsManifestURL(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateAssetsRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("asset-manifest.md", isDirectory: false)
    }

    func ensureBaseDirectories(under appSupportRootDirectory: URL) throws {
        try fileManager.createDirectory(
            at: templateLibraryRootDirectory(under: appSupportRootDirectory),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: templateIndexesRootDirectory(under: appSupportRootDirectory),
            withIntermediateDirectories: true
        )
    }

    func ensureTemplateScaffold(for templateID: String, under appSupportRootDirectory: URL) throws {
        try ensureBaseDirectories(under: appSupportRootDirectory)

        let rootURL = templateRootDirectory(for: templateID, under: appSupportRootDirectory)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: templateRevisionDirectory(for: templateID, under: appSupportRootDirectory),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: templateExamplesRootDirectory(for: templateID, under: appSupportRootDirectory),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: templateTestsRootDirectory(for: templateID, under: appSupportRootDirectory),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: templateAssetsRootDirectory(for: templateID, under: appSupportRootDirectory),
            withIntermediateDirectories: true
        )

        let readmeURL = templateExtensionsReadmeURL(for: templateID, under: appSupportRootDirectory)
        if !fileManager.fileExists(atPath: readmeURL.path) {
            try writeTextDocument(
                """
                # Template Extensions

                This directory stores the secondary development materials for the template package.

                - `examples/`: sample prompts or usage examples
                - `tests/`: validation fixtures or test cases
                - `assets/`: supporting files bundled with the template
                """,
                to: readmeURL
            )
        }
    }

    func loadManifest(under appSupportRootDirectory: URL) -> TemplateLibraryManifest? {
        load(TemplateLibraryManifest.self, from: templateManifestURL(under: appSupportRootDirectory))
    }

    func saveManifest(_ manifest: TemplateLibraryManifest, under appSupportRootDirectory: URL) throws {
        try ensureBaseDirectories(under: appSupportRootDirectory)
        try encode(manifest, to: templateManifestURL(under: appSupportRootDirectory))
    }

    func loadPreferences(under appSupportRootDirectory: URL) -> TemplateLibraryPreferences? {
        load(TemplateLibraryPreferences.self, from: templatePreferencesURL(under: appSupportRootDirectory))
    }

    func savePreferences(_ preferences: TemplateLibraryPreferences, under appSupportRootDirectory: URL) throws {
        try ensureBaseDirectories(under: appSupportRootDirectory)
        try encode(preferences, to: templatePreferencesURL(under: appSupportRootDirectory))
    }

    func listTemplateAssetIDs(under appSupportRootDirectory: URL) -> [String] {
        let rootURL = templateLibraryRootDirectory(under: appSupportRootDirectory)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { url in
            guard url.lastPathComponent != "Indexes" else { return nil }

            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { return nil }
            return url.lastPathComponent
        }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func isTemplateAssetDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        guard values?.isDirectory == true else { return false }
        return fileManager.fileExists(
            atPath: url.appendingPathComponent("template.json", isDirectory: false).path
        )
    }

    func resolvedTemplateAssetDirectories(from urls: [URL]) -> [URL] {
        var results: [URL] = []
        var seen = Set<String>()

        for url in urls {
            let standardizedURL = url.standardizedFileURL
            if isTemplateAssetDirectory(standardizedURL) {
                if seen.insert(standardizedURL.path).inserted {
                    results.append(standardizedURL)
                }
                continue
            }

            let values = try? standardizedURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }

            let children = (try? fileManager.contentsOfDirectory(
                at: standardizedURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for childURL in children where isTemplateAssetDirectory(childURL) {
                let standardizedChildURL = childURL.standardizedFileURL
                guard seen.insert(standardizedChildURL.path).inserted else { continue }
                results.append(standardizedChildURL)
            }
        }

        return results.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    func loadTemplateDocument(for templateID: String, under appSupportRootDirectory: URL) -> TemplateAssetDocument? {
        load(TemplateAssetDocument.self, from: templateDocumentURL(for: templateID, under: appSupportRootDirectory))
    }

    func loadTemplateLineage(for templateID: String, under appSupportRootDirectory: URL) -> TemplateLineage? {
        load(TemplateLineage.self, from: templateLineageURL(for: templateID, under: appSupportRootDirectory))
    }

    func loadTemplateDocument(at templateRootDirectory: URL) -> TemplateAssetDocument? {
        load(
            TemplateAssetDocument.self,
            from: templateRootDirectory.appendingPathComponent("template.json", isDirectory: false)
        )
    }

    func loadTemplateLineage(at templateRootDirectory: URL) -> TemplateLineage? {
        load(
            TemplateLineage.self,
            from: templateRootDirectory.appendingPathComponent("lineage.json", isDirectory: false)
        )
    }

    func writeTemplateAsset(
        document: TemplateAssetDocument,
        lineage: TemplateLineage,
        under appSupportRootDirectory: URL
    ) throws {
        let template = document.asTemplate()
        try ensureTemplateScaffold(for: document.id, under: appSupportRootDirectory)

        try encode(document, to: templateDocumentURL(for: document.id, under: appSupportRootDirectory))
        try encode(lineage, to: templateLineageURL(for: document.id, under: appSupportRootDirectory))
        try encode(
            document,
            to: templateRevisionURL(for: document.id, revision: document.revision, under: appSupportRootDirectory)
        )

        try writeTextDocument(template.soulMD, to: templateSoulURL(for: document.id, under: appSupportRootDirectory))
        try writeTextDocument(
            renderAgentsMarkdown(template: template, document: document),
            to: templateAgentsURL(for: document.id, under: appSupportRootDirectory)
        )
        try writeTextDocument(
            renderIdentityMarkdown(template: template),
            to: templateIdentityURL(for: document.id, under: appSupportRootDirectory)
        )
        try writeTextDocument(
            renderUserMarkdown(template: template),
            to: templateUserURL(for: document.id, under: appSupportRootDirectory)
        )
        try writeTextDocument(
            renderToolsMarkdown(template: template),
            to: templateToolsURL(for: document.id, under: appSupportRootDirectory)
        )
        try writeTextDocument(
            renderBootstrapMarkdown(template: template),
            to: templateBootstrapURL(for: document.id, under: appSupportRootDirectory)
        )
        try writeTextDocument(
            renderHeartbeatMarkdown(),
            to: templateHeartbeatURL(for: document.id, under: appSupportRootDirectory)
        )
        try writeTextDocument(
            renderMemoryMarkdown(),
            to: templateMemoryURL(for: document.id, under: appSupportRootDirectory)
        )
        try writeTextDocument(
            renderExamplesReadmeMarkdown(template: template),
            to: templateExamplesReadmeURL(for: document.id, under: appSupportRootDirectory)
        )
        try writeTextDocument(
            renderExamplePromptMarkdown(template: template),
            to: templateExamplePromptURL(for: document.id, under: appSupportRootDirectory)
        )
        try writeTextDocument(
            renderTestsReadmeMarkdown(template: template),
            to: templateTestsReadmeURL(for: document.id, under: appSupportRootDirectory)
        )
        try writeTextDocument(
            renderAcceptanceChecklistMarkdown(template: template),
            to: templateAcceptanceChecklistURL(for: document.id, under: appSupportRootDirectory)
        )
        try writeTextDocument(
            renderAssetsReadmeMarkdown(template: template),
            to: templateAssetsReadmeURL(for: document.id, under: appSupportRootDirectory)
        )
        try writeTextDocument(
            renderAssetManifestMarkdown(template: template, document: document),
            to: templateAssetsManifestURL(for: document.id, under: appSupportRootDirectory)
        )
    }

    func removeTemplateAsset(for templateID: String, under appSupportRootDirectory: URL) throws {
        let rootURL = templateRootDirectory(for: templateID, under: appSupportRootDirectory)
        guard fileManager.fileExists(atPath: rootURL.path) else { return }
        try fileManager.removeItem(at: rootURL)
    }

    func copyTemplateAssetDirectory(
        from sourceRootDirectory: URL,
        toTemplateID templateID: String,
        under appSupportRootDirectory: URL
    ) throws -> URL {
        try ensureBaseDirectories(under: appSupportRootDirectory)
        let destinationURL = templateRootDirectory(for: templateID, under: appSupportRootDirectory)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceRootDirectory, to: destinationURL)
        return destinationURL
    }

    func exportTemplateAssetDirectory(
        for templateID: String,
        under appSupportRootDirectory: URL,
        to destinationDirectory: URL,
        destinationFolderName: String? = nil
    ) throws -> URL {
        let sourceURL = templateRootDirectory(for: templateID, under: appSupportRootDirectory)
        let baseName = (destinationFolderName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? destinationFolderName!
            : templateID
        let destinationURL = uniqueDirectoryURL(named: baseName, in: destinationDirectory)
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) throws {
        let directoryURL = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func writeTextDocument(_ text: String, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func uniqueDirectoryURL(named preferredName: String, in parentDirectory: URL) -> URL {
        let trimmed = preferredName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? "template-asset" : trimmed
        var candidateURL = parentDirectory.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2

        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateURL = parentDirectory.appendingPathComponent("\(baseName)-\(suffix)", isDirectory: true)
            suffix += 1
        }

        return candidateURL
    }

    private func renderAgentsMarkdown(template: AgentTemplate, document: TemplateAssetDocument) -> String {
        let scenarios = markdownBulletList(
            template.applicableScenarios,
            fallback: "This template can be applied wherever the declared role and mission are a fit."
        )
        let capabilities = markdownBulletList(
            template.soulSpec.coreCapabilities,
            fallback: "No capability description recorded."
        )
        let responsibilities = markdownBulletList(
            template.soulSpec.responsibilities,
            fallback: "No responsibility list recorded."
        )
        let workflow = markdownNumberedList(
            template.soulSpec.workflow,
            fallback: "1. Clarify the task.\n2. Execute the work.\n3. Review the result."
        )
        let inputs = markdownBulletList(
            template.soulSpec.inputs,
            fallback: "No input contract recorded."
        )
        let outputs = markdownBulletList(
            template.soulSpec.outputs,
            fallback: "No output contract recorded."
        )
        let collaboration = markdownBulletList(
            template.soulSpec.collaboration,
            fallback: "No collaboration contract recorded."
        )
        let guardrails = markdownBulletList(
            template.soulSpec.guardrails,
            fallback: "No guardrail list recorded."
        )
        let successCriteria = markdownBulletList(
            template.soulSpec.successCriteria,
            fallback: "No success criteria recorded."
        )

        return """
        # AGENTS

        - package_type: agent-template
        - display_name: \(template.name)
        - template_id: \(document.id)
        - revision: r\(document.revision)
        - status: \(document.status.rawValue)
        - category: \(template.category.rawValue)
        - family: \(template.family.rawValue)
        - identity: \(normalizedOrPlaceholder(template.identity))

        ## Package Summary
        \(normalizedOrPlaceholder(template.summary, fallback: "No summary recorded."))

        ## Recommended Scenarios
        \(scenarios)

        ## Core Capabilities
        \(capabilities)

        ## Responsibilities
        \(responsibilities)

        ## Workflow
        \(workflow)

        ## Input Contract
        \(inputs)

        ## Output Contract
        \(outputs)

        ## Collaboration Contract
        \(collaboration)

        ## Guardrails
        \(guardrails)

        ## Success Criteria
        \(successCriteria)

        ## Included Files
        - template.json
        - SOUL.md
        - AGENTS.md
        - IDENTITY.md
        - USER.md
        - TOOLS.md
        - BOOTSTRAP.md
        - HEARTBEAT.md
        - MEMORY.md
        - lineage.json
        - extensions/examples/default-prompt.md
        - extensions/tests/acceptance-checklist.md
        - extensions/assets/asset-manifest.md
        """
    }

    private func renderIdentityMarkdown(template: AgentTemplate) -> String {
        let capabilitySummary = markdownBulletList(
            template.soulSpec.coreCapabilities,
            fallback: normalizedOrPlaceholder(template.summary)
        )
        let posture = markdownBulletList(
            Array(template.soulSpec.guardrails.prefix(3)),
            fallback: "Operate with the declared role discipline and stay within the assigned scope."
        )

        return """
        # IDENTITY

        Identity: \(normalizedOrPlaceholder(template.identity))
        Display Name: \(template.name)
        Family: \(template.family.rawValue)
        Category: \(template.category.rawValue)
        Template ID: \(template.id)

        ## Role Summary
        \(normalizedOrPlaceholder(template.soulSpec.role))

        ## Mission
        \(normalizedOrPlaceholder(template.soulSpec.mission))

        ## Capability Signature
        \(capabilitySummary)

        ## Operating Posture
        \(posture)
        """
    }

    private func renderUserMarkdown(template: AgentTemplate) -> String {
        let scenarios = template.applicableScenarios.isEmpty
            ? "- No specific scenarios recorded."
            : template.applicableScenarios.map { "- \($0)" }.joined(separator: "\n")
        let briefingChecklist = markdownBulletList(
            template.soulSpec.inputs,
            fallback: "Clarify goal, scope, constraints, and acceptance criteria before invocation."
        )
        let deliverables = markdownBulletList(
            template.soulSpec.outputs,
            fallback: "Produce a directly usable result and the supporting notes required for handoff."
        )
        let boundaries = markdownBulletList(
            template.soulSpec.guardrails,
            fallback: "Do not exceed the role boundary declared by the template."
        )

        return """
        # USER

        \(normalizedOrPlaceholder(template.summary, fallback: "No user-facing description recorded."))

        ## Applicable Scenarios
        \(scenarios)

        ## Briefing Checklist
        \(briefingChecklist)

        ## Expected Deliverables
        \(deliverables)

        ## Usage Boundaries
        \(boundaries)
        """
    }

    private func renderToolsMarkdown(template: AgentTemplate) -> String {
        let capabilities = template.capabilities.isEmpty
            ? "- none"
            : template.capabilities.sorted().map { "- \($0)" }.joined(separator: "\n")
        let operatingNotes = markdownBulletList(
            toolingNotes(for: template.category),
            fallback: "Use only the tools necessary for the assigned task."
        )
        let reviewChecklist = markdownBulletList(
            Array(template.soulSpec.successCriteria.prefix(3)),
            fallback: "Check correctness, completeness, and handoff readiness before finishing."
        )

        return """
        # TOOLS

        Model: MiniMax-M2.5
        Runtime Profile: default

        ## Capabilities
        \(capabilities)

        ## Operating Notes
        \(operatingNotes)

        ## Review Checklist
        \(reviewChecklist)
        """
    }

    private func renderBootstrapMarkdown(template: AgentTemplate) -> String {
        let identifier = template.identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? template.name
            : template.identity
        let startupChecklist = markdownNumberedList(
            [
                "Read `SOUL.md` and align on role, mission, workflow, and boundaries.",
                "Check `USER.md` to confirm the invocation contract and the expected deliverables.",
                "Check `TOOLS.md` and determine whether the available tools match the task.",
                "Check `MEMORY.md` and `HEARTBEAT.md` to align on continuity and self-review rules.",
                "Before execution, restate the goal, assumptions, risks, and completion criteria."
            ],
            fallback: "1. Read the package files.\n2. Confirm the task.\n3. Start execution."
        )

        return """
        # BOOTSTRAP

        Agent Identifier: \(normalizedOrPlaceholder(identifier))
        Model Identifier: MiniMax-M2.5
        Runtime Profile: default
        Soul Source Path: workspace/SOUL.md

        ## Startup Checklist
        \(startupChecklist)
        """
    }

    private func renderHeartbeatMarkdown() -> String {
        let memory = OpenClawAgentProtocolMemory()
        let cadence = markdownBulletList(
            [
                "After every meaningful step, compare the current result against the task goal and declared output contract.",
                "When new constraints appear, update the working assumptions before continuing.",
                "Before handoff, review correctness, completeness, risk disclosure, and next-step clarity."
            ],
            fallback: "Maintain a steady self-review loop."
        )

        return """
        # HEARTBEAT

        Protocol Version: \(memory.protocolVersion)
        Last Updated: \(iso8601String(from: memory.lastUpdatedAt))
        Recent Corrections: \(memory.recentCorrections.count)
        Repeat Offenses: \(memory.repeatOffenses.count)

        ## Review Cadence
        \(cadence)
        """
    }

    private func renderMemoryMarkdown() -> String {
        let memory = OpenClawAgentProtocolMemory()
        let stableRules = memory.stableRules.isEmpty
            ? "- none"
            : memory.stableRules.map { "- \($0)" }.joined(separator: "\n")

        return """
        # MEMORY

        Memory Backup Path: Not recorded.
        Last Session Digest: Not recorded.

        ## Stable Rules
        \(stableRules)
        """
    }

    private func renderExamplesReadmeMarkdown(template: AgentTemplate) -> String {
        """
        # Examples

        This directory stores example prompts and invocation materials for `\(template.name)`.

        - `default-prompt.md`: a standard invocation example aligned with the template contract
        - add more files here when extending the template for a specialized domain
        """
    }

    private func renderExamplePromptMarkdown(template: AgentTemplate) -> String {
        let scenarios = template.applicableScenarios.prefix(3).map { "- \($0)" }.joined(separator: "\n")
        let scenarioBlock = scenarios.isEmpty ? "- Use any task that matches the role and mission." : scenarios
        let inputs = markdownBulletList(
            template.soulSpec.inputs,
            fallback: "State the objective, context, constraints, and expected output."
        )
        let outputs = markdownBulletList(
            template.soulSpec.outputs,
            fallback: "Produce a directly usable result plus assumptions and next steps."
        )

        return """
        # Default Prompt Example

        ## Suitable Scenarios
        \(scenarioBlock)

        ## Suggested User Brief
        - 请你以 `\(template.name)` 模板执行当前任务。
        - 目标：补充本次任务的明确业务目标、交付边界和验收标准。
        - 背景：补充已知事实、上游上下文、输入材料与限制。
        - 输出要求：输出结构化结果，并显式标注假设、风险和下一步动作。

        ## Expected Inputs
        \(inputs)

        ## Expected Outputs
        \(outputs)
        """
    }

    private func renderTestsReadmeMarkdown(template: AgentTemplate) -> String {
        """
        # Tests

        This directory stores acceptance and regression materials for `\(template.name)`.

        - `acceptance-checklist.md`: baseline review checklist for the template output
        - add scenario-specific fixtures here when the template is extended
        """
    }

    private func renderAcceptanceChecklistMarkdown(template: AgentTemplate) -> String {
        let criteria = markdownBulletList(
            template.soulSpec.successCriteria,
            fallback: "Check that the result is correct, complete, and easy to continue."
        )
        let guardrails = markdownBulletList(
            template.soulSpec.guardrails,
            fallback: "Check that the result stays inside the declared role boundary."
        )

        return """
        # Acceptance Checklist

        ## Success Criteria
        \(criteria)

        ## Guardrail Verification
        \(guardrails)

        ## Reviewer Prompts
        - Is the output aligned with the declared role, mission, and scenario?
        - Are the critical inputs, assumptions, and constraints explicitly reflected?
        - Is the result directly usable without guessing hidden context?
        - Are risks, limitations, and next steps clearly called out?
        """
    }

    private func renderAssetsReadmeMarkdown(template: AgentTemplate) -> String {
        """
        # Assets

        This directory stores bundled support assets for `\(template.name)`.

        By default it contains a manifest file describing the current package state.
        Add static references, fixtures, or domain-specific materials here during secondary development.
        """
    }

    private func renderAssetManifestMarkdown(template: AgentTemplate, document: TemplateAssetDocument) -> String {
        let tags = markdownBulletList(
            template.tags,
            fallback: "No tags recorded."
        )

        return """
        # Asset Manifest

        - template_id: \(template.id)
        - display_name: \(template.name)
        - revision: r\(document.revision)
        - status: \(document.status.rawValue)
        - category: \(template.category.rawValue)

        ## Tags
        \(tags)

        ## Current Bundled Assets
        - README.md
        - asset-manifest.md

        ## Secondary Development Notes
        - Add any binary or static reference files here.
        - Keep filenames stable so downstream sharing and export remain predictable.
        - Do not place workflow runtime state in this directory.
        """
    }

    private func toolingNotes(for category: AgentTemplateCategory) -> [String] {
        switch category {
        case .productionCode:
            return [
                "Read the existing codebase and conventions before editing.",
                "Prefer minimal, verifiable changes with explicit validation steps.",
                "Call out any unrun tests, uncertain dependencies, or migration impact."
            ]
        case .productionDocument:
            return [
                "Keep the structure readable and audience-aware.",
                "Separate facts, assumptions, and recommendations.",
                "Preserve terminology consistency across the final deliverable."
            ]
        case .productionVideo:
            return [
                "Respect platform constraints such as duration, ratio, and subtitle format.",
                "Keep script, shot list, and edit instructions aligned.",
                "Record asset or licensing assumptions when source material is incomplete."
            ]
        case .productionImage:
            return [
                "Prioritize information clarity over decoration.",
                "Keep labels, legends, and hierarchy explicit.",
                "Check that visual proposals stay consistent with data or factual inputs."
            ]
        case .functionalLogAnalysis:
            return [
                "Base conclusions on evidence that can be traced back to logs or artifacts.",
                "Separate anomaly description, suspected cause, and confirmed cause.",
                "Avoid over-generalizing from one-off failures."
            ]
        case .functionalLearningTrainingTesting:
            return [
                "Make capability growth measurable and repeatable.",
                "Prefer exercises, rubrics, and checkpoints over vague advice.",
                "Distinguish baseline, target level, and evaluation result."
            ]
        case .functionalMemoryOptimization:
            return [
                "Preserve critical context while reducing redundancy.",
                "Record the reason for deletion, compression, or merge decisions.",
                "Keep summaries traceable to the original memory source."
            ]
        case .functionalHRWorkflow, .functionalSupervisionAssessment:
            return [
                "Make ownership, pacing, and review points explicit.",
                "Escalate uncertainty or blocking dependencies instead of hiding them.",
                "Keep handoff artifacts structured so other agents can continue cleanly."
            ]
        }
    }

    private func markdownBulletList(_ items: [String], fallback: String) -> String {
        let normalized = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if normalized.isEmpty {
            return "- \(fallback)"
        }

        return normalized.map { "- \($0)" }.joined(separator: "\n")
    }

    private func markdownNumberedList(_ items: [String], fallback: String) -> String {
        let normalized = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if normalized.isEmpty {
            return fallback
        }

        return normalized.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }

    private func normalizedOrPlaceholder(_ value: String?, fallback: String = "Not recorded.") -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
