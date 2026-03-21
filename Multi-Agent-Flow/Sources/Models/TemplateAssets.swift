//
//  TemplateAssets.swift
//  Multi-Agent-Flow
//
//  Created by Codex on 2026/3/22.
//

import Foundation
import CryptoKit

enum TemplateAssetStatus: String, Codable, Hashable {
    case draft
    case published
}

enum TemplateAssetSourceScope: String, Codable, Hashable {
    case builtInCatalog
    case duplicatedTemplate
    case importedAssetDirectory
    case importedJSON
    case importedSoul
    case savedAgent
    case manualCreation
    case unknown
}

struct TemplateValidationState: Codable, Hashable {
    var issues: [AgentTemplateValidationIssue]
    var hasErrors: Bool
    var validatedAt: Date

    init(
        issues: [AgentTemplateValidationIssue],
        validatedAt: Date = Date()
    ) {
        self.issues = issues
        self.hasErrors = issues.contains(where: { $0.severity == .error })
        self.validatedAt = validatedAt
    }
}

struct TemplateLineage: Codable, Hashable {
    static let currentSchemaVersion = "template.lineage.v1"

    var schemaVersion: String
    var sourceScope: TemplateAssetSourceScope
    var sourceTemplateID: String?
    var sourceRevision: Int?
    var importedFromPath: String?
    var importHash: String?
    var createdReason: String
    var createdAt: Date
    var updatedAt: Date

    init(
        sourceScope: TemplateAssetSourceScope,
        sourceTemplateID: String? = nil,
        sourceRevision: Int? = nil,
        importedFromPath: String? = nil,
        importHash: String? = nil,
        createdReason: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.sourceScope = sourceScope
        self.sourceTemplateID = sourceTemplateID
        self.sourceRevision = sourceRevision
        self.importedFromPath = importedFromPath
        self.importHash = importHash
        self.createdReason = createdReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct TemplateAssetDocument: Codable, Hashable {
    static let currentSchemaVersion = "agent.template.asset.v1"

    var schemaVersion: String
    var assetKind: String
    var id: String
    var revision: Int
    var displayName: String
    var meta: AgentTemplateMeta
    var soulSpec: AgentTemplateSoulSpec
    var renderedSoulHash: String
    var validation: TemplateValidationState
    var status: TemplateAssetStatus
    var createdAt: Date
    var updatedAt: Date

    init(
        template: AgentTemplate,
        revision: Int,
        status: TemplateAssetStatus,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        let sanitized = template.sanitizedForPersistence()
        self.schemaVersion = Self.currentSchemaVersion
        self.assetKind = "agent-template"
        self.id = sanitized.id
        self.revision = revision
        self.displayName = sanitized.name
        self.meta = sanitized.meta
        self.soulSpec = sanitized.soulSpec
        self.renderedSoulHash = Self.hash(markdown: sanitized.soulMD)
        self.validation = TemplateValidationState(issues: sanitized.validationIssues)
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func asTemplate() -> AgentTemplate {
        var template = AgentTemplate(meta: meta, soulSpec: soulSpec).sanitizedForPersistence()
        template.meta.id = id
        template.meta.name = displayName
        return template
    }

    private static func hash(markdown: String) -> String {
        let digest = SHA256.hash(data: Data(markdown.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

struct TemplateLibraryPreferences: Codable, Hashable {
    static let currentSchemaVersion = "template.library.preferences.v1"

    var schemaVersion: String
    var customFunctionDescriptions: [String]
    var favoriteTemplateIDs: [String]
    var recentTemplateIDs: [String]
    var orderedTemplateIDs: [String]
    var updatedAt: Date

    init(
        customFunctionDescriptions: [String] = [],
        favoriteTemplateIDs: [String] = [],
        recentTemplateIDs: [String] = [],
        orderedTemplateIDs: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.customFunctionDescriptions = customFunctionDescriptions
        self.favoriteTemplateIDs = favoriteTemplateIDs
        self.recentTemplateIDs = recentTemplateIDs
        self.orderedTemplateIDs = orderedTemplateIDs
        self.updatedAt = updatedAt
    }
}

struct TemplateLibraryManifestEntry: Codable, Hashable {
    var id: String
    var displayName: String
    var revision: Int
    var status: TemplateAssetStatus
    var isBuiltIn: Bool
    var updatedAt: Date
}

struct TemplateLibraryManifest: Codable, Hashable {
    static let currentSchemaVersion = "template.library.manifest.v1"

    var schemaVersion: String
    var templateIDs: [String]
    var entries: [TemplateLibraryManifestEntry]
    var updatedAt: Date

    init(
        templateIDs: [String] = [],
        entries: [TemplateLibraryManifestEntry] = [],
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.templateIDs = templateIDs
        self.entries = entries
        self.updatedAt = updatedAt
    }
}
