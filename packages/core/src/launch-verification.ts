import type {
  Agent,
  ExecutionOutputType,
  ExecutionStatus,
  MAProject,
  Workflow,
  WorkflowLaunchTestCase,
  WorkflowLaunchTestCaseReport,
  WorkflowLaunchVerificationReport,
  WorkflowNode,
  WorkflowVerificationStatus
} from "@multi-agent-flow/domain";
import { assessWorkflowRuntimeIsolation } from "./runtime-isolation";
import { toSwiftDate } from "./swift-date";
import { createUUID } from "./uuid";

export interface WorkflowLaunchExecutionObservation {
  agentID: string;
  status: ExecutionStatus;
  outputType: ExecutionOutputType;
  routingAction?: string | null;
  routingTargets: string[];
}

function workflowNodeSort(left: WorkflowNode, right: WorkflowNode): number {
  if (left.position.y !== right.position.y) {
    return left.position.y - right.position.y;
  }
  if (left.position.x !== right.position.x) {
    return left.position.x - right.position.x;
  }
  return left.title.localeCompare(right.title);
}

export function calculateWorkflowLaunchVerificationSignature(workflow: Workflow, agents: Agent[]): string {
  const agentIDs = agents
    .map((agent) => `${agent.id}:${agent.name}:${agent.openClawDefinition.agentIdentifier}`)
    .sort()
    .join("|");
  const launchCaseFingerprint = workflow.launchTestCases
    .map((testCase) =>
      [
        testCase.name,
        testCase.prompt,
        testCase.requiredAgentNames.join(","),
        testCase.forbiddenAgentNames.join(","),
        testCase.expectedRoutingActions.join(","),
        testCase.expectedOutputTypes.join(","),
        testCase.maxSteps ?? "",
        testCase.notes
      ].join("|")
    )
    .sort()
    .join("::");

  return [
    workflow.id,
    workflow.name,
    workflow.fallbackRoutingPolicy,
    `nodes:${workflow.nodes.length}`,
    `edges:${workflow.edges.length}`,
    `cases:${workflow.launchTestCases.length}`,
    launchCaseFingerprint,
    agentIDs
  ].join("::");
}

function entryConnectedAgentNodes(workflow: Workflow): WorkflowNode[] {
  const nodeMap = new Map(workflow.nodes.map((node) => [node.id, node] as const));
  const startNodeIds = workflow.nodes.filter((node) => node.type === "start").map((node) => node.id);
  const connected = workflow.edges
    .filter((edge) => startNodeIds.includes(edge.fromNodeID))
    .map((edge) => nodeMap.get(edge.toNodeID))
    .filter((node): node is WorkflowNode => Boolean(node && node.type === "agent" && node.agentID))
    .sort(workflowNodeSort);

  const seen = new Set<string>();
  return connected.filter((node) => {
    if (seen.has(node.id)) {
      return false;
    }
    seen.add(node.id);
    return true;
  });
}

function reachableAgentNodeIds(workflow: Workflow): Set<string> {
  const nodeMap = new Map(workflow.nodes.map((node) => [node.id, node] as const));
  const outgoing = new Map<string, string[]>();
  for (const edge of workflow.edges) {
    outgoing.set(edge.fromNodeID, [...(outgoing.get(edge.fromNodeID) ?? []), edge.toNodeID]);
    if (edge.isBidirectional) {
      outgoing.set(edge.toNodeID, [...(outgoing.get(edge.toNodeID) ?? []), edge.fromNodeID]);
    }
  }

  const queue = entryConnectedAgentNodes(workflow).map((node) => node.id);
  const visited = new Set<string>();
  while (queue.length > 0) {
    const nodeId = queue.shift();
    if (!nodeId || visited.has(nodeId)) {
      continue;
    }
    visited.add(nodeId);
    for (const nextId of outgoing.get(nodeId) ?? []) {
      const nextNode = nodeMap.get(nextId);
      if (nextNode?.type === "agent" && !visited.has(nextNode.id)) {
        queue.push(nextNode.id);
      }
    }
  }
  return visited;
}

function aggregateVerificationStatus(failures: string[], warnings: string[]): WorkflowVerificationStatus {
  if (failures.length > 0) {
    return "fail";
  }
  if (warnings.length > 0) {
    return "warn";
  }
  return "pass";
}

function aggregateVerificationReportStatus(
  initial: WorkflowVerificationStatus,
  runtimeFindings: string[],
  caseReports: WorkflowLaunchTestCaseReport[]
): WorkflowVerificationStatus {
  if (initial === "fail" || caseReports.some((report) => report.status === "fail")) {
    return "fail";
  }
  if (initial === "warn" || runtimeFindings.length > 0 || caseReports.some((report) => report.status === "warn")) {
    return "warn";
  }
  return "pass";
}

function staticVerificationFindings(project: MAProject, workflow: Workflow): {
  status: WorkflowVerificationStatus;
  findings: string[];
} {
  const failures: string[] = [];
  const warnings: string[] = [];
  const agentByID = new Map(project.agents.map((agent) => [agent.id, agent] as const));
  const agentNodes = workflow.nodes.filter((node) => node.type === "agent");

  if (!project.openClaw.isConnected) {
    failures.push("OpenClaw is not connected, so launch verification cannot confirm runnable state.");
  }

  if (agentNodes.length === 0) {
    failures.push("The workflow has no agent nodes to execute.");
  }

  const entryNodes = entryConnectedAgentNodes(workflow);
  if (entryNodes.length === 0) {
    failures.push("No Start node is connected to an executable agent node.");
  }

  const missingAgentNodes = agentNodes.filter((node) => {
    if (!node.agentID) {
      return true;
    }
    return !agentByID.has(node.agentID);
  });
  if (missingAgentNodes.length > 0) {
    failures.push(`${missingAgentNodes.length} agent node(s) are missing a valid assigned agent.`);
  }

  const invalidIdentifiers = project.agents.filter((agent) => {
    return !agent.name.trim() && !agent.openClawDefinition.agentIdentifier.trim();
  });
  if (invalidIdentifiers.length > 0) {
    failures.push(`${invalidIdentifiers.length} agent(s) are missing a usable OpenClaw identifier.`);
  }

  const runtimeIsolation = assessWorkflowRuntimeIsolation(project, workflow);
  warnings.push(...runtimeIsolation.blockingFindings);

  const reachable = reachableAgentNodeIds(workflow);
  const unreachableAgents = agentNodes.filter((node) => !reachable.has(node.id));
  if (unreachableAgents.length > 0) {
    warnings.push(`${unreachableAgents.length} agent node(s) are unreachable from the workflow entry path.`);
  }

  if (workflow.fallbackRoutingPolicy !== "stop") {
    warnings.push(
      `Fallback routing policy is "${workflow.fallbackRoutingPolicy}", so downstream agents may still run without an explicit route.`
    );
  }

  const approvalEdges = workflow.edges.filter((edge) => edge.requiresApproval);
  if (approvalEdges.length > 0) {
    warnings.push(`${approvalEdges.length} edge(s) require approval and may pause execution during launch.`);
  }

  if (workflow.launchTestCases.length > 0) {
    warnings.push(
      `This workflow has ${workflow.launchTestCases.length} saved launch test case(s) configured for runtime verification.`
    );
  }

  return {
    status: aggregateVerificationStatus(failures, warnings),
    findings: [...failures, ...warnings]
  };
}

function defaultLaunchTestCases(workflow: Workflow, agents: Agent[]): WorkflowLaunchTestCase[] {
  const entryNodes = entryConnectedAgentNodes(workflow);
  const entryAgentIDs = new Set(entryNodes.map((node) => node.agentID).filter(Boolean));
  const entryAgentNames = agents
    .filter((agent) => entryAgentIDs.has(agent.id))
    .map((agent) => agent.name)
    .sort((left, right) => left.localeCompare(right));
  const nonEntryAgentNames = agents
    .filter((agent) => !entryAgentIDs.has(agent.id))
    .map((agent) => agent.name)
    .sort((left, right) => left.localeCompare(right));
  const strictStepLimit = Math.max(1, entryAgentNames.length);

  const cases: WorkflowLaunchTestCase[] = [
    {
      id: createUUID(),
      name: "Greeting Smoke",
      prompt: "Hello",
      requiredAgentNames: entryAgentNames,
      forbiddenAgentNames: nonEntryAgentNames,
      expectedRoutingActions: ["stop"],
      expectedOutputTypes: ["agent_final_response"],
      maxSteps: strictStepLimit,
      notes: "A simple greeting should not trigger downstream collaboration."
    },
    {
      id: createUUID(),
      name: "Direct Reply Smoke",
      prompt: "Reply in one sentence confirming readiness, and do not contact downstream agents if they are unnecessary.",
      requiredAgentNames: entryAgentNames,
      forbiddenAgentNames: nonEntryAgentNames,
      expectedRoutingActions: ["stop"],
      expectedOutputTypes: ["agent_final_response"],
      maxSteps: strictStepLimit,
      notes: "The entry agent should be able to respond directly and stop."
    }
  ];

  if (nonEntryAgentNames.length > 0) {
    cases.push({
      id: createUUID(),
      name: "Routing Contract Smoke",
      prompt: "If downstream collaboration is truly needed, choose the smallest valid downstream set and emit a valid routing decision.",
      requiredAgentNames: entryAgentNames,
      forbiddenAgentNames: [],
      expectedRoutingActions: [],
      expectedOutputTypes: ["agent_final_response"],
      maxSteps: null,
      notes: "Verifies that routing directives remain parseable during launch verification."
    });
  }

  return cases;
}

export function resolveWorkflowLaunchTestCases(project: MAProject, workflowId: string): WorkflowLaunchTestCase[] {
  const workflow = project.workflows.find((item) => item.id === workflowId);
  if (!workflow) {
    return [];
  }

  if (workflow.launchTestCases.length > 0) {
    return workflow.launchTestCases;
  }

  return defaultLaunchTestCases(workflow, project.agents);
}

export function evaluateWorkflowLaunchTestCase(
  project: MAProject,
  workflowId: string,
  testCase: WorkflowLaunchTestCase,
  observations: WorkflowLaunchExecutionObservation[],
  runtimeFindings: string[]
): WorkflowLaunchTestCaseReport {
  const workflow = project.workflows.find((item) => item.id === workflowId);
  const agents = project.agents;
  const agentNameByID = new Map(agents.map((agent) => [agent.id, agent.name] as const));
  const actualAgents = observations.map((item) => agentNameByID.get(item.agentID) ?? item.agentID.slice(0, 8));
  const actualRoutingActions = observations
    .map((item) => item.routingAction?.toLowerCase())
    .filter((item): item is string => Boolean(item));
  const actualRoutingTargets = Array.from(new Set(observations.flatMap((item) => item.routingTargets))).sort();
  const actualOutputTypes: string[] = observations.map((item) => item.outputType);

  const failures: string[] = [];
  const warnings: string[] = [];

  if (!workflow) {
    failures.push("The workflow could not be resolved while evaluating the launch test case.");
  }

  if (observations.length === 0) {
    failures.push("No execution observations were captured.");
  }

  const failedResults = observations.filter((item) => item.status === "Failed");
  if (failedResults.length > 0) {
    failures.push(`${failedResults.length} node(s) failed during the verification run.`);
  }

  for (const required of testCase.requiredAgentNames) {
    if (!actualAgents.includes(required)) {
      failures.push(`Missing required agent: ${required}`);
    }
  }

  for (const forbidden of testCase.forbiddenAgentNames) {
    if (actualAgents.includes(forbidden)) {
      failures.push(`Triggered forbidden agent: ${forbidden}`);
    }
  }

  if (typeof testCase.maxSteps === "number" && observations.length > testCase.maxSteps) {
    failures.push(`Observed ${observations.length} steps, exceeding the limit of ${testCase.maxSteps}.`);
  }

  for (const expectedAction of testCase.expectedRoutingActions.map((item) => item.toLowerCase())) {
    if (!actualRoutingActions.includes(expectedAction)) {
      failures.push(`Missing expected routing action: ${expectedAction}`);
    }
  }

  for (const expectedOutputType of testCase.expectedOutputTypes) {
    if (!actualOutputTypes.includes(expectedOutputType)) {
      failures.push(`Missing expected output type: ${expectedOutputType}`);
    }
  }

  if (testCase.expectedRoutingActions.length > 0 && actualRoutingActions.length === 0) {
    warnings.push("No explicit routing decision was observed, so the workflow may be relying on fallback routing.");
  }

  warnings.push(...runtimeFindings);

  return {
    id: createUUID(),
    testCaseID: testCase.id,
    name: testCase.name,
    prompt: testCase.prompt,
    status: aggregateVerificationStatus(failures, warnings),
    actualStepCount: observations.length,
    actualAgents,
    actualRoutingActions,
    actualRoutingTargets,
    actualOutputTypes,
    notes: [...failures, ...warnings]
  };
}

export function runWorkflowLaunchVerification(project: MAProject, workflowId: string): {
  project: MAProject;
  report: WorkflowLaunchVerificationReport | null;
} {
  const workflow = project.workflows.find((item) => item.id === workflowId);
  if (!workflow) {
    return {
      project,
      report: null
    };
  }

  const startedAt = toSwiftDate();
  const staticEvaluation = staticVerificationFindings(project, workflow);
  const report: WorkflowLaunchVerificationReport = {
    id: createUUID(),
    workflowID: workflow.id,
    workflowName: workflow.name,
    workflowSignature: calculateWorkflowLaunchVerificationSignature(workflow, project.agents),
    startedAt,
    completedAt: toSwiftDate(),
    status: staticEvaluation.status,
    staticFindings: staticEvaluation.findings,
    runtimeFindings: [],
    testCaseReports: []
  };

  return {
    report,
    project: {
      ...project,
      workflows: project.workflows.map((item) =>
        item.id === workflowId
          ? {
              ...item,
              lastLaunchVerificationReport: report
            }
          : item
      ),
      updatedAt: toSwiftDate()
    }
  };
}

export function finalizeWorkflowLaunchVerification(
  project: MAProject,
  workflowId: string,
  runtimeFindings: string[],
  caseReports: WorkflowLaunchTestCaseReport[]
): {
  project: MAProject;
  report: WorkflowLaunchVerificationReport | null;
} {
  const workflow = project.workflows.find((item) => item.id === workflowId);
  if (!workflow) {
    return {
      project,
      report: null
    };
  }

  const staticEvaluation = staticVerificationFindings(project, workflow);
  const previous = workflow.lastLaunchVerificationReport;
  const report: WorkflowLaunchVerificationReport = {
    id: previous?.id ?? createUUID(),
    workflowID: workflow.id,
    workflowName: workflow.name,
    workflowSignature: calculateWorkflowLaunchVerificationSignature(workflow, project.agents),
    startedAt: previous?.startedAt ?? toSwiftDate(),
    completedAt: toSwiftDate(),
    status: aggregateVerificationReportStatus(staticEvaluation.status, runtimeFindings, caseReports),
    staticFindings: staticEvaluation.findings,
    runtimeFindings: Array.from(new Set(runtimeFindings)),
    testCaseReports: caseReports
  };

  return {
    report,
    project: {
      ...project,
      workflows: project.workflows.map((item) =>
        item.id === workflowId
          ? {
              ...item,
              lastLaunchVerificationReport: report
            }
          : item
      ),
      updatedAt: toSwiftDate()
    }
  };
}
