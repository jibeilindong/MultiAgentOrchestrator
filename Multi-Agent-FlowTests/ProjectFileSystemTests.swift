import XCTest
@testable import Multi_Agent_Flow

final class ProjectFileSystemTests: XCTestCase {
    func testSynchronizeProjectCreatesManagedScaffoldAndManifest() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let project = MAProject(name: "Filesystem Test")
        let fileSystem = ProjectFileSystem()

        let manifest = try fileSystem.synchronizeProject(
            project,
            sourceProjectFileURL: URL(fileURLWithPath: "/tmp/Filesystem Test.maoproj"),
            under: tempRoot
        )

        XCTAssertEqual(manifest.projectID, project.id)
        XCTAssertEqual(manifest.projectName, project.name)
        XCTAssertEqual(manifest.fileVersion, project.fileVersion)

        let manifestURL = fileSystem.manifestURL(for: project.id, under: tempRoot)
        let snapshotURL = fileSystem.currentSnapshotURL(for: project.id, under: tempRoot)

        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fileSystem.managedProjectRootDirectory(for: project.id, under: tempRoot)
                    .appendingPathComponent("design/workflows", isDirectory: true).path
            )
        )
    }

    func testSynchronizeProjectUpdatesStoredSnapshotContents() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let project = MAProject(name: "Snapshot Test")
        let fileSystem = ProjectFileSystem()

        _ = try fileSystem.synchronizeProject(project, sourceProjectFileURL: nil, under: tempRoot)

        let snapshotURL = fileSystem.currentSnapshotURL(for: project.id, under: tempRoot)
        let data = try Data(contentsOf: snapshotURL)
        let decoded = try JSONDecoder().decode(MAProject.self, from: data)

        XCTAssertEqual(decoded.id, project.id)
        XCTAssertEqual(decoded.name, project.name)
        XCTAssertEqual(decoded.fileVersion, project.fileVersion)
    }
}
