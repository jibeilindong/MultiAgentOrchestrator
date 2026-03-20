import type {
  Agent,
  ExecutionLogEntry,
  ExecutionLogLevel,
  ExecutionOutputType,
  ExecutionResult,
  ExecutionStatus,
  MAProject,
  Message,
  MessageStatus,
  MessageType,
  ProjectTaskDataSettings,
  ProjectWorkspaceRecord,
  Task,
  TaskStatus,
  Workflow,
  WorkflowEdge,
  WorkflowNode
} from "@multi-agent-flow/domain";
import { toSwiftDate } from "./swift-date";
import { createUUID } from "./uuid";

export interface WorkbenchPublishResult {
  project: MAProject;
  taskId: string;
  pendingApprovalCount: number;
  completedNodeCount: number;
}

export interface WorkbenchApprovalResult {
  project: MAProject;
  taskId: string | null;
  pendingApprovalCount: number;
  completedNodeCount: number;
}

export interface WorkbenchRealEntryExecution {
  entryNodeId: string;
  agentId: string;
  agentIdentifier: string;
  success: boolean;
  output: string;
  outputType: ExecutionOutputType;
  engineMessage?: string | null;
  rawStdout?: string;
  rawStderr?: string;
}

export interface WorkbenchLiveNodeExecution {
  nodeId: string;
  agentId: string;
  agentIdentifier: string;
  success: boolean;
  output: string;
  outputType: ExecutionOutputType;
  routingAction?: string | null;
  routingTargets?: string[];
  routingReason?: string | null;
  engineMessage?: string | null;
  rawStdout?: string;
  rawStderr?: string;
}

export interface WorkbenchLiveApprovalCheckpoint {
  edgeId: string;
  sourceNodeId: string;
  targetNodeId: string;
}

function sanitizePathSegment(value: string): string {
  const normalized = value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return normalized || "item";
}

function uniqueNodeList(nodes: WorkflowNode[]): WorkflowNode[] {
  const seen = new Set<string>();
  return nodes.filter((node) => {
    if (seen.has(node.id)) {
      return false;
    }
    seen.add(node.id);
    return true;
  });
}

function sortNodes(nodes: WorkflowNode[]): WorkflowNode[] {
  return [...nodes].sort((left, right) => {
    if (left.position.y !== right.position.y) {
      return left.position.y - right.position.y;
    }
    if (left.position.x !== right.position.x) {
      return left.position.x - right.position.x;
    }
    return left.title.localeCompare(right.title);
  });
}

function sortEdges(workflow: Workflow): WorkflowEdge[] {
  const nodeMap = new Map(workflow.nodes.map((node) => [node.id, node] as const));
  return [...workflow.edges].sort((left, right) => {
    const leftTarget = nodeMap.get(left.toNodeID);
    const rightTarget = nodeMap.get(right.toNodeID);
    if (leftTarget && rightTarget) {
      if (leftTarget.position.y !== rightTarget.position.y) {
        return leftTarget.position.y - rightTarget.position.y;
      }
      if (leftTarget.position.x !== rightTarget.position.x) {
        return leftTarget.position.x - rightTarget.position.x;
      }
    }
    return left.id.localeCompare(right.id);
  });
}

function summarizePrompt(prompt: string): string {
  const firstLine = prompt.split(/\r?\n/, 1)[0]?.trim() ?? "";
  if (!firstLine) {
    return "Workbench Task";
  }
  return firstLine.length > 40 ? `${firstLine.slice(0, 40).trimEnd()}...` : firstLine;
}

function parseMetadataList(value: string | undefined): string[] {
  if (!value) {
    return [];
  }

  return value
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function serializeMetadataList(values: Iterable<string>): string {
  return Array.from(new Set(Array.from(values).map((value) => value.trim()).filter(Boolean))).join(",");
}

function updateTaskLifecycle(task: Task, status: TaskStatus): Task {
  if (task.status === status) {
    return task;
  }

  const now = toSwiftDate();
  switch (status) {
    case "To Do":
      return {
        ...task,
        status,
        startedAt: null,
        completedAt: null,
        actualDuration: null
      };
    case "In Progress":
      return {
        ...task,
        status,
        startedAt: task.startedAt ?? now,
        completedAt: null,
        actualDuration: null
      };
    case "Done": {
      const startedAt = task.startedAt ?? now;
      const completedAt = now;
      return {
        ...task,
        status,
        startedAt,
        completedAt,
        actualDuration: Math.max(0, Math.round(completedAt - startedAt))
      };
    }
    case "Blocked":
      return {
        ...task,
        status,
        startedAt: task.startedAt ?? now,
        completedAt: null,
        actualDuration: null
      };
  }
}

function createMessageRecord(input: {
  fromAgentID: string;
  toAgentID: string;
  type: MessageType;
  content: string;
  status: MessageStatus;
  requiresApproval?: boolean;
  metadata?: Record<string, string>;
}): Message {
  return {
    id: createUUID(),
    fromAgentID: input.fromAgentID,
    toAgentID: input.toAgentID,
    type: input.type,
    content: input.content,
    timestamp: toSwiftDate(),
    status: input.status,
    metadata: input.metadata ?? {},
    requiresApproval: input.requiresApproval ?? false,
    approvedBy: null,
    approvalTimestamp: null
  };
}

function createExecutionLog(level: ExecutionLogLevel, message: string, nodeID?: string | null): ExecutionLogEntry {
  return {
    id: createUUID(),
    timestamp: toSwiftDate(),
    level,
    message,
    nodeID: nodeID ?? null
  };
}

function createExecutionResult(input: {
  nodeID: string;
  agentID: string;
  status: ExecutionStatus;
  output: string;
  outputType: ExecutionOutputType;
  routingAction?: string | null;
  routingTargets?: string[];
  routingReason?: string | null;
}): ExecutionResult {
  const startedAt = toSwiftDate();
  const completedAt = input.status === "Completed" || input.status === "Failed" ? toSwiftDate() : null;
  return {
    id: createUUID(),
    nodeID: input.nodeID,
    agentID: input.agentID,
    status: input.status,
    output: input.output,
    outputType: input.outputType,
    routingAction: input.routingAction ?? null,
    routingTargets: input.routingTargets ?? [],
    routingReason: input.routingReason ?? null,
    startedAt,
    completedAt,
    duration: completedAt == null ? null : Math.max(0, Math.round(completedAt - startedAt))
  };
}

function createTaskRecord(input: {
  title: string;
  description: string;
  assignedAgentID: string | null;
  workflowNodeID: string | null;
  workflowID: string;
  prompt: string;
  tags: string[];
}): Task {
  const now = toSwiftDate();
  const task: Task = {
    id: createUUID(),
    title: input.title.trim() || "Workbench Task",
    description: input.description.trim(),
    status: "In Progress",
    priority: "High",
    assignedAgentID: input.assignedAgentID,
    workflowNodeID: input.workflowNodeID,
    createdBy: null,
    createdAt: now,
    startedAt: now,
    completedAt: null,
    estimatedDuration: null,
    actualDuration: null,
    tags: Array.from(new Set(input.tags.map((tag) => tag.trim()).filter(Boolean))),
    metadata: {
      source: "workbench",
      workflowID: input.workflowID,
      prompt: input.prompt,
      completedNodeIDs: "",
      pendingApprovalMessageIDs: ""
    }
  };
  return task;
}

function createWorkspaceRecord(
  project: MAProject,
  task: Task,
  leadAgent: Agent | null,
  settings: ProjectTaskDataSettings
): ProjectWorkspaceRecord | null {
  if (!settings.workspaceRootPath) {
    return null;
  }

  const projectSegment = sanitizePathSegment(project.name);
  const agentSegment = sanitizePathSegment(leadAgent?.name ?? "unassigned");
  const taskSegment = sanitizePathSegment(task.title);
  const suffix = task.id.slice(0, 8);

  let workspaceRelativePath = `${projectSegment}/${taskSegment}-${suffix}`;
  if (settings.organizationMode === "project/agent/task") {
    workspaceRelativePath = `${projectSegment}/${agentSegment}/${taskSegment}-${suffix}`;
  } else if (settings.organizationMode === "flat") {
    workspaceRelativePath = `${taskSegment}-${suffix}`;
  }

  const now = toSwiftDate();
  return {
    id: createUUID(),
    taskID: task.id,
    workspaceRelativePath,
    workspaceName: task.title,
    createdAt: now,
    updatedAt: now
  };
}

function resolveEntryAgentNodes(project: MAProject, workflow: Workflow): WorkflowNode[] {
  const nodeMap = new Map(workflow.nodes.map((node) => [node.id, node] as const));
  const startNodeIds = new Set(workflow.nodes.filter((node) => node.type === "start").map((node) => node.id));
  const candidates = sortEdges(workflow)
    .filter((edge) => startNodeIds.has(edge.fromNodeID))
    .map((edge) => nodeMap.get(edge.toNodeID))
    .filter((node): node is WorkflowNode => Boolean(node && node.type === "agent" && node.agentID))
    .filter((node) => project.agents.some((agent) => agent.id === node.agentID));

  const uniqueCandidates = sortNodes(uniqueNodeList(candidates));
  if (workflow.fallbackRoutingPolicy === "all_available") {
    return uniqueCandidates;
  }
  return uniqueCandidates.slice(0, 1);
}

function synthesizeExecutionOutput(agent: Agent, node: WorkflowNode, prompt: string, workflowName: string): string {
  const cleanPrompt = prompt.trim();
  const nodeTitle = node.title.trim() || agent.name;
  const excerpt = cleanPrompt.length > 160 ? `${cleanPrompt.slice(0, 160).trimEnd()}...` : cleanPrompt;
  return [
    `${agent.name} accepted the workbench task in workflow "${workflowName}".`,
    `Node: ${nodeTitle}.`,
    excerpt ? `Prompt: ${excerpt}` : "Prompt captured from the workbench input.",
    "This desktop shell has recorded the dispatch, downstream routing, and execution receipt so the project can be reviewed and handed off across platforms."
  ].join(" ");
}

function executeWorkflowNodes(
  project: MAProject,
  workflow: Workflow,
  task: Task,
  startNodes: WorkflowNode[],
  completedNodeIDs: Set<string>
): {
  messages: Message[];
  executionLogs: ExecutionLogEntry[];
  executionResults: ExecutionResult[];
  completedNodeIDs: Set<string>;
  pendingApprovalMessageIDs: string[];
  agentStates: Record<string, string>;
  hadFailure: boolean;
} {
  const nodeMap = new Map(workflow.nodes.map((node) => [node.id, node] as const));
  const agentMap = new Map(project.agents.map((agent) => [agent.id, agent] as const));
  const outgoingEdgeMap = new Map<string, WorkflowEdge[]>();
  for (const edge of sortEdges(workflow)) {
    const currentEdges = outgoingEdgeMap.get(edge.fromNodeID) ?? [];
    currentEdges.push(edge);
    outgoingEdgeMap.set(edge.fromNodeID, currentEdges);
  }

  const messages: Message[] = [];
  const executionLogs: ExecutionLogEntry[] = [];
  const executionResults: ExecutionResult[] = [];
  const pendingApprovalMessageIDs: string[] = [];
  const agentStates: Record<string, string> = {};
  const queue = sortNodes(uniqueNodeList(startNodes));
  let hadFailure = false;

  while (queue.length > 0) {
    const node = queue.shift();
    if (!node || completedNodeIDs.has(node.id)) {
      continue;
    }

    if (!node.agentID) {
      executionLogs.push(createExecutionLog("ERROR", `Node ${node.title || node.id} has no assigned agent.`, node.id));
      hadFailure = true;
      continue;
    }

    const agent = agentMap.get(node.agentID);
    if (!agent) {
      executionLogs.push(createExecutionLog("ERROR", `Agent ${node.agentID} was not found in the project.`, node.id));
      hadFailure = true;
      continue;
    }

    const output = synthesizeExecutionOutput(agent, node, task.metadata.prompt ?? task.description, workflow.name);
    const result = createExecutionResult({
      nodeID: node.id,
      agentID: agent.id,
      status: "Completed",
      output,
      outputType: "agent_final_response",
      routingAction: "dispatch",
      routingTargets: [],
      routingReason: `task:${task.id}`
    });
    executionResults.push(result);
    completedNodeIDs.add(node.id);
    agentStates[agent.id] = "completed";

    messages.push(
      createMessageRecord({
        fromAgentID: agent.id,
        toAgentID: agent.id,
        type: "Notification",
        content: output,
        status: "Delivered",
        metadata: {
          channel: "workbench",
          role: "assistant",
          kind: "output",
          workflowID: workflow.id,
          taskID: task.id,
          nodeID: node.id,
          agentName: agent.name,
          outputType: "agent_final_response"
        }
      })
    );
    executionLogs.push(createExecutionLog("SUCCESS", `${agent.name} completed node ${node.title || agent.name}.`, node.id));

    const outgoingEdges = outgoingEdgeMap.get(node.id) ?? [];
    const selectedEdges =
      workflow.fallbackRoutingPolicy === "all_available" ? outgoingEdges : outgoingEdges.slice(0, 1);

    for (const edge of selectedEdges) {
      const targetNode = nodeMap.get(edge.toNodeID);
      if (!targetNode?.agentID) {
        executionLogs.push(
          createExecutionLog("WARN", `Skipping edge ${edge.id.slice(0, 8)} because its target is not an executable agent node.`, node.id)
        );
        continue;
      }

      const targetAgent = agentMap.get(targetNode.agentID);
      if (!targetAgent) {
        executionLogs.push(
          createExecutionLog("WARN", `Skipping edge ${edge.id.slice(0, 8)} because agent ${targetNode.agentID} is missing.`, node.id)
        );
        continue;
      }

      if (edge.requiresApproval) {
        const approvalMessage = createMessageRecord({
          fromAgentID: agent.id,
          toAgentID: targetAgent.id,
          type: "Notification",
          content: `Approval required before routing from ${agent.name} to ${targetAgent.name}.`,
          status: "Waiting for Approval",
          requiresApproval: true,
          metadata: {
            channel: "workbench",
            role: "system",
            kind: "approval",
            workflowID: workflow.id,
            taskID: task.id,
            edgeID: edge.id,
            sourceNodeID: node.id,
            targetNodeID: targetNode.id,
            sourceAgentName: agent.name,
            targetAgentName: targetAgent.name
          }
        });
        messages.push(approvalMessage);
        pendingApprovalMessageIDs.push(approvalMessage.id);
        agentStates[targetAgent.id] = "waiting_approval";
        executionLogs.push(
          createExecutionLog("WARN", `Routing from ${agent.name} to ${targetAgent.name} is waiting for approval.`, targetNode.id)
        );
        continue;
      }

      messages.push(
        createMessageRecord({
          fromAgentID: agent.id,
          toAgentID: targetAgent.id,
          type: "Notification",
          content: `Task routed from ${agent.name} to ${targetAgent.name}.`,
          status: "Delivered",
          metadata: {
            channel: "workbench",
            role: "system",
            kind: "handoff",
            workflowID: workflow.id,
            taskID: task.id,
            edgeID: edge.id,
            sourceNodeID: node.id,
            targetNodeID: targetNode.id,
            sourceAgentName: agent.name,
            targetAgentName: targetAgent.name
          }
        })
      );
      executionLogs.push(
        createExecutionLog("INFO", `Queued downstream node ${targetNode.title || targetAgent.name} from ${agent.name}.`, targetNode.id)
      );
      if (!completedNodeIDs.has(targetNode.id)) {
        queue.push(targetNode);
      }
    }
  }

  return {
    messages,
    executionLogs,
    executionResults,
    completedNodeIDs,
    pendingApprovalMessageIDs,
    agentStates,
    hadFailure
  };
}

function createWorkbenchTaskSeed(
  project: MAProject,
  workflow: Workflow,
  prompt: string,
  leadAgent: Agent,
  entryNode: WorkflowNode
) {
  const task = createTaskRecord({
    title: summarizePrompt(prompt),
    description: prompt,
    assignedAgentID: leadAgent.id,
    workflowNodeID: entryNode.id,
    workflowID: workflow.id,
    prompt,
    tags: ["workbench", workflow.name]
  });
  const workspaceRecord = createWorkspaceRecord(project, task, leadAgent, project.taskData);
  const workbenchSessionID = `workbench-${project.runtimeState.sessionID}-${workflow.id}-${leadAgent.id}`;
  task.metadata.workbenchSessionID = workbenchSessionID;
  task.metadata.entryNodeIDs = entryNode.id;
  task.metadata.entryAgentIDs = leadAgent.id;
  if (workspaceRecord) {
    task.metadata.workspaceRelativePath = workspaceRecord.workspaceRelativePath;
  }

  const userMessage = createMessageRecord({
    fromAgentID: leadAgent.id,
    toAgentID: leadAgent.id,
    type: "Task",
    content: prompt,
    status: "Read",
    metadata: {
      channel: "workbench",
      role: "user",
      kind: "input",
      workflowID: workflow.id,
      taskID: task.id,
      workbenchSessionID
    }
  });

  return {
    task,
    workspaceRecord,
    workbenchSessionID,
    userMessage
  };
}

export function publishWorkbenchPromptWithLiveExecution(
  project: MAProject,
  workflowId: string,
  prompt: string,
  executions: WorkbenchLiveNodeExecution[],
  approvalCheckpoints: WorkbenchLiveApprovalCheckpoint[] = []
): WorkbenchPublishResult {
  const workflow = project.workflows.find((item) => item.id === workflowId);
  const trimmedPrompt = prompt.trim();
  const firstExecution = executions[0];
  if (!workflow || !trimmedPrompt || !firstExecution) {
    return {
      project,
      taskId: "",
      pendingApprovalCount: 0,
      completedNodeCount: 0
    };
  }

  const entryNode = workflow.nodes.find((node) => node.id === firstExecution.nodeId);
  const leadAgent = project.agents.find((agent) => agent.id === firstExecution.agentId) ?? null;
  if (!entryNode || !leadAgent) {
    return {
      project,
      taskId: "",
      pendingApprovalCount: 0,
      completedNodeCount: 0
    };
  }

  const { task, workspaceRecord, userMessage } = createWorkbenchTaskSeed(
    project,
    workflow,
    trimmedPrompt,
    leadAgent,
    entryNode
  );
  task.metadata.liveExecution = "true";
  task.metadata.liveAgentIdentifier = firstExecution.agentIdentifier;

  const nodeMap = new Map(workflow.nodes.map((node) => [node.id, node] as const));
  const agentMap = new Map(project.agents.map((agent) => [agent.id, agent] as const));
  const completedNodeIDs = new Set<string>();
  const executionLogs: ExecutionLogEntry[] = [
    createExecutionLog("INFO", `Workbench published task "${task.title}" to workflow ${workflow.name}.`)
  ];
  const executionResults: ExecutionResult[] = [];
  const messages: Message[] = [userMessage];
  const pendingApprovalMessageIDs: string[] = [];
  const runtimeAgentStates: Record<string, string> = {};
  let hadFailure = false;

  for (const execution of executions) {
    const node = nodeMap.get(execution.nodeId);
    const agent = agentMap.get(execution.agentId);
    if (!node || !agent) {
      hadFailure = true;
      executionLogs.push(
        createExecutionLog("ERROR", `Skipped a live execution receipt because node or agent metadata was missing.`, execution.nodeId)
      );
      continue;
    }

    const visibleOutput =
      execution.output.trim() || execution.engineMessage?.trim() || "OpenClaw returned no visible output.";
    const result = createExecutionResult({
      nodeID: node.id,
      agentID: agent.id,
      status: execution.success ? "Completed" : "Failed",
      output: visibleOutput,
      outputType: execution.outputType,
      routingAction: execution.routingAction ?? null,
      routingTargets: execution.routingTargets ?? [],
      routingReason: execution.routingReason ?? execution.engineMessage ?? null
    });
    executionResults.push(result);

    messages.push(
      createMessageRecord({
        fromAgentID: agent.id,
        toAgentID: agent.id,
        type: execution.success ? "Notification" : "Data",
        content: visibleOutput,
        status: execution.success ? "Delivered" : "Failed",
        metadata: {
          channel: "workbench",
          role: "assistant",
          kind: "output",
          workflowID: workflow.id,
          taskID: task.id,
          nodeID: node.id,
          agentName: agent.name,
          outputType: execution.outputType,
          liveExecution: "true",
          liveAgentIdentifier: execution.agentIdentifier
        }
      })
    );

    executionLogs.push(
      createExecutionLog(
        execution.success ? "SUCCESS" : "ERROR",
        execution.success
          ? `OpenClaw executed ${agent.name} (${execution.agentIdentifier}) for node ${node.title || agent.name}.`
          : `OpenClaw failed while executing ${agent.name} (${execution.agentIdentifier}) for node ${node.title || agent.name}.`,
        node.id
      )
    );

    if (execution.routingAction || (execution.routingTargets?.length ?? 0) > 0) {
      executionLogs.push(
        createExecutionLog(
          "INFO",
          `Routing decision: ${execution.routingAction ?? "selected"}${
            execution.routingTargets && execution.routingTargets.length > 0
              ? ` -> ${execution.routingTargets.join(", ")}`
              : ""
          }${execution.routingReason ? ` (${execution.routingReason})` : ""}`,
          node.id
        )
      );
    }

    if (execution.engineMessage?.trim()) {
      executionLogs.push(createExecutionLog(execution.success ? "INFO" : "ERROR", execution.engineMessage.trim(), node.id));
    }
    if (execution.rawStderr?.trim()) {
      executionLogs.push(createExecutionLog("WARN", execution.rawStderr.trim(), node.id));
    }

    if (execution.success) {
      completedNodeIDs.add(node.id);
      runtimeAgentStates[agent.id] = "completed";
    } else {
      hadFailure = true;
      runtimeAgentStates[agent.id] = "failed";
    }
  }

  for (const checkpoint of approvalCheckpoints) {
    const sourceNode = nodeMap.get(checkpoint.sourceNodeId);
    const targetNode = nodeMap.get(checkpoint.targetNodeId);
    const sourceAgent = sourceNode?.agentID ? agentMap.get(sourceNode.agentID) : null;
    const targetAgent = targetNode?.agentID ? agentMap.get(targetNode.agentID) : null;
    if (!sourceNode || !targetNode || !sourceAgent || !targetAgent) {
      continue;
    }

    const approvalMessage = createMessageRecord({
      fromAgentID: sourceAgent.id,
      toAgentID: targetAgent.id,
      type: "Notification",
      content: `Approval required before routing from ${sourceAgent.name} to ${targetAgent.name}.`,
      status: "Waiting for Approval",
      requiresApproval: true,
      metadata: {
        channel: "workbench",
        role: "system",
        kind: "approval",
        workflowID: workflow.id,
        taskID: task.id,
        edgeID: checkpoint.edgeId,
        sourceNodeID: sourceNode.id,
        targetNodeID: targetNode.id,
        sourceAgentName: sourceAgent.name,
        targetAgentName: targetAgent.name,
        liveExecution: "true"
      }
    });
    messages.push(approvalMessage);
    pendingApprovalMessageIDs.push(approvalMessage.id);
    runtimeAgentStates[targetAgent.id] = "waiting_approval";
    executionLogs.push(
      createExecutionLog("WARN", `Routing from ${sourceAgent.name} to ${targetAgent.name} is waiting for approval.`, targetNode.id)
    );
  }

  task.metadata.completedNodeIDs = serializeMetadataList(completedNodeIDs);
  task.metadata.pendingApprovalMessageIDs = serializeMetadataList(pendingApprovalMessageIDs);
  task.metadata.lastWorkbenchRunAt = String(toSwiftDate());

  const finalTask = updateTaskLifecycle(
    task,
    hadFailure || pendingApprovalMessageIDs.length > 0 ? "Blocked" : "Done"
  );

  const nextWorkspaceIndex =
    workspaceRecord == null ? project.workspaceIndex : [...project.workspaceIndex, workspaceRecord];
  const nextMemoryData =
    workspaceRecord == null
      ? project.memoryData
      : {
          ...project.memoryData,
          taskExecutionMemories: [
            ...project.memoryData.taskExecutionMemories,
            {
              id: createUUID(),
              taskID: finalTask.id,
              workspaceRelativePath: workspaceRecord.workspaceRelativePath,
              backupLabel: hadFailure
                ? "live-run-failed"
                : pendingApprovalMessageIDs.length > 0
                  ? "live-run-awaiting-approval"
                  : "live-run",
              lastCapturedAt: toSwiftDate()
            }
          ],
          lastBackupAt: toSwiftDate()
        };

  return {
    project: {
      ...project,
      tasks: [...project.tasks, finalTask],
      messages: [...project.messages, ...messages],
      executionLogs: [...project.executionLogs, ...executionLogs],
      executionResults: [...project.executionResults, ...executionResults],
      workspaceIndex: nextWorkspaceIndex,
      memoryData: nextMemoryData,
      runtimeState: {
        ...project.runtimeState,
        messageQueue: Array.from(new Set([...project.runtimeState.messageQueue, ...pendingApprovalMessageIDs])),
        agentStates: {
          ...project.runtimeState.agentStates,
          ...runtimeAgentStates
        },
        lastUpdated: toSwiftDate()
      },
      updatedAt: toSwiftDate()
    },
    taskId: finalTask.id,
    pendingApprovalCount: pendingApprovalMessageIDs.length,
    completedNodeCount: completedNodeIDs.size
  };
}

export function publishWorkbenchPromptWithRealEntryExecution(
  project: MAProject,
  workflowId: string,
  prompt: string,
  execution: WorkbenchRealEntryExecution
): WorkbenchPublishResult {
  return publishWorkbenchPromptWithLiveExecution(project, workflowId, prompt, [
    {
      nodeId: execution.entryNodeId,
      agentId: execution.agentId,
      agentIdentifier: execution.agentIdentifier,
      success: execution.success,
      output: execution.output,
      outputType: execution.outputType,
      routingAction: execution.success ? "live_entry" : "live_entry_failed",
      routingTargets: [],
      routingReason: execution.engineMessage ?? null,
      engineMessage: execution.engineMessage,
      rawStdout: execution.rawStdout,
      rawStderr: execution.rawStderr
    }
  ]);
}

export function publishWorkbenchPrompt(
  project: MAProject,
  workflowId: string,
  prompt: string
): WorkbenchPublishResult {
  const workflow = project.workflows.find((item) => item.id === workflowId);
  const trimmedPrompt = prompt.trim();
  if (!workflow || !trimmedPrompt) {
    return {
      project,
      taskId: "",
      pendingApprovalCount: 0,
      completedNodeCount: 0
    };
  }

  const entryNodes = resolveEntryAgentNodes(project, workflow);
  if (entryNodes.length === 0) {
    return {
      project,
      taskId: "",
      pendingApprovalCount: 0,
      completedNodeCount: 0
    };
  }

  const leadAgent = project.agents.find((agent) => agent.id === entryNodes[0]?.agentID) ?? null;
  const task = createTaskRecord({
    title: summarizePrompt(trimmedPrompt),
    description: trimmedPrompt,
    assignedAgentID: leadAgent?.id ?? null,
    workflowNodeID: entryNodes[0]?.id ?? null,
    workflowID: workflow.id,
    prompt: trimmedPrompt,
    tags: ["workbench", workflow.name]
  });
  const workspaceRecord = createWorkspaceRecord(project, task, leadAgent, project.taskData);
  const workbenchSessionID = `workbench-${project.runtimeState.sessionID}-${workflow.id}-${leadAgent?.id ?? "entry"}`;
  task.metadata.workbenchSessionID = workbenchSessionID;
  task.metadata.entryNodeIDs = serializeMetadataList(entryNodes.map((node) => node.id));
  task.metadata.entryAgentIDs = serializeMetadataList(entryNodes.map((node) => node.agentID ?? "").filter(Boolean));
  if (workspaceRecord) {
    task.metadata.workspaceRelativePath = workspaceRecord.workspaceRelativePath;
  }

  const userMessage = createMessageRecord({
    fromAgentID: leadAgent?.id ?? entryNodes[0].agentID ?? "",
    toAgentID: leadAgent?.id ?? entryNodes[0].agentID ?? "",
    type: "Task",
    content: trimmedPrompt,
    status: "Read",
    metadata: {
      channel: "workbench",
      role: "user",
      kind: "input",
      workflowID: workflow.id,
      taskID: task.id,
      workbenchSessionID
    }
  });

  const initialLogs = [
    createExecutionLog("INFO", `Workbench published task "${task.title}" to workflow ${workflow.name}.`),
    createExecutionLog(
      "INFO",
      `Entry routing resolved to ${entryNodes.length} agent node(s): ${entryNodes
        .map((node) => project.agents.find((agent) => agent.id === node.agentID)?.name ?? node.title)
        .join(", ")}.`
    )
  ];

  const execution = executeWorkflowNodes(project, workflow, task, entryNodes, new Set<string>());
  task.metadata.completedNodeIDs = serializeMetadataList(execution.completedNodeIDs);
  task.metadata.pendingApprovalMessageIDs = serializeMetadataList(execution.pendingApprovalMessageIDs);
  task.metadata.lastWorkbenchRunAt = String(toSwiftDate());

  const finalTask = updateTaskLifecycle(
    task,
    execution.hadFailure || execution.pendingApprovalMessageIDs.length > 0 ? "Blocked" : "Done"
  );

  const nextWorkspaceIndex =
    workspaceRecord == null ? project.workspaceIndex : [...project.workspaceIndex, workspaceRecord];
  const nextMemoryData =
    workspaceRecord == null
      ? project.memoryData
      : {
          ...project.memoryData,
          taskExecutionMemories: [
            ...project.memoryData.taskExecutionMemories,
            {
              id: createUUID(),
              taskID: finalTask.id,
              workspaceRelativePath: workspaceRecord.workspaceRelativePath,
              backupLabel: execution.pendingApprovalMessageIDs.length > 0 ? "awaiting-approval" : "latest-run",
              lastCapturedAt: toSwiftDate()
            }
          ],
          lastBackupAt: toSwiftDate()
        };

  const nextProject: MAProject = {
    ...project,
    tasks: [...project.tasks, finalTask],
    messages: [...project.messages, userMessage, ...execution.messages],
    executionLogs: [...project.executionLogs, ...initialLogs, ...execution.executionLogs],
    executionResults: [...project.executionResults, ...execution.executionResults],
    workspaceIndex: nextWorkspaceIndex,
    memoryData: nextMemoryData,
    runtimeState: {
      ...project.runtimeState,
      messageQueue: Array.from(
        new Set([...project.runtimeState.messageQueue, ...execution.pendingApprovalMessageIDs])
      ),
      agentStates: {
        ...project.runtimeState.agentStates,
        ...(leadAgent ? { [leadAgent.id]: execution.pendingApprovalMessageIDs.length > 0 ? "blocked" : "completed" } : {}),
        ...execution.agentStates
      },
      lastUpdated: toSwiftDate()
    },
    updatedAt: toSwiftDate()
  };

  return {
    project: nextProject,
    taskId: finalTask.id,
    pendingApprovalCount: execution.pendingApprovalMessageIDs.length,
    completedNodeCount: execution.completedNodeIDs.size
  };
}

export function reviewWorkbenchApproval(
  project: MAProject,
  messageId: string,
  decision: "approve" | "reject"
): WorkbenchApprovalResult {
  const approvalMessage = project.messages.find((message) => message.id === messageId);
  if (!approvalMessage || approvalMessage.status !== "Waiting for Approval") {
    return {
      project,
      taskId: null,
      pendingApprovalCount: 0,
      completedNodeCount: 0
    };
  }

  const workflowId = approvalMessage.metadata.workflowID;
  const taskId = approvalMessage.metadata.taskID;
  const targetNodeId = approvalMessage.metadata.targetNodeID;
  const workflow = project.workflows.find((item) => item.id === workflowId);
  const task = project.tasks.find((item) => item.id === taskId);
  if (!workflow || !task || !targetNodeId) {
    return {
      project,
      taskId: taskId ?? null,
      pendingApprovalCount: 0,
      completedNodeCount: parseMetadataList(task?.metadata.completedNodeIDs).length
    };
  }

  const updatedMessages: Message[] = project.messages.map((message) => {
    if (message.id !== messageId) {
      return message;
    }

    return {
      ...message,
      status: (decision === "approve" ? "Approved" : "Rejected") as MessageStatus,
      approvedBy: "operator",
      approvalTimestamp: toSwiftDate(),
      timestamp: toSwiftDate()
    };
  });

  const completedNodeIDs = new Set(parseMetadataList(task.metadata.completedNodeIDs));
  const pendingApprovalMessageIDs = new Set(parseMetadataList(task.metadata.pendingApprovalMessageIDs));
  pendingApprovalMessageIDs.delete(messageId);
  const runtimeQueue = new Set(project.runtimeState.messageQueue);
  runtimeQueue.delete(messageId);

  const taskIndex = project.tasks.findIndex((item) => item.id === task.id);
  const nextLogs = [
    createExecutionLog(
      decision === "approve" ? "SUCCESS" : "WARN",
      decision === "approve"
        ? `Approved routing request ${messageId.slice(0, 8)} for task ${task.title}.`
        : `Rejected routing request ${messageId.slice(0, 8)} for task ${task.title}.`,
      targetNodeId
    )
  ];

  let additionalMessages: Message[] = [];
  let additionalLogs: ExecutionLogEntry[] = [];
  let additionalResults: ExecutionResult[] = [];
  let additionalAgentStates: Record<string, string> = {};
  let hadFailure = false;

  if (decision === "approve") {
    const targetNode = workflow.nodes.find((node) => node.id === targetNodeId);
    if (targetNode) {
      const execution = executeWorkflowNodes(project, workflow, task, [targetNode], completedNodeIDs);
      additionalMessages = execution.messages;
      additionalLogs = execution.executionLogs;
      additionalResults = execution.executionResults;
      additionalAgentStates = execution.agentStates;
      hadFailure = execution.hadFailure;
      for (const id of execution.pendingApprovalMessageIDs) {
        pendingApprovalMessageIDs.add(id);
        runtimeQueue.add(id);
      }
    }
  }

  const nextTask = {
    ...task,
    metadata: {
      ...task.metadata,
      completedNodeIDs: serializeMetadataList(completedNodeIDs),
      pendingApprovalMessageIDs: serializeMetadataList(pendingApprovalMessageIDs),
      lastWorkbenchRunAt: String(toSwiftDate())
    }
  };
  const finalTask = updateTaskLifecycle(
    nextTask,
    decision === "reject" || hadFailure || pendingApprovalMessageIDs.size > 0 ? "Blocked" : "Done"
  );

  const nextTasks = [...project.tasks];
  nextTasks[taskIndex] = finalTask;

  const nextProject: MAProject = {
    ...project,
    tasks: nextTasks,
    messages: [...updatedMessages, ...additionalMessages],
    executionLogs: [...project.executionLogs, ...nextLogs, ...additionalLogs],
    executionResults: [...project.executionResults, ...additionalResults],
    runtimeState: {
      ...project.runtimeState,
      messageQueue: Array.from(runtimeQueue),
      agentStates: {
        ...project.runtimeState.agentStates,
        ...additionalAgentStates
      },
      lastUpdated: toSwiftDate()
    },
    updatedAt: toSwiftDate()
  };

  return {
    project: nextProject,
    taskId: finalTask.id,
    pendingApprovalCount: pendingApprovalMessageIDs.size,
    completedNodeCount: completedNodeIDs.size
  };
}

export function reviewWorkbenchApprovalWithLiveExecution(
  project: MAProject,
  messageId: string,
  decision: "approve" | "reject",
  executions: WorkbenchLiveNodeExecution[] = [],
  approvalCheckpoints: WorkbenchLiveApprovalCheckpoint[] = []
): WorkbenchApprovalResult {
  if (decision === "reject") {
    return reviewWorkbenchApproval(project, messageId, decision);
  }

  const approvalMessage = project.messages.find((message) => message.id === messageId);
  if (!approvalMessage || approvalMessage.status !== "Waiting for Approval") {
    return {
      project,
      taskId: null,
      pendingApprovalCount: 0,
      completedNodeCount: 0
    };
  }

  const workflowId = approvalMessage.metadata.workflowID;
  const taskId = approvalMessage.metadata.taskID;
  const workflow = project.workflows.find((item) => item.id === workflowId);
  const task = project.tasks.find((item) => item.id === taskId);
  if (!workflow || !task) {
    return {
      project,
      taskId: taskId ?? null,
      pendingApprovalCount: 0,
      completedNodeCount: 0
    };
  }

  const updatedMessages: Message[] = project.messages.map((message) => {
    if (message.id !== messageId) {
      return message;
    }

    return {
      ...message,
      status: "Approved",
      approvedBy: "operator",
      approvalTimestamp: toSwiftDate(),
      timestamp: toSwiftDate()
    };
  });

  const nodeMap = new Map(workflow.nodes.map((node) => [node.id, node] as const));
  const agentMap = new Map(project.agents.map((agent) => [agent.id, agent] as const));
  const completedNodeIDs = new Set(parseMetadataList(task.metadata.completedNodeIDs));
  const pendingApprovalMessageIDs = new Set(parseMetadataList(task.metadata.pendingApprovalMessageIDs));
  pendingApprovalMessageIDs.delete(messageId);
  const runtimeQueue = new Set(project.runtimeState.messageQueue);
  runtimeQueue.delete(messageId);
  const runtimeAgentStates: Record<string, string> = {};

  const taskIndex = project.tasks.findIndex((item) => item.id === task.id);
  const executionLogs: ExecutionLogEntry[] = [
    createExecutionLog("SUCCESS", `Approved routing request ${messageId.slice(0, 8)} for task ${task.title}.`)
  ];
  const additionalMessages: Message[] = [];
  const additionalResults: ExecutionResult[] = [];
  let hadFailure = false;

  for (const execution of executions) {
    const node = nodeMap.get(execution.nodeId);
    const agent = agentMap.get(execution.agentId);
    if (!node || !agent) {
      hadFailure = true;
      executionLogs.push(
        createExecutionLog("ERROR", "Skipped a live approval execution because node or agent metadata was missing.", execution.nodeId)
      );
      continue;
    }

    const visibleOutput =
      execution.output.trim() || execution.engineMessage?.trim() || "OpenClaw returned no visible output.";
    additionalResults.push(
      createExecutionResult({
        nodeID: node.id,
        agentID: agent.id,
        status: execution.success ? "Completed" : "Failed",
        output: visibleOutput,
        outputType: execution.outputType,
        routingAction: execution.routingAction ?? null,
        routingTargets: execution.routingTargets ?? [],
        routingReason: execution.routingReason ?? execution.engineMessage ?? null
      })
    );

    additionalMessages.push(
      createMessageRecord({
        fromAgentID: agent.id,
        toAgentID: agent.id,
        type: execution.success ? "Notification" : "Data",
        content: visibleOutput,
        status: execution.success ? "Delivered" : "Failed",
        metadata: {
          channel: "workbench",
          role: "assistant",
          kind: "output",
          workflowID: workflow.id,
          taskID: task.id,
          nodeID: node.id,
          agentName: agent.name,
          outputType: execution.outputType,
          liveExecution: "true",
          liveAgentIdentifier: execution.agentIdentifier
        }
      })
    );

    executionLogs.push(
      createExecutionLog(
        execution.success ? "SUCCESS" : "ERROR",
        execution.success
          ? `OpenClaw executed ${agent.name} (${execution.agentIdentifier}) after approval.`
          : `OpenClaw failed while executing ${agent.name} (${execution.agentIdentifier}) after approval.`,
        node.id
      )
    );
    if (execution.routingAction || (execution.routingTargets?.length ?? 0) > 0) {
      executionLogs.push(
        createExecutionLog(
          "INFO",
          `Routing decision: ${execution.routingAction ?? "selected"}${
            execution.routingTargets && execution.routingTargets.length > 0
              ? ` -> ${execution.routingTargets.join(", ")}`
              : ""
          }${execution.routingReason ? ` (${execution.routingReason})` : ""}`,
          node.id
        )
      );
    }
    if (execution.engineMessage?.trim()) {
      executionLogs.push(createExecutionLog(execution.success ? "INFO" : "ERROR", execution.engineMessage.trim(), node.id));
    }
    if (execution.rawStderr?.trim()) {
      executionLogs.push(createExecutionLog("WARN", execution.rawStderr.trim(), node.id));
    }

    if (execution.success) {
      completedNodeIDs.add(node.id);
      runtimeAgentStates[agent.id] = "completed";
    } else {
      hadFailure = true;
      runtimeAgentStates[agent.id] = "failed";
    }
  }

  for (const checkpoint of approvalCheckpoints) {
    const sourceNode = nodeMap.get(checkpoint.sourceNodeId);
    const targetNode = nodeMap.get(checkpoint.targetNodeId);
    const sourceAgent = sourceNode?.agentID ? agentMap.get(sourceNode.agentID) : null;
    const targetAgent = targetNode?.agentID ? agentMap.get(targetNode.agentID) : null;
    if (!sourceNode || !targetNode || !sourceAgent || !targetAgent) {
      continue;
    }

    const approvalRecord = createMessageRecord({
      fromAgentID: sourceAgent.id,
      toAgentID: targetAgent.id,
      type: "Notification",
      content: `Approval required before routing from ${sourceAgent.name} to ${targetAgent.name}.`,
      status: "Waiting for Approval",
      requiresApproval: true,
      metadata: {
        channel: "workbench",
        role: "system",
        kind: "approval",
        workflowID: workflow.id,
        taskID: task.id,
        edgeID: checkpoint.edgeId,
        sourceNodeID: sourceNode.id,
        targetNodeID: targetNode.id,
        sourceAgentName: sourceAgent.name,
        targetAgentName: targetAgent.name,
        liveExecution: "true"
      }
    });
    additionalMessages.push(approvalRecord);
    pendingApprovalMessageIDs.add(approvalRecord.id);
    runtimeQueue.add(approvalRecord.id);
    runtimeAgentStates[targetAgent.id] = "waiting_approval";
    executionLogs.push(
      createExecutionLog("WARN", `Routing from ${sourceAgent.name} to ${targetAgent.name} is waiting for approval.`, targetNode.id)
    );
  }

  const nextTask = {
    ...task,
    metadata: {
      ...task.metadata,
      completedNodeIDs: serializeMetadataList(completedNodeIDs),
      pendingApprovalMessageIDs: serializeMetadataList(pendingApprovalMessageIDs),
      lastWorkbenchRunAt: String(toSwiftDate())
    }
  };
  const finalTask = updateTaskLifecycle(
    nextTask,
    hadFailure || pendingApprovalMessageIDs.size > 0 ? "Blocked" : "Done"
  );

  const nextTasks = [...project.tasks];
  nextTasks[taskIndex] = finalTask;

  return {
    project: {
      ...project,
      tasks: nextTasks,
      messages: [...updatedMessages, ...additionalMessages],
      executionLogs: [...project.executionLogs, ...executionLogs],
      executionResults: [...project.executionResults, ...additionalResults],
      runtimeState: {
        ...project.runtimeState,
        messageQueue: Array.from(runtimeQueue),
        agentStates: {
          ...project.runtimeState.agentStates,
          ...runtimeAgentStates
        },
        lastUpdated: toSwiftDate()
      },
      updatedAt: toSwiftDate()
    },
    taskId: finalTask.id,
    pendingApprovalCount: pendingApprovalMessageIDs.size,
    completedNodeCount: completedNodeIDs.size
  };
}
