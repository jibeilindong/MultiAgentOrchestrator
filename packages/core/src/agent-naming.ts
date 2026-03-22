import type { Agent } from "@multi-agent-flow/domain";

const AGENT_NAME_SEPARATOR = "-";
const VALID_AGENT_NAME_PATTERN = /^([^-]+)-([^-]+)-([1-9]\d*)$/;
export const VALID_RUNTIME_AGENT_IDENTIFIER_PATTERN = /^[a-z0-9]+(?:[_-][a-z0-9]+)*$/;

interface AgentNameSegments {
  functionDescription: string;
  taskDomain: string;
  sequence: number | null;
}

interface NormalizeAgentNameOptions {
  excludeAgentId?: string;
  fallbackFunctionDescription?: string;
  fallbackTaskDomain?: string;
}

function normalizeDash(value: string): string {
  return value.replace(/[－—–]+/g, AGENT_NAME_SEPARATOR);
}

function normalizeWhitespace(value: string): string {
  return value.trim().replace(/\s+/g, " ");
}

function sanitizeAgentNameSegment(value: string, fallback: string): string {
  const normalized = normalizeWhitespace(normalizeDash(value).replace(/-/g, " "));
  return normalized || fallback;
}

function defaultAgentNameSegments(
  options: NormalizeAgentNameOptions = {}
): Omit<AgentNameSegments, "sequence"> {
  return {
    functionDescription: sanitizeAgentNameSegment(options.fallbackFunctionDescription ?? "", "功能描述"),
    taskDomain: sanitizeAgentNameSegment(options.fallbackTaskDomain ?? "", "任务领域")
  };
}

function parseRequestedAgentName(
  requestedName: string,
  options: NormalizeAgentNameOptions = {}
): AgentNameSegments {
  const defaults = defaultAgentNameSegments(options);
  const normalizedName = normalizeWhitespace(normalizeDash(requestedName));
  const parts = normalizedName
    .split(AGENT_NAME_SEPARATOR)
    .map((part) => normalizeWhitespace(part))
    .filter(Boolean);

  if (parts.length === 0) {
    return {
      ...defaults,
      sequence: null
    };
  }

  const lastPart = parts[parts.length - 1] ?? "";
  if (parts.length >= 3 && /^[1-9]\d*$/.test(lastPart)) {
    return {
      functionDescription: sanitizeAgentNameSegment(parts.slice(0, -2).join(" "), defaults.functionDescription),
      taskDomain: sanitizeAgentNameSegment(parts[parts.length - 2] ?? "", defaults.taskDomain),
      sequence: Number(lastPart)
    };
  }

  if (parts.length >= 2) {
    return {
      functionDescription: sanitizeAgentNameSegment(parts.slice(0, -1).join(" "), defaults.functionDescription),
      taskDomain: sanitizeAgentNameSegment(parts[parts.length - 1] ?? "", defaults.taskDomain),
      sequence: null
    };
  }

  return {
    functionDescription: sanitizeAgentNameSegment(parts[0] ?? "", defaults.functionDescription),
    taskDomain: defaults.taskDomain,
    sequence: null
  };
}

function parseExistingAgentName(name: string): AgentNameSegments | null {
  const match = normalizeWhitespace(normalizeDash(name)).match(VALID_AGENT_NAME_PATTERN);
  if (!match) {
    return null;
  }

  return {
    functionDescription: sanitizeAgentNameSegment(match[1], ""),
    taskDomain: sanitizeAgentNameSegment(match[2], ""),
    sequence: Number(match[3])
  };
}

function nextAgentNameSequence(
  agents: Agent[],
  functionDescription: string,
  taskDomain: string,
  excludeAgentId?: string,
  preferredSequence?: number | null
): number {
  const key = `${functionDescription.toLocaleLowerCase()}::${taskDomain.toLocaleLowerCase()}`;
  const usedSequences = new Set<number>();

  for (const agent of agents) {
    if (agent.id === excludeAgentId) {
      continue;
    }

    const parsed = parseExistingAgentName(agent.name);
    if (!parsed) {
      continue;
    }

    const agentKey = `${parsed.functionDescription.toLocaleLowerCase()}::${parsed.taskDomain.toLocaleLowerCase()}`;
    if (agentKey === key) {
      usedSequences.add(parsed.sequence ?? 0);
    }
  }

  if (preferredSequence && preferredSequence > 0 && !usedSequences.has(preferredSequence)) {
    return preferredSequence;
  }

  let sequence = 1;
  while (usedSequences.has(sequence)) {
    sequence += 1;
  }

  return sequence;
}

function normalizeRuntimeAgentIdentifierKey(value: string): string {
  return value.trim().toLowerCase();
}

function sanitizeRuntimeAgentIdentifierCandidate(value: string): string {
  const normalized = value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "-")
    .replace(/[-_]{2,}/g, "-")
    .replace(/^[-_]+|[-_]+$/g, "");

  if (!normalized) {
    return "";
  }

  return /[a-z]/.test(normalized) ? normalized : `agent-${normalized}`;
}

function nextRuntimeAgentIdentifier(
  agents: Agent[],
  baseIdentifier: string,
  excludeAgentId?: string
): string {
  const usedIdentifiers = new Set(
    agents
      .filter((agent) => agent.id !== excludeAgentId)
      .map((agent) => normalizeRuntimeAgentIdentifierKey(agent.openClawDefinition.agentIdentifier))
      .filter(Boolean)
  );

  let candidate = baseIdentifier;
  let suffix = 2;
  while (usedIdentifiers.has(normalizeRuntimeAgentIdentifierKey(candidate))) {
    candidate = `${baseIdentifier}-${suffix}`;
    suffix += 1;
  }

  return candidate;
}

export function isAgentNameValid(name: string): boolean {
  return VALID_AGENT_NAME_PATTERN.test(normalizeWhitespace(normalizeDash(name)));
}

export function isRuntimeAgentIdentifierValid(value: string): boolean {
  return VALID_RUNTIME_AGENT_IDENTIFIER_PATTERN.test(value.trim().toLowerCase());
}

export function normalizeRuntimeAgentIdentifier(
  agents: Agent[],
  requestedIdentifier: string,
  fallbackName: string,
  options: Pick<NormalizeAgentNameOptions, "excludeAgentId"> = {}
): string {
  const sanitizedRequestedIdentifier = sanitizeRuntimeAgentIdentifierCandidate(requestedIdentifier);
  const sanitizedFallbackIdentifier = sanitizeRuntimeAgentIdentifierCandidate(fallbackName);
  const baseIdentifier = sanitizedRequestedIdentifier || sanitizedFallbackIdentifier || "agent";
  return nextRuntimeAgentIdentifier(agents, baseIdentifier, options.excludeAgentId);
}

export function normalizeAgentName(
  agents: Agent[],
  requestedName: string,
  options: NormalizeAgentNameOptions = {}
): string {
  const rawName = normalizeWhitespace(requestedName) || normalizeWhitespace(options.fallbackFunctionDescription ?? "");
  const parsed = parseRequestedAgentName(rawName, options);
  const sequence = nextAgentNameSequence(
    agents,
    parsed.functionDescription,
    parsed.taskDomain,
    options.excludeAgentId,
    parsed.sequence
  );

  return `${parsed.functionDescription}${AGENT_NAME_SEPARATOR}${parsed.taskDomain}${AGENT_NAME_SEPARATOR}${sequence}`;
}
