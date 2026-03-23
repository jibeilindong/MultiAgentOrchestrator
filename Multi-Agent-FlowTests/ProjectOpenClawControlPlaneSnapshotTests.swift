import XCTest
@testable import Multi_Agent_Flow

final class ProjectOpenClawControlPlaneSnapshotTests: XCTestCase {
    func testControlPlaneSnapshotRoundTripPreservesSecondarySummary() throws {
        let snapshot = ProjectOpenClawControlPlaneSnapshot(
            entries: [
                ProjectOpenClawControlPlaneEntrySnapshot(
                    gate: .publish,
                    status: .pending,
                    detail: "当前 run.controlled 需要先完成 persistent publish。"
                )
            ],
            highlightedGate: .publish,
            summary: "聊天模式可以继续，但 run.controlled 当前仍被阻塞。",
            secondarySummary: "项目镜像 staging 不完整，已阻止本次运行时写回。"
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ProjectOpenClawControlPlaneSnapshot.self, from: data)

        XCTAssertEqual(decoded.summary, snapshot.summary)
        XCTAssertEqual(decoded.secondarySummary, snapshot.secondarySummary)
        XCTAssertEqual(decoded.entries, snapshot.entries)
    }

    func testControlPlaneSnapshotDecodesLegacyPayloadWithoutSecondarySummary() throws {
        let legacyPayload = """
        {
          "entries" : [
            {
              "detail" : "当前项目镜像已经发布到运行时会话。",
              "gate" : "publish",
              "status" : "ready"
            }
          ],
          "highlightedGate" : "publish",
          "summary" : "当前项目镜像已经发布到运行时会话。",
          "updatedAt" : 764553600
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ProjectOpenClawControlPlaneSnapshot.self, from: legacyPayload)

        XCTAssertEqual(decoded.highlightedGate, .publish)
        XCTAssertEqual(decoded.summary, "当前项目镜像已经发布到运行时会话。")
        XCTAssertNil(decoded.secondarySummary)
    }
}
