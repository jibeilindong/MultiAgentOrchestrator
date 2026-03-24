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

    func testParseChatHistoryPayloadPreservesStructuredBlocks() async throws {
        let client = OpenClawGatewayClient()
        let payload: [String: Any] = [
            "messages": [
                [
                    "role": "assistant",
                    "timestamp": 1_710_000_000,
                    "content": [
                        ["type": "text", "text": "这里是总结"],
                        ["type": "thinking", "thinking": "先分析上下文"],
                        ["type": "function_call", "name": "read_file", "arguments": "{\"path\":\"README.md\"}"],
                        ["type": "image", "url": "/tmp/preview.png", "mimeType": "image/png", "bytes": 2048, "omitted": true]
                    ]
                ],
                [
                    "role": "tool_result",
                    "content": [
                        ["type": "function_call_output", "name": "read_file", "output": "# README"]
                    ]
                ]
            ]
        ]

        let messages = await client.parseChatHistoryPayload(payload)

        XCTAssertEqual(messages.count, 2)

        let assistant = try XCTUnwrap(messages.first)
        XCTAssertEqual(assistant.role, "assistant")
        XCTAssertEqual(assistant.text, "这里是总结")
        XCTAssertEqual(assistant.blocks.count, 4)
        XCTAssertEqual(assistant.blocks[0].kind, .text)
        XCTAssertEqual(assistant.blocks[1].kind, .thinking)
        XCTAssertEqual(assistant.blocks[2].kind, .toolUse)
        XCTAssertEqual(assistant.blocks[2].toolName, "read_file")
        XCTAssertEqual(assistant.blocks[3].kind, .image)
        XCTAssertEqual(assistant.blocks[3].imageURL, "/tmp/preview.png")
        XCTAssertEqual(assistant.blocks[3].imageMimeType, "image/png")
        XCTAssertEqual(assistant.blocks[3].imageByteCount, 2048)
        XCTAssertTrue(assistant.blocks[3].isImageDataOmitted)

        let toolResult = try XCTUnwrap(messages.last)
        XCTAssertEqual(toolResult.role, "tool_result")
        XCTAssertEqual(toolResult.text, "# README")
        XCTAssertEqual(toolResult.blocks.count, 1)
        XCTAssertEqual(toolResult.blocks[0].kind, .toolResult)
        XCTAssertEqual(toolResult.blocks[0].toolOutput, "# README")
    }

    func testParseChatHistoryPayloadFallsBackToThinkingWhenAssistantHasNoText() async throws {
        let client = OpenClawGatewayClient()
        let payload: [String: Any] = [
            "messages": [
                [
                    "role": "assistant",
                    "content": [
                        ["type": "thinking", "thinking": "先想一下"]
                    ]
                ]
            ]
        ]

        let messages = await client.parseChatHistoryPayload(payload)

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].text, "先想一下")
        XCTAssertEqual(messages[0].blocks.first?.kind, .thinking)
    }
}
