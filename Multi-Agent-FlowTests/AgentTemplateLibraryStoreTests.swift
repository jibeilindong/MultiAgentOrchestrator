import XCTest
@testable import Multi_Agent_Flow

final class AgentTemplateLibraryStoreTests: XCTestCase {
    func testImportPlannerReportsExistingLibraryConflicts() throws {
        let builtInTemplate = try XCTUnwrap(AgentTemplateCatalog.builtInTemplates.first)
        var planner = TemplateAssetImportPlanner(
            existingTemplateIDs: Set(AgentTemplateCatalog.builtInTemplates.map(\.id)),
            existingTemplateNames: Set(AgentTemplateCatalog.builtInTemplates.map(\.name)),
            existingIdentities: Set(AgentTemplateCatalog.builtInTemplates.map(\.identity)),
            existingSourceTemplateIDs: Set(AgentTemplateCatalog.builtInTemplates.map(\.id))
        )
        let sourceDirectoryURL = URL(fileURLWithPath: "/tmp/source-template", isDirectory: true)
        let sourceDocument = TemplateAssetDocument(
            template: builtInTemplate,
            revision: 7,
            status: .published
        )
        let entry = planner.buildPreviewEntry(
            sourceDirectoryURL: sourceDirectoryURL,
            sourceDocument: sourceDocument,
            sortOrder: 200,
            importHash: "hash-a"
        )

        XCTAssertEqual(entry.sourceTemplateID, builtInTemplate.id)
        XCTAssertEqual(entry.sourceName, builtInTemplate.name)
        XCTAssertEqual(entry.sourceIdentity, builtInTemplate.identity)
        XCTAssertEqual(entry.importedTemplate.id, "custom.\(builtInTemplate.id)")
        XCTAssertEqual(entry.importedTemplate.name, "\(builtInTemplate.name) 2")
        XCTAssertEqual(entry.importedTemplate.identity, "\(builtInTemplate.identity)-2")
        XCTAssertEqual(entry.importedTemplate.meta.sortOrder, 200)
        XCTAssertEqual(entry.importedLineage.sourceScope, .importedAssetDirectory)
        XCTAssertEqual(entry.importedLineage.sourceTemplateID, builtInTemplate.id)
        XCTAssertEqual(entry.importedLineage.sourceRevision, 7)
        XCTAssertEqual(entry.importedLineage.importedFromPath, sourceDirectoryURL.path)
        XCTAssertEqual(entry.importedLineage.importHash, "hash-a")

        let issueTitles = Set(entry.issues.map(\.title))
        XCTAssertTrue(issueTitles.contains("独立导入"))
        XCTAssertTrue(issueTitles.contains("检测到同源模板"))
        XCTAssertTrue(issueTitles.contains("模板名称已调整"))
        XCTAssertTrue(issueTitles.contains("身份标识已调整"))
    }

    func testImportPlannerReportsConflictsWithinSelectedAssets() throws {
        var planner = TemplateAssetImportPlanner(
            existingTemplateIDs: [],
            existingTemplateNames: [],
            existingIdentities: [],
            existingSourceTemplateIDs: []
        )
        let templateA = makeTemplate(
            id: "source.shared-alpha",
            name: "Shared Import Template",
            identity: "shared-import-template"
        )
        let templateB = makeTemplate(
            id: "source.shared-beta",
            name: "Shared Import Template",
            identity: "shared-import-template"
        )

        let firstEntry = planner.buildPreviewEntry(
            sourceDirectoryURL: URL(fileURLWithPath: "/tmp/shared-alpha", isDirectory: true),
            sourceDocument: TemplateAssetDocument(
                template: templateA,
                revision: 1,
                status: .published
            ),
            sortOrder: 10,
            importHash: nil
        )
        let secondEntry = planner.buildPreviewEntry(
            sourceDirectoryURL: URL(fileURLWithPath: "/tmp/shared-beta", isDirectory: true),
            sourceDocument: TemplateAssetDocument(
                template: templateB,
                revision: 1,
                status: .published
            ),
            sortOrder: 11,
            importHash: nil
        )

        XCTAssertEqual(firstEntry.importedTemplate.name, "Shared Import Template")
        XCTAssertEqual(firstEntry.importedTemplate.identity, "shared-import-template")

        XCTAssertEqual(secondEntry.importedTemplate.name, "Shared Import Template 2")
        XCTAssertEqual(secondEntry.importedTemplate.identity, "shared-import-template-2")

        let conflictDetails = secondEntry.issues.map(\.detail).joined(separator: "\n")
        XCTAssertTrue(conflictDetails.contains("与本次导入中的其他模板冲突"))
    }

    func testImportPlannerWarnsWhenSelectedAssetsShareSourceTemplateID() throws {
        var planner = TemplateAssetImportPlanner(
            existingTemplateIDs: [],
            existingTemplateNames: [],
            existingIdentities: [],
            existingSourceTemplateIDs: []
        )
        let firstEntry = planner.buildPreviewEntry(
            sourceDirectoryURL: URL(fileURLWithPath: "/tmp/duplicate-source-a", isDirectory: true),
            sourceDocument: TemplateAssetDocument(
                template: makeTemplate(
                    id: "same.source",
                    name: "Planner Duplicate A",
                    identity: "planner-duplicate-a"
                ),
                revision: 3,
                status: .published
            ),
            sortOrder: 20,
            importHash: nil
        )
        let secondEntry = planner.buildPreviewEntry(
            sourceDirectoryURL: URL(fileURLWithPath: "/tmp/duplicate-source-b", isDirectory: true),
            sourceDocument: TemplateAssetDocument(
                template: makeTemplate(
                    id: "same.source",
                    name: "Planner Duplicate B",
                    identity: "planner-duplicate-b"
                ),
                revision: 4,
                status: .published
            ),
            sortOrder: 21,
            importHash: nil
        )

        XCTAssertFalse(firstEntry.issues.contains(where: { $0.title == "检测到同源模板" }))
        XCTAssertTrue(secondEntry.issues.contains(where: { $0.title == "检测到同源模板" }))
    }

    private func makeTemplate(
        id: String,
        name: String,
        identity: String
    ) -> AgentTemplate {
        let baseTemplate = AgentTemplateCatalog.defaultTemplate
        var template = baseTemplate
        template.meta.id = id
        template.meta.name = name
        template.meta.identity = identity
        template.meta.summary = "Template used for import conflict tests."
        template.meta.tags = ["test"]
        return template.sanitizedForPersistence()
    }
}
