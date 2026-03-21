#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

function resolveReportPath(inputPath) {
  const fallbackDirectory = path.join(
    os.homedir(),
    "Library",
    "Application Support",
    "OpenClaw",
    "benchmarks"
  );
  const resolvedInput = inputPath ? path.resolve(inputPath) : fallbackDirectory;

  if (!fs.existsSync(resolvedInput)) {
    throw new Error(`Benchmark path not found: ${resolvedInput}`);
  }

  const stats = fs.statSync(resolvedInput);
  if (stats.isFile()) {
    return resolvedInput;
  }

  const candidateFiles = fs
    .readdirSync(resolvedInput)
    .filter((entry) => entry.endsWith(".json"))
    .map((entry) => path.join(resolvedInput, entry))
    .sort((left, right) => {
      const leftTime = fs.statSync(left).mtimeMs;
      const rightTime = fs.statSync(right).mtimeMs;
      return rightTime - leftTime;
    });

  if (candidateFiles.length === 0) {
    throw new Error(`No benchmark reports found in: ${resolvedInput}`);
  }

  return candidateFiles[0];
}

function formatPercent(numerator, denominator) {
  if (!denominator) {
    return "n/a";
  }
  return `${((numerator / denominator) * 100).toFixed(1)}%`;
}

function main() {
  const inputPath = process.argv[2];
  const reportPath = resolveReportPath(inputPath);
  const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
  const summaries = Array.isArray(report.summaries) ? report.summaries : [];
  const workflowSummary = summaries.find(
    (summary) => summary.transport === "workflow_hot_path"
  );

  if (!workflowSummary) {
    throw new Error("workflow_hot_path summary not found in benchmark report");
  }

  const actualKinds = Array.isArray(workflowSummary.actualTransportKinds)
    ? workflowSummary.actualTransportKinds
    : [];
  const matched = Number(workflowSummary.expectedTransportMatchedCount ?? 0);
  const mismatched = Number(workflowSummary.expectedTransportMismatchCount ?? 0);
  const sampleCount = Number(workflowSummary.sampleCount ?? 0);
  const expected = workflowSummary.expectedTransportKind ?? "unknown";
  const passed = expected === "gateway_agent" && mismatched === 0 && matched > 0;

  console.log("Transport Benchmark Report");
  console.log(`Report: ${reportPath}`);
  console.log(`Completed: ${report.completedAt ?? "unknown"}`);
  console.log(`Deployment: ${report.deploymentKind ?? "unknown"}`);
  console.log(`Workflow Hot Path: ${passed ? "PASS" : "FAIL"}`);
  console.log(`Expected: ${expected}`);
  console.log(`Observed: ${actualKinds.length > 0 ? actualKinds.join(", ") : "none"}`);
  console.log(`Matched: ${matched}/${sampleCount} (${formatPercent(matched, sampleCount)})`);
  console.log(`Mismatch: ${mismatched}/${sampleCount} (${formatPercent(mismatched, sampleCount)})`);

  if (workflowSummary.averageFirstChunkLatencyMs != null) {
    console.log(
      `Avg first chunk: ${workflowSummary.averageFirstChunkLatencyMs.toFixed(1)} ms`
    );
  }
  if (workflowSummary.averageCompletionLatencyMs != null) {
    console.log(
      `Avg completion: ${workflowSummary.averageCompletionLatencyMs.toFixed(1)} ms`
    );
  }

  process.exitCode = passed ? 0 : 2;
}

try {
  main();
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`Error: ${message}`);
  process.exitCode = 1;
}
