import type { Agent } from "./agent";
import type { ExecutionLogEntry, ExecutionResult } from "./execution";
import type { Message } from "./message";
import type { ProjectOpenClawSnapshot } from "./openclaw";
import type { Permission } from "./permission";
import type { Task } from "./task";
import type { SwiftDate } from "./types";
import type { Workflow } from "./workflow";
import type { OpenClawRuntimeEvent } from "./openclaw-runtime";

export interface RuntimeState {
  sessionID: string;
  messageQueue: string[];
  agentStates: Record<string, string>;
  runtimeEvents: OpenClawRuntimeEvent[];
  lastUpdated: SwiftDate;
}

export interface ProjectWorkspaceRecord {
  id: string;
  taskID: string;
  workspaceRelativePath: string;
  workspaceName: string;
  createdAt: SwiftDate;
  updatedAt: SwiftDate;
}

export interface ProjectTaskDataSettings {
  workspaceRootPath?: string | null;
  organizationMode: string;
  lastUpdatedAt: SwiftDate;
}

export interface TaskMemoryBackupRecord {
  id: string;
  taskID: string;
  workspaceRelativePath: string;
  backupLabel: string;
  lastCapturedAt: SwiftDate;
}

export interface AgentMemoryBackupRecord {
  id: string;
  agentID: string;
  agentName: string;
  sourcePath?: string | null;
  lastCapturedAt: SwiftDate;
}

export interface ProjectMemoryData {
  backupOnly: boolean;
  taskExecutionMemories: TaskMemoryBackupRecord[];
  agentMemories: AgentMemoryBackupRecord[];
  lastBackupAt?: SwiftDate | null;
}

export interface MAProject {
  id: string;
  fileVersion: string;
  name: string;
  agents: Agent[];
  workflows: Workflow[];
  permissions: Permission[];
  openClaw: ProjectOpenClawSnapshot;
  taskData: ProjectTaskDataSettings;
  tasks: Task[];
  messages: Message[];
  executionResults: ExecutionResult[];
  executionLogs: ExecutionLogEntry[];
  workspaceIndex: ProjectWorkspaceRecord[];
  memoryData: ProjectMemoryData;
  runtimeState: RuntimeState;
  createdAt: SwiftDate;
  updatedAt: SwiftDate;
}
