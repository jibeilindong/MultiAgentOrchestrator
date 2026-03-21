import test from "node:test";
import assert from "node:assert/strict";
import type { OpenClawRecoveryReportSnapshot } from "@multi-agent-flow/domain";
import { buildOpenClawRecoveryAudit, formatOpenClawRecoveryStatus } from "../src/openclaw-recovery-audit";

function createRecoveryReport(
  overrides: Partial<OpenClawRecoveryReportSnapshot>
): OpenClawRecoveryReportSnapshot {
  return {
    createdAt: 1_700_000_000,
    status: "completed",
    summary: "Recovery completed.",
    completedSteps: [],
    manualSteps: [],
    findings: [],
    before: {
      label: "Blocked",
      summary: "before",
      layers: "transport=degraded, auth=degraded, session=degraded, inventory=ready"
    },
    after: {
      label: "Ready",
      summary: "after",
      layers: "transport=ready, auth=ready, session=ready, inventory=ready"
    },
    ...overrides
  };
}

test("recovery audit summarizes status counts and sorts newest first", () => {
  const audit = buildOpenClawRecoveryAudit([
    createRecoveryReport({
      createdAt: 1_700_000_001,
      status: "manual_follow_up",
      after: {
        label: "Blocked",
        summary: "manual",
        layers: "transport=ready, auth=degraded, session=degraded, inventory=unavailable"
      }
    }),
    createRecoveryReport({
      createdAt: 1_700_000_003,
      status: "failed",
      after: {
        label: "Blocked",
        summary: "failed",
        layers: "transport=unavailable, auth=unavailable, session=unavailable, inventory=unavailable"
      }
    }),
    createRecoveryReport({
      createdAt: 1_700_000_002,
      status: "partial",
      after: {
        label: "Degraded",
        summary: "partial",
        layers: "transport=ready, auth=ready, session=ready, inventory=degraded"
      }
    })
  ]);

  assert.equal(audit.summary.total, 3);
  assert.equal(audit.summary.manualFollowUp, 1);
  assert.equal(audit.summary.failed, 1);
  assert.equal(audit.summary.partial, 1);
  assert.equal(audit.latest?.createdAt, 1_700_000_003);
  assert.deepEqual(
    audit.timeline.map((report) => report.createdAt),
    [1_700_000_003, 1_700_000_002, 1_700_000_001]
  );
});

test("recovery audit tracks improvement and ready outcomes", () => {
  const audit = buildOpenClawRecoveryAudit([
    createRecoveryReport({
      createdAt: 1_700_000_010,
      after: {
        label: "Ready",
        summary: "ready",
        layers: "transport=ready, auth=ready, session=ready, inventory=ready"
      }
    }),
    createRecoveryReport({
      createdAt: 1_700_000_011,
      before: {
        label: "Degraded",
        summary: "before",
        layers: "transport=ready, auth=ready, session=ready, inventory=degraded"
      },
      after: {
        label: "Degraded",
        summary: "after",
        layers: "transport=ready, auth=ready, session=ready, inventory=degraded"
      }
    })
  ]);

  assert.equal(audit.summary.improved, 1);
  assert.equal(audit.summary.reachedReady, 1);
});

test("recovery status formatter stays readable", () => {
  assert.equal(formatOpenClawRecoveryStatus("manual_follow_up"), "Manual Follow-up");
  assert.equal(formatOpenClawRecoveryStatus("failed"), "Failed");
});
