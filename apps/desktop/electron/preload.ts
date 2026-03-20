import { contextBridge, ipcRenderer } from "electron";
import type { MAProject } from "@multi-agent-flow/domain";

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

contextBridge.exposeInMainWorld("desktopApi", {
  platform: process.platform,
  versions: {
    chrome: process.versions.chrome,
    electron: process.versions.electron,
    node: process.versions.node
  },
  createProject(name?: string): Promise<ProjectFileHandle> {
    return ipcRenderer.invoke("project:create", name);
  },
  openProject(): Promise<ProjectFileHandle | null> {
    return ipcRenderer.invoke("project:open");
  },
  openRecentProject(filePath: string): Promise<ProjectFileHandle> {
    return ipcRenderer.invoke("project:openRecent", filePath);
  },
  listRecentProjects(): Promise<RecentProjectRecord[]> {
    return ipcRenderer.invoke("project:listRecent");
  },
  saveProject(project: MAProject, filePath: string | null): Promise<ProjectFileHandle> {
    return ipcRenderer.invoke("project:save", { project, filePath });
  },
  saveProjectAs(project: MAProject, filePath: string | null): Promise<ProjectFileHandle | null> {
    return ipcRenderer.invoke("project:saveAs", { project, filePath });
  },
  autosaveProject(project: MAProject): Promise<AutosaveResult> {
    return ipcRenderer.invoke("project:autosave", project);
  }
});
