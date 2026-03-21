import type { MAProject } from "@multi-agent-flow/domain";
import { normalizeAgentName } from "./agent-naming";
import { stableStringify } from "./json";
import { createEmptyProject } from "./project-factory";
import { toSwiftDate } from "./swift-date";
import { normalizeWorkflowNodeTitle } from "./workflow-node-naming";

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringRecord(value: unknown): Record<string, string> {
  if (!isRecord(value)) {
    return {};
  }

  return Object.fromEntries(
    Object.entries(value).flatMap(([key, entry]) => (typeof entry === "string" ? [[key, entry]] : []))
  );
}

function createDefaultProtocolMemory(timestamp: number) {
  return {
    protocolVersion: "openclaw.runtime.v1",
    stableRules: [
      "Machine-readable workflow coordination must use the runtime protocol.",
      "Always end with exactly one valid routing JSON line when a machine tail is required.",
      "Only choose downstream targets from the allowed candidate list.",
      "Do not exceed the provided write scope, tool scope, or approval rules.",
      "If uncertain, emit the smallest valid safe result instead of guessing."
    ],
    recentCorrections: [],
    repeatOffenses: [],
    lastSessionDigest: null,
    lastUpdatedAt: timestamp
  };
}

function normalizeAgents(input: Partial<MAProject>, base: MAProject): MAProject["agents"] {
  const baseTimestamp = input.updatedAt ?? base.updatedAt;
  const fallbackProtocolMemory = createDefaultProtocolMemory(baseTimestamp);
  const nextAgents: MAProject["agents"] = [];

  for (const agent of input.agents ?? base.agents) {
    const rawOpenClawDefinition: Record<string, unknown> = isRecord(agent.openClawDefinition) ? agent.openClawDefinition : {};
    const protocolMemory = isRecord(rawOpenClawDefinition.protocolMemory)
      ? rawOpenClawDefinition.protocolMemory
      : fallbackProtocolMemory;
    const normalizedName = normalizeAgentName(nextAgents, typeof agent.name === "string" ? agent.name : "", {
      excludeAgentId: agent.id
    });

    nextAgents.push({
      ...agent,
      name: normalizedName,
      openClawDefinition: {
        agentIdentifier:
          typeof rawOpenClawDefinition["agentIdentifier"] === "string"
            ? rawOpenClawDefinition["agentIdentifier"] || normalizedName
            : normalizedName,
        modelIdentifier:
          typeof rawOpenClawDefinition["modelIdentifier"] === "string"
            ? rawOpenClawDefinition["modelIdentifier"]
            : "MiniMax-M2.5",
        runtimeProfile:
          typeof rawOpenClawDefinition["runtimeProfile"] === "string"
            ? rawOpenClawDefinition["runtimeProfile"]
            : "default",
        memoryBackupPath:
          typeof rawOpenClawDefinition.memoryBackupPath === "string"
            ? rawOpenClawDefinition.memoryBackupPath
            : null,
        soulSourcePath:
          typeof rawOpenClawDefinition.soulSourcePath === "string"
            ? rawOpenClawDefinition.soulSourcePath
            : null,
        environment: stringRecord(rawOpenClawDefinition.environment),
        protocolMemory: {
          ...fallbackProtocolMemory,
          ...protocolMemory,
          stableRules: Array.isArray(protocolMemory.stableRules)
            ? protocolMemory.stableRules.filter((value): value is string => typeof value === "string")
            : fallbackProtocolMemory.stableRules,
          recentCorrections: Array.isArray(protocolMemory.recentCorrections)
            ? protocolMemory.recentCorrections
            : fallbackProtocolMemory.recentCorrections,
          repeatOffenses: Array.isArray(protocolMemory.repeatOffenses)
            ? protocolMemory.repeatOffenses
            : fallbackProtocolMemory.repeatOffenses
          }
      }
    });
  }

  return nextAgents;
}

function normalizeWorkflows(
  input: Partial<MAProject>,
  base: MAProject,
  agents: MAProject["agents"]
): MAProject["workflows"] {
  const agentNameById = new Map(agents.map((agent) => [agent.id, agent.name] as const));

  return (input.workflows ?? base.workflows).map((workflow) => {
    const nextNodes = [...workflow.nodes];

    for (const [index, node] of workflow.nodes.entries()) {
      const fallbackFunctionDescription = node.agentID ? agentNameById.get(node.agentID) : undefined;
      const requestedTitle = (typeof node.title === "string" ? node.title.trim() : "") || fallbackFunctionDescription || "";
      nextNodes[index] = {
        ...node,
        title: normalizeWorkflowNodeTitle(
          {
            ...workflow,
            nodes: nextNodes
          },
          node.type,
          requestedTitle,
          {
            excludeNodeId: node.id,
            fallbackFunctionDescription
          }
        )
      };
    }

    return {
      ...workflow,
      nodes: nextNodes
    };
  });
}

export function normalizeProject(input: Partial<MAProject>): MAProject {
  const base = createEmptyProject(input.name ?? "Untitled Project");
  const openClawInput = isRecord(input.openClaw) ? input.openClaw : null;
  const openClawConfigInput = isRecord(openClawInput?.config) ? openClawInput.config : null;
  const openClawContainerInput = isRecord(openClawConfigInput?.container) ? openClawConfigInput.container : null;
  const taskDataInput = isRecord(input.taskData) ? input.taskData : null;
  const memoryDataInput = isRecord(input.memoryData) ? input.memoryData : null;
  const runtimeStateInput = isRecord(input.runtimeState) ? input.runtimeState : null;
  const agents = normalizeAgents(input, base);
  const workflows = normalizeWorkflows(input, base, agents);

  return {
    ...base,
    ...input,
    agents,
    workflows,
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
      agentStates: isRecord(runtimeStateInput?.agentStates) ? runtimeStateInput.agentStates : base.runtimeState.agentStates,
      runtimeEvents: Array.isArray(runtimeStateInput?.runtimeEvents)
        ? runtimeStateInput.runtimeEvents
        : base.runtimeState.runtimeEvents
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
