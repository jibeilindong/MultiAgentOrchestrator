import {
  addAgentToProject,
  addNodeToWorkflow,
  addTaskToProject,
  appendOpenClawRecoveryReport,
  addWorkflowLaunchTestCase,
  addWorkflowToProject,
  assessWorkflowRuntimeIsolation,
  assignAgentToNode,
  assignAgentToNodes,
  assignTaskToAgent,
  calculateWorkflowLaunchVerificationSignature,
  connectWorkflowNodes,
  evaluateWorkflowLaunchTestCase,
  finalizeWorkflowLaunchVerification,
  fromSwiftDate,
  toSwiftDate,
  type WorkflowLaunchExecutionObservation,
  generateTasksFromWorkflow,
  moveTaskToStatus,
  resolveProjectAgentWorkspacePaths,
  resolveWorkflowLaunchTestCases,
  runWorkflowLaunchVerification,
  repositionWorkflowNode,
  repositionWorkflowNodes,
  removeEdgeFromWorkflow,
  removeWorkflowLaunchTestCase,
  removeNodesFromWorkflow,
  removeTaskFromProject,
  removeWorkflowFromProject,
  renameProject,
  renameWorkflow,
  renameWorkflowNode,
  reviewWorkbenchApproval,
  publishWorkbenchPrompt,
  publishWorkbenchPromptWithLiveExecution,
  setWorkflowEdgeApprovalRequired,
  setWorkflowEdgeBidirectional,
  setWorkflowFallbackRoutingPolicy,
  reviewWorkbenchApprovalWithLiveExecution,
  syncOpenClawState,
  importDetectedOpenClawAgents,
  isRuntimeAgentIdentifierValid,
  updateAgentInProject,
  updateWorkflowLaunchTestCase,
  updateOpenClawConfig,
  updateOpenClawSessionPaths,
  summarizeOpenClawGovernancePreflight,
  updateProjectTaskDataSettings,
  updateTaskInProject,
  updateWorkflowEdgeLabel
} from "@multi-agent-flow/core";
import type {
  MAProject,
  Message,
  OpenClawCLILogLevel,
  OpenClawDeploymentKind,
  TaskPriority,
  TaskStatus,
  Workflow,
  WorkflowEdge,
  WorkflowFallbackRoutingPolicy,
  WorkflowLaunchTestCase,
  WorkflowVerificationStatus,
  WorkflowNodeType
} from "@multi-agent-flow/domain";
import {
  OPENCLAW_CLI_LOG_LEVELS,
  OPENCLAW_DEPLOYMENT_KINDS,
  TASK_PRIORITIES,
  TASK_STATUSES
} from "@multi-agent-flow/domain";
import { startTransition, useEffect, useState } from "react";
import { WorkflowCanvasPreview } from "./components/WorkflowCanvasPreview";
import { buildOpenClawRecoveryAudit, formatOpenClawRecoveryStatus } from "./openclaw-recovery-audit";
import { buildOpenClawRecoveryReport } from "./openclaw-recovery-report";
import { buildOpenClawRetryGuidance } from "./openclaw-retry-guidance";
import { buildOpenClawRetryPolicy } from "./openclaw-retry-policy";
import { assessOpenClawRuntimeReadiness, formatOpenClawRuntimeLayers } from "./openclaw-runtime-readiness";

type BusyAction = "new" | "open" | "save" | "saveAs" | null;

interface ProjectFileHandle {
  project: MAProject;
  filePath: string | null;
}

interface RecentProjectRecord {
  name: string;
  filePath: string;
  updatedAt: string;
}

interface AutosaveInfo {
  autosavePath: string;
  savedAt: string;
}

interface ProjectHistoryState {
  past: MAProject[];
  future: MAProject[];
}

const MIN_CANVAS_ZOOM = 0.5;
const MAX_CANVAS_ZOOM = 1.8;
const DEFAULT_CANVAS_ZOOM = 1;
const MAX_HISTORY_ENTRIES = 60;
const CANVAS_NODE_WIDTH = 188;
const CANVAS_NODE_HEIGHT = 92;
const TASK_STATUS_ACCENTS: Record<TaskStatus, string> = {
  "To Do": "todo",
  "In Progress": "in-progress",
  Done: "done",
  Blocked: "blocked"
};

function toClassToken(value: string): string {
  return value.toLowerCase().replace(/\s+/g, "-");
}

function parseTagInput(value: string): string[] {
  return Array.from(
    new Set(
      value
        .split(",")
        .map((tag) => tag.trim())
        .filter(Boolean)
    )
  );
}

function parseMetadataCsv(value?: string): string[] {
  if (!value) {
    return [];
  }

  return value
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function formatCsvInput(values: string[]): string {
  return values.join(", ");
}

function parseKeyValueLines(value: string): Record<string, string> {
  return Object.fromEntries(
    value
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean)
      .map((line) => {
        const separatorIndex = line.indexOf("=");
        if (separatorIndex < 0) {
          return [line, ""];
        }
        return [line.slice(0, separatorIndex).trim(), line.slice(separatorIndex + 1).trim()];
      })
      .filter(([key, lineValue]) => key.length > 0 && lineValue.length > 0)
  );
}

function formatKeyValueLines(value: Record<string, string>): string {
  return Object.entries(value)
    .map(([key, itemValue]) => `${key}=${itemValue}`)
    .join("\n");
}

function resolveWorkbenchMessageTone(message: Message): "user" | "assistant" | "system" | "approval" {
  if (message.status === "Waiting for Approval" || message.metadata.kind === "approval") {
    return "approval";
  }

  const role = message.metadata.role;
  if (role === "user") {
    return "user";
  }
  if (role === "assistant") {
    return "assistant";
  }
  return "system";
}

function resolveEntryAgentNodeIds(project: MAProject, workflowId: string): string[] {
  const workflow = project.workflows.find((item) => item.id === workflowId);
  if (!workflow) {
    return [];
  }

  const startNodeIds = new Set(workflow.nodes.filter((node) => node.type === "start").map((node) => node.id));
  const nodeMap = new Map(workflow.nodes.map((node) => [node.id, node] as const));
  const candidateIds = workflow.edges
    .filter((edge) => startNodeIds.has(edge.fromNodeID))
    .map((edge) => nodeMap.get(edge.toNodeID))
    .filter((node): node is NonNullable<typeof node> => Boolean(node && node.type === "agent" && node.agentID))
    .sort((left, right) => {
      if (left.position.y !== right.position.y) {
        return left.position.y - right.position.y;
      }
      if (left.position.x !== right.position.x) {
        return left.position.x - right.position.x;
      }
      return left.title.localeCompare(right.title);
    })
    .map((node) => node.id);

  return Array.from(new Set(candidateIds));
}

function buildSuggestedLaunchTestCaseDraft(project: MAProject, workflow: Workflow) {
  const entryNodeIds = new Set(resolveEntryAgentNodeIds(project, workflow.id));
  const agentNameById = new Map(
    project.agents.map((agent) => [agent.id, agent.name.trim()] as const)
  );
  const requiredAgentNames = Array.from(
    new Set(
      workflow.nodes
        .filter((node) => entryNodeIds.has(node.id) && node.agentID)
        .map((node) => agentNameById.get(node.agentID ?? ""))
        .filter((name): name is string => Boolean(name))
    )
  );
  const forbiddenAgentNames = Array.from(
    new Set(
      workflow.nodes
        .filter((node) => node.type === "agent" && !entryNodeIds.has(node.id) && node.agentID)
        .map((node) => agentNameById.get(node.agentID ?? ""))
        .filter((name): name is string => Boolean(name))
    )
  );

  return {
    name: `Launch Case ${workflow.launchTestCases.length + 1}`,
    prompt: "Reply with a concise readiness confirmation unless downstream collaboration is truly required.",
    requiredAgentNames,
    forbiddenAgentNames,
    expectedRoutingActions: [],
    expectedOutputTypes: ["agent_final_response"],
    maxSteps: requiredAgentNames.length > 0 ? Math.max(1, requiredAgentNames.length) : null,
    notes: "Tighten these expectations to match your real launch contract before shipping."
  };
}

function resolveRuntimeAgentIdentifier(project: MAProject, agentId: string | null | undefined): string {
  const agent = project.agents.find((item) => item.id === agentId) ?? null;
  const candidates = [
    agent?.openClawDefinition.agentIdentifier,
    agent?.name,
    project.openClaw.config.defaultAgent
  ];
  for (const candidate of candidates) {
    const trimmed = candidate?.trim();
    if (trimmed) {
      return trimmed;
    }
  }
  return "default";
}

function describeRuntimeAgentIdentifier(identifier: string): string {
  return isRuntimeAgentIdentifierValid(identifier)
    ? "Runtime ID is ready for OpenClaw and session spawning."
    : "Runtime ID must use lowercase letters, digits, hyphens, or underscores.";
}

function normalizeRouteKey(value: string): string {
  return value.trim().toLowerCase();
}

function buildWorkflowOutgoingEdges(workflow: Workflow): Map<string, WorkflowEdge[]> {
  const outgoing = new Map<string, WorkflowEdge[]>();
  for (const edge of workflow.edges) {
    const current = outgoing.get(edge.fromNodeID) ?? [];
    current.push(edge);
    outgoing.set(edge.fromNodeID, current);

    if (edge.isBidirectional) {
      const reversed = outgoing.get(edge.toNodeID) ?? [];
      reversed.push({
        ...edge,
        fromNodeID: edge.toNodeID,
        toNodeID: edge.fromNodeID
      });
      outgoing.set(edge.toNodeID, reversed);
    }
  }
  return outgoing;
}

interface LiveExecutionGuardrails {
  writeScope: string[];
  toolScope: string[];
  requiresApproval: boolean;
  fallbackRoutingPolicy: WorkflowFallbackRoutingPolicy;
  directTargetKeys: string[];
  approvalTargetKeys: string[];
}

function resolveDetectedWorkspacePaths(project: MAProject, agentId: string): string[] {
  const agent = project.agents.find((item) => item.id === agentId) ?? null;
  if (!agent) {
    return [];
  }
  return resolveProjectAgentWorkspacePaths(project, agent);
}

interface LiveExecutionPreflightResult {
  blocked: boolean;
  message: string | null;
  advisoryMessage: string | null;
  governanceReport: OpenClawGovernanceAuditReport | null;
}

interface OpenClawGovernanceRemediationSummary {
  appliedActionTitles: string[];
  skippedActionTitles: string[];
  fixedFindingTitles: string[];
  remainingFailTitles: string[];
  remainingUnknownTitles: string[];
}

interface LiveWorkflowExecutionResult {
  liveExecutions: Parameters<typeof publishWorkbenchPromptWithLiveExecution>[3];
  approvalCheckpoints: Parameters<typeof publishWorkbenchPromptWithLiveExecution>[4];
  errorMessage: string | null;
  blocked: boolean;
  advisoryMessage: string | null;
}

function shouldAttemptLiveApprovalContinuation(
  project: MAProject,
  message: Message | null,
  workflow: Workflow | null,
  targetNodeId: string | null | undefined
): {
  shouldAttempt: boolean;
  blockingMessage: string | null;
} {
  if (message?.metadata.liveExecution !== "true") {
    return { shouldAttempt: false, blockingMessage: null };
  }

  const runtimeReadiness = assessOpenClawRuntimeReadiness(project.openClaw);
  if (runtimeReadiness.blockingMessage) {
    return {
      shouldAttempt: false,
      blockingMessage: runtimeReadiness.blockingMessage
    };
  }

  if (!workflow || !targetNodeId) {
    return {
      shouldAttempt: false,
      blockingMessage: "Approval could not continue because the downstream workflow target is missing."
    };
  }

  return {
    shouldAttempt: true,
    blockingMessage: null
  };
}

async function evaluateLiveExecutionPreflight(project: MAProject, workflow: Workflow): Promise<LiveExecutionPreflightResult> {
  const assessment = assessWorkflowRuntimeIsolation(project, workflow);
  const runtimeReadiness = assessOpenClawRuntimeReadiness(project.openClaw);
  const advisories: string[] = [...runtimeReadiness.advisoryMessages];
  if (assessment.blockingFindings.length > 0) {
    advisories.push(assessment.blockingFindings.join(" "));
  }

  if (runtimeReadiness.blockingMessage) {
    return {
      blocked: true,
      message: runtimeReadiness.blockingMessage,
      advisoryMessage: advisories.length > 0 ? advisories.join(" ") : null,
      governanceReport: null
    };
  }

  const workflowAgentIdentifiers = Array.from(
    new Set(
      assessment.workflowAgents
        .map((agent) => resolveRuntimeAgentIdentifier(project, agent.id))
        .map((value) => value.trim())
        .filter(Boolean)
    )
  );

  const runtimeSecurity = await requireDesktopApi().inspectOpenClawRuntimeSecurity(
    project.openClaw.config,
    workflowAgentIdentifiers
  );
  if (runtimeSecurity.blockingIssues.length > 0) {
    advisories.push(runtimeSecurity.blockingIssues.join(" "));
  }

  let governanceReport: OpenClawGovernanceAuditReport | null = null;
  try {
    governanceReport = await requireDesktopApi().auditOpenClawRuntimeGovernance(project.openClaw.config);
    const governanceAdvisory = summarizeOpenClawGovernancePreflight(governanceReport);
    if (governanceAdvisory) {
      advisories.push(governanceAdvisory);
    }
  } catch (actionError) {
    advisories.push(
      `Unable to refresh the OpenClaw governance audit during startup preflight: ${
        actionError instanceof Error ? actionError.message : String(actionError)
      }`
    );
  }

  return {
    blocked: false,
    message: null,
    advisoryMessage: advisories.length > 0 ? advisories.join(" ") : null,
    governanceReport
  };
}

function buildLiveExecutionGuardrails(
  project: MAProject,
  workflow: Workflow,
  nodeId: string,
  agentId: string
): LiveExecutionGuardrails {
  const agent = project.agents.find((item) => item.id === agentId) ?? null;
  const outgoingEdges = buildWorkflowOutgoingEdges(workflow).get(nodeId) ?? [];
  const nodeMap = new Map(workflow.nodes.map((node) => [node.id, node] as const));

  const directTargetKeys: string[] = [];
  const approvalTargetKeys: string[] = [];

  for (const edge of outgoingEdges) {
    const targetNode = nodeMap.get(edge.toNodeID);
    const targetAgent = project.agents.find((item) => item.id === targetNode?.agentID) ?? null;
    const identifier = targetAgent?.openClawDefinition.agentIdentifier?.trim() || targetAgent?.name?.trim() || targetNode?.id;
    if (!identifier) {
      continue;
    }

    if (edge.requiresApproval) {
      approvalTargetKeys.push(identifier);
    } else {
      directTargetKeys.push(identifier);
    }
  }

  const toolScope = Array.from(
    new Set(
      [
        ...(agent?.capabilities ?? [])
          .map((value) => normalizeRouteKey(value).replace(/[^a-z0-9._-]/g, "-"))
          .filter((value) => value && value !== "basic"),
        ...(outgoingEdges.length > 0 ? ["workflow.route"] : [])
      ]
    )
  ).sort((left, right) => left.localeCompare(right));

  return {
    writeScope: resolveDetectedWorkspacePaths(project, agentId),
    toolScope,
    requiresApproval: approvalTargetKeys.length > 0,
    fallbackRoutingPolicy: workflow.fallbackRoutingPolicy,
    directTargetKeys: Array.from(new Set(directTargetKeys)).sort((left, right) => left.localeCompare(right)),
    approvalTargetKeys: Array.from(new Set(approvalTargetKeys)).sort((left, right) => left.localeCompare(right))
  };
}

function augmentLiveExecutionPrompt(prompt: string, guardrails: LiveExecutionGuardrails): string {
  const sections = [prompt.trim()];
  const allowedTargetsText =
    guardrails.directTargetKeys.length > 0 ? guardrails.directTargetKeys.join(", ") : "(none)";
  const approvalTargetsText =
    guardrails.approvalTargetKeys.length > 0 ? guardrails.approvalTargetKeys.join(", ") : "(none)";
  const writeScopeText = guardrails.writeScope.length > 0 ? guardrails.writeScope.join(", ") : "(unresolved)";
  const toolScopeText = guardrails.toolScope.length > 0 ? guardrails.toolScope.join(", ") : "(unresolved)";

  sections.push(
    [
      "Runtime Guardrails:",
      `- Allowed downstream targets: ${allowedTargetsText}`,
      `- Approval-required downstream targets: ${approvalTargetsText}`,
      `- Restrict writes to: ${writeScopeText}`,
      `- Limit tools to: ${toolScopeText}`,
      "- Do not directly contact approval-required targets; request routing instead."
    ].join("\n")
  );

  return sections.filter(Boolean).join("\n\n");
}

function resolveLiveRoutingTargets(
  project: MAProject,
  workflow: Workflow,
  nodeId: string,
  routingDecision: OpenClawRoutingDecision | null
): Array<{ edge: WorkflowEdge; targetNodeId: string }> {
  const outgoingEdges = buildWorkflowOutgoingEdges(workflow).get(nodeId) ?? [];
  if (outgoingEdges.length === 0 || !routingDecision) {
    return [];
  }

  if (routingDecision.action === "stop") {
    return [];
  }

  if (routingDecision.action === "all") {
    return outgoingEdges.map((edge) => ({ edge, targetNodeId: edge.toNodeID }));
  }

  const nodeMap = new Map(workflow.nodes.map((node) => [node.id, node] as const));
  const requested = new Set(routingDecision.targets.map(normalizeRouteKey).filter(Boolean));
  if (requested.size === 0) {
    return [];
  }

  return outgoingEdges.filter((edge) => {
    const targetNode = nodeMap.get(edge.toNodeID);
    const targetAgent =
      project.agents.find((agent) => agent.id === targetNode?.agentID) ?? null;
    const candidateKeys = [
      targetNode?.id,
      targetNode?.id.slice(0, 8),
      targetNode?.title,
      targetAgent?.name,
      targetAgent?.openClawDefinition.agentIdentifier
    ]
      .filter((value): value is string => Boolean(value))
      .map(normalizeRouteKey);
    return candidateKeys.some((key) => requested.has(key));
  }).map((edge) => ({ edge, targetNodeId: edge.toNodeID }));
}

function formatDate(value?: number | null): string {
  if (value == null) {
    return "Not recorded";
  }

  return fromSwiftDate(value).toLocaleString();
}

function formatDuration(value?: number | null): string {
  if (value == null) {
    return "Not recorded";
  }

  const totalSeconds = Math.max(0, Math.round(value));
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;

  if (hours > 0) {
    return `${hours}h ${minutes}m`;
  }

  if (minutes > 0) {
    return `${minutes}m ${seconds}s`;
  }

  return `${seconds}s`;
}

function formatPercent(value: number): string {
  return `${Math.round(value * 100)}%`;
}

function arraysEqual(left: string[], right: string[]): boolean {
  if (left.length !== right.length) {
    return false;
  }

  return left.every((value, index) => value === right[index]);
}

function summarizeOpenClawGovernanceRemediation(
  previousReport: OpenClawGovernanceAuditReport | null,
  nextReport: OpenClawGovernanceAuditReport,
  appliedActionIds: string[],
  skippedActionIds: string[]
): OpenClawGovernanceRemediationSummary {
  const actionTitleById = new Map(
    [...(previousReport?.proposedActions ?? []), ...nextReport.proposedActions].map((action) => [action.id, action.title] as const)
  );
  const previousStatusById = new Map((previousReport?.findings ?? []).map((finding) => [finding.id, finding.status] as const));

  return {
    appliedActionTitles: appliedActionIds.map((actionId) => actionTitleById.get(actionId) ?? actionId),
    skippedActionTitles: skippedActionIds.map((actionId) => actionTitleById.get(actionId) ?? actionId),
    fixedFindingTitles: nextReport.findings
      .filter((finding) => previousStatusById.get(finding.id) !== "pass" && finding.status === "pass")
      .map((finding) => finding.title),
    remainingFailTitles: nextReport.findings.filter((finding) => finding.status === "fail").map((finding) => finding.title),
    remainingUnknownTitles: nextReport.findings.filter((finding) => finding.status === "unknown").map((finding) => finding.title)
  };
}

function formatRelativeDate(value?: number | null): string {
  if (value == null) {
    return "No recent activity";
  }

  const date = fromSwiftDate(value);
  const diffMs = Date.now() - date.getTime();
  const diffMinutes = Math.max(0, Math.round(diffMs / 60000));

  if (diffMinutes < 1) {
    return "just now";
  }

  if (diffMinutes < 60) {
    return `${diffMinutes}m ago`;
  }

  const diffHours = Math.round(diffMinutes / 60);
  if (diffHours < 24) {
    return `${diffHours}h ago`;
  }

  const diffDays = Math.round(diffHours / 24);
  return `${diffDays}d ago`;
}

function verificationStatusLabel(status: WorkflowVerificationStatus): string {
  switch (status) {
    case "pass":
      return "Pass";
    case "warn":
      return "Warn";
    case "fail":
      return "Fail";
  }
}

function verificationStatusToken(status: WorkflowVerificationStatus): string {
  switch (status) {
    case "pass":
      return "done";
    case "warn":
      return "in-progress";
    case "fail":
      return "blocked";
  }
}

function computeOpenClawReadiness(project: MAProject) {
  const checks: boolean[] = [];
  const issues: string[] = [];
  const config = project.openClaw.config;

  checks.push(config.defaultAgent.trim().length > 0);
  if (config.defaultAgent.trim().length === 0) {
    issues.push("Set a default OpenClaw agent.");
  }

  checks.push(config.timeout > 0);
  if (config.timeout <= 0) {
    issues.push("Timeout should be greater than 0.");
  }

  switch (config.deploymentKind) {
    case "local":
      checks.push(true);
      break;
    case "remoteServer":
      checks.push(config.host.trim().length > 0);
      checks.push(config.port > 0);
      if (config.host.trim().length === 0) {
        issues.push("Set the OpenClaw host.");
      }
      if (config.port <= 0) {
        issues.push("Set a valid OpenClaw port.");
      }
      break;
    case "container":
      checks.push(config.container.containerName.trim().length > 0);
      checks.push(config.container.workspaceMountPath.trim().length > 0);
      if (config.container.containerName.trim().length === 0) {
        issues.push("Set the container name.");
      }
      if (config.container.workspaceMountPath.trim().length === 0) {
        issues.push("Set the container workspace mount path.");
      }
      break;
  }

  const passedChecks = checks.filter(Boolean).length;
  const score = checks.length > 0 ? passedChecks / checks.length : 0;

  return {
    score,
    label: score >= 1 ? "Ready" : score >= 0.66 ? "Needs attention" : "Not ready",
    issues
  };
}

function isEditableTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) {
    return false;
  }

  return Boolean(target.closest("input, textarea, select, [contenteditable='true']"));
}

function requireDesktopApi() {
  const api = window.desktopApi;
  if (!api) {
    throw new Error("desktopApi is unavailable. Run this UI through the Electron shell.");
  }

  return api;
}

export function App() {
  const [projectState, setProjectState] = useState<ProjectFileHandle | null>(null);
  const [projectHistory, setProjectHistory] = useState<ProjectHistoryState>({ past: [], future: [] });
  const [recentProjects, setRecentProjects] = useState<RecentProjectRecord[]>([]);
  const [autosaveInfo, setAutosaveInfo] = useState<AutosaveInfo | null>(null);
  const [busyAction, setBusyAction] = useState<BusyAction>(null);
  const [status, setStatus] = useState("Bootstrapping cross-platform workspace...");
  const [error, setError] = useState<string | null>(null);
  const [newAgentName, setNewAgentName] = useState("New Agent");
  const [newWorkflowName, setNewWorkflowName] = useState("Workflow");
  const [newTaskTitle, setNewTaskTitle] = useState("");
  const [newTaskDescription, setNewTaskDescription] = useState("");
  const [newTaskPriority, setNewTaskPriority] = useState<TaskPriority>("Medium");
  const [newTaskAgentId, setNewTaskAgentId] = useState("");
  const [newTaskTags, setNewTaskTags] = useState("");
  const [verificationAction, setVerificationAction] = useState<"run" | null>(null);
  const [workbenchPrompt, setWorkbenchPrompt] = useState("");
  const [workbenchError, setWorkbenchError] = useState<string | null>(null);
  const [workbenchAction, setWorkbenchAction] = useState<"publish" | `approval:${string}` | null>(null);
  const [openClawAction, setOpenClawAction] = useState<"detect" | "connect" | "disconnect" | "import" | "recover" | null>(null);
  const [openClawGovernanceAction, setOpenClawGovernanceAction] = useState<"audit" | "remediate" | null>(null);
  const [openClawGovernanceReport, setOpenClawGovernanceReport] = useState<OpenClawGovernanceAuditReport | null>(null);
  const [openClawGovernanceNotes, setOpenClawGovernanceNotes] = useState<string[]>([]);
  const [openClawGovernanceBackupPaths, setOpenClawGovernanceBackupPaths] = useState<string[]>([]);
  const [openClawGovernanceSelectedActionIds, setOpenClawGovernanceSelectedActionIds] = useState<string[]>([]);
  const [openClawGovernanceLastRemediation, setOpenClawGovernanceLastRemediation] =
    useState<OpenClawGovernanceRemediationSummary | null>(null);
  const [activeWorkflowId, setActiveWorkflowId] = useState<string | null>(null);
  const [selectedNodeId, setSelectedNodeId] = useState<string | null>(null);
  const [selectedNodeIds, setSelectedNodeIds] = useState<string[]>([]);
  const [selectedEdgeId, setSelectedEdgeId] = useState<string | null>(null);
  const [selectedTaskId, setSelectedTaskId] = useState<string | null>(null);
  const [canvasZoom, setCanvasZoom] = useState(DEFAULT_CANVAS_ZOOM);
  const [newNodeType, setNewNodeType] = useState<WorkflowNodeType>("agent");
  const [connectionFromNodeId, setConnectionFromNodeId] = useState("");
  const [connectionToNodeId, setConnectionToNodeId] = useState("");
  const project = projectState?.project ?? null;
  const filePath = projectState?.filePath ?? null;
  const activeWorkflow =
    project?.workflows.find((workflow) => workflow.id === activeWorkflowId) ?? project?.workflows[0] ?? null;
  const launchVerificationReport = activeWorkflow?.lastLaunchVerificationReport ?? null;
  const currentLaunchVerificationSignature =
    project && activeWorkflow
      ? calculateWorkflowLaunchVerificationSignature(activeWorkflow, project.agents)
      : null;
  const launchVerificationIsStale = Boolean(
    launchVerificationReport &&
      currentLaunchVerificationSignature &&
      launchVerificationReport.workflowSignature !== currentLaunchVerificationSignature
  );
  const selectedNode =
    selectedNodeIds.length === 1
      ? activeWorkflow?.nodes.find((node) => node.id === selectedNodeIds[0]) ?? null
      : null;
  const selectedNodes = activeWorkflow?.nodes.filter((node) => selectedNodeIds.includes(node.id)) ?? [];
  const openClawRecoveryReports = project?.openClaw.recoveryReports ?? [];
  const openClawLastRecoveryReport = openClawRecoveryReports[0] ?? null;
  const openClawRecoveryAudit = buildOpenClawRecoveryAudit(openClawRecoveryReports);
  const openClawRetryGuidance = project ? buildOpenClawRetryGuidance(project.openClaw) : null;
  const openClawRetryPolicy = project ? buildOpenClawRetryPolicy(project.openClaw) : null;
  const selectedEdge =
    activeWorkflow?.edges.find((edge) => edge.id === selectedEdgeId) ?? null;
  const selectedTask = project?.tasks.find((task) => task.id === selectedTaskId) ?? null;
  const canUndo = projectHistory.past.length > 0;
  const canRedo = projectHistory.future.length > 0;
  const multiSelectedAgentId =
    selectedNodes.length > 1
      ? selectedNodes.every((node) => node.agentID === (selectedNodes[0]?.agentID ?? null))
        ? (selectedNodes[0]?.agentID ?? "")
        : "__mixed__"
      : "";

  useEffect(() => {
    let cancelled = false;

    async function bootstrap() {
      try {
        const api = requireDesktopApi();
        const [created, recent] = await Promise.all([
          api.createProject("Migration Preview"),
          api.listRecentProjects()
        ]);
        if (cancelled) {
          return;
        }

        startTransition(() => {
          setProjectState(created);
          setRecentProjects(recent);
          setActiveWorkflowId(created.project.workflows[0]?.id ?? null);
          setSelectedNodeId(null);
          setSelectedNodeIds([]);
          setSelectedEdgeId(null);
          setStatus("Created an in-memory project. Open or save a `.maoproj` file to continue.");
        });
      } catch (bootstrapError) {
        if (cancelled) {
          return;
        }

        setError(bootstrapError instanceof Error ? bootstrapError.message : String(bootstrapError));
      }
    }

    void bootstrap();

    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!project) {
      return;
    }

    if (!activeWorkflowId || !project.workflows.some((workflow) => workflow.id === activeWorkflowId)) {
      setActiveWorkflowId(project.workflows[0]?.id ?? null);
    }
  }, [activeWorkflowId, project]);

  useEffect(() => {
    const safeActionIds = (openClawGovernanceReport?.proposedActions ?? [])
      .filter((action) => action.safeToAutoApply)
      .map((action) => action.id)
      .sort((left, right) => left.localeCompare(right));

    setOpenClawGovernanceSelectedActionIds((current) => {
      const retained = current
        .filter((actionId) => safeActionIds.includes(actionId))
        .sort((left, right) => left.localeCompare(right));
      const nextSelection = retained.length > 0 ? retained : safeActionIds;
      return arraysEqual(current, nextSelection) ? current : nextSelection;
    });
  }, [openClawGovernanceReport]);

  useEffect(() => {
    if (!activeWorkflow) {
      setSelectedNodeId(null);
      setSelectedNodeIds([]);
      setSelectedEdgeId(null);
      setSelectedTaskId(null);
      return;
    }

    const validSelectedNodeIds = selectedNodeIds.filter((nodeId) =>
      activeWorkflow.nodes.some((node) => node.id === nodeId)
    );
    if (validSelectedNodeIds.length !== selectedNodeIds.length) {
      setSelectedNodeIds(validSelectedNodeIds);
    }
    if (selectedNodeId && !validSelectedNodeIds.includes(selectedNodeId)) {
      setSelectedNodeId(validSelectedNodeIds[0] ?? null);
    } else if (!selectedNodeId && validSelectedNodeIds.length === 1) {
      setSelectedNodeId(validSelectedNodeIds[0]);
    } else if (validSelectedNodeIds.length === 0 && selectedNodeId) {
      setSelectedNodeId(null);
    }
    if (selectedEdgeId && !activeWorkflow.edges.some((edge) => edge.id === selectedEdgeId)) {
      setSelectedEdgeId(null);
    }
  }, [activeWorkflow, selectedEdgeId, selectedNodeId, selectedNodeIds]);

  useEffect(() => {
    if (!project) {
      setSelectedTaskId(null);
      return;
    }

    if (selectedTaskId && !project.tasks.some((task) => task.id === selectedTaskId)) {
      setSelectedTaskId(null);
    }
  }, [project, selectedTaskId]);

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (isEditableTarget(event.target)) {
        return;
      }

      if (event.key === "Escape") {
        event.preventDefault();
        handleCanvasBackgroundClick();
        return;
      }

      const isModifierPressed = event.metaKey || event.ctrlKey;
      if (isModifierPressed && event.key.toLowerCase() === "z") {
        event.preventDefault();
        if (event.shiftKey) {
          handleRedo();
        } else {
          handleUndo();
        }
        return;
      }

      if (event.ctrlKey && event.key.toLowerCase() === "y") {
        event.preventDefault();
        handleRedo();
        return;
      }

      if (event.key !== "Delete" && event.key !== "Backspace") {
        return;
      }

      if (selectedEdgeId) {
        event.preventDefault();
        handleRemoveEdge(selectedEdgeId);
        return;
      }

      if (selectedNodeIds.length > 0) {
        event.preventDefault();
        handleRemoveNodes(selectedNodeIds);
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [selectedEdgeId, selectedNodeId, selectedNodeIds, activeWorkflow, connectionFromNodeId, connectionToNodeId, canUndo, canRedo, projectHistory, projectState]);

  useEffect(() => {
    if (!project) {
      return;
    }

    const timer = window.setTimeout(() => {
      void requireDesktopApi()
        .autosaveProject(project)
        .then((result) => {
          startTransition(() => {
            setAutosaveInfo(result);
          });
        })
        .catch((autosaveError) => {
          setError(autosaveError instanceof Error ? autosaveError.message : String(autosaveError));
        });
    }, 2000);

    return () => {
      window.clearTimeout(timer);
    };
  }, [project]);

  async function runProjectAction(action: BusyAction, handler: () => Promise<void>) {
    setBusyAction(action);
    setError(null);

    try {
      await handler();
    } catch (actionError) {
      setError(actionError instanceof Error ? actionError.message : String(actionError));
    } finally {
      setBusyAction(null);
    }
  }

  function replaceProjectState(nextState: ProjectFileHandle, nextStatus?: string, resetHistory = false) {
    setProjectState(nextState);
    if (resetHistory) {
      setProjectHistory({ past: [], future: [] });
    }
    if (nextStatus) {
      setStatus(nextStatus);
    }
  }

  function commitProject(
    nextProject: MAProject,
    nextStatus?: string,
    options?: { recordHistory?: boolean }
  ) {
    const shouldRecordHistory = options?.recordHistory ?? true;

    setProjectState((current) => {
      if (!current || nextProject === current.project) {
        return current;
      }

      if (shouldRecordHistory) {
        setProjectHistory((history) => ({
          past: [...history.past.slice(-(MAX_HISTORY_ENTRIES - 1)), current.project],
          future: []
        }));
      }

      return {
        ...current,
        project: nextProject
      };
    });

    if (nextStatus) {
      setStatus(nextStatus);
    }
  }

  function updateProject(
    mutator: (current: MAProject) => MAProject,
    nextStatus?: string,
    options?: { recordHistory?: boolean }
  ) {
    const shouldRecordHistory = options?.recordHistory ?? true;

    setProjectState((current) => {
      if (!current) {
        return current;
      }

      const nextProject = mutator(current.project);
      if (nextProject === current.project) {
        return current;
      }

      if (shouldRecordHistory) {
        setProjectHistory((history) => ({
          past: [...history.past.slice(-(MAX_HISTORY_ENTRIES - 1)), current.project],
          future: []
        }));
      }

      return {
        ...current,
        project: nextProject
      };
    });

    if (nextStatus) {
      setStatus(nextStatus);
    }
  }

  async function runLiveWorkflowExecutions(
    currentProject: MAProject,
    workflow: Workflow,
    prompt: string,
    initialRoutes: Array<{ edge: WorkflowEdge | null; targetNodeId: string }>,
    seedVisitCounts?: Map<string, number>
  ): Promise<LiveWorkflowExecutionResult> {
    const preflight = await evaluateLiveExecutionPreflight(currentProject, workflow);
    applyOpenClawGovernancePreflightReport(preflight.governanceReport);
    if (preflight.blocked) {
      return {
        liveExecutions: [] as Parameters<typeof publishWorkbenchPromptWithLiveExecution>[3],
        approvalCheckpoints: [] as Parameters<typeof publishWorkbenchPromptWithLiveExecution>[4],
        errorMessage: preflight.message,
        blocked: true,
        advisoryMessage: preflight.advisoryMessage
      };
    }

    const liveExecutions: Parameters<typeof publishWorkbenchPromptWithLiveExecution>[3] = [];
    const approvalCheckpoints: Parameters<typeof publishWorkbenchPromptWithLiveExecution>[4] = [];
    const visitCounts = seedVisitCounts ? new Map(seedVisitCounts) : new Map<string, number>();
    const queue = [...initialRoutes];

    while (queue.length > 0) {
      const nextRoute = queue.shift();
      if (!nextRoute) {
        continue;
      }

      const targetNode = workflow.nodes.find((node) => node.id === nextRoute.targetNodeId) ?? null;
      const targetAgent =
        currentProject.agents.find((agent) => agent.id === targetNode?.agentID) ?? null;

      if (!targetNode || !targetAgent) {
        continue;
      }

      if (nextRoute.edge?.requiresApproval) {
        approvalCheckpoints.push({
          edgeId: nextRoute.edge.id,
          sourceNodeId: nextRoute.edge.fromNodeID,
          targetNodeId: nextRoute.targetNodeId
        });
        continue;
      }

      const allowedVisits = Math.max(1, targetNode.loopEnabled ? targetNode.maxIterations : 1);
      const nextVisitCount = (visitCounts.get(targetNode.id) ?? 0) + 1;
      if (nextVisitCount > allowedVisits) {
        continue;
      }
      visitCounts.set(targetNode.id, nextVisitCount);
      const guardrails = buildLiveExecutionGuardrails(
        currentProject,
        workflow,
        targetNode.id,
        targetAgent.id
      );

      const execution = await requireDesktopApi().executeOpenClawAgent(currentProject.openClaw.config, {
        agentIdentifier: resolveRuntimeAgentIdentifier(currentProject, targetAgent.id),
        message: augmentLiveExecutionPrompt(prompt, guardrails),
        sessionID: `workbench-${currentProject.runtimeState.sessionID}-${workflow.id}-${targetAgent.id}`,
        timeoutSeconds: currentProject.openClaw.config.timeout,
        writeScope: guardrails.writeScope,
        toolScope: guardrails.toolScope,
        requiresApproval: guardrails.requiresApproval,
        fallbackRoutingPolicy: guardrails.fallbackRoutingPolicy
      });

      liveExecutions.push({
        nodeId: targetNode.id,
        agentId: targetAgent.id,
        agentIdentifier: execution.agentIdentifier,
        success: execution.success,
        output: execution.output,
        outputType: execution.outputType,
        routingAction: execution.routingDecision?.action ?? "stop",
        routingTargets: execution.routingDecision?.targets ?? [],
        routingReason: execution.routingDecision?.reason ?? execution.message,
        engineMessage: execution.message,
        rawStdout: execution.rawStdout,
        rawStderr: execution.rawStderr
      });

      if (!execution.success) {
        continue;
      }

      const nextTargets = resolveLiveRoutingTargets(
        currentProject,
        workflow,
        targetNode.id,
        execution.routingDecision
      );
      for (const nextTarget of nextTargets) {
        queue.push({ edge: nextTarget.edge, targetNodeId: nextTarget.targetNodeId });
      }
    }

    return {
      liveExecutions,
      approvalCheckpoints,
      errorMessage: null,
      blocked: false,
      advisoryMessage: preflight.advisoryMessage
    };
  }

  async function runLiveWorkflowCase(
    currentProject: MAProject,
    workflow: Workflow,
    prompt: string
  ): Promise<LiveWorkflowExecutionResult> {
    const preflight = await evaluateLiveExecutionPreflight(currentProject, workflow);
    applyOpenClawGovernancePreflightReport(preflight.governanceReport);
    if (preflight.blocked) {
      return {
        liveExecutions: [] as Parameters<typeof publishWorkbenchPromptWithLiveExecution>[3],
        approvalCheckpoints: [] as Parameters<typeof publishWorkbenchPromptWithLiveExecution>[4],
        errorMessage: preflight.message,
        blocked: true,
        advisoryMessage: preflight.advisoryMessage
      };
    }

    const entryNodeIds = resolveEntryAgentNodeIds(currentProject, workflow.id);
    const leadEntryNode = workflow.nodes.find((node) => node.id === entryNodeIds[0]) ?? null;
    const leadAgent =
      currentProject.agents.find((agent) => agent.id === leadEntryNode?.agentID) ?? null;

    if (!leadEntryNode || !leadAgent) {
      return {
        liveExecutions: [] as Parameters<typeof publishWorkbenchPromptWithLiveExecution>[3],
        approvalCheckpoints: [] as Parameters<typeof publishWorkbenchPromptWithLiveExecution>[4],
        errorMessage: "No executable entry agent was resolved for this workflow.",
        blocked: false,
        advisoryMessage: preflight.advisoryMessage
      };
    }

    const leadGuardrails = buildLiveExecutionGuardrails(
      currentProject,
      workflow,
      leadEntryNode.id,
      leadAgent.id
    );
    const liveExecution = await requireDesktopApi().executeOpenClawAgent(currentProject.openClaw.config, {
      agentIdentifier: resolveRuntimeAgentIdentifier(currentProject, leadAgent.id),
      message: augmentLiveExecutionPrompt(prompt, leadGuardrails),
      sessionID: `workbench-${currentProject.runtimeState.sessionID}-${workflow.id}-${leadAgent.id}`,
      timeoutSeconds: currentProject.openClaw.config.timeout,
      writeScope: leadGuardrails.writeScope,
      toolScope: leadGuardrails.toolScope,
      requiresApproval: leadGuardrails.requiresApproval,
      fallbackRoutingPolicy: leadGuardrails.fallbackRoutingPolicy
    });

    const initialExecution: Parameters<typeof publishWorkbenchPromptWithLiveExecution>[3][number] = {
      nodeId: leadEntryNode.id,
      agentId: leadAgent.id,
      agentIdentifier: liveExecution.agentIdentifier,
      success: liveExecution.success,
      output: liveExecution.output,
      outputType: liveExecution.outputType,
      routingAction: liveExecution.routingDecision?.action ?? (liveExecution.success ? "stop" : "live_entry_failed"),
      routingTargets: liveExecution.routingDecision?.targets ?? [],
      routingReason: liveExecution.routingDecision?.reason ?? liveExecution.message,
      engineMessage: liveExecution.message,
      rawStdout: liveExecution.rawStdout,
      rawStderr: liveExecution.rawStderr
    };

    if (!liveExecution.success) {
      return {
        liveExecutions: [initialExecution],
        approvalCheckpoints: [] as Parameters<typeof publishWorkbenchPromptWithLiveExecution>[4],
        errorMessage: liveExecution.message,
        blocked: false,
        advisoryMessage: preflight.advisoryMessage
      };
    }

    const downstreamWork = await runLiveWorkflowExecutions(
      currentProject,
      workflow,
      prompt,
      resolveLiveRoutingTargets(currentProject, workflow, leadEntryNode.id, liveExecution.routingDecision).map(
        (target) => ({
          edge: target.edge,
          targetNodeId: target.targetNodeId
        })
      ),
      new Map([[leadEntryNode.id, 1]])
    );

    return {
      liveExecutions: [initialExecution, ...downstreamWork.liveExecutions],
      approvalCheckpoints: downstreamWork.approvalCheckpoints,
      errorMessage: downstreamWork.errorMessage,
      blocked: downstreamWork.blocked,
      advisoryMessage: [preflight.advisoryMessage, downstreamWork.advisoryMessage].filter(Boolean).join(" ") || null
    };
  }

  async function refreshRecentProjects() {
    const recent = await requireDesktopApi().listRecentProjects();
    startTransition(() => {
      setRecentProjects(recent);
    });
  }

  async function handleCreateProject() {
    await runProjectAction("new", async () => {
      const created = await requireDesktopApi().createProject("Untitled Project");
      startTransition(() => {
        replaceProjectState(created, "Created a new unsaved project.", true);
        setActiveWorkflowId(created.project.workflows[0]?.id ?? null);
        setSelectedNodeId(null);
        setSelectedNodeIds([]);
        setSelectedEdgeId(null);
        setSelectedTaskId(null);
      });
    });
  }

  async function handleOpenProject() {
    await runProjectAction("open", async () => {
      const opened = await requireDesktopApi().openProject();
      if (!opened) {
        setStatus("Open cancelled.");
        return;
      }

      startTransition(() => {
        replaceProjectState(opened, `Opened ${opened.project.name}.`, true);
        setActiveWorkflowId(opened.project.workflows[0]?.id ?? null);
        setSelectedNodeId(null);
        setSelectedNodeIds([]);
        setSelectedEdgeId(null);
        setSelectedTaskId(null);
      });

      await refreshRecentProjects();
    });
  }

  async function handleSaveProject() {
    if (!project) {
      return;
    }

    await runProjectAction("save", async () => {
      if (!filePath) {
        const saved = await requireDesktopApi().saveProjectAs(project, null);
        if (!saved) {
          setStatus("Save cancelled.");
          return;
        }

        startTransition(() => {
          replaceProjectState(saved, `Saved ${saved.project.name}.`);
        });
        await refreshRecentProjects();
        return;
      }

      const saved = await requireDesktopApi().saveProject(project, filePath);
      startTransition(() => {
        replaceProjectState(saved, `Saved ${saved.project.name}.`);
      });
      await refreshRecentProjects();
    });
  }

  async function handleSaveProjectAs() {
    if (!project) {
      return;
    }

    await runProjectAction("saveAs", async () => {
      const saved = await requireDesktopApi().saveProjectAs(project, filePath);
      if (!saved) {
        setStatus("Save As cancelled.");
        return;
      }

      startTransition(() => {
        replaceProjectState(saved, `Saved ${saved.project.name} to a new location.`);
      });
      await refreshRecentProjects();
    });
  }

  async function handleOpenRecentProject(nextFilePath: string) {
    await runProjectAction("open", async () => {
      const opened = await requireDesktopApi().openRecentProject(nextFilePath);
      startTransition(() => {
        replaceProjectState(opened, `Opened ${opened.project.name} from recent projects.`, true);
        setActiveWorkflowId(opened.project.workflows[0]?.id ?? null);
        setSelectedNodeId(null);
        setSelectedNodeIds([]);
        setSelectedEdgeId(null);
        setSelectedTaskId(null);
      });
      await refreshRecentProjects();
    });
  }

  function handleUndo() {
    if (!projectState || projectHistory.past.length === 0) {
      return;
    }

    const previousProject = projectHistory.past[projectHistory.past.length - 1];
    setProjectHistory((history) => ({
      past: history.past.slice(0, -1),
      future: [projectState.project, ...history.future].slice(0, MAX_HISTORY_ENTRIES)
    }));
    setProjectState((current) =>
      current
        ? {
            ...current,
            project: previousProject
          }
        : current
    );
    setStatus("Undid the last workflow change.");
  }

  function handleRedo() {
    if (!projectState || projectHistory.future.length === 0) {
      return;
    }

    const [nextProject, ...remainingFuture] = projectHistory.future;
    setProjectHistory((history) => ({
      past: [...history.past, projectState.project].slice(-MAX_HISTORY_ENTRIES),
      future: remainingFuture
    }));
    setProjectState((current) =>
      current
        ? {
            ...current,
            project: nextProject
          }
        : current
    );
    setStatus("Redid the last workflow change.");
  }

  function handleProjectNameChange(nextName: string) {
    updateProject((current) => renameProject(current, nextName));
  }

  function handleAddAgent() {
    updateProject((current) => addAgentToProject(current, newAgentName), "Added a new agent to the project.");
  }

  function handleAddWorkflow() {
    if (!project) {
      return;
    }

    const nextProject = addWorkflowToProject(project, newWorkflowName);
    const latestWorkflow = nextProject.workflows[nextProject.workflows.length - 1] ?? null;
    startTransition(() => {
      setProjectState((current) => (current ? { ...current, project: nextProject } : current));
      setActiveWorkflowId(latestWorkflow?.id ?? null);
      setSelectedNodeId(latestWorkflow?.nodes[0]?.id ?? null);
      setSelectedNodeIds(latestWorkflow?.nodes[0]?.id ? [latestWorkflow.nodes[0].id] : []);
      setSelectedEdgeId(null);
      setStatus("Added a new workflow.");
    });
  }

  function handleAddNode() {
    if (!activeWorkflow) {
      return;
    }

    const nextProject = addNodeToWorkflow(project!, activeWorkflow.id, newNodeType);
    const updatedWorkflow = nextProject.workflows.find((workflow) => workflow.id === activeWorkflow.id) ?? null;
    const latestNode = updatedWorkflow?.nodes[updatedWorkflow.nodes.length - 1] ?? null;
    startTransition(() => {
      setProjectState((current) => (current ? { ...current, project: nextProject } : current));
      setSelectedNodeId(latestNode?.id ?? null);
      setSelectedNodeIds(latestNode?.id ? [latestNode.id] : []);
      setSelectedEdgeId(null);
      setStatus(`Added a ${newNodeType} node to ${activeWorkflow.name}.`);
    });
  }

  function handleWorkflowNameChange(nextName: string) {
    if (!activeWorkflow) {
      return;
    }

    updateProject(
      (current) => renameWorkflow(current, activeWorkflow.id, nextName),
      "Updated workflow name."
    );
  }

  function handleWorkflowPolicyChange(nextPolicy: WorkflowFallbackRoutingPolicy) {
    if (!activeWorkflow) {
      return;
    }

    updateProject(
      (current) => setWorkflowFallbackRoutingPolicy(current, activeWorkflow.id, nextPolicy),
      "Updated fallback routing policy."
    );
  }

  function handleUpdateAgent(
    agentId: string,
    patch: {
      name?: string;
      identity?: string;
      description?: string;
      soulMD?: string;
      capabilities?: string[];
      openClawDefinition?: Partial<MAProject["agents"][number]["openClawDefinition"]>;
    }
  ) {
    updateProject((current) => updateAgentInProject(current, agentId, patch), undefined);
  }

  function handleAddLaunchTestCase() {
    if (!project || !activeWorkflow) {
      return;
    }

    updateProject((current) => {
      const workflow = current.workflows.find((item) => item.id === activeWorkflow.id) ?? null;
      if (!workflow) {
        return current;
      }

      return addWorkflowLaunchTestCase(current, workflow.id, buildSuggestedLaunchTestCaseDraft(current, workflow));
    }, "Added a saved launch verification case.");
  }

  function handleUpdateLaunchTestCase(
    testCaseId: string,
    patch: {
      name?: string;
      prompt?: string;
      requiredAgentNames?: string[];
      forbiddenAgentNames?: string[];
      expectedRoutingActions?: string[];
      expectedOutputTypes?: string[];
      maxSteps?: number | null;
      notes?: string;
    }
  ) {
    if (!activeWorkflow) {
      return;
    }

    updateProject((current) => updateWorkflowLaunchTestCase(current, activeWorkflow.id, testCaseId, patch), undefined);
  }

  function handleRemoveLaunchTestCase(testCaseId: string) {
    if (!activeWorkflow) {
      return;
    }

    updateProject(
      (current) => removeWorkflowLaunchTestCase(current, activeWorkflow.id, testCaseId),
      "Removed the saved launch verification case."
    );
  }

  async function handleRunLaunchVerification() {
    if (!project || !activeWorkflow) {
      return;
    }

    setVerificationAction("run");
    setWorkbenchError(null);
    try {
      const seeded = runWorkflowLaunchVerification(project, activeWorkflow.id);
      if (!seeded.report) {
        setWorkbenchError("The workflow could not be prepared for launch verification.");
        return;
      }

      commitProject(seeded.project, "Started launch verification.", { recordHistory: false });

      if (seeded.report.status === "fail") {
        setStatus("Launch verification stopped on static blockers.");
        return;
      }

      const verificationProject = seeded.project;
      const verificationWorkflow =
        verificationProject.workflows.find((workflow) => workflow.id === activeWorkflow.id) ?? null;
      if (!verificationWorkflow) {
        setWorkbenchError("The workflow disappeared before verification could continue.");
        return;
      }

      const runtimeReadiness = assessOpenClawRuntimeReadiness(verificationProject.openClaw);
      const runtimeFindings: string[] = [];
      if (runtimeReadiness.blockingMessage) {
        runtimeFindings.push(`Live runtime blocked: ${runtimeReadiness.blockingMessage}`);
      }
      if (runtimeReadiness.advisoryMessages.length > 0) {
        runtimeFindings.push(...runtimeReadiness.advisoryMessages.map((message) => `Runtime advisory: ${message}`));
      }

      let governancePreflightFinding: string | null = null;
      try {
        const governanceReport = await requireDesktopApi().auditOpenClawRuntimeGovernance(
          verificationProject.openClaw.config
        );
        applyOpenClawGovernancePreflightReport(governanceReport);
        governancePreflightFinding = summarizeOpenClawGovernancePreflight(governanceReport);
      } catch (actionError) {
        governancePreflightFinding = `Unable to refresh OpenClaw governance during launch verification: ${
          actionError instanceof Error ? actionError.message : String(actionError)
        }`;
      }

      const testCases = resolveWorkflowLaunchTestCases(verificationProject, verificationWorkflow.id);
      if (testCases.length === 0) {
        const finalized = finalizeWorkflowLaunchVerification(
          verificationProject,
          verificationWorkflow.id,
          [...runtimeFindings, ...(governancePreflightFinding ? [governancePreflightFinding] : [])],
          []
        );
        commitProject(finalized.project, "Launch verification completed with static checks only.", {
          recordHistory: false
        });
        return;
      }

      const caseReports: ReturnType<typeof evaluateWorkflowLaunchTestCase>[] = [];
      if (governancePreflightFinding) {
        runtimeFindings.push(governancePreflightFinding);
      }

      if (runtimeReadiness.blockingMessage) {
        const finalized = finalizeWorkflowLaunchVerification(
          verificationProject,
          verificationWorkflow.id,
          runtimeFindings,
          []
        );
        commitProject(finalized.project, "Launch verification stopped because live runtime is blocked.", {
          recordHistory: false
        });
        return;
      }

      for (const testCase of testCases) {
        const liveCase = await runLiveWorkflowCase(verificationProject, verificationWorkflow, testCase.prompt);
        const approvalCheckpoints = liveCase.approvalCheckpoints ?? [];
        const observations: WorkflowLaunchExecutionObservation[] = liveCase.liveExecutions.map((execution) => ({
          agentID: execution.agentId,
          status: execution.success ? "Completed" : "Failed",
          outputType: execution.outputType,
          routingAction: execution.routingAction ?? null,
          routingTargets: execution.routingTargets ?? []
        }));

        const caseRuntimeFindings: string[] = [];
        if (liveCase.errorMessage) {
          caseRuntimeFindings.push(`${testCase.name}: ${liveCase.errorMessage}`);
        }
        if (liveCase.advisoryMessage) {
          caseRuntimeFindings.push(`${testCase.name}: advisory - ${liveCase.advisoryMessage}`);
        }
        if (approvalCheckpoints.length > 0) {
          caseRuntimeFindings.push(
            `${testCase.name}: encountered ${approvalCheckpoints.length} approval checkpoint(s) during verification.`
          );
        }
        if (liveCase.liveExecutions.some((execution) => !execution.success)) {
          caseRuntimeFindings.push(`${testCase.name}: one or more nodes failed during runtime verification.`);
        }

        runtimeFindings.push(...caseRuntimeFindings);
        caseReports.push(
          evaluateWorkflowLaunchTestCase(
            verificationProject,
            verificationWorkflow.id,
            testCase,
            observations,
            caseRuntimeFindings
          )
        );
      }

      const finalized = finalizeWorkflowLaunchVerification(
        verificationProject,
        verificationWorkflow.id,
        runtimeFindings,
        caseReports
      );
      commitProject(finalized.project, "Launch verification report refreshed.", { recordHistory: false });
    } finally {
      setVerificationAction(null);
    }
  }

  function handleRemoveActiveWorkflow() {
    if (!project || !activeWorkflow) {
      return;
    }

    const remainingWorkflows = project.workflows.filter((workflow) => workflow.id !== activeWorkflow.id);
    updateProject(
      (current) => removeWorkflowFromProject(current, activeWorkflow.id),
      "Removed workflow from the project."
    );
    setActiveWorkflowId(remainingWorkflows[0]?.id ?? null);
    setSelectedNodeId(null);
    setSelectedNodeIds([]);
    setSelectedEdgeId(null);
  }

  function handleConnectNodes() {
    if (!activeWorkflow || !connectionFromNodeId || !connectionToNodeId) {
      return;
    }

    updateProject(
      (current) => connectWorkflowNodes(current, activeWorkflow.id, connectionFromNodeId, connectionToNodeId),
      "Connected workflow nodes."
    );

    setConnectionFromNodeId("");
    setConnectionToNodeId("");
  }

  function clearCanvasConnectionSelection(nextStatus?: string) {
    setConnectionFromNodeId("");
    setConnectionToNodeId("");
    if (nextStatus) {
      setStatus(nextStatus);
    }
  }

  function handleCanvasNodeClick(nodeId: string) {
    if (!activeWorkflow) {
      return;
    }

    if (!connectionFromNodeId) {
      setConnectionFromNodeId(nodeId);
      setConnectionToNodeId("");
      setStatus("Selected the source node. Click another node on the canvas to create an edge.");
      return;
    }

    if (connectionFromNodeId === nodeId) {
      clearCanvasConnectionSelection("Cleared canvas edge selection.");
      return;
    }

    setConnectionToNodeId(nodeId);
    updateProject(
      (current) => connectWorkflowNodes(current, activeWorkflow.id, connectionFromNodeId, nodeId),
      "Connected workflow nodes from the canvas."
    );
    setConnectionFromNodeId("");
    setConnectionToNodeId("");
  }

  function handleCanvasNodeConnect(fromNodeId: string, toNodeId: string) {
    if (!activeWorkflow || fromNodeId === toNodeId) {
      return;
    }

    updateProject(
      (current) => connectWorkflowNodes(current, activeWorkflow.id, fromNodeId, toNodeId),
      "Connected workflow nodes by dragging on the canvas."
    );
    setConnectionFromNodeId("");
    setConnectionToNodeId("");
    setSelectedEdgeId(null);
    setSelectedNodeId(toNodeId);
    setSelectedNodeIds([toNodeId]);
  }

  function handleCanvasBackgroundClick() {
    const hadConnectionSelection = Boolean(connectionFromNodeId || connectionToNodeId);
    const hadObjectSelection = Boolean(selectedNodeIds.length > 0 || selectedEdgeId);

    if (!hadConnectionSelection && !hadObjectSelection) {
      return;
    }

    setSelectedNodeId(null);
    setSelectedNodeIds([]);
    setSelectedEdgeId(null);
    clearCanvasConnectionSelection(
      hadConnectionSelection ? "Cleared canvas edge selection." : "Cleared canvas selection."
    );
  }

  function handleAssignAgent(nodeId: string, agentId: string | null) {
    if (!activeWorkflow) {
      return;
    }

    updateProject(
      (current) => assignAgentToNode(current, activeWorkflow.id, nodeId, agentId),
      "Updated workflow node assignment."
    );
  }

  function handleAssignAgents(nodeIds: string[], agentId: string | null) {
    if (!activeWorkflow || nodeIds.length === 0) {
      return;
    }

    updateProject(
      (current) => assignAgentToNodes(current, activeWorkflow.id, nodeIds, agentId),
      agentId ? "Updated selected node assignments." : "Cleared selected node assignments."
    );
  }

  function handleRenameNode(nodeId: string, title: string) {
    if (!activeWorkflow) {
      return;
    }

    updateProject(
      (current) => renameWorkflowNode(current, activeWorkflow.id, nodeId, title),
      "Updated node title."
    );
  }

  function handleRemoveNode(nodeId: string) {
    handleRemoveNodes([nodeId]);
  }

  function handleRemoveNodes(nodeIds: string[]) {
    if (!activeWorkflow) {
      return;
    }

    const nodeIdSet = new Set(nodeIds);
    updateProject(
      (current) => removeNodesFromWorkflow(current, activeWorkflow.id, nodeIds),
      nodeIdSet.size > 1 ? "Removed selected workflow nodes and related edges." : "Removed workflow node and related edges."
    );

    if (connectionFromNodeId && nodeIdSet.has(connectionFromNodeId)) {
      setConnectionFromNodeId("");
    }

    if (connectionToNodeId && nodeIdSet.has(connectionToNodeId)) {
      setConnectionToNodeId("");
    }

    const remainingSelectedNodeIds = selectedNodeIds.filter((id) => !nodeIdSet.has(id));
    setSelectedNodeIds(remainingSelectedNodeIds);
    setSelectedNodeId(remainingSelectedNodeIds[0] ?? null);

    if (
      selectedEdgeId &&
      activeWorkflow.edges.some(
        (edge) => edge.id === selectedEdgeId && (nodeIdSet.has(edge.fromNodeID) || nodeIdSet.has(edge.toNodeID))
      )
    ) {
      setSelectedEdgeId(null);
    }
  }

  function handleRemoveEdge(edgeId: string) {
    if (!activeWorkflow) {
      return;
    }

    updateProject(
      (current) => removeEdgeFromWorkflow(current, activeWorkflow.id, edgeId),
      "Removed workflow edge."
    );
    if (selectedEdgeId === edgeId) {
      setSelectedEdgeId(null);
    }
  }

  function handleNodePositionChange(nodeId: string, x: number, y: number) {
    if (!activeWorkflow) {
      return;
    }

    updateProject(
      (current) => repositionWorkflowNode(current, activeWorkflow.id, nodeId, x, y),
      undefined,
      { recordHistory: false }
    );
  }

  function handleNodePositionCommit(nodeId: string, x: number, y: number) {
    if (!activeWorkflow) {
      return;
    }

    updateProject(
      (current) => repositionWorkflowNode(current, activeWorkflow.id, nodeId, x, y),
      "Updated node position."
    );
  }

  function handleNodesPositionChange(updates: Array<{ nodeId: string; x: number; y: number }>) {
    if (!activeWorkflow) {
      return;
    }

    updateProject(
      (current) => repositionWorkflowNodes(current, activeWorkflow.id, updates),
      undefined,
      { recordHistory: false }
    );
  }

  function handleNodesPositionCommit(updates: Array<{ nodeId: string; x: number; y: number }>) {
    if (!activeWorkflow) {
      return;
    }

    updateProject(
      (current) => repositionWorkflowNodes(current, activeWorkflow.id, updates),
      updates.length > 1 ? "Updated selected node positions." : "Updated node position."
    );
  }

  function handleCanvasNodeSelect(nodeId: string) {
    setSelectedNodeIds([nodeId]);
    setSelectedNodeId(nodeId);
    setSelectedEdgeId(null);
  }

  function handleCanvasNodeSelectionChange(nodeId: string, mode: "replace" | "toggle" = "replace") {
    if (mode === "toggle") {
      const exists = selectedNodeIds.includes(nodeId);
      const nextSelectedNodeIds = exists
        ? selectedNodeIds.filter((id) => id !== nodeId)
        : [...selectedNodeIds, nodeId];
      setSelectedNodeIds(nextSelectedNodeIds);
      setSelectedNodeId(nextSelectedNodeIds[nextSelectedNodeIds.length - 1] ?? null);
      setSelectedEdgeId(null);
      return;
    }

    handleCanvasNodeSelect(nodeId);
  }

  function handleAlignSelectedNodes(
    alignment: "left" | "center" | "right" | "top" | "middle" | "bottom"
  ) {
    if (!activeWorkflow || selectedNodes.length < 2) {
      return;
    }

    const left = Math.min(...selectedNodes.map((node) => node.position.x));
    const right = Math.max(...selectedNodes.map((node) => node.position.x + CANVAS_NODE_WIDTH));
    const top = Math.min(...selectedNodes.map((node) => node.position.y));
    const bottom = Math.max(...selectedNodes.map((node) => node.position.y + CANVAS_NODE_HEIGHT));
    const center = (left + right) / 2;
    const middle = (top + bottom) / 2;

    const updates = selectedNodes.map((node) => {
      switch (alignment) {
        case "left":
          return { nodeId: node.id, x: left, y: node.position.y };
        case "center":
          return {
            nodeId: node.id,
            x: center - CANVAS_NODE_WIDTH / 2,
            y: node.position.y
          };
        case "right":
          return {
            nodeId: node.id,
            x: right - CANVAS_NODE_WIDTH,
            y: node.position.y
          };
        case "top":
          return { nodeId: node.id, x: node.position.x, y: top };
        case "middle":
          return {
            nodeId: node.id,
            x: node.position.x,
            y: middle - CANVAS_NODE_HEIGHT / 2
          };
        case "bottom":
          return {
            nodeId: node.id,
            x: node.position.x,
            y: bottom - CANVAS_NODE_HEIGHT
          };
      }
    });

    updateProject(
      (current) => repositionWorkflowNodes(current, activeWorkflow.id, updates),
      `Aligned ${selectedNodes.length} selected nodes.`
    );
  }

  function handleDistributeSelectedNodes(axis: "horizontal" | "vertical") {
    if (!activeWorkflow || selectedNodes.length < 3) {
      return;
    }

    const orderedNodes = [...selectedNodes].sort((left, right) =>
      axis === "horizontal"
        ? left.position.x - right.position.x
        : left.position.y - right.position.y
    );
    const firstNode = orderedNodes[0];
    const lastNode = orderedNodes[orderedNodes.length - 1];
    const start = axis === "horizontal" ? firstNode.position.x : firstNode.position.y;
    const end = axis === "horizontal" ? lastNode.position.x : lastNode.position.y;
    const gap = (end - start) / (orderedNodes.length - 1);

    const updates = orderedNodes.map((node, index) => {
      const nextOffset = start + gap * index;
      return axis === "horizontal"
        ? { nodeId: node.id, x: nextOffset, y: node.position.y }
        : { nodeId: node.id, x: node.position.x, y: nextOffset };
    });

    updateProject(
      (current) => repositionWorkflowNodes(current, activeWorkflow.id, updates),
      `Distributed ${selectedNodes.length} selected nodes ${axis === "horizontal" ? "horizontally" : "vertically"}.`
    );
  }

  function handleTidySelectedNodes() {
    if (!activeWorkflow || selectedNodes.length < 2) {
      return;
    }

    const orderedNodes = [...selectedNodes].sort((left, right) =>
      left.position.y === right.position.y
        ? left.position.x - right.position.x
        : left.position.y - right.position.y
    );
    const columns = Math.max(2, Math.ceil(Math.sqrt(orderedNodes.length)));
    const originX = Math.min(...orderedNodes.map((node) => node.position.x));
    const originY = Math.min(...orderedNodes.map((node) => node.position.y));
    const horizontalGap = CANVAS_NODE_WIDTH + 56;
    const verticalGap = CANVAS_NODE_HEIGHT + 44;

    const updates = orderedNodes.map((node, index) => ({
      nodeId: node.id,
      x: originX + (index % columns) * horizontalGap,
      y: originY + Math.floor(index / columns) * verticalGap
    }));

    updateProject(
      (current) => repositionWorkflowNodes(current, activeWorkflow.id, updates),
      `Tidied ${selectedNodes.length} selected nodes into a grid.`
    );
  }

  function handleCanvasSelectionBox(nodeIds: string[], mode: "replace" | "add" = "replace") {
    if (mode === "add") {
      const nextSelectedNodeIds = Array.from(new Set([...selectedNodeIds, ...nodeIds]));
      setSelectedNodeIds(nextSelectedNodeIds);
      setSelectedNodeId(nextSelectedNodeIds[nextSelectedNodeIds.length - 1] ?? null);
      setSelectedEdgeId(null);
      setStatus(
        nextSelectedNodeIds.length > 0
          ? `Selected ${nextSelectedNodeIds.length} nodes from the canvas.`
          : "No nodes matched the box selection."
      );
      return;
    }

    setSelectedNodeIds(nodeIds);
    setSelectedNodeId(nodeIds[nodeIds.length - 1] ?? null);
    setSelectedEdgeId(null);
    setStatus(
      nodeIds.length > 0
        ? `Selected ${nodeIds.length} nodes from the canvas.`
        : "Cleared canvas selection."
    );
  }

  function handleCanvasEdgeSelect(edgeId: string) {
    setConnectionFromNodeId("");
    setConnectionToNodeId("");
    setSelectedEdgeId(edgeId);
    setSelectedNodeId(null);
    setStatus("Selected an edge on the canvas.");
  }

  function handleAddTask() {
    if (!project) {
      return;
    }

    const nextProject = addTaskToProject(project, {
      title: newTaskTitle,
      description: newTaskDescription,
      priority: newTaskPriority,
      assignedAgentID: newTaskAgentId || null,
      tags: parseTagInput(newTaskTags)
    });
    const createdTask = nextProject.tasks[nextProject.tasks.length - 1] ?? null;

    commitProject(nextProject, "Added a new task.");
    setSelectedTaskId(createdTask?.id ?? null);
    setNewTaskTitle("");
    setNewTaskDescription("");
    setNewTaskPriority("Medium");
    setNewTaskAgentId("");
    setNewTaskTags("");
  }

  function handleGenerateTasks() {
    if (!project || !activeWorkflow) {
      return;
    }

    const nextProject = generateTasksFromWorkflow(project, activeWorkflow.id);
    commitProject(nextProject, `Generated tasks from ${activeWorkflow.name}.`);
  }

  function handleTaskUpdate(
    taskId: string,
    patch: Parameters<typeof updateTaskInProject>[2],
    nextStatus = "Updated task."
  ) {
    updateProject((current) => updateTaskInProject(current, taskId, patch), nextStatus);
  }

  function handleTaskStatusChange(taskId: string, status: TaskStatus) {
    updateProject(
      (current) => moveTaskToStatus(current, taskId, status),
      `Moved task to ${status}.`
    );
  }

  function handleTaskAssignmentChange(taskId: string, agentId: string | null) {
    updateProject(
      (current) => assignTaskToAgent(current, taskId, agentId),
      agentId ? "Updated task assignment." : "Cleared task assignment."
    );
  }

  function handleRemoveTask(taskId: string) {
    updateProject((current) => removeTaskFromProject(current, taskId), "Deleted task.");
    if (selectedTaskId === taskId) {
      setSelectedTaskId(null);
    }
  }

  async function handleChooseDirectory(
    currentPath: string | null | undefined,
    onSelected: (directoryPath: string) => void
  ) {
    const result = await requireDesktopApi().chooseDirectory(currentPath ?? null);
    if (!result.directoryPath) {
      setStatus("Folder selection cancelled.");
      return;
    }

    onSelected(result.directoryPath);
  }

  async function handleChooseTaskWorkspaceRoot() {
    if (!project) {
      return;
    }

    await handleChooseDirectory(project.taskData.workspaceRootPath, (directoryPath) => {
      updateProject(
        (current) => updateProjectTaskDataSettings(current, { workspaceRootPath: directoryPath }),
        "Updated task workspace root."
      );
    });
  }

  async function handleChooseOpenClawSessionPath(target: "backup" | "mirror") {
    if (!project) {
      return;
    }

    const currentPath =
      target === "backup" ? project.openClaw.sessionBackupPath : project.openClaw.sessionMirrorPath;

    await handleChooseDirectory(currentPath, (directoryPath) => {
      updateProject(
        (current) =>
          updateOpenClawSessionPaths(
            current,
            target === "backup"
              ? { sessionBackupPath: directoryPath }
              : { sessionMirrorPath: directoryPath }
          ),
        target === "backup" ? "Updated OpenClaw backup path." : "Updated OpenClaw mirror path."
      );
    });
  }

  function handleTaskDataSettingChange(patch: Parameters<typeof updateProjectTaskDataSettings>[1], nextStatus: string) {
    updateProject((current) => updateProjectTaskDataSettings(current, patch), nextStatus);
  }

  function handleOpenClawConfigChange(patch: Parameters<typeof updateOpenClawConfig>[1], nextStatus: string) {
    setOpenClawGovernanceReport(null);
    setOpenClawGovernanceNotes([]);
    setOpenClawGovernanceBackupPaths([]);
    setOpenClawGovernanceSelectedActionIds([]);
    setOpenClawGovernanceLastRemediation(null);
    updateProject((current) => updateOpenClawConfig(current, patch), nextStatus);
  }

  function handleOpenClawPathChange(
    patch: Parameters<typeof updateOpenClawSessionPaths>[1],
    nextStatus: string
  ) {
    setOpenClawGovernanceReport(null);
    setOpenClawGovernanceNotes([]);
    setOpenClawGovernanceBackupPaths([]);
    setOpenClawGovernanceSelectedActionIds([]);
    setOpenClawGovernanceLastRemediation(null);
    updateProject((current) => updateOpenClawSessionPaths(current, patch), nextStatus);
  }

  function handleToggleOpenClawGovernanceAction(actionId: string, checked: boolean) {
    setOpenClawGovernanceSelectedActionIds((current) => {
      const next = checked ? [...current, actionId] : current.filter((value) => value !== actionId);
      return Array.from(new Set(next)).sort((left, right) => left.localeCompare(right));
    });
  }

  function handleSelectAllOpenClawGovernanceActions() {
    if (!openClawGovernanceReport) {
      return;
    }

    setOpenClawGovernanceSelectedActionIds(
      openClawGovernanceReport.proposedActions
        .filter((action) => action.safeToAutoApply)
        .map((action) => action.id)
        .sort((left, right) => left.localeCompare(right))
    );
  }

  function handleClearOpenClawGovernanceActions() {
    setOpenClawGovernanceSelectedActionIds([]);
  }

  function applyOpenClawGovernancePreflightReport(report: OpenClawGovernanceAuditReport | null) {
    if (!report) {
      return;
    }

    setOpenClawGovernanceReport(report);
    setOpenClawGovernanceNotes([]);
    setOpenClawGovernanceBackupPaths([]);
  }

  async function handleAuditOpenClawRuntimeGovernance() {
    if (!project) {
      return;
    }

    setOpenClawGovernanceAction("audit");
    setOpenClawGovernanceNotes([]);
    setOpenClawGovernanceBackupPaths([]);
    try {
      const report = await requireDesktopApi().auditOpenClawRuntimeGovernance(project.openClaw.config);
      applyOpenClawGovernancePreflightReport(report);
      setStatus(
        report.summary.fail > 0
          ? `OpenClaw runtime audit found ${report.summary.fail} failing finding(s) and ${report.summary.unknown} unknown finding(s).`
          : "OpenClaw runtime audit completed without failing findings."
      );
    } catch (actionError) {
      setError(actionError instanceof Error ? actionError.message : String(actionError));
    } finally {
      setOpenClawGovernanceAction(null);
    }
  }

  async function handleRemediateOpenClawRuntimeGovernance() {
    if (!project) {
      return;
    }

    const previousReport = openClawGovernanceReport;
    setOpenClawGovernanceAction("remediate");
    try {
      const result = await requireDesktopApi().remediateOpenClawRuntimeGovernance(
        project.openClaw.config,
        openClawGovernanceSelectedActionIds
      );
      setOpenClawGovernanceReport(result.report);
      setOpenClawGovernanceNotes(result.notes);
      setOpenClawGovernanceBackupPaths(result.backupPaths);
      setOpenClawGovernanceLastRemediation(
        summarizeOpenClawGovernanceRemediation(
          previousReport,
          result.report,
          result.appliedActionIds,
          result.skippedActionIds
        )
      );
      setStatus(
        result.appliedActionIds.length > 0
          ? `Applied ${result.appliedActionIds.length} OpenClaw remediation action(s). ${result.report.summary.fail} failing finding(s) remain.`
          : `No OpenClaw remediations were applied. ${result.report.summary.fail} failing finding(s) remain.`
      );
    } catch (actionError) {
      setError(actionError instanceof Error ? actionError.message : String(actionError));
    } finally {
      setOpenClawGovernanceAction(null);
    }
  }

  async function handleDetectOpenClawAgents() {
    if (!project) {
      return;
    }

    setOpenClawAction("detect");
    try {
      const result = await requireDesktopApi().detectOpenClawAgents(project.openClaw.config);
      const nextProject = syncOpenClawState(project, {
        isConnected: false,
        availableAgents: result.availableAgents,
        activeAgents: result.activeAgents,
        detectedAgents: result.detectedAgents,
        connectionState: result.connectionState,
        lastProbeReport: result.probeReport
      });
      commitProject(nextProject, result.message);
    } catch (actionError) {
      setError(actionError instanceof Error ? actionError.message : String(actionError));
    } finally {
      setOpenClawAction(null);
    }
  }

  async function runDetectOpenClawAgents(projectSnapshot: MAProject) {
    const result = await requireDesktopApi().detectOpenClawAgents(projectSnapshot.openClaw.config);
    const nextProject = syncOpenClawState(projectSnapshot, {
      isConnected: false,
      availableAgents: result.availableAgents,
      activeAgents: result.activeAgents,
      detectedAgents: result.detectedAgents,
      connectionState: result.connectionState,
      lastProbeReport: result.probeReport
    });

    return { result, nextProject };
  }

  async function handleConnectOpenClaw() {
    if (!project) {
      return;
    }

    setOpenClawAction("connect");
    try {
      const { result, nextProject } = await runConnectOpenClaw(project);
      commitProject(nextProject, result.message);
    } catch (actionError) {
      setError(actionError instanceof Error ? actionError.message : String(actionError));
    } finally {
      setOpenClawAction(null);
    }
  }

  async function runConnectOpenClaw(projectSnapshot: MAProject) {
    const result = await requireDesktopApi().connectOpenClaw(projectSnapshot.openClaw.config);
    const nextProject = syncOpenClawState(projectSnapshot, {
      isConnected: result.isConnected,
      availableAgents: result.availableAgents,
      activeAgents: result.activeAgents,
      detectedAgents: result.detectedAgents,
      connectionState: result.connectionState,
      lastProbeReport: result.probeReport
    });

    return { result, nextProject };
  }

  async function handleDisconnectOpenClaw() {
    if (!project) {
      return;
    }

    setOpenClawAction("disconnect");
    try {
      const result = await requireDesktopApi().disconnectOpenClaw(project.openClaw.config);
      updateProject(
        (current) =>
          syncOpenClawState(current, {
            isConnected: result.isConnected,
            availableAgents: result.availableAgents,
            activeAgents: result.activeAgents,
            connectionState: result.connectionState,
            lastProbeReport: result.probeReport
          }),
        result.message
      );
    } catch (actionError) {
      setError(actionError instanceof Error ? actionError.message : String(actionError));
    } finally {
      setOpenClawAction(null);
    }
  }

  function handleRunOpenClawRecoveryAction(command: "connect" | "detect" | "review_config") {
    switch (command) {
      case "connect":
        void handleConnectOpenClaw();
        break;
      case "detect":
        void handleDetectOpenClawAgents();
        break;
      case "review_config":
        setStatus("Review the OpenClaw configuration fields highlighted in the diagnostics panel before retrying.");
        break;
    }
  }

  async function handleRunOpenClawRecoveryPlan() {
    if (!project) {
      return;
    }

    const readiness = assessOpenClawRuntimeReadiness(project.openClaw);
    if (readiness.recoveryActions.length === 0) {
      setStatus("OpenClaw recovery plan is already clear. No recovery action is needed right now.");
      return;
    }

    setOpenClawAction("recover");
    setError(null);

    const startingProject = project;
    let workingProject = project;
    const completedSteps: string[] = [];
    const manualSteps: string[] = [];
    const persistRecoveryReport = (report: ReturnType<typeof buildOpenClawRecoveryReport>) => {
      const nextProject = appendOpenClawRecoveryReport(workingProject, report);
      workingProject = nextProject;
      commitProject(nextProject, undefined, { recordHistory: false });
    };

    try {
      for (const action of readiness.recoveryActions) {
        if (action.command === "review_config") {
          manualSteps.push(action.detail);
          persistRecoveryReport(
            buildOpenClawRecoveryReport({
              before: startingProject.openClaw,
              after: workingProject.openClaw,
              createdAt: toSwiftDate(),
              completedSteps,
              manualSteps
            })
          );
          setStatus(
            completedSteps.length > 0
              ? `Recovery progressed through ${completedSteps.join(" -> ")}. Manual follow-up: ${action.detail}`
              : `Recovery paused for manual follow-up: ${action.detail}`
          );
          return;
        }

        if (action.command === "connect") {
          const { result, nextProject } = await runConnectOpenClaw(workingProject);
          workingProject = nextProject;
          commitProject(nextProject, `Recovery step complete: ${action.title}. ${result.message}`, {
            recordHistory: false
          });
          completedSteps.push(action.title);

          const nextReadiness = assessOpenClawRuntimeReadiness(nextProject.openClaw);
          if (nextReadiness.blockingMessage) {
            persistRecoveryReport(
              buildOpenClawRecoveryReport({
                before: startingProject.openClaw,
                after: nextProject.openClaw,
                createdAt: toSwiftDate(),
                completedSteps
              })
            );
            setStatus(`Recovery stopped after ${action.title}: ${nextReadiness.blockingMessage}`);
            return;
          }
          continue;
        }

        if (action.command === "detect") {
          const { result, nextProject } = await runDetectOpenClawAgents(workingProject);
          workingProject = nextProject;
          commitProject(nextProject, `Recovery step complete: ${action.title}. ${result.message}`, {
            recordHistory: false
          });
          completedSteps.push(action.title);
        }
      }

      persistRecoveryReport(
        buildOpenClawRecoveryReport({
          before: startingProject.openClaw,
          after: workingProject.openClaw,
          createdAt: toSwiftDate(),
          completedSteps
        })
      );
      setStatus(
        completedSteps.length > 0
          ? `OpenClaw recovery plan completed: ${completedSteps.join(" -> ")}.`
          : "OpenClaw recovery plan did not require an automatic step."
      );
    } catch (actionError) {
      persistRecoveryReport(
        buildOpenClawRecoveryReport({
          before: startingProject.openClaw,
          after: workingProject.openClaw,
          createdAt: toSwiftDate(),
          completedSteps,
          errorMessage: actionError instanceof Error ? actionError.message : String(actionError)
        })
      );
      setError(actionError instanceof Error ? actionError.message : String(actionError));
    } finally {
      setOpenClawAction(null);
    }
  }

  async function handleRunOpenClawSmartRetry() {
    if (!project) {
      return;
    }

    const retryPolicy = buildOpenClawRetryPolicy(project.openClaw);
    if (!retryPolicy.canAutoRetry || !retryPolicy.immediate) {
      setStatus(retryPolicy.detail);
      return;
    }

    await handleRunOpenClawRecoveryPlan();
  }

  function handleImportDetectedAgents(detectedAgentIds?: string[]) {
    setOpenClawAction("import");
    try {
      updateProject(
        (current) => importDetectedOpenClawAgents(current, detectedAgentIds),
        detectedAgentIds && detectedAgentIds.length === 1
          ? "Imported detected OpenClaw agent into the project."
          : "Imported detected OpenClaw agents into the project."
      );
    } finally {
      setOpenClawAction(null);
    }
  }

  async function handlePublishWorkbenchPrompt() {
    if (!project || !activeWorkflow) {
      return;
    }

    const trimmedPrompt = workbenchPrompt.trim();
    if (!trimmedPrompt) {
      setWorkbenchError("Enter a task prompt for the active workflow.");
      return;
    }

    const runtimeReadiness = assessOpenClawRuntimeReadiness(project.openClaw);
    if (runtimeReadiness.blockingMessage) {
      setWorkbenchError(runtimeReadiness.blockingMessage);
      return;
    }

    if (!hasExecutableWorkflow) {
      setWorkbenchError("Connect the Start node to at least one assigned agent before publishing.");
      return;
    }

    setWorkbenchAction("publish");
    setWorkbenchError(null);
    try {
      const liveCase = await runLiveWorkflowCase(project, activeWorkflow, trimmedPrompt);
      if (liveCase.blocked) {
        const message = liveCase.errorMessage ?? "Live execution was blocked by runtime isolation guardrails.";
        setWorkbenchError(message);
        setStatus(`Blocked live OpenClaw execution: ${message}`);
        return;
      }
      if (liveCase.liveExecutions.length > 0 && liveCase.liveExecutions[0]?.success) {
        const liveResult = publishWorkbenchPromptWithLiveExecution(
          project,
          activeWorkflow.id,
          trimmedPrompt,
          liveCase.liveExecutions,
          liveCase.approvalCheckpoints
        );

        if (!liveResult.taskId) {
          setWorkbenchError("Live execution finished, but the workbench receipt could not be recorded.");
          return;
        }

        commitProject(
          liveResult.project,
          liveResult.pendingApprovalCount > 0
            ? `${liveCase.advisoryMessage ? `Advisory: ${liveCase.advisoryMessage} ` : ""}Published workbench task with ${liveResult.completedNodeCount} real execution receipt(s) and ${liveResult.pendingApprovalCount} approval checkpoint(s).`
            : `${liveCase.advisoryMessage ? `Advisory: ${liveCase.advisoryMessage} ` : ""}Published workbench task with ${liveResult.completedNodeCount} real OpenClaw execution receipt(s).`
        );
        setWorkbenchPrompt("");
        setSelectedTaskId(liveResult.taskId);
        return;
      }

      if (liveCase.errorMessage) {
        setStatus(
          `${liveCase.advisoryMessage ? `Advisory: ${liveCase.advisoryMessage} ` : ""}Live OpenClaw execution was unavailable. Falling back to synthetic receipt: ${liveCase.errorMessage}`
        );
      }

      const result = publishWorkbenchPrompt(project, activeWorkflow.id, trimmedPrompt);
      if (!result.taskId) {
        setWorkbenchError("Workbench publish could not resolve an executable entry agent.");
        return;
      }

      commitProject(
        result.project,
        result.pendingApprovalCount > 0
          ? `${liveCase.advisoryMessage ? `Advisory: ${liveCase.advisoryMessage} ` : ""}Published workbench task with ${result.pendingApprovalCount} approval checkpoint(s).`
          : `${liveCase.advisoryMessage ? `Advisory: ${liveCase.advisoryMessage} ` : ""}Published workbench task and recorded ${result.completedNodeCount} execution receipt(s).`
      );
      setWorkbenchPrompt("");
      setSelectedTaskId(result.taskId);
    } finally {
      setWorkbenchAction(null);
    }
  }

  async function handleWorkbenchApproval(messageId: string, decision: "approve" | "reject") {
    if (!project) {
      return;
    }

    setWorkbenchAction(`approval:${messageId}`);
    setWorkbenchError(null);
    try {
      const approvalMessage = project.messages.find((message) => message.id === messageId) ?? null;
      const linkedTask =
        project.tasks.find((task) => task.id === approvalMessage?.metadata.taskID) ?? null;
      const linkedWorkflow =
        project.workflows.find((workflow) => workflow.id === approvalMessage?.metadata.workflowID) ?? null;
      const targetNode =
        linkedWorkflow?.nodes.find((node) => node.id === approvalMessage?.metadata.targetNodeID) ?? null;
      const liveApproval = shouldAttemptLiveApprovalContinuation(
        project,
        approvalMessage,
        linkedWorkflow,
        targetNode?.id
      );

      if (
        decision === "approve" &&
        approvalMessage?.metadata.liveExecution === "true" &&
        liveApproval.blockingMessage
      ) {
        setWorkbenchError(liveApproval.blockingMessage);
        setStatus(`Blocked downstream OpenClaw execution: ${liveApproval.blockingMessage}`);
        return;
      }

      if (
        decision === "approve" &&
        approvalMessage &&
        linkedTask?.metadata.liveExecution === "true" &&
        linkedWorkflow &&
        targetNode?.agentID &&
        liveApproval.shouldAttempt
      ) {
        const completedNodeIds = parseMetadataCsv(linkedTask.metadata.completedNodeIDs);
        const visitCounts = new Map(completedNodeIds.map((nodeId) => [nodeId, 1] as const));
        const downstreamWork = await runLiveWorkflowExecutions(
          project,
          linkedWorkflow,
          linkedTask.metadata.prompt ?? linkedTask.description,
          [{ edge: null, targetNodeId: targetNode.id }],
          visitCounts
        );
        if (downstreamWork.blocked) {
          const message =
            downstreamWork.errorMessage ?? "Approval could not continue because runtime isolation checks failed.";
          setWorkbenchError(message);
          setStatus(`Blocked downstream OpenClaw execution: ${message}`);
          return;
        }
        const liveApprovalResult = reviewWorkbenchApprovalWithLiveExecution(
          project,
          messageId,
          decision,
          downstreamWork.liveExecutions,
          downstreamWork.approvalCheckpoints
        );

        commitProject(
          liveApprovalResult.project,
          liveApprovalResult.pendingApprovalCount > 0
            ? `${downstreamWork.advisoryMessage ? `Advisory: ${downstreamWork.advisoryMessage} ` : ""}Approval granted. ${liveApprovalResult.completedNodeCount} node(s) completed and ${liveApprovalResult.pendingApprovalCount} checkpoint(s) remain.`
            : `${downstreamWork.advisoryMessage ? `Advisory: ${downstreamWork.advisoryMessage} ` : ""}Approval granted and downstream OpenClaw execution completed.`
        );
        if (liveApprovalResult.taskId) {
          setSelectedTaskId(liveApprovalResult.taskId);
        }
        return;
      }

      const result = reviewWorkbenchApproval(project, messageId, decision);
      commitProject(
        result.project,
        decision === "approve"
          ? result.pendingApprovalCount > 0
            ? `Approval granted. ${result.pendingApprovalCount} checkpoint(s) remain.`
            : `Approval granted and workflow execution receipts were updated.`
          : "Approval request rejected and the workbench task remains blocked."
      );
      if (result.taskId) {
        setSelectedTaskId(result.taskId);
      }
    } finally {
      setWorkbenchAction(null);
    }
  }

  const taskCompletionRate =
    project && project.tasks.length > 0
      ? project.tasks.filter((task) => task.status === "Done").length / project.tasks.length
      : 0;
  const averageTaskDurationSeconds =
    project && project.tasks.length > 0
      ? (() => {
          const completedTasks = project.tasks.filter((task) => task.actualDuration != null);
          if (completedTasks.length === 0) {
            return null;
          }
          const totalDuration = completedTasks.reduce(
            (sum, task) => sum + (task.actualDuration ?? 0),
            0
          );
          return totalDuration / completedTasks.length;
        })()
      : null;
  const blockedTaskCount = project?.tasks.filter((task) => task.status === "Blocked").length ?? 0;
  const inProgressTaskCount = project?.tasks.filter((task) => task.status === "In Progress").length ?? 0;
  const taskLinkedToWorkflowCount = project?.tasks.filter((task) => task.workflowNodeID).length ?? 0;
  const pendingApprovalCount =
    project?.messages.filter((message) => message.status === "Waiting for Approval").length ?? 0;
  const failedMessageCount = project?.messages.filter((message) => message.status === "Failed").length ?? 0;
  const failedExecutionCount =
    project?.executionResults.filter((result) => result.status === "Failed").length ?? 0;
  const completedExecutionCount =
    project?.executionResults.filter((result) => result.status === "Completed").length ?? 0;
  const executionSuccessRate =
    completedExecutionCount + failedExecutionCount > 0
      ? completedExecutionCount / (completedExecutionCount + failedExecutionCount)
      : null;
  const errorLogCount = project?.executionLogs.filter((entry) => entry.level === "ERROR").length ?? 0;
  const warnLogCount = project?.executionLogs.filter((entry) => entry.level === "WARN").length ?? 0;
  const openClawReadiness = project ? computeOpenClawReadiness(project) : null;
  const openClawRuntimeReadiness = project ? assessOpenClawRuntimeReadiness(project.openClaw) : null;
  const recentExecutionResults =
    project?.executionResults
      .slice()
      .sort((left, right) => right.startedAt - left.startedAt)
      .slice(0, 5) ?? [];
  const recentExecutionLogs =
    project?.executionLogs
      .slice()
      .sort((left, right) => right.timestamp - left.timestamp)
      .slice(0, 6) ?? [];
  const agentLoadRows =
    project?.agents.map((agent) => {
      const tasks = project.tasks.filter((task) => task.assignedAgentID === agent.id);
      const activeTasks = tasks.filter((task) => task.status === "In Progress").length;
      const blockedTasks = tasks.filter((task) => task.status === "Blocked").length;
      const completedTasks = tasks.filter((task) => task.status === "Done").length;
      return {
        agent,
        totalTasks: tasks.length,
        activeTasks,
        blockedTasks,
        completedTasks,
        workflowTasks: tasks.filter((task) => task.workflowNodeID).length
      };
    }) ?? [];
  const workflowCoverageRows =
    project?.workflows.map((workflow) => {
      const agentNodes = workflow.nodes.filter((node) => node.type === "agent");
      const assignedNodes = agentNodes.filter((node) => node.agentID).length;
      const linkedTasks = project.tasks.filter((task) =>
        task.workflowNodeID ? agentNodes.some((node) => node.id === task.workflowNodeID) : false
      ).length;
      const coverage = agentNodes.length > 0 ? assignedNodes / agentNodes.length : 1;

      return {
        workflow,
        agentNodeCount: agentNodes.length,
        assignedNodeCount: assignedNodes,
        linkedTasks,
        coverage
      };
    }) ?? [];
  const importedOpenClawAgentKeys = new Set(
    project?.agents.flatMap((agent) => [agent.name.trim().toLowerCase(), agent.openClawDefinition.agentIdentifier.trim().toLowerCase()]) ??
      []
  );
  const workbenchMessages =
    project && activeWorkflow
      ? project.messages
          .filter(
            (message) =>
              message.metadata.channel === "workbench" && message.metadata.workflowID === activeWorkflow.id
          )
          .slice()
          .sort((left, right) => left.timestamp - right.timestamp)
      : [];
  const pendingApprovalMessages = workbenchMessages.filter(
    (message) => message.status === "Waiting for Approval" && message.requiresApproval
  );
  const workbenchTaskIds = new Set(
    workbenchMessages.map((message) => message.metadata.taskID).filter((value): value is string => Boolean(value))
  );
  const workbenchTasks =
    project?.tasks
      .filter((task) => workbenchTaskIds.has(task.id))
      .slice()
      .sort((left, right) => right.createdAt - left.createdAt) ?? [];
  const workbenchNodeIds = new Set(activeWorkflow?.nodes.map((node) => node.id) ?? []);
  const workbenchExecutionResults =
    project?.executionResults
      .filter((result) => workbenchNodeIds.has(result.nodeID))
      .slice()
      .sort((left, right) => right.startedAt - left.startedAt)
      .slice(0, 10) ?? [];
  const executableEntryNodeIds = project && activeWorkflow ? resolveEntryAgentNodeIds(project, activeWorkflow.id) : [];
  const hasExecutableWorkflow = executableEntryNodeIds.length > 0;

  function updateCanvasZoom(nextZoom: number) {
    const clampedZoom = Math.min(MAX_CANVAS_ZOOM, Math.max(MIN_CANVAS_ZOOM, Number(nextZoom.toFixed(2))));
    setCanvasZoom(clampedZoom);
    setStatus(`Canvas zoom set to ${Math.round(clampedZoom * 100)}%.`);
  }

  function handleSelectedNodeXChange(nextValue: string) {
    if (!activeWorkflow || !selectedNode) {
      return;
    }

    const parsed = Number(nextValue);
    if (Number.isNaN(parsed)) {
      return;
    }

    updateProject((current) =>
      repositionWorkflowNode(current, activeWorkflow.id, selectedNode.id, parsed, selectedNode.position.y)
    );
  }

  function handleSelectedNodeYChange(nextValue: string) {
    if (!activeWorkflow || !selectedNode) {
      return;
    }

    const parsed = Number(nextValue);
    if (Number.isNaN(parsed)) {
      return;
    }

    updateProject((current) =>
      repositionWorkflowNode(current, activeWorkflow.id, selectedNode.id, selectedNode.position.x, parsed)
    );
  }

  function handleSelectedEdgeLabelChange(nextLabel: string) {
    if (!activeWorkflow || !selectedEdge) {
      return;
    }

    updateProject(
      (current) => updateWorkflowEdgeLabel(current, activeWorkflow.id, selectedEdge.id, nextLabel),
      "Updated edge label."
    );
  }

  function handleSelectedEdgeApprovalChange(nextValue: boolean) {
    if (!activeWorkflow || !selectedEdge) {
      return;
    }

    updateProject(
      (current) => setWorkflowEdgeApprovalRequired(current, activeWorkflow.id, selectedEdge.id, nextValue),
      "Updated edge approval requirement."
    );
  }

  function handleSelectedEdgeBidirectionalChange(nextValue: boolean) {
    if (!activeWorkflow || !selectedEdge) {
      return;
    }

    updateProject(
      (current) => setWorkflowEdgeBidirectional(current, activeWorkflow.id, selectedEdge.id, nextValue),
      "Updated edge directionality."
    );
  }

  return (
    <main className="shell">
      <section className="hero">
        <p className="eyebrow">Cross-platform migration</p>
        <h1>Multi-Agent-Flow project shell</h1>
        <p className="lede">
          The new desktop shell can now create, open, save, and save-as `.maoproj` files, and it
          has started taking over agent and workflow state editing from the legacy macOS app.
        </p>
      </section>

      <section className="toolbar">
        <button type="button" onClick={() => void handleCreateProject()} disabled={busyAction !== null}>
          {busyAction === "new" ? "Creating..." : "New"}
        </button>
        <button type="button" onClick={() => void handleOpenProject()} disabled={busyAction !== null}>
          {busyAction === "open" ? "Opening..." : "Open"}
        </button>
        <button type="button" onClick={() => void handleSaveProject()} disabled={!project || busyAction !== null}>
          {busyAction === "save" ? "Saving..." : "Save"}
        </button>
        <button
          type="button"
          onClick={() => void handleSaveProjectAs()}
          disabled={!project || busyAction !== null}
        >
          {busyAction === "saveAs" ? "Saving..." : "Save As"}
        </button>
        <button
          type="button"
          onClick={() => handleRemoveNodes(selectedNodeIds)}
          disabled={selectedNodeIds.length === 0 || busyAction !== null}
        >
          Delete Selected
        </button>
        <button type="button" onClick={handleUndo} disabled={!canUndo || busyAction !== null}>
          Undo
        </button>
        <button type="button" onClick={handleRedo} disabled={!canRedo || busyAction !== null}>
          Redo
        </button>
      </section>

      <section className="statusBar">
        <p>{status}</p>
        {autosaveInfo ? <p>Autosave: {autosaveInfo.savedAt}</p> : null}
        {error ? <p className="errorText">{error}</p> : null}
      </section>

      <section className="grid">
        <article className="card">
          <h2>Project details</h2>
          {project ? (
            <div className="formStack">
              <label className="field">
                <span>Project name</span>
                <input
                  value={project.name}
                  onChange={(event) => handleProjectNameChange(event.target.value)}
                  placeholder="Untitled Project"
                />
              </label>

              <dl className="meta">
                <div>
                  <dt>File version</dt>
                  <dd>{project.fileVersion}</dd>
                </div>
                <div>
                  <dt>Project file</dt>
                  <dd>{filePath ?? "Unsaved project"}</dd>
                </div>
                <div>
                  <dt>Created at</dt>
                  <dd>{fromSwiftDate(project.createdAt).toISOString()}</dd>
                </div>
                <div>
                  <dt>Updated at</dt>
                  <dd>{fromSwiftDate(project.updatedAt).toISOString()}</dd>
                </div>
              </dl>
            </div>
          ) : (
            <p className="emptyState">Project state is still loading.</p>
          )}
        </article>

        <article className="card">
          <h2>Agents</h2>
          {project ? (
            <div className="formStack">
              <div className="inlineForm">
                <input value={newAgentName} onChange={(event) => setNewAgentName(event.target.value)} />
                <button type="button" onClick={handleAddAgent}>
                  Add agent
                </button>
              </div>
              {project.agents.length > 0 ? (
                <div className="listStack">
                  {project.agents.map((agent) => (
                    <div key={agent.id} className="inspectorCard">
                      <div className="dashboardListItemHeader">
                        <strong>{agent.name}</strong>
                        <span>{agent.identity}</span>
                      </div>
                      <div className="inspectorGrid">
                        <label className="field compactField">
                          <span>Agent name</span>
                          <input
                            value={agent.name}
                            onChange={(event) => handleUpdateAgent(agent.id, { name: event.target.value })}
                          />
                        </label>
                        <label className="field compactField">
                          <span>Identity</span>
                          <input
                            value={agent.identity}
                            onChange={(event) => handleUpdateAgent(agent.id, { identity: event.target.value })}
                          />
                        </label>
                        <label className="field compactField">
                          <span>Capabilities</span>
                          <input
                            value={formatCsvInput(agent.capabilities)}
                            placeholder="basic, planner, reviewer"
                            onChange={(event) =>
                              handleUpdateAgent(agent.id, { capabilities: parseTagInput(event.target.value) })
                            }
                          />
                        </label>
                        <label className="field compactField">
                          <span>OpenClaw agent ID</span>
                          <input
                            value={agent.openClawDefinition.agentIdentifier}
                            placeholder="code-dev-task-1"
                            spellCheck={false}
                            onChange={(event) =>
                              handleUpdateAgent(agent.id, {
                                openClawDefinition: { agentIdentifier: event.target.value }
                              })
                            }
                          />
                          <small
                            className={
                              isRuntimeAgentIdentifierValid(agent.openClawDefinition.agentIdentifier)
                                ? "fieldNote"
                                : "fieldNote fieldNoteError"
                            }
                          >
                            {describeRuntimeAgentIdentifier(agent.openClawDefinition.agentIdentifier)}
                          </small>
                        </label>
                        <label className="field compactField">
                          <span>Model</span>
                          <input
                            value={agent.openClawDefinition.modelIdentifier}
                            onChange={(event) =>
                              handleUpdateAgent(agent.id, {
                                openClawDefinition: { modelIdentifier: event.target.value }
                              })
                            }
                          />
                        </label>
                        <label className="field compactField">
                          <span>Runtime profile</span>
                          <input
                            value={agent.openClawDefinition.runtimeProfile}
                            placeholder="default"
                            onChange={(event) =>
                              handleUpdateAgent(agent.id, {
                                openClawDefinition: { runtimeProfile: event.target.value }
                              })
                            }
                          />
                        </label>
                        <label className="field compactField">
                          <span>Memory backup path</span>
                          <input
                            value={agent.openClawDefinition.memoryBackupPath ?? ""}
                            placeholder="/path/to/state"
                            onChange={(event) =>
                              handleUpdateAgent(agent.id, {
                                openClawDefinition: { memoryBackupPath: event.target.value || null }
                              })
                            }
                          />
                        </label>
                        <label className="field compactField">
                          <span>SOUL source path</span>
                          <input
                            value={agent.openClawDefinition.soulSourcePath ?? ""}
                            placeholder="/path/to/SOUL.md"
                            onChange={(event) =>
                              handleUpdateAgent(agent.id, {
                                openClawDefinition: { soulSourcePath: event.target.value || null }
                              })
                            }
                          />
                        </label>
                      </div>
                      <label className="field">
                        <span>Description</span>
                        <textarea
                          value={agent.description}
                          placeholder="Describe this agent's responsibility."
                          onChange={(event) => handleUpdateAgent(agent.id, { description: event.target.value })}
                        />
                      </label>
                      <label className="field">
                        <span>Environment overrides</span>
                        <textarea
                          value={formatKeyValueLines(agent.openClawDefinition.environment)}
                          placeholder={"OPENAI_API_KEY=...\nOPENCLAW_PROFILE=prod"}
                          onChange={(event) =>
                            handleUpdateAgent(agent.id, {
                              openClawDefinition: { environment: parseKeyValueLines(event.target.value) }
                            })
                          }
                        />
                      </label>
                      <label className="field">
                        <span>SOUL prompt</span>
                        <textarea
                          value={agent.soulMD}
                          placeholder="# Agent prompt"
                          onChange={(event) => handleUpdateAgent(agent.id, { soulMD: event.target.value })}
                        />
                      </label>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="emptyState">No agents yet.</p>
              )}
            </div>
          ) : (
            <p className="emptyState">Project state is still loading.</p>
          )}
        </article>

        <article className="card cardWide">
          <h2>Workflow state shell</h2>
          {project ? (
            <div className="formStack">
              <div className="inlineForm">
                <input value={newWorkflowName} onChange={(event) => setNewWorkflowName(event.target.value)} />
                <button type="button" onClick={handleAddWorkflow}>
                  Add workflow
                </button>
              </div>

              <label className="field">
                <span>Active workflow</span>
                <select
                  value={activeWorkflow?.id ?? ""}
                  onChange={(event) => setActiveWorkflowId(event.target.value || null)}
                >
                  {project.workflows.map((workflow) => (
                    <option key={workflow.id} value={workflow.id}>
                      {workflow.name}
                    </option>
                  ))}
                </select>
              </label>

              {activeWorkflow ? (
                <>
                  <div className="workflowHeader">
                    <label className="field">
                      <span>Workflow name</span>
                      <input
                        value={activeWorkflow.name}
                        onChange={(event) => handleWorkflowNameChange(event.target.value)}
                      />
                    </label>
                    <label className="field compactField">
                      <span>Fallback policy</span>
                      <select
                        value={activeWorkflow.fallbackRoutingPolicy}
                        onChange={(event) =>
                          handleWorkflowPolicyChange(
                            event.target.value as WorkflowFallbackRoutingPolicy
                          )
                        }
                      >
                        <option value="stop">stop</option>
                        <option value="first_available">first_available</option>
                        <option value="all_available">all_available</option>
                      </select>
                    </label>
                    <button
                      type="button"
                      className="dangerButton"
                      onClick={handleRemoveActiveWorkflow}
                      disabled={project.workflows.length <= 1}
                    >
                      Remove workflow
                    </button>
                  </div>

                  <div className="workflowToolbar">
                    <label className="field compactField">
                      <span>Node type</span>
                      <select
                        value={newNodeType}
                        onChange={(event) => setNewNodeType(event.target.value as WorkflowNodeType)}
                      >
                        <option value="agent">Agent</option>
                        <option value="start">Start</option>
                      </select>
                    </label>
                    <button type="button" onClick={handleAddNode}>
                      Add node
                    </button>
                  </div>

                  <div className="metaStrip">
                    <span>Nodes: {activeWorkflow.nodes.length}</span>
                    <span>Edges: {activeWorkflow.edges.length}</span>
                    <span>Policy: {activeWorkflow.fallbackRoutingPolicy}</span>
                    <span>Zoom: {Math.round(canvasZoom * 100)}%</span>
                    <span>Undo: {projectHistory.past.length}</span>
                    <span>Selected nodes: {selectedNodeIds.length}</span>
                  </div>

                  <div className="formStack">
                    <span className="sectionLabel">Launch verification</span>
                    <div className="inspectorCard">
                      <div className="dashboardPanelHeader">
                        <h3>Preflight check</h3>
                        <span>{activeWorkflow.launchTestCases.length} saved case(s)</span>
                      </div>
                      <p className="canvasHint">
                        This desktop pass checks structure, entry routing, agent bindings, and other launch blockers before execution.
                      </p>
                      <div className="taskMeta">
                        <span>
                          {activeWorkflow.launchTestCases.length > 0
                            ? `${activeWorkflow.launchTestCases.length} saved case(s) will run.`
                            : "No saved cases yet. Built-in smoke cases will run until you add workflow-specific contracts."}
                        </span>
                        {launchVerificationIsStale ? <span>Current report is stale and should be rerun.</span> : null}
                      </div>
                      <div className="inspectorActions">
                        <button
                          type="button"
                          onClick={() => {
                            void handleRunLaunchVerification();
                          }}
                          disabled={verificationAction !== null}
                        >
                          {verificationAction === "run" ? "Running..." : "Run launch verification"}
                        </button>
                        <button type="button" onClick={handleAddLaunchTestCase}>
                          Add saved case
                        </button>
                      </div>
                      {activeWorkflow.launchTestCases.length > 0 ? (
                        <div className="dashboardList">
                          {activeWorkflow.launchTestCases.map((testCase: WorkflowLaunchTestCase) => (
                            <article key={testCase.id} className="dashboardListItem">
                              <div className="dashboardListItemHeader">
                                <strong>{testCase.name}</strong>
                                <button
                                  type="button"
                                  className="ghostDangerButton"
                                  onClick={() => handleRemoveLaunchTestCase(testCase.id)}
                                >
                                  Remove
                                </button>
                              </div>
                              <label className="field">
                                <span>Prompt</span>
                                <textarea
                                  value={testCase.prompt}
                                  placeholder="Describe the prompt this workflow must handle during launch."
                                  onChange={(event) =>
                                    handleUpdateLaunchTestCase(testCase.id, { prompt: event.target.value })
                                  }
                                />
                              </label>
                              <div className="inspectorGrid">
                                <label className="field compactField">
                                  <span>Case name</span>
                                  <input
                                    value={testCase.name}
                                    placeholder="Launch Case"
                                    onChange={(event) =>
                                      handleUpdateLaunchTestCase(testCase.id, { name: event.target.value })
                                    }
                                  />
                                </label>
                                <label className="field compactField">
                                  <span>Required agents</span>
                                  <input
                                    value={formatCsvInput(testCase.requiredAgentNames)}
                                    placeholder="Coordinator, Planner"
                                    onChange={(event) =>
                                      handleUpdateLaunchTestCase(testCase.id, {
                                        requiredAgentNames: parseTagInput(event.target.value)
                                      })
                                    }
                                  />
                                </label>
                                <label className="field compactField">
                                  <span>Forbidden agents</span>
                                  <input
                                    value={formatCsvInput(testCase.forbiddenAgentNames)}
                                    placeholder="Escalation Bot"
                                    onChange={(event) =>
                                      handleUpdateLaunchTestCase(testCase.id, {
                                        forbiddenAgentNames: parseTagInput(event.target.value)
                                      })
                                    }
                                  />
                                </label>
                                <label className="field compactField">
                                  <span>Routing actions</span>
                                  <input
                                    value={formatCsvInput(testCase.expectedRoutingActions)}
                                    placeholder="stop, route"
                                    onChange={(event) =>
                                      handleUpdateLaunchTestCase(testCase.id, {
                                        expectedRoutingActions: parseTagInput(event.target.value)
                                      })
                                    }
                                  />
                                </label>
                                <label className="field compactField">
                                  <span>Output types</span>
                                  <input
                                    value={formatCsvInput(testCase.expectedOutputTypes)}
                                    placeholder="agent_final_response"
                                    onChange={(event) =>
                                      handleUpdateLaunchTestCase(testCase.id, {
                                        expectedOutputTypes: parseTagInput(event.target.value)
                                      })
                                    }
                                  />
                                </label>
                                <label className="field compactField">
                                  <span>Max steps</span>
                                  <input
                                    type="number"
                                    min="1"
                                    value={testCase.maxSteps ?? ""}
                                    placeholder="Optional"
                                    onChange={(event) =>
                                      handleUpdateLaunchTestCase(testCase.id, {
                                        maxSteps:
                                          event.target.value.trim().length === 0
                                            ? null
                                            : Number(event.target.value)
                                      })
                                    }
                                  />
                                </label>
                              </div>
                              <label className="field">
                                <span>Notes</span>
                                <textarea
                                  value={testCase.notes}
                                  placeholder="Capture the specific contract you expect this workflow to keep."
                                  onChange={(event) =>
                                    handleUpdateLaunchTestCase(testCase.id, { notes: event.target.value })
                                  }
                                />
                              </label>
                            </article>
                          ))}
                        </div>
                      ) : (
                        <p className="emptyState">
                          Save your own launch cases here when you want workflow-specific prompts, routing expectations, and step limits instead of the built-in smoke coverage.
                        </p>
                      )}

                      {launchVerificationReport ? (
                        <div className="dashboardList">
                          <article className="dashboardListItem">
                            <div className="dashboardListItemHeader">
                              <strong>Latest report</strong>
                              <span
                                className={`taskPriorityBadge taskPriority-${toClassToken(
                                  verificationStatusToken(launchVerificationReport.status)
                                )}`}
                              >
                                {verificationStatusLabel(launchVerificationReport.status)}
                              </span>
                            </div>
                            <div className="taskMeta">
                              <span>Started {formatDate(launchVerificationReport.startedAt)}</span>
                              <span>Completed {formatDate(launchVerificationReport.completedAt)}</span>
                              <span>Signature {launchVerificationReport.workflowSignature.slice(0, 20)}...</span>
                              <span>{launchVerificationReport.testCaseReports.length} runtime case result(s)</span>
                            </div>
                            {launchVerificationIsStale ? (
                              <p className="dashboardEventBody">
                                This report no longer matches the current workflow or saved launch cases. Re-run launch verification to refresh it.
                              </p>
                            ) : null}
                            {launchVerificationReport.staticFindings.length > 0 ? (
                              <div className="dashboardChecklist">
                                {launchVerificationReport.staticFindings.map((finding) => (
                                  <div key={finding} className="dashboardChecklistItem">
                                    <strong>
                                      {launchVerificationReport.status === "fail" ? "Blocker" : "Attention"}
                                    </strong>
                                    <span>{finding}</span>
                                  </div>
                                ))}
                              </div>
                            ) : (
                              <p className="emptyState">No launch blockers were found in the current workflow structure.</p>
                            )}
                            {launchVerificationReport.runtimeFindings.length > 0 ? (
                              <div className="dashboardList">
                                {launchVerificationReport.runtimeFindings.map((finding) => (
                                  <article key={finding} className="dashboardListItem">
                                    <p className="dashboardEventBody">{finding}</p>
                                  </article>
                                ))}
                              </div>
                            ) : null}
                            {launchVerificationReport.testCaseReports.length > 0 ? (
                              <div className="dashboardList">
                                {launchVerificationReport.testCaseReports.map((caseReport) => (
                                  <article key={caseReport.id} className="dashboardListItem">
                                    <div className="dashboardListItemHeader">
                                      <strong>{caseReport.name}</strong>
                                      <span
                                        className={`taskPriorityBadge taskPriority-${toClassToken(
                                          verificationStatusToken(caseReport.status)
                                        )}`}
                                      >
                                        {verificationStatusLabel(caseReport.status)}
                                      </span>
                                    </div>
                                    <p className="dashboardEventBody">{caseReport.prompt}</p>
                                    <div className="taskMeta">
                                      <span>{caseReport.actualStepCount} step(s)</span>
                                      <span>
                                        Agents {caseReport.actualAgents.length > 0 ? caseReport.actualAgents.join(", ") : "none"}
                                      </span>
                                      <span>
                                        Routes{" "}
                                        {caseReport.actualRoutingActions.length > 0
                                          ? caseReport.actualRoutingActions.join(", ")
                                          : "none"}
                                      </span>
                                      <span>
                                        Outputs{" "}
                                        {caseReport.actualOutputTypes.length > 0
                                          ? caseReport.actualOutputTypes.join(", ")
                                          : "none"}
                                      </span>
                                    </div>
                                    {caseReport.notes.length > 0 ? (
                                      <div className="dashboardChecklist">
                                        {caseReport.notes.map((note, index) => (
                                          <div
                                            key={`${caseReport.id}-${index}-${note}`}
                                            className="dashboardChecklistItem"
                                          >
                                            <strong>{caseReport.status === "fail" ? "Issue" : "Note"}</strong>
                                            <span>{note}</span>
                                          </div>
                                        ))}
                                      </div>
                                    ) : (
                                      <p className="emptyState">This case completed without additional findings.</p>
                                    )}
                                  </article>
                                ))}
                              </div>
                            ) : null}
                          </article>
                        </div>
                      ) : (
                        <p className="emptyState">
                          No launch verification report yet. Run the preflight check to record a workflow readiness snapshot.
                        </p>
                      )}
                    </div>
                  </div>

                  <div className="formStack">
                    <span className="sectionLabel">Visual preview</span>
                    <p className="canvasHint">
                      Click one node to choose a source, drag from a node handle to connect directly,
                      drag nodes to reposition them, hold Space and drag to pan, use zoom controls
                      plus scrolling to inspect larger workflows, press Esc/Delete for quick canvas
                      cleanup, use Cmd/Ctrl+Z to undo changes, Shift/Cmd/Ctrl-click to multi-select
                      nodes, and hold Alt while dragging to temporarily disable snapping.
                    </p>
                    <div className="workflowToolbar">
                      <button type="button" onClick={() => updateCanvasZoom(canvasZoom - 0.1)}>
                        Zoom out
                      </button>
                      <button type="button" onClick={() => updateCanvasZoom(DEFAULT_CANVAS_ZOOM)}>
                        Reset zoom
                      </button>
                      <button type="button" onClick={() => updateCanvasZoom(canvasZoom + 0.1)}>
                        Zoom in
                      </button>
                      <button type="button" onClick={handleUndo} disabled={!canUndo}>
                        Undo
                      </button>
                      <button type="button" onClick={handleRedo} disabled={!canRedo}>
                        Redo
                      </button>
                    </div>
                    <WorkflowCanvasPreview
                      workflow={activeWorkflow}
                      agents={project.agents}
                      zoom={canvasZoom}
                      selectedNodeId={selectedNodeId ?? undefined}
                      selectedNodeIds={selectedNodeIds}
                      selectedEdgeId={selectedEdgeId ?? undefined}
                      selectedFromNodeId={connectionFromNodeId}
                      selectedToNodeId={connectionToNodeId}
                      onWheelZoom={(deltaY) => updateCanvasZoom(canvasZoom + (deltaY < 0 ? 0.1 : -0.1))}
                      onNodeConnect={handleCanvasNodeConnect}
                      onNodeSelect={handleCanvasNodeSelectionChange}
                      onSelectionBox={handleCanvasSelectionBox}
                      onEdgeSelect={handleCanvasEdgeSelect}
                      onNodePositionChange={handleNodePositionChange}
                      onNodePositionCommit={handleNodePositionCommit}
                      onNodesPositionChange={handleNodesPositionChange}
                      onNodesPositionCommit={handleNodesPositionCommit}
                      onNodeClick={handleCanvasNodeClick}
                      onCanvasClick={handleCanvasBackgroundClick}
                    />
                  </div>

                  <div className="formStack">
                    <span className="sectionLabel">Selected node</span>
                    {selectedNode ? (
                      <div className="inspectorCard">
                        <div className="inspectorGrid">
                          <label className="field">
                            <span>Node title</span>
                            <input
                              value={selectedNode.title}
                              onChange={(event) => handleRenameNode(selectedNode.id, event.target.value)}
                              placeholder={selectedNode.type === "start" ? "Start" : "Node title"}
                            />
                          </label>
                          <label className="field compactField">
                            <span>Assigned agent</span>
                            <select
                              value={selectedNode.agentID ?? ""}
                              onChange={(event) => handleAssignAgent(selectedNode.id, event.target.value || null)}
                            >
                              <option value="">Unassigned</option>
                              {project.agents.map((agent) => (
                                <option key={agent.id} value={agent.id}>
                                  {agent.name}
                                </option>
                              ))}
                            </select>
                          </label>
                          <label className="field compactField">
                            <span>X</span>
                            <input
                              type="number"
                              value={Math.round(selectedNode.position.x)}
                              onChange={(event) => handleSelectedNodeXChange(event.target.value)}
                            />
                          </label>
                          <label className="field compactField">
                            <span>Y</span>
                            <input
                              type="number"
                              value={Math.round(selectedNode.position.y)}
                              onChange={(event) => handleSelectedNodeYChange(event.target.value)}
                            />
                          </label>
                        </div>
                        <div className="metaStrip">
                          <span>Node type: {selectedNode.type}</span>
                          <span>ID: {selectedNode.id.slice(0, 8)}</span>
                        </div>
                      </div>
                    ) : selectedNodeIds.length > 1 ? (
                      <div className="inspectorCard">
                        <div className="metaStrip">
                          <span>{selectedNodeIds.length} nodes selected</span>
                          <span>Batch actions ready</span>
                        </div>
                        <div className="inspectorGrid">
                          <label className="field compactField">
                            <span>Assign agent</span>
                            <select
                              value={multiSelectedAgentId}
                              onChange={(event) => {
                                if (event.target.value === "__mixed__") {
                                  return;
                                }
                                handleAssignAgents(
                                  selectedNodeIds,
                                  event.target.value === "" ? null : event.target.value
                                );
                              }}
                            >
                              <option value="__mixed__">Mixed selection</option>
                              <option value="">Unassigned</option>
                              {project.agents.map((agent) => (
                                <option key={agent.id} value={agent.id}>
                                  {agent.name}
                                </option>
                              ))}
                            </select>
                          </label>
                        </div>
                        <div className="inspectorActions">
                          <button type="button" onClick={() => handleAlignSelectedNodes("left")}>
                            Align left
                          </button>
                          <button type="button" onClick={() => handleAlignSelectedNodes("center")}>
                            Align center
                          </button>
                          <button type="button" onClick={() => handleAlignSelectedNodes("right")}>
                            Align right
                          </button>
                          <button type="button" onClick={() => handleAlignSelectedNodes("top")}>
                            Align top
                          </button>
                          <button type="button" onClick={() => handleAlignSelectedNodes("middle")}>
                            Align middle
                          </button>
                          <button type="button" onClick={() => handleAlignSelectedNodes("bottom")}>
                            Align bottom
                          </button>
                          <button
                            type="button"
                            onClick={() => handleDistributeSelectedNodes("horizontal")}
                            disabled={selectedNodes.length < 3}
                          >
                            Distribute horizontally
                          </button>
                          <button
                            type="button"
                            onClick={() => handleDistributeSelectedNodes("vertical")}
                            disabled={selectedNodes.length < 3}
                          >
                            Distribute vertically
                          </button>
                          <button
                            type="button"
                            onClick={handleTidySelectedNodes}
                            disabled={selectedNodes.length < 2}
                          >
                            Tidy grid
                          </button>
                        </div>
                        <p className="emptyState">
                          Single-node inspector is disabled during multi-select. Use alignment,
                          distribution, tidy layout, batch agent assignment, or Delete Selected to
                          edit this group.
                        </p>
                      </div>
                    ) : (
                      <p className="emptyState">Select a node on the canvas to inspect and edit it.</p>
                    )}
                  </div>

                  <div className="formStack">
                    <span className="sectionLabel">Selected edge</span>
                    {selectedEdge ? (
                      <div className="inspectorCard">
                        <div className="inspectorGrid">
                          <label className="field">
                            <span>Label</span>
                            <input
                              value={selectedEdge.label}
                              onChange={(event) => handleSelectedEdgeLabelChange(event.target.value)}
                              placeholder="Optional edge label"
                            />
                          </label>
                          <label className="checkboxField">
                            <input
                              type="checkbox"
                              checked={selectedEdge.requiresApproval}
                              onChange={(event) => handleSelectedEdgeApprovalChange(event.target.checked)}
                            />
                            <span>Requires approval</span>
                          </label>
                          <label className="checkboxField">
                            <input
                              type="checkbox"
                              checked={selectedEdge.isBidirectional}
                              onChange={(event) => handleSelectedEdgeBidirectionalChange(event.target.checked)}
                            />
                            <span>Bidirectional</span>
                          </label>
                        </div>
                        <div className="metaStrip">
                          <span>From: {selectedEdge.fromNodeID.slice(0, 8)}</span>
                          <span>To: {selectedEdge.toNodeID.slice(0, 8)}</span>
                          <span>ID: {selectedEdge.id.slice(0, 8)}</span>
                        </div>
                      </div>
                    ) : (
                      <p className="emptyState">Select an edge on the canvas to inspect and edit it.</p>
                    )}
                  </div>

                  <div className="listStack">
                    {activeWorkflow.nodes.map((node) => (
                      <div key={node.id} className="listCard">
                        <div className="listCardHeader">
                          <strong>{node.title || node.type}</strong>
                          <button
                            type="button"
                            className="ghostDangerButton"
                            onClick={() => handleRemoveNode(node.id)}
                          >
                            Remove
                          </button>
                        </div>
                        <span>
                          {node.type} at ({Math.round(node.position.x)}, {Math.round(node.position.y)})
                        </span>
                        <label className="field compactField">
                          <span>Node title</span>
                          <input
                            value={node.title}
                            onChange={(event) => handleRenameNode(node.id, event.target.value)}
                            placeholder={node.type === "start" ? "Start" : "Node title"}
                          />
                        </label>
                        <label className="field compactField">
                          <span>Assigned agent</span>
                          <select
                            value={node.agentID ?? ""}
                            onChange={(event) => handleAssignAgent(node.id, event.target.value || null)}
                          >
                            <option value="">Unassigned</option>
                            {project.agents.map((agent) => (
                              <option key={agent.id} value={agent.id}>
                                {agent.name}
                              </option>
                            ))}
                          </select>
                        </label>
                      </div>
                    ))}
                    {activeWorkflow.nodes.length === 0 ? (
                      <p className="emptyState">No nodes yet. Add a start or agent node first.</p>
                    ) : null}
                  </div>

                  <div className="connectionBuilder">
                    <label className="field compactField">
                      <span>From node</span>
                      <select value={connectionFromNodeId} onChange={(event) => setConnectionFromNodeId(event.target.value)}>
                        <option value="">Select node</option>
                        {activeWorkflow.nodes.map((node) => (
                          <option key={node.id} value={node.id}>
                            {node.title || node.type}
                          </option>
                        ))}
                      </select>
                    </label>
                    <label className="field compactField">
                      <span>To node</span>
                      <select value={connectionToNodeId} onChange={(event) => setConnectionToNodeId(event.target.value)}>
                        <option value="">Select node</option>
                        {activeWorkflow.nodes.map((node) => (
                          <option key={node.id} value={node.id}>
                            {node.title || node.type}
                          </option>
                        ))}
                      </select>
                    </label>
                    <button type="button" onClick={handleConnectNodes}>
                      Add edge
                    </button>
                  </div>

                  <div className="listStack">
                    {activeWorkflow.edges.map((edge) => (
                      <div key={edge.id} className="listCard">
                        <div className="listCardHeader">
                          <strong>
                            {edge.fromNodeID.slice(0, 8)} {"->"} {edge.toNodeID.slice(0, 8)}
                          </strong>
                          <button
                            type="button"
                            className="ghostDangerButton"
                            onClick={() => handleRemoveEdge(edge.id)}
                          >
                            Remove
                          </button>
                        </div>
                        <span>{edge.requiresApproval ? "Requires approval" : "Direct route"}</span>
                      </div>
                    ))}
                    {activeWorkflow.edges.length === 0 ? (
                      <p className="emptyState">No edges yet. Connect two nodes to start shaping a flow.</p>
                    ) : null}
                  </div>
                </>
              ) : (
                <p className="emptyState">No workflow selected.</p>
              )}
            </div>
          ) : (
            <p className="emptyState">Project state is still loading.</p>
          )}
        </article>

        <article className="card cardWide">
          <h2>Task workspace</h2>
          {project ? (
            <div className="formStack">
              <div className="metaStrip">
                <span>Total: {project.tasks.length}</span>
                <span>Completion: {formatPercent(taskCompletionRate)}</span>
                <span>
                  In progress: {project.tasks.filter((task) => task.status === "In Progress").length}
                </span>
                <span>Blocked: {project.tasks.filter((task) => task.status === "Blocked").length}</span>
                <span>Average completion: {formatDuration(averageTaskDurationSeconds)}</span>
              </div>

              <div className="workflowToolbar">
                <button type="button" onClick={handleGenerateTasks} disabled={!activeWorkflow}>
                  Generate from active workflow
                </button>
              </div>

              <div className="inspectorCard">
                <span className="sectionLabel">Create task</span>
                <div className="inspectorGrid">
                  <label className="field">
                    <span>Title</span>
                    <input
                      value={newTaskTitle}
                      onChange={(event) => setNewTaskTitle(event.target.value)}
                      placeholder="Document execution plan"
                    />
                  </label>
                  <label className="field compactField">
                    <span>Priority</span>
                    <select
                      value={newTaskPriority}
                      onChange={(event) => setNewTaskPriority(event.target.value as TaskPriority)}
                    >
                      {TASK_PRIORITIES.map((priority) => (
                        <option key={priority} value={priority}>
                          {priority}
                        </option>
                      ))}
                    </select>
                  </label>
                  <label className="field compactField">
                    <span>Assign agent</span>
                    <select
                      value={newTaskAgentId}
                      onChange={(event) => setNewTaskAgentId(event.target.value)}
                    >
                      <option value="">Unassigned</option>
                      {project.agents.map((agent) => (
                        <option key={agent.id} value={agent.id}>
                          {agent.name}
                        </option>
                      ))}
                    </select>
                  </label>
                  <label className="field">
                    <span>Tags</span>
                    <input
                      value={newTaskTags}
                      onChange={(event) => setNewTaskTags(event.target.value)}
                      placeholder="docs, release, ui"
                    />
                  </label>
                </div>
                <label className="field">
                  <span>Description</span>
                  <textarea
                    value={newTaskDescription}
                    onChange={(event) => setNewTaskDescription(event.target.value)}
                    placeholder="Describe the outcome this task should deliver."
                    rows={4}
                  />
                </label>
                <div className="inspectorActions">
                  <button type="button" onClick={handleAddTask}>
                    Add task
                  </button>
                </div>
              </div>

              <div className="taskBoard">
                {TASK_STATUSES.map((statusItem) => {
                  const tasksForStatus = project.tasks.filter((task) => task.status === statusItem);

                  return (
                    <section
                      key={statusItem}
                      className={`taskColumn taskColumn-${TASK_STATUS_ACCENTS[statusItem]}`}
                    >
                      <header className="taskColumnHeader">
                        <div>
                          <strong>{statusItem}</strong>
                          <span>{tasksForStatus.length} task(s)</span>
                        </div>
                      </header>
                      <div className="taskColumnBody">
                        {tasksForStatus.map((task) => {
                          const assignedAgent =
                            project.agents.find((agent) => agent.id === task.assignedAgentID) ?? null;

                          return (
                            <article
                              key={task.id}
                              className={`taskCard ${selectedTaskId === task.id ? "taskCardSelected" : ""}`}
                              onClick={() => setSelectedTaskId(task.id)}
                            >
                              <div className="taskCardHeader">
                                <strong>{task.title}</strong>
                                <span className={`taskPriorityBadge taskPriority-${toClassToken(task.priority)}`}>
                                  {task.priority}
                                </span>
                              </div>
                              <p>{task.description || "No description yet."}</p>
                              <div className="taskMeta">
                                <span>{assignedAgent?.name ?? "Unassigned"}</span>
                                <span>{task.tags.length > 0 ? task.tags.join(", ") : "No tags"}</span>
                                <span>{task.workflowNodeID ? "Linked to workflow node" : "Manual task"}</span>
                              </div>
                              <div className="taskQuickActions">
                                <button
                                  type="button"
                                  onClick={(event) => {
                                    event.stopPropagation();
                                    handleTaskStatusChange(task.id, "To Do");
                                  }}
                                  disabled={task.status === "To Do"}
                                >
                                  Reset
                                </button>
                                <button
                                  type="button"
                                  onClick={(event) => {
                                    event.stopPropagation();
                                    handleTaskStatusChange(task.id, "In Progress");
                                  }}
                                  disabled={task.status === "In Progress"}
                                >
                                  Start
                                </button>
                                <button
                                  type="button"
                                  onClick={(event) => {
                                    event.stopPropagation();
                                    handleTaskStatusChange(task.id, "Blocked");
                                  }}
                                  disabled={task.status === "Blocked"}
                                >
                                  Block
                                </button>
                                <button
                                  type="button"
                                  onClick={(event) => {
                                    event.stopPropagation();
                                    handleTaskStatusChange(task.id, "Done");
                                  }}
                                  disabled={task.status === "Done"}
                                >
                                  Complete
                                </button>
                              </div>
                            </article>
                          );
                        })}
                        {tasksForStatus.length === 0 ? (
                          <p className="emptyState">No tasks in this column yet.</p>
                        ) : null}
                      </div>
                    </section>
                  );
                })}
              </div>

              <div className="formStack">
                <span className="sectionLabel">Selected task</span>
                {selectedTask ? (
                  <div className="inspectorCard">
                    <div className="inspectorGrid">
                      <label className="field">
                        <span>Title</span>
                        <input
                          value={selectedTask.title}
                          onChange={(event) =>
                            handleTaskUpdate(selectedTask.id, { title: event.target.value }, "Updated task title.")
                          }
                        />
                      </label>
                      <label className="field compactField">
                        <span>Status</span>
                        <select
                          value={selectedTask.status}
                          onChange={(event) =>
                            handleTaskStatusChange(selectedTask.id, event.target.value as TaskStatus)
                          }
                        >
                          {TASK_STATUSES.map((statusItem) => (
                            <option key={statusItem} value={statusItem}>
                              {statusItem}
                            </option>
                          ))}
                        </select>
                      </label>
                      <label className="field compactField">
                        <span>Priority</span>
                        <select
                          value={selectedTask.priority}
                          onChange={(event) =>
                            handleTaskUpdate(
                              selectedTask.id,
                              { priority: event.target.value as TaskPriority },
                              "Updated task priority."
                            )
                          }
                        >
                          {TASK_PRIORITIES.map((priority) => (
                            <option key={priority} value={priority}>
                              {priority}
                            </option>
                          ))}
                        </select>
                      </label>
                      <label className="field compactField">
                        <span>Assigned agent</span>
                        <select
                          value={selectedTask.assignedAgentID ?? ""}
                          onChange={(event) =>
                            handleTaskAssignmentChange(selectedTask.id, event.target.value || null)
                          }
                        >
                          <option value="">Unassigned</option>
                          {project.agents.map((agent) => (
                            <option key={agent.id} value={agent.id}>
                              {agent.name}
                            </option>
                          ))}
                        </select>
                      </label>
                      <label className="field compactField">
                        <span>Estimate (minutes)</span>
                        <input
                          type="number"
                          min="0"
                          value={selectedTask.estimatedDuration ? Math.round(selectedTask.estimatedDuration / 60) : ""}
                          onChange={(event) =>
                            handleTaskUpdate(
                              selectedTask.id,
                              {
                                estimatedDuration:
                                  event.target.value === ""
                                    ? null
                                    : Math.max(0, Number(event.target.value)) * 60
                              },
                              "Updated task estimate."
                            )
                          }
                        />
                      </label>
                      <label className="field">
                        <span>Tags</span>
                        <input
                          key={`${selectedTask.id}-tags`}
                          defaultValue={selectedTask.tags.join(", ")}
                          onBlur={(event) =>
                            handleTaskUpdate(
                              selectedTask.id,
                              { tags: parseTagInput(event.target.value) },
                              "Updated task tags."
                            )
                          }
                          placeholder="docs, release, ui"
                        />
                      </label>
                    </div>

                    <label className="field">
                      <span>Description</span>
                      <textarea
                        value={selectedTask.description}
                        onChange={(event) =>
                          handleTaskUpdate(
                            selectedTask.id,
                            { description: event.target.value },
                            "Updated task description."
                          )
                        }
                        rows={5}
                      />
                    </label>

                    <div className="taskTimeline">
                      <div>
                        <dt>Created</dt>
                        <dd>{formatDate(selectedTask.createdAt)}</dd>
                      </div>
                      <div>
                        <dt>Started</dt>
                        <dd>{formatDate(selectedTask.startedAt)}</dd>
                      </div>
                      <div>
                        <dt>Completed</dt>
                        <dd>{formatDate(selectedTask.completedAt)}</dd>
                      </div>
                      <div>
                        <dt>Actual duration</dt>
                        <dd>{formatDuration(selectedTask.actualDuration)}</dd>
                      </div>
                    </div>

                    <div className="inspectorActions">
                      <button type="button" onClick={() => handleTaskStatusChange(selectedTask.id, "In Progress")}>
                        Start
                      </button>
                      <button type="button" onClick={() => handleTaskStatusChange(selectedTask.id, "Done")}>
                        Mark done
                      </button>
                      <button type="button" onClick={() => handleTaskStatusChange(selectedTask.id, "Blocked")}>
                        Block
                      </button>
                      <button type="button" onClick={() => handleTaskStatusChange(selectedTask.id, "To Do")}>
                        Reset
                      </button>
                      <button
                        type="button"
                        className="dangerButton"
                        onClick={() => handleRemoveTask(selectedTask.id)}
                      >
                        Delete task
                      </button>
                    </div>
                  </div>
                ) : (
                  <p className="emptyState">Select a task card to edit details and lifecycle.</p>
                )}
              </div>
            </div>
          ) : (
            <p className="emptyState">Project state is still loading.</p>
          )}
        </article>

        <article className="card cardWide">
          <h2>Workbench conversation</h2>
          {project && activeWorkflow ? (
            <div className="formStack">
              <div className="metaStrip">
                <span>Workflow: {activeWorkflow.name}</span>
                <span>{project.openClaw.isConnected ? "OpenClaw connected" : "OpenClaw disconnected"}</span>
                <span>Entry agents: {executableEntryNodeIds.length}</span>
                <span>Pending approvals: {pendingApprovalMessages.length}</span>
                <span>Conversation messages: {workbenchMessages.length}</span>
              </div>

              <div className="workbenchLayout">
                <section className="workbenchConversationPanel">
                  <div className="dashboardPanelHeader">
                    <h3>Conversation</h3>
                    <span>{workbenchMessages.length} message(s)</span>
                  </div>
                  <div className="workbenchConversationList">
                    {workbenchMessages.length > 0 ? (
                      workbenchMessages.map((message) => {
                        const tone = resolveWorkbenchMessageTone(message);
                        const linkedTask =
                          project.tasks.find((task) => task.id === message.metadata.taskID) ?? null;
                        const fromAgent =
                          project.agents.find((agent) => agent.id === message.fromAgentID) ?? null;
                        const toAgent =
                          project.agents.find((agent) => agent.id === message.toAgentID) ?? null;
                        const approvalActionKey = `approval:${message.id}`;

                        return (
                          <article key={message.id} className={`workbenchBubble workbenchBubble-${tone}`}>
                            <div className="workbenchBubbleHeader">
                              <strong>
                                {tone === "user"
                                  ? "You"
                                  : message.metadata.sourceAgentName ??
                                    fromAgent?.name ??
                                    message.metadata.agentName ??
                                    "Workbench"}
                              </strong>
                              <span>{formatRelativeDate(message.timestamp)}</span>
                            </div>
                            <p>{message.content}</p>
                            <div className="taskMeta">
                              <span>Status {message.status}</span>
                              <span>
                                Route {(fromAgent?.name ?? "Workbench")} to {(toAgent?.name ?? "Workbench")}
                              </span>
                              <span>Task {linkedTask?.title ?? "Detached"}</span>
                            </div>
                            {message.status === "Waiting for Approval" ? (
                              <div className="taskQuickActions">
                                <button
                                  type="button"
                                  onClick={() => void handleWorkbenchApproval(message.id, "approve")}
                                  disabled={workbenchAction === approvalActionKey}
                                >
                                  {workbenchAction === approvalActionKey ? "Working..." : "Approve"}
                                </button>
                                <button
                                  type="button"
                                  className="dangerButton"
                                  onClick={() => void handleWorkbenchApproval(message.id, "reject")}
                                  disabled={workbenchAction === approvalActionKey}
                                >
                                  Reject
                                </button>
                              </div>
                            ) : null}
                          </article>
                        );
                      })
                    ) : (
                      <p className="emptyState">
                        Publish the first workbench task to capture a reusable cross-platform execution trail.
                      </p>
                    )}
                  </div>

                  <div className="workbenchComposer">
                    {workbenchError ? <p className="errorText">{workbenchError}</p> : null}
                    <label className="field">
                      <span>Prompt</span>
                      <textarea
                        value={workbenchPrompt}
                        onChange={(event) => setWorkbenchPrompt(event.target.value)}
                        rows={4}
                        placeholder="Describe the task for the active workflow, for example: investigate, break down, and propose an execution plan."
                      />
                    </label>
                    <div className="taskMeta">
                      <span>{hasExecutableWorkflow ? "Workflow entry is executable" : "Start node is not executable yet"}</span>
                      <span>{project.openClaw.isConnected ? "Ready to publish" : "Connect OpenClaw first"}</span>
                    </div>
                    <div className="inspectorActions">
                      <button
                        type="button"
                        onClick={() => void handlePublishWorkbenchPrompt()}
                        disabled={workbenchAction !== null}
                      >
                        {workbenchAction === "publish" ? "Publishing..." : "Publish to workflow"}
                      </button>
                    </div>
                  </div>
                </section>

                <section className="workbenchSidebar">
                  <div className="dashboardPanel">
                    <div className="dashboardPanelHeader">
                      <h3>Pending approvals</h3>
                      <span>{pendingApprovalMessages.length}</span>
                    </div>
                    {pendingApprovalMessages.length > 0 ? (
                      <div className="dashboardList">
                        {pendingApprovalMessages.map((message) => {
                          const approvalActionKey = `approval:${message.id}`;
                          return (
                            <article key={message.id} className="dashboardListItem">
                              <div className="dashboardListItemHeader">
                                <strong>{message.metadata.sourceAgentName ?? "Source agent"}</strong>
                                <span>{message.metadata.targetAgentName ?? "Target agent"}</span>
                              </div>
                              <p className="dashboardEventBody">{message.content}</p>
                              <p className="dashboardEventMeta">
                                Task {message.metadata.taskID?.slice(0, 8) ?? "unknown"} • Edge{" "}
                                {message.metadata.edgeID?.slice(0, 8) ?? "n/a"}
                              </p>
                              <div className="taskQuickActions">
                                <button
                                  type="button"
                                  onClick={() => void handleWorkbenchApproval(message.id, "approve")}
                                  disabled={workbenchAction === approvalActionKey}
                                >
                                  {workbenchAction === approvalActionKey ? "Working..." : "Approve"}
                                </button>
                                <button
                                  type="button"
                                  className="dangerButton"
                                  onClick={() => void handleWorkbenchApproval(message.id, "reject")}
                                  disabled={workbenchAction === approvalActionKey}
                                >
                                  Reject
                                </button>
                              </div>
                            </article>
                          );
                        })}
                      </div>
                    ) : (
                      <p className="emptyState">Approval-required routing will surface here for operator review.</p>
                    )}
                  </div>

                  <div className="dashboardPanel">
                    <div className="dashboardPanelHeader">
                      <h3>Execution receipts</h3>
                      <span>{workbenchExecutionResults.length}</span>
                    </div>
                    {workbenchExecutionResults.length > 0 ? (
                      <div className="dashboardList">
                        {workbenchExecutionResults.map((result) => {
                          const agent =
                            project.agents.find((candidate) => candidate.id === result.agentID) ?? null;
                          return (
                            <article key={result.id} className="dashboardListItem">
                              <div className="dashboardListItemHeader">
                                <strong>{agent?.name ?? result.agentID.slice(0, 8)}</strong>
                                <span>{result.status}</span>
                              </div>
                              <p className="dashboardEventMeta">
                                {formatRelativeDate(result.startedAt)} • Targets {result.routingTargets.length}
                              </p>
                              <p className="dashboardEventBody">{result.output || "No output captured."}</p>
                            </article>
                          );
                        })}
                      </div>
                    ) : (
                      <p className="emptyState">Execution receipts will appear here after workbench publishing.</p>
                    )}
                  </div>

                  <div className="dashboardPanel">
                    <div className="dashboardPanelHeader">
                      <h3>Workbench tasks</h3>
                      <span>{workbenchTasks.length}</span>
                    </div>
                    {workbenchTasks.length > 0 ? (
                      <div className="dashboardList">
                        {workbenchTasks.map((task) => (
                          <article key={task.id} className="dashboardListItem">
                            <div className="dashboardListItemHeader">
                              <strong>{task.title}</strong>
                              <span>{task.status}</span>
                            </div>
                            <div className="taskMeta">
                              <span>{task.priority}</span>
                              <span>{task.assignedAgentID ? "Assigned" : "Unassigned"}</span>
                              <span>{formatRelativeDate(task.createdAt)}</span>
                            </div>
                            <p className="dashboardEventMeta">
                              Workspace {task.metadata.workspaceRelativePath ?? "not indexed"}
                            </p>
                          </article>
                        ))}
                      </div>
                    ) : (
                      <p className="emptyState">Published workbench tasks will collect here.</p>
                    )}
                  </div>
                </section>
              </div>
            </div>
          ) : (
            <p className="emptyState">Open or create a project to use the workbench conversation flow.</p>
          )}
        </article>

        <article className="card">
          <h2>Recent projects</h2>
          {recentProjects.length > 0 ? (
            <div className="recentList">
              {recentProjects.map((entry) => (
                <button
                  key={entry.filePath}
                  type="button"
                  className="recentItem"
                  onClick={() => void handleOpenRecentProject(entry.filePath)}
                  disabled={busyAction !== null}
                >
                  <strong>{entry.name}</strong>
                  <span>{entry.filePath}</span>
                  <span>{entry.updatedAt}</span>
                </button>
              ))}
            </div>
          ) : (
            <p className="emptyState">No recent projects yet.</p>
          )}
        </article>

        <article className="card">
          <h2>Compatibility snapshot</h2>
          {project ? (
            <dl className="meta">
              <div>
                <dt>Default workflow</dt>
                <dd>{project.workflows[0]?.name ?? "None"}</dd>
              </div>
              <div>
                <dt>Agents</dt>
                <dd>{project.agents.length}</dd>
              </div>
              <div>
                <dt>Tasks</dt>
                <dd>{project.tasks.length}</dd>
              </div>
              <div>
                <dt>Platform</dt>
                <dd>{window.desktopApi?.platform ?? "browser"}</dd>
              </div>
            </dl>
          ) : (
            <p className="emptyState">Waiting for project bootstrap.</p>
          )}
        </article>

        <article className="card cardWide">
          <h2>Project configuration</h2>
          {project ? (
            <div className="formStack">
              <div className="inspectorCard">
                <span className="sectionLabel">Task data settings</span>
                <div className="inspectorGrid">
                  <label className="field">
                    <span>Workspace root path</span>
                    <input
                      value={project.taskData.workspaceRootPath ?? ""}
                      onChange={(event) =>
                        handleTaskDataSettingChange(
                          { workspaceRootPath: event.target.value },
                          "Updated task workspace root."
                        )
                      }
                      placeholder="Choose or paste a workspace root directory"
                    />
                  </label>
                  <label className="field compactField">
                    <span>Organization mode</span>
                    <select
                      value={project.taskData.organizationMode}
                      onChange={(event) =>
                        handleTaskDataSettingChange(
                          { organizationMode: event.target.value },
                          "Updated task organization mode."
                        )
                      }
                    >
                      <option value="project/task">project/task</option>
                      <option value="project/agent/task">project/agent/task</option>
                      <option value="flat">flat</option>
                    </select>
                  </label>
                </div>
                <div className="inspectorActions">
                  <button type="button" onClick={() => void handleChooseTaskWorkspaceRoot()}>
                    Choose folder
                  </button>
                  <button
                    type="button"
                    onClick={() =>
                      handleTaskDataSettingChange(
                        { workspaceRootPath: null },
                        "Reset task workspace root to project default."
                      )
                    }
                  >
                    Reset default
                  </button>
                </div>
                <div className="taskTimeline">
                  <div>
                    <dt>Last updated</dt>
                    <dd>{formatDate(project.taskData.lastUpdatedAt)}</dd>
                  </div>
                </div>
              </div>

              <div className="inspectorCard">
                <span className="sectionLabel">OpenClaw configuration</span>
                <div className="metaStrip">
                  <span>{project.openClaw.isConnected ? "Connected" : "Disconnected"}</span>
                  <span>Phase: {project.openClaw.connectionState.phase}</span>
                  <span>Available agents: {project.openClaw.availableAgents.length}</span>
                  <span>Active agents: {project.openClaw.activeAgents.length}</span>
                  <span>Detected agents: {project.openClaw.detectedAgents.length}</span>
                </div>
                <div className="inspectorGrid">
                  <label className="field compactField">
                    <span>Deployment kind</span>
                    <select
                      value={project.openClaw.config.deploymentKind}
                      onChange={(event) =>
                        handleOpenClawConfigChange(
                          { deploymentKind: event.target.value as OpenClawDeploymentKind },
                          "Updated OpenClaw deployment kind."
                        )
                      }
                    >
                      {OPENCLAW_DEPLOYMENT_KINDS.map((deploymentKind) => (
                        <option key={deploymentKind} value={deploymentKind}>
                          {deploymentKind}
                        </option>
                      ))}
                    </select>
                  </label>
                  {project.openClaw.config.deploymentKind === "local" ? (
                    <label className="field compactField">
                      <span>Local runtime ownership</span>
                      <input value="appManaged" readOnly />
                    </label>
                  ) : null}
                  <label className="field compactField">
                    <span>Host</span>
                    <input
                      value={project.openClaw.config.host}
                      onChange={(event) =>
                        handleOpenClawConfigChange({ host: event.target.value }, "Updated OpenClaw host.")
                      }
                    />
                  </label>
                  <label className="field compactField">
                    <span>Port</span>
                    <input
                      type="number"
                      min="1"
                      value={project.openClaw.config.port}
                      onChange={(event) =>
                        handleOpenClawConfigChange(
                          { port: Number(event.target.value) },
                          "Updated OpenClaw port."
                        )
                      }
                    />
                  </label>
                  <label className="field compactField">
                    <span>Default agent</span>
                    <input
                      value={project.openClaw.config.defaultAgent}
                      onChange={(event) =>
                        handleOpenClawConfigChange(
                          { defaultAgent: event.target.value },
                          "Updated OpenClaw default agent."
                        )
                      }
                    />
                  </label>
                  <label className="field compactField">
                    <span>Timeout (seconds)</span>
                    <input
                      type="number"
                      min="1"
                      value={project.openClaw.config.timeout}
                      onChange={(event) =>
                        handleOpenClawConfigChange(
                          { timeout: Number(event.target.value) },
                          "Updated OpenClaw timeout."
                        )
                      }
                    />
                  </label>
                  <label className="field compactField">
                    <span>CLI log level</span>
                    <select
                      value={project.openClaw.config.cliLogLevel}
                      onChange={(event) =>
                        handleOpenClawConfigChange(
                          { cliLogLevel: event.target.value as OpenClawCLILogLevel },
                          "Updated OpenClaw CLI log level."
                        )
                      }
                    >
                      {OPENCLAW_CLI_LOG_LEVELS.map((level) => (
                        <option key={level} value={level}>
                          {level}
                        </option>
                      ))}
                    </select>
                  </label>
                  <label className="field">
                    <span>API key</span>
                    <input
                      value={project.openClaw.config.apiKey}
                      onChange={(event) =>
                        handleOpenClawConfigChange({ apiKey: event.target.value }, "Updated OpenClaw API key.")
                      }
                      placeholder="Optional for remote deployment"
                    />
                  </label>
                  <label className="checkboxField">
                    <input
                      type="checkbox"
                      checked={project.openClaw.config.useSSL}
                      onChange={(event) =>
                        handleOpenClawConfigChange({ useSSL: event.target.checked }, "Updated SSL setting.")
                      }
                    />
                    <span>Use SSL</span>
                  </label>
                  <label className="checkboxField">
                    <input
                      type="checkbox"
                      checked={project.openClaw.config.autoConnect}
                      onChange={(event) =>
                        handleOpenClawConfigChange(
                          { autoConnect: event.target.checked },
                          "Updated auto-connect setting."
                        )
                      }
                    />
                    <span>Auto-connect on launch</span>
                  </label>
                  <label className="checkboxField">
                    <input
                      type="checkbox"
                      checked={project.openClaw.config.cliQuietMode}
                      onChange={(event) =>
                        handleOpenClawConfigChange(
                          { cliQuietMode: event.target.checked },
                          "Updated CLI quiet mode."
                        )
                      }
                    />
                    <span>CLI quiet mode</span>
                  </label>
                </div>

                <div className="inspectorGrid">
                  <label className="field compactField">
                    <span>Container engine</span>
                    <input
                      value={project.openClaw.config.container.engine}
                      onChange={(event) =>
                        handleOpenClawConfigChange(
                          { container: { engine: event.target.value } },
                          "Updated container engine."
                        )
                      }
                    />
                  </label>
                  <label className="field compactField">
                    <span>Container name</span>
                    <input
                      value={project.openClaw.config.container.containerName}
                      onChange={(event) =>
                        handleOpenClawConfigChange(
                          { container: { containerName: event.target.value } },
                          "Updated container name."
                        )
                      }
                    />
                  </label>
                  <label className="field">
                    <span>Workspace mount path</span>
                    <input
                      value={project.openClaw.config.container.workspaceMountPath}
                      onChange={(event) =>
                        handleOpenClawConfigChange(
                          { container: { workspaceMountPath: event.target.value } },
                          "Updated container workspace mount path."
                        )
                      }
                    />
                  </label>
                </div>

                <div className="inspectorGrid">
                  <label className="field">
                    <span>Session backup path</span>
                    <input
                      value={project.openClaw.sessionBackupPath ?? ""}
                      onChange={(event) =>
                        handleOpenClawPathChange(
                          { sessionBackupPath: event.target.value },
                          "Updated OpenClaw backup path."
                        )
                      }
                      placeholder="Folder containing backup artifacts"
                    />
                  </label>
                  <label className="field">
                    <span>Session mirror path</span>
                    <input
                      value={project.openClaw.sessionMirrorPath ?? ""}
                      onChange={(event) =>
                        handleOpenClawPathChange(
                          { sessionMirrorPath: event.target.value },
                          "Updated OpenClaw mirror path."
                        )
                      }
                      placeholder="Folder mirroring external sessions"
                    />
                  </label>
                </div>

                <div className="inspectorActions">
                  <button
                    type="button"
                    onClick={() => void handleDetectOpenClawAgents()}
                    disabled={openClawAction !== null}
                  >
                    {openClawAction === "detect" ? "Detecting..." : "Detect agents"}
                  </button>
                  <button
                    type="button"
                    onClick={() => void handleConnectOpenClaw()}
                    disabled={openClawAction !== null}
                  >
                    {openClawAction === "connect" ? "Connecting..." : "Connect"}
                  </button>
                  <button
                    type="button"
                    onClick={() => void handleDisconnectOpenClaw()}
                    disabled={openClawAction !== null || !project.openClaw.isConnected}
                  >
                    {openClawAction === "disconnect" ? "Disconnecting..." : "Disconnect"}
                  </button>
                  <button
                    type="button"
                    onClick={() => handleImportDetectedAgents()}
                    disabled={openClawAction !== null || project.openClaw.detectedAgents.length === 0}
                  >
                    {openClawAction === "import" ? "Importing..." : "Import all detected"}
                  </button>
                  <button type="button" onClick={() => void handleChooseOpenClawSessionPath("backup")}>
                    Choose backup folder
                  </button>
                  <button type="button" onClick={() => void handleChooseOpenClawSessionPath("mirror")}>
                    Choose mirror folder
                  </button>
                  <button
                    type="button"
                    onClick={() =>
                      handleOpenClawPathChange(
                        { sessionBackupPath: null, sessionMirrorPath: null },
                        "Cleared OpenClaw session paths."
                      )
                    }
                  >
                    Clear session paths
                  </button>
                </div>

                {openClawRuntimeReadiness ? (
                  <div className="dashboardPanel">
                    <div className="dashboardPanelHeader">
                      <h3>OpenClaw connection diagnostics</h3>
                      <span>{openClawRuntimeReadiness.label}</span>
                    </div>
                    <div className="metaStrip">
                      <span>Phase: {project.openClaw.connectionState.phase}</span>
                      <span>
                        Last probe:{" "}
                        {project.openClaw.connectionState.health.lastProbeAt
                          ? fromSwiftDate(project.openClaw.connectionState.health.lastProbeAt).toLocaleString()
                          : "Never"}
                      </span>
                      <span>
                        Layers:{" "}
                        {openClawRuntimeReadiness.layers
                          ? formatOpenClawRuntimeLayers(openClawRuntimeReadiness.layers)
                          : "Not probed"}
                      </span>
                    </div>
                    <p className="dashboardEventBody">{openClawRuntimeReadiness.summary}</p>
                    {openClawRuntimeReadiness.recoveryActions.some((action) => action.command !== "review_config") ? (
                      <div className="inspectorActions">
                        <button
                          type="button"
                          onClick={() => void handleRunOpenClawRecoveryPlan()}
                          disabled={openClawAction !== null}
                        >
                          {openClawAction === "recover" ? "Recovering..." : "Run recovery plan"}
                        </button>
                      </div>
                    ) : null}
                    {openClawRuntimeReadiness.recoveryActions.length > 0 ? (
                      <div className="dashboardChecklist">
                        {openClawRuntimeReadiness.recoveryActions.map((action) => (
                          <div key={action.id} className="dashboardChecklistItem">
                            <strong>{action.title}</strong>
                            <span>{action.detail}</span>
                            <button
                              type="button"
                              onClick={() => handleRunOpenClawRecoveryAction(action.command)}
                              disabled={openClawAction !== null && action.command !== "review_config"}
                            >
                              {action.command === "connect"
                                ? openClawAction === "connect"
                                  ? "Connecting..."
                                  : "Run Connect"
                                : action.command === "detect"
                                  ? openClawAction === "detect"
                                    ? "Detecting..."
                                    : "Run Detect"
                                  : "Review config"}
                            </button>
                          </div>
                        ))}
                      </div>
                    ) : null}
                    {openClawRuntimeReadiness.advisoryMessages.length > 0 ? (
                      <div className="dashboardChecklist">
                        {openClawRuntimeReadiness.advisoryMessages.map((message) => (
                          <div key={message} className="dashboardChecklistItem">
                            <strong>Advisory</strong>
                            <span>{message}</span>
                          </div>
                        ))}
                      </div>
                    ) : null}
                    {openClawLastRecoveryReport ? (
                      <div className="dashboardChecklist">
                        <div className="dashboardChecklistItem">
                          <strong>Last recovery</strong>
                          <span>{openClawLastRecoveryReport.summary}</span>
                        </div>
                        <div className="dashboardChecklistItem">
                          <strong>Before</strong>
                          <span>
                            {openClawLastRecoveryReport.before.label} • {openClawLastRecoveryReport.before.layers}
                          </span>
                        </div>
                        <div className="dashboardChecklistItem">
                          <strong>After</strong>
                          <span>
                            {openClawLastRecoveryReport.after.label} • {openClawLastRecoveryReport.after.layers}
                          </span>
                        </div>
                        {openClawLastRecoveryReport.findings.map((finding) => (
                          <div key={finding} className="dashboardChecklistItem">
                            <strong>Change</strong>
                            <span>{finding}</span>
                          </div>
                        ))}
                      </div>
                    ) : null}
                  </div>
                ) : null}

                <div className="dashboardPanel">
                  <div className="dashboardPanelHeader">
                    <h3>OpenClaw runtime governance</h3>
                    <span>
                      {openClawGovernanceReport ? new Date(openClawGovernanceReport.auditedAt).toLocaleString() : "Not audited"}
                    </span>
                  </div>
                  <div className="metaStrip">
                    <span>
                      {openClawGovernanceReport
                        ? `${openClawGovernanceReport.summary.fail} fail / ${openClawGovernanceReport.summary.unknown} unknown / ${openClawGovernanceReport.summary.pass} pass`
                        : "Run an audit to inspect the embedded OpenClaw runtime."}
                    </span>
                    <span>
                      {openClawGovernanceReport
                        ? `${openClawGovernanceReport.proposedActions.filter((action) => action.safeToAutoApply).length} safe fix(es)`
                        : "Safe fixes unavailable until audit"}
                    </span>
                    <span>
                      {openClawGovernanceReport
                        ? `${openClawGovernanceSelectedActionIds.length} selected for remediation`
                        : "Nothing selected yet"}
                    </span>
                    <span>
                      {openClawGovernanceReport
                        ? `${openClawGovernanceReport.residualRisks.length} residual risk note(s)`
                        : "Residual risks unavailable until audit"}
                    </span>
                  </div>
                  <div className="inspectorActions">
                    <button
                      type="button"
                      onClick={() => void handleAuditOpenClawRuntimeGovernance()}
                      disabled={openClawGovernanceAction !== null}
                    >
                      {openClawGovernanceAction === "audit" ? "Auditing..." : "Run runtime audit"}
                    </button>
                    <button
                      type="button"
                      onClick={() => void handleRemediateOpenClawRuntimeGovernance()}
                      disabled={
                        openClawGovernanceAction !== null ||
                        openClawGovernanceSelectedActionIds.length === 0
                      }
                    >
                      {openClawGovernanceAction === "remediate" ? "Applying..." : "Apply selected fixes"}
                    </button>
                  </div>
                  {openClawGovernanceReport ? (
                    <div className="dashboardList">
                      {openClawGovernanceReport.findings.map((finding) => (
                        <article key={finding.id} className="dashboardListItem">
                          <div className="dashboardListItemHeader">
                            <strong>{finding.title}</strong>
                            <span>{finding.status.toUpperCase()}</span>
                          </div>
                          <p className="dashboardEventBody">{finding.summary}</p>
                          <div className="taskMeta">
                            <span>{finding.severity}</span>
                            <span>{finding.remediable ? "Auto-remediable" : "Report only"}</span>
                            <span>
                              {finding.remediationActionIds.length > 0
                                ? `Actions: ${finding.remediationActionIds.join(", ")}`
                                : "No automatic fix"}
                            </span>
                          </div>
                          {finding.evidence.length > 0 ? (
                            <p className="dashboardEventMeta">{finding.evidence.join(" | ")}</p>
                          ) : null}
                        </article>
                      ))}
                    </div>
                  ) : (
                    <p className="emptyState">
                      The first release of this tool audits high-risk session tools, subagent allowlists, exec approvals,
                      and elevated execution, then applies safe fixes for local OpenClaw deployments.
                    </p>
                  )}
                  {openClawGovernanceReport?.proposedActions.length ? (
                    <div className="dashboardList">
                      {openClawGovernanceReport.proposedActions.map((action) => {
                        const checked = openClawGovernanceSelectedActionIds.includes(action.id);
                        return (
                          <article key={action.id} className="dashboardListItem">
                            <label className="taskMeta">
                              <input
                                type="checkbox"
                                checked={checked}
                                disabled={!action.safeToAutoApply || openClawGovernanceAction !== null}
                                onChange={(event) =>
                                  handleToggleOpenClawGovernanceAction(action.id, event.currentTarget.checked)
                                }
                              />
                              <strong>{action.title}</strong>
                              <span>{action.safeToAutoApply ? "Safe to auto-apply" : "Manual only"}</span>
                              <span>{action.kind}</span>
                            </label>
                            <p className="dashboardEventBody">{action.description}</p>
                            <p className="dashboardEventMeta">
                              {action.targetPath ? `Target: ${action.targetPath}` : "Target: runtime operation"}
                              {" | "}
                              {action.requiresSandboxRecreate ? "Requires sandbox recreate" : "No sandbox recreate required"}
                            </p>
                          </article>
                        );
                      })}
                      <div className="inspectorActions">
                        <button
                          type="button"
                          onClick={() => handleSelectAllOpenClawGovernanceActions()}
                          disabled={openClawGovernanceAction !== null}
                        >
                          Select all safe fixes
                        </button>
                        <button
                          type="button"
                          onClick={() => handleClearOpenClawGovernanceActions()}
                          disabled={openClawGovernanceAction !== null || openClawGovernanceSelectedActionIds.length === 0}
                        >
                          Clear selection
                        </button>
                      </div>
                    </div>
                  ) : null}
                  {openClawGovernanceNotes.length > 0 ? (
                    <p className="dashboardEventBody">{openClawGovernanceNotes.join(" ")}</p>
                  ) : null}
                  {openClawGovernanceLastRemediation ? (
                    <div className="dashboardList">
                      <article className="dashboardListItem">
                        <div className="dashboardListItemHeader">
                          <strong>Latest remediation outcome</strong>
                          <span>POST-CHECK</span>
                        </div>
                        <div className="taskMeta">
                          <span>
                            {openClawGovernanceLastRemediation.appliedActionTitles.length > 0
                              ? `Applied: ${openClawGovernanceLastRemediation.appliedActionTitles.join(" | ")}`
                              : "Applied: none"}
                          </span>
                        </div>
                        <p className="dashboardEventMeta">
                          {openClawGovernanceLastRemediation.skippedActionTitles.length > 0
                            ? `Skipped: ${openClawGovernanceLastRemediation.skippedActionTitles.join(" | ")}`
                            : "Skipped: none"}
                        </p>
                        <p className="dashboardEventMeta">
                          {openClawGovernanceLastRemediation.fixedFindingTitles.length > 0
                            ? `Fixed findings: ${openClawGovernanceLastRemediation.fixedFindingTitles.join(" | ")}`
                            : "Fixed findings: none in this run"}
                        </p>
                        <p className="dashboardEventMeta">
                          {openClawGovernanceLastRemediation.remainingFailTitles.length > 0
                            ? `Remaining fails: ${openClawGovernanceLastRemediation.remainingFailTitles.join(" | ")}`
                            : "Remaining fails: none"}
                        </p>
                        <p className="dashboardEventMeta">
                          {openClawGovernanceLastRemediation.remainingUnknownTitles.length > 0
                            ? `Remaining unknowns: ${openClawGovernanceLastRemediation.remainingUnknownTitles.join(" | ")}`
                            : "Remaining unknowns: none"}
                        </p>
                      </article>
                    </div>
                  ) : null}
                  {openClawGovernanceBackupPaths.length > 0 ? (
                    <p className="dashboardEventMeta">Backups: {openClawGovernanceBackupPaths.join(" | ")}</p>
                  ) : null}
                  {openClawGovernanceReport?.residualRisks.length ? (
                    <p className="dashboardEventMeta">
                      Residual risks: {openClawGovernanceReport.residualRisks.join(" | ")}
                    </p>
                  ) : null}
                </div>

                <div className="dashboardPanel">
                  <div className="dashboardPanelHeader">
                    <h3>Detected OpenClaw agents</h3>
                    <span>{project.openClaw.detectedAgents.length} detected</span>
                  </div>
                  {project.openClaw.detectedAgents.length > 0 ? (
                    <div className="dashboardList">
                      {project.openClaw.detectedAgents.map((record) => {
                        const alreadyImported = importedOpenClawAgentKeys.has(record.name.trim().toLowerCase());
                        return (
                          <article key={record.id} className="dashboardListItem">
                            <div className="dashboardListItemHeader">
                              <strong>{record.name}</strong>
                              <span>{alreadyImported ? "Imported" : "Not imported"}</span>
                            </div>
                            <div className="taskMeta">
                              <span>{record.directoryValidated ? "Workspace verified" : "Workspace missing"}</span>
                              <span>{record.configValidated ? "Config matched" : "Config missing"}</span>
                              <span>{record.workspacePath ? "Workspace path found" : "No workspace path"}</span>
                            </div>
                            <p className="dashboardEventMeta">
                              {record.directoryPath ?? record.workspacePath ?? "No local directory resolved"}
                            </p>
                            {record.issues.length > 0 ? (
                              <p className="dashboardEventBody">{record.issues.join(" ")}</p>
                            ) : (
                              <p className="dashboardEventBody">
                                Detection looks healthy. This agent is ready to be imported into the project.
                              </p>
                            )}
                            <div className="taskQuickActions">
                              <button
                                type="button"
                                onClick={() => handleImportDetectedAgents([record.id])}
                                disabled={openClawAction !== null || alreadyImported}
                              >
                                {alreadyImported ? "Already imported" : "Import"}
                              </button>
                            </div>
                          </article>
                        );
                      })}
                    </div>
                  ) : (
                    <p className="emptyState">
                      Run Detect agents to scan the configured OpenClaw environment and surface import candidates.
                    </p>
                  )}
                </div>

                <div className="taskTimeline">
                  <div>
                    <dt>Last synced</dt>
                    <dd>{formatDate(project.openClaw.lastSyncedAt)}</dd>
                  </div>
                </div>
              </div>
            </div>
          ) : (
            <p className="emptyState">Project state is still loading.</p>
          )}
        </article>

        <article className="card cardWide">
          <h2>Operations dashboard</h2>
          {project ? (
            <div className="formStack">
              <div className="dashboardGrid">
                <article className="dashboardMetricCard">
                  <span className="dashboardMetricLabel">Task health</span>
                  <strong>{formatPercent(taskCompletionRate)}</strong>
                  <p>
                    {project.tasks.length} total tasks, {inProgressTaskCount} in progress, {blockedTaskCount} blocked.
                  </p>
                </article>
                <article className="dashboardMetricCard">
                  <span className="dashboardMetricLabel">Execution reliability</span>
                  <strong>{executionSuccessRate == null ? "No runs" : formatPercent(executionSuccessRate)}</strong>
                  <p>
                    {completedExecutionCount} completed, {failedExecutionCount} failed, {errorLogCount} error logs.
                  </p>
                </article>
                <article className="dashboardMetricCard">
                  <span className="dashboardMetricLabel">OpenClaw readiness</span>
                  <strong>{openClawRuntimeReadiness?.label ?? openClawReadiness?.label ?? "Unavailable"}</strong>
                  <p>
                    Score {openClawReadiness ? formatPercent(openClawReadiness.score) : "0%"}.
                    {openClawRuntimeReadiness
                      ? ` ${openClawRuntimeReadiness.summary}`
                      : openClawReadiness?.issues[0]
                        ? ` ${openClawReadiness.issues[0]}`
                        : " Configuration looks complete."}
                  </p>
                </article>
                <article className="dashboardMetricCard">
                  <span className="dashboardMetricLabel">Runtime posture</span>
                  <strong>{formatRelativeDate(project.runtimeState.lastUpdated)}</strong>
                  <p>
                    Queue {project.runtimeState.messageQueue.length}, approvals {pendingApprovalCount}, workspaces{" "}
                    {project.workspaceIndex.length}.
                  </p>
                </article>
              </div>

              <div className="dashboardColumns">
                <section className="dashboardPanel">
                  <div className="dashboardPanelHeader">
                    <h3>Agent load</h3>
                    <span>{agentLoadRows.length} agent(s)</span>
                  </div>
                  {agentLoadRows.length > 0 ? (
                    <div className="dashboardList">
                      {agentLoadRows.map((row) => (
                        <article key={row.agent.id} className="dashboardListItem">
                          <div className="dashboardListItemHeader">
                            <strong>{row.agent.name}</strong>
                            <span>{row.totalTasks} task(s)</span>
                          </div>
                          <div className="taskMeta">
                            <span>Active {row.activeTasks}</span>
                            <span>Blocked {row.blockedTasks}</span>
                            <span>Done {row.completedTasks}</span>
                            <span>Workflow-linked {row.workflowTasks}</span>
                          </div>
                        </article>
                      ))}
                    </div>
                  ) : (
                    <p className="emptyState">Add agents to start tracking task ownership and load.</p>
                  )}
                </section>

                <section className="dashboardPanel">
                  <div className="dashboardPanelHeader">
                    <h3>Workflow coverage</h3>
                    <span>{workflowCoverageRows.length} workflow(s)</span>
                  </div>
                  {workflowCoverageRows.length > 0 ? (
                    <div className="dashboardList">
                      {workflowCoverageRows.map((row) => (
                        <article key={row.workflow.id} className="dashboardListItem">
                          <div className="dashboardListItemHeader">
                            <strong>{row.workflow.name}</strong>
                            <span>{formatPercent(row.coverage)}</span>
                          </div>
                          <div className="taskMeta">
                            <span>Agent nodes {row.agentNodeCount}</span>
                            <span>Assigned {row.assignedNodeCount}</span>
                            <span>Linked tasks {row.linkedTasks}</span>
                          </div>
                        </article>
                      ))}
                    </div>
                  ) : (
                    <p className="emptyState">No workflows yet. Add one to start monitoring routing coverage.</p>
                  )}
                </section>
              </div>

              <div className="dashboardColumns">
                <section className="dashboardPanel">
                  <div className="dashboardPanelHeader">
                    <h3>Recent execution</h3>
                    <span>{recentExecutionResults.length} recent result(s)</span>
                  </div>
                  {recentExecutionResults.length > 0 ? (
                    <div className="dashboardList">
                      {recentExecutionResults.map((result) => {
                        const agent =
                          project.agents.find((candidate) => candidate.id === result.agentID) ?? null;
                        return (
                          <article key={result.id} className="dashboardListItem">
                            <div className="dashboardListItemHeader">
                              <strong>{agent?.name ?? result.agentID.slice(0, 8)}</strong>
                              <span>{result.status}</span>
                            </div>
                            <p className="dashboardEventMeta">
                              {formatRelativeDate(result.startedAt)} • Duration {formatDuration(result.duration)} •
                              Targets {result.routingTargets.length}
                            </p>
                            <p className="dashboardEventBody">{result.output || "No output captured."}</p>
                          </article>
                        );
                      })}
                    </div>
                  ) : (
                    <p className="emptyState">Execution results will show up after runtime activity is saved.</p>
                  )}
                </section>

                <section className="dashboardPanel">
                  <div className="dashboardPanelHeader">
                    <h3>Recent events</h3>
                    <span>
                      {project.executionLogs.length} logs, {project.messages.length} messages
                    </span>
                  </div>
                  <div className="dashboardSignalStrip">
                    <span>Error logs {errorLogCount}</span>
                    <span>Warnings {warnLogCount}</span>
                    <span>Failed messages {failedMessageCount}</span>
                    <span>Linked tasks {taskLinkedToWorkflowCount}</span>
                    <span>Backups {project.memoryData.taskExecutionMemories.length}</span>
                  </div>
                  {recentExecutionLogs.length > 0 ? (
                    <div className="dashboardList">
                      {recentExecutionLogs.map((entry) => (
                        <article key={entry.id} className="dashboardListItem">
                          <div className="dashboardListItemHeader">
                            <strong>{entry.level}</strong>
                            <span>{formatRelativeDate(entry.timestamp)}</span>
                          </div>
                          <p className="dashboardEventBody">{entry.message}</p>
                          <p className="dashboardEventMeta">
                            Node {entry.nodeID ? entry.nodeID.slice(0, 8) : "global"} • Session{" "}
                            {project.runtimeState.sessionID.slice(0, 8)}
                          </p>
                        </article>
                      ))}
                    </div>
                  ) : (
                    <p className="emptyState">Execution logs and runtime alerts will appear here.</p>
                  )}
                </section>
              </div>

              {openClawReadiness && openClawReadiness.issues.length > 0 ? (
                <section className="dashboardPanel">
                  <div className="dashboardPanelHeader">
                    <h3>OpenClaw readiness checklist</h3>
                    <span>{openClawReadiness.issues.length} item(s)</span>
                  </div>
                  <div className="dashboardChecklist">
                    {openClawReadiness.issues.map((issue) => (
                      <div key={issue} className="dashboardChecklistItem">
                        <strong>Attention</strong>
                        <span>{issue}</span>
                      </div>
                    ))}
                  </div>
                </section>
              ) : null}

              {openClawRuntimeReadiness && openClawRuntimeReadiness.advisoryMessages.length > 0 ? (
                <section className="dashboardPanel">
                  <div className="dashboardPanelHeader">
                    <h3>OpenClaw runtime advisories</h3>
                    <span>{openClawRuntimeReadiness.advisoryMessages.length} item(s)</span>
                  </div>
                  <div className="dashboardChecklist">
                    {openClawRuntimeReadiness.advisoryMessages.map((message) => (
                      <div key={message} className="dashboardChecklistItem">
                        <strong>Advisory</strong>
                        <span>{message}</span>
                      </div>
                    ))}
                  </div>
                </section>
              ) : null}

              {openClawRuntimeReadiness && openClawRuntimeReadiness.recoveryActions.length > 0 ? (
                <section className="dashboardPanel">
                  <div className="dashboardPanelHeader">
                    <h3>OpenClaw recovery plan</h3>
                    <span>{openClawRuntimeReadiness.recoveryActions.length} step(s)</span>
                  </div>
                  <div className="dashboardChecklist">
                    {openClawRuntimeReadiness.recoveryActions.map((action) => (
                      <div key={action.id} className="dashboardChecklistItem">
                        <strong>{action.title}</strong>
                        <span>{action.detail}</span>
                      </div>
                    ))}
                  </div>
                </section>
              ) : null}

              {openClawRetryGuidance ? (
                <section className="dashboardPanel">
                  <div className="dashboardPanelHeader">
                    <h3>Retry guidance</h3>
                    <span>{openClawRetryGuidance.recommendation.replaceAll("_", " ")}</span>
                  </div>
                  <p className="dashboardEventBody">{openClawRetryGuidance.detail}</p>
                  {openClawRetryPolicy ? (
                    <>
                      <p className="dashboardEventMeta">
                        Policy: {openClawRetryPolicy.status} • Budget remaining {openClawRetryPolicy.retryBudgetRemaining}/
                        {openClawRetryPolicy.maxRetryBudget}
                        {openClawRetryPolicy.cooldownRemainingMs > 0
                          ? ` • Cooldown ${Math.ceil(openClawRetryPolicy.cooldownRemainingMs / 1000)}s`
                          : ""}
                      </p>
                      <p className="dashboardEventMeta">{openClawRetryPolicy.detail}</p>
                      {openClawRetryPolicy.plannedCommands.length > 0 ? (
                        <div className="inspectorActions">
                          <button
                            type="button"
                            onClick={() => void handleRunOpenClawSmartRetry()}
                            disabled={!openClawRetryPolicy.canAutoRetry || !openClawRetryPolicy.immediate || openClawAction !== null}
                          >
                            {openClawAction === "recover" ? "Recovering..." : "Run smart retry"}
                          </button>
                        </div>
                      ) : null}
                    </>
                  ) : null}
                  {openClawRetryGuidance.suggestedCommands.length > 0 ? (
                    <p className="dashboardEventMeta">
                      Suggested automatic steps: {openClawRetryGuidance.suggestedCommands.join(" -> ")}
                    </p>
                  ) : null}
                  {openClawRetryGuidance.rationale.length > 0 ? (
                    <div className="dashboardChecklist">
                      {openClawRetryGuidance.rationale.map((reason) => (
                        <div key={reason} className="dashboardChecklistItem">
                          <strong>Reason</strong>
                          <span>{reason}</span>
                        </div>
                      ))}
                    </div>
                  ) : null}
                </section>
              ) : null}

              {openClawRecoveryReports.length > 0 ? (
                <section className="dashboardPanel">
                  <div className="dashboardPanelHeader">
                    <h3>Recovery audit</h3>
                    <span>{openClawRecoveryReports.length} report(s)</span>
                  </div>
                  <div className="dashboardSignalStrip">
                    <span>Completed {openClawRecoveryAudit.summary.completed}</span>
                    <span>Partial {openClawRecoveryAudit.summary.partial}</span>
                    <span>Manual {openClawRecoveryAudit.summary.manualFollowUp}</span>
                    <span>Failed {openClawRecoveryAudit.summary.failed}</span>
                    <span>Improved {openClawRecoveryAudit.summary.improved}</span>
                    <span>Reached ready {openClawRecoveryAudit.summary.reachedReady}</span>
                  </div>
                  <div className="dashboardList">
                    {openClawRecoveryAudit.timeline.map((report) => (
                      <article key={`${report.createdAt}-${report.summary}`} className="dashboardListItem">
                        <div className="dashboardListItemHeader">
                          <strong>{formatOpenClawRecoveryStatus(report.status)}</strong>
                          <span>{fromSwiftDate(report.createdAt).toLocaleString()}</span>
                        </div>
                        <p className="dashboardEventBody">{report.summary}</p>
                        <p className="dashboardEventMeta">
                          {`${report.before.label} -> ${report.after.label}`} • {report.after.layers}
                        </p>
                        {report.completedSteps.length > 0 ? (
                          <p className="dashboardEventMeta">Completed steps: {report.completedSteps.join(" -> ")}</p>
                        ) : null}
                        {report.manualSteps.length > 0 ? (
                          <p className="dashboardEventMeta">Manual follow-up: {report.manualSteps.join(" | ")}</p>
                        ) : null}
                        {report.findings.length > 0 ? (
                          <div className="dashboardChecklist">
                            {report.findings.slice(0, 3).map((finding) => (
                              <div key={finding} className="dashboardChecklistItem">
                                <strong>Finding</strong>
                                <span>{finding}</span>
                              </div>
                            ))}
                          </div>
                        ) : null}
                      </article>
                    ))}
                  </div>
                </section>
              ) : null}
            </div>
          ) : (
            <p className="emptyState">Project state is still loading.</p>
          )}
        </article>

        <article className="card cardWide">
          <h2>Project JSON preview</h2>
          {project ? (
            <pre className="jsonPreview">{JSON.stringify(project, null, 2)}</pre>
          ) : (
            <p className="emptyState">Waiting for project bootstrap.</p>
          )}
        </article>
      </section>
    </main>
  );
}
