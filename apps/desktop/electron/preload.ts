import { contextBridge, ipcRenderer } from "electron";
import type {
  ExecutionOutputType,
  MAProject,
  OpenClawConfig,
  OpenClawRuntimeEvent,
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

interface OpenClawAgentExecutionRequest {
  agentIdentifier: string;
  message: string;
  sessionID?: string | null;
  thinkingLevel?: string | null;
  timeoutSeconds?: number | null;
  writeScope?: string[] | null;
  toolScope?: string[] | null;
  requiresApproval?: boolean | null;
  fallbackRoutingPolicy?: string | null;
}

interface OpenClawRoutingDecision {
  action: "stop" | "selected" | "all";
  targets: string[];
  reason: string | null;
}

interface OpenClawAgentExecutionResult {
  success: boolean;
  message: string;
  agentIdentifier: string;
  output: string;
  outputType: ExecutionOutputType;
  rawStdout: string;
  rawStderr: string;
  routingDecision: OpenClawRoutingDecision | null;
  runtimeEvents: OpenClawRuntimeEvent[];
  primaryRuntimeEvent: OpenClawRuntimeEvent | null;
}

interface OpenClawRuntimeSecurityFinding {
  agentIdentifier: string;
  sandboxMode: string;
  sessionIsSandboxed: boolean;
  allowedDangerousTools: string[];
  execToolAllowed: boolean;
  processToolAllowed: boolean;
  elevatedAllowedByConfig: boolean;
  elevatedAlwaysAllowedByConfig: boolean;
  blockingIssues: string[];
}

interface OpenClawRuntimeSecurityInspectionResult {
  blockingIssues: string[];
  findings: OpenClawRuntimeSecurityFinding[];
  approvalsHaveCustomEntries: boolean;
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
  },
  executeOpenClawAgent(config: OpenClawConfig, request: OpenClawAgentExecutionRequest): Promise<OpenClawAgentExecutionResult> {
    return ipcRenderer.invoke("openClaw:executeAgent", { config, request });
  },
  inspectOpenClawRuntimeSecurity(
    config: OpenClawConfig,
    agentIdentifiers: string[]
  ): Promise<OpenClawRuntimeSecurityInspectionResult> {
    return ipcRenderer.invoke("openClaw:inspectRuntimeSecurity", { config, agentIdentifiers });
  }
});
