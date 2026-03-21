import type { OpenClawRuntimeSecurityInspectionResult } from "./openclaw-runtime-security";

export type OpenClawGovernanceFindingStatus = "pass" | "fail" | "unknown";
export type OpenClawGovernanceFindingSeverity = "info" | "warning" | "error";
export type OpenClawGovernanceActionKind =
  | "edit_openclaw_config"
  | "edit_exec_approvals"
  | "recreate_sandbox"
  | "manual_follow_up";

export interface OpenClawGovernanceFinding {
  id: string;
  title: string;
  status: OpenClawGovernanceFindingStatus;
  severity: OpenClawGovernanceFindingSeverity;
  summary: string;
  evidence: string[];
  remediable: boolean;
  remediationActionIds: string[];
}

export interface OpenClawGovernanceAction {
  id: string;
  title: string;
  description: string;
  kind: OpenClawGovernanceActionKind;
  targetPath: string | null;
  safeToAutoApply: boolean;
  requiresSandboxRecreate: boolean;
}

export interface OpenClawGovernanceAuditReport {
  auditedAt: string;
  deploymentKind: string;
  findings: OpenClawGovernanceFinding[];
  proposedActions: OpenClawGovernanceAction[];
  residualRisks: string[];
  summary: {
    pass: number;
    fail: number;
    unknown: number;
    remediableFailCount: number;
  };
}

export interface OpenClawGovernanceRemediationResult {
  report: OpenClawGovernanceAuditReport;
  appliedActionIds: string[];
  skippedActionIds: string[];
  notes: string[];
  backupPaths: string[];
}

export interface OpenClawGovernanceAuditInput {
  auditedAt?: string;
  deploymentKind: string;
  rootPath: string | null;
  configPath: string | null;
  approvalsPath: string | null;
  agentIdentifiers: string[];
  subagentBindings: Array<{
    agentIdentifier: string;
    allowAgents: string[];
  }>;
  workspaceBindings: Array<{
    agentIdentifier: string;
    workspacePath: string | null;
    existsOnDisk: boolean;
  }>;
  runtimeSecurity: OpenClawRuntimeSecurityInspectionResult;
}

function uniqueSorted(values: Iterable<string>): string[] {
  return Array.from(new Set(Array.from(values).map((value) => value.trim()).filter(Boolean))).sort((left, right) =>
    left.localeCompare(right)
  );
}

function statusFromBooleans(options: { hasFail: boolean; hasUnknown?: boolean }): OpenClawGovernanceFindingStatus {
  if (options.hasFail) {
    return "fail";
  }
  if (options.hasUnknown) {
    return "unknown";
  }
  return "pass";
}

export function buildOpenClawGovernanceAuditReport(
  input: OpenClawGovernanceAuditInput
): OpenClawGovernanceAuditReport {
  const findings: OpenClawGovernanceFinding[] = [];
  const proposedActions: OpenClawGovernanceAction[] = [];
  const residualRisks: string[] = [];
  const allAgentIdentifiers = uniqueSorted([
    ...input.agentIdentifiers,
    ...input.runtimeSecurity.findings.map((finding) => finding.agentIdentifier),
    ...input.subagentBindings.map((binding) => binding.agentIdentifier)
  ]);
  const automaticRemediationSupported =
    (input.deploymentKind === "local" || input.deploymentKind === "container") && Boolean(input.configPath);
  const subagentBindings = input.subagentBindings
    .filter((binding) => binding.allowAgents.length > 0)
    .map((binding) => ({
      agentIdentifier: binding.agentIdentifier,
      allowAgents: uniqueSorted(binding.allowAgents)
    }));
  const workspaceBindings = input.workspaceBindings.map((binding) => ({
    agentIdentifier: binding.agentIdentifier,
    workspacePath: binding.workspacePath?.trim() || null,
    existsOnDisk: binding.existsOnDisk
  }));

  if (!automaticRemediationSupported) {
    findings.push({
      id: "remediation-support",
      title: "Automatic remediation support",
      status: "unknown",
      severity: "warning",
      summary: "This release can only auto-remediate local or container OpenClaw configurations with a writable `openclaw.json`.",
      evidence: [
        input.configPath
          ? `Deployment kind is ${input.deploymentKind}.`
          : "No writable OpenClaw config path could be resolved for the current deployment."
      ],
      remediable: false,
      remediationActionIds: []
    });
    residualRisks.push(
      "Automatic remediation is not available for the current OpenClaw deployment. The audit can still report issues, but config changes must be applied manually."
    );
  }

  const sandboxFailures = input.runtimeSecurity.findings.filter(
    (finding) => finding.sandboxMode.toLowerCase() === "off" || !finding.sessionIsSandboxed
  );
  findings.push({
    id: "sandbox-isolation",
    title: "Sandbox isolation enforcement",
    status: statusFromBooleans({
      hasFail: sandboxFailures.length > 0,
      hasUnknown: input.runtimeSecurity.findings.length === 0 && allAgentIdentifiers.length > 1
    }),
    severity: sandboxFailures.length > 0 ? "error" : input.runtimeSecurity.findings.length === 0 ? "warning" : "info",
    summary:
      sandboxFailures.length > 0
        ? "One or more agents are not running inside an enforced OpenClaw sandbox."
        : "Sandbox isolation looks enforced for the inspected agents.",
    evidence:
      sandboxFailures.length > 0
        ? sandboxFailures.map(
            (finding) =>
              `${finding.agentIdentifier}: mode=${finding.sandboxMode}, sessionIsSandboxed=${finding.sessionIsSandboxed ? "true" : "false"}`
          )
        : allAgentIdentifiers.length > 1 && input.runtimeSecurity.findings.length === 0
          ? ["No per-agent sandbox policy could be inspected for this multi-agent environment."]
          : input.runtimeSecurity.findings.map(
              (finding) =>
                `${finding.agentIdentifier}: mode=${finding.sandboxMode}, sessionIsSandboxed=${finding.sessionIsSandboxed ? "true" : "false"}`
            ),
    remediable: false,
    remediationActionIds: []
  });
  if (sandboxFailures.length > 0) {
    residualRisks.push(
      "The current audit can detect missing sandbox isolation, but this release does not auto-enable OpenClaw sandbox mode because the upstream config path is not exposed as a stable writable fix target."
    );
  }

  const dangerousToolAgents = input.runtimeSecurity.findings.filter((finding) => finding.allowedDangerousTools.length > 0);
  const dangerousToolActionIds: string[] = [];
  if (dangerousToolAgents.length > 0 && automaticRemediationSupported && input.configPath) {
    dangerousToolActionIds.push("disable-high-risk-session-tools");
    proposedActions.push({
      id: "disable-high-risk-session-tools",
      title: "Disable high-risk session tools",
      description:
        "Add `subagents`, `sessions_send`, and `sessions_spawn` to the OpenClaw sandbox deny list and remove them from explicit allow lists where present.",
      kind: "edit_openclaw_config",
      targetPath: input.configPath,
      safeToAutoApply: true,
      requiresSandboxRecreate: true
    });
  }
  findings.push({
    id: "dangerous-session-tools",
    title: "High-risk session tools",
    status: statusFromBooleans({
      hasFail: dangerousToolAgents.length > 0,
      hasUnknown: input.runtimeSecurity.findings.length === 0 && allAgentIdentifiers.length > 1
    }),
    severity: dangerousToolAgents.length > 0 ? "error" : input.runtimeSecurity.findings.length === 0 ? "warning" : "info",
    summary:
      dangerousToolAgents.length > 0
        ? "One or more agents can still spawn or message side-channel sessions."
        : "The inspected agents do not expose high-risk session tools.",
    evidence:
      dangerousToolAgents.length > 0
        ? dangerousToolAgents.map(
            (finding) => `${finding.agentIdentifier}: ${finding.allowedDangerousTools.join(", ")}`
          )
        : allAgentIdentifiers.length > 1 && input.runtimeSecurity.findings.length === 0
          ? ["No sandbox tool policy could be inspected for this multi-agent environment."]
          : ["No inspected agent exposed `subagents`, `sessions_send`, or `sessions_spawn`."],
    remediable: dangerousToolActionIds.length > 0,
    remediationActionIds: dangerousToolActionIds
  });

  const subagentActionIds: string[] = [];
  if (subagentBindings.length > 0 && automaticRemediationSupported && input.configPath) {
    subagentActionIds.push("clear-subagent-allowlists");
    proposedActions.push({
      id: "clear-subagent-allowlists",
      title: "Clear configured subagent allowlists",
      description: "Rewrite `agents.list[].subagents.allowAgents` to empty arrays so the config no longer advertises agent-to-agent subdelegation.",
      kind: "edit_openclaw_config",
      targetPath: input.configPath,
      safeToAutoApply: true,
      requiresSandboxRecreate: false
    });
  }
  findings.push({
    id: "subagent-bindings",
    title: "Configured subagent allowlists",
    status: subagentBindings.length > 0 ? "fail" : "pass",
    severity: subagentBindings.length > 0 ? "warning" : "info",
    summary:
      subagentBindings.length > 0
        ? "Some agents explicitly allow subagent delegation in `openclaw.json`."
        : "The config does not advertise subagent allowlists.",
    evidence:
      subagentBindings.length > 0
        ? subagentBindings.map((binding) => `${binding.agentIdentifier}: ${binding.allowAgents.join(", ")}`)
        : ["All configured `subagents.allowAgents` arrays are already empty or absent."],
    remediable: subagentActionIds.length > 0,
    remediationActionIds: subagentActionIds
  });

  const missingWorkspaceBindings = workspaceBindings.filter((binding) => !binding.workspacePath);
  const nonExistentWorkspaceBindings = workspaceBindings.filter((binding) => binding.workspacePath && !binding.existsOnDisk);
  const duplicateWorkspaceBindings = Array.from(
    workspaceBindings.reduce((accumulator, binding) => {
      if (!binding.workspacePath) {
        return accumulator;
      }
      const key = binding.workspacePath.toLowerCase();
      const current = accumulator.get(key) ?? [];
      current.push(binding);
      accumulator.set(key, current);
      return accumulator;
    }, new Map<string, typeof workspaceBindings>())
  ).filter(([, bindings]) => bindings.length > 1);
  const workspaceActionIds: string[] = [];
  if (
    automaticRemediationSupported &&
    input.configPath &&
    input.rootPath &&
    (missingWorkspaceBindings.length > 0 || nonExistentWorkspaceBindings.length > 0 || duplicateWorkspaceBindings.length > 0)
  ) {
    workspaceActionIds.push("repair-agent-workspaces");
    proposedActions.push({
      id: "repair-agent-workspaces",
      title: "Repair agent workspace isolation",
      description:
        "Assign deterministic per-agent workspace paths under the OpenClaw root and create any missing workspace directories.",
      kind: "edit_openclaw_config",
      targetPath: input.configPath,
      safeToAutoApply: true,
      requiresSandboxRecreate: false
    });
  }
  findings.push({
    id: "workspace-isolation",
    title: "Agent workspace isolation",
    status:
      missingWorkspaceBindings.length > 0 || nonExistentWorkspaceBindings.length > 0 || duplicateWorkspaceBindings.length > 0
        ? "fail"
        : workspaceBindings.length > 0
          ? "pass"
          : "unknown",
    severity:
      missingWorkspaceBindings.length > 0 || duplicateWorkspaceBindings.length > 0
        ? "error"
        : nonExistentWorkspaceBindings.length > 0
          ? "warning"
          : workspaceBindings.length > 0
            ? "info"
            : "warning",
    summary:
      missingWorkspaceBindings.length > 0 || duplicateWorkspaceBindings.length > 0 || nonExistentWorkspaceBindings.length > 0
        ? "One or more agents are missing an isolated workspace path, point to the same workspace, or reference a workspace that does not exist on disk."
        : workspaceBindings.length > 0
          ? "Configured agents each have their own workspace path, and those directories exist on disk."
          : "No configured agent workspace bindings were available to audit.",
    evidence: [
      ...missingWorkspaceBindings.map((binding) => `${binding.agentIdentifier}: missing workspace path`),
      ...nonExistentWorkspaceBindings.map((binding) => `${binding.agentIdentifier}: ${binding.workspacePath} (directory missing)`),
      ...duplicateWorkspaceBindings.map(([, bindings]) => {
        const workspacePath = bindings[0]?.workspacePath ?? "unknown";
        return `${bindings.map((binding) => binding.agentIdentifier).join(", ")} share ${workspacePath}`;
      }),
      ...(missingWorkspaceBindings.length === 0 &&
      nonExistentWorkspaceBindings.length === 0 &&
      duplicateWorkspaceBindings.length === 0 &&
      workspaceBindings.length > 0
        ? workspaceBindings.map((binding) => `${binding.agentIdentifier}: ${binding.workspacePath}`)
        : []),
      ...(workspaceBindings.length === 0 ? ["No `agents.list[].workspace` entries were available in the current OpenClaw config."] : [])
    ],
    remediable: workspaceActionIds.length > 0,
    remediationActionIds: workspaceActionIds
  });

  const approvalActionIds: string[] = [];
  if (input.runtimeSecurity.approvalsHaveCustomEntries && input.approvalsPath) {
    approvalActionIds.push("clear-exec-approvals");
    proposedActions.push({
      id: "clear-exec-approvals",
      title: "Clear custom exec approvals",
      description: "Reset `exec-approvals.json` so custom `defaults` and `agents` allowlists are empty.",
      kind: "edit_exec_approvals",
      targetPath: input.approvalsPath,
      safeToAutoApply: input.deploymentKind === "local" || input.deploymentKind === "container",
      requiresSandboxRecreate: false
    });
  }
  findings.push({
    id: "exec-approvals",
    title: "Custom exec approvals",
    status: input.runtimeSecurity.approvalsHaveCustomEntries ? "fail" : "pass",
    severity: input.runtimeSecurity.approvalsHaveCustomEntries ? "warning" : "info",
    summary: input.runtimeSecurity.approvalsHaveCustomEntries
      ? "Custom exec approval rules are present."
      : "Exec approvals are already empty.",
    evidence: input.runtimeSecurity.approvalsHaveCustomEntries
      ? [input.approvalsPath ? `Approvals file: ${input.approvalsPath}` : "The current approvals snapshot reported custom defaults or agent allowlists."]
      : ["`defaults` and `agents` are empty in the current exec approvals snapshot."],
    remediable: approvalActionIds.length > 0,
    remediationActionIds: approvalActionIds
  });

  const elevatedAgents = input.runtimeSecurity.findings.filter(
    (finding) => finding.elevatedAllowedByConfig || finding.elevatedAlwaysAllowedByConfig
  );
  const elevatedActionIds: string[] = [];
  if (elevatedAgents.length > 0 && automaticRemediationSupported && input.configPath) {
    elevatedActionIds.push("disable-elevated-execution");
    proposedActions.push({
      id: "disable-elevated-execution",
      title: "Disable elevated execution",
      description: "Set `tools.elevated.enabled = false` in `openclaw.json`.",
      kind: "edit_openclaw_config",
      targetPath: input.configPath,
      safeToAutoApply: true,
      requiresSandboxRecreate: true
    });
  }
  findings.push({
    id: "elevated-execution",
    title: "Elevated execution",
    status: elevatedAgents.length > 0 ? "fail" : "pass",
    severity: elevatedAgents.length > 0 ? "error" : "info",
    summary:
      elevatedAgents.length > 0
        ? "One or more agents are allowed to use OpenClaw elevated execution."
        : "No inspected agent reported elevated execution permissions.",
    evidence:
      elevatedAgents.length > 0
        ? elevatedAgents.map(
            (finding) =>
              `${finding.agentIdentifier}: allowedByConfig=${finding.elevatedAllowedByConfig ? "true" : "false"}, alwaysAllowedByConfig=${finding.elevatedAlwaysAllowedByConfig ? "true" : "false"}`
          )
        : ["The current sandbox policy does not expose elevated execution permissions."],
    remediable: elevatedActionIds.length > 0,
    remediationActionIds: elevatedActionIds
  });

  if (proposedActions.some((action) => action.requiresSandboxRecreate)) {
    proposedActions.push({
      id: "recreate-sandbox-containers",
      title: "Recreate sandbox containers",
      description: "Run `openclaw sandbox recreate --all --force` so the next session picks up the updated sandbox configuration.",
      kind: "recreate_sandbox",
      targetPath: null,
      safeToAutoApply: input.deploymentKind !== "remoteServer",
      requiresSandboxRecreate: false
    });
  }

  const dedupedActions = proposedActions.filter(
    (action, index, list) => list.findIndex((candidate) => candidate.id === action.id) === index
  );
  const summary = findings.reduce(
    (accumulator, finding) => {
      accumulator[finding.status] += 1;
      if (finding.status === "fail" && finding.remediable) {
        accumulator.remediableFailCount += 1;
      }
      return accumulator;
    },
    { pass: 0, fail: 0, unknown: 0, remediableFailCount: 0 }
  );

  return {
    auditedAt: input.auditedAt ?? new Date().toISOString(),
    deploymentKind: input.deploymentKind,
    findings,
    proposedActions: dedupedActions,
    residualRisks: uniqueSorted(residualRisks),
    summary
  };
}
