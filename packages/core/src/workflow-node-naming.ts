import type { Workflow, WorkflowNodeType } from "@multi-agent-flow/domain";

const NODE_TITLE_SEPARATOR = "-";
const VALID_NODE_TITLE_PATTERN = /^([^-]+)-([^-]+)-([1-9]\d*)$/;

interface NodeTitleSegments {
  functionDescription: string;
  taskDomain: string;
  sequence: number | null;
}

interface NormalizeWorkflowNodeTitleOptions {
  excludeNodeId?: string;
  fallbackFunctionDescription?: string;
  fallbackTaskDomain?: string;
}

function normalizeDash(value: string): string {
  return value.replace(/[－—–]+/g, NODE_TITLE_SEPARATOR);
}

function normalizeWhitespace(value: string): string {
  return value.trim().replace(/\s+/g, " ");
}

function sanitizeNodeTitleSegment(value: string, fallback: string): string {
  const normalized = normalizeWhitespace(normalizeDash(value).replace(/-/g, " "));
  return normalized || fallback;
}

function defaultNodeTitleSegments(
  nodeType: WorkflowNodeType,
  options: NormalizeWorkflowNodeTitleOptions = {}
): Omit<NodeTitleSegments, "sequence"> {
  const defaultFunctionDescription = nodeType === "start" ? "开始" : "功能描述";
  const defaultTaskDomain = nodeType === "start" ? "工作流" : "任务领域";

  return {
    functionDescription: sanitizeNodeTitleSegment(
      options.fallbackFunctionDescription ?? "",
      defaultFunctionDescription
    ),
    taskDomain: sanitizeNodeTitleSegment(options.fallbackTaskDomain ?? "", defaultTaskDomain)
  };
}

function parseRequestedNodeTitle(
  requestedTitle: string,
  nodeType: WorkflowNodeType,
  options: NormalizeWorkflowNodeTitleOptions = {}
): NodeTitleSegments {
  const defaults = defaultNodeTitleSegments(nodeType, options);
  const normalizedTitle = normalizeWhitespace(normalizeDash(requestedTitle));
  const parts = normalizedTitle
    .split(NODE_TITLE_SEPARATOR)
    .map((part) => normalizeWhitespace(part))
    .filter(Boolean);

  if (parts.length === 0) {
    return {
      ...defaults,
      sequence: null
    };
  }

  const lastPart = parts[parts.length - 1] ?? "";
  const hasExplicitSequence = parts.length >= 3 && /^[1-9]\d*$/.test(lastPart);
  if (hasExplicitSequence) {
    const functionParts = parts.slice(0, -2);
    const taskDomain = sanitizeNodeTitleSegment(parts[parts.length - 2] ?? "", defaults.taskDomain);
    return {
      functionDescription: sanitizeNodeTitleSegment(functionParts.join(" "), defaults.functionDescription),
      taskDomain,
      sequence: Number(lastPart)
    };
  }

  if (parts.length >= 2) {
    return {
      functionDescription: sanitizeNodeTitleSegment(parts.slice(0, -1).join(" "), defaults.functionDescription),
      taskDomain: sanitizeNodeTitleSegment(parts[parts.length - 1] ?? "", defaults.taskDomain),
      sequence: null
    };
  }

  return {
    functionDescription: sanitizeNodeTitleSegment(parts[0] ?? "", defaults.functionDescription),
    taskDomain: defaults.taskDomain,
    sequence: null
  };
}

function parseExistingNodeTitle(title: string): NodeTitleSegments | null {
  const match = normalizeWhitespace(normalizeDash(title)).match(VALID_NODE_TITLE_PATTERN);
  if (!match) {
    return null;
  }

  return {
    functionDescription: sanitizeNodeTitleSegment(match[1], ""),
    taskDomain: sanitizeNodeTitleSegment(match[2], ""),
    sequence: Number(match[3])
  };
}

function nextWorkflowNodeSequence(
  workflow: Workflow,
  functionDescription: string,
  taskDomain: string,
  excludeNodeId?: string,
  preferredSequence?: number | null
): number {
  const key = `${functionDescription.toLocaleLowerCase()}::${taskDomain.toLocaleLowerCase()}`;
  const usedSequences = new Set<number>();

  for (const node of workflow.nodes) {
    if (node.id === excludeNodeId) {
      continue;
    }

    const parsed = parseExistingNodeTitle(node.title);
    if (!parsed) {
      continue;
    }

    const nodeKey = `${parsed.functionDescription.toLocaleLowerCase()}::${parsed.taskDomain.toLocaleLowerCase()}`;
    if (nodeKey === key) {
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

export function isWorkflowNodeTitleValid(title: string): boolean {
  return VALID_NODE_TITLE_PATTERN.test(normalizeWhitespace(normalizeDash(title)));
}

export function normalizeWorkflowNodeTitle(
  workflow: Workflow,
  nodeType: WorkflowNodeType,
  requestedTitle: string,
  options: NormalizeWorkflowNodeTitleOptions = {}
): string {
  const rawTitle = normalizeWhitespace(requestedTitle) || normalizeWhitespace(options.fallbackFunctionDescription ?? "");
  const parsed = parseRequestedNodeTitle(rawTitle, nodeType, options);
  const sequence = nextWorkflowNodeSequence(
    workflow,
    parsed.functionDescription,
    parsed.taskDomain,
    options.excludeNodeId,
    parsed.sequence
  );

  return `${parsed.functionDescription}${NODE_TITLE_SEPARATOR}${parsed.taskDomain}${NODE_TITLE_SEPARATOR}${sequence}`;
}
