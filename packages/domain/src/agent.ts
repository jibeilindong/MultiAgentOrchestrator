import type { Point, SwiftDate } from "./types";

export interface OpenClawProtocolCorrectionRecord {
  id: string;
  kind: string;
  message: string;
  count: number;
  lastSeenAt: SwiftDate;
}

export interface OpenClawAgentProtocolMemory {
  protocolVersion: string;
  stableRules: string[];
  recentCorrections: OpenClawProtocolCorrectionRecord[];
  repeatOffenses: OpenClawProtocolCorrectionRecord[];
  lastSessionDigest?: string | null;
  lastUpdatedAt: SwiftDate;
}

export interface OpenClawAgentDefinition {
  agentIdentifier: string;
  modelIdentifier: string;
  runtimeProfile: string;
  memoryBackupPath?: string | null;
  soulSourcePath?: string | null;
  environment: Record<string, string>;
  protocolMemory?: OpenClawAgentProtocolMemory;
}

export interface Agent {
  id: string;
  name: string;
  identity: string;
  description: string;
  soulMD: string;
  position: Point;
  createdAt: SwiftDate;
  updatedAt: SwiftDate;
  capabilities: string[];
  colorHex?: string | null;
  openClawDefinition: OpenClawAgentDefinition;
}
