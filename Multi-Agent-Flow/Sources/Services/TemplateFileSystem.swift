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

    func templateTestsRootDirectory(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateExtensionsRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("tests", isDirectory: true)
    }

    func templateAssetsRootDirectory(for templateID: String, under appSupportRootDirectory: URL) -> URL {
        templateExtensionsRootDirectory(for: templateID, under: appSupportRootDirectory)
            .appendingPathComponent("assets", isDirectory: true)
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

                This directory is reserved for secondary development assets for the template package.

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
        """
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
        """
    }

    private func renderIdentityMarkdown(template: AgentTemplate) -> String {
        """
        # IDENTITY

        Identity: \(normalizedOrPlaceholder(template.identity))

        ## Role Summary
        \(normalizedOrPlaceholder(template.soulSpec.role))
        """
    }

    private func renderUserMarkdown(template: AgentTemplate) -> String {
        let scenarios = template.applicableScenarios.isEmpty
            ? "- No specific scenarios recorded."
            : template.applicableScenarios.map { "- \($0)" }.joined(separator: "\n")

        return """
        # USER

        \(normalizedOrPlaceholder(template.summary, fallback: "No user-facing description recorded."))

        ## Applicable Scenarios
        \(scenarios)
        """
    }

    private func renderToolsMarkdown(template: AgentTemplate) -> String {
        let capabilities = template.capabilities.isEmpty
            ? "- none"
            : template.capabilities.sorted().map { "- \($0)" }.joined(separator: "\n")

        return """
        # TOOLS

        Model: MiniMax-M2.5
        Runtime Profile: default

        ## Capabilities
        \(capabilities)

        ## Environment
        - none
        """
    }

    private func renderBootstrapMarkdown(template: AgentTemplate) -> String {
        let identifier = template.identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? template.name
            : template.identity

        return """
        # BOOTSTRAP

        Agent Identifier: \(normalizedOrPlaceholder(identifier))
        Model Identifier: MiniMax-M2.5
        Runtime Profile: default
        Soul Source Path: workspace/SOUL.md
        """
    }

    private func renderHeartbeatMarkdown() -> String {
        let memory = OpenClawAgentProtocolMemory()

        return """
        # HEARTBEAT

        Protocol Version: \(memory.protocolVersion)
        Last Updated: \(iso8601String(from: memory.lastUpdatedAt))
        Recent Corrections: \(memory.recentCorrections.count)
        Repeat Offenses: \(memory.repeatOffenses.count)
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
