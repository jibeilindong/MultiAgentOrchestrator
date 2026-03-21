/// <reference types="vite/client" />

import type {
  ExecutionOutputType,
  MAProject,
  OpenClawConfig,
  OpenClawRuntimeEvent,
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

  interface OpenClawGovernanceFinding {
    id: string;
    title: string;
    status: "pass" | "fail" | "unknown";
    severity: "info" | "warning" | "error";
    summary: string;
    evidence: string[];
    remediable: boolean;
    remediationActionIds: string[];
  }

  interface OpenClawGovernanceAction {
    id: string;
    title: string;
    description: string;
    kind: "edit_openclaw_config" | "edit_exec_approvals" | "recreate_sandbox" | "manual_follow_up";
    targetPath: string | null;
    safeToAutoApply: boolean;
    requiresSandboxRecreate: boolean;
  }

  interface OpenClawGovernanceAuditReport {
    auditedAt: string;
    deploymentKind: string;
    findings: OpenClawGovernanceFinding[];
    proposedActions: OpenClawGovernanceAction[];
    residualRisks: string[];
    summary: {
      pass: number;
      fail: number;
      unknown: number;
      remediableFailCount: number;
    };
  }

  interface OpenClawGovernanceRemediationResult {
    report: OpenClawGovernanceAuditReport;
    appliedActionIds: string[];
    skippedActionIds: string[];
    notes: string[];
    backupPaths: string[];
  }

  interface OpenClawGovernanceRemediationRequest {
    config: OpenClawConfig;
    actionIds?: string[] | null;
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
      inspectOpenClawRuntimeSecurity(
        config: OpenClawConfig,
        agentIdentifiers: string[]
      ): Promise<OpenClawRuntimeSecurityInspectionResult>;
      auditOpenClawRuntimeGovernance(config: OpenClawConfig): Promise<OpenClawGovernanceAuditReport>;
      remediateOpenClawRuntimeGovernance(
        config: OpenClawConfig,
        actionIds?: string[] | null
      ): Promise<OpenClawGovernanceRemediationResult>;
    };
  }
}

export {};
