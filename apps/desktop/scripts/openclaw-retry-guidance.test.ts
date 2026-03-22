import test from "node:test";
import assert from "node:assert/strict";
import type { OpenClawRecoveryReportSnapshot, ProjectOpenClawSnapshot } from "@multi-agent-flow/domain";
import { buildOpenClawRetryGuidance } from "../src/openclaw-retry-guidance";

function createRecoveryReport(overrides: Partial<OpenClawRecoveryReportSnapshot>): OpenClawRecoveryReportSnapshot {
  return {
    createdAt: 1_700_000_000,
    status: "completed",
    summary: "Recovery completed.",
    completedSteps: ["Reconnect OpenClaw"],
    manualSteps: [],
    findings: [],
    before: {
      label: "Blocked",
      summary: "before",
      layers: "transport=degraded, auth=degraded, session=degraded, inventory=ready"
    },
    after: {
      label: "Ready",
      summary: "after",
      layers: "transport=ready, auth=ready, session=ready, inventory=ready"
    },
    ...overrides
  };
}

function createOpenClawSnapshot(overrides: Partial<ProjectOpenClawSnapshot> = {}): ProjectOpenClawSnapshot {
  return {
    config: {
      deploymentKind: "local",
      runtimeOwnership: "externalLocal",
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
    },
    lastProbeReport: null,
    recoveryReports: [],
    sessionBackupPath: null,
    sessionMirrorPath: null,
    lastSyncedAt: 1_700_000_000,
    ...overrides
  };
}

test("retry guidance suggests auto retry when history shows successful recovery", () => {
  const guidance = buildOpenClawRetryGuidance(
    createOpenClawSnapshot({
      recoveryReports: [createRecoveryReport({ createdAt: 1_700_000_005 })]
    })
  );

  assert.equal(guidance.recommendation, "auto_retry");
  assert.deepEqual(guidance.suggestedCommands, ["connect"]);
});

test("retry guidance stops on manual follow-up requirements", () => {
  const guidance = buildOpenClawRetryGuidance(
    createOpenClawSnapshot({
      config: {
        deploymentKind: "remoteServer",
        runtimeOwnership: "appManaged",
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
    })
  );

  assert.equal(guidance.recommendation, "manual_first");
  assert.match(guidance.detail, /manual/i);
});

test("retry guidance avoids repeated failing loops without improvement", () => {
  const guidance = buildOpenClawRetryGuidance(
    createOpenClawSnapshot({
      recoveryReports: [
        createRecoveryReport({
          createdAt: 1_700_000_010,
          status: "failed",
          completedSteps: ["Reconnect OpenClaw"],
          before: { label: "Blocked", summary: "before", layers: "x" },
          after: { label: "Blocked", summary: "after", layers: "x" }
        }),
        createRecoveryReport({
          createdAt: 1_700_000_009,
          status: "failed",
          completedSteps: ["Reconnect OpenClaw"],
          before: { label: "Blocked", summary: "before", layers: "x" },
          after: { label: "Blocked", summary: "after", layers: "x" }
        })
      ]
    })
  );

  assert.equal(guidance.recommendation, "manual_first");
  assert.match(guidance.title, /Repeated retries/i);
});

test("retry guidance says no retry is needed when runtime is ready", () => {
  const guidance = buildOpenClawRetryGuidance(
    createOpenClawSnapshot({
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
          lastMessage: "Connected."
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
          lastMessage: "Connected."
        },
        availableAgents: ["planner"],
        message: "Connected.",
        warnings: [],
        sourceOfTruth: "test",
        observedDefaultTransports: ["cli", "ws"]
      }
    })
  );

  assert.equal(guidance.recommendation, "not_needed");
  assert.deepEqual(guidance.suggestedCommands, []);
});
