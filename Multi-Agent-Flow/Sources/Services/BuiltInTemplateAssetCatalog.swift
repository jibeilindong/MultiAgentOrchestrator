//
//  BuiltInTemplateAssetCatalog.swift
//  Multi-Agent-Flow
//
//  Created by Codex on 2026/3/22.
//

import Foundation

struct BuiltInTemplateAssetCatalog {
    static let shared = BuiltInTemplateAssetCatalog()

    private let templateFileSystem: TemplateFileSystem
    private let fileManager: FileManager
    private let appSupportRootDirectory: URL

    init(
        templateFileSystem: TemplateFileSystem = .shared,
        fileManager: FileManager = .default,
        appSupportRootDirectory: URL = ProjectManager.shared.appSupportRootDirectory
    ) {
        self.templateFileSystem = templateFileSystem
        self.fileManager = fileManager
        self.appSupportRootDirectory = appSupportRootDirectory
    }

    var cacheRootDirectory: URL {
        appSupportRootDirectory.appendingPathComponent("SystemTemplates", isDirectory: true)
    }

    func synchronize(seedTemplates: [AgentTemplate] = AgentTemplateCatalog.bundledSeedTemplates) {
        let orderedTemplates = seedTemplates.enumerated().map { index, template in
            template
                .withSortOrder(index)
                .withRecommended(template.id == AgentTemplateCatalog.defaultTemplateID)
                .sanitizedForPersistence()
        }

        let validTemplateIDs = Set(orderedTemplates.map(\.id))
        let existingTemplateIDs = Set(templateFileSystem.listTemplateAssetIDs(under: cacheRootDirectory))

        for staleTemplateID in existingTemplateIDs.subtracting(validTemplateIDs) {
            try? templateFileSystem.removeTemplateAsset(for: staleTemplateID, under: cacheRootDirectory)
        }

        let now = Date()
        let manifest = TemplateLibraryManifest(
            templateIDs: orderedTemplates.map(\.id),
            entries: orderedTemplates.map { template in
                TemplateLibraryManifestEntry(
                    id: template.id,
                    displayName: template.name,
                    revision: 1,
                    status: .published,
                    isBuiltIn: true,
                    updatedAt: now
                )
            },
            updatedAt: now
        )

        for template in orderedTemplates {
            let existingDocument = templateFileSystem.loadTemplateDocument(
                for: template.id,
                under: cacheRootDirectory
            )
            let document = TemplateAssetDocument(
                template: template,
                revision: 1,
                status: .published,
                createdAt: existingDocument?.createdAt ?? now,
                updatedAt: now
            )
            let lineage = TemplateLineage(
                sourceScope: .builtInCatalog,
                sourceTemplateID: template.id,
                sourceRevision: 1,
                createdReason: "Materialized built-in template into the standard system template asset cache.",
                createdAt: existingDocument?.createdAt ?? now,
                updatedAt: now
            )

            try? templateFileSystem.writeTemplateAsset(
                document: document,
                lineage: lineage,
                under: cacheRootDirectory
            )
        }

        try? templateFileSystem.saveManifest(manifest, under: cacheRootDirectory)
    }

    func loadTemplates() -> [AgentTemplate] {
        let orderedIDs = templateFileSystem.loadManifest(under: cacheRootDirectory)?.templateIDs
            ?? templateFileSystem.listTemplateAssetIDs(under: cacheRootDirectory)

        var documentsByID: [String: TemplateAssetDocument] = [:]
        for templateID in orderedIDs {
            guard let document = templateFileSystem.loadTemplateDocument(for: templateID, under: cacheRootDirectory) else {
                continue
            }
            documentsByID[templateID] = document
        }

        return orderedIDs.enumerated().compactMap { index, templateID in
            documentsByID[templateID]?
                .asTemplate()
                .withSortOrder(index)
                .withRecommended(templateID == AgentTemplateCatalog.defaultTemplateID)
        }
    }

    func templateAssetDirectoryURL(for templateID: String) -> URL? {
        let url = templateFileSystem.templateRootDirectory(for: templateID, under: cacheRootDirectory)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return url
    }
}
