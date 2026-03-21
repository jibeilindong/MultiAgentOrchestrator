import type { Agent, MAProject, Workflow } from "@multi-agent-flow/domain";

export interface WorkflowRuntimeIsolationAssessment {
  workflowAgents: Agent[];
  missingWorkspaceAgents: Agent[];
  workspaceConflicts: Array<{
    normalizedPath: string;
    displayPath: string;
    agents: Agent[];
  }>;
  blockingFindings: string[];
}

function normalizeAgentKey(value: string): string {
  return value.trim().toLowerCase();
}

function trimPath(value: string | null | undefined): string {
  return value?.trim() ?? "";
}

function uniqueSorted(values: Iterable<string>): string[] {
  return Array.from(new Set(Array.from(values).map((value) => value.trim()).filter(Boolean))).sort((left, right) =>
    left.localeCompare(right)
  );
}

function parentPath(path: string): string | null {
  const trimmed = trimPath(path).replace(/[\\/]+$/, "");
  if (!trimmed) {
    return null;
  }

  const separatorIndex = Math.max(trimmed.lastIndexOf("/"), trimmed.lastIndexOf("\\"));
  if (separatorIndex <= 0) {
    return null;
  }

  return trimmed.slice(0, separatorIndex);
}

function joinPath(basePath: string, child: string): string {
  const trimmedBase = trimPath(basePath).replace(/[\\/]+$/, "");
  if (!trimmedBase) {
    return child;
  }

  const separator = trimmedBase.includes("\\") && !trimmedBase.includes("/") ? "\\" : "/";
  return `${trimmedBase}${separator}${child}`;
}

function derivedWorkspacePathFromMemoryBackup(memoryBackupPath: string | null | undefined): string | null {
  const trimmed = trimPath(memoryBackupPath);
  if (!trimmed) {
    return null;
  }

  const normalized = trimmed.replace(/[\\/]+$/, "");
  const trailingSegment = normalized.split(/[\\/]/).pop()?.toLowerCase() ?? "";
  const rootPath = trailingSegment === "private" ? parentPath(normalized) : normalized;
  if (!rootPath) {
    return null;
  }

  return joinPath(rootPath, "workspace");
}

function normalizeWorkspacePath(path: string): string {
  return trimPath(path).replace(/\\/g, "/").replace(/\/+/g, "/").replace(/\/$/, "").toLowerCase();
}

export function resolveProjectAgentWorkspacePaths(project: MAProject, agent: Agent): string[] {
  const matchKeys = new Set(
    [agent.name, agent.openClawDefinition.agentIdentifier].map((value) => normalizeAgentKey(value)).filter(Boolean)
  );
  const detectedMatches = project.openClaw.detectedAgents.filter((record) => matchKeys.has(normalizeAgentKey(record.name)));

  const candidatePaths = [
    derivedWorkspacePathFromMemoryBackup(agent.openClawDefinition.memoryBackupPath),
    ...detectedMatches.flatMap((record) => [
      trimPath(record.workspacePath),
      trimPath(record.copiedToProjectPath) ? joinPath(trimPath(record.copiedToProjectPath), "workspace") : "",
      trimPath(record.directoryPath),
      trimPath(record.copiedToProjectPath)
    ])
  ];

  return uniqueSorted(candidatePaths.filter((value): value is string => Boolean(value)));
}

function uniqueWorkflowAgents(project: MAProject, workflow: Workflow): Agent[] {
  const agentById = new Map(project.agents.map((agent) => [agent.id, agent] as const));
  const seen = new Set<string>();
  const agents: Agent[] = [];

  for (const node of workflow.nodes) {
    if (node.type !== "agent" || !node.agentID || seen.has(node.agentID)) {
      continue;
    }
    const agent = agentById.get(node.agentID);
    if (!agent) {
      continue;
    }
    seen.add(node.agentID);
    agents.push(agent);
  }

  return agents;
}

export function assessWorkflowRuntimeIsolation(project: MAProject, workflow: Workflow): WorkflowRuntimeIsolationAssessment {
  const workflowAgents = uniqueWorkflowAgents(project, workflow);
  const resolvedWorkspaceByAgentId = new Map<string, string>();
  const missingWorkspaceAgents: Agent[] = [];

  for (const agent of workflowAgents) {
    const resolvedPath = resolveProjectAgentWorkspacePaths(project, agent)[0] ?? "";
    if (!resolvedPath) {
      missingWorkspaceAgents.push(agent);
      continue;
    }
    resolvedWorkspaceByAgentId.set(agent.id, resolvedPath);
  }

  const agentsByWorkspace = new Map<string, { displayPath: string; agents: Agent[] }>();
  for (const agent of workflowAgents) {
    const displayPath = resolvedWorkspaceByAgentId.get(agent.id);
    if (!displayPath) {
      continue;
    }

    const normalizedPath = normalizeWorkspacePath(displayPath);
    const existing = agentsByWorkspace.get(normalizedPath);
    if (existing) {
      existing.agents.push(agent);
      continue;
    }

    agentsByWorkspace.set(normalizedPath, {
      displayPath,
      agents: [agent]
    });
  }

  const workspaceConflicts = Array.from(agentsByWorkspace.entries())
    .filter(([, entry]) => entry.agents.length > 1)
    .map(([normalizedPath, entry]) => ({
      normalizedPath,
      displayPath: entry.displayPath,
      agents: [...entry.agents].sort((left, right) => left.name.localeCompare(right.name))
    }))
    .sort((left, right) => left.displayPath.localeCompare(right.displayPath));

  const blockingFindings: string[] = [];
  if (missingWorkspaceAgents.length > 0) {
    blockingFindings.push(
      `The following agent(s) do not have an isolated workspace path resolved: ${missingWorkspaceAgents
        .map((agent) => agent.name)
        .sort((left, right) => left.localeCompare(right))
        .join(", ")}.`
    );
  }

  if (workspaceConflicts.length > 0) {
    blockingFindings.push(
      `Detected shared agent workspaces: ${workspaceConflicts
        .map((conflict) => `${conflict.agents.map((agent) => agent.name).join(" / ")} -> ${conflict.displayPath}`)
        .join("; ")}.`
    );
  }

  if (project.openClaw.config.deploymentKind === "remoteServer" && workflowAgents.length > 1) {
    blockingFindings.push(
      "remoteServer mode cannot currently enforce Multi-Agent-Flow runtime isolation for multi-agent workflows. Switch to local/container deployment or reduce the workflow to a single runnable agent."
    );
  }

  return {
    workflowAgents,
    missingWorkspaceAgents,
    workspaceConflicts,
    blockingFindings
  };
}
