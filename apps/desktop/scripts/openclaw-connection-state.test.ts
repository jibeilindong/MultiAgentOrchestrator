import test from "node:test";
import assert from "node:assert/strict";
import type { OpenClawConfig } from "@multi-agent-flow/domain";
import {
  buildConnectionStateFromProbeReport,
  buildDetachedOpenClawConnectionState,
  buildOpenClawProbeContract,
  createOpenClawConnectionState,
  formatOpenClawProbeLayers,
  inferProbePhase
} from "../electron/openclaw-connection-state";

const baseConfig: OpenClawConfig = {
  deploymentKind: "local",
  host: "127.0.0.1",
  port: 18789,
  useSSL: false,
  apiKey: "",
  defaultAgent: "default",
  timeout: 30,
  autoConnect: true,
  localBinaryPath: "",
  container: {
    engine: "docker",
    containerName: "openclaw-dev",
    workspaceMountPath: "/workspace"
  },
  cliQuietMode: true,
  cliLogLevel: "warning"
};

test("local probe contract reaches ready semantics when CLI and gateway both pass", () => {
  const contract = buildOpenClawProbeContract({
    config: baseConfig,
    endpoint: "http://127.0.0.1:18789",
    availableAgents: ["planner", "reviewer"],
    cliAvailable: true,
    agentListingAvailable: true,
    gatewayProbe: {
      reachable: true,
      authenticated: true,
      latencyMs: 14,
      message: "ok",
      warnings: []
    },
    probedAt: 1_700_000_000
  });

  assert.equal(contract.success, true);
  assert.deepEqual(contract.layers, {
    transport: "ready",
    authentication: "ready",
    session: "ready",
    inventory: "ready"
  });
  assert.equal(formatOpenClawProbeLayers(contract.layers), "transport=ready, auth=ready, session=ready, inventory=ready");
  assert.equal(contract.capabilities.cliAvailable, true);
  assert.equal(contract.capabilities.gatewayAuthenticated, true);

  const phase = inferProbePhase({
    success: contract.success,
    deploymentKind: baseConfig.deploymentKind,
    endpoint: "http://127.0.0.1:18789",
    layers: contract.layers,
    capabilities: contract.capabilities,
    health: contract.health,
    availableAgents: ["planner", "reviewer"],
    message: contract.message,
    warnings: contract.warnings,
    sourceOfTruth: "test",
    observedDefaultTransports: contract.observedDefaultTransports
  }, "ready");

  assert.equal(phase, "ready");
});

test("remote probe contract becomes degraded when websocket is reachable but connect auth fails", () => {
  const config: OpenClawConfig = {
    ...baseConfig,
    deploymentKind: "remoteServer",
    host: "remote.example.com",
    apiKey: "bad-token"
  };

  const contract = buildOpenClawProbeContract({
    config,
    endpoint: "http://remote.example.com:18789",
    availableAgents: [],
    cliAvailable: false,
    agentListingAvailable: false,
    gatewayProbe: {
      reachable: true,
      authenticated: false,
      latencyMs: 41,
      message: "auth rejected",
      warnings: []
    },
    probedAt: 1_700_000_001
  });

  assert.equal(contract.success, false);
  assert.deepEqual(contract.layers, {
    transport: "ready",
    authentication: "degraded",
    session: "degraded",
    inventory: "unavailable"
  });
  assert.equal(contract.capabilities.gatewayReachable, true);
  assert.equal(contract.capabilities.gatewayAuthenticated, false);
  assert.match(contract.health.degradationReason ?? "", /auth rejected/i);
  assert.match(contract.warnings.join(" "), /transport=ready, auth=degraded/i);

  const phase = inferProbePhase({
    success: contract.success,
    deploymentKind: config.deploymentKind,
    endpoint: "http://remote.example.com:18789",
    layers: contract.layers,
    capabilities: contract.capabilities,
    health: contract.health,
    availableAgents: [],
    message: contract.message,
    warnings: contract.warnings,
    sourceOfTruth: "test",
    observedDefaultTransports: contract.observedDefaultTransports
  });

  assert.equal(phase, "degraded");
});

test("container probe contract reaches ready semantics when CLI and gateway both pass", () => {
  const config: OpenClawConfig = {
    ...baseConfig,
    deploymentKind: "container"
  };

  const contract = buildOpenClawProbeContract({
    config,
    endpoint: "http://127.0.0.1:18789",
    availableAgents: ["builder"],
    cliAvailable: true,
    agentListingAvailable: true,
    gatewayProbe: {
      reachable: true,
      authenticated: true,
      latencyMs: 18,
      message: "ok",
      warnings: []
    },
    probedAt: 1_700_000_002
  });

  assert.equal(contract.success, true);
  assert.deepEqual(contract.layers, {
    transport: "ready",
    authentication: "ready",
    session: "ready",
    inventory: "ready"
  });
  assert.equal(contract.capabilities.gatewayReachable, true);
  assert.match(contract.message, /container cli and gateway/i);
  assert.equal(contract.warnings.some((warning) => /transport=ready/i.test(warning)), false);
});

test("container probe contract becomes degraded when CLI listing succeeds but gateway transport is unreachable", () => {
  const config: OpenClawConfig = {
    ...baseConfig,
    deploymentKind: "container"
  };

  const contract = buildOpenClawProbeContract({
    config,
    endpoint: "http://127.0.0.1:18789",
    availableAgents: ["builder"],
    cliAvailable: true,
    agentListingAvailable: true,
    gatewayProbe: {
      reachable: false,
      authenticated: false,
      latencyMs: null,
      message: "connection refused",
      warnings: []
    },
    probedAt: 1_700_000_002
  });

  assert.equal(contract.success, false);
  assert.deepEqual(contract.layers, {
    transport: "degraded",
    authentication: "degraded",
    session: "degraded",
    inventory: "ready"
  });
  assert.match(contract.health.degradationReason ?? "", /connection refused/i);
  assert.match(contract.warnings.join(" "), /transport=degraded, auth=degraded/i);
});

test("local probe contract becomes failed when neither CLI nor gateway transport is available", () => {
  const contract = buildOpenClawProbeContract({
    config: baseConfig,
    endpoint: "http://127.0.0.1:18789",
    availableAgents: [],
    cliAvailable: false,
    agentListingAvailable: false,
    cliFailureMessage: "openclaw not found",
    gatewayProbe: {
      reachable: false,
      authenticated: false,
      latencyMs: null,
      message: "connection refused",
      warnings: []
    },
    probedAt: 1_700_000_004
  });

  assert.equal(contract.success, false);
  assert.deepEqual(contract.layers, {
    transport: "unavailable",
    authentication: "unavailable",
    session: "unavailable",
    inventory: "unavailable"
  });
  assert.match(contract.health.degradationReason ?? "", /openclaw not found/i);
  assert.match(contract.warnings.join(" "), /transport=unavailable, auth=unavailable/i);

  const phase = inferProbePhase({
    success: contract.success,
    deploymentKind: baseConfig.deploymentKind,
    endpoint: "http://127.0.0.1:18789",
    layers: contract.layers,
    capabilities: contract.capabilities,
    health: contract.health,
    availableAgents: [],
    message: contract.message,
    warnings: contract.warnings,
    sourceOfTruth: "test",
    observedDefaultTransports: contract.observedDefaultTransports
  });

  assert.equal(phase, "failed");
});

test("detached connection state publishes detached phase and clears capabilities", () => {
  const state = buildDetachedOpenClawConnectionState("local", 1_700_000_003, "manual disconnect");

  assert.equal(state.phase, "detached");
  assert.equal(state.capabilities.cliAvailable, false);
  assert.equal(state.capabilities.gatewayReachable, false);
  assert.equal(state.health.lastMessage, "manual disconnect");

  const rebuilt = createOpenClawConnectionState("local", state.phase, state.capabilities, state.health);
  assert.equal(rebuilt.phase, "detached");
});

test("local probe contract becomes degraded when CLI agent list succeeds but gateway transport is unreachable", () => {
  const contract = buildOpenClawProbeContract({
    config: baseConfig,
    endpoint: "http://127.0.0.1:18789",
    availableAgents: ["planner"],
    cliAvailable: true,
    agentListingAvailable: true,
    gatewayProbe: {
      reachable: false,
      authenticated: false,
      latencyMs: null,
      message: "connection refused",
      warnings: ["ws dial failed"]
    },
    probedAt: 1_700_000_005
  });

  assert.equal(contract.success, false);
  assert.deepEqual(contract.layers, {
    transport: "degraded",
    authentication: "degraded",
    session: "degraded",
    inventory: "ready"
  });
  assert.match(contract.health.degradationReason ?? "", /connection refused/i);
  assert.match(contract.warnings.join(" "), /ws dial failed/i);
  assert.match(contract.warnings.join(" "), /transport=degraded, auth=degraded/i);
});

test("local probe contract reports degraded inventory when gateway authenticates but cli listing is unavailable", () => {
  const contract = buildOpenClawProbeContract({
    config: baseConfig,
    endpoint: "http://127.0.0.1:18789",
    availableAgents: [],
    cliAvailable: true,
    agentListingAvailable: false,
    gatewayProbe: {
      reachable: true,
      authenticated: true,
      latencyMs: 9,
      message: "ok",
      warnings: []
    },
    probedAt: 1_700_000_006
  });

  assert.equal(contract.success, false);
  assert.deepEqual(contract.layers, {
    transport: "ready",
    authentication: "ready",
    session: "degraded",
    inventory: "degraded"
  });
  assert.match(contract.warnings.join(" "), /session=degraded, inventory=degraded/i);
});

test("remote probe can be authenticated while inventory stays degraded", () => {
  const config: OpenClawConfig = {
    ...baseConfig,
    deploymentKind: "remoteServer",
    host: "remote.example.com",
    apiKey: "good-token"
  };
  const contract = buildOpenClawProbeContract({
    config,
    endpoint: "http://remote.example.com:18789",
    availableAgents: [],
    cliAvailable: false,
    agentListingAvailable: false,
    gatewayProbe: {
      reachable: true,
      authenticated: true,
      latencyMs: 26,
      message: "ok",
      warnings: []
    },
    probedAt: 1_700_000_007
  });

  assert.equal(contract.success, true);
  assert.deepEqual(contract.layers, {
    transport: "ready",
    authentication: "ready",
    session: "ready",
    inventory: "degraded"
  });
  assert.match(contract.warnings.join(" "), /inventory=degraded/i);

  const report = {
    success: contract.success,
    deploymentKind: config.deploymentKind,
    endpoint: "http://remote.example.com:18789",
    layers: contract.layers,
    capabilities: contract.capabilities,
    health: contract.health,
    availableAgents: [],
    message: contract.message,
    warnings: contract.warnings,
    sourceOfTruth: "test",
    observedDefaultTransports: contract.observedDefaultTransports
  } as const;

  const state = buildConnectionStateFromProbeReport({
    deploymentKind: config.deploymentKind,
    report,
    successPhase: "ready"
  });
  assert.equal(state.phase, "ready");
  assert.equal(state.health.lastMessage, contract.message);
});
