import path from "node:path";
import os from "node:os";
import * as net from "node:net";
import * as tls from "node:tls";
import { execFile } from "node:child_process";
import { createHash, createPrivateKey, createPublicKey, generateKeyPairSync, randomBytes, sign as signData } from "node:crypto";
import type { JsonWebKey as NodeJsonWebKey } from "node:crypto";
import { existsSync, promises as fs } from "node:fs";
import { promisify } from "node:util";
import { app, BrowserWindow, dialog, ipcMain } from "electron";
import {
  buildConnectionStateFromProbeReport,
  buildDetachedOpenClawConnectionState,
  buildOpenClawProbeContract,
  createDefaultOpenClawCapabilities,
  createDefaultOpenClawHealth,
  formatOpenClawProbeLayers,
  type GatewayTransportProbeResult
} from "./openclaw-connection-state";
import {
  buildContainerOpenClawRootDiscoveryScript,
  buildOpenClawRootFallbackCandidates
} from "./openclaw-discovery";
import {
  buildOpenClawGovernanceAuditReport,
  assessOpenClawSandboxSecurityFromText,
  createEmptyProject,
  parseOpenClawApprovalsSnapshotFromText,
  parseProject,
  prepareProjectForSave,
  projectFileName,
  serializeProject,
  toSwiftDate,
  type OpenClawGovernanceAction,
  type OpenClawGovernanceAuditReport,
  type OpenClawGovernanceFinding,
  type OpenClawGovernanceRemediationResult,
  type OpenClawRuntimeSecurityFinding,
  type OpenClawRuntimeSecurityInspectionResult
} from "@multi-agent-flow/core";
import type {
  ExecutionOutputType,
  MAProject,
  OpenClawConfig,
  OpenClawConnectionCapabilitiesSnapshot,
  OpenClawConnectionHealthSnapshot,
  OpenClawConnectionPhase,
  OpenClawConnectionStateSnapshot,
  OpenClawProbeReportSnapshot,
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
const OPENCLAW_PROBE_SOURCE = "desktop-shell.probe.v1";
const DESKTOP_GATEWAY_CLIENT_ID = "gateway-client";
const DESKTOP_GATEWAY_CLIENT_MODE = "backend";
const DESKTOP_GATEWAY_ROLE = "operator";
const DESKTOP_GATEWAY_SCOPES = ["operator.admin"] as const;
const DESKTOP_GATEWAY_DEVICE_FAMILY = "desktop";
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
  connectionState?: OpenClawConnectionStateSnapshot;
  probeReport?: OpenClawProbeReportSnapshot | null;
}

interface DesktopGatewayDeviceIdentity {
  version: number;
  deviceID: string;
  publicKeyBase64URL: string;
  privateKeyJwk: NodeJsonWebKey;
  createdAtMilliseconds: number;
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

interface DirectoryInspection {
  name: string;
  path: string;
  workspacePath: string | null;
  statePath: string | null;
  hasSoulFile: boolean;
}

interface OpenClawGovernancePaths {
  rootPath: string | null;
  configPath: string | null;
  approvalsPath: string | null;
}

interface OpenClawGovernanceRemediationRequest {
  config: OpenClawConfig;
  actionIds?: string[] | null;
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
      thinkingLevel: trimmedString(request.thinkingLevel) || null,
      writeScope: Array.isArray(request.writeScope) ? request.writeScope.filter(Boolean) : [],
      toolScope: Array.isArray(request.toolScope) ? request.toolScope.filter(Boolean) : []
    },
    control: {
      requiresApproval: request.requiresApproval === true,
      fallbackRoutingPolicy: trimmedString(request.fallbackRoutingPolicy) || "stop",
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

function buildOpenClawWebSocketUrl(config: OpenClawConfig): string {
  const scheme = config.useSSL ? "wss" : "ws";
  return `${scheme}://${config.host}:${config.port}/`;
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

function tryParseWebSocketTextFrame(
  buffer: Buffer
): { payload: string; remaining: Buffer; opcode: number } | null {
  if (buffer.length < 2) {
    return null;
  }

  const firstByte = buffer[0];
  const secondByte = buffer[1];
  const opcode = firstByte & 0x0f;
  const masked = (secondByte & 0x80) !== 0;
  let offset = 2;
  let payloadLength = secondByte & 0x7f;

  if (payloadLength === 126) {
    if (buffer.length < offset + 2) {
      return null;
    }
    payloadLength = buffer.readUInt16BE(offset);
    offset += 2;
  } else if (payloadLength === 127) {
    if (buffer.length < offset + 8) {
      return null;
    }
    const extendedLength = buffer.readBigUInt64BE(offset);
    if (extendedLength > BigInt(Number.MAX_SAFE_INTEGER)) {
      throw new Error("Gateway websocket frame is too large to probe safely.");
    }
    payloadLength = Number(extendedLength);
    offset += 8;
  }

  const maskLength = masked ? 4 : 0;
  if (buffer.length < offset + maskLength + payloadLength) {
    return null;
  }

  let payload = buffer.subarray(offset + maskLength, offset + maskLength + payloadLength);
  if (masked) {
    const mask = buffer.subarray(offset, offset + 4);
    const unmasked = Buffer.alloc(payload.length);
    for (let index = 0; index < payload.length; index += 1) {
      unmasked[index] = payload[index] ^ mask[index % 4];
    }
    payload = unmasked;
  }

  return {
    payload: payload.toString("utf8"),
    remaining: buffer.subarray(offset + maskLength + payloadLength),
    opcode
  };
}

function createMaskedWebSocketTextFrame(payload: string): Buffer {
  const payloadBuffer = Buffer.from(payload, "utf8");
  const payloadLength = payloadBuffer.length;
  const mask = randomBytes(4);
  const header: number[] = [0x81];

  if (payloadLength < 126) {
    header.push(0x80 | payloadLength);
  } else if (payloadLength <= 0xffff) {
    header.push(0x80 | 126, (payloadLength >> 8) & 0xff, payloadLength & 0xff);
  } else {
    const high = Math.floor(payloadLength / 2 ** 32);
    const low = payloadLength >>> 0;
    header.push(
      0x80 | 127,
      (high >> 24) & 0xff,
      (high >> 16) & 0xff,
      (high >> 8) & 0xff,
      high & 0xff,
      (low >> 24) & 0xff,
      (low >> 16) & 0xff,
      (low >> 8) & 0xff,
      low & 0xff
    );
  }

  const maskedPayload = Buffer.alloc(payloadBuffer.length);
  for (let index = 0; index < payloadBuffer.length; index += 1) {
    maskedPayload[index] = payloadBuffer[index] ^ mask[index % 4];
  }

  return Buffer.concat([Buffer.from(header), mask, maskedPayload]);
}

function base64UrlEncode(value: Buffer): string {
  return value
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function base64UrlDecode(value: string): Buffer {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padding = normalized.length % 4 === 0 ? "" : "=".repeat(4 - (normalized.length % 4));
  return Buffer.from(`${normalized}${padding}`, "base64");
}

function gatewayClientVersion(): string {
  const version = trimmedString(app.getVersion?.());
  return version || "0.1.0";
}

function gatewayDeviceIdentityPath(): string {
  return path.join(app.getPath("userData"), "openclaw", "identity", "gateway-device-identity.json");
}

function normalizedGatewayMetadata(value: string): string {
  return trimmedString(value).toLowerCase();
}

function buildGatewayDeviceAuthPayload(
  identity: DesktopGatewayDeviceIdentity,
  signedAtMilliseconds: number,
  token: string | null,
  nonce: string
): string {
  return [
    "v3",
    identity.deviceID,
    DESKTOP_GATEWAY_CLIENT_ID,
    DESKTOP_GATEWAY_CLIENT_MODE,
    DESKTOP_GATEWAY_ROLE,
    DESKTOP_GATEWAY_SCOPES.join(","),
    String(signedAtMilliseconds),
    token ?? "",
    nonce,
    normalizedGatewayMetadata(process.platform),
    normalizedGatewayMetadata(DESKTOP_GATEWAY_DEVICE_FAMILY)
  ].join("|");
}

function createDesktopGatewayDeviceIdentity(): DesktopGatewayDeviceIdentity {
  const { privateKey } = generateKeyPairSync("ed25519");
  const privateKeyJwk = privateKey.export({ format: "jwk" }) as NodeJsonWebKey;
  const publicKeyJwk = createPublicKey(privateKey).export({ format: "jwk" }) as NodeJsonWebKey;
  const publicKeyBase64URL = trimmedString(publicKeyJwk.x);
  if (!publicKeyBase64URL) {
    throw new Error("Unable to generate OpenClaw gateway public key.");
  }

  return {
    version: 1,
    deviceID: createHash("sha256").update(base64UrlDecode(publicKeyBase64URL)).digest("hex"),
    publicKeyBase64URL,
    privateKeyJwk,
    createdAtMilliseconds: Date.now()
  };
}

async function persistDesktopGatewayDeviceIdentity(identity: DesktopGatewayDeviceIdentity): Promise<void> {
  const filePath = gatewayDeviceIdentityPath();
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(`${filePath}.tmp`, `${JSON.stringify(identity, null, 2)}\n`, "utf8");
  await fs.rename(`${filePath}.tmp`, filePath);
}

async function loadOrCreateDesktopGatewayDeviceIdentity(): Promise<DesktopGatewayDeviceIdentity> {
  const filePath = gatewayDeviceIdentityPath();

  try {
    const raw = await fs.readFile(filePath, "utf8");
    const parsed = JSON.parse(raw) as Partial<DesktopGatewayDeviceIdentity>;
    const publicKeyBase64URL = trimmedString(parsed.publicKeyBase64URL ?? "");
    const privateKeyJwk = parsed.privateKeyJwk;

    if (publicKeyBase64URL && privateKeyJwk && typeof privateKeyJwk === "object") {
      const deviceID = createHash("sha256").update(base64UrlDecode(publicKeyBase64URL)).digest("hex");
      const identity: DesktopGatewayDeviceIdentity = {
        version: typeof parsed.version === "number" ? parsed.version : 1,
        deviceID,
        publicKeyBase64URL,
        privateKeyJwk,
        createdAtMilliseconds:
          typeof parsed.createdAtMilliseconds === "number" ? parsed.createdAtMilliseconds : Date.now()
      };

      if (identity.deviceID !== parsed.deviceID) {
        await persistDesktopGatewayDeviceIdentity(identity);
      }

      return identity;
    }
  } catch {
    // Regenerate below.
  }

  const identity = createDesktopGatewayDeviceIdentity();
  await persistDesktopGatewayDeviceIdentity(identity);
  return identity;
}

function buildGatewayConnectParams(
  config: OpenClawConfig,
  identity: DesktopGatewayDeviceIdentity,
  challengePayload: Record<string, unknown> | null
): Record<string, unknown> {
  const token = trimmedString(config.apiKey) || null;
  const version = gatewayClientVersion();
  const nonce = typeof challengePayload?.nonce === "string" ? trimmedString(challengePayload.nonce) : "";
  const signedAtMilliseconds = Date.now();
  return {
    minProtocol: 3,
    maxProtocol: 3,
    client: {
      id: DESKTOP_GATEWAY_CLIENT_ID,
      displayName: "Multi-Agent-Flow",
      version,
      platform: process.platform,
      deviceFamily: DESKTOP_GATEWAY_DEVICE_FAMILY,
      mode: DESKTOP_GATEWAY_CLIENT_MODE
    },
    role: DESKTOP_GATEWAY_ROLE,
    scopes: [...DESKTOP_GATEWAY_SCOPES],
    caps: [],
    commands: [],
    permissions: {},
    locale: Intl.DateTimeFormat().resolvedOptions().locale || "en-US",
    userAgent: `Multi-Agent-Flow/${version}`,
    ...(token ? { auth: { token } } : {}),
    ...(nonce
      ? {
          device: {
            id: identity.deviceID,
            publicKey: identity.publicKeyBase64URL,
            signature: base64UrlEncode(
              signData(
                null,
                Buffer.from(buildGatewayDeviceAuthPayload(identity, signedAtMilliseconds, token, nonce), "utf8"),
                createPrivateKey({ key: identity.privateKeyJwk, format: "jwk" })
              )
            ),
            signedAt: signedAtMilliseconds,
            nonce
          }
        }
      : {})
  };
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

async function discoverContainerOpenClawRootPath(config: OpenClawConfig): Promise<string | null> {
  if (config.deploymentKind !== "container") {
    return null;
  }

  try {
    const { stdout } = await runOpenClawDeploymentShell(
      config,
      buildContainerOpenClawRootDiscoveryScript(config.container.workspaceMountPath),
      {
        timeoutMs: Math.max(config.timeout, 5) * 1000
      }
    );
    return trimmedString(stdout) || null;
  } catch {
    return null;
  }
}

async function openClawRootCandidatesForConfig(config: OpenClawConfig): Promise<string[]> {
  if (config.deploymentKind === "container") {
    const deploymentHomeDirectory = await resolveDeploymentHomeDirectory(config);
    return buildOpenClawRootFallbackCandidates(config, {
      deploymentHomeDirectory
    });
  }

  return buildOpenClawRootFallbackCandidates(config, {
    localHomeDirectory: os.homedir()
  });
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

async function inspectAgentConfigCandidatesForConfig(
  config: OpenClawConfig,
  configPath: string
): Promise<ConfigInspection[]> {
  const raw = await readFileForConfig(config, configPath);
  if (!raw) {
    return [];
  }

  try {
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
      soulPath: sourceDirectoryPath
        ? firstExistingChildPath(sourceDirectoryPath, ["SOUL.md", "soul.md"])
        : null,
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
      soulPath: null,
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

async function inspectOpenClawAgentsFromConfigPath(
  config: OpenClawConfig,
  configPath: string,
  fallbackAgentNames: string[] = []
): Promise<ProjectOpenClawDetectedAgentRecord[]> {
  const configInspections = await inspectAgentConfigCandidatesForConfig(config, configPath);
  const configMap = new Map(configInspections.map((item) => [normalizeAgentKey(item.name), item]));
  const records: ProjectOpenClawDetectedAgentRecord[] = [];

  for (const [key, configCandidate] of configMap.entries()) {
    const workspacePath = configCandidate.workspacePath?.trim() || null;
    const directoryValidated = workspacePath ? await pathExistsForConfig(config, workspacePath) : false;
    const soulPath =
      directoryValidated && workspacePath
        ? await firstExistingChildPathForConfig(config, workspacePath, ["SOUL.md", "soul.md"])
        : null;
    const issues: string[] = [];

    if (!directoryValidated) {
      issues.push("workspace directory not found");
    }

    if (directoryValidated && !soulPath) {
      issues.push("SOUL.md not found");
    }

    records.push({
      id: [configCandidate.name ?? key, workspacePath ?? "", configCandidate.configPath ?? ""].join("|"),
      name: configCandidate.name ?? key,
      directoryPath: workspacePath,
      configPath: configCandidate.configPath ?? configPath,
      soulPath,
      workspacePath,
      statePath: configCandidate.statePath ?? null,
      directoryValidated,
      configValidated: true,
      copiedToProjectPath: null,
      copiedFileCount: 0,
      issues,
      importedAt: null
    });
  }

  if (records.length > 0) {
    return records.sort((left, right) => left.name.localeCompare(right.name));
  }

  return fallbackAgentNames
    .map((name) => ({
      id: name,
      name,
      directoryPath: null,
      configPath,
      soulPath: null,
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
  const cliConfigPath = await resolveOpenClawConfigPathFromCli(config);
  if (cliConfigPath) {
    if (config.deploymentKind === "container") {
      return inspectOpenClawAgentsFromConfigPath(config, cliConfigPath, fallbackAgentNames);
    }

    const rootPath = path.dirname(cliConfigPath);
    if (rootPath && existsSync(rootPath)) {
      return inspectOpenClawAgentsAtRoot(rootPath, fallbackAgentNames);
    }
  }

  if (config.deploymentKind === "container") {
    const discoveredRoot = await resolveOpenClawRootPathForProbe(config);
    if (discoveredRoot) {
      const configPath = await firstExistingChildPathForConfig(config, discoveredRoot, ["openclaw.json"]);
      if (configPath) {
        return inspectOpenClawAgentsFromConfigPath(config, configPath, fallbackAgentNames);
      }
    }
  }

  for (const candidate of await openClawRootCandidatesForConfig(config)) {
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
        soulPath: null,
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

function shellSingleQuote(value: string): string {
  return `'${value.replace(/'/g, `'\"'\"'`)}'`;
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

async function runOpenClawDeploymentShell(
  config: OpenClawConfig,
  script: string,
  options?: { timeoutMs?: number }
) {
  switch (config.deploymentKind) {
    case "local":
      return runCommand("/bin/sh", ["-lc", script], options);
    case "container": {
      const engine = config.container.engine.trim() || "docker";
      const containerName = config.container.containerName.trim();
      if (!containerName) {
        throw new Error("Container name is required.");
      }
      return runCommand(engine, ["exec", containerName, "sh", "-lc", script], options);
    }
    case "remoteServer":
      throw new Error("Remote server mode does not support shell-based OpenClaw file management yet.");
  }
}

function expandHomePath(candidatePath: string, homeDirectory: string | null): string {
  const trimmed = candidatePath.trim();
  if (!trimmed.startsWith("~/") || !homeDirectory) {
    return trimmed;
  }
  return path.join(homeDirectory, trimmed.slice(2));
}

async function resolveDeploymentHomeDirectory(config: OpenClawConfig): Promise<string | null> {
  switch (config.deploymentKind) {
    case "local":
      return os.homedir();
    case "container":
      try {
        const { stdout } = await runOpenClawDeploymentShell(config, "printf %s \"$HOME\"", {
          timeoutMs: Math.max(config.timeout, 5) * 1000
        });
        return trimmedString(stdout) || null;
      } catch {
        return null;
      }
    case "remoteServer":
      return null;
  }
}

async function resolveOpenClawConfigPathFromCli(config: OpenClawConfig): Promise<string | null> {
  try {
    const { stdout, stderr } = await runOpenClawDeploymentCommand(config, ["config", "file"], {
      timeoutMs: Math.max(config.timeout, 5) * 1000
    });
    const reported = trimmedString(`${stdout ?? ""}\n${stderr ?? ""}`);
    if (!reported) {
      return null;
    }
    const homeDirectory = await resolveDeploymentHomeDirectory(config);
    return expandHomePath(reported.split(/\r?\n/).at(-1) ?? reported, homeDirectory);
  } catch {
    return null;
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

function jsonRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
}

async function readJSONRecord(filePath: string): Promise<Record<string, unknown> | null> {
  try {
    const raw = await fs.readFile(filePath, "utf8");
    return jsonRecord(JSON.parse(raw) as unknown);
  } catch {
    return null;
  }
}

async function pathExistsForConfig(config: OpenClawConfig, candidatePath: string): Promise<boolean> {
  switch (config.deploymentKind) {
    case "local":
      return existsSync(candidatePath);
    case "container":
      try {
        await runOpenClawDeploymentShell(config, `test -e ${shellSingleQuote(candidatePath)}`, {
          timeoutMs: Math.max(config.timeout, 5) * 1000
        });
        return true;
      } catch {
        return false;
      }
    case "remoteServer":
      return false;
  }
}

async function firstExistingChildPathForConfig(
  config: OpenClawConfig,
  directoryPath: string,
  candidates: string[]
): Promise<string | null> {
  for (const candidate of candidates) {
    const resolved = path.join(directoryPath, candidate);
    if (await pathExistsForConfig(config, resolved)) {
      return resolved;
    }
  }

  return null;
}

async function readFileForConfig(config: OpenClawConfig, filePath: string): Promise<string | null> {
  switch (config.deploymentKind) {
    case "local":
      try {
        return await fs.readFile(filePath, "utf8");
      } catch {
        return null;
      }
    case "container":
      try {
        const { stdout } = await runOpenClawDeploymentShell(config, `cat ${shellSingleQuote(filePath)}`, {
          timeoutMs: Math.max(config.timeout, 5) * 1000
        });
        return stdout ?? "";
      } catch {
        return null;
      }
    case "remoteServer":
      return null;
  }
}

async function readJSONRecordForConfig(config: OpenClawConfig, filePath: string): Promise<Record<string, unknown> | null> {
  const raw = await readFileForConfig(config, filePath);
  if (!raw) {
    return null;
  }

  try {
    return jsonRecord(JSON.parse(raw) as unknown);
  } catch {
    return null;
  }
}

function createFallbackGatewayProbeConfig(
  baseConfig: OpenClawConfig,
  hostFallback: string,
  useSSLFallback: boolean,
  fallbackPort: number = baseConfig.port
): OpenClawConfig | null {
  const resolvedHost = trimmedString(hostFallback) || "127.0.0.1";
  const resolvedPort = normalizedPositiveInteger(fallbackPort, baseConfig.port);
  if (resolvedPort <= 0) {
    return null;
  }

  return {
    ...baseConfig,
    deploymentKind: "remoteServer",
    host: resolvedHost,
    port: resolvedPort,
    useSSL: useSSLFallback,
    apiKey: trimmedString(baseConfig.apiKey)
  };
}

async function resolveOpenClawRootPathForProbe(config: OpenClawConfig): Promise<string | null> {
  const cliConfigPath = await resolveOpenClawConfigPathFromCli(config);
  if (cliConfigPath) {
    return path.dirname(cliConfigPath);
  }

  if (config.deploymentKind === "container") {
    const discoveredRoot = await discoverContainerOpenClawRootPath(config);
    if (discoveredRoot) {
      return discoveredRoot;
    }
  }

  for (const candidate of await openClawRootCandidatesForConfig(config)) {
    if (candidate && (await pathExistsForConfig(config, candidate))) {
      return candidate;
    }
  }

  return null;
}

async function resolveGatewayProbeConfigFromRoot(
  baseConfig: OpenClawConfig,
  rootPath: string,
  options: {
    hostFallback: string;
    useSSLFallback: boolean;
    fallbackPort?: number;
  }
): Promise<OpenClawConfig | null> {
  const configRecord = await readJSONRecordForConfig(baseConfig, path.join(rootPath, "openclaw.json"));
  const fallback = createFallbackGatewayProbeConfig(
    baseConfig,
    options.hostFallback,
    options.useSSLFallback,
    options.fallbackPort ?? baseConfig.port
  );

  if (!configRecord) {
    return fallback;
  }

  const gateway = jsonRecord(configRecord.gateway);
  if (!gateway) {
    return fallback;
  }

  const mode = (firstNonEmptyString(gateway, ["mode"]) ?? "local").toLowerCase();
  if (mode !== "local") {
    return null;
  }

  const portValue = typeof gateway.port === "number" && Number.isFinite(gateway.port)
    ? Math.max(1, Math.round(gateway.port))
    : options.fallbackPort ?? baseConfig.port;
  const auth = jsonRecord(gateway.auth) ?? {};
  const authMode = (firstNonEmptyString(auth, ["mode"]) ?? "token").toLowerCase();
  const normalizedToken = trimmedString(typeof auth.token === "string" ? auth.token : "");

  let apiKey = trimmedString(baseConfig.apiKey);
  switch (authMode) {
    case "none":
      apiKey = "";
      break;
    case "token":
      apiKey = normalizedToken || apiKey;
      break;
    default:
      return null;
  }

  if (portValue <= 0) {
    return fallback;
  }

  return {
    ...baseConfig,
    deploymentKind: "remoteServer",
    host: trimmedString(options.hostFallback) || "127.0.0.1",
    port: portValue,
    useSSL: options.useSSLFallback,
    apiKey
  };
}

async function resolveGatewayProbeConfig(config: OpenClawConfig): Promise<OpenClawConfig | null> {
  const normalizedConfig = normalizeOpenClawConfig(config);
  switch (normalizedConfig.deploymentKind) {
    case "remoteServer":
      return trimmedString(normalizedConfig.host) ? normalizedConfig : null;
    case "local": {
      const rootPath = await resolveOpenClawRootPathForProbe(normalizedConfig);
      if (!rootPath) {
        return createFallbackGatewayProbeConfig(normalizedConfig, "127.0.0.1", false, normalizedConfig.port);
      }
      return resolveGatewayProbeConfigFromRoot(normalizedConfig, rootPath, {
        hostFallback: "127.0.0.1",
        useSSLFallback: false,
        fallbackPort: normalizedConfig.port
      });
    }
    case "container": {
      const hostFallback = trimmedString(normalizedConfig.host) || "127.0.0.1";
      const rootPath = await resolveOpenClawRootPathForProbe(normalizedConfig);
      if (!rootPath) {
        return createFallbackGatewayProbeConfig(
          normalizedConfig,
          hostFallback,
          normalizedConfig.useSSL,
          normalizedConfig.port
        );
      }
      return resolveGatewayProbeConfigFromRoot(normalizedConfig, rootPath, {
        hostFallback,
        useSSLFallback: normalizedConfig.useSSL,
        fallbackPort: normalizedConfig.port
      });
    }
  }
}

async function writeJSONFileForConfig(config: OpenClawConfig, filePath: string, value: unknown): Promise<void> {
  const rendered = `${JSON.stringify(value, null, 2)}\n`;
  switch (config.deploymentKind) {
    case "local":
      await fs.mkdir(path.dirname(filePath), { recursive: true });
      await fs.writeFile(filePath, rendered, "utf8");
      return;
    case "container": {
      const delimiter = `__MAF_JSON_${crypto.randomUUID().replace(/-/g, "_")}__`;
      const script = [
        `mkdir -p "$(dirname ${shellSingleQuote(filePath)})"`,
        `cat <<'${delimiter}' > ${shellSingleQuote(filePath)}`,
        rendered,
        delimiter
      ].join("\n");
      await runOpenClawDeploymentShell(config, script, {
        timeoutMs: Math.max(config.timeout, 10) * 1000
      });
      return;
    }
    case "remoteServer":
      throw new Error("Remote server mode does not support writable OpenClaw governance files.");
  }
}

async function ensureDirectoryForConfig(config: OpenClawConfig, directoryPath: string): Promise<void> {
  switch (config.deploymentKind) {
    case "local":
      await fs.mkdir(directoryPath, { recursive: true });
      return;
    case "container":
      await runOpenClawDeploymentShell(config, `mkdir -p ${shellSingleQuote(directoryPath)}`, {
        timeoutMs: Math.max(config.timeout, 10) * 1000
      });
      return;
    case "remoteServer":
      throw new Error("Remote server mode does not support writable OpenClaw governance directories.");
  }
}

async function backupGovernanceFileForConfig(config: OpenClawConfig, filePath: string): Promise<string> {
  const backupDirectory = path.join(path.dirname(filePath), "backups", "multi-agent-flow-governance");
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const backupPath = path.join(backupDirectory, `${timestamp}-${path.basename(filePath)}`);

  switch (config.deploymentKind) {
    case "local":
      await fs.mkdir(backupDirectory, { recursive: true });
      await fs.copyFile(filePath, backupPath);
      return backupPath;
    case "container":
      await runOpenClawDeploymentShell(
        config,
        `mkdir -p ${shellSingleQuote(backupDirectory)} && cp ${shellSingleQuote(filePath)} ${shellSingleQuote(backupPath)}`,
        {
          timeoutMs: Math.max(config.timeout, 10) * 1000
        }
      );
      return backupPath;
    case "remoteServer":
      throw new Error("Remote server mode does not support OpenClaw governance backups.");
  }
}

function blockingErrorMessage(error: unknown, fallback: string): string {
  const message = error instanceof Error ? trimmedString(error.message) : trimmedString(String(error));
  return message || fallback;
}

async function inspectOpenClawExecApprovalSnapshot(config: OpenClawConfig): Promise<{ hasCustomEntries: boolean }> {
  const { stdout, stderr } = await runOpenClawDeploymentCommand(config, ["approvals", "get", "--json"], {
    timeoutMs: Math.max(config.timeout, 5) * 1000
  });
  return parseOpenClawApprovalsSnapshotFromText(`${stdout ?? ""}\n${stderr ?? ""}`);
}

async function inspectOpenClawSandboxSecurity(
  config: OpenClawConfig,
  agentIdentifier: string,
  approvalsHaveCustomEntries: boolean
): Promise<OpenClawRuntimeSecurityFinding> {
  const { stdout, stderr } = await runOpenClawDeploymentCommand(
    config,
    ["sandbox", "explain", "--agent", agentIdentifier, "--json"],
    {
      timeoutMs: Math.max(config.timeout, 5) * 1000
    }
  );
  return assessOpenClawSandboxSecurityFromText(
    `${stdout ?? ""}\n${stderr ?? ""}`,
    agentIdentifier,
    approvalsHaveCustomEntries
  );
}

async function inspectOpenClawRuntimeSecurity(
  config: OpenClawConfig,
  agentIdentifiers: string[]
): Promise<OpenClawRuntimeSecurityInspectionResult> {
  const normalizedConfig = normalizeOpenClawConfig(config);
  const uniqueAgentIdentifiers = Array.from(
    new Set(agentIdentifiers.map((value) => trimmedString(value)).filter(Boolean))
  );

  if (uniqueAgentIdentifiers.length <= 1) {
    return {
      blockingIssues: [],
      findings: [],
      approvalsHaveCustomEntries: false
    };
  }

  if (normalizedConfig.deploymentKind === "remoteServer") {
    return {
      blockingIssues: [
        "remoteServer mode does not let the desktop app verify OpenClaw sandbox/runtime policy for multi-agent workflows."
      ],
      findings: [],
      approvalsHaveCustomEntries: false
    };
  }

  let approvalsHaveCustomEntries = false;
  try {
    const approvalsSnapshot = await inspectOpenClawExecApprovalSnapshot(normalizedConfig);
    approvalsHaveCustomEntries = approvalsSnapshot.hasCustomEntries;
  } catch (error) {
    return {
      blockingIssues: [
        `Unable to inspect OpenClaw exec approvals, so the app cannot verify runtime isolation: ${blockingErrorMessage(
          error,
          "OpenClaw approvals inspection failed."
        )}`
      ],
      findings: [],
      approvalsHaveCustomEntries: false
    };
  }

  const findings: OpenClawRuntimeSecurityFinding[] = [];
  const blockingIssues: string[] = [];

  for (const agentIdentifier of uniqueAgentIdentifiers) {
    try {
      const finding = await inspectOpenClawSandboxSecurity(
        normalizedConfig,
        agentIdentifier,
        approvalsHaveCustomEntries
      );
      findings.push(finding);
      blockingIssues.push(...finding.blockingIssues);
    } catch (error) {
      blockingIssues.push(
        `Unable to inspect OpenClaw sandbox policy for agent ${agentIdentifier}: ${blockingErrorMessage(
          error,
          "OpenClaw sandbox inspection failed."
        )}`
      );
    }
  }

  return {
    blockingIssues: Array.from(new Set(blockingIssues)).sort((left, right) => left.localeCompare(right)),
    findings,
    approvalsHaveCustomEntries
  };
}

async function resolveOpenClawGovernancePaths(config: OpenClawConfig): Promise<OpenClawGovernancePaths> {
  const normalizedConfig = normalizeOpenClawConfig(config);
  const cliConfigPath = await resolveOpenClawConfigPathFromCli(normalizedConfig);
  if (cliConfigPath) {
    const rootPath = path.dirname(cliConfigPath);
    return {
      rootPath,
      configPath: cliConfigPath,
      approvalsPath: await firstExistingChildPathForConfig(normalizedConfig, rootPath, ["exec-approvals.json"])
    };
  }

  if (normalizedConfig.deploymentKind === "container") {
    const discoveredRoot = await resolveOpenClawRootPathForProbe(normalizedConfig);
    if (discoveredRoot) {
      return {
        rootPath: discoveredRoot,
        configPath: await firstExistingChildPathForConfig(normalizedConfig, discoveredRoot, ["openclaw.json"]),
        approvalsPath: await firstExistingChildPathForConfig(normalizedConfig, discoveredRoot, ["exec-approvals.json"])
      };
    }
  }

  for (const candidate of await openClawRootCandidatesForConfig(normalizedConfig)) {
    if (!candidate || !(await pathExistsForConfig(normalizedConfig, candidate))) {
      continue;
    }

    return {
      rootPath: candidate,
      configPath: await firstExistingChildPathForConfig(normalizedConfig, candidate, ["openclaw.json"]),
      approvalsPath: await firstExistingChildPathForConfig(normalizedConfig, candidate, ["exec-approvals.json"])
    };
  }

  return {
    rootPath: null,
    configPath: null,
    approvalsPath: null
  };
}

function extractConfiguredAgentBindings(configRecord: Record<string, unknown> | null) {
  const agents = jsonRecord(configRecord?.agents);
  const list = Array.isArray(agents?.list) ? agents.list : [];
  return list.flatMap((entry) => {
    const record = jsonRecord(entry);
    if (!record) {
      return [];
    }

    const agentIdentifier = firstNonEmptyString(record, ["id", "agentId", "name", "identifier"]);
    if (!agentIdentifier) {
      return [];
    }

    const subagents = jsonRecord(record.subagents);
    return [
      {
        agentIdentifier,
        allowAgents: stringArray(subagents?.allowAgents)
      }
    ];
  });
}

function extractConfiguredAgentIdentifiers(configRecord: Record<string, unknown> | null): string[] {
  return extractConfiguredAgentBindings(configRecord).map((binding) => binding.agentIdentifier);
}

function extractConfiguredAgentWorkspaces(configRecord: Record<string, unknown> | null) {
  const agents = jsonRecord(configRecord?.agents);
  const list = Array.isArray(agents?.list) ? agents.list : [];
  return list.flatMap((entry) => {
    const record = jsonRecord(entry);
    if (!record) {
      return [];
    }

    const agentIdentifier = firstNonEmptyString(record, ["id", "agentId", "name", "identifier"]);
    if (!agentIdentifier) {
      return [];
    }

    const workspacePath = firstNonEmptyString(record, ["workspace", "workspacePath", "workdir"]);
    return [
      {
        agentIdentifier,
        workspacePath
      }
    ];
  });
}

async function resolveConfiguredAgentWorkspaces(
  config: OpenClawConfig,
  configRecord: Record<string, unknown> | null
): Promise<Array<{ agentIdentifier: string; workspacePath: string | null; existsOnDisk: boolean }>> {
  const bindings = extractConfiguredAgentWorkspaces(configRecord);
  const resolved: Array<{ agentIdentifier: string; workspacePath: string | null; existsOnDisk: boolean }> = [];

  for (const binding of bindings) {
    const workspacePath = binding.workspacePath?.trim() || null;
    resolved.push({
      agentIdentifier: binding.agentIdentifier,
      workspacePath,
      existsOnDisk: workspacePath ? await pathExistsForConfig(config, workspacePath) : false
    });
  }

  return resolved;
}

async function listOpenClawAgentIdentifiers(config: OpenClawConfig): Promise<string[]> {
  try {
    const { stdout, stderr } = await runOpenClawDeploymentCommand(config, ["agents", "list"], {
      timeoutMs: Math.max(config.timeout, 5) * 1000
    });
    return parseAgentNamesFromOutput(`${stdout ?? ""}\n${stderr ?? ""}`);
  } catch {
    return [];
  }
}

function ensureObjectProperty(record: Record<string, unknown>, key: string): Record<string, unknown> {
  const existing = jsonRecord(record[key]);
  if (existing) {
    return existing;
  }

  const next: Record<string, unknown> = {};
  record[key] = next;
  return next;
}

function ensureArrayProperty(record: Record<string, unknown>, key: string): unknown[] {
  const existing = record[key];
  if (Array.isArray(existing)) {
    return existing;
  }

  const next: unknown[] = [];
  record[key] = next;
  return next;
}

function normalizedToolList(value: unknown): string[] {
  return stringArray(value).map((item) => item.toLowerCase());
}

function workspacePathKey(value: string): string {
  return value.trim().replace(/\\/g, "/").replace(/\/+/g, "/").replace(/\/$/, "").toLowerCase();
}

function safeWorkspaceSlug(agentIdentifier: string): string {
  const normalized = agentIdentifier.trim().toLowerCase().replace(/[^a-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "");
  return normalized || "agent";
}

function mergeToolList(existing: string[], additions: string[]): string[] {
  return Array.from(new Set([...existing.map((item) => item.toLowerCase()), ...additions.map((item) => item.toLowerCase())])).sort(
    (left, right) => left.localeCompare(right)
  );
}

function removeTools(existing: string[], removals: string[]): string[] {
  const removalSet = new Set(removals.map((item) => item.toLowerCase()));
  return existing.filter((item) => !removalSet.has(item.toLowerCase()));
}

function applyHighRiskToolRemediation(configRecord: Record<string, unknown>): boolean {
  const dangerousTools = ["subagents", "sessions_send", "sessions_spawn"];
  let changed = false;

  const tools = ensureObjectProperty(configRecord, "tools");
  const sandbox = ensureObjectProperty(tools, "sandbox");
  const sandboxTools = ensureObjectProperty(sandbox, "tools");
  const globalAllow = normalizedToolList(sandboxTools.allow);
  const globalDeny = normalizedToolList(sandboxTools.deny);
  const nextGlobalAllow = removeTools(globalAllow, dangerousTools);
  const nextGlobalDeny = mergeToolList(globalDeny, dangerousTools);
  if (JSON.stringify(globalAllow) !== JSON.stringify(nextGlobalAllow)) {
    sandboxTools.allow = nextGlobalAllow;
    changed = true;
  }
  if (JSON.stringify(globalDeny) !== JSON.stringify(nextGlobalDeny)) {
    sandboxTools.deny = nextGlobalDeny;
    changed = true;
  }

  const agents = ensureObjectProperty(configRecord, "agents");
  const list = ensureArrayProperty(agents, "list");
  for (const entry of list) {
    const agentRecord = jsonRecord(entry);
    if (!agentRecord) {
      continue;
    }
    const agentTools = ensureObjectProperty(ensureObjectProperty(agentRecord, "tools"), "sandbox");
    const agentSandboxTools = ensureObjectProperty(agentTools, "tools");
    const agentAllow = normalizedToolList(agentSandboxTools.allow);
    const agentDeny = normalizedToolList(agentSandboxTools.deny);
    const nextAgentAllow = removeTools(agentAllow, dangerousTools);
    const nextAgentDeny = mergeToolList(agentDeny, dangerousTools);
    if (JSON.stringify(agentAllow) !== JSON.stringify(nextAgentAllow)) {
      agentSandboxTools.allow = nextAgentAllow;
      changed = true;
    }
    if (JSON.stringify(agentDeny) !== JSON.stringify(nextAgentDeny)) {
      agentSandboxTools.deny = nextAgentDeny;
      changed = true;
    }
  }

  return changed;
}

function applySubagentAllowlistRemediation(configRecord: Record<string, unknown>): boolean {
  let changed = false;
  const agents = ensureObjectProperty(configRecord, "agents");
  const list = ensureArrayProperty(agents, "list");
  for (const entry of list) {
    const agentRecord = jsonRecord(entry);
    if (!agentRecord) {
      continue;
    }
    const subagents = ensureObjectProperty(agentRecord, "subagents");
    const allowAgents = stringArray(subagents.allowAgents);
    if (allowAgents.length > 0 || !Array.isArray(subagents.allowAgents)) {
      subagents.allowAgents = [];
      changed = true;
    }
  }
  return changed;
}

function applyWorkspaceIsolationRemediation(configRecord: Record<string, unknown>, rootPath: string): { changed: boolean; workspacePaths: string[] } {
  const agents = ensureObjectProperty(configRecord, "agents");
  const list = ensureArrayProperty(agents, "list");
  const seenWorkspaceKeys = new Map<string, number>();
  const workspacePathsToCreate = new Set<string>();
  let changed = false;

  for (const entry of list) {
    const agentRecord = jsonRecord(entry);
    if (!agentRecord) {
      continue;
    }
    const agentIdentifier = firstNonEmptyString(agentRecord, ["id", "agentId", "name", "identifier"]);
    if (!agentIdentifier) {
      continue;
    }

    const currentWorkspace = firstNonEmptyString(agentRecord, ["workspace", "workspacePath", "workdir"]);
    const currentWorkspaceKey = currentWorkspace ? workspacePathKey(currentWorkspace) : "";
    const isDuplicate = currentWorkspaceKey ? (seenWorkspaceKeys.get(currentWorkspaceKey) ?? 0) > 0 : false;
    const needsReplacement = !currentWorkspace || !existsSync(currentWorkspace) || isDuplicate;
    if (!needsReplacement) {
      seenWorkspaceKeys.set(currentWorkspaceKey, (seenWorkspaceKeys.get(currentWorkspaceKey) ?? 0) + 1);
      workspacePathsToCreate.add(currentWorkspace);
      continue;
    }

    let nextWorkspace = path.join(rootPath, `workspace-${safeWorkspaceSlug(agentIdentifier)}`);
    let suffix = 2;
    while (seenWorkspaceKeys.has(workspacePathKey(nextWorkspace))) {
      nextWorkspace = path.join(rootPath, `workspace-${safeWorkspaceSlug(agentIdentifier)}-${suffix}`);
      suffix += 1;
    }

    if (currentWorkspace !== nextWorkspace) {
      agentRecord.workspace = nextWorkspace;
      changed = true;
    }
    const nextKey = workspacePathKey(nextWorkspace);
    seenWorkspaceKeys.set(nextKey, (seenWorkspaceKeys.get(nextKey) ?? 0) + 1);
    workspacePathsToCreate.add(nextWorkspace);
  }

  return {
    changed,
    workspacePaths: Array.from(workspacePathsToCreate).sort((left, right) => left.localeCompare(right))
  };
}

function applyElevatedExecutionRemediation(configRecord: Record<string, unknown>): boolean {
  const tools = ensureObjectProperty(configRecord, "tools");
  const elevated = ensureObjectProperty(tools, "elevated");
  if (elevated.enabled === false) {
    return false;
  }

  elevated.enabled = false;
  return true;
}

function applyExecApprovalsRemediation(approvalsRecord: Record<string, unknown>): boolean {
  const defaults = jsonRecord(approvalsRecord.defaults);
  const agents = jsonRecord(approvalsRecord.agents);
  const hasChanges = Boolean((defaults && Object.keys(defaults).length > 0) || (agents && Object.keys(agents).length > 0));
  approvalsRecord.version = typeof approvalsRecord.version === "number" ? approvalsRecord.version : 1;
  approvalsRecord.defaults = {};
  approvalsRecord.agents = {};
  return hasChanges;
}

async function auditOpenClawRuntimeGovernance(config: OpenClawConfig): Promise<OpenClawGovernanceAuditReport> {
  const normalizedConfig = normalizeOpenClawConfig(config);
  const governancePaths = await resolveOpenClawGovernancePaths(normalizedConfig);
  const configRecord = governancePaths.configPath ? await readJSONRecordForConfig(normalizedConfig, governancePaths.configPath) : null;
  const configuredAgentBindings = extractConfiguredAgentBindings(configRecord);
  const configuredWorkspaceBindings = await resolveConfiguredAgentWorkspaces(normalizedConfig, configRecord);
  const cliAgentIdentifiers = await listOpenClawAgentIdentifiers(normalizedConfig);
  const detectedAgents = await inspectOpenClawAgents(normalizedConfig, cliAgentIdentifiers);
  const agentIdentifiers = Array.from(
    new Set(
      [
        ...cliAgentIdentifiers,
        ...extractConfiguredAgentIdentifiers(configRecord),
        ...detectedAgents.map((record) => record.name)
      ]
        .map((value) => value.trim())
        .filter(Boolean)
    )
  );
  const runtimeSecurity = await inspectOpenClawRuntimeSecurity(normalizedConfig, agentIdentifiers);

  return buildOpenClawGovernanceAuditReport({
    auditedAt: new Date().toISOString(),
    deploymentKind: normalizedConfig.deploymentKind,
    rootPath: governancePaths.rootPath,
    configPath: governancePaths.configPath,
    approvalsPath: governancePaths.approvalsPath,
    agentIdentifiers,
    subagentBindings: configuredAgentBindings,
    workspaceBindings: configuredWorkspaceBindings,
    runtimeSecurity
  });
}

async function remediateOpenClawRuntimeGovernance(
  request: OpenClawGovernanceRemediationRequest
): Promise<OpenClawGovernanceRemediationResult> {
  const normalizedConfig = normalizeOpenClawConfig(request.config);
  const initialReport = await auditOpenClawRuntimeGovernance(normalizedConfig);
  const safeActionIds = new Set(
    initialReport.proposedActions.filter((action) => action.safeToAutoApply).map((action) => action.id)
  );
  const requestedActionIds = Array.isArray(request.actionIds)
    ? Array.from(new Set(request.actionIds.map((actionId) => actionId.trim()).filter(Boolean)))
    : [];
  const selectedActionIds =
    requestedActionIds.length > 0
      ? requestedActionIds.filter((actionId) => safeActionIds.has(actionId))
      : Array.from(safeActionIds);
  const selectedActionSet = new Set(selectedActionIds);
  const selectedActionsBeforeDependencies = initialReport.proposedActions.filter((action) => selectedActionSet.has(action.id));
  const shouldAutoIncludeSandboxRecreate =
    selectedActionsBeforeDependencies.some((action) => action.requiresSandboxRecreate) &&
    safeActionIds.has("recreate-sandbox-containers");
  if (shouldAutoIncludeSandboxRecreate) {
    selectedActionSet.add("recreate-sandbox-containers");
  }
  const safeActions = initialReport.proposedActions.filter((action) => selectedActionSet.has(action.id));

  if (safeActionIds.size === 0) {
    return {
      report: initialReport,
      appliedActionIds: [],
      skippedActionIds: initialReport.proposedActions.map((action) => action.id),
      notes: ["No safe auto-remediation actions are available for the current OpenClaw deployment."],
      backupPaths: []
    };
  }

  if (selectedActionIds.length === 0) {
    return {
      report: initialReport,
      appliedActionIds: [],
      skippedActionIds: initialReport.proposedActions.map((action) => action.id),
      notes: ["No remediation actions were selected for this run."],
      backupPaths: []
    };
  }

  const governancePaths = await resolveOpenClawGovernancePaths(normalizedConfig);
  const configRecord = governancePaths.configPath
    ? await readJSONRecordForConfig(normalizedConfig, governancePaths.configPath)
    : null;
  const approvalsRecord = governancePaths.approvalsPath
    ? await readJSONRecordForConfig(normalizedConfig, governancePaths.approvalsPath)
    : null;
  const appliedActionIds: string[] = [];
  const skippedActionIds = initialReport.proposedActions
    .map((action) => action.id)
    .filter((actionId) => !selectedActionSet.has(actionId));
  const notes: string[] = [];
  const backupPaths: string[] = [];
  let configModified = false;
  let approvalsModified = false;
  let shouldRecreateSandbox = false;
  const workspacePathsToCreate = new Set<string>();

  if (shouldAutoIncludeSandboxRecreate && !selectedActionIds.includes("recreate-sandbox-containers")) {
    notes.push("Automatically included sandbox recreation because one or more selected config fixes require it before they fully take effect.");
  }

  for (const action of safeActions) {
    switch (action.id) {
      case "disable-high-risk-session-tools":
        if (!configRecord || !governancePaths.configPath) {
          skippedActionIds.push(action.id);
          notes.push("Skipped high-risk tool remediation because `openclaw.json` could not be loaded.");
          continue;
        }
        if (applyHighRiskToolRemediation(configRecord)) {
          configModified = true;
        }
        appliedActionIds.push(action.id);
        shouldRecreateSandbox = true;
        break;
      case "clear-subagent-allowlists":
        if (!configRecord || !governancePaths.configPath) {
          skippedActionIds.push(action.id);
          notes.push("Skipped subagent allowlist remediation because `openclaw.json` could not be loaded.");
          continue;
        }
        if (applySubagentAllowlistRemediation(configRecord)) {
          configModified = true;
        }
        appliedActionIds.push(action.id);
        break;
      case "disable-elevated-execution":
        if (!configRecord || !governancePaths.configPath) {
          skippedActionIds.push(action.id);
          notes.push("Skipped elevated execution remediation because `openclaw.json` could not be loaded.");
          continue;
        }
        if (applyElevatedExecutionRemediation(configRecord)) {
          configModified = true;
        }
        appliedActionIds.push(action.id);
        shouldRecreateSandbox = true;
        break;
      case "repair-agent-workspaces":
        if (!configRecord || !governancePaths.configPath || !governancePaths.rootPath) {
          skippedActionIds.push(action.id);
          notes.push("Skipped workspace remediation because the OpenClaw root or `openclaw.json` could not be loaded.");
          continue;
        }
        {
          const workspaceResult = applyWorkspaceIsolationRemediation(configRecord, governancePaths.rootPath);
          if (workspaceResult.changed) {
            configModified = true;
          }
          for (const workspacePath of workspaceResult.workspacePaths) {
            workspacePathsToCreate.add(workspacePath);
          }
        }
        appliedActionIds.push(action.id);
        break;
      case "clear-exec-approvals":
        if (!approvalsRecord || !governancePaths.approvalsPath) {
          skippedActionIds.push(action.id);
          notes.push("Skipped exec approvals remediation because `exec-approvals.json` could not be loaded.");
          continue;
        }
        if (applyExecApprovalsRemediation(approvalsRecord)) {
          approvalsModified = true;
        }
        appliedActionIds.push(action.id);
        break;
      case "recreate-sandbox-containers":
        shouldRecreateSandbox = true;
        break;
      default:
        skippedActionIds.push(action.id);
        notes.push(`Skipped unsupported remediation action: ${action.id}`);
    }
  }

  if (configModified && governancePaths.configPath && configRecord) {
    backupPaths.push(await backupGovernanceFileForConfig(normalizedConfig, governancePaths.configPath));
    await writeJSONFileForConfig(normalizedConfig, governancePaths.configPath, configRecord);
  }

  if (workspacePathsToCreate.size > 0) {
    for (const workspacePath of workspacePathsToCreate) {
      await ensureDirectoryForConfig(normalizedConfig, workspacePath);
    }
    notes.push(`Ensured ${workspacePathsToCreate.size} OpenClaw workspace director${workspacePathsToCreate.size === 1 ? "y" : "ies"} exist on disk.`);
  }

  if (approvalsModified && governancePaths.approvalsPath && approvalsRecord) {
    backupPaths.push(await backupGovernanceFileForConfig(normalizedConfig, governancePaths.approvalsPath));
    await writeJSONFileForConfig(normalizedConfig, governancePaths.approvalsPath, approvalsRecord);
  }

  const recreateAction = safeActions.find((action) => action.id === "recreate-sandbox-containers");
  if (shouldRecreateSandbox && recreateAction) {
    try {
      await runOpenClawDeploymentCommand(normalizedConfig, ["sandbox", "recreate", "--all", "--force"], {
        timeoutMs: Math.max(normalizedConfig.timeout, 15) * 1000
      });
      appliedActionIds.push(recreateAction.id);
      notes.push("Recreated OpenClaw sandbox containers so updated sandbox settings can take effect on the next run.");
    } catch (error) {
      skippedActionIds.push(recreateAction.id);
      notes.push(
        `OpenClaw config files were updated, but sandbox recreation did not complete automatically: ${blockingErrorMessage(
          error,
          "OpenClaw sandbox recreation failed."
        )}`
      );
    }
  }

  const report = await auditOpenClawRuntimeGovernance(normalizedConfig);
  return {
    report,
    appliedActionIds: Array.from(new Set(appliedActionIds)),
    skippedActionIds: Array.from(new Set(skippedActionIds)),
    notes,
    backupPaths
  };
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
  return connectOpenClaw(config);
}

async function probeGatewayEndpoint(
  config: OpenClawConfig,
  sourceDeploymentKind: OpenClawConfig["deploymentKind"] = config.deploymentKind
): Promise<GatewayTransportProbeResult> {
  const endpoint = buildOpenClawWebSocketUrl(config);
  const timeoutMs = Math.max(config.timeout, 5) * 1000;
  const startedAt = Date.now();
  const deviceIdentity = await loadOrCreateDesktopGatewayDeviceIdentity();

  return new Promise<GatewayTransportProbeResult>((resolve) => {
    const websocketURL = new URL(endpoint);
    const websocketKey = randomBytes(16).toString("base64");
    const expectedAccept = createHash("sha1")
      .update(`${websocketKey}258EAFA5-E914-47DA-95CA-C5AB0DC85B11`)
      .digest("base64");
    const socket = config.useSSL
      ? tls.connect({
          host: websocketURL.hostname,
          port: Number(websocketURL.port || (config.useSSL ? 443 : 80)),
          servername: websocketURL.hostname
        })
      : net.createConnection({
          host: websocketURL.hostname,
          port: Number(websocketURL.port || (config.useSSL ? 443 : 80))
        });

    let settled = false;
    let headerBuffer = Buffer.alloc(0);
    let frameBuffer = Buffer.alloc(0);
    let headersParsed = false;
    let awaitingConnectResponse = false;
    const connectRequestId = crypto.randomUUID();

    const finish = (result: GatewayTransportProbeResult) => {
      if (settled) {
        return;
      }
      settled = true;
      socket.removeAllListeners();
      socket.destroy();
      resolve(result);
    };

    const handshakeRequest = [
      `GET ${websocketURL.pathname || "/"} HTTP/1.1`,
      `Host: ${websocketURL.host}`,
      "Upgrade: websocket",
      "Connection: Upgrade",
      `Sec-WebSocket-Key: ${websocketKey}`,
      "Sec-WebSocket-Version: 13",
      "User-Agent: Multi-Agent-Flow/desktop-probe",
      ...(config.apiKey ? [`Authorization: Bearer ${config.apiKey}`] : []),
      "\r\n"
    ].join("\r\n");

    socket.setTimeout(timeoutMs);

    socket.once(config.useSSL ? "secureConnect" : "connect", () => {
      socket.write(handshakeRequest);
    });

    socket.on("data", (chunk: Buffer) => {
      if (!headersParsed) {
        headerBuffer = Buffer.concat([headerBuffer, chunk]);
        const headerBoundary = headerBuffer.indexOf("\r\n\r\n");
        if (headerBoundary < 0) {
          return;
        }

        const rawHeaders = headerBuffer.subarray(0, headerBoundary).toString("utf8");
        frameBuffer = headerBuffer.subarray(headerBoundary + 4);
        headerBuffer = Buffer.alloc(0);
        headersParsed = true;

        const headerLines = rawHeaders.split("\r\n");
        const statusLine = headerLines.shift() ?? "";
        const statusMatch = statusLine.match(/^HTTP\/1\.[01]\s+(\d{3})\b/);
        const statusCode = statusMatch ? Number(statusMatch[1]) : 0;
        const responseHeaders = Object.fromEntries(
          headerLines.flatMap((line) => {
            const separatorIndex = line.indexOf(":");
            if (separatorIndex < 0) {
              return [];
            }
            return [[line.slice(0, separatorIndex).trim().toLowerCase(), line.slice(separatorIndex + 1).trim()]];
          })
        );

        if (statusCode !== 101) {
          finish({
            reachable: false,
            authenticated: false,
            latencyMs: Date.now() - startedAt,
            message: statusCode > 0
              ? `Gateway websocket upgrade failed with HTTP ${statusCode} at ${endpoint}.`
              : `Gateway websocket upgrade failed at ${endpoint}.`,
            warnings: []
          });
          return;
        }

        if (responseHeaders["sec-websocket-accept"] !== expectedAccept) {
          finish({
            reachable: false,
            authenticated: false,
            latencyMs: Date.now() - startedAt,
            message: `Gateway websocket accept key validation failed at ${endpoint}.`,
            warnings: []
          });
          return;
        }
      } else {
        frameBuffer = Buffer.concat([frameBuffer, chunk]);
      }

      try {
        while (true) {
          const frame = tryParseWebSocketTextFrame(frameBuffer);
          if (!frame) {
            return;
          }
          frameBuffer = Buffer.from(frame.remaining);

          if (frame.opcode === 0x8) {
            finish({
              reachable: true,
              authenticated: false,
              latencyMs: Date.now() - startedAt,
              message: awaitingConnectResponse
                ? `Gateway websocket closed before the connect response completed at ${endpoint}.`
                : `Gateway websocket closed before probe challenge completed at ${endpoint}.`,
              warnings: []
            });
            return;
          }

          if (frame.opcode !== 0x1) {
            continue;
          }

          let payload: Record<string, unknown>;
          try {
            payload = JSON.parse(frame.payload) as Record<string, unknown>;
          } catch {
            finish({
              reachable: true,
              authenticated: false,
              latencyMs: Date.now() - startedAt,
              message: `Gateway websocket upgraded at ${endpoint}, but the probe could not parse a JSON frame.`,
              warnings: []
            });
            return;
          }

          if (!awaitingConnectResponse) {
            const isChallenge =
              payload["type"] === "event" &&
              payload["event"] === "connect.challenge" &&
              typeof payload["payload"] === "object" &&
              payload["payload"] !== null;
            if (!isChallenge) {
              finish({
                reachable: true,
                authenticated: false,
                latencyMs: Date.now() - startedAt,
                message: `Gateway websocket upgraded at ${endpoint}, but protocol challenge did not match the expected handshake.`,
                warnings: []
              });
              return;
            }

            const connectFrame = {
              type: "req",
              id: connectRequestId,
              method: "connect",
              params: buildGatewayConnectParams(
                config,
                deviceIdentity,
                payload["payload"] as Record<string, unknown>
              )
            };
            socket.write(createMaskedWebSocketTextFrame(JSON.stringify(connectFrame)));
            awaitingConnectResponse = true;
            continue;
          }

          const isExpectedResponse =
            payload["type"] === "res" &&
            payload["id"] === connectRequestId;
          if (!isExpectedResponse) {
            continue;
          }

          const ok = payload["ok"] === true;
          const errorPayload =
            payload["error"] && typeof payload["error"] === "object" && !Array.isArray(payload["error"])
              ? (payload["error"] as Record<string, unknown>)
              : null;
          const errorMessage =
            typeof errorPayload?.message === "string" && errorPayload.message.trim().length > 0
              ? errorPayload.message.trim()
              : null;
          const warnings =
            sourceDeploymentKind === "remoteServer"
              ? ["Desktop shell probe now validates websocket challenge plus RPC connect, but device-identity parity with the Swift gateway client is still pending."]
              : [];

          finish({
            reachable: true,
            authenticated: ok,
            latencyMs: Date.now() - startedAt,
            message: ok
              ? `Gateway websocket challenge and connect succeeded at ${endpoint}.`
              : errorMessage || `Gateway connect request was rejected at ${endpoint}.`,
            warnings
          });
          return;
        }
      } catch (error) {
        finish({
          reachable: false,
          authenticated: false,
          latencyMs: Date.now() - startedAt,
          message: error instanceof Error ? error.message : String(error),
          warnings: []
        });
      }
    });

    socket.once("timeout", () => {
      finish({
        reachable: false,
        authenticated: false,
        latencyMs: Date.now() - startedAt,
        message: `Gateway websocket probe timed out at ${endpoint}.`,
        warnings: []
      });
    });

    socket.once("error", (error) => {
      finish({
        reachable: false,
        authenticated: false,
        latencyMs: Date.now() - startedAt,
        message: error instanceof Error ? error.message : String(error),
        warnings: []
      });
    });

    socket.once("end", () => {
      finish({
        reachable: headersParsed,
        authenticated: false,
        latencyMs: Date.now() - startedAt,
        message: headersParsed
          ? `Gateway websocket closed before the probe completed at ${endpoint}.`
          : `Gateway websocket closed before upgrade completed at ${endpoint}.`,
        warnings: []
      });
    });
  });
}

async function probeOpenClaw(config: OpenClawConfig): Promise<OpenClawProbeReportSnapshot> {
  const normalizedConfig = normalizeOpenClawConfig(config);
  const availableAgents: string[] = [];
  const fallbackEndpoint = buildOpenClawBaseUrl(normalizedConfig);
  let cliFailureMessage: string | null = null;
  let cliAvailable = false;
  let agentListingAvailable = false;

  if (normalizedConfig.deploymentKind === "container" && !normalizedConfig.container.containerName.trim()) {
    const failureMessage = "Container name is required.";
    const capabilities = createDefaultOpenClawCapabilities();
    const failedHealth = {
      ...createDefaultOpenClawHealth(failureMessage),
      lastProbeAt: toSwiftDate(),
      degradationReason: failureMessage
    };

    return {
      success: false,
      deploymentKind: normalizedConfig.deploymentKind,
      endpoint: fallbackEndpoint,
      layers: null,
      capabilities,
      health: failedHealth,
      availableAgents: [],
      message: failureMessage,
      warnings: [],
      sourceOfTruth: OPENCLAW_PROBE_SOURCE,
      observedDefaultTransports: []
    };
  }

  const gatewayProbeConfig = await resolveGatewayProbeConfig(normalizedConfig);
  const endpoint = buildOpenClawBaseUrl(gatewayProbeConfig ?? normalizedConfig);

  if (normalizedConfig.deploymentKind !== "remoteServer") {
    try {
      const { stdout, stderr } = await runOpenClawDeploymentCommand(normalizedConfig, ["agents", "list"], {
        timeoutMs: Math.max(normalizedConfig.timeout, 5) * 1000
      });
      const listedAgents = parseAgentNamesFromOutput(`${stdout ?? ""}\n${stderr ?? ""}`);
      availableAgents.push(...listedAgents);
      cliAvailable = true;
      agentListingAvailable = true;
    } catch (error) {
      cliFailureMessage = error instanceof Error ? error.message : String(error);
    }
  }

  const probedAt = toSwiftDate();
  const gatewayProbe = gatewayProbeConfig
    ? await probeGatewayEndpoint(gatewayProbeConfig, normalizedConfig.deploymentKind)
    : {
        reachable: false,
        authenticated: false,
        latencyMs: null,
        message:
          normalizedConfig.deploymentKind === "container"
            ? "OpenClaw CLI 可用，但容器 Gateway 配置不可用。"
            : "OpenClaw CLI 可用，但本地 Gateway 配置不可用。",
        warnings: []
      };
  const probeContract = buildOpenClawProbeContract({
    config: normalizedConfig,
    endpoint,
    availableAgents,
    cliAvailable,
    agentListingAvailable,
    cliFailureMessage,
    gatewayProbe,
    probedAt
  });

  return {
    success: probeContract.success,
    deploymentKind: normalizedConfig.deploymentKind,
    endpoint,
    layers: probeContract.layers,
    capabilities: probeContract.capabilities,
    health: probeContract.health,
    availableAgents,
    message: probeContract.message,
    warnings: probeContract.warnings,
    sourceOfTruth: OPENCLAW_PROBE_SOURCE,
    observedDefaultTransports: probeContract.observedDefaultTransports
  };
}

function buildConnectOpenClawResult(
  config: OpenClawConfig,
  probeReport: OpenClawProbeReportSnapshot,
  detectedAgents: ProjectOpenClawDetectedAgentRecord[]
): OpenClawActionResult {
  const availableAgents =
    probeReport.availableAgents.length > 0 ? probeReport.availableAgents : detectedAgents.map((item) => item.name);

  return {
    success: probeReport.success,
    message: probeReport.success
      ? `Connected to OpenClaw. Found ${availableAgents.length} agent(s).`
      : probeReport.layers
        ? `${probeReport.message} (${formatOpenClawProbeLayers(probeReport.layers)})`
        : probeReport.message,
    isConnected: probeReport.success,
    availableAgents,
    activeAgents: probeReport.success ? buildActiveAgentRecords(availableAgents) : [],
    detectedAgents,
    connectionState: buildConnectionStateFromProbeReport({
      deploymentKind: config.deploymentKind,
      report: probeReport,
      successPhase: "ready"
    }),
    probeReport
  };
}

function buildDetectOpenClawResult(
  config: OpenClawConfig,
  probeReport: OpenClawProbeReportSnapshot,
  detectedAgents: ProjectOpenClawDetectedAgentRecord[]
): OpenClawActionResult {
  const availableAgents =
    probeReport.availableAgents.length > 0 ? probeReport.availableAgents : detectedAgents.map((item) => item.name);
  const success = probeReport.success || detectedAgents.length > 0 || availableAgents.length > 0;
  const message = detectedAgents.length > 0
    ? `Detected ${detectedAgents.length} OpenClaw agent(s).`
    : probeReport.success
      ? "OpenClaw probe succeeded, but no agents were detected."
      : probeReport.layers
        ? `${probeReport.message} (${formatOpenClawProbeLayers(probeReport.layers)})`
        : probeReport.message;

  return {
    success,
    message,
    isConnected: false,
    availableAgents,
    activeAgents: [],
    detectedAgents,
    connectionState: buildConnectionStateFromProbeReport({
      deploymentKind: config.deploymentKind,
      report: probeReport,
      successPhase: "probed",
      fallbackPhase: success ? "degraded" : undefined,
      messageOverride: message
    }),
    probeReport
  };
}

async function connectOpenClaw(config: OpenClawConfig): Promise<OpenClawActionResult> {
  const normalizedConfig = normalizeOpenClawConfig(config);
  const probeReport = await probeOpenClaw(normalizedConfig);
  const detectedAgents = probeReport.success
    ? await inspectOpenClawAgents(normalizedConfig, probeReport.availableAgents)
    : [];
  return buildConnectOpenClawResult(normalizedConfig, probeReport, detectedAgents);
}

async function detectOpenClawAgents(config: OpenClawConfig): Promise<OpenClawActionResult> {
  const normalizedConfig = normalizeOpenClawConfig(config);
  const probeReport = await probeOpenClaw(normalizedConfig);
  const detectedAgents = await inspectOpenClawAgents(normalizedConfig, probeReport.availableAgents);
  return buildDetectOpenClawResult(normalizedConfig, probeReport, detectedAgents);
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

  ipcMain.handle("openClaw:probe", async (_event, config: OpenClawConfig): Promise<OpenClawProbeReportSnapshot> => {
    return probeOpenClaw(config);
  });

  ipcMain.handle("openClaw:detect", async (_event, config: OpenClawConfig): Promise<OpenClawActionResult> => {
    return detectOpenClawAgents(config);
  });

  ipcMain.handle("openClaw:disconnect", async (_event, config: OpenClawConfig): Promise<OpenClawActionResult> => {
    const normalizedConfig = normalizeOpenClawConfig(config);
    return {
      success: true,
      message: "Disconnected from OpenClaw.",
      isConnected: false,
      availableAgents: [],
      activeAgents: [],
      detectedAgents: [],
      connectionState: buildDetachedOpenClawConnectionState(
        normalizedConfig.deploymentKind,
        toSwiftDate(),
        "OpenClaw session detached."
      ),
      probeReport: null
    };
  });

  ipcMain.handle(
    "openClaw:executeAgent",
    async (_event, payload: { config: OpenClawConfig; request: OpenClawAgentExecutionRequest }): Promise<OpenClawAgentExecutionResult> => {
      return executeOpenClawAgent(payload.config, payload.request);
    }
  );

  ipcMain.handle(
    "openClaw:inspectRuntimeSecurity",
    async (
      _event,
      payload: { config: OpenClawConfig; agentIdentifiers: string[] }
    ): Promise<OpenClawRuntimeSecurityInspectionResult> => {
      return inspectOpenClawRuntimeSecurity(payload.config, payload.agentIdentifiers);
    }
  );

  ipcMain.handle("openClaw:auditRuntimeGovernance", async (_event, config: OpenClawConfig): Promise<OpenClawGovernanceAuditReport> => {
    return auditOpenClawRuntimeGovernance(config);
  });

  ipcMain.handle(
    "openClaw:remediateRuntimeGovernance",
    async (_event, request: OpenClawGovernanceRemediationRequest): Promise<OpenClawGovernanceRemediationResult> => {
      return remediateOpenClawRuntimeGovernance(request);
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
