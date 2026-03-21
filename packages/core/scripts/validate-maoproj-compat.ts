import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  fromSwiftDate,
  parseProject,
  prepareProjectForSave,
  serializeProject
} from "../src/index.ts";

interface FixtureExpectation {
  agents: number;
  workflows: number;
  totalNodes: number;
  totalEdges: number;
}

const EXPECTATIONS = new Map<string, FixtureExpectation>([
  [
    "minimal-legacy.maoproj",
    {
      agents: 0,
      workflows: 1,
      totalNodes: 0,
      totalEdges: 0
    }
  ],
  [
    "openclaw-partial-config.maoproj",
    {
      agents: 0,
      workflows: 1,
      totalNodes: 0,
      totalEdges: 0
    }
  ],
  [
    "workflow-complex.maoproj",
    {
      agents: 2,
      workflows: 2,
      totalNodes: 3,
      totalEdges: 2
    }
  ],
  [
    "runtime-protocol.maoproj",
    {
      agents: 1,
      workflows: 1,
      totalNodes: 1,
      totalEdges: 0
    }
  ]
]);

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const DEFAULT_FIXTURE_DIR = path.resolve(__dirname, "../fixtures/compat");

function ensureValidSwiftDate(value: number, label: string) {
  assert.equal(typeof value, "number", `${label} should be a number`);
  assert.equal(Number.isFinite(value), true, `${label} should be finite`);
  assert.equal(Number.isNaN(fromSwiftDate(value).getTime()), false, `${label} should decode to a valid Date`);
}

async function resolveFixturePaths(args: string[]): Promise<string[]> {
  if (args.length > 0) {
    return args.map((entry) => path.resolve(process.cwd(), entry));
  }

  const entries = await readdir(DEFAULT_FIXTURE_DIR);
  return entries
    .filter((entry) => entry.endsWith(".maoproj"))
    .sort((left, right) => left.localeCompare(right))
    .map((entry) => path.join(DEFAULT_FIXTURE_DIR, entry));
}

async function validateFixture(filePath: string) {
  const fileName = path.basename(filePath);
  const raw = await readFile(filePath, "utf8");
  const parsed = parseProject(raw);
  const serialized = serializeProject(parsed);
  const reparsed = parseProject(serialized);
  const reserialized = serializeProject(reparsed);
  const prepared = prepareProjectForSave(parsed);
  const expectation = EXPECTATIONS.get(fileName);

  assert.deepEqual(reparsed, parsed, `${fileName} should survive parse -> serialize -> parse roundtrip`);
  assert.equal(reserialized, serialized, `${fileName} should serialize stably after roundtrip`);

  ensureValidSwiftDate(parsed.createdAt, `${fileName}: createdAt`);
  ensureValidSwiftDate(parsed.updatedAt, `${fileName}: updatedAt`);
  ensureValidSwiftDate(prepared.updatedAt, `${fileName}: prepared.updatedAt`);

  assert.ok(Array.isArray(parsed.permissions), `${fileName} should normalize permissions array`);
  assert.ok(Array.isArray(parsed.messages), `${fileName} should normalize messages array`);
  assert.ok(Array.isArray(parsed.tasks), `${fileName} should normalize tasks array`);
  assert.ok(Array.isArray(parsed.executionLogs), `${fileName} should normalize execution logs array`);
  assert.ok(parsed.openClaw.config.host.length > 0, `${fileName} should normalize OpenClaw config`);
  assert.ok(parsed.runtimeState.sessionID.length > 0, `${fileName} should normalize runtime state`);
  assert.ok(prepared.updatedAt > parsed.updatedAt, `${fileName} should receive a newer updatedAt on save preparation`);

  const totalNodes = parsed.workflows.reduce((sum, workflow) => sum + workflow.nodes.length, 0);
  const totalEdges = parsed.workflows.reduce((sum, workflow) => sum + workflow.edges.length, 0);

  if (expectation) {
    assert.equal(parsed.agents.length, expectation.agents, `${fileName} agent count mismatch`);
    assert.equal(parsed.workflows.length, expectation.workflows, `${fileName} workflow count mismatch`);
    assert.equal(totalNodes, expectation.totalNodes, `${fileName} total node count mismatch`);
    assert.equal(totalEdges, expectation.totalEdges, `${fileName} total edge count mismatch`);
  }

  if (fileName === "workflow-complex.maoproj") {
    const mainWorkflow = parsed.workflows.find((workflow) => workflow.id === "workflow-main");
    assert.ok(mainWorkflow, "workflow-complex.maoproj should include workflow-main");
    const approvalEdge = mainWorkflow?.edges.find((edge) => edge.id === "edge-handoff");
    assert.ok(approvalEdge?.requiresApproval, "workflow-complex.maoproj should preserve approval edge flag");
    assert.equal(approvalEdge?.dataMapping.brief, "draft", "workflow-complex.maoproj should preserve data mapping");
  }

  if (fileName === "openclaw-partial-config.maoproj") {
    assert.equal(parsed.openClaw.config.deploymentKind, "container");
    assert.equal(parsed.openClaw.config.host, "gateway.internal");
    assert.equal(parsed.openClaw.config.defaultAgent, "ops");
    assert.equal(parsed.openClaw.config.localBinaryPath, "");
    assert.equal(parsed.openClaw.config.container.engine, "docker");
    assert.equal(parsed.openClaw.config.container.containerName, "");
    assert.equal(parsed.openClaw.config.container.workspaceMountPath, "/workspace");
    assert.ok(Array.isArray(parsed.openClaw.availableAgents), "OpenClaw availableAgents should default to an array");
    assert.ok(Array.isArray(parsed.openClaw.activeAgents), "OpenClaw activeAgents should default to an array");
    assert.ok(Array.isArray(parsed.openClaw.detectedAgents), "OpenClaw detectedAgents should default to an array");
  }

  if (fileName === "runtime-protocol.maoproj") {
    assert.equal(parsed.messages.length, 1, "runtime-protocol.maoproj should preserve messages");
    assert.equal(parsed.executionResults.length, 1, "runtime-protocol.maoproj should preserve execution results");
    assert.equal(parsed.runtimeState.runtimeEvents.length, 1, "runtime-protocol.maoproj should preserve runtime state events");
    assert.equal(parsed.messages[0]?.runtimeEvent?.eventType, "task.dispatch");
    assert.equal(parsed.messages[0]?.runtimeEvent?.refs[0]?.kind, "workspace_file");
    assert.equal(parsed.executionResults[0]?.runtimeEvents?.length, 2);
    assert.equal(parsed.executionResults[0]?.primaryRuntimeEvent?.eventType, "task.result");
    assert.equal(
      (parsed.executionResults[0]?.primaryRuntimeEvent?.payload as { summary?: string } | undefined)?.summary,
      "Prepared runtime summary"
    );
    assert.equal(parsed.executionResults[0]?.routingAction, "selected");
    assert.deepEqual(parsed.executionResults[0]?.routingTargets, ["Reviewer"]);
    assert.equal(parsed.executionResults[0]?.routingReason, "Escalate for verification");
    assert.equal(parsed.runtimeState.runtimeEvents[0]?.eventType, "session.sync");
  }

  console.log(
    `validated ${fileName}: workflows=${parsed.workflows.length}, agents=${parsed.agents.length}, nodes=${totalNodes}, edges=${totalEdges}`
  );
}

async function main() {
  const fixturePaths = await resolveFixturePaths(process.argv.slice(2));
  assert.ok(fixturePaths.length > 0, "No .maoproj fixtures were found to validate.");

  for (const fixturePath of fixturePaths) {
    await validateFixture(fixturePath);
  }

  console.log(`compatibility validation passed for ${fixturePaths.length} fixture(s)`);
}

await main();
