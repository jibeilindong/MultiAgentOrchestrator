export interface OpenClawRuntimeSecurityFinding {
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

export interface OpenClawRuntimeSecurityInspectionResult {
  blockingIssues: string[];
  findings: OpenClawRuntimeSecurityFinding[];
  approvalsHaveCustomEntries: boolean;
}

function normalizedNonEmpty(value: string): string | null {
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function firstNonEmptyString(record: Record<string, unknown>, keys: string[]): string | null {
  for (const key of keys) {
    const value = record[key];
    if (typeof value === "string" && value.trim()) {
      return value.trim();
    }
  }
  return null;
}

function stringArray(value: unknown): string[] {
  if (Array.isArray(value)) {
    return value
      .flatMap((item) => {
        if (typeof item === "string") {
          return normalizedNonEmpty(item) ? [normalizedNonEmpty(item) as string] : [];
        }
        if (item && typeof item === "object") {
          const candidate = firstNonEmptyString(item as Record<string, unknown>, [
            "name",
            "agent",
            "agent_id",
            "id",
            "node",
            "target"
          ]);
          return candidate ? [candidate] : [];
        }
        return [];
      })
      .filter((item): item is string => typeof item === "string");
  }

  if (typeof value === "string") {
    return value
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean);
  }

  return [];
}

function extractJSONPayloads(text: string): string[] {
  const chars = Array.from(text);
  const payloads: string[] = [];

  for (let startIndex = 0; startIndex < chars.length; startIndex += 1) {
    const opening = chars[startIndex];
    if (opening !== "{" && opening !== "[") {
      continue;
    }

    const stack = [opening];
    let inString = false;
    let escaping = false;

    for (let index = startIndex + 1; index < chars.length; index += 1) {
      const char = chars[index];

      if (inString) {
        if (escaping) {
          escaping = false;
        } else if (char === "\\") {
          escaping = true;
        } else if (char === "\"") {
          inString = false;
        }
        continue;
      }

      if (char === "\"") {
        inString = true;
        continue;
      }

      if (char === "{" || char === "[") {
        stack.push(char);
        continue;
      }

      if (char !== "}" && char !== "]") {
        continue;
      }

      const last = stack.at(-1);
      const matched = (last === "{" && char === "}") || (last === "[" && char === "]");
      if (!matched) {
        break;
      }

      stack.pop();
      if (stack.length === 0) {
        payloads.push(chars.slice(startIndex, index + 1).join(""));
        break;
      }
    }
  }

  return payloads;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
}

function parseLastJSONObjectMatching(text: string, matcher: (record: Record<string, unknown>) => boolean): Record<string, unknown> | null {
  const payloads = extractJSONPayloads(text);
  for (let index = payloads.length - 1; index >= 0; index -= 1) {
    try {
      const parsed = JSON.parse(payloads[index]) as unknown;
      const record = asRecord(parsed);
      if (record && matcher(record)) {
        return record;
      }
    } catch {
      continue;
    }
  }

  return null;
}

export function parseOpenClawApprovalsSnapshotFromText(text: string): { hasCustomEntries: boolean } {
  const payload = parseLastJSONObjectMatching(text, (record) => "file" in record);
  if (!payload) {
    throw new Error("Failed to parse `openclaw approvals get --json` output.");
  }

  const fileRecord = asRecord(payload.file) ?? {};
  const defaults = asRecord(fileRecord.defaults);
  const agents = asRecord(fileRecord.agents);

  return {
    hasCustomEntries: Boolean((defaults && Object.keys(defaults).length > 0) || (agents && Object.keys(agents).length > 0))
  };
}

export function assessOpenClawSandboxSecurityFromText(
  text: string,
  agentIdentifier: string,
  approvalsHaveCustomEntries: boolean
): OpenClawRuntimeSecurityFinding {
  const payload = parseLastJSONObjectMatching(text, (record) => "sandbox" in record || "agentId" in record);
  if (!payload) {
    throw new Error("Failed to parse `openclaw sandbox explain --json` output.");
  }

  const sandbox = asRecord(payload.sandbox) ?? {};
  const tools = asRecord(sandbox.tools) ?? {};
  const elevated = asRecord(payload.elevated) ?? {};
  const allowedTools = new Set(stringArray(tools.allow).map((tool) => tool.toLowerCase()));
  const allowedDangerousTools = ["subagents", "sessions_send", "sessions_spawn"].filter((tool) =>
    allowedTools.has(tool)
  );
  const sandboxMode = normalizedNonEmpty(typeof sandbox.mode === "string" ? sandbox.mode : "unknown") ?? "unknown";
  const sessionIsSandboxed = sandbox.sessionIsSandboxed === true;
  const execToolAllowed = allowedTools.has("exec");
  const processToolAllowed = allowedTools.has("process");
  const elevatedAllowedByConfig = elevated.allowedByConfig === true;
  const elevatedAlwaysAllowedByConfig = elevated.alwaysAllowedByConfig === true;
  const blockingIssues: string[] = [];

  if (sandboxMode.toLowerCase() === "off" || !sessionIsSandboxed) {
    blockingIssues.push(
      `agent ${agentIdentifier} is not running inside an enforced OpenClaw sandbox, so the app cannot prevent it from creating side-channel sessions during execution.`
    );
  }

  if (allowedDangerousTools.length > 0) {
    blockingIssues.push(
      `agent ${agentIdentifier} is allowed high-risk session tools: ${allowedDangerousTools.join(", ")}. Disable them in the OpenClaw sandbox before running a multi-agent workflow.`
    );
  }

  if (approvalsHaveCustomEntries && (execToolAllowed || processToolAllowed)) {
    blockingIssues.push(
      `OpenClaw exec approvals contain custom allow rules while agent ${agentIdentifier} can still use ${
        execToolAllowed && processToolAllowed ? "exec/process" : execToolAllowed ? "exec" : "process"
      }; the app cannot prove it will not start extra agent/session processes on its own.`
    );
  }

  if (elevatedAllowedByConfig || elevatedAlwaysAllowedByConfig) {
    blockingIssues.push(
      `agent ${agentIdentifier} is allowed to use OpenClaw elevated execution, which can bypass app-layer orchestration constraints.`
    );
  }

  return {
    agentIdentifier,
    sandboxMode,
    sessionIsSandboxed,
    allowedDangerousTools,
    execToolAllowed,
    processToolAllowed,
    elevatedAllowedByConfig,
    elevatedAlwaysAllowedByConfig,
    blockingIssues
  };
}
