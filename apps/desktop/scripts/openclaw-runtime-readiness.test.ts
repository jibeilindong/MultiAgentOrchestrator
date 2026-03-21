import test from "node:test";
import assert from "node:assert/strict";
import type { ProjectOpenClawSnapshot } from "@multi-agent-flow/domain";
import { assessOpenClawRuntimeReadiness, formatOpenClawRuntimeLayers } from "../src/openclaw-runtime-readiness";

function createOpenClawSnapshot(overrides: Partial<ProjectOpenClawSnapshot> = {}): ProjectOpenClawSnapshot {
  return {
    config: {
      deploymentKind: "local",
      host: "127.0.0.1",
      port: 18789,
      useSSL: false,
      apiKey: "",
      defaultAgent: "default",
      timeout: 30,
      autoConnect: true,
      localBinaryPath: "/usr/local/bin/openclaw",
      container: {
        engine: "docker",
        containerName: "openclaw-dev",
        workspaceMountPath: "/workspace"
      },
      cliQuietMode: true,
      cliLogLevel: "warning"
    },
    isConnected: false,
    availableAgents: [],
    activeAgents: [],
    detectedAgents: [],
    connectionState: {
      phase: "idle",
      deploymentKind: "local",
      capabilities: {
        cliAvailable: false,
        gatewayReachable: false,
        gatewayAuthenticated: false,
        agentListingAvailable: false,
        sessionHistoryAvailable: false,
        gatewayAgentAvailable: false,
        gatewayChatAvailable: false,
        projectAttachmentSupported: false
      },
      health: {
        lastProbeAt: null,
        lastHeartbeatAt: null,
        latencyMs: null,
        degradationReason: null,
        lastMessage: null
      }
    },
    lastProbeReport: null,
    sessionBackupPath: null,
    sessionMirrorPath: null,
    lastSyncedAt: 1_700_000_000,
    ...overrides
  };
}

test("runtime readiness is ready when connected layers are all ready", () => {
  const openClaw = createOpenClawSnapshot({
    isConnected: true,
    connectionState: {
      phase: "ready",
      deploymentKind: "local",
      capabilities: {
        cliAvailable: true,
        gatewayReachable: true,
        gatewayAuthenticated: true,
        agentListingAvailable: true,
        sessionHistoryAvailable: true,
        gatewayAgentAvailable: true,
        gatewayChatAvailable: true,
        projectAttachmentSupported: true
      },
      health: {
        lastMessage: "Connected to OpenClaw CLI and gateway."
      }
    },
    lastProbeReport: {
      success: true,
      deploymentKind: "local",
      endpoint: "http://127.0.0.1:18789",
      layers: {
        transport: "ready",
        authentication: "ready",
        session: "ready",
        inventory: "ready"
      },
      capabilities: {
        cliAvailable: true,
        gatewayReachable: true,
        gatewayAuthenticated: true,
        agentListingAvailable: true,
        sessionHistoryAvailable: true,
        gatewayAgentAvailable: true,
        gatewayChatAvailable: true,
        projectAttachmentSupported: true
      },
      health: {
        lastMessage: "Connected to OpenClaw CLI and gateway."
      },
      availableAgents: ["planner"],
      message: "Connected to OpenClaw CLI and gateway.",
      warnings: [],
      sourceOfTruth: "test",
      observedDefaultTransports: ["cli", "ws"]
    }
  });

  const readiness = assessOpenClawRuntimeReadiness(openClaw);

  assert.equal(readiness.label, "Ready");
  assert.equal(readiness.blockingMessage, null);
  assert.equal(readiness.layers?.inventory, "ready");
  assert.equal(readiness.recoveryActions.length, 0);
  assert.equal(formatOpenClawRuntimeLayers(readiness.layers!), "transport=ready, auth=ready, session=ready, inventory=ready");
});

test("runtime readiness stays degraded when only inventory is stale", () => {
  const openClaw = createOpenClawSnapshot({
    isConnected: true,
    connectionState: {
      phase: "degraded",
      deploymentKind: "remoteServer",
      capabilities: {
        cliAvailable: false,
        gatewayReachable: true,
        gatewayAuthenticated: true,
        agentListingAvailable: false,
        sessionHistoryAvailable: true,
        gatewayAgentAvailable: true,
        gatewayChatAvailable: true,
        projectAttachmentSupported: false
      },
      health: {
        degradationReason: "Agent list is stale."
      }
    },
    lastProbeReport: {
      success: true,
      deploymentKind: "remoteServer",
      endpoint: "https://remote.example.com",
      layers: {
        transport: "ready",
        authentication: "ready",
        session: "ready",
        inventory: "degraded"
      },
      capabilities: {
        cliAvailable: false,
        gatewayReachable: true,
        gatewayAuthenticated: true,
        agentListingAvailable: false,
        sessionHistoryAvailable: true,
        gatewayAgentAvailable: true,
        gatewayChatAvailable: true,
        projectAttachmentSupported: false
      },
      health: {
        degradationReason: "Agent list is stale."
      },
      availableAgents: [],
      message: "Connected to remote OpenClaw gateway.",
      warnings: ["Probe layers: transport=ready, auth=ready, session=ready, inventory=degraded."],
      sourceOfTruth: "test",
      observedDefaultTransports: ["ws"]
    }
  });

  const readiness = assessOpenClawRuntimeReadiness(openClaw);

  assert.equal(readiness.label, "Degraded");
  assert.equal(readiness.blockingMessage, null);
  assert.match(readiness.advisoryMessages.join(" "), /inventory is degraded/i);
  assert.deepEqual(
    readiness.recoveryActions.map((action) => action.command),
    ["detect"]
  );
});

test("runtime readiness blocks detached sessions before live execution", () => {
  const openClaw = createOpenClawSnapshot({
    isConnected: false,
    connectionState: {
      phase: "detached",
      deploymentKind: "local",
      capabilities: {
        cliAvailable: false,
        gatewayReachable: false,
        gatewayAuthenticated: false,
        agentListingAvailable: false,
        sessionHistoryAvailable: false,
        gatewayAgentAvailable: false,
        gatewayChatAvailable: false,
        projectAttachmentSupported: false
      },
      health: {
        lastMessage: "Gateway websocket dropped."
      }
    }
  });

  const readiness = assessOpenClawRuntimeReadiness(openClaw);

  assert.equal(readiness.label, "Blocked");
  assert.equal(readiness.blockingMessage, "Gateway websocket dropped.");
  assert.deepEqual(readiness.recoveryActions.map((action) => action.command), ["connect"]);
});

test("runtime readiness keeps local CLI-only execution degraded but runnable", () => {
  const openClaw = createOpenClawSnapshot({
    isConnected: false,
    connectionState: {
      phase: "degraded",
      deploymentKind: "local",
      capabilities: {
        cliAvailable: true,
        gatewayReachable: false,
        gatewayAuthenticated: false,
        agentListingAvailable: true,
        sessionHistoryAvailable: false,
        gatewayAgentAvailable: false,
        gatewayChatAvailable: false,
        projectAttachmentSupported: true
      },
      health: {
        degradationReason: "Gateway probe failed."
      }
    }
  });

  const readiness = assessOpenClawRuntimeReadiness(openClaw);

  assert.equal(readiness.label, "Degraded");
  assert.equal(readiness.blockingMessage, null);
  assert.match(readiness.summary, /gateway probe failed/i);
  assert.equal(readiness.recoveryActions[0]?.command, "connect");
});

test("remote auth degradation recommends config review when credentials are missing", () => {
  const openClaw = createOpenClawSnapshot({
    config: {
      deploymentKind: "remoteServer",
      host: "remote.example.com",
      port: 443,
      useSSL: true,
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
    },
    isConnected: false,
    connectionState: {
      phase: "degraded",
      deploymentKind: "remoteServer",
      capabilities: {
        cliAvailable: false,
        gatewayReachable: true,
        gatewayAuthenticated: false,
        agentListingAvailable: false,
        sessionHistoryAvailable: false,
        gatewayAgentAvailable: false,
        gatewayChatAvailable: false,
        projectAttachmentSupported: false
      },
      health: {
        degradationReason: "Authentication rejected."
      }
    },
    lastProbeReport: {
      success: false,
      deploymentKind: "remoteServer",
      endpoint: "https://remote.example.com",
      layers: {
        transport: "ready",
        authentication: "degraded",
        session: "degraded",
        inventory: "unavailable"
      },
      capabilities: {
        cliAvailable: false,
        gatewayReachable: true,
        gatewayAuthenticated: false,
        agentListingAvailable: false,
        sessionHistoryAvailable: false,
        gatewayAgentAvailable: false,
        gatewayChatAvailable: false,
        projectAttachmentSupported: false
      },
      health: {
        degradationReason: "Authentication rejected."
      },
      availableAgents: [],
      message: "Authentication rejected.",
      warnings: [],
      sourceOfTruth: "test",
      observedDefaultTransports: ["ws"]
    }
  });

  const readiness = assessOpenClawRuntimeReadiness(openClaw);

  assert.equal(readiness.label, "Blocked");
  assert.deepEqual(
    readiness.recoveryActions.map((action) => action.command),
    ["connect", "review_config"]
  );
});
