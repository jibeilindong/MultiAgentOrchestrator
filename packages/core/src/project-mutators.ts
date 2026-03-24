import type {
  Agent,
  MAProject,
  OpenClawAgentProtocolMemory,
  OpenClawCLILogLevel,
  OpenClawDeploymentKind,
  OpenClawRuntimeOwnership,
  Task,
  TaskPriority,
  TaskStatus,
  Workflow,
  WorkflowFallbackRoutingPolicy,
  WorkflowLaunchTestCase,
  WorkflowNodeType
} from "@multi-agent-flow/domain";
import { toSwiftDate } from "./swift-date";
import { createUUID } from "./uuid";
import { normalizeAgentName, normalizeRuntimeAgentIdentifier } from "./agent-naming";
import { normalizeWorkflowNodeTitle } from "./workflow-node-naming";

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

function normalizeAgentKey(value: string): string {
  return value.trim().toLowerCase();
}

function createDefaultProtocolMemory(now: number): OpenClawAgentProtocolMemory {
  return {
    protocolVersion: "openclaw.runtime.v1",
    stableRules: [
      "Machine-readable workflow coordination must use the runtime protocol.",
      "Always end with exactly one valid routing JSON line when a machine tail is required.",
      "Only choose downstream targets from the allowed candidate list.",
      "Do not exceed the provided write scope, tool scope, or approval rules.",
      "If uncertain, emit the smallest valid safe result instead of guessing."
    ],
    recentCorrections: [],
    repeatOffenses: [],
    lastSessionDigest: null,
    lastUpdatedAt: now
  };
}

function createAgent(name: string, index: number, existingAgents: Agent[] = []): Agent {
  const now = toSwiftDate();
  const normalizedName = normalizeAgentName(existingAgents, name);
  const runtimeAgentIdentifier = normalizeRuntimeAgentIdentifier(existingAgents, normalizedName, normalizedName);

  return {
    id: createUUID(),
    name: normalizedName,
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
      agentIdentifier: runtimeAgentIdentifier,
      modelIdentifier: "MiniMax-M2.5",
      runtimeProfile: "default",
      memoryBackupPath: null,
      soulSourcePath: null,
      environment: {},
      protocolMemory: createDefaultProtocolMemory(now)
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

interface WorkflowLaunchTestCaseDraft {
  name?: string;
  prompt?: string;
  requiredAgentNames?: string[];
  forbiddenAgentNames?: string[];
  expectedRoutingActions?: string[];
  expectedOutputTypes?: string[];
  maxSteps?: number | null;
  notes?: string;
}

interface AgentDraft {
  name?: string;
  identity?: string;
  description?: string;
  soulMD?: string;
  capabilities?: string[];
  colorHex?: string | null;
  openClawDefinition?: Partial<Agent["openClawDefinition"]>;
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

function sanitizeAgentEnvironment(environment: Record<string, string> | undefined): Record<string, string> {
  if (!environment) {
    return {};
  }

  return Object.fromEntries(
    Object.entries(environment)
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

function sanitizeStringList(values: string[] | undefined): string[] {
  if (!values) {
    return [];
  }

  return Array.from(
    new Set(
      values
        .map((value) => value.trim())
        .filter(Boolean)
    )
  );
}

function sanitizeLaunchMaxSteps(value: number | null | undefined): number | null {
  if (value == null || Number.isNaN(value)) {
    return null;
  }

  return Math.max(1, Math.round(value));
}

function createWorkflowLaunchTestCaseRecord(
  workflow: Workflow,
  draft: WorkflowLaunchTestCaseDraft = {}
): WorkflowLaunchTestCase {
  return {
    id: createUUID(),
    name: draft.name?.trim() || `Launch Case ${workflow.launchTestCases.length + 1}`,
    prompt: draft.prompt?.trim() || "Reply with a concise readiness confirmation.",
    requiredAgentNames: sanitizeStringList(draft.requiredAgentNames),
    forbiddenAgentNames: sanitizeStringList(draft.forbiddenAgentNames),
    expectedRoutingActions: sanitizeStringList(draft.expectedRoutingActions),
    expectedOutputTypes: sanitizeStringList(draft.expectedOutputTypes),
    maxSteps: sanitizeLaunchMaxSteps(draft.maxSteps),
    notes: draft.notes?.trim() ?? ""
  };
}

function patchWorkflowLaunchTestCaseRecord(
  testCase: WorkflowLaunchTestCase,
  patch: WorkflowLaunchTestCaseDraft
): WorkflowLaunchTestCase {
  return {
    ...testCase,
    name: patch.name === undefined ? testCase.name : patch.name.trim() || testCase.name,
    prompt: patch.prompt === undefined ? testCase.prompt : patch.prompt.trim(),
    requiredAgentNames:
      patch.requiredAgentNames === undefined ? testCase.requiredAgentNames : sanitizeStringList(patch.requiredAgentNames),
    forbiddenAgentNames:
      patch.forbiddenAgentNames === undefined ? testCase.forbiddenAgentNames : sanitizeStringList(patch.forbiddenAgentNames),
    expectedRoutingActions:
      patch.expectedRoutingActions === undefined
        ? testCase.expectedRoutingActions
        : sanitizeStringList(patch.expectedRoutingActions),
    expectedOutputTypes:
      patch.expectedOutputTypes === undefined ? testCase.expectedOutputTypes : sanitizeStringList(patch.expectedOutputTypes),
    maxSteps: patch.maxSteps === undefined ? testCase.maxSteps ?? null : sanitizeLaunchMaxSteps(patch.maxSteps),
    notes: patch.notes === undefined ? testCase.notes : patch.notes.trim()
  };
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

function sanitizeProjectPath(value: string | null | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

export function renameProject(project: MAProject, nextName: string): MAProject {
  return withUpdatedAt({
    ...project,
    name: nextName
  });
}

export function updateProjectTaskDataSettings(
  project: MAProject,
  patch: {
    workspaceRootPath?: string | null;
    organizationMode?: string;
  }
): MAProject {
  const nextTaskData = {
    ...project.taskData,
    workspaceRootPath:
      patch.workspaceRootPath === undefined
        ? project.taskData.workspaceRootPath ?? null
        : sanitizeProjectPath(patch.workspaceRootPath),
    organizationMode: patch.organizationMode?.trim() || project.taskData.organizationMode,
    lastUpdatedAt: toSwiftDate()
  };

  if (JSON.stringify(nextTaskData) === JSON.stringify(project.taskData)) {
    return project;
  }

  return withUpdatedAt({
    ...project,
    taskData: nextTaskData
  });
}

export function updateOpenClawConfig(
  project: MAProject,
  patch: {
    deploymentKind?: OpenClawDeploymentKind;
    runtimeOwnership?: OpenClawRuntimeOwnership;
    host?: string;
    port?: number;
    useSSL?: boolean;
    apiKey?: string;
    defaultAgent?: string;
    timeout?: number;
    autoConnect?: boolean;
    localBinaryPath?: string | null;
    cliQuietMode?: boolean;
    cliLogLevel?: OpenClawCLILogLevel;
    container?: Partial<{
      engine: string;
      containerName: string;
      workspaceMountPath: string;
    }>;
  }
): MAProject {
  const nextDeploymentKind = patch.deploymentKind ?? project.openClaw.config.deploymentKind;
  const nextRuntimeOwnership = nextDeploymentKind === "local"
    ? "appManaged"
    : (patch.runtimeOwnership ?? project.openClaw.config.runtimeOwnership);
  const nextLocalBinaryPath = nextDeploymentKind === "local"
    ? ""
    : (
        patch.localBinaryPath === undefined
          ? project.openClaw.config.localBinaryPath
          : (patch.localBinaryPath ?? "").trim()
      );
  const nextConfig = {
    ...project.openClaw.config,
    deploymentKind: nextDeploymentKind,
    runtimeOwnership: nextRuntimeOwnership,
    host: patch.host === undefined ? project.openClaw.config.host : patch.host.trim(),
    port:
      patch.port === undefined || Number.isNaN(patch.port)
        ? project.openClaw.config.port
        : Math.max(1, Math.round(patch.port)),
    useSSL: patch.useSSL ?? project.openClaw.config.useSSL,
    apiKey: patch.apiKey === undefined ? project.openClaw.config.apiKey : patch.apiKey.trim(),
    defaultAgent:
      patch.defaultAgent === undefined ? project.openClaw.config.defaultAgent : patch.defaultAgent.trim(),
    timeout:
      patch.timeout === undefined || Number.isNaN(patch.timeout)
        ? project.openClaw.config.timeout
        : Math.max(1, Math.round(patch.timeout)),
    autoConnect: patch.autoConnect ?? project.openClaw.config.autoConnect,
    localBinaryPath: nextLocalBinaryPath,
    cliQuietMode: patch.cliQuietMode ?? project.openClaw.config.cliQuietMode,
    cliLogLevel: patch.cliLogLevel ?? project.openClaw.config.cliLogLevel,
    container: {
      ...project.openClaw.config.container,
      engine: patch.container?.engine === undefined ? project.openClaw.config.container.engine : patch.container.engine.trim(),
      containerName:
        patch.container?.containerName === undefined
          ? project.openClaw.config.container.containerName
          : patch.container.containerName.trim(),
      workspaceMountPath:
        patch.container?.workspaceMountPath === undefined
          ? project.openClaw.config.container.workspaceMountPath
          : patch.container.workspaceMountPath.trim()
    }
  };

  if (JSON.stringify(nextConfig) === JSON.stringify(project.openClaw.config)) {
    return project;
  }

  return withUpdatedAt({
    ...project,
    openClaw: {
      ...project.openClaw,
      config: nextConfig,
      lastSyncedAt: toSwiftDate()
    }
  });
}

export function updateOpenClawSessionPaths(
  project: MAProject,
  patch: {
    sessionBackupPath?: string | null;
    sessionMirrorPath?: string | null;
  }
): MAProject {
  const nextOpenClaw = {
    ...project.openClaw,
    sessionBackupPath:
      patch.sessionBackupPath === undefined
        ? project.openClaw.sessionBackupPath ?? null
        : sanitizeProjectPath(patch.sessionBackupPath),
    sessionMirrorPath:
      patch.sessionMirrorPath === undefined
        ? project.openClaw.sessionMirrorPath ?? null
        : sanitizeProjectPath(patch.sessionMirrorPath),
    lastSyncedAt: toSwiftDate()
  };

  if (
    nextOpenClaw.sessionBackupPath === (project.openClaw.sessionBackupPath ?? null) &&
    nextOpenClaw.sessionMirrorPath === (project.openClaw.sessionMirrorPath ?? null)
  ) {
    return project;
  }

  return withUpdatedAt({
    ...project,
    openClaw: nextOpenClaw
  });
}

export function syncOpenClawState(
  project: MAProject,
  payload: {
    isConnected: boolean;
    availableAgents?: string[];
    activeAgents?: MAProject["openClaw"]["activeAgents"];
    detectedAgents?: MAProject["openClaw"]["detectedAgents"];
    connectionState?: MAProject["openClaw"]["connectionState"];
    sessionLifecycle?: MAProject["openClaw"]["sessionLifecycle"];
    lastProbeReport?: MAProject["openClaw"]["lastProbeReport"];
    recoveryReports?: MAProject["openClaw"]["recoveryReports"];
  }
): MAProject {
  const nextOpenClaw = {
    ...project.openClaw,
    isConnected: payload.isConnected,
    availableAgents: payload.availableAgents ?? project.openClaw.availableAgents,
    activeAgents: payload.activeAgents ?? project.openClaw.activeAgents,
    detectedAgents: payload.detectedAgents ?? project.openClaw.detectedAgents,
    connectionState: payload.connectionState ?? project.openClaw.connectionState,
    sessionLifecycle:
      payload.sessionLifecycle === undefined ? project.openClaw.sessionLifecycle ?? null : payload.sessionLifecycle,
    lastProbeReport:
      payload.lastProbeReport === undefined ? project.openClaw.lastProbeReport ?? null : payload.lastProbeReport,
    recoveryReports: payload.recoveryReports ?? project.openClaw.recoveryReports ?? [],
    lastSyncedAt: toSwiftDate()
  };

  return withUpdatedAt({
    ...project,
    openClaw: nextOpenClaw
  });
}

export function appendOpenClawRecoveryReport(
  project: MAProject,
  report: NonNullable<MAProject["openClaw"]["recoveryReports"]>[number],
  maxReports = 10
): MAProject {
  const nextReports = [report, ...(project.openClaw.recoveryReports ?? [])].slice(0, Math.max(1, maxReports));

  return withUpdatedAt({
    ...project,
    openClaw: {
      ...project.openClaw,
      recoveryReports: nextReports,
      lastSyncedAt: toSwiftDate()
    }
  });
}

export function importDetectedOpenClawAgents(
  project: MAProject,
  detectedAgentIds?: string[]
): MAProject {
  const selectedIds = detectedAgentIds ? new Set(detectedAgentIds) : null;
  const candidates = project.openClaw.detectedAgents.filter((record) =>
    selectedIds ? selectedIds.has(record.id) : true
  );

  if (candidates.length === 0) {
    return project;
  }

  const existingKeys = new Set(
    project.agents.flatMap((agent) => [
      normalizeAgentKey(agent.name),
      normalizeAgentKey(agent.openClawDefinition.agentIdentifier)
    ])
  );

  const nextAgents = [...project.agents];

  for (const record of candidates) {
    const recordKey = normalizeAgentKey(record.name);
    if (existingKeys.has(recordKey)) {
      continue;
    }

    const importedAgent = createAgent(
      record.name || "Imported Agent",
      nextAgents.length,
      nextAgents
    );
    importedAgent.identity = "openclaw";
    importedAgent.description = record.issues.length
      ? `Imported from OpenClaw detection. Notes: ${record.issues.join(" ")}`
      : "Imported from OpenClaw detection.";
    importedAgent.capabilities = Array.from(
      new Set([
        ...importedAgent.capabilities,
        record.directoryValidated ? "workspace" : "detected",
        record.configValidated ? "configured" : "unverified"
      ])
    );
    importedAgent.openClawDefinition = {
      ...importedAgent.openClawDefinition,
      agentIdentifier: record.name,
      soulSourcePath: record.directoryPath
        ? `${record.directoryPath.replace(/\/+$/, "")}/SOUL.md`
        : null,
      memoryBackupPath: record.statePath ?? null
    };

    nextAgents.push(importedAgent);
    existingKeys.add(recordKey);
  }

  if (nextAgents.length === project.agents.length) {
    return project;
  }

  return withUpdatedAt({
    ...project,
    agents: nextAgents
  });
}

export function addAgentToProject(project: MAProject, baseName = "New Agent"): MAProject {
  const name = normalizeAgentName(project.agents, baseName);

  return withUpdatedAt({
    ...project,
    agents: [...project.agents, createAgent(name, project.agents.length, project.agents)]
  });
}

export function updateAgentInProject(project: MAProject, agentId: string, patch: AgentDraft): MAProject {
  let didChange = false;
  const previousAgent = project.agents.find((agent) => agent.id === agentId);
  const normalizedName =
    patch.name === undefined
      ? previousAgent?.name
      : normalizeAgentName(project.agents, patch.name, {
          excludeAgentId: agentId
        });

  const nextAgents = project.agents.map((agent) => {
    if (agent.id !== agentId) {
      return agent;
    }

    const nextAgent: Agent = {
      ...agent,
      name: normalizedName ?? agent.name,
      identity: patch.identity === undefined ? agent.identity : patch.identity.trim() || agent.identity,
      description: patch.description === undefined ? agent.description : patch.description.trim(),
      soulMD: patch.soulMD === undefined ? agent.soulMD : patch.soulMD,
      capabilities: patch.capabilities === undefined ? agent.capabilities : sanitizeStringList(patch.capabilities),
      colorHex: patch.colorHex === undefined ? agent.colorHex ?? null : sanitizeProjectPath(patch.colorHex),
      openClawDefinition: {
        ...agent.openClawDefinition,
        agentIdentifier:
          normalizeRuntimeAgentIdentifier(
            project.agents,
            patch.openClawDefinition?.agentIdentifier === undefined
              ? agent.openClawDefinition.agentIdentifier || normalizedName || agent.name
              : patch.openClawDefinition.agentIdentifier.trim(),
            normalizedName || agent.name,
            { excludeAgentId: agentId }
          ),
        modelIdentifier:
          patch.openClawDefinition?.modelIdentifier === undefined
            ? agent.openClawDefinition.modelIdentifier
            : patch.openClawDefinition.modelIdentifier.trim(),
        runtimeProfile:
          patch.openClawDefinition?.runtimeProfile === undefined
            ? agent.openClawDefinition.runtimeProfile
            : patch.openClawDefinition.runtimeProfile.trim(),
        memoryBackupPath:
          patch.openClawDefinition?.memoryBackupPath === undefined
            ? agent.openClawDefinition.memoryBackupPath ?? null
            : sanitizeProjectPath(patch.openClawDefinition.memoryBackupPath),
        soulSourcePath:
          patch.openClawDefinition?.soulSourcePath === undefined
            ? agent.openClawDefinition.soulSourcePath ?? null
            : sanitizeProjectPath(patch.openClawDefinition.soulSourcePath),
        environment:
          patch.openClawDefinition?.environment === undefined
            ? agent.openClawDefinition.environment
            : sanitizeAgentEnvironment(patch.openClawDefinition.environment)
      },
      updatedAt: toSwiftDate()
    };

    if (JSON.stringify(nextAgent) !== JSON.stringify(agent)) {
      didChange = true;
    }

    return nextAgent;
  });

  if (!didChange) {
    return project;
  }

  const renamedAgent = nextAgents.find((agent) => agent.id === agentId) ?? null;
  const nextWorkflows =
    previousAgent && renamedAgent
      ? project.workflows.map((workflow) => {
          const nextNodes = [...workflow.nodes];
          let workflowDidChange = false;

          for (const [index, node] of workflow.nodes.entries()) {
            if (node.type !== "agent" || node.agentID !== agentId) {
              continue;
            }

            const trimmedTitle = node.title.trim();
            if (trimmedTitle.length > 0 && trimmedTitle !== previousAgent.name) {
              continue;
            }

            nextNodes[index] = {
              ...node,
              title: normalizeWorkflowNodeTitle(
                {
                  ...workflow,
                  nodes: nextNodes
                },
                node.type,
                renamedAgent.name,
                {
                  excludeNodeId: node.id,
                  fallbackFunctionDescription: renamedAgent.name
                }
              )
            };
            workflowDidChange = true;
          }

          return workflowDidChange
            ? {
                ...workflow,
                nodes: nextNodes
              }
            : workflow;
        })
      : project.workflows;

  return withUpdatedAt({
    ...project,
    agents: nextAgents,
    workflows: nextWorkflows
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

export function addWorkflowLaunchTestCase(
  project: MAProject,
  workflowId: string,
  draft: WorkflowLaunchTestCaseDraft = {}
): MAProject {
  const workflow = project.workflows.find((item) => item.id === workflowId);
  if (!workflow) {
    return project;
  }

  const nextCase = createWorkflowLaunchTestCaseRecord(workflow, draft);
  return updateWorkflow(project, workflowId, (currentWorkflow) => ({
    ...currentWorkflow,
    launchTestCases: [...currentWorkflow.launchTestCases, nextCase]
  }));
}

export function updateWorkflowLaunchTestCase(
  project: MAProject,
  workflowId: string,
  testCaseId: string,
  patch: WorkflowLaunchTestCaseDraft
): MAProject {
  let didChange = false;

  const nextWorkflows = project.workflows.map((workflow) => {
    if (workflow.id !== workflowId) {
      return workflow;
    }

    const nextCases = workflow.launchTestCases.map((testCase) => {
      if (testCase.id !== testCaseId) {
        return testCase;
      }

      const nextCase = patchWorkflowLaunchTestCaseRecord(testCase, patch);
      if (JSON.stringify(nextCase) !== JSON.stringify(testCase)) {
        didChange = true;
      }
      return nextCase;
    });

    if (!didChange) {
      return workflow;
    }

    return {
      ...workflow,
      launchTestCases: nextCases
    };
  });

  if (!didChange) {
    return project;
  }

  return withUpdatedAt({
    ...project,
    workflows: nextWorkflows
  });
}

export function removeWorkflowLaunchTestCase(
  project: MAProject,
  workflowId: string,
  testCaseId: string
): MAProject {
  const workflow = project.workflows.find((item) => item.id === workflowId);
  if (!workflow) {
    return project;
  }

  const nextCases = workflow.launchTestCases.filter((testCase) => testCase.id !== testCaseId);
  if (nextCases.length === workflow.launchTestCases.length) {
    return project;
  }

  return updateWorkflow(project, workflowId, (currentWorkflow) => ({
    ...currentWorkflow,
    launchTestCases: nextCases
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
    const title = normalizeWorkflowNodeTitle(workflow, nodeType, "");

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
          title,
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

  return updateWorkflow(project, workflowId, (workflow) => {
    const nextNodes = [...workflow.nodes];

    for (const [index, node] of workflow.nodes.entries()) {
      if (!nodeIdSet.has(node.id)) {
        continue;
      }

      const requestedTitle = agentName && node.type === "agent" ? agentName : node.title;
      nextNodes[index] = {
        ...node,
        agentID: agentId,
        title: normalizeWorkflowNodeTitle(
          {
            ...workflow,
            nodes: nextNodes
          },
          node.type,
          requestedTitle,
          {
            excludeNodeId: node.id
          }
        )
      };
    }

    return {
      ...workflow,
      nodes: nextNodes
    };
  });
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
            title: normalizeWorkflowNodeTitle(workflow, node.type, title, {
              excludeNodeId: node.id
            })
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
