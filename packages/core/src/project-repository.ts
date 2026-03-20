import type { MAProject } from "@multi-agent-flow/domain";
import { stableStringify } from "./json";
import { createEmptyProject } from "./project-factory";
import { toSwiftDate } from "./swift-date";

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function normalizeProject(input: Partial<MAProject>): MAProject {
  const base = createEmptyProject(input.name ?? "Untitled Project");
  const openClawInput = isRecord(input.openClaw) ? input.openClaw : null;
  const openClawConfigInput = isRecord(openClawInput?.config) ? openClawInput.config : null;
  const openClawContainerInput = isRecord(openClawConfigInput?.container) ? openClawConfigInput.container : null;
  const taskDataInput = isRecord(input.taskData) ? input.taskData : null;
  const memoryDataInput = isRecord(input.memoryData) ? input.memoryData : null;
  const runtimeStateInput = isRecord(input.runtimeState) ? input.runtimeState : null;

  return {
    ...base,
    ...input,
    agents: input.agents ?? base.agents,
    workflows: input.workflows ?? base.workflows,
    permissions: input.permissions ?? base.permissions,
    openClaw: {
      ...base.openClaw,
      ...(openClawInput ?? {}),
      config: {
        ...base.openClaw.config,
        ...(openClawConfigInput ?? {}),
        container: {
          ...base.openClaw.config.container,
          ...(openClawContainerInput ?? {})
        }
      },
      availableAgents: Array.isArray(openClawInput?.availableAgents)
        ? openClawInput.availableAgents
        : base.openClaw.availableAgents,
      activeAgents: Array.isArray(openClawInput?.activeAgents) ? openClawInput.activeAgents : base.openClaw.activeAgents,
      detectedAgents: Array.isArray(openClawInput?.detectedAgents)
        ? openClawInput.detectedAgents
        : base.openClaw.detectedAgents
    },
    taskData: {
      ...base.taskData,
      ...(taskDataInput ?? {})
    },
    tasks: input.tasks ?? base.tasks,
    messages: input.messages ?? base.messages,
    executionResults: input.executionResults ?? base.executionResults,
    executionLogs: input.executionLogs ?? base.executionLogs,
    workspaceIndex: input.workspaceIndex ?? base.workspaceIndex,
    memoryData: {
      ...base.memoryData,
      ...(memoryDataInput ?? {}),
      taskExecutionMemories: Array.isArray(memoryDataInput?.taskExecutionMemories)
        ? memoryDataInput.taskExecutionMemories
        : base.memoryData.taskExecutionMemories,
      agentMemories: Array.isArray(memoryDataInput?.agentMemories)
        ? memoryDataInput.agentMemories
        : base.memoryData.agentMemories
    },
    runtimeState: {
      ...base.runtimeState,
      ...(runtimeStateInput ?? {}),
      messageQueue: Array.isArray(runtimeStateInput?.messageQueue)
        ? runtimeStateInput.messageQueue
        : base.runtimeState.messageQueue,
      agentStates: isRecord(runtimeStateInput?.agentStates) ? runtimeStateInput.agentStates : base.runtimeState.agentStates
    }
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
