import {
  addAgentToProject,
  addNodeToWorkflow,
  addWorkflowToProject,
  assignAgentToNode,
  connectWorkflowNodes,
  fromSwiftDate,
  renameProject
} from "@multi-agent-flow/core";
import type { MAProject, WorkflowNodeType } from "@multi-agent-flow/domain";
import { startTransition, useEffect, useState } from "react";

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

function requireDesktopApi() {
  const api = window.desktopApi;
  if (!api) {
    throw new Error("desktopApi is unavailable. Run this UI through the Electron shell.");
  }

  return api;
}

export function App() {
  const [projectState, setProjectState] = useState<ProjectFileHandle | null>(null);
  const [recentProjects, setRecentProjects] = useState<RecentProjectRecord[]>([]);
  const [autosaveInfo, setAutosaveInfo] = useState<AutosaveInfo | null>(null);
  const [busyAction, setBusyAction] = useState<BusyAction>(null);
  const [status, setStatus] = useState("Bootstrapping cross-platform workspace...");
  const [error, setError] = useState<string | null>(null);
  const [newAgentName, setNewAgentName] = useState("New Agent");
  const [newWorkflowName, setNewWorkflowName] = useState("Workflow");
  const [activeWorkflowId, setActiveWorkflowId] = useState<string | null>(null);
  const [newNodeType, setNewNodeType] = useState<WorkflowNodeType>("agent");
  const [connectionFromNodeId, setConnectionFromNodeId] = useState("");
  const [connectionToNodeId, setConnectionToNodeId] = useState("");
  const project = projectState?.project ?? null;
  const filePath = projectState?.filePath ?? null;
  const activeWorkflow =
    project?.workflows.find((workflow) => workflow.id === activeWorkflowId) ?? project?.workflows[0] ?? null;

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

  function updateProject(mutator: (current: MAProject) => MAProject, nextStatus?: string) {
    setProjectState((current) => {
      if (!current) {
        return current;
      }

      return {
        ...current,
        project: mutator(current.project)
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
        setProjectState(created);
        setActiveWorkflowId(created.project.workflows[0]?.id ?? null);
        setStatus("Created a new unsaved project.");
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
        setProjectState(opened);
        setActiveWorkflowId(opened.project.workflows[0]?.id ?? null);
        setStatus(`Opened ${opened.project.name}.`);
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
          setProjectState(saved);
          setStatus(`Saved ${saved.project.name}.`);
        });
        await refreshRecentProjects();
        return;
      }

      const saved = await requireDesktopApi().saveProject(project, filePath);
      startTransition(() => {
        setProjectState(saved);
        setStatus(`Saved ${saved.project.name}.`);
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
        setProjectState(saved);
        setStatus(`Saved ${saved.project.name} to a new location.`);
      });
      await refreshRecentProjects();
    });
  }

  async function handleOpenRecentProject(nextFilePath: string) {
    await runProjectAction("open", async () => {
      const opened = await requireDesktopApi().openRecentProject(nextFilePath);
      startTransition(() => {
        setProjectState(opened);
        setActiveWorkflowId(opened.project.workflows[0]?.id ?? null);
        setStatus(`Opened ${opened.project.name} from recent projects.`);
      });
      await refreshRecentProjects();
    });
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
      setStatus("Added a new workflow.");
    });
  }

  function handleAddNode() {
    if (!activeWorkflow) {
      return;
    }

    updateProject(
      (current) => addNodeToWorkflow(current, activeWorkflow.id, newNodeType),
      `Added a ${newNodeType} node to ${activeWorkflow.name}.`
    );
  }

  function handleConnectNodes() {
    if (!activeWorkflow || !connectionFromNodeId || !connectionToNodeId) {
      return;
    }

    updateProject(
      (current) => connectWorkflowNodes(current, activeWorkflow.id, connectionFromNodeId, connectionToNodeId),
      "Connected workflow nodes."
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
                  </div>

                  <div className="listStack">
                    {activeWorkflow.nodes.map((node) => (
                      <div key={node.id} className="listCard">
                        <strong>{node.title || node.type}</strong>
                        <span>
                          {node.type} at ({Math.round(node.position.x)}, {Math.round(node.position.y)})
                        </span>
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
                          <strong>
                            {edge.fromNodeID.slice(0, 8)} {"->"} {edge.toNodeID.slice(0, 8)}
                          </strong>
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
