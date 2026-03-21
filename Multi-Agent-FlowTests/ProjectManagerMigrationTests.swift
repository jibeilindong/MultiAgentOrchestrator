import XCTest
@testable import Multi_Agent_Flow

final class ProjectManagerMigrationTests: XCTestCase {
    func testDefaultWorkspaceRootMigratesLegacyWorkspaceProjectFolderIntoManagedStorage() throws {
        let rig = try makeTestRig()
        defer { try? FileManager.default.removeItem(at: rig.rootDirectory) }

        let projectID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let taskID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let legacyFileURL = rig.directories.legacyAppSupportRootDirectory
            .appendingPathComponent("Workspaces", isDirectory: true)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent(taskID.uuidString, isDirectory: true)
            .appendingPathComponent("context.txt", isDirectory: false)

        try write("legacy workspace context", to: legacyFileURL)

        let manager = makeProjectManager(using: rig)
        let workspaceRoot = manager.defaultWorkspaceRootDirectory(for: projectID)
        let migratedFileURL = workspaceRoot
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent(taskID.uuidString, isDirectory: true)
            .appendingPathComponent("context.txt", isDirectory: false)

        XCTAssertEqual(
            workspaceRoot,
            ProjectFileSystem().taskWorkspaceRootDirectory(for: projectID, under: rig.directories.appSupportRootDirectory)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: migratedFileURL.path))
        XCTAssertEqual(try String(contentsOf: migratedFileURL), "legacy workspace context")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: manager.legacyDefaultWorkspaceRootDirectory
                    .appendingPathComponent(projectID.uuidString, isDirectory: true)
                    .path
            )
        )
    }

    func testOpenClawProjectRootMigratesLegacySessionDirectoryIntoManagedStorage() throws {
        let rig = try makeTestRig()
        defer { try? FileManager.default.removeItem(at: rig.rootDirectory) }

        let projectID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
        let legacyFileURL = rig.directories.legacyProjectsDirectory
            .appendingPathComponent("openclaw-sessions", isDirectory: true)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("session.json", isDirectory: false)

        try write("{\"state\":\"legacy\"}", to: legacyFileURL)

        let manager = makeProjectManager(using: rig)
        let sessionRoot = manager.openClawProjectRoot(for: projectID)
        let migratedFileURL = sessionRoot
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("session.json", isDirectory: false)

        XCTAssertEqual(
            sessionRoot,
            ProjectFileSystem().openClawSessionRootDirectory(for: projectID, under: rig.directories.appSupportRootDirectory)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: migratedFileURL.path))
        XCTAssertEqual(try String(contentsOf: migratedFileURL), "{\"state\":\"legacy\"}")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: manager.legacyOpenClawSessionRootDirectory
                    .appendingPathComponent(projectID.uuidString, isDirectory: true)
                    .path
            )
        )
    }

    func testAnalyticsDatabaseURLMigratesLegacyDatabaseIntoManagedStorage() throws {
        let rig = try makeTestRig()
        defer { try? FileManager.default.removeItem(at: rig.rootDirectory) }

        let projectID = UUID(uuidString: "40000000-0000-0000-0000-000000000004")!
        let legacyDatabaseURL = rig.directories.legacyAppSupportRootDirectory
            .appendingPathComponent("Analytics", isDirectory: true)
            .appendingPathComponent("\(projectID.uuidString).sqlite", isDirectory: false)

        try write("sqlite-bytes", to: legacyDatabaseURL)

        let manager = makeProjectManager(using: rig)
        let databaseURL = manager.analyticsDatabaseURL(for: projectID)

        XCTAssertEqual(
            databaseURL,
            ProjectFileSystem().analyticsDatabaseURL(for: projectID, under: rig.directories.appSupportRootDirectory)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path))
        XCTAssertEqual(try String(contentsOf: databaseURL), "sqlite-bytes")
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.legacyAnalyticsRootDirectory
            .appendingPathComponent("\(projectID.uuidString).sqlite", isDirectory: false)
            .path))
    }

    private func makeProjectManager(using rig: ProjectManagerTestRig) -> ProjectManager {
        let manager = ProjectManager(
            fileManager: .default,
            projectFileSystem: ProjectFileSystem(),
            storageDirectories: rig.directories
        )
        // ProjectManager currently crashes on custom-instance deallocation under XCTest.
        // The app runtime uses the shared singleton, so tests retain these isolated instances.
        _ = Unmanaged.passRetained(manager)
        return manager
    }

    private func makeTestRig() throws -> ProjectManagerTestRig {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectManagerMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let documentsRoot = rootDirectory.appendingPathComponent("Documents", isDirectory: true)
        let appSupportRoot = rootDirectory.appendingPathComponent("Application Support", isDirectory: true)

        return ProjectManagerTestRig(
            rootDirectory: rootDirectory,
            directories: .init(
                projectsDirectory: documentsRoot.appendingPathComponent("Multi-Agent-Flow", isDirectory: true),
                legacyProjectsDirectory: documentsRoot.appendingPathComponent("MultiAgentOrchestrator", isDirectory: true),
                appSupportRootDirectory: appSupportRoot.appendingPathComponent("Multi-Agent-Flow", isDirectory: true),
                legacyAppSupportRootDirectory: appSupportRoot.appendingPathComponent("MultiAgentOrchestrator", isDirectory: true)
            )
        )
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url, options: .atomic)
    }
}

private struct ProjectManagerTestRig {
    let rootDirectory: URL
    let directories: ProjectManager.StorageDirectories
}
