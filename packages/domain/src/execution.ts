import type { SwiftDate } from "./types";

export const EXECUTION_STATUSES = ["Idle", "Running", "Completed", "Failed", "Waiting"] as const;
export type ExecutionStatus = (typeof EXECUTION_STATUSES)[number];

export const EXECUTION_OUTPUT_TYPES = [
  "agent_final_response",
  "runtime_log",
  "error_summary",
  "empty"
] as const;
export type ExecutionOutputType = (typeof EXECUTION_OUTPUT_TYPES)[number];

export const EXECUTION_LOG_LEVELS = ["INFO", "WARN", "ERROR", "SUCCESS"] as const;
export type ExecutionLogLevel = (typeof EXECUTION_LOG_LEVELS)[number];

export interface ExecutionResult {
  id: string;
  nodeID: string;
  agentID: string;
  status: ExecutionStatus;
  output: string;
  outputType: ExecutionOutputType;
  routingAction?: string | null;
  routingTargets: string[];
  routingReason?: string | null;
  startedAt: SwiftDate;
  completedAt?: SwiftDate | null;
  duration?: number | null;
}

export interface ExecutionLogEntry {
  id: string;
  timestamp: SwiftDate;
  level: ExecutionLogLevel;
  message: string;
  nodeID?: string | null;
}
