//
//  AgentTemplateLibraryStore.swift
//  Multi-Agent-Flow
//
//  Created by Codex on 2026/3/21.
//

import Foundation
import Combine

struct AgentTemplateLibrarySnapshot: Codable {
    var builtInOverrides: [AgentTemplate]
    var customTemplates: [AgentTemplate]
    var favoriteTemplateIDs: [String]
    var recentTemplateIDs: [String]
    var orderedTemplateIDs: [String]
    var updatedAt: Date

    init(
        builtInOverrides: [AgentTemplate] = [],
        customTemplates: [AgentTemplate] = [],
        favoriteTemplateIDs: [String] = [],
        recentTemplateIDs: [String] = [],
        orderedTemplateIDs: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.builtInOverrides = builtInOverrides
        self.customTemplates = customTemplates
        self.favoriteTemplateIDs = favoriteTemplateIDs
        self.recentTemplateIDs = recentTemplateIDs
        self.orderedTemplateIDs = orderedTemplateIDs
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case builtInOverrides
        case customTemplates
        case favoriteTemplateIDs
        case recentTemplateIDs
        case orderedTemplateIDs
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        builtInOverrides = try container.decodeIfPresent([AgentTemplate].self, forKey: .builtInOverrides) ?? []
        customTemplates = try container.decodeIfPresent([AgentTemplate].self, forKey: .customTemplates) ?? []
        favoriteTemplateIDs = try container.decodeIfPresent([String].self, forKey: .favoriteTemplateIDs) ?? []
        recentTemplateIDs = try container.decodeIfPresent([String].self, forKey: .recentTemplateIDs) ?? []
        orderedTemplateIDs = try container.decodeIfPresent([String].self, forKey: .orderedTemplateIDs) ?? []
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(builtInOverrides, forKey: .builtInOverrides)
        try container.encode(customTemplates, forKey: .customTemplates)
        try container.encode(favoriteTemplateIDs, forKey: .favoriteTemplateIDs)
        try container.encode(recentTemplateIDs, forKey: .recentTemplateIDs)
        try container.encode(orderedTemplateIDs, forKey: .orderedTemplateIDs)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

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

final class AgentTemplateLibraryStore: ObservableObject {
    static let shared = AgentTemplateLibraryStore()

    @Published private(set) var templates: [AgentTemplate] = []

    private var snapshot = AgentTemplateLibrarySnapshot()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
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
        snapshot.customTemplates
    }

    var builtInOverrides: [AgentTemplate] {
        snapshot.builtInOverrides
    }

    var invalidTemplates: [AgentTemplate] {
        templates.filter { !$0.validationIssues.isEmpty }
    }

    var favoriteTemplateIDs: [String] {
        snapshot.favoriteTemplateIDs
    }

    var recentTemplateIDs: [String] {
        snapshot.recentTemplateIDs
    }

    var favoriteTemplates: [AgentTemplate] {
        snapshot.favoriteTemplateIDs.compactMap(template(withID:))
    }

    var recentTemplates: [AgentTemplate] {
        snapshot.recentTemplateIDs.compactMap(template(withID:))
    }

    var orderedTemplateIDs: [String] {
        snapshot.orderedTemplateIDs
    }

    func isBuiltInTemplate(_ templateID: String) -> Bool {
        builtInTemplateIDs.contains(templateID)
    }

    func template(withID id: String) -> AgentTemplate? {
        templates.first { $0.id == id }
    }

    func isFavorite(_ templateID: String) -> Bool {
        snapshot.favoriteTemplateIDs.contains(templateID)
    }

    func toggleFavorite(_ templateID: String) {
        guard template(withID: templateID) != nil else { return }

        if snapshot.favoriteTemplateIDs.contains(templateID) {
            snapshot.favoriteTemplateIDs.removeAll { $0 == templateID }
        } else {
            snapshot.favoriteTemplateIDs.insert(templateID, at: 0)
        }

        snapshot.favoriteTemplateIDs = deduplicatedTemplateIDs(snapshot.favoriteTemplateIDs)
        persist()
    }

    func markUsed(_ templateID: String) {
        guard template(withID: templateID) != nil else { return }

        snapshot.recentTemplateIDs.removeAll { $0 == templateID }
        snapshot.recentTemplateIDs.insert(templateID, at: 0)
        snapshot.recentTemplateIDs = Array(deduplicatedTemplateIDs(snapshot.recentTemplateIDs).prefix(12))
        persist()
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
        snapshot.orderedTemplateIDs = updatedOrder
        persist()
    }

    func upsert(_ template: AgentTemplate) {
        let sanitized = template.sanitizedForPersistence()
        if isBuiltInTemplate(sanitized.id) {
            snapshot.builtInOverrides.removeAll { $0.id == sanitized.id }
            snapshot.builtInOverrides.append(sanitized)
        } else {
            snapshot.customTemplates.removeAll { $0.id == sanitized.id }
            snapshot.customTemplates.append(sanitized)
        }

        persist()
    }

    @discardableResult
    func duplicateTemplate(from templateID: String) -> AgentTemplate? {
        guard let source = template(withID: templateID) else { return nil }
        var copy = source.sanitizedForPersistence()
        let baseName = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseID = source.id.replacingOccurrences(of: ".", with: "-")

        copy.meta.id = uniqueCustomTemplateID(base: "custom.\(baseID)")
        copy.meta.name = uniqueTemplateName(base: "\(baseName) Copy")
        copy.meta.identity = uniqueIdentity(base: "\(source.identity)-copy")
        copy.meta.isRecommended = false
        copy.meta.sortOrder = nextCustomSortOrder()

        snapshot.customTemplates.append(copy)
        persist()
        return copy
    }

    func resetBuiltInTemplate(_ templateID: String) {
        guard isBuiltInTemplate(templateID) else { return }
        snapshot.builtInOverrides.removeAll { $0.id == templateID }
        persist()
    }

    func deleteCustomTemplate(_ templateID: String) {
        snapshot.customTemplates.removeAll { $0.id == templateID }
        snapshot.favoriteTemplateIDs.removeAll { $0 == templateID }
        snapshot.recentTemplateIDs.removeAll { $0 == templateID }
        persist()
    }

    func importTemplates(from data: Data) throws -> [AgentTemplate] {
        let importedTemplates: [AgentTemplate]

        if let payload = try? decoder.decode(AgentTemplateExchangePayload.self, from: data) {
            importedTemplates = payload.templates
        } else {
            importedTemplates = try decoder.decode([AgentTemplate].self, from: data)
        }

        let normalized = importedTemplates.map { imported in
            var copy = imported.sanitizedForPersistence()
            if copy.id.isEmpty {
                copy.meta.id = uniqueCustomTemplateID(base: "custom.imported-template")
            }
            if copy.name.isEmpty {
                copy.meta.name = uniqueTemplateName(base: "Imported Template")
            }
            if copy.identity.isEmpty {
                copy.meta.identity = uniqueIdentity(base: "imported-template")
            }
            if builtInTemplateIDs.contains(copy.id) {
                copy.meta.isRecommended = copy.id == AgentTemplateCatalog.defaultTemplateID
            } else {
                copy.meta.id = uniqueCustomTemplateID(base: copy.id.hasPrefix("custom.") ? copy.id : "custom.\(copy.id)")
                copy.meta.name = uniqueTemplateName(base: copy.name)
                copy.meta.identity = uniqueIdentity(base: copy.identity)
                copy.meta.isRecommended = false
                copy.meta.sortOrder = nextCustomSortOrder()
            }
            return copy
        }

        for template in normalized {
            if builtInTemplateIDs.contains(template.id) {
                snapshot.builtInOverrides.removeAll { $0.id == template.id }
                snapshot.builtInOverrides.append(template)
            } else {
                snapshot.customTemplates.removeAll { $0.id == template.id }
                snapshot.customTemplates.append(template)
            }
        }

        persist()
        return normalized
    }

    func exportTemplates(_ templateIDs: [String]) throws -> Data {
        let selected = templateIDs.compactMap { template(withID: $0)?.sanitizedForPersistence() }
        let payload = AgentTemplateExchangePayload(templates: selected)
        return try encoder.encode(payload)
    }

    func exportAllTemplates() throws -> Data {
        try exportTemplates(templates.map(\.id))
    }

    func reload() {
        load()
    }

    private func load() {
        if let data = try? Data(contentsOf: storageURL),
           let snapshot = try? decoder.decode(AgentTemplateLibrarySnapshot.self, from: data) {
            self.snapshot = snapshot
        } else {
            self.snapshot = AgentTemplateLibrarySnapshot()
        }

        cleanupTemplateReferences()
        templates = mergedTemplates()
    }

    private func persist() {
        cleanupTemplateReferences()
        snapshot.updatedAt = Date()
        templates = mergedTemplates()

        try? FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    private func mergedTemplates() -> [AgentTemplate] {
        let overridesByID = Dictionary(uniqueKeysWithValues: snapshot.builtInOverrides.map { ($0.id, $0.sanitizedForPersistence()) })

        let builtIns = AgentTemplateCatalog.builtInTemplates.map { template in
            (overridesByID[template.id] ?? template)
                .withRecommended(template.id == AgentTemplateCatalog.defaultTemplateID)
        }

        let customs = snapshot.customTemplates.map { template in
            template
                .sanitizedForPersistence()
                .withRecommended(false)
        }

        let templatesByID = Dictionary(uniqueKeysWithValues: (builtIns + customs).map { ($0.id, $0) })
        return effectiveOrderedTemplateIDs()
            .enumerated()
            .compactMap { index, id in
                templatesByID[id]?.withSortOrder(index)
            }
    }

    private var storageURL: URL {
        ProjectManager.shared.appSupportRootDirectory
            .appendingPathComponent("TemplateLibrary", isDirectory: true)
            .appendingPathComponent("agent-template-library.json", isDirectory: false)
    }

    private func cleanupTemplateReferences() {
        let validTemplateIDs = Set(
            AgentTemplateCatalog.builtInTemplates.map(\.id)
            + snapshot.builtInOverrides.map(\.id)
            + snapshot.customTemplates.map(\.id)
        )

        snapshot.favoriteTemplateIDs = deduplicatedTemplateIDs(
            snapshot.favoriteTemplateIDs.filter { validTemplateIDs.contains($0) }
        )
        snapshot.recentTemplateIDs = Array(
            deduplicatedTemplateIDs(
                snapshot.recentTemplateIDs.filter { validTemplateIDs.contains($0) }
            ).prefix(12)
        )
        snapshot.orderedTemplateIDs = deduplicatedTemplateIDs(
            snapshot.orderedTemplateIDs.filter { validTemplateIDs.contains($0) }
        )

        let missingTemplateIDs = defaultTemplateIDs().filter { !snapshot.orderedTemplateIDs.contains($0) }
        snapshot.orderedTemplateIDs.append(contentsOf: missingTemplateIDs)
    }

    private func deduplicatedTemplateIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for id in ids where seen.insert(id).inserted {
            result.append(id)
        }

        return result
    }

    private func uniqueCustomTemplateID(base: String) -> String {
        let normalizedBase = base
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        var candidate = normalizedBase.isEmpty ? "custom.template" : normalizedBase
        var counter = 2
        let existing = Set(templates.map(\.id)).union(snapshot.customTemplates.map(\.id))

        while existing.contains(candidate) {
            candidate = "\(normalizedBase)-\(counter)"
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
        let existing = Set(templates.map(\.identity)).union(snapshot.customTemplates.map(\.identity))

        while existing.contains(candidate) {
            candidate = "\(baseIdentity)-\(counter)"
            counter += 1
        }

        return candidate
    }

    private func nextCustomSortOrder() -> Int {
        (snapshot.customTemplates.map { $0.meta.sortOrder }.max() ?? AgentTemplateCatalog.builtInTemplates.count) + 1
    }

    private func defaultTemplateIDs() -> [String] {
        AgentTemplateCatalog.builtInTemplates.map(\.id) + snapshot.customTemplates.map(\.id)
    }

    private func effectiveOrderedTemplateIDs() -> [String] {
        deduplicatedTemplateIDs(snapshot.orderedTemplateIDs + defaultTemplateIDs())
    }
}

enum TemplateMoveDirection {
    case up
    case down
}
