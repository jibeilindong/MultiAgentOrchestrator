/// <reference types="vite/client" />

import type {
  ExecutionOutputType,
  MAProject,
  OpenClawConfig,
  ProjectOpenClawAgentRecord,
  ProjectOpenClawDetectedAgentRecord
} from "@multi-agent-flow/domain";

declare global {
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
  }

  interface Window {
    desktopApi?: {
      platform: string;
      versions: {
        chrome: string;
        electron: string;
        node: string;
      };
      createProject(name?: string): Promise<ProjectFileHandle>;
      openProject(): Promise<ProjectFileHandle | null>;
      openRecentProject(filePath: string): Promise<ProjectFileHandle>;
      listRecentProjects(): Promise<RecentProjectRecord[]>;
      saveProject(project: MAProject, filePath: string | null): Promise<ProjectFileHandle>;
      saveProjectAs(project: MAProject, filePath: string | null): Promise<ProjectFileHandle | null>;
      autosaveProject(project: MAProject): Promise<AutosaveResult>;
      chooseDirectory(defaultPath?: string | null): Promise<DirectorySelectionResult>;
      connectOpenClaw(config: OpenClawConfig): Promise<OpenClawActionResult>;
      detectOpenClawAgents(config: OpenClawConfig): Promise<OpenClawActionResult>;
      disconnectOpenClaw(): Promise<OpenClawActionResult>;
      executeOpenClawAgent(
        config: OpenClawConfig,
        request: OpenClawAgentExecutionRequest
      ): Promise<OpenClawAgentExecutionResult>;
    };
  }
}

export {};
