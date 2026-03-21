import XCTest
@testable import Multi_Agent_Flow

final class DraftPersistenceTests: XCTestCase {
    func testProjectManagerDraftURLUsesDraftsDirectoryAndProjectID() {
        let projectID = UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!
        let url = ProjectManager.shared.draftURL(for: projectID)

        XCTAssertTrue(url.path.contains("/Drafts/"))
        XCTAssertEqual(url.lastPathComponent, "draft_12345678-1234-1234-1234-1234567890AB.maoproj")
    }

    func testProjectManagerCanSaveAndLoadDraft() throws {
        let project = MAProject(name: "Draft Persistence Test")
        let manager = ProjectManager.shared
        let draftURL = manager.draftURL(for: project.id)

        manager.removeDraft(for: project.id)
        defer {
            manager.removeDraft(for: project.id)
        }

        let savedURL = try manager.saveDraft(project)
        XCTAssertEqual(savedURL, draftURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: draftURL.path))

        let loadedProject = try manager.loadDraft(for: project.id)
        XCTAssertEqual(loadedProject.id, project.id)
        XCTAssertEqual(loadedProject.name, project.name)
    }
}
