import test from "node:test";
import assert from "node:assert/strict";
import { isRuntimeAgentIdentifierValid, normalizeRuntimeAgentIdentifier } from "../src/agent-naming";

test("normalizeRuntimeAgentIdentifier converts non-ascii display names into safe runtime ids", () => {
  const identifier = normalizeRuntimeAgentIdentifier([], "代码开发-任务领域-1", "代码开发-任务领域-1");
  assert.equal(identifier, "agent-1");
  assert.equal(isRuntimeAgentIdentifierValid(identifier), true);
});

test("normalizeRuntimeAgentIdentifier keeps valid ids stable and de-duplicates collisions", () => {
  const existingAgents = [
    {
      id: "agent-1",
      name: "代码开发-任务领域-1",
      identity: "generalist",
      description: "",
      soulMD: "",
      position: { x: 0, y: 0 },
      createdAt: 0,
      updatedAt: 0,
      capabilities: [],
      colorHex: null,
      openClawDefinition: {
        agentIdentifier: "agent-1",
        modelIdentifier: "MiniMax-M2.5",
        runtimeProfile: "default",
        memoryBackupPath: null,
        soulSourcePath: null,
        environment: {}
      }
    }
  ];

  assert.equal(
    normalizeRuntimeAgentIdentifier(existingAgents, "agent-1", "代码开发-任务领域-2"),
    "agent-1-2"
  );
  assert.equal(
    normalizeRuntimeAgentIdentifier(existingAgents, "Code Dev_Task_1", "代码开发-任务领域-2"),
    "code-dev_task_1"
  );
});
