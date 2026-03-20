import {
  addAgentToProject,
  addNodeToWorkflow,
  addWorkflowToProject,
  assignAgentToNode,
  connectWorkflowNodes,
  fromSwiftDate,
  repositionWorkflowNode,
  removeEdgeFromWorkflow,
  removeNodeFromWorkflow,
  removeWorkflowFromProject,
  renameProject,
  renameWorkflow,
  renameWorkflowNode,
  setWorkflowEdgeApprovalRequired,
  setWorkflowEdgeBidirectional,
  setWorkflowFallbackRoutingPolicy,
  updateWorkflowEdgeLabel
} from "@multi-agent-flow/core";
import type {
  MAProject,
  WorkflowFallbackRoutingPolicy,
  WorkflowNodeType
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
  const [activeWorkflowId, setActiveWorkflowId] = useState<string | null>(null);
  const [selectedNodeId, setSelectedNodeId] = useState<string | null>(null);
  const [selectedEdgeId, setSelectedEdgeId] = useState<string | null>(null);
  const [canvasZoom, setCanvasZoom] = useState(DEFAULT_CANVAS_ZOOM);
  const [newNodeType, setNewNodeType] = useState<WorkflowNodeType>("agent");
  const [connectionFromNodeId, setConnectionFromNodeId] = useState("");
  const [connectionToNodeId, setConnectionToNodeId] = useState("");
  const project = projectState?.project ?? null;
  const filePath = projectState?.filePath ?? null;
  const activeWorkflow =
    project?.workflows.find((workflow) => workflow.id === activeWorkflowId) ?? project?.workflows[0] ?? null;
  const selectedNode =
    activeWorkflow?.nodes.find((node) => node.id === selectedNodeId) ?? null;
  const selectedEdge =
    activeWorkflow?.edges.find((edge) => edge.id === selectedEdgeId) ?? null;
  const canUndo = projectHistory.past.length > 0;
  const canRedo = projectHistory.future.length > 0;

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
      setSelectedEdgeId(null);
      return;
    }

    if (selectedNodeId && !activeWorkflow.nodes.some((node) => node.id === selectedNodeId)) {
      setSelectedNodeId(null);
    }
    if (selectedEdgeId && !activeWorkflow.edges.some((edge) => edge.id === selectedEdgeId)) {
      setSelectedEdgeId(null);
    }
  }, [activeWorkflow, selectedEdgeId, selectedNodeId]);

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

      if (selectedNodeId) {
        event.preventDefault();
        handleRemoveNode(selectedNodeId);
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [selectedEdgeId, selectedNodeId, activeWorkflow, connectionFromNodeId, connectionToNodeId, canUndo, canRedo]);

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
        setSelectedEdgeId(null);
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
        setSelectedEdgeId(null);
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
        setSelectedEdgeId(null);
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
  }

  function handleCanvasBackgroundClick() {
    const hadConnectionSelection = Boolean(connectionFromNodeId || connectionToNodeId);
    const hadObjectSelection = Boolean(selectedNodeId || selectedEdgeId);

    if (!hadConnectionSelection && !hadObjectSelection) {
      return;
    }

    setSelectedNodeId(null);
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
    if (!activeWorkflow) {
      return;
    }

    updateProject(
      (current) => removeNodeFromWorkflow(current, activeWorkflow.id, nodeId),
      "Removed workflow node and related edges."
    );

    if (connectionFromNodeId === nodeId) {
      setConnectionFromNodeId("");
    }

    if (connectionToNodeId === nodeId) {
      setConnectionToNodeId("");
    }

    if (selectedNodeId === nodeId) {
      setSelectedNodeId(null);
    }
    if (selectedEdgeId && activeWorkflow.edges.some((edge) => edge.id === selectedEdgeId && (edge.fromNodeID === nodeId || edge.toNodeID === nodeId))) {
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

    updateProject((current) => repositionWorkflowNode(current, activeWorkflow.id, nodeId, x, y));
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

  function handleCanvasNodeSelect(nodeId: string) {
    setSelectedNodeId(nodeId);
    setSelectedEdgeId(null);
  }

  function handleCanvasEdgeSelect(edgeId: string) {
    setConnectionFromNodeId("");
    setConnectionToNodeId("");
    setSelectedEdgeId(edgeId);
    setSelectedNodeId(null);
    setStatus("Selected an edge on the canvas.");
  }

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
                  </div>

                  <div className="formStack">
                    <span className="sectionLabel">Visual preview</span>
                    <p className="canvasHint">
                      Click one node to choose a source, drag from a node handle to connect directly,
                      drag nodes to reposition them, hold Space and drag to pan, use zoom controls
                      plus scrolling to inspect larger workflows, press Esc/Delete for quick canvas
                      cleanup, and use Cmd/Ctrl+Z to undo changes.
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
                      selectedEdgeId={selectedEdgeId ?? undefined}
                      selectedFromNodeId={connectionFromNodeId}
                      selectedToNodeId={connectionToNodeId}
                      onWheelZoom={(deltaY) => updateCanvasZoom(canvasZoom + (deltaY < 0 ? 0.1 : -0.1))}
                      onNodeConnect={handleCanvasNodeConnect}
                      onNodeSelect={handleCanvasNodeSelect}
                      onEdgeSelect={handleCanvasEdgeSelect}
                      onNodePositionChange={handleNodePositionChange}
                      onNodePositionCommit={handleNodePositionCommit}
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
