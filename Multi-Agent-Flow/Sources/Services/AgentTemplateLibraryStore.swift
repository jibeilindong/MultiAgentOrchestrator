//
//  AgentTemplateLibraryStore.swift
//  Multi-Agent-Flow
//
//  Created by Codex on 2026/3/21.
//

import Foundation
import Combine
import CryptoKit

struct AgentTemplateExchangePayload: Codable {
    var version: String
    var exportedAt: Date
    var templates: [AgentTemplate]

    init(
        version: String = "agent-template-library.v1",
        exportedAt: Date = Date(),
        templates: [AgentTemplate]
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.templates = templates
    }
}

private enum AgentTemplateLibraryStoreError: LocalizedError {
    case noTemplateAssetDirectoriesFound
    case missingTemplate(String)
    case unreadableTemplateAsset(URL)

    var errorDescription: String? {
        switch self {
        case .noTemplateAssetDirectoriesFound:
            return "未找到包含 template.json 的模板资产目录。"
        case let .missingTemplate(templateID):
            return "找不到模板 \(templateID)。"
        case let .unreadableTemplateAsset(url):
            return "无法读取模板资产目录：\(url.lastPathComponent)。"
        }
    }
}

final class AgentTemplateLibraryStore: ObservableObject {
    static let shared = AgentTemplateLibraryStore()

    @Published private(set) var templates: [AgentTemplate] = []

    private let templateFileSystem: TemplateFileSystem
    private let appSupportRootDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var preferences = TemplateLibraryPreferences()
    private var manifest = TemplateLibraryManifest()
    private var customTemplateDocuments: [String: TemplateAssetDocument] = [:]
    private var customTemplateLineages: [String: TemplateLineage] = [:]

    init(
        templateFileSystem: TemplateFileSystem = .shared,
        appSupportRootDirectory: URL = ProjectManager.shared.appSupportRootDirectory
    ) {
        self.templateFileSystem = templateFileSystem
        self.appSupportRootDirectory = appSupportRootDirectory

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        self.decoder = decoder

        load()
    }

    var builtInTemplateIDs: Set<String> {
        Set(AgentTemplateCatalog.builtInTemplates.map(\.id))
    }

    var customTemplates: [AgentTemplate] {
        templates.filter { !isBuiltInTemplate($0.id) }
    }

    var builtInOverrides: [AgentTemplate] {
        []
    }

    var customFunctionDescriptions: [String] {
        preferences.customFunctionDescriptions
    }

    var functionDescriptionOptions: [String] {
        deduplicatedFunctionDescriptions(templates.map(\.name) + preferences.customFunctionDescriptions)
    }

    var invalidTemplates: [AgentTemplate] {
        templates.filter { !$0.validationIssues.isEmpty }
    }

    var favoriteTemplateIDs: [String] {
        preferences.favoriteTemplateIDs
    }

    var recentTemplateIDs: [String] {
        preferences.recentTemplateIDs
    }

    var favoriteTemplates: [AgentTemplate] {
        preferences.favoriteTemplateIDs.compactMap(template(withID:))
    }

    var recentTemplates: [AgentTemplate] {
        preferences.recentTemplateIDs.compactMap(template(withID:))
    }

    var orderedTemplateIDs: [String] {
        preferences.orderedTemplateIDs
    }

    func isBuiltInTemplate(_ templateID: String) -> Bool {
        builtInTemplateIDs.contains(templateID)
    }

    func template(withID id: String) -> AgentTemplate? {
        templates.first { $0.id == id }
    }

    func isFavorite(_ templateID: String) -> Bool {
        preferences.favoriteTemplateIDs.contains(templateID)
    }

    func toggleFavorite(_ templateID: String) {
        guard template(withID: templateID) != nil else { return }

        if preferences.favoriteTemplateIDs.contains(templateID) {
            preferences.favoriteTemplateIDs.removeAll { $0 == templateID }
        } else {
            preferences.favoriteTemplateIDs.insert(templateID, at: 0)
        }

        preferences.favoriteTemplateIDs = deduplicatedTemplateIDs(preferences.favoriteTemplateIDs)
        persistLibraryMetadata()
    }

    func markUsed(_ templateID: String) {
        guard template(withID: templateID) != nil else { return }

        preferences.recentTemplateIDs.removeAll { $0 == templateID }
        preferences.recentTemplateIDs.insert(templateID, at: 0)
        preferences.recentTemplateIDs = Array(deduplicatedTemplateIDs(preferences.recentTemplateIDs).prefix(12))
        persistLibraryMetadata()
    }

    func recordCustomFunctionDescription(_ description: String) {
        let sanitized = sanitizeFunctionDescription(description)
        guard !sanitized.isEmpty else { return }

        let existingTemplateNames = Set(
            templates.map { sanitizeFunctionDescription($0.name).lowercased() }
        )
        guard !existingTemplateNames.contains(sanitized.lowercased()) else { return }

        preferences.customFunctionDescriptions.removeAll {
            sanitizeFunctionDescription($0).localizedCaseInsensitiveCompare(sanitized) == .orderedSame
        }
        preferences.customFunctionDescriptions.insert(sanitized, at: 0)
        preferences.customFunctionDescriptions = Array(
            deduplicatedFunctionDescriptions(preferences.customFunctionDescriptions).prefix(24)
        )
        persistLibraryMetadata()
    }

    func moveTemplate(_ templateID: String, direction: TemplateMoveDirection) {
        let currentOrder = effectiveOrderedTemplateIDs()
        guard let index = currentOrder.firstIndex(of: templateID) else { return }

        let targetIndex: Int
        switch direction {
        case .up:
            guard index > 0 else { return }
            targetIndex = index - 1
        case .down:
            guard index < currentOrder.count - 1 else { return }
            targetIndex = index + 1
        }

        var updatedOrder = currentOrder
        updatedOrder.swapAt(index, targetIndex)
        preferences.orderedTemplateIDs = updatedOrder
        persistLibraryMetadata()
    }

    @discardableResult
    func upsert(_ template: AgentTemplate) -> AgentTemplate {
        let sanitized = template.sanitizedForPersistence()

        if isBuiltInTemplate(sanitized.id) {
            var fork = sanitized
            fork.meta.id = uniqueCustomTemplateID(base: "custom.\(normalizedTemplateIDBase(from: sanitized.id))")
            fork.meta.name = uniqueTemplateName(base: "\(sanitized.name) Custom")
            fork.meta.identity = uniqueIdentity(base: "\(sanitized.identity)-custom")
            fork.meta.isRecommended = false
            fork.meta.sortOrder = nextCustomSortOrder()

            let lineage = TemplateLineage(
                sourceScope: .duplicatedTemplate,
                sourceTemplateID: sanitized.id,
                sourceRevision: nil,
                createdReason: "Customized from built-in template \(sanitized.id)."
            )
            return persistCustomTemplate(fork, existingDocument: nil, lineage: lineage)
        }

        let existingDocument = customTemplateDocuments[sanitized.id]
        var prepared = sanitized
        prepared.meta.id = sanitized.id.isEmpty
            ? uniqueCustomTemplateID(base: "custom.template")
            : sanitized.id
        prepared.meta.name = sanitized.name.isEmpty
            ? uniqueTemplateName(base: "New Template")
            : sanitized.name
        prepared.meta.identity = sanitized.identity.isEmpty
            ? uniqueIdentity(base: prepared.meta.name)
            : sanitized.identity
        prepared.meta.isRecommended = false
        prepared.meta.sortOrder = existingDocument?.meta.sortOrder ?? nextCustomSortOrder()

        let lineage = existingDocument.flatMap { existingDocument in
            customTemplateLineages[existingDocument.id].map {
                updatedLineage($0, sourceTemplateID: existingDocument.id)
            }
        } ?? TemplateLineage(
            sourceScope: .manualCreation,
            createdReason: "Created or updated custom template asset from editor."
        )

        return persistCustomTemplate(prepared, existingDocument: existingDocument, lineage: lineage)
    }

    @discardableResult
    func duplicateTemplate(from templateID: String) -> AgentTemplate? {
        guard let source = template(withID: templateID) else { return nil }

        var copy = source.sanitizedForPersistence()
        copy.meta.id = uniqueCustomTemplateID(base: "custom.\(normalizedTemplateIDBase(from: source.id))")
        copy.meta.name = uniqueTemplateName(base: "\(source.name) Copy")
        copy.meta.identity = uniqueIdentity(base: "\(source.identity)-copy")
        copy.meta.isRecommended = false
        copy.meta.sortOrder = nextCustomSortOrder()

        let lineage = TemplateLineage(
            sourceScope: .duplicatedTemplate,
            sourceTemplateID: source.id,
            sourceRevision: customTemplateDocuments[source.id]?.revision,
            createdReason: "Duplicated from template \(source.id)."
        )
        return persistCustomTemplate(copy, existingDocument: nil, lineage: lineage)
    }

    func resetBuiltInTemplate(_ templateID: String) {
        guard isBuiltInTemplate(templateID) else { return }
        reload()
    }

    func deleteCustomTemplate(_ templateID: String) {
        guard !isBuiltInTemplate(templateID) else { return }

        customTemplateDocuments.removeValue(forKey: templateID)
        customTemplateLineages.removeValue(forKey: templateID)
        try? templateFileSystem.removeTemplateAsset(for: templateID, under: appSupportRootDirectory)

        preferences.favoriteTemplateIDs.removeAll { $0 == templateID }
        preferences.recentTemplateIDs.removeAll { $0 == templateID }
        preferences.orderedTemplateIDs.removeAll { $0 == templateID }
        persistLibraryMetadata()
    }

    func templateAssetDirectoryURL(for templateID: String) -> URL? {
        guard customTemplateDocuments[templateID] != nil else { return nil }
        let assetURL = templateFileSystem.templateRootDirectory(for: templateID, under: appSupportRootDirectory)
        guard FileManager.default.fileExists(atPath: assetURL.path) else { return nil }
        return assetURL
    }

    func importTemplateAssets(from urls: [URL]) throws -> [AgentTemplate] {
        let assetDirectories = templateFileSystem.resolvedTemplateAssetDirectories(from: urls)
        guard !assetDirectories.isEmpty else {
            throw AgentTemplateLibraryStoreError.noTemplateAssetDirectoriesFound
        }

        return try assetDirectories.map { directoryURL in
            guard let importedDocument = templateFileSystem.loadTemplateDocument(at: directoryURL) else {
                throw AgentTemplateLibraryStoreError.unreadableTemplateAsset(directoryURL)
            }

            let importedTemplate = importedDocument.asTemplate().sanitizedForPersistence()
            let originalTemplateID = importedDocument.id.isEmpty ? directoryURL.lastPathComponent : importedDocument.id
            let importHash = (
                try? Data(
                    contentsOf: directoryURL.appendingPathComponent("template.json", isDirectory: false)
                )
            ).map { sha256(data: $0) }

            var copy = importedTemplate
            copy.meta.id = uniqueCustomTemplateID(
                base: "custom.\(normalizedTemplateIDBase(from: originalTemplateID))"
            )
            copy.meta.name = uniqueTemplateName(
                base: copy.name.isEmpty ? directoryURL.lastPathComponent : copy.name
            )
            copy.meta.identity = uniqueIdentity(
                base: copy.identity.isEmpty ? copy.name : copy.identity
            )
            copy.meta.isRecommended = false
            copy.meta.sortOrder = nextCustomSortOrder()

            _ = try templateFileSystem.copyTemplateAssetDirectory(
                from: directoryURL,
                toTemplateID: copy.id,
                under: appSupportRootDirectory
            )

            let lineage = TemplateLineage(
                sourceScope: .importedAssetDirectory,
                sourceTemplateID: originalTemplateID.isEmpty ? nil : originalTemplateID,
                sourceRevision: importedDocument.revision,
                importedFromPath: directoryURL.path,
                importHash: importHash,
                createdReason: "Imported from a standardized template asset directory."
            )

            return persistCustomTemplate(copy, existingDocument: nil, lineage: lineage)
        }
    }

    func importTemplates(from data: Data) throws -> [AgentTemplate] {
        let importedTemplates: [AgentTemplate]

        if let payload = try? decoder.decode(AgentTemplateExchangePayload.self, from: data) {
            importedTemplates = payload.templates
        } else {
            importedTemplates = try decoder.decode([AgentTemplate].self, from: data)
        }

        let importHash = sha256(data: data)
        return importedTemplates.map { imported in
            var copy = imported.sanitizedForPersistence()
            let originalID = copy.id

            copy.meta.id = uniqueCustomTemplateID(
                base: "custom.\(normalizedTemplateIDBase(from: originalID.isEmpty ? "imported-template" : originalID))"
            )
            copy.meta.name = uniqueTemplateName(
                base: copy.name.isEmpty ? "Imported Template" : copy.name
            )
            copy.meta.identity = uniqueIdentity(
                base: copy.identity.isEmpty ? copy.name : copy.identity
            )
            copy.meta.isRecommended = false
            copy.meta.sortOrder = nextCustomSortOrder()

            let lineage = TemplateLineage(
                sourceScope: .importedJSON,
                sourceTemplateID: originalID.isEmpty ? nil : originalID,
                sourceRevision: customTemplateDocuments[originalID]?.revision,
                importHash: importHash,
                createdReason: "Imported from template JSON payload."
            )

            return persistCustomTemplate(copy, existingDocument: nil, lineage: lineage)
        }
    }

    func exportTemplates(_ templateIDs: [String]) throws -> Data {
        let selected = templateIDs.compactMap { template(withID: $0)?.sanitizedForPersistence() }
        let payload = AgentTemplateExchangePayload(templates: selected)
        return try encoder.encode(payload)
    }

    func exportAllTemplates() throws -> Data {
        try exportTemplates(templates.map(\.id))
    }

    func exportTemplateAsset(_ templateID: String, to destinationDirectory: URL) throws -> URL {
        try exportTemplateAssets([templateID], to: destinationDirectory).first
            .unwrap(or: AgentTemplateLibraryStoreError.missingTemplate(templateID))
    }

    func exportTemplateAssets(_ templateIDs: [String], to destinationDirectory: URL) throws -> [URL] {
        let validTemplateIDs = deduplicatedTemplateIDs(templateIDs).filter { template(withID: $0) != nil }
        guard !validTemplateIDs.isEmpty else {
            throw AgentTemplateLibraryStoreError.noTemplateAssetDirectoriesFound
        }

        return try validTemplateIDs.map { templateID in
            let sourceContext = try exportSourceContext(for: templateID)
            defer {
                if let cleanupURL = sourceContext.cleanupURL {
                    try? FileManager.default.removeItem(at: cleanupURL)
                }
            }

            return try templateFileSystem.exportTemplateAssetDirectory(
                for: templateID,
                under: sourceContext.appSupportRootDirectory,
                to: destinationDirectory,
                destinationFolderName: templateID
            )
        }
    }

    @discardableResult
    func createTemplate(from agent: Agent, basedOnTemplateID templateID: String? = nil) -> AgentTemplate {
        let baseTemplate = templateID.flatMap(template(withID:))
        var template = synthesizedTemplate(from: agent, basedOn: baseTemplate)
        template.meta.id = uniqueCustomTemplateID(
            base: "custom.\(normalizedTemplateIDBase(from: humanReadableTemplateName(from: agent.name)))"
        )
        template.meta.name = uniqueTemplateName(base: template.name)
        template.meta.identity = uniqueIdentity(base: template.identity)
        template.meta.isRecommended = false
        template.meta.sortOrder = nextCustomSortOrder()

        let lineage = TemplateLineage(
            sourceScope: .savedAgent,
            sourceTemplateID: templateID,
            sourceRevision: templateID.flatMap { customTemplateDocuments[$0]?.revision },
            createdReason: "Saved agent \(agent.id.uuidString) as an independent template asset."
        )

        return persistCustomTemplate(template, existingDocument: nil, lineage: lineage)
    }

    func reload() {
        load()
    }

    private func load() {
        try? templateFileSystem.ensureBaseDirectories(under: appSupportRootDirectory)
        preferences = templateFileSystem.loadPreferences(under: appSupportRootDirectory) ?? TemplateLibraryPreferences()
        manifest = templateFileSystem.loadManifest(under: appSupportRootDirectory) ?? TemplateLibraryManifest()

        var documents: [String: TemplateAssetDocument] = [:]
        var lineages: [String: TemplateLineage] = [:]

        for templateID in templateFileSystem.listTemplateAssetIDs(under: appSupportRootDirectory) {
            guard let document = templateFileSystem.loadTemplateDocument(
                for: templateID,
                under: appSupportRootDirectory
            ) else {
                continue
            }

            documents[templateID] = document
            lineages[templateID] = templateFileSystem.loadTemplateLineage(
                for: templateID,
                under: appSupportRootDirectory
            ) ?? TemplateLineage(
                sourceScope: .unknown,
                sourceTemplateID: templateID,
                sourceRevision: document.revision,
                createdReason: "Recovered existing template asset without lineage metadata."
            )
        }

        customTemplateDocuments = documents
        customTemplateLineages = lineages
        cleanupTemplateReferences()
        templates = mergedTemplates()
        persistLibraryMetadata()
    }

    @discardableResult
    private func persistCustomTemplate(
        _ templateValue: AgentTemplate,
        existingDocument: TemplateAssetDocument?,
        lineage: TemplateLineage
    ) -> AgentTemplate {
        var prepared = templateValue.sanitizedForPersistence()
        prepared.meta.isRecommended = false
        prepared.meta.sortOrder = existingDocument?.meta.sortOrder ?? prepared.meta.sortOrder

        let document = TemplateAssetDocument(
            template: prepared,
            revision: (existingDocument?.revision ?? 0) + 1,
            status: status(for: prepared),
            createdAt: existingDocument?.createdAt ?? Date(),
            updatedAt: Date()
        )

        let finalLineage = updatedLineage(
            lineage,
            sourceTemplateID: lineage.sourceTemplateID ?? prepared.id,
            sourceRevision: existingDocument?.revision
        )

        try? templateFileSystem.writeTemplateAsset(
            document: document,
            lineage: finalLineage,
            under: appSupportRootDirectory
        )

        customTemplateDocuments[document.id] = document
        customTemplateLineages[document.id] = finalLineage
        persistLibraryMetadata()

        return templates.first(where: { $0.id == document.id }) ?? document.asTemplate()
    }

    private func persistLibraryMetadata() {
        cleanupTemplateReferences()
        preferences.updatedAt = Date()
        templates = mergedTemplates()

        let orderedIDs = effectiveOrderedTemplateIDs()
        let entries = orderedIDs.compactMap { templateID -> TemplateLibraryManifestEntry? in
            if let document = customTemplateDocuments[templateID] {
                return TemplateLibraryManifestEntry(
                    id: document.id,
                    displayName: document.displayName,
                    revision: document.revision,
                    status: document.status,
                    isBuiltIn: false,
                    updatedAt: document.updatedAt
                )
            }

            guard let template = AgentTemplateCatalog.builtInTemplates.first(where: { $0.id == templateID }) else {
                return nil
            }

            return TemplateLibraryManifestEntry(
                id: template.id,
                displayName: template.name,
                revision: 0,
                status: .published,
                isBuiltIn: true,
                updatedAt: Date()
            )
        }

        manifest = TemplateLibraryManifest(
            templateIDs: orderedIDs,
            entries: entries,
            updatedAt: Date()
        )

        try? templateFileSystem.savePreferences(preferences, under: appSupportRootDirectory)
        try? templateFileSystem.saveManifest(manifest, under: appSupportRootDirectory)
    }

    private func mergedTemplates() -> [AgentTemplate] {
        let builtIns = AgentTemplateCatalog.builtInTemplates.map {
            $0.withRecommended($0.id == AgentTemplateCatalog.defaultTemplateID)
        }

        let customs = customTemplateDocuments.values.map { document in
            document.asTemplate()
                .withRecommended(false)
                .withSortOrder(document.meta.sortOrder)
        }

        let templatesByID = Dictionary(uniqueKeysWithValues: (builtIns + customs).map { ($0.id, $0) })
        return effectiveOrderedTemplateIDs()
            .enumerated()
            .compactMap { index, id in
                templatesByID[id]?.withSortOrder(index)
            }
    }

    private func cleanupTemplateReferences() {
        let validTemplateIDs = Set(defaultTemplateIDs())

        preferences.favoriteTemplateIDs = deduplicatedTemplateIDs(
            preferences.favoriteTemplateIDs.filter { validTemplateIDs.contains($0) }
        )
        preferences.recentTemplateIDs = Array(
            deduplicatedTemplateIDs(
                preferences.recentTemplateIDs.filter { validTemplateIDs.contains($0) }
            ).prefix(12)
        )
        preferences.orderedTemplateIDs = deduplicatedTemplateIDs(
            preferences.orderedTemplateIDs.filter { validTemplateIDs.contains($0) }
        )

        let missingTemplateIDs = defaultTemplateIDs().filter { !preferences.orderedTemplateIDs.contains($0) }
        preferences.orderedTemplateIDs.append(contentsOf: missingTemplateIDs)
        preferences.customFunctionDescriptions = Array(
            deduplicatedFunctionDescriptions(preferences.customFunctionDescriptions).prefix(24)
        )
    }

    private func deduplicatedTemplateIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for id in ids where seen.insert(id).inserted {
            result.append(id)
        }

        return result
    }

    private func deduplicatedFunctionDescriptions(_ descriptions: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for description in descriptions {
            let sanitized = sanitizeFunctionDescription(description)
            guard !sanitized.isEmpty else { continue }
            let key = sanitized.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(sanitized)
        }

        return result
    }

    private func sanitizeFunctionDescription(_ description: String) -> String {
        description
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func uniqueCustomTemplateID(base: String) -> String {
        let baseID = normalizedTemplateIDBase(from: base).isEmpty
            ? "custom.template"
            : normalizedTemplateIDBase(from: base)
        var candidate = baseID.hasPrefix("custom.") ? baseID : "custom.\(baseID)"
        var counter = 2
        let existing = Set(defaultTemplateIDs())

        while existing.contains(candidate) {
            candidate = "\(baseID)-\(counter)"
            if !candidate.hasPrefix("custom.") {
                candidate = "custom.\(candidate)"
            }
            counter += 1
        }

        return candidate
    }

    private func uniqueTemplateName(base: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? "New Template" : trimmed
        var candidate = baseName
        var counter = 2
        let existing = Set(templates.map(\.name))

        while existing.contains(candidate) {
            candidate = "\(baseName) \(counter)"
            counter += 1
        }

        return candidate
    }

    private func uniqueIdentity(base: String) -> String {
        let cleaned = base
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        let baseIdentity = cleaned.isEmpty ? "custom-agent" : cleaned
        var candidate = baseIdentity
        var counter = 2
        let existing = Set(templates.map(\.identity)).union(customTemplateDocuments.values.map(\.meta.identity))

        while existing.contains(candidate) {
            candidate = "\(baseIdentity)-\(counter)"
            counter += 1
        }

        return candidate
    }

    private func nextCustomSortOrder() -> Int {
        (customTemplateDocuments.values.map { $0.meta.sortOrder }.max() ?? AgentTemplateCatalog.builtInTemplates.count) + 1
    }

    private func defaultTemplateIDs() -> [String] {
        AgentTemplateCatalog.builtInTemplates.map(\.id) + customTemplateDocuments.keys.sorted()
    }

    private func effectiveOrderedTemplateIDs() -> [String] {
        deduplicatedTemplateIDs(preferences.orderedTemplateIDs + defaultTemplateIDs())
    }

    private func normalizedTemplateIDBase(from value: String) -> String {
        let lowered = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")

        let normalized = lowered.unicodeScalars.map { scalar -> String in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "-" {
                return String(scalar)
            }
            return "-"
        }
        .joined()
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))

        return normalized.isEmpty ? "template" : normalized
    }

    private func status(for template: AgentTemplate) -> TemplateAssetStatus {
        template.validationIssues.contains(where: { $0.severity == .error }) ? .draft : .published
    }

    private func updatedLineage(
        _ lineage: TemplateLineage,
        sourceTemplateID: String?,
        sourceRevision: Int? = nil
    ) -> TemplateLineage {
        var updated = lineage
        updated.sourceTemplateID = sourceTemplateID ?? updated.sourceTemplateID
        updated.sourceRevision = sourceRevision ?? updated.sourceRevision
        updated.updatedAt = Date()
        return updated
    }

    private func synthesizedTemplate(from agent: Agent, basedOn baseTemplate: AgentTemplate?) -> AgentTemplate {
        let parsedSoul = try? AgentTemplateSoulMarkdownParser.parse(agent.soulMD)
        let displayName = humanReadableTemplateName(from: agent.name)
        let summary = agent.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (parsedSoul?.spec.mission ?? "Standardized agent template asset generated from an existing agent.")
            : agent.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = baseTemplate?.category ?? inferredCategory(for: agent)
        let identity = agent.identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "generalist"
            : agent.identity.trimmingCharacters(in: .whitespacesAndNewlines)
        let capabilities = agent.capabilities.isEmpty ? ["basic"] : agent.capabilities
        let tags = baseTemplate?.tags ?? inferredTags(for: category, agent: agent)
        let scenarios = baseTemplate?.applicableScenarios ?? inferredApplicableScenarios(for: agent, summary: summary)
        let soulSpec = parsedSoul?.spec ?? synthesizedSoulSpec(
            for: agent,
            displayName: displayName,
            summary: summary
        )

        return AgentTemplate(
            meta: AgentTemplateMeta(
                id: "",
                category: category,
                name: displayName,
                summary: summary,
                applicableScenarios: scenarios,
                identity: identity,
                capabilities: capabilities,
                tags: tags,
                colorHex: agent.colorHex ?? baseTemplate?.colorHex ?? "64748B",
                sortOrder: nextCustomSortOrder(),
                isRecommended: false
            ),
            soulSpec: soulSpec
        ).sanitizedForPersistence()
    }

    private func humanReadableTemplateName(from agentName: String) -> String {
        let trimmed = agentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.split(separator: "-").map(String.init)
        if components.count >= 3, Int(components.last ?? "") != nil {
            let prefix = components.dropLast(2).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty {
                return prefix
            }
        }
        return trimmed.isEmpty ? "New Template" : trimmed
    }

    private func inferredCategory(for agent: Agent) -> AgentTemplateCategory {
        let searchText = [
            agent.name,
            agent.identity,
            agent.description,
            agent.capabilities.joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()

        if searchText.contains("video") || searchText.contains("视频") {
            return .productionVideo
        }
        if searchText.contains("image") || searchText.contains("图片") || searchText.contains("视觉") {
            return .productionImage
        }
        if searchText.contains("code")
            || searchText.contains("debug")
            || searchText.contains("implementation")
            || searchText.contains("api")
            || searchText.contains("代码") {
            return .productionCode
        }
        if searchText.contains("memory") || searchText.contains("记忆") {
            return .functionalMemoryOptimization
        }
        if searchText.contains("log") || searchText.contains("日志") {
            return .functionalLogAnalysis
        }
        if searchText.contains("review")
            || searchText.contains("qa")
            || searchText.contains("监督")
            || searchText.contains("评估") {
            return .functionalSupervisionAssessment
        }
        if searchText.contains("workflow")
            || searchText.contains("hr")
            || searchText.contains("招聘")
            || searchText.contains("调度") {
            return .functionalHRWorkflow
        }
        if searchText.contains("learn")
            || searchText.contains("test")
            || searchText.contains("训练")
            || searchText.contains("学习") {
            return .functionalLearningTrainingTesting
        }
        return .productionDocument
    }

    private func inferredTags(for category: AgentTemplateCategory, agent: Agent) -> [String] {
        let categoryTag: String
        switch category {
        case .functionalLearningTrainingTesting:
            categoryTag = "训练测试"
        case .functionalSupervisionAssessment:
            categoryTag = "监督评估"
        case .functionalLogAnalysis:
            categoryTag = "日志分析"
        case .functionalMemoryOptimization:
            categoryTag = "记忆整理"
        case .functionalHRWorkflow:
            categoryTag = "工作流设计"
        case .productionDocument:
            categoryTag = "文档交付"
        case .productionVideo:
            categoryTag = "视频交付"
        case .productionCode:
            categoryTag = "代码交付"
        case .productionImage:
            categoryTag = "图片交付"
        }

        return Array(
            Set([categoryTag] + agent.capabilities.prefix(3))
        )
    }

    private func inferredApplicableScenarios(for agent: Agent, summary: String) -> [String] {
        let baseName = humanReadableTemplateName(from: agent.name)
        return [
            "Directly materialize a standard agent for \(baseName).",
            summary
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    private func synthesizedSoulSpec(
        for agent: Agent,
        displayName: String,
        summary: String
    ) -> AgentTemplateSoulSpec {
        let coreCapabilities = agent.capabilities.isEmpty
            ? [
                "\(displayName) task understanding",
                "Structured execution and delivery",
                "Self-check and boundary judgment"
            ]
            : agent.capabilities

        return AgentTemplateSoulSpec(
            role: "You are a \(displayName) agent responsible for delivering standardized outcomes in your specialty.",
            mission: summary,
            coreCapabilities: coreCapabilities,
            responsibilities: [
                "Understand the user goal, context, and acceptance criteria.",
                "Execute the main work for \(displayName) with a structured process.",
                "Surface risks, missing inputs, and follow-up actions when needed."
            ],
            workflow: [
                "Clarify the goal, inputs, and constraints.",
                "Plan the work and produce the core deliverable.",
                "Review quality, summarize assumptions, and provide next steps."
            ],
            inputs: [
                "Task objective, context, and acceptance criteria.",
                "Relevant materials, constraints, and available resources."
            ],
            outputs: [
                "A directly usable result for the assigned task.",
                "Supporting notes, assumptions, and next-step suggestions."
            ],
            collaboration: [
                "Coordinate with other agents only through explicit handoff artifacts.",
                "Do not silently take over responsibilities outside the assigned scope."
            ],
            guardrails: [
                "Do not fabricate facts when inputs are incomplete.",
                "Call out high-risk uncertainty before committing to strong conclusions.",
                "Keep outputs structured, actionable, and reviewable."
            ],
            successCriteria: [
                "The output meets the stated objective and acceptance criteria.",
                "The result is ready to use or easy to continue iterating on."
            ]
        )
    }

    private func sha256(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func exportSourceContext(
        for templateID: String
    ) throws -> (appSupportRootDirectory: URL, cleanupURL: URL?) {
        guard let template = template(withID: templateID) else {
            throw AgentTemplateLibraryStoreError.missingTemplate(templateID)
        }

        if let customAssetURL = templateAssetDirectoryURL(for: templateID),
           FileManager.default.fileExists(atPath: customAssetURL.path) {
            return (appSupportRootDirectory, nil)
        }

        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("template-asset-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)

        let document = customTemplateDocuments[templateID] ?? TemplateAssetDocument(
            template: template,
            revision: 1,
            status: .published
        )
        let lineage = customTemplateLineages[templateID] ?? TemplateLineage(
            sourceScope: .builtInCatalog,
            sourceTemplateID: template.id,
            createdReason: "Materialized built-in template as an exportable template asset package."
        )

        try templateFileSystem.writeTemplateAsset(
            document: document,
            lineage: lineage,
            under: temporaryRoot
        )

        return (temporaryRoot, temporaryRoot)
    }
}

private extension Optional {
    func unwrap(or error: @autoclosure () -> Error) throws -> Wrapped {
        guard let value = self else { throw error() }
        return value
    }
}

enum TemplateMoveDirection {
    case up
    case down
}
