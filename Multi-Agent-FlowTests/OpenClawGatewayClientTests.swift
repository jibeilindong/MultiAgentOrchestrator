import XCTest
@testable import Multi_Agent_Flow

final class OpenClawGatewayClientTests: XCTestCase {
    func testAssistantTextExtractsNestedChatMessageContent() {
        let payload: [String: Any] = [
            "runId": "run-1",
            "state": "final",
            "message": [
                "role": "assistant",
                "content": [
                    ["text": "你好，我在。"]
                ]
            ]
        ]

        XCTAssertEqual(
            OpenClawGatewayClient.assistantText(fromChatPayload: payload),
            "你好，我在。"
        )
    }

    func testMergedAssistantTextHandlesFullSnapshotsAndDeltas() {
        XCTAssertEqual(
            OpenClawGatewayClient.mergedAssistantText(previous: "你好", incoming: "你好，已经收到"),
            "你好，已经收到"
        )
        XCTAssertEqual(
            OpenClawGatewayClient.mergedAssistantText(previous: "你好", incoming: "，已经收到"),
            "你好，已经收到"
        )
        XCTAssertEqual(
            OpenClawGatewayClient.mergedAssistantText(previous: "你好，已经", incoming: "已经收到"),
            "你好，已经收到"
        )
    }

    func testResolvedWorkbenchGatewaySessionKeyReadsStoredMetadata() {
        let metadata = [
            WorkbenchMetadataKey.workbenchGatewaySessionKey: "agent:planner:workbench-session"
        ]

        XCTAssertEqual(
            resolvedWorkbenchGatewaySessionKey(from: metadata),
            "agent:planner:workbench-session"
        )
    }
}
