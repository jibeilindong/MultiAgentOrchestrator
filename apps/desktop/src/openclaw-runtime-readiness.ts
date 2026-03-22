import type {
  OpenClawConnectionCapabilitiesSnapshot,
  OpenClawProbeLayersSnapshot,
  ProjectOpenClawSnapshot
} from "@multi-agent-flow/domain";
import { openClawRequiresExplicitLocalBinaryPath } from "@multi-agent-flow/domain";

export interface OpenClawRuntimeReadinessAssessment {
  label: "Ready" | "Degraded" | "Blocked" | "Idle";
  tone: "ready" | "degraded" | "blocked" | "idle";
  summary: string;
  blockingMessage: string | null;
  advisoryMessages: string[];
  recoveryActions: OpenClawRuntimeRecoveryAction[];
  layers: OpenClawProbeLayersSnapshot | null;
}

export interface OpenClawRuntimeRecoveryAction {
  id: string;
  title: string;
  detail: string;
  command: "connect" | "detect" | "review_config";
}

function formatLayerState(state: OpenClawProbeLayersSnapshot[keyof OpenClawProbeLayersSnapshot]): string {
  switch (state) {
    case "ready":
      return "ready";
    case "degraded":
      return "degraded";
    case "unavailable":
      return "unavailable";
    case "not_required":
      return "not required";
  }
}

export function formatOpenClawRuntimeLayers(layers: OpenClawProbeLayersSnapshot): string {
  return `transport=${layers.transport}, auth=${layers.authentication}, session=${layers.session}, inventory=${layers.inventory}`;
}

function deriveProbeLayers(
  deploymentKind: ProjectOpenClawSnapshot["config"]["deploymentKind"],
  capabilities: OpenClawConnectionCapabilitiesSnapshot
): OpenClawProbeLayersSnapshot {
  if (deploymentKind === "container") {
    return {
      transport: capabilities.cliAvailable ? "ready" : "unavailable",
      authentication: "not_required",
      session: capabilities.cliAvailable && capabilities.agentListingAvailable ? "ready" : capabilities.cliAvailable ? "degraded" : "unavailable",
      inventory: capabilities.agentListingAvailable ? "ready" : capabilities.cliAvailable ? "degraded" : "unavailable"
    };
  }

  if (deploymentKind === "remoteServer") {
    return {
      transport: capabilities.gatewayReachable ? "ready" : "unavailable",
      authentication: capabilities.gatewayReachable
        ? capabilities.gatewayAuthenticated
          ? "ready"
          : "degraded"
        : "unavailable",
      session: capabilities.gatewayAuthenticated ? "ready" : capabilities.gatewayReachable ? "degraded" : "unavailable",
      inventory: capabilities.agentListingAvailable ? "ready" : capabilities.gatewayAuthenticated ? "degraded" : "unavailable"
    };
  }

  return {
    transport:
      capabilities.cliAvailable && capabilities.gatewayReachable ? "ready" : capabilities.cliAvailable || capabilities.gatewayReachable ? "degraded" : "unavailable",
    authentication: capabilities.gatewayReachable
      ? capabilities.gatewayAuthenticated
        ? "ready"
        : "degraded"
      : capabilities.cliAvailable
        ? "degraded"
        : "unavailable",
    session:
      capabilities.cliAvailable && capabilities.agentListingAvailable && capabilities.gatewayAuthenticated
        ? "ready"
        : capabilities.cliAvailable || capabilities.gatewayReachable
          ? "degraded"
          : "unavailable",
    inventory: capabilities.agentListingAvailable ? "ready" : capabilities.cliAvailable ? "degraded" : "unavailable"
  };
}

function dedupeMessages(messages: string[]): string[] {
  return Array.from(new Set(messages.map((message) => message.trim()).filter(Boolean)));
}

function dedupeRecoveryActions(actions: OpenClawRuntimeRecoveryAction[]): OpenClawRuntimeRecoveryAction[] {
  const seen = new Set<string>();
  return actions.filter((action) => {
    if (seen.has(action.id)) {
      return false;
    }
    seen.add(action.id);
    return true;
  });
}

function resolveProbeLayers(openClaw: ProjectOpenClawSnapshot): OpenClawProbeLayersSnapshot | null {
  if (openClaw.lastProbeReport?.layers) {
    return openClaw.lastProbeReport.layers;
  }

  if (openClaw.connectionState.phase === "idle") {
    return null;
  }

  return deriveProbeLayers(openClaw.connectionState.deploymentKind, openClaw.connectionState.capabilities);
}

function isRunnablePhase(openClaw: ProjectOpenClawSnapshot): boolean {
  return openClaw.connectionState.phase === "ready" || openClaw.connectionState.phase === "degraded";
}

function canRunLiveExecution(openClaw: ProjectOpenClawSnapshot): boolean {
  if (!isRunnablePhase(openClaw)) {
    return false;
  }

  const { deploymentKind, capabilities } = openClaw.connectionState;
  switch (deploymentKind) {
    case "remoteServer":
      return capabilities.gatewayReachable && capabilities.gatewayAuthenticated && capabilities.gatewayAgentAvailable;
    case "local":
    case "container":
      return capabilities.cliAvailable || (capabilities.gatewayReachable && capabilities.gatewayAuthenticated && capabilities.gatewayAgentAvailable);
  }
}

function buildBlockingMessage(openClaw: ProjectOpenClawSnapshot, layers: OpenClawProbeLayersSnapshot | null): string | null {
  const lastMessage = openClaw.connectionState.health.lastMessage ?? openClaw.lastProbeReport?.message ?? null;

  if (openClaw.connectionState.phase === "detached") {
    return lastMessage ?? "OpenClaw session is detached. Reconnect before running live workflow execution.";
  }

  if (openClaw.connectionState.phase === "idle") {
    return "Connect OpenClaw before running live workflow execution.";
  }

  if (!canRunLiveExecution(openClaw)) {
    return lastMessage ?? "OpenClaw runtime is not runnable. Reconnect before running live workflow execution.";
  }

  if (!layers) {
    return null;
  }

  if (openClaw.connectionState.deploymentKind === "remoteServer" && layers.transport !== "ready") {
    return `OpenClaw transport is ${formatLayerState(layers.transport)}. Reconnect before starting high-speed live execution.`;
  }

  if (openClaw.connectionState.deploymentKind === "remoteServer" && layers.authentication !== "ready" && layers.authentication !== "not_required") {
    return `OpenClaw authentication is ${formatLayerState(layers.authentication)}. Reconnect before starting live execution.`;
  }

  if (openClaw.connectionState.deploymentKind === "remoteServer" && layers.session !== "ready") {
    return `OpenClaw session channel is ${formatLayerState(layers.session)}. Reconnect before starting live execution.`;
  }

  return null;
}

function buildRecoveryActions(
  openClaw: ProjectOpenClawSnapshot,
  layers: OpenClawProbeLayersSnapshot | null,
  blockingMessage: string | null
): OpenClawRuntimeRecoveryAction[] {
  const actions: OpenClawRuntimeRecoveryAction[] = [];

  if (openClaw.connectionState.phase === "idle") {
    actions.push({
      id: "connect-runtime",
      title: "Probe runtime",
      detail: "Run Connect to create the first runtime probe and verify the active OpenClaw path.",
      command: "connect"
    });
  }

  const shouldRecommendReconnect =
    !canRunLiveExecution(openClaw)
    || openClaw.connectionState.phase === "detached"
    || Boolean(blockingMessage)
    || (
      openClaw.connectionState.phase === "degraded"
      && openClaw.connectionState.deploymentKind !== "remoteServer"
    );

  if (shouldRecommendReconnect) {
    actions.push({
      id: "reconnect-runtime",
      title: "Reconnect OpenClaw",
      detail: "Run Connect to re-establish the runtime transport, authentication, and live session channel.",
      command: "connect"
    });
  }

  const canRefreshInventory =
    !blockingMessage &&
    layers &&
    layers.transport === "ready" &&
    (layers.authentication === "ready" || layers.authentication === "not_required") &&
    layers.session === "ready";

  if (canRefreshInventory && layers.inventory !== "ready") {
    actions.push({
      id: "refresh-inventory",
      title: "Refresh agent inventory",
      detail: "Run Detect agents to refresh import candidates and workflow agent mapping against the current runtime.",
      command: "detect"
    });
  }

  if (openClawRequiresExplicitLocalBinaryPath(openClaw.config) && !openClaw.config.localBinaryPath.trim()) {
    actions.push({
      id: "review-local-config",
      title: "Review local runtime path",
      detail: "Set a valid local OpenClaw binary path before retrying the runtime probe.",
      command: "review_config"
    });
  }

  if (openClaw.config.deploymentKind === "container" && !openClaw.config.container.containerName.trim()) {
    actions.push({
      id: "review-container-config",
      title: "Review container target",
      detail: "Set the container name so Detect and Connect can resolve the real OpenClaw runtime.",
      command: "review_config"
    });
  }

  if (openClaw.config.deploymentKind === "remoteServer") {
    if (!openClaw.config.host.trim()) {
      actions.push({
        id: "review-remote-host",
        title: "Review remote host",
        detail: "Set the remote OpenClaw host before retrying the gateway probe.",
        command: "review_config"
      });
    }

    if (layers && layers.authentication !== "ready" && !openClaw.config.apiKey.trim()) {
      actions.push({
        id: "review-remote-auth",
        title: "Review remote credentials",
        detail: "Add or refresh the remote API key before retrying gateway authentication.",
        command: "review_config"
      });
    }
  }

  return dedupeRecoveryActions(actions);
}

export function assessOpenClawRuntimeReadiness(openClaw: ProjectOpenClawSnapshot): OpenClawRuntimeReadinessAssessment {
  const layers = resolveProbeLayers(openClaw);
  const blockingMessage = buildBlockingMessage(openClaw, layers);
  const advisories: string[] = [];

  if (layers && layers.inventory !== "ready") {
    advisories.push(
      `Agent inventory is ${formatLayerState(layers.inventory)}. Run Detect agents before importing or remapping workflow agents.`
    );
  }

  if (openClaw.connectionState.phase === "degraded" && openClaw.connectionState.health.degradationReason) {
    advisories.push(openClaw.connectionState.health.degradationReason);
  }

  if (openClaw.lastProbeReport?.warnings?.length) {
    advisories.push(...openClaw.lastProbeReport.warnings.slice(0, 3));
  }

  const advisoryMessages = dedupeMessages(advisories).filter((message) => message !== blockingMessage);
  const recoveryActions = buildRecoveryActions(openClaw, layers, blockingMessage);

  if (blockingMessage) {
    return {
      label: openClaw.connectionState.phase === "idle" ? "Idle" : "Blocked",
      tone: openClaw.connectionState.phase === "idle" ? "idle" : "blocked",
      summary: blockingMessage,
      blockingMessage,
      advisoryMessages,
      recoveryActions,
      layers
    };
  }

  if (advisoryMessages.length > 0 || openClaw.connectionState.phase === "degraded") {
    return {
      label: "Degraded",
      tone: "degraded",
      summary:
        openClaw.connectionState.health.lastMessage ??
        advisoryMessages[0] ??
        "OpenClaw runtime is connected with degraded capabilities.",
      blockingMessage: null,
      advisoryMessages,
      recoveryActions,
      layers
    };
  }

  if (openClaw.connectionState.phase === "idle") {
    return {
      label: "Idle",
      tone: "idle",
      summary: "Run Detect agents or Connect to record the first OpenClaw probe.",
      blockingMessage: null,
      advisoryMessages: [],
      recoveryActions,
      layers
    };
  }

  return {
    label: "Ready",
    tone: "ready",
    summary: openClaw.connectionState.health.lastMessage ?? "OpenClaw runtime is ready for live execution.",
    blockingMessage: null,
    advisoryMessages,
    recoveryActions,
    layers
  };
}
