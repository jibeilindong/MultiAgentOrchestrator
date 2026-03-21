import Foundation

struct ProjectStorageManifest: Codable, Equatable {
    static let currentSchemaVersion = "project.storage.v1"
    static let currentSnapshotRelativePath = "snapshot/current.maoproj"

    var schemaVersion: String
    var storageRevision: Int
    var projectID: UUID
    var projectName: String
    var fileVersion: String
    var sourceProjectFilePath: String?
    var currentSnapshotRelativePath: String
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?
    var lastSnapshotAt: Date?

    init(
        storageRevision: Int = 1,
        projectID: UUID,
        projectName: String,
        fileVersion: String,
        sourceProjectFilePath: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastOpenedAt: Date? = nil,
        lastSnapshotAt: Date? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.storageRevision = storageRevision
        self.projectID = projectID
        self.projectName = projectName
        self.fileVersion = fileVersion
        self.sourceProjectFilePath = sourceProjectFilePath
        self.currentSnapshotRelativePath = Self.currentSnapshotRelativePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
        self.lastSnapshotAt = lastSnapshotAt
    }
}

final class ProjectFileSystem {
    static let shared = ProjectFileSystem()

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func managedProjectsRootDirectory(under appSupportRootDirectory: URL) -> URL {
        appSupportRootDirectory.appendingPathComponent("Projects", isDirectory: true)
    }

    func managedProjectRootDirectory(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        managedProjectsRootDirectory(under: appSupportRootDirectory)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
    }

    func manifestURL(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        managedProjectRootDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent("manifest.json", isDirectory: false)
    }

    func currentSnapshotURL(for projectID: UUID, under appSupportRootDirectory: URL) -> URL {
        managedProjectRootDirectory(for: projectID, under: appSupportRootDirectory)
            .appendingPathComponent(ProjectStorageManifest.currentSnapshotRelativePath, isDirectory: false)
    }

    @discardableResult
    func synchronizeProject(
        _ project: MAProject,
        sourceProjectFileURL: URL?,
        under appSupportRootDirectory: URL
    ) throws -> ProjectStorageManifest {
        try ensureProjectScaffold(for: project.id, under: appSupportRootDirectory)

        let snapshotURL = currentSnapshotURL(for: project.id, under: appSupportRootDirectory)
        let manifestURL = manifestURL(for: project.id, under: appSupportRootDirectory)
        let existingManifest = try loadManifest(at: manifestURL)
        let now = Date()

        try encode(project, to: snapshotURL)

        let manifest = ProjectStorageManifest(
            storageRevision: (existingManifest?.storageRevision ?? 0) + 1,
            projectID: project.id,
            projectName: project.name,
            fileVersion: project.fileVersion,
            sourceProjectFilePath: sourceProjectFileURL?.path ?? existingManifest?.sourceProjectFilePath,
            createdAt: existingManifest?.createdAt ?? project.createdAt,
            updatedAt: now,
            lastOpenedAt: now,
            lastSnapshotAt: now
        )
        try encode(manifest, to: manifestURL)
        return manifest
    }

    func loadManifest(for projectID: UUID, under appSupportRootDirectory: URL) throws -> ProjectStorageManifest? {
        try loadManifest(at: manifestURL(for: projectID, under: appSupportRootDirectory))
    }

    func removeManagedProjectRoot(for projectID: UUID, under appSupportRootDirectory: URL) {
        let rootURL = managedProjectRootDirectory(for: projectID, under: appSupportRootDirectory)
        guard fileManager.fileExists(atPath: rootURL.path) else { return }
        try? fileManager.removeItem(at: rootURL)
    }

    func ensureBaseDirectories(under appSupportRootDirectory: URL) throws {
        try fileManager.createDirectory(
            at: managedProjectsRootDirectory(under: appSupportRootDirectory),
            withIntermediateDirectories: true
        )
    }

    private func ensureProjectScaffold(for projectID: UUID, under appSupportRootDirectory: URL) throws {
        let rootURL = managedProjectRootDirectory(for: projectID, under: appSupportRootDirectory)
        let directories = [
            rootURL,
            rootURL.appendingPathComponent("snapshot", isDirectory: true),
            rootURL.appendingPathComponent("design", isDirectory: true),
            rootURL.appendingPathComponent("design/workflows", isDirectory: true),
            rootURL.appendingPathComponent("collaboration", isDirectory: true),
            rootURL.appendingPathComponent("collaboration/workbench", isDirectory: true),
            rootURL.appendingPathComponent("collaboration/workbench/threads", isDirectory: true),
            rootURL.appendingPathComponent("collaboration/communications", isDirectory: true),
            rootURL.appendingPathComponent("runtime", isDirectory: true),
            rootURL.appendingPathComponent("runtime/sessions", isDirectory: true),
            rootURL.appendingPathComponent("runtime/state", isDirectory: true),
            rootURL.appendingPathComponent("tasks", isDirectory: true),
            rootURL.appendingPathComponent("execution", isDirectory: true),
            rootURL.appendingPathComponent("openclaw", isDirectory: true),
            rootURL.appendingPathComponent("openclaw/session", isDirectory: true),
            rootURL.appendingPathComponent("openclaw/session/backup", isDirectory: true),
            rootURL.appendingPathComponent("openclaw/session/mirror", isDirectory: true),
            rootURL.appendingPathComponent("openclaw/session/agents", isDirectory: true),
            rootURL.appendingPathComponent("analytics", isDirectory: true),
            rootURL.appendingPathComponent("analytics/projections", isDirectory: true),
            rootURL.appendingPathComponent("indexes", isDirectory: true),
        ]

        for directory in directories {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func loadManifest(at url: URL) throws -> ProjectStorageManifest? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ProjectStorageManifest.self, from: data)
    }
}
