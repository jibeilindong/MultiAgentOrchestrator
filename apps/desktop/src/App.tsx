import { fromSwiftDate } from "@multi-agent-flow/core";
import type { MAProject } from "@multi-agent-flow/domain";
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
  const project = projectState?.project ?? null;
  const filePath = projectState?.filePath ?? null;

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
        const api = requireDesktopApi();
        const saved = await api.saveProjectAs(project, null);
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

  async function handleOpenRecentProject(filePath: string) {
    await runProjectAction("open", async () => {
      const opened = await requireDesktopApi().openRecentProject(filePath);
      startTransition(() => {
        setProjectState(opened);
        setStatus(`Opened ${opened.project.name} from recent projects.`);
      });
      await refreshRecentProjects();
    });
  }

  function handleProjectNameChange(nextName: string) {
    setProjectState((current) => {
      if (!current) {
        return current;
      }

      return {
        ...current,
        project: {
          ...current.project,
          name: nextName
        }
      };
    });
  }

  return (
    <main className="shell">
      <section className="hero">
        <p className="eyebrow">Cross-platform migration</p>
        <h1>Multi-Agent-Flow project shell</h1>
        <p className="lede">
          The new desktop shell can now create, open, save, and save-as `.maoproj` files while the
          migration moves persistent project logic into shared TypeScript packages.
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
          <h2>Next milestones</h2>
          <ol>
            <li>Project open/save bridge is now in place</li>
            <li>Recent projects and autosave are now wired in</li>
            <li>Next: move workflow editor state into the new shell</li>
          </ol>
        </article>
      </section>
    </main>
  );
}
