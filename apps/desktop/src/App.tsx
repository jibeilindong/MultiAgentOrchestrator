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
  setWorkflowEdgeApprovalRequired,
  setWorkflowEdgeBidirectional,
  setWorkflowFallbackRoutingPolicy,
  updateTaskInProject,
  updateWorkflowEdgeLabel
} from "@multi-agent-flow/core";
import type {
  MAProject,
  TaskPriority,
  TaskStatus,
  WorkflowFallbackRoutingPolicy,
  WorkflowNodeType
} from "@multi-agent-flow/domain";
import { TASK_PRIORITIES, TASK_STATUSES } from "@multi-agent-flow/domain";
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
