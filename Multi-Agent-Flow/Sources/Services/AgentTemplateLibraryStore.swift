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
    case unreadableDraftFile(String)
    case invalidTemplateDocument(String)
    case invalidSoulDocument(String)

    var errorDescription: String? {
        switch self {
        case .noTemplateAssetDirectoriesFound:
            return "未找到包含 template.json 的模板资产目录。"
        case let .missingTemplate(templateID):
            return "找不到模板 \(templateID)。"
        case let .unreadableTemplateAsset(url):
            return "无法读取模板资产目录：\(url.lastPathComponent)。"
        case let .unreadableDraftFile(relativePath):
            return "无法读取模板草稿文件：\(relativePath)。"
        case let .invalidTemplateDocument(message):
            return "template.json 无法保存：\(message)"
        case let .invalidSoulDocument(message):
            return "SOUL.md 无法保存：\(message)"
        }
    }
}

enum TemplateAssetImportIssueLevel: String, Hashable {
    case info
    case warning
}

struct TemplateAssetImportIssue: Identifiable, Hashable {
    let level: TemplateAssetImportIssueLevel
    let title: String
    let detail: String

    var id: String {
        "\(level.rawValue)|\(title)|\(detail)"
    }
}

struct TemplateAssetImportPreviewEntry: Identifiable, Hashable {
    let sourceDirectoryURL: URL
    let sourceDocument: TemplateAssetDocument
    let importedTemplate: AgentTemplate
    let importedLineage: TemplateLineage
    let issues: [TemplateAssetImportIssue]

    var id: String {
        sourceDirectoryURL.path
    }

    var sourceTemplateID: String {
        sourceDocument.id.isEmpty ? sourceDirectoryURL.lastPathComponent : sourceDocument.id
    }

    var sourceName: String {
        sourceDocument.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? importedTemplate.name
            : sourceDocument.displayName
    }

    var sourceIdentity: String {
        sourceDocument.meta.identity
    }

    var warningCount: Int {
        issues.filter { $0.level == .warning }.count
    }
}

struct TemplateAssetImportPreviewReport: Identifiable, Hashable {
    let resolvedDirectoryURLs: [URL]
    let entries: [TemplateAssetImportPreviewEntry]

    var id: String {
        resolvedDirectoryURLs.map(\.path).joined(separator: "|")
    }

    var warningCount: Int {
        entries.reduce(0) { $0 + $1.warningCount }
    }
}

enum TemplateAssetImportConflictOrigin {
    case existingLibrary
    case selectedAssets
}

struct TemplateAssetReservationResult {
    let originalValue: String
    let resolvedValue: String
    let conflictOrigin: TemplateAssetImportConflictOrigin?

    var changed: Bool {
        originalValue != resolvedValue
    }
}

struct TemplateAssetImportPlanner {
    let existingTemplateIDs: Set<String>
    let existingTemplateNames: Set<String>
    let existingIdentities: Set<String>
    let existingSourceTemplateIDs: Set<String>

    private var reservedTemplateIDs: Set<String>
    private var reservedTemplateNames: Set<String>
    private var reservedIdentities: Set<String>
    private var importedSourceTemplateIDs: Set<String> = []

    init(
        existingTemplateIDs: Set<String>,
        existingTemplateNames: Set<String>,
        existingIdentities: Set<String>,
        existingSourceTemplateIDs: Set<String>
    ) {
        self.existingTemplateIDs = existingTemplateIDs
        self.existingTemplateNames = existingTemplateNames
        self.existingIdentities = existingIdentities
        self.existingSourceTemplateIDs = existingSourceTemplateIDs
        self.reservedTemplateIDs = existingTemplateIDs
        self.reservedTemplateNames = existingTemplateNames
        self.reservedIdentities = existingIdentities
    }

    mutating func buildPreviewEntry(
        sourceDirectoryURL: URL,
        sourceDocument: TemplateAssetDocument,
        sortOrder: Int,
        importHash: String?
    ) -> TemplateAssetImportPreviewEntry {
        let sourceTemplate = sourceDocument.asTemplate().sanitizedForPersistence()
        let sourceTemplateID = sourceDocument.id.isEmpty ? sourceDirectoryURL.lastPathComponent : sourceDocument.id

        var issues: [TemplateAssetImportIssue] = [
            TemplateAssetImportIssue(
                level: .info,
                title: "独立导入",
                detail: "导入后会生成新的独立模板资产，与源目录和原模板都不再关联。"
            )
        ]

        if existingSourceTemplateIDs.contains(sourceTemplateID) || importedSourceTemplateIDs.contains(sourceTemplateID) {
            issues.append(
                TemplateAssetImportIssue(
                    level: .warning,
                    title: "检测到同源模板",
                    detail: "库中或本次导入中已出现源模板 ID“\(sourceTemplateID)”，本次导入将保留为新的独立模板资产，不会覆盖已有模板。"
                )
            )
        }
        importedSourceTemplateIDs.insert(sourceTemplateID)

        let preferredTemplateID = "custom.\(Self.normalizedTemplateIDBase(from: sourceTemplateID))"
        let templateIDReservation = reserveTemplateID(
            preferredValue: preferredTemplateID,
            existingValues: existingTemplateIDs,
            reservedValues: &reservedTemplateIDs
        )
        if templateIDReservation.changed {
            issues.append(
                TemplateAssetImportIssue(
                    level: .warning,
                    title: "模板 ID 已调整",
                    detail: conflictDetail(
                        fieldName: "模板 ID",
                        original: templateIDReservation.originalValue,
                        resolved: templateIDReservation.resolvedValue,
                        origin: templateIDReservation.conflictOrigin
                    )
                )
            )
        }

        let preferredName = sourceTemplate.name.isEmpty ? sourceDirectoryURL.lastPathComponent : sourceTemplate.name
        let nameReservation = reserveTemplateName(
            preferredValue: preferredName,
            existingValues: existingTemplateNames,
            reservedValues: &reservedTemplateNames
        )
        if nameReservation.changed {
            issues.append(
                TemplateAssetImportIssue(
                    level: .warning,
                    title: "模板名称已调整",
                    detail: conflictDetail(
                        fieldName: "模板名称",
                        original: nameReservation.originalValue,
                        resolved: nameReservation.resolvedValue,
                        origin: nameReservation.conflictOrigin
                    )
                )
            )
        }

        let preferredIdentity = sourceTemplate.identity.isEmpty ? nameReservation.resolvedValue : sourceTemplate.identity
        let identityReservation = reserveTemplateIdentity(
            preferredValue: preferredIdentity,
            existingValues: existingIdentities,
            reservedValues: &reservedIdentities
        )
        if identityReservation.changed {
            issues.append(
                TemplateAssetImportIssue(
                    level: .warning,
                    title: "身份标识已调整",
                    detail: conflictDetail(
                        fieldName: "identity",
                        original: identityReservation.originalValue,
                        resolved: identityReservation.resolvedValue,
                        origin: identityReservation.conflictOrigin
                    )
                )
            )
        }

        var importedTemplate = sourceTemplate
        importedTemplate.meta.id = templateIDReservation.resolvedValue
        importedTemplate.meta.name = nameReservation.resolvedValue
        importedTemplate.meta.identity = identityReservation.resolvedValue
        importedTemplate.meta.isRecommended = false
        importedTemplate.meta.sortOrder = sortOrder

        let importedLineage = TemplateLineage(
            sourceScope: .importedAssetDirectory,
            sourceTemplateID: sourceTemplateID.isEmpty ? nil : sourceTemplateID,
            sourceRevision: sourceDocument.revision,
            importedFromPath: sourceDirectoryURL.path,
            importHash: importHash,
            createdReason: "Imported from a standardized template asset directory."
        )

        return TemplateAssetImportPreviewEntry(
            sourceDirectoryURL: sourceDirectoryURL,
            sourceDocument: sourceDocument,
            importedTemplate: importedTemplate,
            importedLineage: importedLineage,
            issues: issues
        )
    }

    private static func normalizedTemplateIDBase(from value: String) -> String {
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

    private func reserveTemplateID(
        preferredValue: String,
        existingValues: Set<String>,
        reservedValues: inout Set<String>
    ) -> TemplateAssetReservationResult {
        let originalValue = preferredValue
        var candidate = preferredValue
        var counter = 2
        var conflictOrigin: TemplateAssetImportConflictOrigin?

        while reservedValues.contains(candidate) {
            if conflictOrigin == nil {
                conflictOrigin = existingValues.contains(candidate) ? .existingLibrary : .selectedAssets
            }
            candidate = "\(preferredValue)-\(counter)"
            counter += 1
        }

        reservedValues.insert(candidate)
        return TemplateAssetReservationResult(
            originalValue: originalValue,
            resolvedValue: candidate,
            conflictOrigin: conflictOrigin
        )
    }

    private func reserveTemplateName(
        preferredValue: String,
        existingValues: Set<String>,
        reservedValues: inout Set<String>
    ) -> TemplateAssetReservationResult {
        let trimmed = preferredValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalValue = trimmed.isEmpty ? "Imported Template" : trimmed
        var candidate = originalValue
        var counter = 2
        var conflictOrigin: TemplateAssetImportConflictOrigin?

        while reservedValues.contains(candidate) {
            if conflictOrigin == nil {
                conflictOrigin = existingValues.contains(candidate) ? .existingLibrary : .selectedAssets
            }
            candidate = "\(originalValue) \(counter)"
            counter += 1
        }

        reservedValues.insert(candidate)
        return TemplateAssetReservationResult(
            originalValue: originalValue,
            resolvedValue: candidate,
            conflictOrigin: conflictOrigin
        )
    }

    private func reserveTemplateIdentity(
        preferredValue: String,
        existingValues: Set<String>,
        reservedValues: inout Set<String>
    ) -> TemplateAssetReservationResult {
        let cleaned = preferredValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        let originalValue = cleaned.isEmpty ? "custom-agent" : cleaned
        var candidate = originalValue
        var counter = 2
        var conflictOrigin: TemplateAssetImportConflictOrigin?

        while reservedValues.contains(candidate) {
            if conflictOrigin == nil {
                conflictOrigin = existingValues.contains(candidate) ? .existingLibrary : .selectedAssets
            }
            candidate = "\(originalValue)-\(counter)"
            counter += 1
        }

        reservedValues.insert(candidate)
        return TemplateAssetReservationResult(
            originalValue: originalValue,
            resolvedValue: candidate,
            conflictOrigin: conflictOrigin
        )
    }

    private func conflictDetail(
        fieldName: String,
        original: String,
        resolved: String,
        origin: TemplateAssetImportConflictOrigin?
    ) -> String {
        let originText: String
        switch origin {
        case .existingLibrary:
            originText = "与现有模板冲突"
        case .selectedAssets:
            originText = "与本次导入中的其他模板冲突"
        case .none:
            originText = "为保持唯一性"
        }

        return "\(originText)，\(fieldName) 将从“\(original)”调整为“\(resolved)”。"
    }
}

final class AgentTemplateLibraryStore: ObservableObject {
    static let shared = AgentTemplateLibraryStore()

    @Published private(set) var templates: [AgentTemplate] = []
    @Published private(set) var draftSessions: [String: TemplateDraftSession] = [:]

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

        draftSessions.removeValue(forKey: templateID)
        try? templateFileSystem.removeTemplateDraft(for: templateID, under: appSupportRootDirectory)
        customTemplateDocuments.removeValue(forKey: templateID)
        customTemplateLineages.removeValue(forKey: templateID)
        try? templateFileSystem.removeTemplateAsset(for: templateID, under: appSupportRootDirectory)

        preferences.favoriteTemplateIDs.removeAll { $0 == templateID }
        preferences.recentTemplateIDs.removeAll { $0 == templateID }
        preferences.orderedTemplateIDs.removeAll { $0 == templateID }
        persistLibraryMetadata()
    }

    func templateAssetDirectoryURL(for templateID: String) -> URL? {
        if customTemplateDocuments[templateID] != nil {
            let assetURL = templateFileSystem.templateRootDirectory(for: templateID, under: appSupportRootDirectory)
            guard FileManager.default.fileExists(atPath: assetURL.path) else { return nil }
            return assetURL
        }

        if isBuiltInTemplate(templateID) {
            return BuiltInTemplateAssetCatalog.shared.templateAssetDirectoryURL(for: templateID)
        }

        return nil
    }

    func templateDraftDirectoryURL(for templateID: String) -> URL? {
        let draftURL = templateFileSystem.templateDraftRootDirectory(for: templateID, under: appSupportRootDirectory)
        guard FileManager.default.fileExists(atPath: draftURL.path) else { return nil }
        return draftURL
    }

    func draftSession(for templateID: String) -> TemplateDraftSession? {
        draftSessions[templateID]
    }

    func templateFileIndex(for templateID: String, prefersDraft: Bool = true) -> TemplateFileIndex? {
        let rootURL: URL?

        if prefersDraft, let draftURL = templateDraftDirectoryURL(for: templateID) {
            rootURL = draftURL
        } else {
            rootURL = templateAssetDirectoryURL(for: templateID)
        }

        guard let rootURL else { return nil }
        let dirtyPaths = Set(draftSessions[templateID]?.dirtyFilePaths ?? [])
        return templateFileSystem.templateFileIndex(at: rootURL, dirtyFilePaths: dirtyPaths)
    }

    @discardableResult
    func openDraftSession(for templateID: String) throws -> TemplateDraftSession {
        guard template(withID: templateID) != nil else {
            throw AgentTemplateLibraryStoreError.missingTemplate(templateID)
        }

        if let existingSession = draftSessions[templateID],
           FileManager.default.fileExists(atPath: existingSession.draftRootURL.path) {
            return existingSession
        }

        guard let sourceAssetURL = templateAssetDirectoryURL(for: templateID) else {
            throw AgentTemplateLibraryStoreError.missingTemplate(templateID)
        }

        let draftRootURL: URL
        if let existingDraftURL = templateDraftDirectoryURL(for: templateID) {
            draftRootURL = existingDraftURL
        } else {
            draftRootURL = try templateFileSystem.createTemplateDraftDirectory(
                for: templateID,
                from: sourceAssetURL,
                under: appSupportRootDirectory
            )
        }

        let session = TemplateDraftSession(
            templateID: templateID,
            sourceAssetURL: sourceAssetURL,
            draftRootURL: draftRootURL
        )
        draftSessions[templateID] = session
        return session
    }

    func selectDraftFile(_ relativePath: String?, for templateID: String) {
        guard var session = draftSessions[templateID] else { return }
        session.selectedFilePath = relativePath
        draftSessions[templateID] = session
    }

    func templateFileContents(
        for templateID: String,
        relativePath: String,
        prefersDraft: Bool = true
    ) throws -> String {
        let rootURL: URL

        if prefersDraft {
            let session = try openDraftSession(for: templateID)
            rootURL = session.draftRootURL
        } else if let assetURL = templateAssetDirectoryURL(for: templateID) {
            rootURL = assetURL
        } else {
            throw AgentTemplateLibraryStoreError.missingTemplate(templateID)
        }

        return try templateFileSystem.fileContents(at: rootURL, relativePath: relativePath)
    }

    @discardableResult
    func updateDraftFile(
        for templateID: String,
        relativePath: String,
        contents: String
    ) throws -> TemplateDraftSession {
        var session = try openDraftSession(for: templateID)
        try templateFileSystem.writeFileContents(
            contents,
            at: session.draftRootURL,
            relativePath: relativePath
        )

        session.selectedFilePath = relativePath
        session.hasUnsavedChanges = true
        session.lastValidationState = nil
        session.hasValidationErrors = false
        session.dirtyFilePaths = mergedDirtyPaths(
            session.dirtyFilePaths,
            inserting: relativePath
        )
        draftSessions[templateID] = session
        return session
    }

    @discardableResult
    func restoreDraftFile(
        for templateID: String,
        relativePath: String
    ) throws -> TemplateDraftSession {
        var session = try openDraftSession(for: templateID)
        let sourceURL = session.sourceAssetURL
        let sourceFileURL = templateFileSystem.templateFileURL(at: sourceURL, relativePath: relativePath)

        if FileManager.default.fileExists(atPath: sourceFileURL.path) {
            let sourceContents = try templateFileSystem.fileContents(at: sourceURL, relativePath: relativePath)
            try templateFileSystem.writeFileContents(
                sourceContents,
                at: session.draftRootURL,
                relativePath: relativePath
            )
        } else {
            try templateFileSystem.removeFile(at: session.draftRootURL, relativePath: relativePath)
        }

        session.selectedFilePath = relativePath
        session.dirtyFilePaths.removeAll { $0 == relativePath }
        session.hasUnsavedChanges = !session.dirtyFilePaths.isEmpty
        session.lastValidationState = nil
        session.hasValidationErrors = false
        draftSessions[templateID] = session
        return session
    }

    @discardableResult
    func scaffoldDraftFile(
        for templateID: String,
        relativePath: String
    ) throws -> TemplateDraftSession {
        guard let template = template(withID: templateID) else {
            throw AgentTemplateLibraryStoreError.missingTemplate(templateID)
        }

        var session = try openDraftSession(for: templateID)
        try templateFileSystem.scaffoldFile(
            at: session.draftRootURL,
            relativePath: relativePath,
            template: template,
            document: templateAssetDocumentSnapshot(for: templateID, template: template),
            lineage: templateLineageSnapshot(for: templateID, template: template)
        )

        session.selectedFilePath = relativePath
        session.hasUnsavedChanges = true
        session.lastValidationState = nil
        session.hasValidationErrors = false
        session.dirtyFilePaths = mergedDirtyPaths(
            session.dirtyFilePaths,
            inserting: relativePath
        )
        draftSessions[templateID] = session
        return session
    }

    func validateDraftSession(for templateID: String) throws -> TemplateValidationState {
        var session = try openDraftSession(for: templateID)
        var issues: [AgentTemplateValidationIssue] = []

        if let index = templateFileIndex(for: templateID, prefersDraft: true) {
            let missingRequiredFiles = index.flattenedNodes.filter {
                $0.isDirectory == false && $0.isRequired && $0.isPresent == false
            }
            issues.append(contentsOf: missingRequiredFiles.map {
                AgentTemplateValidationIssue(
                    severity: .error,
                    field: $0.relativePath,
                    message: "缺少必需模板文件：\($0.displayName)。"
                )
            })
        }

        let document: TemplateAssetDocument?
        do {
            document = try decodeDraftTemplateDocument(from: session)
        } catch {
            issues.append(
                AgentTemplateValidationIssue(
                    severity: .error,
                    field: "template.json",
                    message: error.localizedDescription
                )
            )
            session.lastValidationState = TemplateValidationState(issues: issues)
            session.hasValidationErrors = session.lastValidationState?.hasErrors ?? false
            draftSessions[templateID] = session
            return session.lastValidationState ?? TemplateValidationState(issues: issues)
        }

        let parsedSoul: ParsedAgentTemplateSoul
        do {
            parsedSoul = try parseDraftSoul(from: session)
        } catch {
            issues.append(
                AgentTemplateValidationIssue(
                    severity: .error,
                    field: "SOUL.md",
                    message: error.localizedDescription
                )
            )
            session.lastValidationState = TemplateValidationState(issues: issues)
            session.hasValidationErrors = session.lastValidationState?.hasErrors ?? false
            draftSessions[templateID] = session
            return session.lastValidationState ?? TemplateValidationState(issues: issues)
        }

        if let document {
            var template = document.asTemplate().sanitizedForPersistence()
            template.meta.name = parsedSoul.name
            template.soulSpec = parsedSoul.spec
            issues.append(contentsOf: AgentTemplateValidator.validate(template))
        }

        let validationState = TemplateValidationState(issues: issues)
        session.lastValidationState = validationState
        session.hasValidationErrors = validationState.hasErrors
        draftSessions[templateID] = session
        return validationState
    }

    func templateRevisionHistory(for templateID: String) -> [TemplateAssetDocument] {
        guard let rootURL = templateAssetDirectoryURL(for: templateID) else { return [] }
        return templateFileSystem.loadTemplateRevisions(at: rootURL)
    }

    @discardableResult
    func persistDraftSession(for templateID: String) throws -> AgentTemplate {
        guard let sourceTemplate = template(withID: templateID) else {
            throw AgentTemplateLibraryStoreError.missingTemplate(templateID)
        }

        let session = try openDraftSession(for: templateID)
        let draftDocument = try decodeDraftTemplateDocument(from: session)
        let parsedSoul = try parseDraftSoul(from: session)

        var prepared = draftDocument.asTemplate().sanitizedForPersistence()
        prepared.meta.name = parsedSoul.name
        prepared.soulSpec = parsedSoul.spec
        prepared.meta.isRecommended = false
        prepared.meta.summary = prepared.meta.summary.isEmpty ? sourceTemplate.summary : prepared.meta.summary
        prepared.meta.identity = prepared.meta.identity.isEmpty ? sourceTemplate.identity : prepared.meta.identity
        prepared.meta.colorHex = prepared.meta.colorHex.isEmpty ? sourceTemplate.colorHex : prepared.meta.colorHex

        let persisted: AgentTemplate

        if isBuiltInTemplate(templateID) {
            var fork = prepared
            let requestedBaseID = prepared.id.isEmpty ? sourceTemplate.id : prepared.id
            fork.meta.id = uniqueCustomTemplateID(
                base: "custom.\(normalizedTemplateIDBase(from: requestedBaseID))"
            )
            fork.meta.name = uniqueTemplateName(
                base: prepared.name.isEmpty ? "\(sourceTemplate.name) Custom" : prepared.name
            )
            fork.meta.identity = uniqueIdentity(
                base: prepared.identity.isEmpty ? fork.name : prepared.identity
            )
            fork.meta.sortOrder = nextCustomSortOrder()

            let lineage = TemplateLineage(
                sourceScope: .duplicatedTemplate,
                sourceTemplateID: sourceTemplate.id,
                sourceRevision: draftDocument.revision,
                createdReason: "Customized from built-in template draft \(sourceTemplate.id)."
            )

            persisted = persistCustomTemplate(
                fork,
                existingDocument: nil,
                lineage: lineage,
                draftRootURL: session.draftRootURL
            )
        } else {
            let existingDocument = customTemplateDocuments[templateID]
            var updated = prepared
            updated.meta.id = templateID
            updated.meta.name = updated.meta.name.isEmpty ? sourceTemplate.name : updated.meta.name
            updated.meta.identity = updated.meta.identity.isEmpty ? sourceTemplate.identity : updated.meta.identity
            updated.meta.sortOrder = existingDocument?.meta.sortOrder ?? sourceTemplate.meta.sortOrder

            let lineage = existingDocument.flatMap { existingDocument in
                customTemplateLineages[existingDocument.id].map {
                    updatedLineage($0, sourceTemplateID: existingDocument.id)
                }
            } ?? TemplateLineage(
                sourceScope: .manualCreation,
                sourceTemplateID: templateID,
                sourceRevision: existingDocument?.revision,
                createdReason: "Saved template asset from draft workspace."
            )

            persisted = persistCustomTemplate(
                updated,
                existingDocument: existingDocument,
                lineage: lineage,
                draftRootURL: session.draftRootURL
            )
        }

        try? templateFileSystem.removeTemplateDraft(for: templateID, under: appSupportRootDirectory)
        draftSessions.removeValue(forKey: templateID)
        return persisted
    }

    func closeDraftSession(for templateID: String) {
        draftSessions.removeValue(forKey: templateID)
    }

    func discardDraftSession(for templateID: String) throws {
        draftSessions.removeValue(forKey: templateID)
        try templateFileSystem.removeTemplateDraft(for: templateID, under: appSupportRootDirectory)
    }

    func preflightImportTemplateAssets(from urls: [URL]) throws -> TemplateAssetImportPreviewReport {
        let assetDirectories = templateFileSystem.resolvedTemplateAssetDirectories(from: urls)
        guard !assetDirectories.isEmpty else {
            throw AgentTemplateLibraryStoreError.noTemplateAssetDirectoriesFound
        }

        return TemplateAssetImportPreviewReport(
            resolvedDirectoryURLs: assetDirectories,
            entries: try buildTemplateAssetImportPreviewEntries(for: assetDirectories)
        )
    }

    func importTemplateAssets(from urls: [URL]) throws -> [AgentTemplate] {
        let preview = try preflightImportTemplateAssets(from: urls)
        return try importTemplateAssets(using: preview)
    }

    func importTemplateAssets(using preview: TemplateAssetImportPreviewReport) throws -> [AgentTemplate] {
        try preview.entries.map { entry in
            _ = try templateFileSystem.copyTemplateAssetDirectory(
                from: entry.sourceDirectoryURL,
                toTemplateID: entry.importedTemplate.id,
                under: appSupportRootDirectory
            )

            return persistCustomTemplate(
                entry.importedTemplate,
                existingDocument: nil,
                lineage: entry.importedLineage
            )
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
        BuiltInTemplateAssetCatalog.shared.synchronize(seedTemplates: AgentTemplateCatalog.bundledSeedTemplates)
        try? templateFileSystem.ensureBaseDirectories(under: appSupportRootDirectory)
        preferences = templateFileSystem.loadPreferences(under: appSupportRootDirectory) ?? TemplateLibraryPreferences()
        manifest = templateFileSystem.loadManifest(under: appSupportRootDirectory) ?? TemplateLibraryManifest()
        draftSessions = [:]

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
        lineage: TemplateLineage,
        draftRootURL: URL? = nil
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

        if let draftRootURL {
            try? templateFileSystem.commitTemplateDraft(
                from: draftRootURL,
                toTemplateID: document.id,
                document: document,
                lineage: finalLineage,
                under: appSupportRootDirectory
            )
        } else {
            try? templateFileSystem.writeTemplateAsset(
                document: document,
                lineage: finalLineage,
                under: appSupportRootDirectory
            )
        }

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

    private func mergedDirtyPaths(
        _ existingPaths: [String],
        inserting relativePath: String
    ) -> [String] {
        let normalizedPath = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var paths = existingPaths.filter { !$0.isEmpty && $0 != normalizedPath }
        paths.append(normalizedPath)
        return paths.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private func templateAssetDocumentSnapshot(
        for templateID: String,
        template: AgentTemplate
    ) -> TemplateAssetDocument {
        customTemplateDocuments[templateID] ?? TemplateAssetDocument(
            template: template,
            revision: 1,
            status: status(for: template),
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func templateLineageSnapshot(
        for templateID: String,
        template: AgentTemplate
    ) -> TemplateLineage {
        customTemplateLineages[templateID] ?? TemplateLineage(
            sourceScope: isBuiltInTemplate(templateID) ? .builtInCatalog : .manualCreation,
            sourceTemplateID: templateID,
            sourceRevision: customTemplateDocuments[templateID]?.revision,
            createdReason: "Draft scaffold generated for \(template.name)."
        )
    }

    private func decodeDraftTemplateDocument(
        from session: TemplateDraftSession
    ) throws -> TemplateAssetDocument {
        let documentURL = session.draftRootURL.appendingPathComponent("template.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: documentURL.path) else {
            throw AgentTemplateLibraryStoreError.unreadableDraftFile("template.json")
        }

        do {
            let data = try Data(contentsOf: documentURL)
            return try decoder.decode(TemplateAssetDocument.self, from: data)
        } catch {
            throw AgentTemplateLibraryStoreError.invalidTemplateDocument(error.localizedDescription)
        }
    }

    private func parseDraftSoul(
        from session: TemplateDraftSession
    ) throws -> ParsedAgentTemplateSoul {
        let relativePath = "SOUL.md"

        do {
            let soulMarkdown = try templateFileSystem.fileContents(
                at: session.draftRootURL,
                relativePath: relativePath
            )
            return try AgentTemplateSoulMarkdownParser.parse(soulMarkdown)
        } catch let error as AgentTemplateSoulMarkdownParser.ParseError {
            throw AgentTemplateLibraryStoreError.invalidSoulDocument(error.localizedDescription)
        } catch {
            throw AgentTemplateLibraryStoreError.unreadableDraftFile(relativePath)
        }
    }

    private func buildTemplateAssetImportPreviewEntries(
        for assetDirectories: [URL]
    ) throws -> [TemplateAssetImportPreviewEntry] {
        let existingTemplateIDs = Set(defaultTemplateIDs())
        let existingTemplateNames = Set(templates.map(\.name))
        let existingIdentities = Set(templates.map(\.identity))
            .union(customTemplateDocuments.values.map(\.meta.identity))
        let existingSourceTemplateIDs = Set(customTemplateLineages.values.compactMap(\.sourceTemplateID))
            .union(existingTemplateIDs)

        let baseSortOrder = nextCustomSortOrder()
        var planner = TemplateAssetImportPlanner(
            existingTemplateIDs: existingTemplateIDs,
            existingTemplateNames: existingTemplateNames,
            existingIdentities: existingIdentities,
            existingSourceTemplateIDs: existingSourceTemplateIDs
        )

        return try assetDirectories.enumerated().map { index, directoryURL in
            guard let importedDocument = templateFileSystem.loadTemplateDocument(at: directoryURL) else {
                throw AgentTemplateLibraryStoreError.unreadableTemplateAsset(directoryURL)
            }

            let importHash = (
                try? Data(
                    contentsOf: directoryURL.appendingPathComponent("template.json", isDirectory: false)
                )
            ).map { sha256(data: $0) }
            return planner.buildPreviewEntry(
                sourceDirectoryURL: directoryURL,
                sourceDocument: importedDocument,
                sortOrder: baseSortOrder + index,
                importHash: importHash
            )
        }
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
            if isBuiltInTemplate(templateID) {
                return (BuiltInTemplateAssetCatalog.shared.cacheRootDirectory, nil)
            }
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
