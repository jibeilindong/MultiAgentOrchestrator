/// <reference types="vite/client" />

import type { MAProject } from "@multi-agent-flow/domain";

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
    };
  }
}

export {};
