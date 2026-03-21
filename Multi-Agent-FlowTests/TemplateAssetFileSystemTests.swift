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
            fileSystem.templateExamplesRootDirectory(for: template.id, under: rootURL),
            fileSystem.templateTestsRootDirectory(for: template.id, under: rootURL),
            fileSystem.templateAssetsRootDirectory(for: template.id, under: rootURL)
        ]

        for path in requiredPaths {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: path.path),
                "Expected template asset path to exist: \(path.path)"
            )
        }
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

    private func makeTemporaryDirectory() throws -> URL {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("template-filesystem-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }
}
