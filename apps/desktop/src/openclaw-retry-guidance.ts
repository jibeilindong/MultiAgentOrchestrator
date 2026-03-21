import type { ProjectOpenClawSnapshot } from "@multi-agent-flow/domain";
import { buildOpenClawRecoveryAudit } from "./openclaw-recovery-audit";
import { assessOpenClawRuntimeReadiness } from "./openclaw-runtime-readiness";

export interface OpenClawRetryGuidance {
  recommendation: "auto_retry" | "manual_first" | "observe" | "not_needed";
  title: string;
  detail: string;
  suggestedCommands: Array<"connect" | "detect">;
  rationale: string[];
}

export function buildOpenClawRetryGuidance(openClaw: ProjectOpenClawSnapshot): OpenClawRetryGuidance {
  const readiness = assessOpenClawRuntimeReadiness(openClaw);
  const audit = buildOpenClawRecoveryAudit(openClaw.recoveryReports ?? []);
  const suggestedCommands = readiness.recoveryActions
    .map((action) => action.command)
    .filter((command): command is "connect" | "detect" => command === "connect" || command === "detect");

  if (readiness.label === "Ready" && suggestedCommands.length === 0) {
    return {
      recommendation: "not_needed",
      title: "No retry needed",
      detail: "The runtime is already ready, so an automatic retry would add noise without improving state.",
      suggestedCommands: [],
      rationale: ["Current readiness is Ready."]
    };
  }

  if (readiness.recoveryActions.some((action) => action.command === "review_config")) {
    return {
      recommendation: "manual_first",
      title: "Manual fix required first",
      detail: "The current failure still depends on host, container, or credential changes, so manual review should happen before automatic retry resumes.",
      suggestedCommands: suggestedCommands,
      rationale: ["Recovery actions still include manual configuration review."]
    };
  }

  if (suggestedCommands.length === 0) {
    return {
      recommendation: "observe",
      title: "Observe current state",
      detail: "The runtime is degraded, but there is no safe automatic retry step to run right now.",
      suggestedCommands: [],
      rationale: ["No automatic Connect/Detect action is currently recommended."]
    };
  }

  if (audit.latest?.status === "manual_follow_up") {
    return {
      recommendation: "manual_first",
      title: "Recent recovery paused for manual follow-up",
      detail: "The most recent recovery did not finish automatically, so retrying again would likely repeat the same stall.",
      suggestedCommands,
      rationale: ["Latest recovery status is manual follow-up."]
    };
  }

  if (audit.summary.failed >= 2 && audit.summary.completed === 0 && audit.summary.improved === 0) {
    return {
      recommendation: "manual_first",
      title: "Repeated retries are not converging",
      detail: "Recent recovery attempts failed without improving readiness, so automatic retry should stop until the underlying issue is reviewed.",
      suggestedCommands,
      rationale: ["Multiple failed recoveries produced no readiness improvement."]
    };
  }

  if (audit.summary.total === 0 || audit.summary.completed > 0 || audit.summary.improved > 0) {
    return {
      recommendation: "auto_retry",
      title: "Automatic retry is reasonable",
      detail: "Recent evidence suggests the runtime can recover through the current automatic steps, so a retry is worth attempting.",
      suggestedCommands,
      rationale: [
        audit.summary.total === 0
          ? "No prior recovery history is available yet."
          : "Past recovery history includes either completion or measurable improvement."
      ]
    };
  }

  return {
    recommendation: "observe",
    title: "Retry with caution",
    detail: "The runtime may still recover automatically, but recent history is mixed, so review diagnostics while retrying.",
    suggestedCommands,
    rationale: ["Recovery history is inconclusive rather than clearly successful or clearly blocked."]
  };
}
