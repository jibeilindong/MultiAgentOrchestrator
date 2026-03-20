import { contextBridge, ipcRenderer } from "electron";
import type {
  MAProject,
  OpenClawConfig,
  ProjectOpenClawAgentRecord,
  ProjectOpenClawDetectedAgentRecord
} from "@multi-agent-flow/domain";

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

interface DirectorySelectionResult {
  directoryPath: string | null;
}

interface OpenClawActionResult {
  success: boolean;
  message: string;
  isConnected: boolean;
  availableAgents: string[];
  activeAgents: ProjectOpenClawAgentRecord[];
  detectedAgents: ProjectOpenClawDetectedAgentRecord[];
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
  },
  chooseDirectory(defaultPath?: string | null): Promise<DirectorySelectionResult> {
    return ipcRenderer.invoke("project:chooseDirectory", defaultPath);
  },
  connectOpenClaw(config: OpenClawConfig): Promise<OpenClawActionResult> {
    return ipcRenderer.invoke("openClaw:connect", config);
  },
  detectOpenClawAgents(config: OpenClawConfig): Promise<OpenClawActionResult> {
    return ipcRenderer.invoke("openClaw:detect", config);
  },
  disconnectOpenClaw(): Promise<OpenClawActionResult> {
    return ipcRenderer.invoke("openClaw:disconnect");
  }
});
