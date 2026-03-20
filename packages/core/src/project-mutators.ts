import type {
  Agent,
  MAProject,
  Task,
  TaskPriority,
  TaskStatus,
  Workflow,
  WorkflowFallbackRoutingPolicy,
  WorkflowNodeType
} from "@multi-agent-flow/domain";
import { toSwiftDate } from "./swift-date";
import { createUUID } from "./uuid";

function withUpdatedAt(project: MAProject): MAProject {
  return {
    ...project,
    updatedAt: toSwiftDate()
  };
}

function uniqueName(existingNames: string[], baseName: string): string {
  const trimmed = baseName.trim() || "Untitled";
  const existing = new Set(existingNames);
  if (!existing.has(trimmed)) {
    return trimmed;
  }

  let counter = 2;
  let candidate = `${trimmed} ${counter}`;
  while (existing.has(candidate)) {
    counter += 1;
    candidate = `${trimmed} ${counter}`;
  }

  return candidate;
}

function createAgent(name: string, index: number): Agent {
  const now = toSwiftDate();

  return {
    id: createUUID(),
    name,
    identity: "generalist",
    description: "",
    soulMD: "# New Agent\nThis agent configuration was created in the cross-platform shell.",
    position: {
      x: 140 + index * 80,
      y: 180 + (index % 3) * 56
    },
    createdAt: now,
    updatedAt: now,
    capabilities: ["basic"],
    colorHex: null,
    openClawDefinition: {
      agentIdentifier: name,
      modelIdentifier: "MiniMax-M2.5",
      runtimeProfile: "default",
      memoryBackupPath: null,
      soulSourcePath: null,
      environment: {}
    }
  };
}

interface TaskDraft {
  title?: string;
  description?: string;
  status?: TaskStatus;
  priority?: TaskPriority;
  assignedAgentID?: string | null;
  workflowNodeID?: string | null;
  createdBy?: string | null;
  estimatedDuration?: number | null;
  actualDuration?: number | null;
  tags?: string[];
  metadata?: Record<string, string>;
}

function sanitizeTaskTags(tags: string[] | undefined): string[] {
  if (!tags) {
    return [];
  }

  return Array.from(
    new Set(
      tags
        .map((tag) => tag.trim())
        .filter(Boolean)
    )
  );
}

function sanitizeTaskMetadata(metadata: Record<string, string> | undefined): Record<string, string> {
  if (!metadata) {
    return {};
  }

  return Object.fromEntries(
    Object.entries(metadata)
      .map(([key, value]) => [key.trim(), value.trim()])
      .filter(([key, value]) => key.length > 0 && value.length > 0)
  );
}

function sanitizeDuration(value: number | null | undefined): number | null {
  if (value == null || Number.isNaN(value)) {
    return null;
  }

  return Math.max(0, Math.round(value));
}

function reconcileTaskLifecycle(task: Task, previousTask?: Task): Task {
  if (previousTask?.status === task.status) {
    return task;
  }

  const now = toSwiftDate();

  switch (task.status) {
    case "To Do":
      return {
        ...task,
        startedAt: null,
        completedAt: null,
        actualDuration: null
      };
    case "In Progress":
      return {
        ...task,
        startedAt: task.startedAt ?? previousTask?.startedAt ?? now,
        completedAt: null,
        actualDuration: null
      };
    case "Done": {
      const startedAt = task.startedAt ?? previousTask?.startedAt ?? now;
      const completedAt = now;
      return {
        ...task,
        startedAt,
        completedAt,
        actualDuration: Math.max(0, Math.round(completedAt - startedAt))
      };
    }
    case "Blocked":
      return {
        ...task,
        startedAt: task.startedAt ?? previousTask?.startedAt ?? null,
        completedAt: null,
        actualDuration: null
      };
  }
}

function createTaskRecord(draft: TaskDraft = {}): Task {
  const now = toSwiftDate();

  return reconcileTaskLifecycle(
    {
      id: createUUID(),
      title: draft.title?.trim() || "Untitled Task",
      description: draft.description?.trim() ?? "",
      status: draft.status ?? "To Do",
      priority: draft.priority ?? "Medium",
      assignedAgentID: draft.assignedAgentID ?? null,
      workflowNodeID: draft.workflowNodeID ?? null,
      createdBy: draft.createdBy ?? null,
      createdAt: now,
      startedAt: null,
      completedAt: null,
      estimatedDuration: sanitizeDuration(draft.estimatedDuration),
      actualDuration: sanitizeDuration(draft.actualDuration),
      tags: sanitizeTaskTags(draft.tags),
      metadata: sanitizeTaskMetadata(draft.metadata)
    },
    undefined
  );
}

function patchTaskRecord(task: Task, patch: TaskDraft): Task {
  return reconcileTaskLifecycle(
    {
      ...task,
      title: patch.title === undefined ? task.title : patch.title.trim() || "Untitled Task",
      description: patch.description === undefined ? task.description : patch.description.trim(),
      status: patch.status ?? task.status,
      priority: patch.priority ?? task.priority,
      assignedAgentID: patch.assignedAgentID === undefined ? task.assignedAgentID ?? null : patch.assignedAgentID,
      workflowNodeID: patch.workflowNodeID === undefined ? task.workflowNodeID ?? null : patch.workflowNodeID,
      createdBy: patch.createdBy === undefined ? task.createdBy ?? null : patch.createdBy,
      estimatedDuration:
        patch.estimatedDuration === undefined ? task.estimatedDuration ?? null : sanitizeDuration(patch.estimatedDuration),
      actualDuration:
        patch.actualDuration === undefined ? task.actualDuration ?? null : sanitizeDuration(patch.actualDuration),
      tags: patch.tags === undefined ? task.tags : sanitizeTaskTags(patch.tags),
      metadata: patch.metadata === undefined ? task.metadata : sanitizeTaskMetadata(patch.metadata)
    },
    task
  );
}

function updateWorkflow(project: MAProject, workflowId: string, mutate: (workflow: Workflow) => Workflow): MAProject {
  return withUpdatedAt({
    ...project,
    workflows: project.workflows.map((workflow) =>
      workflow.id === workflowId ? mutate(workflow) : workflow
    )
  });
}

export function renameProject(project: MAProject, nextName: string): MAProject {
  return withUpdatedAt({
    ...project,
    name: nextName
  });
}

export function addAgentToProject(project: MAProject, baseName = "New Agent"): MAProject {
  const name = uniqueName(
    project.agents.map((agent) => agent.name),
    baseName
  );

  return withUpdatedAt({
    ...project,
    agents: [...project.agents, createAgent(name, project.agents.length)]
  });
}

export function addTaskToProject(project: MAProject, draft: TaskDraft = {}): MAProject {
  return withUpdatedAt({
    ...project,
    tasks: [...project.tasks, createTaskRecord(draft)]
  });
}

export function updateTaskInProject(
  project: MAProject,
  taskId: string,
  patch: TaskDraft
): MAProject {
  let didChange = false;

  const nextTasks = project.tasks.map((task) => {
    if (task.id !== taskId) {
      return task;
    }

    const nextTask = patchTaskRecord(task, patch);
    if (JSON.stringify(nextTask) !== JSON.stringify(task)) {
      didChange = true;
    }
    return nextTask;
  });

  if (!didChange) {
    return project;
  }

  return withUpdatedAt({
    ...project,
    tasks: nextTasks
  });
}

export function removeTaskFromProject(project: MAProject, taskId: string): MAProject {
  const nextTasks = project.tasks.filter((task) => task.id !== taskId);
  if (nextTasks.length === project.tasks.length) {
    return project;
  }

  return withUpdatedAt({
    ...project,
    tasks: nextTasks
  });
}

export function moveTaskToStatus(
  project: MAProject,
  taskId: string,
  status: TaskStatus
): MAProject {
  return updateTaskInProject(project, taskId, { status });
}

export function assignTaskToAgent(
  project: MAProject,
  taskId: string,
  agentId: string | null
): MAProject {
  return updateTaskInProject(project, taskId, { assignedAgentID: agentId });
}

export function generateTasksFromWorkflow(
  project: MAProject,
  workflowId: string
): MAProject {
  const workflow = project.workflows.find((item) => item.id === workflowId);
  if (!workflow) {
    return project;
  }

  const agentNodes = workflow.nodes.filter((node) => node.type === "agent");
  const agentNodeIds = new Set(agentNodes.map((node) => node.id));
  const preservedTasks = project.tasks.filter((task) =>
    !task.workflowNodeID || !agentNodeIds.has(task.workflowNodeID)
  );

  const generatedTasks = agentNodes.flatMap((node) => {
    if (!node.agentID) {
      return [];
    }

    const agent = project.agents.find((item) => item.id === node.agentID);
    if (!agent) {
      return [];
    }

    const existingTask = project.tasks.find((task) => task.workflowNodeID === node.id);
    const title = `Execute: ${agent.name}`;
    const description = `Execute workflow node "${node.title || agent.name}" for ${agent.name}.`;

    if (existingTask) {
      return [
        patchTaskRecord(existingTask, {
          title,
          description,
          assignedAgentID: agent.id,
          workflowNodeID: node.id
        })
      ];
    }

    return [
      createTaskRecord({
        title,
        description,
        priority: "Medium",
        status: "To Do",
        assignedAgentID: agent.id,
        workflowNodeID: node.id,
        metadata: {
          workflowId
        }
      })
    ];
  });

  return withUpdatedAt({
    ...project,
    tasks: [...preservedTasks, ...generatedTasks]
  });
}

export function addWorkflowToProject(project: MAProject, baseName = "Workflow"): MAProject {
  const now = toSwiftDate();
  const name = uniqueName(
    project.workflows.map((workflow) => workflow.name),
    baseName
  );

  return withUpdatedAt({
    ...project,
    workflows: [
      ...project.workflows,
      {
        id: createUUID(),
        name,
        fallbackRoutingPolicy: "stop",
        launchTestCases: [],
        lastLaunchVerificationReport: null,
        nodes: [],
        edges: [],
        boundaries: [],
        colorGroups: [],
        createdAt: now,
        parentNodeID: null,
        inputSchema: [],
        outputSchema: []
      }
    ]
  });
}

export function renameWorkflow(project: MAProject, workflowId: string, nextName: string): MAProject {
  return updateWorkflow(project, workflowId, (workflow) => ({
    ...workflow,
    name: nextName
  }));
}

export function setWorkflowFallbackRoutingPolicy(
  project: MAProject,
  workflowId: string,
  fallbackRoutingPolicy: WorkflowFallbackRoutingPolicy
): MAProject {
  return updateWorkflow(project, workflowId, (workflow) => ({
    ...workflow,
    fallbackRoutingPolicy
  }));
}

export function removeWorkflowFromProject(project: MAProject, workflowId: string): MAProject {
  if (project.workflows.length <= 1) {
    return project;
  }

  return withUpdatedAt({
    ...project,
    workflows: project.workflows.filter((workflow) => workflow.id !== workflowId)
  });
}

export function addNodeToWorkflow(
  project: MAProject,
  workflowId: string,
  nodeType: WorkflowNodeType
): MAProject {
  return updateWorkflow(project, workflowId, (workflow) => {
    const nodeIndex = workflow.nodes.length;

    return {
      ...workflow,
      nodes: [
        ...workflow.nodes,
        {
          id: createUUID(),
          agentID: null,
          type: nodeType,
          position: {
            x: 120 + nodeIndex * 160,
            y: nodeType === "start" ? 120 : 260
          },
          title: nodeType === "start" ? "Start" : `Agent Node ${nodeIndex + 1}`,
          displayColorHex: null,
          conditionExpression: "",
          loopEnabled: false,
          maxIterations: 1,
          subflowID: null,
          nestingLevel: 0,
          inputParameters: [],
          outputParameters: []
        }
      ]
    };
  });
}

export function assignAgentToNode(
  project: MAProject,
  workflowId: string,
  nodeId: string,
  agentId: string | null
): MAProject {
  return assignAgentToNodes(project, workflowId, [nodeId], agentId);
}

export function assignAgentToNodes(
  project: MAProject,
  workflowId: string,
  nodeIds: string[],
  agentId: string | null
): MAProject {
  const nodeIdSet = new Set(nodeIds);
  if (nodeIdSet.size === 0) {
    return project;
  }

  const agentName = project.agents.find((agent) => agent.id === agentId)?.name;

  return updateWorkflow(project, workflowId, (workflow) => ({
    ...workflow,
    nodes: workflow.nodes.map((node) =>
      nodeIdSet.has(node.id)
        ? {
            ...node,
            agentID: agentId,
            title: agentName && node.type === "agent" ? agentName : node.title
          }
        : node
    )
  }));
}

export function renameWorkflowNode(
  project: MAProject,
  workflowId: string,
  nodeId: string,
  title: string
): MAProject {
  return updateWorkflow(project, workflowId, (workflow) => ({
    ...workflow,
    nodes: workflow.nodes.map((node) =>
      node.id === nodeId
        ? {
            ...node,
            title
          }
        : node
    )
  }));
}

export function repositionWorkflowNode(
  project: MAProject,
  workflowId: string,
  nodeId: string,
  x: number,
  y: number
): MAProject {
  const nextX = Math.max(24, Math.round(x));
  const nextY = Math.max(24, Math.round(y));

  return updateWorkflow(project, workflowId, (workflow) => ({
    ...workflow,
    nodes: workflow.nodes.map((node) =>
      node.id === nodeId
        ? {
            ...node,
            position: {
              x: nextX,
              y: nextY
            }
          }
        : node
    )
  }));
}

export function repositionWorkflowNodes(
  project: MAProject,
  workflowId: string,
  updates: Array<{ nodeId: string; x: number; y: number }>
): MAProject {
  if (updates.length === 0) {
    return project;
  }

  const updateMap = new Map(
    updates.map((update) => [
      update.nodeId,
      {
        x: Math.max(24, Math.round(update.x)),
        y: Math.max(24, Math.round(update.y))
      }
    ])
  );

  return updateWorkflow(project, workflowId, (workflow) => ({
    ...workflow,
    nodes: workflow.nodes.map((node) => {
      const nextPosition = updateMap.get(node.id);
      if (!nextPosition) {
        return node;
      }

      return {
        ...node,
        position: nextPosition
      };
    })
  }));
}

export function removeNodeFromWorkflow(
  project: MAProject,
  workflowId: string,
  nodeId: string
): MAProject {
  return removeNodesFromWorkflow(project, workflowId, [nodeId]);
}

export function removeNodesFromWorkflow(
  project: MAProject,
  workflowId: string,
  nodeIds: string[]
): MAProject {
  const nodeIdSet = new Set(nodeIds);
  if (nodeIdSet.size === 0) {
    return project;
  }

  return updateWorkflow(project, workflowId, (workflow) => ({
    ...workflow,
    nodes: workflow.nodes.filter((node) => !nodeIdSet.has(node.id)),
    edges: workflow.edges.filter((edge) => !nodeIdSet.has(edge.fromNodeID) && !nodeIdSet.has(edge.toNodeID))
  }));
}

export function connectWorkflowNodes(
  project: MAProject,
  workflowId: string,
  fromNodeID: string,
  toNodeID: string
): MAProject {
  if (!fromNodeID || !toNodeID || fromNodeID === toNodeID) {
    return project;
  }

  return updateWorkflow(project, workflowId, (workflow) => {
    const exists = workflow.edges.some(
      (edge) => edge.fromNodeID === fromNodeID && edge.toNodeID === toNodeID
    );
    if (exists) {
      return workflow;
    }

    return {
      ...workflow,
      edges: [
        ...workflow.edges,
        {
          id: createUUID(),
          fromNodeID,
          toNodeID,
          label: "",
          displayColorHex: null,
          conditionExpression: "",
          requiresApproval: false,
          isBidirectional: false,
          dataMapping: {}
        }
      ]
    };
  });
}

export function removeEdgeFromWorkflow(
  project: MAProject,
  workflowId: string,
  edgeId: string
): MAProject {
  return updateWorkflow(project, workflowId, (workflow) => ({
    ...workflow,
    edges: workflow.edges.filter((edge) => edge.id !== edgeId)
  }));
}

export function updateWorkflowEdgeLabel(
  project: MAProject,
  workflowId: string,
  edgeId: string,
  label: string
): MAProject {
  return updateWorkflow(project, workflowId, (workflow) => ({
    ...workflow,
    edges: workflow.edges.map((edge) =>
      edge.id === edgeId
        ? {
            ...edge,
            label
          }
        : edge
    )
  }));
}

export function setWorkflowEdgeApprovalRequired(
  project: MAProject,
  workflowId: string,
  edgeId: string,
  requiresApproval: boolean
): MAProject {
  return updateWorkflow(project, workflowId, (workflow) => ({
    ...workflow,
    edges: workflow.edges.map((edge) =>
      edge.id === edgeId
        ? {
            ...edge,
            requiresApproval
          }
        : edge
    )
  }));
}

export function setWorkflowEdgeBidirectional(
  project: MAProject,
  workflowId: string,
  edgeId: string,
  isBidirectional: boolean
): MAProject {
  return updateWorkflow(project, workflowId, (workflow) => ({
    ...workflow,
    edges: workflow.edges.map((edge) =>
      edge.id === edgeId
        ? {
            ...edge,
            isBidirectional
          }
        : edge
    )
  }));
}
