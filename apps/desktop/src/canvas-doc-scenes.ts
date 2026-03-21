import type { Workflow } from "@multi-agent-flow/domain";

export interface CanvasDocScene {
  id: "overview" | "fanout" | "fanin" | "bridge";
  title: string;
  subtitle: string;
  emphasis: string;
  bullets: string[];
  workflow: Workflow;
  selectedEdgeId?: string;
  selectedNodeIds?: string[];
  zoom?: number;
  focusBox?: {
    left: number;
    top: number;
    width: number;
    height: number;
    label: string;
  };
}

function makeNode(
  id: string,
  x: number,
  y: number,
  title: string,
  type: "start" | "agent" = "agent"
): Workflow["nodes"][number] {
  return {
    id,
    agentID: null,
    type,
    position: { x, y },
    title,
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

function makeEdge(
  id: string,
  fromNodeID: string,
  toNodeID: string,
  label = "",
  options?: { requiresApproval?: boolean; isBidirectional?: boolean }
): Workflow["edges"][number] {
  return {
    id,
    fromNodeID,
    toNodeID,
    label,
    displayColorHex: null,
    conditionExpression: "",
    requiresApproval: options?.requiresApproval ?? false,
    isBidirectional: options?.isBidirectional ?? false,
    dataMapping: {}
  };
}

function makeWorkflow(id: string, nodes: Workflow["nodes"], edges: Workflow["edges"]): Workflow {
  return {
    id,
    name: id,
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

export const canvasDocScenes: CanvasDocScene[] = [
  {
    id: "overview",
    title: "画布编辑器总览",
    subtitle: "真实软件画布中的正交连线、共享主干、以及跨线弧桥。",
    emphasis: "优先避让，避不开时用弧桥说明只是跨越，不是真连接。",
    bullets: [
      "从 Planner 到上下游的连线优先走规整正交路径",
      "同源多分支共享主干，减少杂乱扩散",
      "Review 的审批线保留标签与终点提示"
    ],
    selectedEdgeId: "e5",
    selectedNodeIds: ["planner", "review"],
    zoom: 0.9,
    workflow: makeWorkflow(
      "overview",
      [
        makeNode("start", 84, 144, "Start", "start"),
        makeNode("planner", 344, 126, "Planner"),
        makeNode("research", 644, 54, "Research Agent"),
        makeNode("writer", 644, 266, "Writer Agent"),
        makeNode("review", 964, 144, "Review Agent"),
        makeNode("publish", 1238, 144, "Publish Agent")
      ],
      [
        makeEdge("e1", "start", "planner"),
        makeEdge("e2", "planner", "research", "research"),
        makeEdge("e3", "planner", "writer", "draft"),
        makeEdge("e4", "research", "review", "handoff"),
        makeEdge("e5", "writer", "review", "approval", { requiresApproval: true }),
        makeEdge("e6", "review", "publish")
      ]
    )
  },
  {
    id: "fanout",
    title: "同源多分支优先共享主干",
    subtitle: "真实画布会先做 fan-out 收束，再分发到不同节点。",
    emphasis: "重点看 Planner 发出的三条线，会先共用一段主干后再分开。",
    bullets: [
      "同一节点发散时减少“炸开式”交叉",
      "上下与左右场景使用同一套路由原则",
      "更容易一眼看出谁在分配任务"
    ],
    selectedNodeIds: ["source"],
    zoom: 1.05,
    focusBox: {
      left: 292,
      top: 182,
      width: 360,
      height: 96,
      label: "共享主干后再分发"
    },
    workflow: makeWorkflow(
      "fanout",
      [
        makeNode("source", 370, 78, "Planner"),
        makeNode("left", 74, 388, "Research"),
        makeNode("center", 370, 388, "Compliance"),
        makeNode("right", 666, 388, "Writer")
      ],
      [
        makeEdge("fanout-1", "source", "left"),
        makeEdge("fanout-2", "source", "center"),
        makeEdge("fanout-3", "source", "right")
      ]
    )
  },
  {
    id: "fanin",
    title: "同目标多输入优先汇流",
    subtitle: "真实画布会先做 fan-in 汇聚，再进入目标节点。",
    emphasis: "重点看 Review 前的一段汇流主干，三条线先整理后再接入目标。",
    bullets: [
      "多上游接入同一节点时更整洁",
      "更容易辨认哪个节点是汇总入口",
      "能减少目标节点前的局部缠绕"
    ],
    selectedNodeIds: ["target"],
    zoom: 1.05,
    focusBox: {
      left: 300,
      top: 214,
      width: 328,
      height: 120,
      label: "先汇流，再进入目标"
    },
    workflow: makeWorkflow(
      "fanin",
      [
        makeNode("left", 74, 78, "Research"),
        makeNode("center", 370, 78, "Writer"),
        makeNode("right", 666, 78, "QA"),
        makeNode("target", 370, 388, "Review")
      ],
      [
        makeEdge("fanin-1", "left", "target"),
        makeEdge("fanin-2", "center", "target"),
        makeEdge("fanin-3", "right", "target")
      ]
    )
  },
  {
    id: "bridge",
    title: "交叉不可避免时显示弧桥",
    subtitle: "真实画布不会把两条线直接画穿，而是用跳线弧桥说明“仅跨越”。",
    emphasis: "重点看中部横向连线上的弧桥，它是在明确告诉用户这里不存在真实连接。",
    bullets: [
      "优先减少交叉，不先用弧桥掩饰问题",
      "如果必须跨越，则在线上做可读的跳线提示",
      "能明显降低把交叉误读为连接的风险"
    ],
    selectedEdgeId: "bridge-1",
    zoom: 1.12,
    focusBox: {
      left: 382,
      top: 226,
      width: 176,
      height: 88,
      label: "这里是弧桥，不是真连接"
    },
    workflow: makeWorkflow(
      "bridge",
      [
        makeNode("left-top", 64, 78, "Intake"),
        makeNode("left-bottom", 64, 388, "Fallback"),
        makeNode("mid-top", 382, 78, "Planner"),
        makeNode("mid-bottom", 382, 388, "Recovery"),
        makeNode("right-top", 700, 78, "Review"),
        makeNode("right-bottom", 700, 388, "Archive")
      ],
      [
        makeEdge("bridge-1", "left-top", "right-bottom", "handoff"),
        makeEdge("bridge-2", "left-bottom", "right-top", "escalate"),
        makeEdge("bridge-3", "mid-top", "mid-bottom", "fallback")
      ]
    )
  }
];

export function resolveCanvasDocScene(id: string | null) {
  return canvasDocScenes.find((scene) => scene.id === id) ?? canvasDocScenes[0];
}
