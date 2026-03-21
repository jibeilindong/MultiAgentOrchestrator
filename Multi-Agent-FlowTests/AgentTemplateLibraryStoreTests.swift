import XCTest
@testable import Multi_Agent_Flow

final class AgentTemplateLibraryStoreTests: XCTestCase {
    func testOpenDraftSessionCreatesDraftDirectoryForCustomTemplate() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = AgentTemplateLibraryStore(
            templateFileSystem: TemplateFileSystem(),
            appSupportRootDirectory: rootURL
        )
        let customTemplate = try XCTUnwrap(
            store.duplicateTemplate(from: AgentTemplateCatalog.defaultTemplateID)
        )

        let session = try store.openDraftSession(for: customTemplate.id)

        XCTAssertEqual(session.templateID, customTemplate.id)
        XCTAssertEqual(store.draftSession(for: customTemplate.id), session)
        XCTAssertNotEqual(session.sourceAssetURL, session.draftRootURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.draftRootURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: session.draftRootURL.appendingPathComponent("template.json", isDirectory: false).path
            )
        )
    }

    func testCloseDraftSessionPreservesDraftDirectoryForLaterReopen() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = AgentTemplateLibraryStore(
            templateFileSystem: TemplateFileSystem(),
            appSupportRootDirectory: rootURL
        )
        let customTemplate = try XCTUnwrap(
            store.duplicateTemplate(from: AgentTemplateCatalog.defaultTemplateID)
        )

        let firstSession = try store.openDraftSession(for: customTemplate.id)
        let draftSoulURL = firstSession.draftRootURL.appendingPathComponent("SOUL.md", isDirectory: false)
        try "# Reopened Draft\n\n保留草稿内容".write(to: draftSoulURL, atomically: true, encoding: .utf8)

        store.closeDraftSession(for: customTemplate.id)

        XCTAssertNil(store.draftSession(for: customTemplate.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstSession.draftRootURL.path))

        let reopenedSession = try store.openDraftSession(for: customTemplate.id)
        let reopenedSoul = try String(contentsOf: draftSoulURL, encoding: .utf8)

        XCTAssertEqual(reopenedSession.draftRootURL, firstSession.draftRootURL)
        XCTAssertEqual(reopenedSoul, "# Reopened Draft\n\n保留草稿内容")
    }

    func testDiscardDraftSessionRemovesDraftDirectoryAndSessionState() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = AgentTemplateLibraryStore(
            templateFileSystem: TemplateFileSystem(),
            appSupportRootDirectory: rootURL
        )
        let customTemplate = try XCTUnwrap(
            store.duplicateTemplate(from: AgentTemplateCatalog.defaultTemplateID)
        )

        let session = try store.openDraftSession(for: customTemplate.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.draftRootURL.path))

        try store.discardDraftSession(for: customTemplate.id)

        XCTAssertNil(store.draftSession(for: customTemplate.id))
        XCTAssertNil(store.templateDraftDirectoryURL(for: customTemplate.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.draftRootURL.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("template-library-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }
}
