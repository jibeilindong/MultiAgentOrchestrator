import type { Point, Rect, SwiftDate } from "./types";

export const WORKFLOW_FALLBACK_ROUTING_POLICIES = [
  "stop",
  "first_available",
  "all_available"
] as const;
export type WorkflowFallbackRoutingPolicy = (typeof WORKFLOW_FALLBACK_ROUTING_POLICIES)[number];

export const WORKFLOW_VERIFICATION_STATUSES = ["pass", "warn", "fail"] as const;
export type WorkflowVerificationStatus = (typeof WORKFLOW_VERIFICATION_STATUSES)[number];

export const CANVAS_GROUP_KINDS = ["node", "edge"] as const;
export type CanvasGroupKind = (typeof CANVAS_GROUP_KINDS)[number];

export const SUBFLOW_PARAMETER_TYPES = [
  "String",
  "Number",
  "Boolean",
  "Array",
  "Object"
] as const;
export type SubflowParameterType = (typeof SUBFLOW_PARAMETER_TYPES)[number];

export const WORKFLOW_NODE_TYPES = ["start", "agent"] as const;
export type WorkflowNodeType = (typeof WORKFLOW_NODE_TYPES)[number];

export interface WorkflowLaunchTestCase {
  id: string;
  name: string;
  prompt: string;
  requiredAgentNames: string[];
  forbiddenAgentNames: string[];
  expectedRoutingActions: string[];
  expectedOutputTypes: string[];
  maxSteps?: number | null;
  notes: string;
}

export interface WorkflowLaunchTestCaseReport {
  id: string;
  testCaseID: string;
  name: string;
  prompt: string;
  status: WorkflowVerificationStatus;
  actualStepCount: number;
  actualAgents: string[];
  actualRoutingActions: string[];
  actualRoutingTargets: string[];
  actualOutputTypes: string[];
  notes: string[];
}

export interface WorkflowLaunchVerificationReport {
  id: string;
  workflowID: string;
  workflowName: string;
  workflowSignature: string;
  startedAt: SwiftDate;
  completedAt?: SwiftDate | null;
  status: WorkflowVerificationStatus;
  staticFindings: string[];
  runtimeFindings: string[];
  testCaseReports: WorkflowLaunchTestCaseReport[];
}

export interface WorkflowBoundary {
  id: string;
  title: string;
  rect: Rect;
  memberNodeIDs: string[];
  createdAt: SwiftDate;
  updatedAt: SwiftDate;
}

export interface SubflowParameter {
  id: string;
  name: string;
  type: SubflowParameterType;
  value: string;
  isInput: boolean;
}

export interface CanvasColorGroup {
  kind: CanvasGroupKind;
  colorHex: string;
  title: string;
}

export interface WorkflowNode {
  id: string;
  agentID?: string | null;
  type: WorkflowNodeType;
  position: Point;
  title: string;
  displayColorHex?: string | null;
  conditionExpression: string;
  loopEnabled: boolean;
  maxIterations: number;
  subflowID?: string | null;
  nestingLevel: number;
  inputParameters: SubflowParameter[];
  outputParameters: SubflowParameter[];
}

export interface WorkflowEdge {
  id: string;
  fromNodeID: string;
  toNodeID: string;
  label: string;
  displayColorHex?: string | null;
  conditionExpression: string;
  requiresApproval: boolean;
  isBidirectional: boolean;
  dataMapping: Record<string, string>;
}

export interface Workflow {
  id: string;
  name: string;
  fallbackRoutingPolicy: WorkflowFallbackRoutingPolicy;
  launchTestCases: WorkflowLaunchTestCase[];
  lastLaunchVerificationReport?: WorkflowLaunchVerificationReport | null;
  nodes: WorkflowNode[];
  edges: WorkflowEdge[];
  boundaries: WorkflowBoundary[];
  colorGroups: CanvasColorGroup[];
  createdAt: SwiftDate;
  parentNodeID?: string | null;
  inputSchema: SubflowParameter[];
  outputSchema: SubflowParameter[];
}
