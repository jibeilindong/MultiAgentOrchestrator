import type { Point, SwiftDate } from "./types";

export interface OpenClawAgentDefinition {
  agentIdentifier: string;
  modelIdentifier: string;
  runtimeProfile: string;
  memoryBackupPath?: string | null;
  soulSourcePath?: string | null;
  environment: Record<string, string>;
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
