import { fromSwiftDate } from "@multi-agent-flow/core";
import type { OpenClawRecoveryReportSnapshot, ProjectOpenClawSnapshot } from "@multi-agent-flow/domain";
import { buildOpenClawRecoveryAudit } from "./openclaw-recovery-audit";
import { buildOpenClawRetryGuidance } from "./openclaw-retry-guidance";

export interface OpenClawRetryPolicy {
  status: "allowed" | "blocked" | "observe" | "not_needed";
  canAutoRetry: boolean;
  immediate: boolean;
  plannedCommands: Array<"connect" | "detect">;
  retryBudgetUsed: number;
  retryBudgetRemaining: number;
  maxRetryBudget: number;
  cooldownRemainingMs: number;
  title: string;
  detail: string;
  rationale: string[];
}

export interface OpenClawRetryPolicyOptions {
  now?: number;
  cooldownMs?: number;
  maxRetryBudget?: number;
  recentWindowSize?: number;
}

const DEFAULT_RETRY_COOLDOWN_MS = 60_000;
const DEFAULT_MAX_RETRY_BUDGET = 2;
const DEFAULT_RECENT_WINDOW_SIZE = 3;

function reportShowsImprovement(report: OpenClawRecoveryReportSnapshot): boolean {
  return report.status === "completed" || report.after.label === "Ready" || report.before.label !== report.after.label;
}

function countRecentNonImprovingAttempts(
  reports: OpenClawRecoveryReportSnapshot[],
  recentWindowSize: number
): number {
  let streak = 0;

  for (const report of reports.slice(0, Math.max(1, recentWindowSize))) {
    if (reportShowsImprovement(report)) {
      break;
    }
    streak += 1;
  }

  return streak;
}

function resolveCooldownRemainingMs(
  latest: OpenClawRecoveryReportSnapshot | null,
  now: number,
  cooldownMs: number
): number {
  if (!latest || reportShowsImprovement(latest)) {
    return 0;
  }

  const elapsedMs = now - fromSwiftDate(latest.createdAt).getTime();
  if (elapsedMs >= cooldownMs) {
    return 0;
  }

  return Math.max(0, cooldownMs - Math.max(0, elapsedMs));
}

export function buildOpenClawRetryPolicy(
  openClaw: ProjectOpenClawSnapshot,
  options: OpenClawRetryPolicyOptions = {}
): OpenClawRetryPolicy {
  const {
    now = Date.now(),
    cooldownMs = DEFAULT_RETRY_COOLDOWN_MS,
    maxRetryBudget = DEFAULT_MAX_RETRY_BUDGET,
    recentWindowSize = DEFAULT_RECENT_WINDOW_SIZE
  } = options;
  const guidance = buildOpenClawRetryGuidance(openClaw);
  const audit = buildOpenClawRecoveryAudit(openClaw.recoveryReports ?? [], recentWindowSize);
  const retryBudgetUsed = countRecentNonImprovingAttempts(audit.timeline, recentWindowSize);
  const retryBudgetRemaining = Math.max(0, maxRetryBudget - retryBudgetUsed);
  const cooldownRemainingMs = resolveCooldownRemainingMs(audit.latest, now, cooldownMs);
  const plannedCommands = guidance.suggestedCommands;

  if (guidance.recommendation === "not_needed") {
    return {
      status: "not_needed",
      canAutoRetry: false,
      immediate: false,
      plannedCommands: [],
      retryBudgetUsed: 0,
      retryBudgetRemaining: maxRetryBudget,
      maxRetryBudget,
      cooldownRemainingMs: 0,
      title: "Runtime already stable",
      detail: "OpenClaw is already ready, so smart retry stays idle.",
      rationale: guidance.rationale
    };
  }

  if (guidance.recommendation === "manual_first") {
    return {
      status: "blocked",
      canAutoRetry: false,
      immediate: false,
      plannedCommands,
      retryBudgetUsed,
      retryBudgetRemaining,
      maxRetryBudget,
      cooldownRemainingMs: 0,
      title: "Smart retry is blocked",
      detail: guidance.detail,
      rationale: guidance.rationale
    };
  }

  if (plannedCommands.length === 0) {
    return {
      status: "observe",
      canAutoRetry: false,
      immediate: false,
      plannedCommands,
      retryBudgetUsed,
      retryBudgetRemaining,
      maxRetryBudget,
      cooldownRemainingMs: 0,
      title: "No automatic command is available",
      detail: guidance.detail,
      rationale: guidance.rationale
    };
  }

  if (retryBudgetRemaining === 0) {
    return {
      status: "blocked",
      canAutoRetry: false,
      immediate: false,
      plannedCommands,
      retryBudgetUsed,
      retryBudgetRemaining,
      maxRetryBudget,
      cooldownRemainingMs: 0,
      title: "Retry budget exhausted",
      detail: "Recent recovery attempts did not improve readiness, so smart retry is paused until the runtime is reviewed manually.",
      rationale: [`Recent non-improving attempts: ${retryBudgetUsed}/${maxRetryBudget}.`, ...guidance.rationale]
    };
  }

  if (cooldownRemainingMs > 0) {
    const secondsRemaining = Math.ceil(cooldownRemainingMs / 1000);
    return {
      status: "observe",
      canAutoRetry: false,
      immediate: false,
      plannedCommands,
      retryBudgetUsed,
      retryBudgetRemaining,
      maxRetryBudget,
      cooldownRemainingMs,
      title: "Cooldown active",
      detail: `A recent retry just ran without clear improvement. Wait about ${secondsRemaining}s before trying smart retry again.`,
      rationale: [
        "Cooldown window is active after the most recent non-improving recovery attempt.",
        ...guidance.rationale
      ]
    };
  }

  return {
    status: "allowed",
    canAutoRetry: true,
    immediate: true,
    plannedCommands,
    retryBudgetUsed,
    retryBudgetRemaining,
    maxRetryBudget,
    cooldownRemainingMs: 0,
    title: "Smart retry is allowed",
    detail: `Automatic recovery may run ${plannedCommands.join(" -> ")} now.`,
    rationale: [`Retry budget remaining: ${retryBudgetRemaining}/${maxRetryBudget}.`, ...guidance.rationale]
  };
}
