import test from "node:test";
import assert from "node:assert/strict";
import { buildOpenClawGovernanceAuditReport } from "../src/openclaw-runtime-governance";

test("local audit proposes safe actions for dangerous tools, subagents, approvals, and elevated execution", () => {
  const report = buildOpenClawGovernanceAuditReport({
    auditedAt: "2026-03-21T00:00:00.000Z",
    deploymentKind: "local",
    rootPath: "/Users/example/.openclaw",
    configPath: "/Users/example/.openclaw/openclaw.json",
    approvalsPath: "/Users/example/.openclaw/exec-approvals.json",
    agentIdentifiers: ["alpha", "beta"],
    subagentBindings: [
      {
        agentIdentifier: "alpha",
        allowAgents: ["beta"]
      }
    ],
    workspaceBindings: [
      {
        agentIdentifier: "alpha",
        workspacePath: "/Users/example/.openclaw/workspace-shared",
        existsOnDisk: true
      },
      {
        agentIdentifier: "beta",
        workspacePath: "/Users/example/.openclaw/workspace-shared",
        existsOnDisk: true
      }
    ],
    runtimeSecurity: {
      approvalsHaveCustomEntries: true,
      blockingIssues: [],
      findings: [
        {
          agentIdentifier: "alpha",
          sandboxMode: "off",
          sessionIsSandboxed: false,
          allowedDangerousTools: ["subagents", "sessions_send", "sessions_spawn"],
          execToolAllowed: true,
          processToolAllowed: true,
          elevatedAllowedByConfig: true,
          elevatedAlwaysAllowedByConfig: false,
          blockingIssues: []
        }
      ]
    }
  });

  assert.equal(report.summary.fail >= 4, true);
  assert.deepEqual(
    report.proposedActions.map((action) => action.id),
    [
      "disable-high-risk-session-tools",
      "clear-subagent-allowlists",
      "repair-agent-workspaces",
      "clear-exec-approvals",
      "disable-elevated-execution",
      "recreate-sandbox-containers"
    ]
  );
  assert.match(report.residualRisks.join(" "), /does not auto-enable OpenClaw sandbox mode/i);
});

test("remote audit reports unsupported auto-remediation instead of proposing local config edits", () => {
  const report = buildOpenClawGovernanceAuditReport({
    deploymentKind: "remoteServer",
    rootPath: null,
    configPath: null,
    approvalsPath: null,
    agentIdentifiers: ["alpha", "beta"],
    subagentBindings: [],
    workspaceBindings: [],
    runtimeSecurity: {
      approvalsHaveCustomEntries: false,
      blockingIssues: [],
      findings: []
    }
  });

  assert.equal(report.findings.some((finding) => finding.id === "remediation-support" && finding.status === "unknown"), true);
  assert.equal(report.proposedActions.length, 0);
  assert.match(report.residualRisks.join(" "), /Automatic remediation is not available/i);
});

test("container audit proposes the same safe config fixes when writable paths are available", () => {
  const report = buildOpenClawGovernanceAuditReport({
    deploymentKind: "container",
    rootPath: "/workspace/.openclaw",
    configPath: "/workspace/.openclaw/openclaw.json",
    approvalsPath: "/workspace/.openclaw/exec-approvals.json",
    agentIdentifiers: ["alpha", "beta"],
    subagentBindings: [
      {
        agentIdentifier: "alpha",
        allowAgents: ["beta"]
      }
    ],
    workspaceBindings: [
      {
        agentIdentifier: "alpha",
        workspacePath: "/workspace/.openclaw/workspace-alpha",
        existsOnDisk: false
      },
      {
        agentIdentifier: "beta",
        workspacePath: "/workspace/.openclaw/workspace-alpha",
        existsOnDisk: true
      }
    ],
    runtimeSecurity: {
      approvalsHaveCustomEntries: true,
      blockingIssues: [],
      findings: [
        {
          agentIdentifier: "alpha",
          sandboxMode: "off",
          sessionIsSandboxed: false,
          allowedDangerousTools: ["subagents"],
          execToolAllowed: true,
          processToolAllowed: true,
          elevatedAllowedByConfig: true,
          elevatedAlwaysAllowedByConfig: false,
          blockingIssues: []
        }
      ]
    }
  });

  assert.equal(report.findings.some((finding) => finding.id === "remediation-support"), false);
  assert.equal(report.proposedActions.some((action) => action.id === "clear-exec-approvals"), true);
  assert.equal(report.proposedActions.some((action) => action.id === "repair-agent-workspaces"), true);
  assert.equal(report.proposedActions.some((action) => action.id === "recreate-sandbox-containers"), true);
});

test("clean local audit stays informational and proposes no actions", () => {
  const report = buildOpenClawGovernanceAuditReport({
    deploymentKind: "local",
    rootPath: "/Users/example/.openclaw",
    configPath: "/Users/example/.openclaw/openclaw.json",
    approvalsPath: "/Users/example/.openclaw/exec-approvals.json",
    agentIdentifiers: ["alpha"],
    subagentBindings: [],
    workspaceBindings: [
      {
        agentIdentifier: "alpha",
        workspacePath: "/Users/example/.openclaw/workspace-alpha",
        existsOnDisk: true
      }
    ],
    runtimeSecurity: {
      approvalsHaveCustomEntries: false,
      blockingIssues: [],
      findings: [
        {
          agentIdentifier: "alpha",
          sandboxMode: "strict",
          sessionIsSandboxed: true,
          allowedDangerousTools: [],
          execToolAllowed: false,
          processToolAllowed: false,
          elevatedAllowedByConfig: false,
          elevatedAlwaysAllowedByConfig: false,
          blockingIssues: []
        }
      ]
    }
  });

  assert.equal(report.summary.fail, 0);
  assert.equal(report.proposedActions.length, 0);
  assert.equal(report.residualRisks.length, 0);
});

test("workspace isolation finding becomes remediable when paths are missing or duplicated", () => {
  const report = buildOpenClawGovernanceAuditReport({
    deploymentKind: "local",
    rootPath: "/Users/example/.openclaw",
    configPath: "/Users/example/.openclaw/openclaw.json",
    approvalsPath: "/Users/example/.openclaw/exec-approvals.json",
    agentIdentifiers: ["alpha", "beta", "gamma"],
    subagentBindings: [],
    workspaceBindings: [
      {
        agentIdentifier: "alpha",
        workspacePath: null,
        existsOnDisk: false
      },
      {
        agentIdentifier: "beta",
        workspacePath: "/Users/example/.openclaw/workspace-shared",
        existsOnDisk: true
      },
      {
        agentIdentifier: "gamma",
        workspacePath: "/Users/example/.openclaw/workspace-shared",
        existsOnDisk: false
      }
    ],
    runtimeSecurity: {
      approvalsHaveCustomEntries: false,
      blockingIssues: [],
      findings: []
    }
  });

  const workspaceFinding = report.findings.find((finding) => finding.id === "workspace-isolation");
  assert.ok(workspaceFinding);
  assert.equal(workspaceFinding.status, "fail");
  assert.equal(workspaceFinding.remediable, true);
  assert.equal(report.proposedActions.some((action) => action.id === "repair-agent-workspaces"), true);
});
