import {
  addAgentToProject,
  addNodeToWorkflow,
  addTaskToProject,
  addWorkflowToProject,
  assignAgentToNode,
  assignAgentToNodes,
  assignTaskToAgent,
  connectWorkflowNodes,
  fromSwiftDate,
  generateTasksFromWorkflow,
  moveTaskToStatus,
  repositionWorkflowNode,
  repositionWorkflowNodes,
  removeEdgeFromWorkflow,
  removeNodesFromWorkflow,
  removeTaskFromProject,
  removeWorkflowFromProject,
  renameProject,
  renameWorkflow,
  renameWorkflowNode,
  reviewWorkbenchApproval,
  publishWorkbenchPrompt,
  setWorkflowEdgeApprovalRequired,
  setWorkflowEdgeBidirectional,
  setWorkflowFallbackRoutingPolicy,
  syncOpenClawState,
  importDetectedOpenClawAgents,
  updateOpenClawConfig,
  updateOpenClawSessionPaths,
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
  WorkflowFallbackRoutingPolicy,
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
      checks.push(config.localBinaryPath.trim().length > 0);
      if (config.localBinaryPath.trim().length === 0) {
        issues.push("Choose a local OpenClaw binary path.");
      }
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
  const [workbenchPrompt, setWorkbenchPrompt] = useState("");
  const [workbenchError, setWorkbenchError] = useState<string | null>(null);
  const [workbenchAction, setWorkbenchAction] = useState<"publish" | `approval:${string}` | null>(null);
  const [openClawAction, setOpenClawAction] = useState<"detect" | "connect" | "disconnect" | "import" | null>(null);
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
  const selectedNode =
    selectedNodeIds.length === 1
      ? activeWorkflow?.nodes.find((node) => node.id === selectedNodeIds[0]) ?? null
      : null;
  const selectedNodes = activeWorkflow?.nodes.filter((node) => selectedNodeIds.includes(node.id)) ?? [];
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
    updateProject((current) => updateOpenClawConfig(current, patch), nextStatus);
  }

  function handleOpenClawPathChange(
    patch: Parameters<typeof updateOpenClawSessionPaths>[1],
    nextStatus: string
  ) {
    updateProject((current) => updateOpenClawSessionPaths(current, patch), nextStatus);
  }

  async function handleDetectOpenClawAgents() {
    if (!project) {
      return;
    }

    setOpenClawAction("detect");
    try {
      const result = await requireDesktopApi().detectOpenClawAgents(project.openClaw.config);
      updateProject(
        (current) =>
          syncOpenClawState(current, {
            isConnected: false,
            availableAgents: result.availableAgents,
            activeAgents: result.activeAgents,
            detectedAgents: result.detectedAgents
          }),
        result.message
      );
    } catch (actionError) {
      setError(actionError instanceof Error ? actionError.message : String(actionError));
    } finally {
      setOpenClawAction(null);
    }
  }

  async function handleConnectOpenClaw() {
    if (!project) {
      return;
    }

    setOpenClawAction("connect");
    try {
      const result = await requireDesktopApi().connectOpenClaw(project.openClaw.config);
      updateProject(
        (current) =>
          syncOpenClawState(current, {
            isConnected: result.isConnected,
            availableAgents: result.availableAgents,
            activeAgents: result.activeAgents,
            detectedAgents: result.detectedAgents
          }),
        result.message
      );
    } catch (actionError) {
      setError(actionError instanceof Error ? actionError.message : String(actionError));
    } finally {
      setOpenClawAction(null);
    }
  }

  async function handleDisconnectOpenClaw() {
    setOpenClawAction("disconnect");
    try {
      const result = await requireDesktopApi().disconnectOpenClaw();
      updateProject(
        (current) =>
          syncOpenClawState(current, {
            isConnected: result.isConnected,
            availableAgents: result.availableAgents,
            activeAgents: result.activeAgents
          }),
        result.message
      );
    } catch (actionError) {
      setError(actionError instanceof Error ? actionError.message : String(actionError));
    } finally {
      setOpenClawAction(null);
    }
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

  function handlePublishWorkbenchPrompt() {
    if (!project || !activeWorkflow) {
      return;
    }

    const trimmedPrompt = workbenchPrompt.trim();
    if (!trimmedPrompt) {
      setWorkbenchError("Enter a task prompt for the active workflow.");
      return;
    }

    if (!project.openClaw.isConnected) {
      setWorkbenchError("Connect OpenClaw before publishing workbench tasks.");
      return;
    }

    if (!hasExecutableWorkflow) {
      setWorkbenchError("Connect the Start node to at least one assigned agent before publishing.");
      return;
    }

    setWorkbenchAction("publish");
    setWorkbenchError(null);
    try {
      const result = publishWorkbenchPrompt(project, activeWorkflow.id, trimmedPrompt);
      if (!result.taskId) {
        setWorkbenchError("Workbench publish could not resolve an executable entry agent.");
        return;
      }

      commitProject(
        result.project,
        result.pendingApprovalCount > 0
          ? `Published workbench task with ${result.pendingApprovalCount} approval checkpoint(s).`
          : `Published workbench task and recorded ${result.completedNodeCount} execution receipt(s).`
      );
      setWorkbenchPrompt("");
      setSelectedTaskId(result.taskId);
    } finally {
      setWorkbenchAction(null);
    }
  }

  function handleWorkbenchApproval(messageId: string, decision: "approve" | "reject") {
    if (!project) {
      return;
    }

    setWorkbenchAction(`approval:${messageId}`);
    setWorkbenchError(null);
    try {
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
                    <div key={agent.id} className="listCard">
                      <strong>{agent.name}</strong>
                      <span>{agent.identity}</span>
                      <span>{agent.openClawDefinition.modelIdentifier}</span>
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
                                  onClick={() => handleWorkbenchApproval(message.id, "approve")}
                                  disabled={workbenchAction === approvalActionKey}
                                >
                                  {workbenchAction === approvalActionKey ? "Working..." : "Approve"}
                                </button>
                                <button
                                  type="button"
                                  className="dangerButton"
                                  onClick={() => handleWorkbenchApproval(message.id, "reject")}
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
                        onClick={handlePublishWorkbenchPrompt}
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
                                  onClick={() => handleWorkbenchApproval(message.id, "approve")}
                                  disabled={workbenchAction === approvalActionKey}
                                >
                                  {workbenchAction === approvalActionKey ? "Working..." : "Approve"}
                                </button>
                                <button
                                  type="button"
                                  className="dangerButton"
                                  onClick={() => handleWorkbenchApproval(message.id, "reject")}
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
                  <label className="field">
                    <span>Local binary path</span>
                    <input
                      value={project.openClaw.config.localBinaryPath}
                      onChange={(event) =>
                        handleOpenClawConfigChange(
                          { localBinaryPath: event.target.value },
                          "Updated OpenClaw binary path."
                        )
                      }
                      placeholder="/usr/local/bin/openclaw"
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
                  <strong>{openClawReadiness?.label ?? "Unavailable"}</strong>
                  <p>
                    Score {openClawReadiness ? formatPercent(openClawReadiness.score) : "0%"}.
                    {openClawReadiness?.issues[0] ? ` ${openClawReadiness.issues[0]}` : " Configuration looks complete."}
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
