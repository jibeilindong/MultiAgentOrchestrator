import type { SwiftDate } from "./types";

export const TASK_STATUSES = ["To Do", "In Progress", "Done", "Blocked"] as const;
export type TaskStatus = (typeof TASK_STATUSES)[number];

export const TASK_PRIORITIES = ["Low", "Medium", "High", "Critical"] as const;
export type TaskPriority = (typeof TASK_PRIORITIES)[number];

export interface Task {
  id: string;
  title: string;
  description: string;
  status: TaskStatus;
  priority: TaskPriority;
  assignedAgentID?: string | null;
  workflowNodeID?: string | null;
  createdBy?: string | null;
  createdAt: SwiftDate;
  startedAt?: SwiftDate | null;
  completedAt?: SwiftDate | null;
  estimatedDuration?: number | null;
  actualDuration?: number | null;
  tags: string[];
  metadata: Record<string, string>;
}
