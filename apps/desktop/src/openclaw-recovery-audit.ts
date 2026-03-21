import type { OpenClawRecoveryReportSnapshot } from "@multi-agent-flow/domain";

export interface OpenClawRecoveryAuditSummary {
  total: number;
  completed: number;
  partial: number;
  manualFollowUp: number;
  failed: number;
  improved: number;
  reachedReady: number;
}

export interface OpenClawRecoveryAudit {
  summary: OpenClawRecoveryAuditSummary;
  latest: OpenClawRecoveryReportSnapshot | null;
  timeline: OpenClawRecoveryReportSnapshot[];
}

export function formatOpenClawRecoveryStatus(status: OpenClawRecoveryReportSnapshot["status"]): string {
  switch (status) {
    case "completed":
      return "Completed";
    case "partial":
      return "Partial";
    case "manual_follow_up":
      return "Manual Follow-up";
    case "failed":
      return "Failed";
  }
}

function sortReportsDescending(reports: OpenClawRecoveryReportSnapshot[]): OpenClawRecoveryReportSnapshot[] {
  return reports
    .slice()
    .sort((left, right) => Number(right.createdAt) - Number(left.createdAt));
}

export function buildOpenClawRecoveryAudit(
  reports: OpenClawRecoveryReportSnapshot[],
  maxTimelineEntries = 5
): OpenClawRecoveryAudit {
  const sortedReports = sortReportsDescending(reports);
  const summary = sortedReports.reduce<OpenClawRecoveryAuditSummary>(
    (current, report) => {
      current.total += 1;

      switch (report.status) {
        case "completed":
          current.completed += 1;
          break;
        case "partial":
          current.partial += 1;
          break;
        case "manual_follow_up":
          current.manualFollowUp += 1;
          break;
        case "failed":
          current.failed += 1;
          break;
      }

      if (report.before.label !== report.after.label) {
        current.improved += 1;
      }

      if (report.after.label === "Ready") {
        current.reachedReady += 1;
      }

      return current;
    },
    {
      total: 0,
      completed: 0,
      partial: 0,
      manualFollowUp: 0,
      failed: 0,
      improved: 0,
      reachedReady: 0
    }
  );

  return {
    summary,
    latest: sortedReports[0] ?? null,
    timeline: sortedReports.slice(0, Math.max(1, maxTimelineEntries))
  };
}
