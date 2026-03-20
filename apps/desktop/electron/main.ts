import path from "node:path";
import { promises as fs } from "node:fs";
import { app, BrowserWindow, dialog, ipcMain } from "electron";
import {
  createEmptyProject,
  parseProject,
  prepareProjectForSave,
  projectFileName,
  serializeProject
} from "@multi-agent-flow/core";
import type { MAProject } from "@multi-agent-flow/domain";

const PROJECT_EXTENSION = "maoproj";
const PROJECT_FILTERS = [{ name: "Multi-Agent-Flow Project", extensions: [PROJECT_EXTENSION] }];
const APP_DOCUMENTS_DIR = "Multi-Agent-Flow";
const APP_AUTOSAVE_DIR = "AutoSave";
const RECENT_PROJECTS_FILE = "recent-projects.json";

interface ProjectFileHandle {
  project: MAProject;
  filePath: string | null;
}

interface RecentProjectRecord {
  name: string;
  filePath: string;
  updatedAt: string;
}

interface AutosaveResult {
  autosavePath: string;
  savedAt: string;
}

function getDefaultProjectsDirectory(): string {
  return path.join(app.getPath("documents"), APP_DOCUMENTS_DIR);
}

async function ensureProjectsDirectory(): Promise<string> {
  const directory = getDefaultProjectsDirectory();
  await fs.mkdir(directory, { recursive: true });
  return directory;
}

async function ensureAutosaveDirectory(): Promise<string> {
  const directory = path.join(app.getPath("userData"), APP_AUTOSAVE_DIR);
  await fs.mkdir(directory, { recursive: true });
  return directory;
}

function getRecentProjectsFilePath(): string {
  return path.join(app.getPath("userData"), RECENT_PROJECTS_FILE);
}

async function loadRecentProjects(): Promise<RecentProjectRecord[]> {
  try {
    const raw = await fs.readFile(getRecentProjectsFilePath(), "utf8");
    const parsed = JSON.parse(raw) as RecentProjectRecord[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

async function saveRecentProjects(entries: RecentProjectRecord[]): Promise<void> {
  await fs.mkdir(app.getPath("userData"), { recursive: true });
  await fs.writeFile(getRecentProjectsFilePath(), JSON.stringify(entries, null, 2), "utf8");
}

async function rememberRecentProject(project: MAProject, filePath: string): Promise<void> {
  const current = await loadRecentProjects();
  const nextEntry: RecentProjectRecord = {
    name: project.name,
    filePath,
    updatedAt: new Date().toISOString()
  };

  const deduped = current.filter((entry) => entry.filePath !== filePath);
  deduped.unshift(nextEntry);
  await saveRecentProjects(deduped.slice(0, 10));
}

async function readProjectFromFile(filePath: string): Promise<ProjectFileHandle> {
  const raw = await fs.readFile(filePath, "utf8");
  const handle = {
    project: parseProject(raw),
    filePath
  };
  await rememberRecentProject(handle.project, filePath);
  return handle;
}

async function writeProjectToFile(project: MAProject, filePath: string): Promise<ProjectFileHandle> {
  const normalized = prepareProjectForSave(project);
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, serializeProject(normalized), "utf8");
  await rememberRecentProject(normalized, filePath);

  return {
    project: normalized,
    filePath
  };
}

async function writeProjectAutosave(project: MAProject): Promise<AutosaveResult> {
  const normalized = prepareProjectForSave(project);
  const autosaveDirectory = await ensureAutosaveDirectory();
  const autosavePath = path.join(
    autosaveDirectory,
    `autosave_${normalized.id.split("-")[0] || normalized.id}.maoproj`
  );
  await fs.writeFile(autosavePath, serializeProject(normalized), "utf8");

  return {
    autosavePath,
    savedAt: new Date().toISOString()
  };
}

async function promptForOpenPath(window: BrowserWindow): Promise<string | null> {
  const defaultDirectory = await ensureProjectsDirectory();
  const result = await dialog.showOpenDialog(window, {
    title: "Open Project",
    properties: ["openFile"],
    defaultPath: defaultDirectory,
    filters: PROJECT_FILTERS
  });

  if (result.canceled) {
    return null;
  }

  return result.filePaths[0] ?? null;
}

async function promptForSavePath(window: BrowserWindow, project: MAProject, filePath: string | null): Promise<string | null> {
  const defaultDirectory = await ensureProjectsDirectory();
  const result = await dialog.showSaveDialog(window, {
    title: "Save Project",
    defaultPath: filePath ?? path.join(defaultDirectory, projectFileName(project)),
    filters: PROJECT_FILTERS
  });

  if (result.canceled) {
    return null;
  }

  const resolvedPath = result.filePath;
  if (!resolvedPath) {
    return null;
  }

  return resolvedPath.endsWith(`.${PROJECT_EXTENSION}`) ? resolvedPath : `${resolvedPath}.${PROJECT_EXTENSION}`;
}

function createWindow(): BrowserWindow {
  const window = new BrowserWindow({
    width: 1360,
    height: 880,
    minWidth: 1024,
    minHeight: 680,
    title: "Multi-Agent-Flow",
    webPreferences: {
      preload: path.join(__dirname, "../preload/preload.mjs"),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  if (process.env.VITE_DEV_SERVER_URL) {
    void window.loadURL(process.env.VITE_DEV_SERVER_URL);
  } else {
    void window.loadFile(path.join(__dirname, "../renderer/index.html"));
  }

  return window;
}

function registerProjectIpcHandlers() {
  ipcMain.handle("project:create", async (_event, name?: string): Promise<ProjectFileHandle> => {
    return {
      project: createEmptyProject(name?.trim() || "Untitled Project"),
      filePath: null
    };
  });

  ipcMain.handle("project:open", async (event): Promise<ProjectFileHandle | null> => {
    const window = BrowserWindow.fromWebContents(event.sender);
    if (!window) {
      throw new Error("Unable to resolve window for open dialog.");
    }

    const filePath = await promptForOpenPath(window);
    if (!filePath) {
      return null;
    }

    return readProjectFromFile(filePath);
  });

  ipcMain.handle("project:openRecent", async (_event, filePath: string): Promise<ProjectFileHandle> => {
    return readProjectFromFile(filePath);
  });

  ipcMain.handle("project:listRecent", async (): Promise<RecentProjectRecord[]> => {
    const entries = await loadRecentProjects();
    const checks = await Promise.all(
      entries.map(async (entry) => {
        try {
          await fs.access(entry.filePath);
          return entry;
        } catch {
          return null;
        }
      })
    );

    const validEntries = checks.filter((entry): entry is RecentProjectRecord => entry !== null);
    if (validEntries.length !== entries.length) {
      await saveRecentProjects(validEntries);
    }

    return validEntries;
  });

  ipcMain.handle(
    "project:save",
    async (_event, payload: { project: MAProject; filePath: string | null }): Promise<ProjectFileHandle> => {
      if (payload.filePath) {
      return writeProjectToFile(payload.project, payload.filePath);
    }

      throw new Error("Save requires an existing file path. Use Save As for unsaved projects.");
    }
  );

  ipcMain.handle(
    "project:saveAs",
    async (event, payload: { project: MAProject; filePath: string | null }): Promise<ProjectFileHandle | null> => {
      const window = BrowserWindow.fromWebContents(event.sender);
      if (!window) {
        throw new Error("Unable to resolve window for save dialog.");
      }

      const nextPath = await promptForSavePath(window, payload.project, payload.filePath);
      if (!nextPath) {
        return null;
      }

      return writeProjectToFile(payload.project, nextPath);
    }
  );

  ipcMain.handle("project:autosave", async (_event, project: MAProject): Promise<AutosaveResult> => {
    return writeProjectAutosave(project);
  });
}

app.whenReady().then(() => {
  registerProjectIpcHandlers();
  createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});
