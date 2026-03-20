import type { Agent, MAProject, Workflow, WorkflowNodeType } from "@multi-agent-flow/domain";
import { toSwiftDate } from "./swift-date";
import { createUUID } from "./uuid";

function withUpdatedAt(project: MAProject): MAProject {
  return {
    ...project,
    updatedAt: toSwiftDate()
  };
}

function uniqueName(existingNames: string[], baseName: string): string {
  const trimmed = baseName.trim() || "Untitled";
  const existing = new Set(existingNames);
  if (!existing.has(trimmed)) {
    return trimmed;
  }

  let counter = 2;
  let candidate = `${trimmed} ${counter}`;
  while (existing.has(candidate)) {
    counter += 1;
    candidate = `${trimmed} ${counter}`;
  }

  return candidate;
}

function createAgent(name: string, index: number): Agent {
  const now = toSwiftDate();

  return {
    id: createUUID(),
    name,
    identity: "generalist",
    description: "",
    soulMD: "# New Agent\nThis agent configuration was created in the cross-platform shell.",
    position: {
      x: 140 + index * 80,
      y: 180 + (index % 3) * 56
    },
    createdAt: now,
    updatedAt: now,
    capabilities: ["basic"],
    colorHex: null,
    openClawDefinition: {
      agentIdentifier: name,
      modelIdentifier: "MiniMax-M2.5",
      runtimeProfile: "default",
      memoryBackupPath: null,
      soulSourcePath: null,
      environment: {}
    }
  };
}

function updateWorkflow(project: MAProject, workflowId: string, mutate: (workflow: Workflow) => Workflow): MAProject {
  return withUpdatedAt({
    ...project,
    workflows: project.workflows.map((workflow) =>
      workflow.id === workflowId ? mutate(workflow) : workflow
    )
  });
}

export function renameProject(project: MAProject, nextName: string): MAProject {
  return withUpdatedAt({
    ...project,
    name: nextName
  });
}

export function addAgentToProject(project: MAProject, baseName = "New Agent"): MAProject {
  const name = uniqueName(
    project.agents.map((agent) => agent.name),
    baseName
  );

  return withUpdatedAt({
    ...project,
    agents: [...project.agents, createAgent(name, project.agents.length)]
  });
}

export function addWorkflowToProject(project: MAProject, baseName = "Workflow"): MAProject {
  const now = toSwiftDate();
  const name = uniqueName(
    project.workflows.map((workflow) => workflow.name),
    baseName
  );

  return withUpdatedAt({
    ...project,
    workflows: [
      ...project.workflows,
      {
        id: createUUID(),
        name,
        fallbackRoutingPolicy: "stop",
        launchTestCases: [],
        lastLaunchVerificationReport: null,
        nodes: [],
        edges: [],
        boundaries: [],
        colorGroups: [],
        createdAt: now,
        parentNodeID: null,
        inputSchema: [],
        outputSchema: []
      }
    ]
  });
}

export function addNodeToWorkflow(
  project: MAProject,
  workflowId: string,
  nodeType: WorkflowNodeType
): MAProject {
  return updateWorkflow(project, workflowId, (workflow) => {
    const nodeIndex = workflow.nodes.length;

    return {
      ...workflow,
      nodes: [
        ...workflow.nodes,
        {
          id: createUUID(),
          agentID: null,
          type: nodeType,
          position: {
            x: 120 + nodeIndex * 160,
            y: nodeType === "start" ? 120 : 260
          },
          title: nodeType === "start" ? "Start" : `Agent Node ${nodeIndex + 1}`,
          displayColorHex: null,
          conditionExpression: "",
          loopEnabled: false,
          maxIterations: 1,
          subflowID: null,
          nestingLevel: 0,
          inputParameters: [],
          outputParameters: []
        }
      ]
    };
  });
}

export function assignAgentToNode(
  project: MAProject,
  workflowId: string,
  nodeId: string,
  agentId: string | null
): MAProject {
  const agentName = project.agents.find((agent) => agent.id === agentId)?.name;

  return updateWorkflow(project, workflowId, (workflow) => ({
    ...workflow,
    nodes: workflow.nodes.map((node) =>
      node.id === nodeId
        ? {
            ...node,
            agentID: agentId,
            title: agentName && node.type === "agent" ? agentName : node.title
          }
        : node
    )
  }));
}

export function connectWorkflowNodes(
  project: MAProject,
  workflowId: string,
  fromNodeID: string,
  toNodeID: string
): MAProject {
  if (!fromNodeID || !toNodeID || fromNodeID === toNodeID) {
    return project;
  }

  return updateWorkflow(project, workflowId, (workflow) => {
    const exists = workflow.edges.some(
      (edge) => edge.fromNodeID === fromNodeID && edge.toNodeID === toNodeID
    );
    if (exists) {
      return workflow;
    }

    return {
      ...workflow,
      edges: [
        ...workflow.edges,
        {
          id: createUUID(),
          fromNodeID,
          toNodeID,
          label: "",
          displayColorHex: null,
          conditionExpression: "",
          requiresApproval: false,
          isBidirectional: false,
          dataMapping: {}
        }
      ]
    };
  });
}
