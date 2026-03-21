import assert from "node:assert/strict";
import type { Workflow, WorkflowEdge, WorkflowNode } from "@multi-agent-flow/domain";
import { buildBridgeOverlays, buildEdgeLayouts, type RoutedEdgeLayout } from "../src/components/workflowCanvasRouting.js";

function makeNode(id: string, x: number, y: number): WorkflowNode {
  return {
    id,
    agentID: null,
    type: "agent",
    position: { x, y },
    title: id,
    displayColorHex: null,
    conditionExpression: "",
    loopEnabled: false,
    maxIterations: 1,
    subflowID: null,
    nestingLevel: 0,
    inputParameters: [],
    outputParameters: []
  };
}

function makeEdge(id: string, fromNodeID: string, toNodeID: string): WorkflowEdge {
  return {
    id,
    fromNodeID,
    toNodeID,
    label: "",
    displayColorHex: null,
    conditionExpression: "",
    requiresApproval: false,
    isBidirectional: false,
    dataMapping: {}
  };
}

function makeWorkflow(name: string, nodes: WorkflowNode[], edges: WorkflowEdge[]): Workflow {
  return {
    id: name,
    name,
    fallbackRoutingPolicy: "first_available",
    launchTestCases: [],
    lastLaunchVerificationReport: null,
    nodes,
    edges,
    boundaries: [],
    colorGroups: [],
    createdAt: Date.now(),
    parentNodeID: null,
    inputSchema: [],
    outputSchema: []
  };
}

function layoutById(layouts: RoutedEdgeLayout[]) {
  return new Map(layouts.map((layout) => [layout.edgeId, layout]));
}

function assertSame(valueA: number | undefined, valueB: number | undefined, message: string) {
  assert.notEqual(valueA, undefined, `${message}: first value missing`);
  assert.notEqual(valueB, undefined, `${message}: second value missing`);
  assert.equal(valueA, valueB, message);
}

function validateVerticalFanout() {
  const workflow = makeWorkflow(
    "vertical-fanout",
    [
      makeNode("source", 220, 80),
      makeNode("target-left", 40, 320),
      makeNode("target-right", 400, 320)
    ],
    [
      makeEdge("edge-left", "source", "target-left"),
      makeEdge("edge-right", "source", "target-right")
    ]
  );

  const layouts = layoutById(buildEdgeLayouts(workflow));
  assertSame(layouts.get("edge-left")?.points[1]?.y, layouts.get("edge-right")?.points[1]?.y, "vertical fanout should share a common turn Y");
}

function validateHorizontalFanout() {
  const workflow = makeWorkflow(
    "horizontal-fanout",
    [
      makeNode("source", 80, 180),
      makeNode("target-top", 420, 40),
      makeNode("target-bottom", 420, 320)
    ],
    [
      makeEdge("edge-top", "source", "target-top"),
      makeEdge("edge-bottom", "source", "target-bottom")
    ]
  );

  const layouts = layoutById(buildEdgeLayouts(workflow));
  assertSame(layouts.get("edge-top")?.points[1]?.x, layouts.get("edge-bottom")?.points[1]?.x, "horizontal fanout should share a common turn X");
}

function validateVerticalFanin() {
  const workflow = makeWorkflow(
    "vertical-fanin",
    [
      makeNode("source-left", 60, 60),
      makeNode("source-right", 380, 60),
      makeNode("target", 220, 320)
    ],
    [
      makeEdge("edge-left", "source-left", "target"),
      makeEdge("edge-right", "source-right", "target")
    ]
  );

  const layouts = layoutById(buildEdgeLayouts(workflow));
  assertSame(layouts.get("edge-left")?.points[1]?.y, layouts.get("edge-right")?.points[1]?.y, "vertical fanin should share a common merge Y");
}

function validateBridgeOverlay() {
  const layouts: RoutedEdgeLayout[] = [
    {
      edgeId: "horizontal",
      points: [
        { x: 40, y: 160 },
        { x: 260, y: 160 }
      ],
      path: "",
      bridges: [],
      label: "",
      labelPosition: { x: 0, y: 0 },
      targetPoint: { x: 260, y: 160 }
    },
    {
      edgeId: "vertical",
      points: [
        { x: 150, y: 60 },
        { x: 150, y: 280 }
      ],
      path: "",
      bridges: [],
      label: "",
      labelPosition: { x: 0, y: 0 },
      targetPoint: { x: 150, y: 280 }
    }
  ];

  const bridged = layoutById(buildBridgeOverlays(layouts));
  assert.ok((bridged.get("horizontal")?.bridges.length ?? 0) > 0, "crossing horizontal edge should receive a bridge overlay");
  assert.equal(bridged.get("vertical")?.bridges.length ?? 0, 0, "vertical edge should stay unbridged in crossing overlay");
}

function run() {
  validateVerticalFanout();
  validateHorizontalFanout();
  validateVerticalFanin();
  validateBridgeOverlay();
  console.log("routing smoke validation passed");
}

run();
