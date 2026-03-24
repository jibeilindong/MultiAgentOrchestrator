import XCTest
@testable import Multi_Agent_Flow

final class OpenClawPathResolutionTests: XCTestCase {
    func testLocalBinaryPathCandidatesPreferManagedRuntimeRootsWhenAppManaged() {
        var config = OpenClawConfig.default
        config.runtimeOwnership = OpenClawRuntimeOwnership.appManaged
        config.localBinaryPath = "/legacy/external/openclaw"

        let bundleResourceURL = URL(fileURLWithPath: "/Applications/Multi-Agent-Flow.app/Contents/Resources", isDirectory: true)
        let managedRuntimeRootURL = URL(
            fileURLWithPath: "/Users/tester/Library/Application Support/Multi-Agent-Flow/openclaw/runtime",
            isDirectory: true
        )
        let homeDirectory = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

        let candidates = OpenClawManager.localBinaryPathCandidates(
            for: config,
            bundleResourceURL: bundleResourceURL,
            managedRuntimeRootURL: managedRuntimeRootURL,
            homeDirectory: homeDirectory
        )

        XCTAssertEqual(candidates, [
            "/Applications/Multi-Agent-Flow.app/Contents/Resources/OpenClaw/bin/openclaw",
            "/Applications/Multi-Agent-Flow.app/Contents/Resources/openclaw/bin/openclaw",
            "/Applications/Multi-Agent-Flow.app/Contents/Resources/OpenClaw/openclaw",
            "/Applications/Multi-Agent-Flow.app/Contents/Resources/openclaw/openclaw",
            "/Users/tester/Library/Application Support/Multi-Agent-Flow/openclaw/runtime/bin/openclaw",
            "/Users/tester/Library/Application Support/Multi-Agent-Flow/openclaw/runtime/openclaw"
        ])
    }

    func testLocalBinaryPathCandidatesStayExplicitWhenRuntimeIsExternallyManaged() {
        var config = OpenClawConfig.default
        config.runtimeOwnership = OpenClawRuntimeOwnership.externalLocal
        config.localBinaryPath = "/custom/openclaw/bin/openclaw"

        let candidates = OpenClawManager.localBinaryPathCandidates(for: config)

        XCTAssertEqual(candidates, ["/custom/openclaw/bin/openclaw"])
    }

    func testResolvedWorkspacePathPrefersProjectManagedWorkspaceAdjacentToPrivateRoot() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenClawPathResolutionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let workspaceRoot = tempRoot.appendingPathComponent("workspace", isDirectory: true)
        let privateRoot = tempRoot.appendingPathComponent("private", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: privateRoot, withIntermediateDirectories: true)

        var agent = Agent(name: "路径解析-Agent-1")
        agent.openClawDefinition.memoryBackupPath = privateRoot.path

        let resolvedPath = OpenClawManager.shared.resolvedWorkspacePath(for: agent)

        XCTAssertEqual(resolvedPath, workspaceRoot.path)
    }

    func testImportDetectedAgentsRepointsSoulAndWorkspaceArtifactsIntoManagedCopy() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenClawImportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceAgentRoot = tempRoot.appendingPathComponent("source-agent", isDirectory: true)
        let sourceWorkspaceRoot = tempRoot.appendingPathComponent("source-workspace", isDirectory: true)
        let sourceStateRoot = tempRoot.appendingPathComponent("source-state", isDirectory: true)
        let sourceSkillsRoot = sourceAgentRoot.appendingPathComponent("skills", isDirectory: true)
        let sourceSoulURL = sourceAgentRoot.appendingPathComponent("SOUL.md", isDirectory: false)
        let sourceSkillURL = sourceSkillsRoot.appendingPathComponent("review.md", isDirectory: false)

        try FileManager.default.createDirectory(at: sourceAgentRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceWorkspaceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceStateRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceSkillsRoot, withIntermediateDirectories: true)
        try "# Imported Soul".write(to: sourceSoulURL, atomically: true, encoding: .utf8)
        try "review skill".write(to: sourceSkillURL, atomically: true, encoding: .utf8)
        try "workspace memory".write(
            to: sourceWorkspaceRoot.appendingPathComponent("MEMORY.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        var project = MAProject(name: "Imported OpenClaw Agent")
        let importedRoot = ProjectManager.shared.openClawImportedAgentsDirectory(for: project.id)
        defer { try? FileManager.default.removeItem(at: importedRoot) }

        let manager = OpenClawManager.shared
        let previousDiscoveryResults = manager.discoveryResults
        defer { manager.discoveryResults = previousDiscoveryResults }

        let record = ProjectOpenClawDetectedAgentRecord(
            id: "record-1",
            name: "导入-Agent-1",
            directoryPath: sourceAgentRoot.path,
            configPath: tempRoot.appendingPathComponent("openclaw.json", isDirectory: false).path,
            soulPath: sourceSoulURL.path,
            workspacePath: sourceWorkspaceRoot.path,
            statePath: sourceStateRoot.path,
            directoryValidated: true,
            configValidated: true
        )
        manager.discoveryResults = [record]

        let imported = manager.importDetectedAgents(into: &project, selectedRecordIDs: [record.id])
        let importedRecord = try XCTUnwrap(imported.first)
        let agent = try XCTUnwrap(project.agents.first)

        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(agent.openClawDefinition.soulSourcePath, importedRecord.soulPath)
        XCTAssertEqual(agent.openClawDefinition.lastImportedSoulPath, importedRecord.soulPath)
        XCTAssertNotNil(agent.openClawDefinition.lastImportedSoulHash)
        XCTAssertNotNil(agent.openClawDefinition.lastImportedAt)
        XCTAssertEqual(importedRecord.workspacePath, importedRecord.copiedToProjectPath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .appendingPathComponent("workspace", isDirectory: true)
                .path
        })
        XCTAssertEqual(importedRecord.statePath, importedRecord.copiedToProjectPath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .appendingPathComponent("state", isDirectory: true)
                .path
        })

        let managedSoulPath = try XCTUnwrap(importedRecord.soulPath)
        let managedSoulURL = URL(fileURLWithPath: managedSoulPath, isDirectory: false)
        XCTAssertEqual(try String(contentsOf: managedSoulURL, encoding: .utf8), "# Imported Soul")
        XCTAssertTrue(FileManager.default.fileExists(atPath: managedSoulURL.deletingLastPathComponent()
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent("review.md", isDirectory: false)
            .path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: agent.openClawDefinition.memoryBackupPath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .appendingPathComponent("SOUL.md", isDirectory: false)
                .path
        } ?? ""))
        XCTAssertNotEqual(importedRecord.workspacePath, sourceWorkspaceRoot.path)
        XCTAssertNotEqual(importedRecord.soulPath, sourceSoulURL.path)
    }
}
