import type { SwiftDate } from "./types";

export const OPENCLAW_CLI_LOG_LEVELS = ["error", "warning", "info", "debug"] as const;
export type OpenClawCLILogLevel = (typeof OPENCLAW_CLI_LOG_LEVELS)[number];

export const OPENCLAW_DEPLOYMENT_KINDS = ["local", "remoteServer", "container"] as const;
export type OpenClawDeploymentKind = (typeof OPENCLAW_DEPLOYMENT_KINDS)[number];

export interface OpenClawContainerConfig {
  engine: string;
  containerName: string;
  workspaceMountPath: string;
}

export interface OpenClawConfig {
  deploymentKind: OpenClawDeploymentKind;
  host: string;
  port: number;
  useSSL: boolean;
  apiKey: string;
  defaultAgent: string;
  timeout: number;
  autoConnect: boolean;
  localBinaryPath: string;
  container: OpenClawContainerConfig;
  cliQuietMode: boolean;
  cliLogLevel: OpenClawCLILogLevel;
}

export interface ProjectOpenClawAgentRecord {
  id: string;
  name: string;
  status: string;
  lastReloadedAt?: SwiftDate | null;
}

export interface ProjectOpenClawDetectedAgentRecord {
  id: string;
  name: string;
  directoryPath?: string | null;
  configPath?: string | null;
  soulPath?: string | null;
  workspacePath?: string | null;
  statePath?: string | null;
  directoryValidated: boolean;
  configValidated: boolean;
  copiedToProjectPath?: string | null;
  copiedFileCount: number;
  issues: string[];
  importedAt?: SwiftDate | null;
}

export const OPENCLAW_CONNECTION_PHASES = [
  "idle",
  "discovering",
  "probed",
  "ready",
  "degraded",
  "detached",
  "failed"
] as const;
export type OpenClawConnectionPhase = (typeof OPENCLAW_CONNECTION_PHASES)[number];

export interface OpenClawConnectionCapabilitiesSnapshot {
  cliAvailable: boolean;
  gatewayReachable: boolean;
  gatewayAuthenticated: boolean;
  agentListingAvailable: boolean;
  sessionHistoryAvailable: boolean;
  gatewayAgentAvailable: boolean;
  gatewayChatAvailable: boolean;
  projectAttachmentSupported: boolean;
}

export interface OpenClawConnectionHealthSnapshot {
  lastProbeAt?: SwiftDate | null;
  lastHeartbeatAt?: SwiftDate | null;
  latencyMs?: number | null;
  degradationReason?: string | null;
  lastMessage?: string | null;
}

export interface OpenClawConnectionStateSnapshot {
  phase: OpenClawConnectionPhase;
  deploymentKind: OpenClawDeploymentKind;
  capabilities: OpenClawConnectionCapabilitiesSnapshot;
  health: OpenClawConnectionHealthSnapshot;
}

export interface OpenClawProbeReportSnapshot {
  success: boolean;
  deploymentKind: OpenClawDeploymentKind;
  endpoint: string;
  capabilities: OpenClawConnectionCapabilitiesSnapshot;
  health: OpenClawConnectionHealthSnapshot;
  availableAgents: string[];
  message: string;
  warnings: string[];
  sourceOfTruth: string;
  observedDefaultTransports: string[];
}

export interface ProjectOpenClawSnapshot {
  config: OpenClawConfig;
  isConnected: boolean;
  availableAgents: string[];
  activeAgents: ProjectOpenClawAgentRecord[];
  detectedAgents: ProjectOpenClawDetectedAgentRecord[];
  connectionState: OpenClawConnectionStateSnapshot;
  lastProbeReport?: OpenClawProbeReportSnapshot | null;
  sessionBackupPath?: string | null;
  sessionMirrorPath?: string | null;
  lastSyncedAt: SwiftDate;
}
