import type {
  MAProject,
  OpenClawConfig,
  OpenClawConnectionCapabilitiesSnapshot,
  OpenClawConnectionHealthSnapshot,
  OpenClawConnectionStateSnapshot,
  ProjectMemoryData,
  ProjectOpenClawSnapshot,
  ProjectTaskDataSettings,
  RuntimeState,
  Workflow
} from "@multi-agent-flow/domain";
import { toSwiftDate } from "./swift-date";
import { createUUID } from "./uuid";

function createDefaultWorkflow(now: number): Workflow {
  return {
    id: createUUID(),
    name: "Main Workflow",
    fallbackRoutingPolicy: "stop",
    launchTestCases: [],
    lastLaunchVerificationReport: null,
    nodes: [],
    edges: [],
    boundaries: [],
    colorGroups: [],
    createdAt: now,
    parentNodeID: null,
    inputSchema: [],
    outputSchema: []
  };
}

function createDefaultOpenClawConfig(): OpenClawConfig {
  return {
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
      containerName: "",
      workspaceMountPath: "/workspace"
    },
    cliQuietMode: true,
    cliLogLevel: "warning"
  };
}

function createDefaultOpenClawCapabilities(): OpenClawConnectionCapabilitiesSnapshot {
  return {
    cliAvailable: false,
    gatewayReachable: false,
    gatewayAuthenticated: false,
    agentListingAvailable: false,
    sessionHistoryAvailable: false,
    gatewayAgentAvailable: false,
    gatewayChatAvailable: false,
    projectAttachmentSupported: false
  };
}

function createDefaultOpenClawHealth(): OpenClawConnectionHealthSnapshot {
  return {
    lastProbeAt: null,
    lastHeartbeatAt: null,
    latencyMs: null,
    degradationReason: null,
    lastMessage: null
  };
}

function createDefaultOpenClawConnectionState(): OpenClawConnectionStateSnapshot {
  return {
    phase: "idle",
    deploymentKind: "local",
    capabilities: createDefaultOpenClawCapabilities(),
    health: createDefaultOpenClawHealth()
  };
}

function createDefaultOpenClawSnapshot(now: number): ProjectOpenClawSnapshot {
  return {
    config: createDefaultOpenClawConfig(),
    isConnected: false,
    availableAgents: [],
    activeAgents: [],
    detectedAgents: [],
    connectionState: createDefaultOpenClawConnectionState(),
    lastProbeReport: null,
    sessionBackupPath: null,
    sessionMirrorPath: null,
    lastSyncedAt: now
  };
}

function createDefaultTaskDataSettings(now: number): ProjectTaskDataSettings {
  return {
    workspaceRootPath: null,
    organizationMode: "project/task",
    lastUpdatedAt: now
  };
}

function createDefaultMemoryData(): ProjectMemoryData {
  return {
    backupOnly: true,
    taskExecutionMemories: [],
    agentMemories: [],
    lastBackupAt: null
  };
}

function createDefaultRuntimeState(now: number): RuntimeState {
  return {
    sessionID: createUUID(),
    messageQueue: [],
    dispatchQueue: [],
    inflightDispatches: [],
    completedDispatches: [],
    failedDispatches: [],
    agentStates: {},
    runtimeEvents: [],
    lastUpdated: now
  };
}

export function createEmptyProject(name: string): MAProject {
  const now = toSwiftDate();

  return {
    id: createUUID(),
    fileVersion: "2.0",
    name,
    agents: [],
    workflows: [createDefaultWorkflow(now)],
    permissions: [],
    openClaw: createDefaultOpenClawSnapshot(now),
    taskData: createDefaultTaskDataSettings(now),
    tasks: [],
    messages: [],
    executionResults: [],
    executionLogs: [],
    workspaceIndex: [],
    memoryData: createDefaultMemoryData(),
    runtimeState: createDefaultRuntimeState(now),
    createdAt: now,
    updatedAt: now
  };
}
