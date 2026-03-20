import path from "node:path";
import os from "node:os";
import { execFile } from "node:child_process";
import { existsSync, promises as fs } from "node:fs";
import { promisify } from "node:util";
import { app, BrowserWindow, dialog, ipcMain } from "electron";
import {
  createEmptyProject,
  parseProject,
  prepareProjectForSave,
  projectFileName,
  serializeProject,
  toSwiftDate
} from "@multi-agent-flow/core";
import type {
  ExecutionOutputType,
  MAProject,
  OpenClawConfig,
  OpenClawRuntimeEvent,
  OpenClawRuntimeRouteAction,
  ProjectOpenClawAgentRecord,
  ProjectOpenClawDetectedAgentRecord
} from "@multi-agent-flow/domain";

const PROJECT_EXTENSION = "maoproj";
const PROJECT_FILTERS = [{ name: "Multi-Agent-Flow Project", extensions: [PROJECT_EXTENSION] }];
const APP_DOCUMENTS_DIR = "Multi-Agent-Flow";
const APP_AUTOSAVE_DIR = "AutoSave";
const RECENT_PROJECTS_FILE = "recent-projects.json";
const APP_ID = "com.multiagentflow.desktop";
const execFileAsync = promisify(execFile);
const OPENCLAW_LOCAL_PATH_CANDIDATES =
  process.platform === "win32"
    ? [
        path.join(os.homedir(), ".local", "bin", "openclaw.exe"),
        path.join(os.homedir(), "AppData", "Local", "Programs", "OpenClaw", "openclaw.exe"),
        "openclaw.exe"
      ]
    : [
        path.join(os.homedir(), ".local", "bin", "openclaw"),
        "/usr/local/bin/openclaw",
        "/opt/homebrew/bin/openclaw",
        "/usr/bin/openclaw",
        "openclaw"
      ];

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
  runtimeEvents: OpenClawRuntimeEvent[];
  primaryRuntimeEvent: OpenClawRuntimeEvent | null;
}

interface DirectoryInspection {
  name: string;
  path: string;
  workspacePath: string | null;
  statePath: string | null;
  hasSoulFile: boolean;
}

function runtimeTimestamp(): string {
  return new Date().toISOString();
}

function createRuntimeActor(agentId: string, agentName?: string | null) {
  return {
    kind: "agent" as const,
    agentId,
    agentName: agentName ?? null
  };
}

function createSystemActor(kind: "system" | "orchestrator", agentId: string) {
  return {
    kind,
    agentId,
    agentName: agentId
  };
}

function createExecutionTransport(config: OpenClawConfig, request: OpenClawAgentExecutionRequest) {
  return {
    kind: config.deploymentKind === "remoteServer" ? (trimmedString(request.sessionID) ? "gateway_chat" : "gateway_agent") : "cli",
    deploymentKind: config.deploymentKind
  } as const;
}

function createRuntimeEvent(input: {
  eventType: OpenClawRuntimeEvent["eventType"];
  source: OpenClawRuntimeEvent["source"];
  target: OpenClawRuntimeEvent["target"];
  transport: OpenClawRuntimeEvent["transport"];
  payload: OpenClawRuntimeEvent["payload"];
  runId?: string | null;
  sessionKey?: string | null;
  refs?: OpenClawRuntimeEvent["refs"];
  constraints?: OpenClawRuntimeEvent["constraints"];
  control?: OpenClawRuntimeEvent["control"];
  parentEventId?: string | null;
  idempotencyKey?: string | null;
}): OpenClawRuntimeEvent {
  return {
    version: "openclaw.runtime.v1",
    eventId: crypto.randomUUID(),
    eventType: input.eventType,
    timestamp: runtimeTimestamp(),
    projectId: null,
    workflowId: null,
    nodeId: null,
    runId: input.runId ?? null,
    sessionKey: input.sessionKey ?? null,
    parentEventId: input.parentEventId ?? null,
    idempotencyKey: input.idempotencyKey ?? null,
    attempt: 1,
    source: input.source,
    target: input.target,
    transport: input.transport,
    payload: input.payload,
    refs: input.refs ?? [],
    constraints: input.constraints ?? {},
    control: input.control ?? {},
    integrity: null
  };
}

function routeActionValue(action: OpenClawRoutingDecision["action"]): OpenClawRuntimeRouteAction {
  switch (action) {
    case "all":
      return "all";
    case "selected":
      return "selected";
    default:
      return "stop";
  }
}

function buildRuntimeEventsForExecution(
  config: OpenClawConfig,
  request: OpenClawAgentExecutionRequest,
  result: {
    success: boolean;
    message: string;
    agentIdentifier: string;
    output: string;
    outputType: ExecutionOutputType;
    routingDecision: OpenClawRoutingDecision | null;
  }
): { runtimeEvents: OpenClawRuntimeEvent[]; primaryRuntimeEvent: OpenClawRuntimeEvent | null } {
  const transport = createExecutionTransport(config, request);
  const idempotencyKey = crypto.randomUUID();
  const sessionKey = trimmedString(request.sessionID) || null;
  const dispatchEvent = createRuntimeEvent({
    eventType: "task.dispatch",
    source: createSystemActor("orchestrator", "openclaw.executeAgent"),
    target: createRuntimeActor(result.agentIdentifier, result.agentIdentifier),
    transport,
    sessionKey,
    idempotencyKey,
    payload: {
      intent: "respond",
      summary: trimmedString(request.message) || "execute agent request",
      inputRefIds: [],
      expectedOutput: result.outputType,
      visibleToUser: true
    },
    constraints: {
      timeoutSeconds: request.timeoutSeconds ?? config.timeout ?? null,
      thinkingLevel: trimmedString(request.thinkingLevel) || null
    },
    control: {
      requiresApproval: false,
      fallbackRoutingPolicy: "stop",
      allowRetry: true,
      maxRetries: 1,
      priority: "medium"
    }
  });

  const resultEvent = createRuntimeEvent({
    eventType: result.success ? "task.result" : "task.error",
    source: createRuntimeActor(result.agentIdentifier, result.agentIdentifier),
    target: createSystemActor("orchestrator", "openclaw.executeAgent"),
    transport,
    sessionKey,
    idempotencyKey,
    parentEventId: dispatchEvent.eventId,
    payload: result.success
      ? {
          status: "success",
          outputType: result.outputType,
          summary: trimmedString(result.output) || trimmedString(result.message) || "execution completed",
          artifactRefIds: []
        }
      : {
          code: "E_AGENT_EXECUTION_FAILED",
          message: trimmedString(result.message) || "OpenClaw agent execution failed.",
          retryable: false,
          detailsRef: null
        }
  });

  const routeEvent =
    result.routingDecision == null
      ? null
      : createRuntimeEvent({
          eventType: "task.route",
          source: createRuntimeActor(result.agentIdentifier, result.agentIdentifier),
          target: createSystemActor("orchestrator", "openclaw.router"),
          transport,
          sessionKey,
          idempotencyKey,
          parentEventId: resultEvent.eventId,
          payload: {
            action: routeActionValue(result.routingDecision.action),
            targets: result.routingDecision.targets,
            reason: result.routingDecision.reason
          }
        });

  const runtimeEvents = routeEvent ? [dispatchEvent, resultEvent, routeEvent] : [dispatchEvent, resultEvent];
  return {
    runtimeEvents,
    primaryRuntimeEvent: routeEvent ?? resultEvent
  };
}

interface ConfigInspection {
  name: string;
  configPath: string | null;
  workspacePath: string | null;
  statePath: string | null;
}

function getDefaultProjectsDirectory(): string {
  return path.join(app.getPath("documents"), APP_DOCUMENTS_DIR);
}

async function ensureProjectsDirectory(): Promise<string> {
  const directory = getDefaultProjectsDirectory();
  await fs.mkdir(directory, { recursive: true });
  return directory;
}

async function ensureAutosaveDirectory(): Promise<string> {
  const directory = path.join(app.getPath("userData"), APP_AUTOSAVE_DIR);
  await fs.mkdir(directory, { recursive: true });
  return directory;
}

function getRecentProjectsFilePath(): string {
  return path.join(app.getPath("userData"), RECENT_PROJECTS_FILE);
}

async function loadRecentProjects(): Promise<RecentProjectRecord[]> {
  try {
    const raw = await fs.readFile(getRecentProjectsFilePath(), "utf8");
    const parsed = JSON.parse(raw) as RecentProjectRecord[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

async function saveRecentProjects(entries: RecentProjectRecord[]): Promise<void> {
  await fs.mkdir(app.getPath("userData"), { recursive: true });
  await fs.writeFile(getRecentProjectsFilePath(), JSON.stringify(entries, null, 2), "utf8");
}

async function rememberRecentProject(project: MAProject, filePath: string): Promise<void> {
  const current = await loadRecentProjects();
  const nextEntry: RecentProjectRecord = {
    name: project.name,
    filePath,
    updatedAt: new Date().toISOString()
  };

  const deduped = current.filter((entry) => entry.filePath !== filePath);
  deduped.unshift(nextEntry);
  await saveRecentProjects(deduped.slice(0, 10));
}

async function readProjectFromFile(filePath: string): Promise<ProjectFileHandle> {
  const raw = await fs.readFile(filePath, "utf8");
  const handle = {
    project: parseProject(raw),
    filePath
  };
  await rememberRecentProject(handle.project, filePath);
  return handle;
}

async function writeProjectToFile(project: MAProject, filePath: string): Promise<ProjectFileHandle> {
  const normalized = prepareProjectForSave(project);
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, serializeProject(normalized), "utf8");
  await rememberRecentProject(normalized, filePath);

  return {
    project: normalized,
    filePath
  };
}

async function writeProjectAutosave(project: MAProject): Promise<AutosaveResult> {
  const normalized = prepareProjectForSave(project);
  const autosaveDirectory = await ensureAutosaveDirectory();
  const autosavePath = path.join(
    autosaveDirectory,
    `autosave_${normalized.id.split("-")[0] || normalized.id}.maoproj`
  );
  await fs.writeFile(autosavePath, serializeProject(normalized), "utf8");

  return {
    autosavePath,
    savedAt: new Date().toISOString()
  };
}

async function promptForOpenPath(window: BrowserWindow): Promise<string | null> {
  const defaultDirectory = await ensureProjectsDirectory();
  const result = await dialog.showOpenDialog(window, {
    title: "Open Project",
    properties: ["openFile"],
    defaultPath: defaultDirectory,
    filters: PROJECT_FILTERS
  });

  if (result.canceled) {
    return null;
  }

  return result.filePaths[0] ?? null;
}

async function promptForSavePath(window: BrowserWindow, project: MAProject, filePath: string | null): Promise<string | null> {
  const defaultDirectory = await ensureProjectsDirectory();
  const result = await dialog.showSaveDialog(window, {
    title: "Save Project",
    defaultPath: filePath ?? path.join(defaultDirectory, projectFileName(project)),
    filters: PROJECT_FILTERS
  });

  if (result.canceled) {
    return null;
  }

  const resolvedPath = result.filePath;
  if (!resolvedPath) {
    return null;
  }

  return resolvedPath.endsWith(`.${PROJECT_EXTENSION}`) ? resolvedPath : `${resolvedPath}.${PROJECT_EXTENSION}`;
}

async function promptForDirectory(window: BrowserWindow, defaultPath?: string | null): Promise<string | null> {
  const projectsDirectory = await ensureProjectsDirectory();
  const result = await dialog.showOpenDialog(window, {
    title: "Choose Folder",
    defaultPath: defaultPath ?? projectsDirectory,
    properties: ["openDirectory", "createDirectory", "promptToCreate"]
  });

  if (result.canceled) {
    return null;
  }

  return result.filePaths[0] ?? null;
}

function normalizeAgentKey(value: string): string {
  return value.trim().toLowerCase();
}

function parseAgentNamesFromOutput(output: string): string[] {
  return Array.from(
    new Set(
      output
        .split(/\r?\n/)
        .map((line) => line.trim())
        .flatMap((line) => {
          if (line.startsWith("- ")) {
            return [line.slice(2).split(" (")[0]?.trim() ?? ""];
          }
          return [];
        })
        .filter(Boolean)
    )
  );
}

function buildOpenClawBaseUrl(config: OpenClawConfig): string {
  const scheme = config.useSSL ? "https" : "http";
  return `${scheme}://${config.host}:${config.port}`;
}

function buildActiveAgentRecords(names: string[]): ProjectOpenClawAgentRecord[] {
  const timestamp = toSwiftDate();
  return names.map((name) => ({
    id: `openclaw:${name}`,
    name,
    status: "available",
    lastReloadedAt: timestamp
  }));
}

function trimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function normalizedPositiveInteger(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) ? Math.max(1, Math.round(value)) : fallback;
}

function normalizeOpenClawConfig(config: OpenClawConfig): OpenClawConfig {
  const container = config && typeof config.container === "object" && config.container !== null ? config.container : null;
  const deploymentKind =
    config.deploymentKind === "container" || config.deploymentKind === "remoteServer" || config.deploymentKind === "local"
      ? config.deploymentKind
      : "local";
  const cliLogLevel =
    config.cliLogLevel === "error" ||
    config.cliLogLevel === "warning" ||
    config.cliLogLevel === "info" ||
    config.cliLogLevel === "debug"
      ? config.cliLogLevel
      : "warning";

  return {
    deploymentKind,
    host: trimmedString(config.host) || "127.0.0.1",
    port: normalizedPositiveInteger(config.port, 18789),
    useSSL: Boolean(config.useSSL),
    apiKey: trimmedString(config.apiKey),
    defaultAgent: trimmedString(config.defaultAgent) || "default",
    timeout: normalizedPositiveInteger(config.timeout, 30),
    autoConnect: config.autoConnect !== false,
    localBinaryPath: trimmedString(config.localBinaryPath),
    container: {
      engine: trimmedString(container?.engine) || "docker",
      containerName: trimmedString(container?.containerName),
      workspaceMountPath: trimmedString(container?.workspaceMountPath) || "/workspace"
    },
    cliQuietMode: config.cliQuietMode !== false,
    cliLogLevel
  };
}

function firstExistingChildPath(directoryPath: string, candidates: string[]): string | null {
  for (const candidate of candidates) {
    const resolved = path.join(directoryPath, candidate);
    if (existsSync(resolved)) {
      return resolved;
    }
  }

  return null;
}

function openClawRootCandidatesForConfig(config: OpenClawConfig): string[] {
  switch (config.deploymentKind) {
    case "local":
      return [path.join(os.homedir(), ".openclaw")];
    case "container": {
      const mountPath = config.container.workspaceMountPath.trim();
      if (!mountPath) {
        return [];
      }
      return [path.join(mountPath, ".openclaw"), path.join(mountPath, "openclaw"), mountPath];
    }
    case "remoteServer":
      return [];
  }
}

async function inspectAgentDirectories(agentsDirectory: string): Promise<DirectoryInspection[]> {
  try {
    const entries = await fs.readdir(agentsDirectory, { withFileTypes: true });
    return entries
      .filter((entry) => entry.isDirectory())
      .map((entry) => {
        const directoryPath = path.join(agentsDirectory, entry.name);
        const hasSoulFile =
          existsSync(path.join(directoryPath, "SOUL.md")) || existsSync(path.join(directoryPath, "soul.md"));

        return {
          name: entry.name,
          path: directoryPath,
          workspacePath: firstExistingChildPath(directoryPath, ["workspace", "workspaces", "job", "jobs"]),
          statePath: firstExistingChildPath(directoryPath, ["state", "status", "runtime", "private"]),
          hasSoulFile
        };
      });
  } catch {
    return [];
  }
}

function pushConfigCandidates(value: unknown, pathStack: string[], result: ConfigInspection[], configPath: string) {
  if (Array.isArray(value)) {
    for (const item of value) {
      pushConfigCandidates(item, pathStack, result, configPath);
    }
    return;
  }

  if (!value || typeof value !== "object") {
    return;
  }

  const record = value as Record<string, unknown>;
  const getString = (keys: string[]) => {
    for (const key of keys) {
      const candidate = record[key];
      if (typeof candidate === "string" && candidate.trim().length > 0) {
        return candidate.trim();
      }
    }
    return null;
  };

  const name = getString(["name", "agentName", "agentIdentifier", "identifier", "id"]);
  const workspacePath = getString(["workspacePath", "workspace", "workPath", "workdir"]);
  const statePath = getString(["statePath", "statusPath", "privatePath", "state", "private"]);
  const filePath = getString(["configPath", "path", "filePath"]);

  if (name && (pathStack.includes("agents") || workspacePath || statePath || filePath)) {
    result.push({
      name,
      configPath: filePath ?? configPath,
      workspacePath,
      statePath
    });
  }

  for (const [key, child] of Object.entries(record)) {
    pushConfigCandidates(child, [...pathStack, key], result, configPath);
  }
}

async function inspectAgentConfigCandidates(configPath: string): Promise<ConfigInspection[]> {
  try {
    const raw = await fs.readFile(configPath, "utf8");
    const parsed = JSON.parse(raw) as unknown;
    const candidates: ConfigInspection[] = [];
    pushConfigCandidates(parsed, [], candidates, configPath);
    return candidates;
  } catch {
    return [];
  }
}

async function inspectOpenClawAgentsAtRoot(
  rootPath: string,
  fallbackAgentNames: string[] = []
): Promise<ProjectOpenClawDetectedAgentRecord[]> {
  const directoryInspections = await inspectAgentDirectories(path.join(rootPath, "agents"));
  const configInspections = await inspectAgentConfigCandidates(path.join(rootPath, "openclaw.json"));
  const directoryMap = new Map(directoryInspections.map((item) => [normalizeAgentKey(item.name), item]));
  const configMap = new Map(configInspections.map((item) => [normalizeAgentKey(item.name), item]));
  const mergedKeys = Array.from(new Set([...directoryMap.keys(), ...configMap.keys()])).sort();

  const records = mergedKeys.map((key) => {
    const directory = directoryMap.get(key);
    const configCandidate = configMap.get(key);
    const workspacePath = configCandidate?.workspacePath?.trim() || directory?.workspacePath || null;
    const sourceDirectoryPath =
      workspacePath && existsSync(workspacePath) ? workspacePath : directory?.path ?? null;
    const directoryValidated = Boolean((workspacePath && existsSync(workspacePath)) || directory);
    const configValidated = Boolean(configCandidate);
    const issues: string[] = [];

    if (!directoryValidated) {
      issues.push("workspace directory not found");
    } else if (
      sourceDirectoryPath &&
      !existsSync(path.join(sourceDirectoryPath, "SOUL.md")) &&
      !existsSync(path.join(sourceDirectoryPath, "soul.md"))
    ) {
      issues.push("SOUL.md not found");
    }

    if (!configValidated) {
      issues.push("No matching OpenClaw config entry found");
    }

    return {
      id: [configCandidate?.name ?? directory?.name ?? key, sourceDirectoryPath ?? "", configCandidate?.configPath ?? ""]
        .join("|"),
      name: configCandidate?.name ?? directory?.name ?? key,
      directoryPath: sourceDirectoryPath,
      configPath: configCandidate?.configPath ?? null,
      workspacePath,
      statePath: configCandidate?.statePath ?? directory?.statePath ?? null,
      directoryValidated,
      configValidated,
      copiedToProjectPath: null,
      copiedFileCount: 0,
      issues,
      importedAt: null
    } satisfies ProjectOpenClawDetectedAgentRecord;
  });

  if (records.length > 0) {
    return records.sort((left, right) => left.name.localeCompare(right.name));
  }

  return fallbackAgentNames
    .map((name) => ({
      id: name,
      name,
      directoryPath: null,
      configPath: null,
      workspacePath: null,
      statePath: null,
      directoryValidated: false,
      configValidated: false,
      copiedToProjectPath: null,
      copiedFileCount: 0,
      issues: ["Only CLI results were available."],
      importedAt: null
    }))
    .sort((left, right) => left.name.localeCompare(right.name));
}

async function inspectOpenClawAgents(config: OpenClawConfig, fallbackAgentNames: string[] = []) {
  for (const candidate of openClawRootCandidatesForConfig(config)) {
    if (candidate && existsSync(candidate)) {
      return inspectOpenClawAgentsAtRoot(candidate, fallbackAgentNames);
    }
  }

  return fallbackAgentNames.length > 0
    ? fallbackAgentNames.map((name) => ({
        id: name,
        name,
        directoryPath: null,
        configPath: null,
        workspacePath: null,
        statePath: null,
        directoryValidated: false,
        configValidated: false,
        copiedToProjectPath: null,
        copiedFileCount: 0,
        issues: ["OpenClaw files were not found on disk."],
        importedAt: null
      }))
    : [];
}

function resolveLocalBinaryPath(config: OpenClawConfig): string {
  const configured = config.localBinaryPath.trim();
  if (configured) {
    return configured;
  }

  return OPENCLAW_LOCAL_PATH_CANDIDATES[0] ?? "openclaw";
}

async function runCommand(command: string, args: string[], options?: { timeoutMs?: number }) {
  return execFileAsync(command, args, {
    timeout: options?.timeoutMs ?? 15000,
    windowsHide: true,
    maxBuffer: 1024 * 1024
  });
}

async function runOpenClawDeploymentCommand(
  config: OpenClawConfig,
  args: string[],
  options?: { timeoutMs?: number }
) {
  switch (config.deploymentKind) {
    case "local":
      return runCommand(resolveLocalBinaryPath(config), args, options);
    case "container": {
      const engine = config.container.engine.trim() || "docker";
      const containerName = config.container.containerName.trim();
      if (!containerName) {
        throw new Error("Container name is required.");
      }
      return runCommand(engine, ["exec", containerName, "openclaw", ...args], options);
    }
    case "remoteServer":
      throw new Error("Remote server mode does not support direct OpenClaw CLI execution yet.");
  }
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

function extractFinalResponseCandidate(json: unknown): string | null {
  if (typeof json === "string") {
    return normalizedNonEmpty(json);
  }

  if (Array.isArray(json)) {
    for (let index = json.length - 1; index >= 0; index -= 1) {
      const candidate = extractFinalResponseCandidate(json[index]);
      if (candidate) {
        return candidate;
      }
    }
    return null;
  }

  if (!json || typeof json !== "object") {
    return null;
  }

  const record = json as Record<string, unknown>;
  const direct = firstNonEmptyString(record, ["final", "content", "message", "response", "output", "text", "answer"]);
  if (direct) {
    return direct;
  }

  for (const key of ["choices", "messages", "result", "data", "payload"]) {
    const value = record[key];
    if (value === undefined) {
      continue;
    }
    const candidate = extractFinalResponseCandidate(value);
    if (candidate) {
      return candidate;
    }
  }

  return null;
}

function routingDecisionFromObject(object: unknown): OpenClawRoutingDecision | null {
  if (!object || typeof object !== "object") {
    return null;
  }

  const record = object as Record<string, unknown>;
  const rawAction = firstNonEmptyString(record, ["action", "mode", "decision", "type"])?.toLowerCase();
  const action =
    rawAction === "all" || rawAction === "broadcast" || rawAction === "fanout"
      ? "all"
      : rawAction === "selected" || rawAction === "select" || rawAction === "route" || rawAction === "delegate"
        ? "selected"
        : rawAction === "stop" || rawAction === "none" || rawAction === "finish" || rawAction === "done"
          ? "stop"
          : null;

  if (!action) {
    return null;
  }

  return {
    action,
    targets: stringArray(record.targets ?? record.next_agents ?? record.nextAgents ?? record.agents),
    reason: firstNonEmptyString(record, ["reason", "why", "note", "summary"])
  };
}

function extractRoutingDecision(text: string): OpenClawRoutingDecision | null {
  const payloads = extractJSONPayloads(text);
  for (let index = payloads.length - 1; index >= 0; index -= 1) {
    try {
      const json = JSON.parse(payloads[index]) as unknown;
      if (json && typeof json === "object") {
        const record = json as Record<string, unknown>;
        const nested = record.workflow_route ?? record.route ?? record.routing ?? json;
        const decision = routingDecisionFromObject(nested);
        if (decision) {
          return decision;
        }
      }
    } catch {
      continue;
    }
  }
  return null;
}

function stripRoutingDirective(text: string): string {
  const normalized = text.replace(/\r/g, "");
  const lines = normalized.split("\n");
  for (let index = lines.length - 1; index >= 0; index -= 1) {
    const candidate = lines[index]?.trim();
    if (!candidate) {
      continue;
    }
    if (extractRoutingDecision(candidate)) {
      lines.splice(index, 1);
      break;
    }
    break;
  }
  return lines.join("\n").trim();
}

function extractAgentResponse(stdout: string): { output: string; outputType: ExecutionOutputType; routingDecision: OpenClawRoutingDecision | null } {
  const trimmed = stdout.trim();
  if (!trimmed) {
    return {
      output: "",
      outputType: "empty",
      routingDecision: null
    };
  }

  const routingDecision = extractRoutingDecision(trimmed);
  const payloads = extractJSONPayloads(trimmed);
  for (let index = payloads.length - 1; index >= 0; index -= 1) {
    try {
      const json = JSON.parse(payloads[index]) as unknown;
      const candidate = extractFinalResponseCandidate(json);
      if (candidate) {
        return {
          output: stripRoutingDirective(candidate),
          outputType: "agent_final_response",
          routingDecision
        };
      }
    } catch {
      continue;
    }
  }

  const stripped = stripRoutingDirective(trimmed);
  return {
    output: stripped,
    outputType: stripped ? "agent_final_response" : "runtime_log",
    routingDecision
  };
}

async function executeOpenClawAgent(
  config: OpenClawConfig,
  request: OpenClawAgentExecutionRequest
): Promise<OpenClawAgentExecutionResult> {
  const normalizedConfig = normalizeOpenClawConfig(config);
  const agentIdentifier = trimmedString(request.agentIdentifier) || normalizedConfig.defaultAgent || "default";
  const message = trimmedString(request.message);
  if (!message) {
    const failedResult = {
      success: false,
      message: "Execution message is required.",
      agentIdentifier,
      output: "",
      outputType: "empty" as ExecutionOutputType,
      routingDecision: null
    };
    const runtimeEnvelope = buildRuntimeEventsForExecution(normalizedConfig, request, failedResult);
    return {
      ...failedResult,
      rawStdout: "",
      rawStderr: "",
      runtimeEvents: runtimeEnvelope.runtimeEvents,
      primaryRuntimeEvent: runtimeEnvelope.primaryRuntimeEvent
    };
  }

  const args = ["agent", "--agent", agentIdentifier, "--message", message];
  if (trimmedString(request.sessionID)) {
    args.push("--session-id", trimmedString(request.sessionID));
  }
  if (trimmedString(request.thinkingLevel)) {
    args.push("--thinking", trimmedString(request.thinkingLevel));
  }
  args.push("--timeout", String(Math.max(1, Math.round(request.timeoutSeconds ?? normalizedConfig.timeout ?? 30))));

  try {
    const { stdout, stderr } = await runOpenClawDeploymentCommand(normalizedConfig, args, {
      timeoutMs: Math.max(5, Math.round(request.timeoutSeconds ?? normalizedConfig.timeout ?? 30)) * 1000
    });
    const parsed = extractAgentResponse(stdout ?? "");
    const stderrText = (stderr ?? "").trim();
    const success = parsed.output.length > 0 || !stderrText;

    const executionResult = {
      success,
      message: success ? "OpenClaw agent execution completed." : stderrText || "OpenClaw agent execution failed.",
      agentIdentifier,
      output: parsed.output,
      outputType: success ? parsed.outputType : "error_summary",
      routingDecision: parsed.routingDecision
    };
    const runtimeEnvelope = buildRuntimeEventsForExecution(normalizedConfig, request, executionResult);
    return {
      ...executionResult,
      rawStdout: stdout ?? "",
      rawStderr: stderr ?? "",
      runtimeEvents: runtimeEnvelope.runtimeEvents,
      primaryRuntimeEvent: runtimeEnvelope.primaryRuntimeEvent
    };
  } catch (error) {
    const executionResult = {
      success: false,
      message: error instanceof Error ? error.message : String(error),
      agentIdentifier,
      output: "",
      outputType: "error_summary" as ExecutionOutputType,
      routingDecision: null
    };
    const runtimeEnvelope = buildRuntimeEventsForExecution(normalizedConfig, request, executionResult);
    return {
      ...executionResult,
      rawStdout: "",
      rawStderr: "",
      runtimeEvents: runtimeEnvelope.runtimeEvents,
      primaryRuntimeEvent: runtimeEnvelope.primaryRuntimeEvent
    };
  }
}

async function testLocalOpenClawConnection(config: OpenClawConfig): Promise<OpenClawActionResult> {
  const normalizedConfig = normalizeOpenClawConfig(config);
  const binaryPath = resolveLocalBinaryPath(normalizedConfig);
  try {
    const { stdout, stderr } = await runCommand(binaryPath, ["agents", "list"], {
      timeoutMs: Math.max(normalizedConfig.timeout, 5) * 1000
    });
    const output = `${stdout ?? ""}\n${stderr ?? ""}`;
    const availableAgents = parseAgentNamesFromOutput(output);
    const detectedAgents = await inspectOpenClawAgents(normalizedConfig, availableAgents);
    const names = availableAgents.length > 0 ? availableAgents : detectedAgents.map((item) => item.name);

    return {
      success: true,
      message: `Connected to OpenClaw. Found ${names.length} agent(s).`,
      isConnected: true,
      availableAgents: names,
      activeAgents: buildActiveAgentRecords(names),
      detectedAgents
    };
  } catch (error) {
    return {
      success: false,
      message: error instanceof Error ? error.message : String(error),
      isConnected: false,
      availableAgents: [],
      activeAgents: [],
      detectedAgents: []
    };
  }
}

async function testContainerOpenClawConnection(config: OpenClawConfig): Promise<OpenClawActionResult> {
  const normalizedConfig = normalizeOpenClawConfig(config);
  const engine = normalizedConfig.container.engine.trim() || "docker";
  const containerName = normalizedConfig.container.containerName.trim();
  if (!containerName) {
    return {
      success: false,
      message: "Container name is required.",
      isConnected: false,
      availableAgents: [],
      activeAgents: [],
      detectedAgents: []
    };
  }

  try {
    const { stdout, stderr } = await runCommand(engine, ["exec", containerName, "openclaw", "agents", "list"], {
      timeoutMs: Math.max(normalizedConfig.timeout, 5) * 1000
    });
    const output = `${stdout ?? ""}\n${stderr ?? ""}`;
    const availableAgents = parseAgentNamesFromOutput(output);
    const detectedAgents = await inspectOpenClawAgents(normalizedConfig, availableAgents);
    const names = availableAgents.length > 0 ? availableAgents : detectedAgents.map((item) => item.name);

    return {
      success: true,
      message: `Connected to OpenClaw container. Found ${names.length} agent(s).`,
      isConnected: true,
      availableAgents: names,
      activeAgents: buildActiveAgentRecords(names),
      detectedAgents
    };
  } catch (error) {
    return {
      success: false,
      message: error instanceof Error ? error.message : String(error),
      isConnected: false,
      availableAgents: [],
      activeAgents: [],
      detectedAgents: []
    };
  }
}

async function testRemoteOpenClawConnection(config: OpenClawConfig): Promise<OpenClawActionResult> {
  const normalizedConfig = normalizeOpenClawConfig(config);
  const host = normalizedConfig.host.trim();
  if (!host) {
    return {
      success: false,
      message: "Remote host is required.",
      isConnected: false,
      availableAgents: [],
      activeAgents: [],
      detectedAgents: []
    };
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), Math.max(normalizedConfig.timeout, 5) * 1000);
  try {
    const response = await fetch(buildOpenClawBaseUrl(normalizedConfig), {
      headers: normalizedConfig.apiKey ? { Authorization: `Bearer ${normalizedConfig.apiKey}` } : undefined,
      signal: controller.signal
    });

    return {
      success: response.ok,
      message: response.ok
        ? `Connected to remote OpenClaw at ${buildOpenClawBaseUrl(normalizedConfig)}.`
        : `Remote OpenClaw responded with HTTP ${response.status}.`,
      isConnected: response.ok,
      availableAgents: [],
      activeAgents: [],
      detectedAgents: []
    };
  } catch (error) {
    return {
      success: false,
      message: error instanceof Error ? error.message : String(error),
      isConnected: false,
      availableAgents: [],
      activeAgents: [],
      detectedAgents: []
    };
  } finally {
    clearTimeout(timeout);
  }
}

async function connectOpenClaw(config: OpenClawConfig): Promise<OpenClawActionResult> {
  switch (config.deploymentKind) {
    case "local":
      return testLocalOpenClawConnection(config);
    case "container":
      return testContainerOpenClawConnection(config);
    case "remoteServer":
      return testRemoteOpenClawConnection(config);
  }
}

async function detectOpenClawAgents(config: OpenClawConfig): Promise<OpenClawActionResult> {
  const connectionAttempt = await connectOpenClaw(config);
  if (connectionAttempt.success) {
    return {
      ...connectionAttempt,
      isConnected: false,
      message: `Detected ${connectionAttempt.detectedAgents.length} OpenClaw agent(s).`
    };
  }

  const detectedAgents = await inspectOpenClawAgents(config, []);
  if (detectedAgents.length > 0) {
    return {
      success: true,
      message: `Detected ${detectedAgents.length} OpenClaw agent(s) from disk.`,
      isConnected: false,
      availableAgents: detectedAgents.map((item) => item.name),
      activeAgents: [],
      detectedAgents
    };
  }

  return connectionAttempt;
}

function createWindow(): BrowserWindow {
  const window = new BrowserWindow({
    width: 1360,
    height: 880,
    minWidth: 1024,
    minHeight: 680,
    title: "Multi-Agent-Flow",
    webPreferences: {
      preload: path.join(__dirname, "../preload/preload.mjs"),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  if (process.env.VITE_DEV_SERVER_URL) {
    void window.loadURL(process.env.VITE_DEV_SERVER_URL);
  } else {
    void window.loadFile(path.join(__dirname, "../renderer/index.html"));
  }

  return window;
}

function registerProjectIpcHandlers() {
  ipcMain.handle("project:create", async (_event, name?: string): Promise<ProjectFileHandle> => {
    return {
      project: createEmptyProject(name?.trim() || "Untitled Project"),
      filePath: null
    };
  });

  ipcMain.handle("project:open", async (event): Promise<ProjectFileHandle | null> => {
    const window = BrowserWindow.fromWebContents(event.sender);
    if (!window) {
      throw new Error("Unable to resolve window for open dialog.");
    }

    const filePath = await promptForOpenPath(window);
    if (!filePath) {
      return null;
    }

    return readProjectFromFile(filePath);
  });

  ipcMain.handle("project:openRecent", async (_event, filePath: string): Promise<ProjectFileHandle> => {
    return readProjectFromFile(filePath);
  });

  ipcMain.handle("project:listRecent", async (): Promise<RecentProjectRecord[]> => {
    const entries = await loadRecentProjects();
    const checks = await Promise.all(
      entries.map(async (entry) => {
        try {
          await fs.access(entry.filePath);
          return entry;
        } catch {
          return null;
        }
      })
    );

    const validEntries = checks.filter((entry): entry is RecentProjectRecord => entry !== null);
    if (validEntries.length !== entries.length) {
      await saveRecentProjects(validEntries);
    }

    return validEntries;
  });

  ipcMain.handle(
    "project:save",
    async (_event, payload: { project: MAProject; filePath: string | null }): Promise<ProjectFileHandle> => {
      if (payload.filePath) {
        return writeProjectToFile(payload.project, payload.filePath);
      }

      throw new Error("Save requires an existing file path. Use Save As for unsaved projects.");
    }
  );

  ipcMain.handle(
    "project:saveAs",
    async (event, payload: { project: MAProject; filePath: string | null }): Promise<ProjectFileHandle | null> => {
      const window = BrowserWindow.fromWebContents(event.sender);
      if (!window) {
        throw new Error("Unable to resolve window for save dialog.");
      }

      const nextPath = await promptForSavePath(window, payload.project, payload.filePath);
      if (!nextPath) {
        return null;
      }

      return writeProjectToFile(payload.project, nextPath);
    }
  );

  ipcMain.handle("project:autosave", async (_event, project: MAProject): Promise<AutosaveResult> => {
    return writeProjectAutosave(project);
  });

  ipcMain.handle(
    "project:chooseDirectory",
    async (event, defaultPath?: string | null): Promise<DirectorySelectionResult> => {
      const window = BrowserWindow.fromWebContents(event.sender);
      if (!window) {
        throw new Error("Unable to resolve window for directory dialog.");
      }

      return {
        directoryPath: await promptForDirectory(window, defaultPath)
      };
    }
  );

  ipcMain.handle("openClaw:connect", async (_event, config: OpenClawConfig): Promise<OpenClawActionResult> => {
    return connectOpenClaw(config);
  });

  ipcMain.handle("openClaw:detect", async (_event, config: OpenClawConfig): Promise<OpenClawActionResult> => {
    return detectOpenClawAgents(config);
  });

  ipcMain.handle("openClaw:disconnect", async (): Promise<OpenClawActionResult> => {
    return {
      success: true,
      message: "Disconnected from OpenClaw.",
      isConnected: false,
      availableAgents: [],
      activeAgents: [],
      detectedAgents: []
    };
  });

  ipcMain.handle(
    "openClaw:executeAgent",
    async (_event, payload: { config: OpenClawConfig; request: OpenClawAgentExecutionRequest }): Promise<OpenClawAgentExecutionResult> => {
      return executeOpenClawAgent(payload.config, payload.request);
    }
  );
}

app.whenReady().then(() => {
  registerProjectIpcHandlers();
  createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

if (process.platform === "win32") {
  app.setAppUserModelId(APP_ID);
}

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});
