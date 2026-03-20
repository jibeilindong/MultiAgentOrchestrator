import type { MAProject } from "@multi-agent-flow/domain";
import { stableStringify } from "./json";
import { createEmptyProject } from "./project-factory";
import { toSwiftDate } from "./swift-date";

export function normalizeProject(input: Partial<MAProject>): MAProject {
  const base = createEmptyProject(input.name ?? "Untitled Project");

  return {
    ...base,
    ...input,
    agents: input.agents ?? base.agents,
    workflows: input.workflows ?? base.workflows,
    permissions: input.permissions ?? base.permissions,
    openClaw: input.openClaw ?? base.openClaw,
    taskData: input.taskData ?? base.taskData,
    tasks: input.tasks ?? base.tasks,
    messages: input.messages ?? base.messages,
    executionResults: input.executionResults ?? base.executionResults,
    executionLogs: input.executionLogs ?? base.executionLogs,
    workspaceIndex: input.workspaceIndex ?? base.workspaceIndex,
    memoryData: input.memoryData ?? base.memoryData,
    runtimeState: input.runtimeState ?? base.runtimeState
  };
}

export function parseProject(raw: string): MAProject {
  return normalizeProject(JSON.parse(raw) as Partial<MAProject>);
}

export function serializeProject(project: MAProject): string {
  return stableStringify(project);
}

export function prepareProjectForSave(project: MAProject): MAProject {
  const now = toSwiftDate();

  return normalizeProject({
    ...project,
    updatedAt: now
  });
}

export function projectFileName(project: Pick<MAProject, "name">): string {
  const trimmed = project.name.trim();
  const safeName = trimmed.length > 0 ? trimmed : "Untitled Project";
  return `${safeName}.maoproj`;
}
