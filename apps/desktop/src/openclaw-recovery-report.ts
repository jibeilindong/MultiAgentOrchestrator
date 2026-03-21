import type { OpenClawRecoveryReportSnapshot, ProjectOpenClawSnapshot, SwiftDate } from "@multi-agent-flow/domain";
import { assessOpenClawRuntimeReadiness, formatOpenClawRuntimeLayers } from "./openclaw-runtime-readiness";

function formatLayers(openClaw: ProjectOpenClawSnapshot): string {
  const readiness = assessOpenClawRuntimeReadiness(openClaw);
  return readiness.layers ? formatOpenClawRuntimeLayers(readiness.layers) : "not_probed";
}

export function buildOpenClawRecoveryReport(input: {
  before: ProjectOpenClawSnapshot;
  after: ProjectOpenClawSnapshot;
  createdAt: SwiftDate;
  completedSteps: string[];
  manualSteps?: string[];
  errorMessage?: string | null;
}): OpenClawRecoveryReportSnapshot {
  const { before, after, createdAt, completedSteps, manualSteps = [], errorMessage = null } = input;
  const beforeReadiness = assessOpenClawRuntimeReadiness(before);
  const afterReadiness = assessOpenClawRuntimeReadiness(after);
  const findings: string[] = [];

  if (beforeReadiness.label !== afterReadiness.label) {
    findings.push(`Readiness changed from ${beforeReadiness.label} to ${afterReadiness.label}.`);
  }

  if (formatLayers(before) !== formatLayers(after)) {
    findings.push(`Layer state changed from ${formatLayers(before)} to ${formatLayers(after)}.`);
  }

  if (afterReadiness.summary !== beforeReadiness.summary) {
    findings.push(`Summary changed from "${beforeReadiness.summary}" to "${afterReadiness.summary}".`);
  }

  let status: OpenClawRecoveryReportSnapshot["status"] = "completed";
  let summary = completedSteps.length > 0
    ? `Recovery completed: ${completedSteps.join(" -> ")}.`
    : "Recovery completed without an automatic step.";

  if (errorMessage) {
    status = "failed";
    summary = completedSteps.length > 0
      ? `Recovery failed after ${completedSteps.join(" -> ")}: ${errorMessage}`
      : `Recovery failed before any automatic step: ${errorMessage}`;
  } else if (manualSteps.length > 0) {
    status = "manual_follow_up";
    summary = completedSteps.length > 0
      ? `Recovery paused after ${completedSteps.join(" -> ")}. Manual follow-up is still required.`
      : "Recovery requires manual follow-up before any automatic step can continue.";
  } else if (afterReadiness.label !== "Ready") {
    status = "partial";
    summary = completedSteps.length > 0
      ? `Recovery improved the runtime via ${completedSteps.join(" -> ")}, but the runtime is still ${afterReadiness.label.toLowerCase()}.`
      : `Recovery ended with runtime still ${afterReadiness.label.toLowerCase()}.`;
  }

  return {
    createdAt,
    status,
    summary,
    completedSteps,
    manualSteps,
    findings,
    before: {
      label: beforeReadiness.label,
      summary: beforeReadiness.summary,
      layers: formatLayers(before)
    },
    after: {
      label: afterReadiness.label,
      summary: afterReadiness.summary,
      layers: formatLayers(after)
    }
  };
}
