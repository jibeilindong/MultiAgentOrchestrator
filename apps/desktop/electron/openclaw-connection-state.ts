import type {
  OpenClawConfig,
  OpenClawConnectionCapabilitiesSnapshot,
  OpenClawConnectionHealthSnapshot,
  OpenClawConnectionPhase,
  OpenClawConnectionStateSnapshot,
  OpenClawProbeLayersSnapshot,
  OpenClawProbeLayerState,
  OpenClawProbeReportSnapshot,
  SwiftDate
} from "@multi-agent-flow/domain";

export interface GatewayTransportProbeResult {
  reachable: boolean;
  authenticated: boolean;
  latencyMs: number | null;
  message: string;
  warnings: string[];
}

export type OpenClawProbeLayers = OpenClawProbeLayersSnapshot;

export function createDefaultOpenClawCapabilities(): OpenClawConnectionCapabilitiesSnapshot {
  return {
    cliAvailable: false,
    gatewayReachable: false,
    gatewayAuthenticated: false,
    agentListingAvailable: false,
    sessionHistoryAvailable: false,
    gatewayAgentAvailable: false,
    gatewayChatAvailable: false,
    projectAttachmentSupported: false
  };
}

export function createDefaultOpenClawHealth(message: string | null = null): OpenClawConnectionHealthSnapshot {
  return {
    lastProbeAt: null,
    lastHeartbeatAt: null,
    latencyMs: null,
    degradationReason: null,
    lastMessage: message
  };
}

export function createOpenClawConnectionState(
  deploymentKind: OpenClawConfig["deploymentKind"],
  phase: OpenClawConnectionPhase,
  capabilities: OpenClawConnectionCapabilitiesSnapshot,
  health: OpenClawConnectionHealthSnapshot
): OpenClawConnectionStateSnapshot {
  return {
    phase,
    deploymentKind,
    capabilities,
    health
  };
}

export function formatOpenClawProbeLayers(layers: OpenClawProbeLayers): string {
  return `transport=${layers.transport}, auth=${layers.authentication}, session=${layers.session}, inventory=${layers.inventory}`;
}

function hasProbeLayerDegradation(layers: OpenClawProbeLayers): boolean {
  return Object.values(layers).some((value) => value !== "ready" && value !== "not_required");
}

export function inferProbePhase(
  report: OpenClawProbeReportSnapshot,
  successPhase: OpenClawConnectionPhase = "probed"
): OpenClawConnectionPhase {
  if (report.success) {
    return successPhase;
  }

  return report.capabilities.cliAvailable || report.capabilities.gatewayReachable || report.availableAgents.length > 0
    ? "degraded"
    : "failed";
}

export function buildDetachedOpenClawConnectionState(
  deploymentKind: OpenClawConfig["deploymentKind"],
  disconnectedAt: SwiftDate,
  message = "OpenClaw session detached."
): OpenClawConnectionStateSnapshot {
  return createOpenClawConnectionState(
    deploymentKind,
    "detached",
    createDefaultOpenClawCapabilities(),
    {
      ...createDefaultOpenClawHealth(message),
      lastProbeAt: disconnectedAt
    }
  );
}

export function buildConnectionStateFromProbeReport(input: {
  deploymentKind: OpenClawConfig["deploymentKind"];
  report: OpenClawProbeReportSnapshot;
  successPhase?: OpenClawConnectionPhase;
  fallbackPhase?: OpenClawConnectionPhase;
  messageOverride?: string;
}): OpenClawConnectionStateSnapshot {
  const { deploymentKind, report, successPhase = "probed", fallbackPhase, messageOverride } = input;
  const phase = report.success ? successPhase : fallbackPhase ?? inferProbePhase(report, successPhase);

  return createOpenClawConnectionState(deploymentKind, phase, report.capabilities, {
    ...report.health,
    lastMessage: messageOverride ?? report.health.lastMessage ?? report.message
  });
}

export function buildOpenClawProbeContract(input: {
  config: OpenClawConfig;
  endpoint: string;
  availableAgents: string[];
  cliAvailable: boolean;
  agentListingAvailable: boolean;
  cliFailureMessage?: string | null;
  gatewayProbe?: GatewayTransportProbeResult | null;
  probedAt: SwiftDate;
}): {
  success: boolean;
  layers: OpenClawProbeLayers;
  capabilities: OpenClawConnectionCapabilitiesSnapshot;
  health: OpenClawConnectionHealthSnapshot;
  message: string;
  warnings: string[];
  observedDefaultTransports: string[];
} {
  const { config, endpoint, availableAgents, cliAvailable, agentListingAvailable, cliFailureMessage, gatewayProbe, probedAt } = input;
  const capabilities = createDefaultOpenClawCapabilities();
  const warnings: string[] = [];
  const layers: OpenClawProbeLayers = {
    transport: "unavailable",
    authentication: "unavailable",
    session: "unavailable",
    inventory: "unavailable"
  };

  capabilities.cliAvailable = cliAvailable;
  capabilities.agentListingAvailable = agentListingAvailable;

  if (config.deploymentKind === "container") {
    layers.transport = cliAvailable ? "ready" : "unavailable";
    layers.authentication = "not_required";
    layers.session = cliAvailable && agentListingAvailable ? "ready" : cliAvailable ? "degraded" : "unavailable";
    layers.inventory = agentListingAvailable ? "ready" : cliAvailable ? "degraded" : "unavailable";
  } else if (config.deploymentKind === "remoteServer") {
    layers.transport = gatewayProbe?.reachable ? "ready" : "unavailable";
    layers.authentication = gatewayProbe?.reachable
      ? gatewayProbe.authenticated
        ? "ready"
        : "degraded"
      : "unavailable";
    layers.session = gatewayProbe?.authenticated ? "ready" : gatewayProbe?.reachable ? "degraded" : "unavailable";
    layers.inventory = availableAgents.length > 0 ? "ready" : gatewayProbe?.authenticated ? "degraded" : "unavailable";
  } else {
    layers.transport =
      cliAvailable && gatewayProbe?.reachable ? "ready" : cliAvailable || gatewayProbe?.reachable ? "degraded" : "unavailable";
    layers.authentication = gatewayProbe?.reachable
      ? gatewayProbe.authenticated
        ? "ready"
        : "degraded"
      : cliAvailable
        ? "degraded"
        : "unavailable";
    layers.session =
      cliAvailable && agentListingAvailable && gatewayProbe?.authenticated
        ? "ready"
        : cliAvailable || gatewayProbe?.reachable
          ? "degraded"
          : "unavailable";
    layers.inventory = agentListingAvailable ? "ready" : cliAvailable ? "degraded" : "unavailable";
  }

  if (cliFailureMessage) {
    warnings.push(`CLI probe failed: ${cliFailureMessage}`);
  }

  if (gatewayProbe) {
    warnings.push(...gatewayProbe.warnings);
    capabilities.gatewayReachable = gatewayProbe.reachable;
    capabilities.gatewayAuthenticated = gatewayProbe.authenticated;
    capabilities.gatewayAgentAvailable = gatewayProbe.authenticated;
    capabilities.gatewayChatAvailable = gatewayProbe.authenticated;
    capabilities.sessionHistoryAvailable = gatewayProbe.authenticated;
  } else if (config.deploymentKind === "container") {
    warnings.push("Container desktop probe currently validates CLI and container-backed config discovery; host-side gateway handshake is not required.");
  }

  capabilities.projectAttachmentSupported = config.deploymentKind !== "remoteServer" && capabilities.cliAvailable;

  const success =
    config.deploymentKind === "remoteServer"
      ? capabilities.gatewayAuthenticated
      : config.deploymentKind === "container"
        ? capabilities.cliAvailable && capabilities.agentListingAvailable
        : capabilities.cliAvailable && capabilities.agentListingAvailable && capabilities.gatewayAuthenticated;

  let degradationReason: string | null = null;
  if (!success) {
    const reasons: string[] = [];
    if (config.deploymentKind !== "remoteServer" && !capabilities.cliAvailable) {
      reasons.push(cliFailureMessage || "OpenClaw CLI probe failed.");
    }
    if (config.deploymentKind !== "container" && gatewayProbe) {
      if (!capabilities.gatewayReachable) {
        reasons.push(gatewayProbe.message || "OpenClaw gateway is unreachable.");
      } else if (!capabilities.gatewayAuthenticated) {
        reasons.push(gatewayProbe.message || "OpenClaw gateway authentication failed.");
      }
    }
    degradationReason = reasons.join(" ").trim() || "OpenClaw probe failed.";
  }

  const message = success
    ? config.deploymentKind === "remoteServer"
      ? `Connected to remote OpenClaw gateway at ${endpoint}.`
      : config.deploymentKind === "container"
        ? `Connected to OpenClaw container CLI. Found ${availableAgents.length} agent(s).`
        : `Connected to OpenClaw CLI and gateway. Found ${availableAgents.length} agent(s).`
    : degradationReason ?? gatewayProbe?.message ?? "OpenClaw probe failed.";

  if (hasProbeLayerDegradation(layers)) {
    warnings.push(`Probe layers: ${formatOpenClawProbeLayers(layers)}.`);
  }

  return {
    success,
    layers,
    capabilities,
    health: {
      lastProbeAt: probedAt,
      lastHeartbeatAt: capabilities.gatewayAuthenticated ? probedAt : null,
      latencyMs: gatewayProbe?.latencyMs ?? null,
      degradationReason,
      lastMessage: message
    },
    message,
    warnings,
    observedDefaultTransports: [
      ...(capabilities.cliAvailable ? ["cli"] : []),
      ...(capabilities.gatewayReachable ? ["ws"] : [])
    ]
  };
}
