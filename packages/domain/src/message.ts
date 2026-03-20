import type { SwiftDate } from "./types";
import type { OpenClawRuntimeEvent } from "./openclaw-runtime";

export const MESSAGE_STATUSES = [
  "Pending",
  "Sent",
  "Delivered",
  "Read",
  "Failed",
  "Waiting for Approval",
  "Approved",
  "Rejected"
] as const;
export type MessageStatus = (typeof MESSAGE_STATUSES)[number];

export const MESSAGE_TYPES = ["Text", "Task", "Command", "Data", "Notification"] as const;
export type MessageType = (typeof MESSAGE_TYPES)[number];

export interface Message {
  id: string;
  fromAgentID: string;
  toAgentID: string;
  type: MessageType;
  content: string;
  timestamp: SwiftDate;
  status: MessageStatus;
  metadata: Record<string, string>;
  runtimeEvent?: OpenClawRuntimeEvent | null;
  requiresApproval: boolean;
  approvedBy?: string | null;
  approvalTimestamp?: SwiftDate | null;
}
