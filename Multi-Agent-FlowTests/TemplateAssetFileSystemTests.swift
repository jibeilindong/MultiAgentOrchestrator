import XCTest
@testable import Multi_Agent_Flow

final class TemplateAssetFileSystemTests: XCTestCase {
    func testWriteTemplateAssetCreatesStandardPackageFiles() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileSystem = TemplateFileSystem()
        let template = try XCTUnwrap(AgentTemplateCatalog.builtInTemplates.first)
        let document = TemplateAssetDocument(
            template: template,
            revision: 1,
            status: .published
        )
        let lineage = TemplateLineage(
            sourceScope: .builtInCatalog,
            sourceTemplateID: template.id,
            createdReason: "Test asset package creation."
        )

        try fileSystem.writeTemplateAsset(
            document: document,
            lineage: lineage,
            under: rootURL
        )

        let requiredPaths = [
            fileSystem.templateDocumentURL(for: template.id, under: rootURL),
            fileSystem.templateSoulURL(for: template.id, under: rootURL),
            fileSystem.templateAgentsURL(for: template.id, under: rootURL),
            fileSystem.templateIdentityURL(for: template.id, under: rootURL),
            fileSystem.templateUserURL(for: template.id, under: rootURL),
            fileSystem.templateToolsURL(for: template.id, under: rootURL),
            fileSystem.templateBootstrapURL(for: template.id, under: rootURL),
            fileSystem.templateHeartbeatURL(for: template.id, under: rootURL),
            fileSystem.templateMemoryURL(for: template.id, under: rootURL),
            fileSystem.templateLineageURL(for: template.id, under: rootURL),
            fileSystem.templateRevisionDirectory(for: template.id, under: rootURL),
            fileSystem.templateExtensionsReadmeURL(for: template.id, under: rootURL),
            fileSystem.templateExamplesReadmeURL(for: template.id, under: rootURL),
            fileSystem.templateExamplePromptURL(for: template.id, under: rootURL),
            fileSystem.templateExamplesRootDirectory(for: template.id, under: rootURL),
            fileSystem.templateTestsReadmeURL(for: template.id, under: rootURL),
            fileSystem.templateAcceptanceChecklistURL(for: template.id, under: rootURL),
            fileSystem.templateTestsRootDirectory(for: template.id, under: rootURL),
            fileSystem.templateAssetsReadmeURL(for: template.id, under: rootURL),
            fileSystem.templateAssetsManifestURL(for: template.id, under: rootURL),
            fileSystem.templateAssetsRootDirectory(for: template.id, under: rootURL)
        ]

        for path in requiredPaths {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: path.path),
                "Expected template asset path to exist: \(path.path)"
            )
        }
    }

    func testWriteTemplateAssetPopulatesDetailedStandardMarkdownFiles() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileSystem = TemplateFileSystem()
        let template = try XCTUnwrap(AgentTemplateCatalog.bundledSeedTemplates.first)
        let document = TemplateAssetDocument(
            template: template,
            revision: 2,
            status: .published
        )
        let lineage = TemplateLineage(
            sourceScope: .builtInCatalog,
            sourceTemplateID: template.id,
            createdReason: "Test detailed scaffold rendering."
        )

        try fileSystem.writeTemplateAsset(
            document: document,
            lineage: lineage,
            under: rootURL
        )

        let agentsMarkdown = try String(
            contentsOf: fileSystem.templateAgentsURL(for: template.id, under: rootURL),
            encoding: .utf8
        )
        let examplePrompt = try String(
            contentsOf: fileSystem.templateExamplePromptURL(for: template.id, under: rootURL),
            encoding: .utf8
        )
        let acceptanceChecklist = try String(
            contentsOf: fileSystem.templateAcceptanceChecklistURL(for: template.id, under: rootURL),
            encoding: .utf8
        )

        XCTAssertTrue(agentsMarkdown.contains("## Recommended Scenarios"))
        XCTAssertTrue(agentsMarkdown.contains(template.name))
        XCTAssertTrue(examplePrompt.contains("## Suggested User Brief"))
        XCTAssertTrue(examplePrompt.contains(template.name))
        XCTAssertTrue(acceptanceChecklist.contains("## Success Criteria"))
    }

    func testTemplateAssetDocumentRoundTripsTemplateContent() throws {
        let template = try XCTUnwrap(AgentTemplateCatalog.builtInTemplates.first)
        let document = TemplateAssetDocument(
            template: template,
            revision: 3,
            status: .published
        )

        let roundTripped = document.asTemplate()

        XCTAssertEqual(roundTripped.id, template.id)
        XCTAssertEqual(roundTripped.name, template.name)
        XCTAssertEqual(roundTripped.summary, template.summary)
        XCTAssertEqual(roundTripped.identity, template.identity)
        XCTAssertEqual(roundTripped.capabilities, template.capabilities)
        XCTAssertEqual(roundTripped.soulSpec, template.soulSpec)
    }

    func testListTemplateAssetIDsReturnsWrittenAssetDirectories() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileSystem = TemplateFileSystem()
        let template = try XCTUnwrap(AgentTemplateCatalog.builtInTemplates.first)
        let document = TemplateAssetDocument(
            template: template,
            revision: 1,
            status: .published
        )
        let lineage = TemplateLineage(
            sourceScope: .manualCreation,
            createdReason: "Test asset indexing."
        )

        try fileSystem.writeTemplateAsset(
            document: document,
            lineage: lineage,
            under: rootURL
        )

        XCTAssertEqual(fileSystem.listTemplateAssetIDs(under: rootURL), [template.id])
    }

    func testResolvedTemplateAssetDirectoriesRecognizesDirectAndNestedSelections() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileSystem = TemplateFileSystem()
        let template = try XCTUnwrap(AgentTemplateCatalog.builtInTemplates.first)
        let document = TemplateAssetDocument(
            template: template,
            revision: 1,
            status: .published
        )
        let lineage = TemplateLineage(
            sourceScope: .manualCreation,
            createdReason: "Test asset directory discovery."
        )

        try fileSystem.writeTemplateAsset(
            document: document,
            lineage: lineage,
            under: rootURL
        )

        let templateRootURL = fileSystem.templateRootDirectory(for: template.id, under: rootURL)
        let directMatch = fileSystem.resolvedTemplateAssetDirectories(from: [templateRootURL])
        let parentMatch = fileSystem.resolvedTemplateAssetDirectories(from: [fileSystem.templateLibraryRootDirectory(under: rootURL)])

        XCTAssertEqual(directMatch, [templateRootURL])
        XCTAssertEqual(parentMatch, [templateRootURL])
        XCTAssertTrue(fileSystem.isTemplateAssetDirectory(templateRootURL))
    }

    func testExportTemplateAssetDirectoryCopiesAssetAndAvoidsNameCollisions() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileSystem = TemplateFileSystem()
        let template = try XCTUnwrap(AgentTemplateCatalog.builtInTemplates.first)
        let document = TemplateAssetDocument(
            template: template,
            revision: 1,
            status: .published
        )
        let lineage = TemplateLineage(
            sourceScope: .manualCreation,
            createdReason: "Test asset directory export."
        )

        try fileSystem.writeTemplateAsset(
            document: document,
            lineage: lineage,
            under: rootURL
        )

        let exportParentURL = rootURL.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportParentURL, withIntermediateDirectories: true)

        let firstExportURL = try fileSystem.exportTemplateAssetDirectory(
            for: template.id,
            under: rootURL,
            to: exportParentURL,
            destinationFolderName: template.id
        )
        let secondExportURL = try fileSystem.exportTemplateAssetDirectory(
            for: template.id,
            under: rootURL,
            to: exportParentURL,
            destinationFolderName: template.id
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: firstExportURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: firstExportURL.appendingPathComponent("template.json", isDirectory: false).path
            )
        )
        XCTAssertEqual(secondExportURL.lastPathComponent, "\(template.id)-2")
    }

    func testCreateTemplateDraftDirectoryCopiesAssetAndDoesNotPolluteTemplateIndex() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileSystem = TemplateFileSystem()
        let template = try XCTUnwrap(AgentTemplateCatalog.builtInTemplates.first)
        let document = TemplateAssetDocument(
            template: template,
            revision: 1,
            status: .published
        )
        let lineage = TemplateLineage(
            sourceScope: .manualCreation,
            createdReason: "Test draft directory creation."
        )

        try fileSystem.writeTemplateAsset(
            document: document,
            lineage: lineage,
            under: rootURL
        )

        let sourceURL = fileSystem.templateRootDirectory(for: template.id, under: rootURL)
        let draftURL = try fileSystem.createTemplateDraftDirectory(
            for: template.id,
            from: sourceURL,
            under: rootURL
        )

        XCTAssertTrue(fileSystem.hasTemplateDraft(for: template.id, under: rootURL))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: draftURL.appendingPathComponent("template.json", isDirectory: false).path
            )
        )
        XCTAssertEqual(fileSystem.listTemplateAssetIDs(under: rootURL), [template.id])

        try fileSystem.removeTemplateDraft(for: template.id, under: rootURL)

        XCTAssertFalse(fileSystem.hasTemplateDraft(for: template.id, under: rootURL))
    }

    func testTemplateFileIndexExposesStandardOrderedTree() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileSystem = TemplateFileSystem()
        let template = try XCTUnwrap(AgentTemplateCatalog.builtInTemplates.first)
        let document = TemplateAssetDocument(
            template: template,
            revision: 2,
            status: .published
        )
        let lineage = TemplateLineage(
            sourceScope: .manualCreation,
            createdReason: "Test template file index ordering."
        )

        try fileSystem.writeTemplateAsset(
            document: document,
            lineage: lineage,
            under: rootURL
        )

        let index = fileSystem.templateFileIndex(
            at: fileSystem.templateRootDirectory(for: template.id, under: rootURL)
        )

        XCTAssertEqual(
            index.nodes.map(\.relativePath),
            [
                "template.json",
                "SOUL.md",
                "AGENTS.md",
                "IDENTITY.md",
                "USER.md",
                "TOOLS.md",
                "BOOTSTRAP.md",
                "HEARTBEAT.md",
                "MEMORY.md",
                "lineage.json",
                "revisions",
                "extensions"
            ]
        )

        let templateDocumentNode = try XCTUnwrap(index.node(relativePath: "template.json"))
        XCTAssertTrue(templateDocumentNode.isEditable)
        XCTAssertFalse(templateDocumentNode.isSystemManaged)
        XCTAssertTrue(templateDocumentNode.isPresent)

        let agentsNode = try XCTUnwrap(index.node(relativePath: "AGENTS.md"))
        XCTAssertFalse(agentsNode.isEditable)
        XCTAssertTrue(agentsNode.isSystemManaged)
        XCTAssertEqual(agentsNode.category, .systemManaged)

        let defaultPromptNode = try XCTUnwrap(index.node(relativePath: "extensions/examples/default-prompt.md"))
        XCTAssertTrue(defaultPromptNode.isEditable)
        XCTAssertTrue(defaultPromptNode.isRequired)
        XCTAssertTrue(defaultPromptNode.isPresent)
    }

    func testTemplateFileIndexMarksMissingDirtyAndRevisionEntries() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileSystem = TemplateFileSystem()
        let template = try XCTUnwrap(AgentTemplateCatalog.builtInTemplates.first)
        let document = TemplateAssetDocument(
            template: template,
            revision: 3,
            status: .published
        )
        let lineage = TemplateLineage(
            sourceScope: .manualCreation,
            createdReason: "Test template file index states."
        )

        try fileSystem.writeTemplateAsset(
            document: document,
            lineage: lineage,
            under: rootURL
        )

        let templateRootURL = fileSystem.templateRootDirectory(for: template.id, under: rootURL)
        try FileManager.default.removeItem(
            at: templateRootURL.appendingPathComponent("USER.md", isDirectory: false)
        )

        let index = fileSystem.templateFileIndex(
            at: templateRootURL,
            dirtyFilePaths: ["SOUL.md", "extensions/examples/default-prompt.md"]
        )

        let userNode = try XCTUnwrap(index.node(relativePath: "USER.md"))
        XCTAssertFalse(userNode.isPresent)
        XCTAssertTrue(userNode.isRequired)

        let soulNode = try XCTUnwrap(index.node(relativePath: "SOUL.md"))
        XCTAssertTrue(soulNode.isDirty)

        let promptNode = try XCTUnwrap(index.node(relativePath: "extensions/examples/default-prompt.md"))
        XCTAssertTrue(promptNode.isDirty)

        let revisionsNode = try XCTUnwrap(index.node(relativePath: "revisions"))
        XCTAssertTrue(revisionsNode.isPresent)
        XCTAssertEqual(revisionsNode.children.map(\.relativePath), ["revisions/r0003.json"])
        XCTAssertTrue(revisionsNode.children.allSatisfy(\.isSystemManaged))
    }

    func testTemplateFileSystemReadsAndWritesDraftFileContents() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileSystem = TemplateFileSystem()
        let template = try XCTUnwrap(AgentTemplateCatalog.builtInTemplates.first)
        let document = TemplateAssetDocument(
            template: template,
            revision: 1,
            status: .published
        )
        let lineage = TemplateLineage(
            sourceScope: .manualCreation,
            createdReason: "Test draft file read/write."
        )

        try fileSystem.writeTemplateAsset(
            document: document,
            lineage: lineage,
            under: rootURL
        )

        let sourceURL = fileSystem.templateRootDirectory(for: template.id, under: rootURL)
        let draftURL = try fileSystem.createTemplateDraftDirectory(
            for: template.id,
            from: sourceURL,
            under: rootURL
        )

        let updatedContents = "# Updated\n\nThis is a draft."
        try fileSystem.writeFileContents(
            updatedContents,
            at: draftURL,
            relativePath: "SOUL.md"
        )

        let loadedContents = try fileSystem.fileContents(
            at: draftURL,
            relativePath: "SOUL.md"
        )

        XCTAssertEqual(loadedContents, updatedContents)
    }

    func testTemplateFileSystemCanScaffoldMissingStandardEditableFile() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileSystem = TemplateFileSystem()
        let template = try XCTUnwrap(AgentTemplateCatalog.builtInTemplates.first)
        let document = TemplateAssetDocument(
            template: template,
            revision: 2,
            status: .published
        )
        let lineage = TemplateLineage(
            sourceScope: .manualCreation,
            createdReason: "Test standard file scaffold."
        )

        try fileSystem.writeTemplateAsset(
            document: document,
            lineage: lineage,
            under: rootURL
        )

        let templateRootURL = fileSystem.templateRootDirectory(for: template.id, under: rootURL)
        let userURL = templateRootURL.appendingPathComponent("USER.md", isDirectory: false)
        try FileManager.default.removeItem(at: userURL)

        try fileSystem.scaffoldFile(
            at: templateRootURL,
            relativePath: "USER.md",
            template: template,
            document: document,
            lineage: lineage
        )

        let scaffoldedContents = try String(contentsOf: userURL, encoding: .utf8)
        XCTAssertTrue(scaffoldedContents.contains("# USER"))
        XCTAssertTrue(scaffoldedContents.contains("## Expected Deliverables"))
    }

    func testBuiltInTemplateAssetCatalogMaterializesStandardAssets() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let catalog = BuiltInTemplateAssetCatalog(
            templateFileSystem: TemplateFileSystem(),
            fileManager: .default,
            appSupportRootDirectory: rootURL
        )

        let seedTemplates = Array(AgentTemplateCatalog.bundledSeedTemplates.prefix(2))
        catalog.synchronize(seedTemplates: seedTemplates)

        let loadedTemplates = catalog.loadTemplates()
        XCTAssertEqual(loadedTemplates.map(\.id), seedTemplates.map(\.id))

        for template in seedTemplates {
            let assetURL = try XCTUnwrap(catalog.templateAssetDirectoryURL(for: template.id))
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: assetURL.appendingPathComponent("template.json", isDirectory: false).path
                )
            )
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: assetURL.appendingPathComponent("extensions/examples/default-prompt.md", isDirectory: false).path
                )
            )
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("template-filesystem-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }
}
