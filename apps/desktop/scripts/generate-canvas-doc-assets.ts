import fs from "node:fs";
import path from "node:path";
import type { Workflow, WorkflowEdge, WorkflowNode } from "@multi-agent-flow/domain";
import { buildEdgeLayouts, type RoutedEdgeLayout } from "../src/components/workflowCanvasRouting.js";

const NODE_WIDTH = 188;
const NODE_HEIGHT = 92;
const OUTPUT_DIR = path.resolve(process.cwd(), "../../Multi-Agent-Flow/Documentation/assets");

interface Scenario {
  fileName: string;
  title: string;
  subtitle: string;
  workflow: Workflow;
  width: number;
  height: number;
  showChrome?: boolean;
}

function makeNode(id: string, x: number, y: number, title: string): WorkflowNode {
  return {
    id,
    agentID: null,
    type: id === "start" ? "start" : "agent",
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
  options?: Partial<Pick<WorkflowEdge, "requiresApproval" | "isBidirectional">>
): WorkflowEdge {
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

function escapeXml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\"", "&quot;")
    .replaceAll("'", "&apos;");
}

function nodeTheme(node: WorkflowNode) {
  if (node.type === "start") {
    return {
      fill: "#10261c",
      stroke: "#31c48d",
      title: "#d8fff0",
      badgeFill: "#173528",
      badgeText: "#8ff5cb"
    };
  }

  return {
    fill: "#f8fbff",
    stroke: "#bfd2ea",
    title: "#11263c",
    badgeFill: "#eaf2fb",
    badgeText: "#3f6ea7"
  };
}

function renderGrid(width: number, height: number) {
  const columns = Math.ceil(width / 40);
  const rows = Math.ceil(height / 40);
  const verticals = Array.from({ length: columns }, (_, index) => {
    const x = index * 40;
    return `<line x1="${x}" y1="0" x2="${x}" y2="${height}" stroke="rgba(146, 170, 199, 0.12)" />`;
  }).join("");
  const horizontals = Array.from({ length: rows }, (_, index) => {
    const y = index * 40;
    return `<line x1="0" y1="${y}" x2="${width}" y2="${y}" stroke="rgba(146, 170, 199, 0.12)" />`;
  }).join("");
  return `<g>${verticals}${horizontals}</g>`;
}

function renderNode(node: WorkflowNode, isSelected: boolean) {
  const theme = nodeTheme(node);
  const badgeLabel = node.type === "start" ? "Entry" : "Agent";
  const x = node.position.x;
  const y = node.position.y;
  const selection = isSelected
    ? `<rect x="${x - 6}" y="${y - 6}" width="${NODE_WIDTH + 12}" height="${NODE_HEIGHT + 12}" rx="26" fill="none" stroke="#3b82f6" stroke-width="2.5" stroke-dasharray="8 6" />`
    : "";

  return `
    <g>
      ${selection}
      <rect x="${x}" y="${y}" width="${NODE_WIDTH}" height="${NODE_HEIGHT}" rx="22" fill="${theme.fill}" stroke="${theme.stroke}" stroke-width="2" />
      <rect x="${x + 16}" y="${y + 14}" width="60" height="24" rx="12" fill="${theme.badgeFill}" />
      <text x="${x + 46}" y="${y + 30}" text-anchor="middle" font-size="12" font-family="Arial, sans-serif" fill="${theme.badgeText}">${badgeLabel}</text>
      <text x="${x + 16}" y="${y + 58}" font-size="18" font-weight="700" font-family="Arial, sans-serif" fill="${theme.title}">${escapeXml(node.title)}</text>
      <text x="${x + 16}" y="${y + 78}" font-size="12" font-family="Arial, sans-serif" fill="#6b7f96">${node.type === "start" ? "Workflow entry point" : "Editable agent node"}</text>
    </g>
  `;
}

function renderEdge(layout: RoutedEdgeLayout) {
  const bridgeMask = layout.bridges.map((bridge) => (
    `<path d="M ${bridge.eraseFrom.x} ${bridge.eraseFrom.y} L ${bridge.eraseTo.x} ${bridge.eraseTo.y}" fill="none" stroke="#f8fbff" stroke-width="6" stroke-linecap="round" />`
  )).join("");
  const bridgeArcs = layout.bridges.map((bridge) => (
    `<path d="M ${bridge.arcFrom.x} ${bridge.arcFrom.y} Q ${bridge.control.x} ${bridge.control.y} ${bridge.arcTo.x} ${bridge.arcTo.y}" fill="none" stroke="#2563eb" stroke-width="3" stroke-linecap="round" />`
  )).join("");

  const label = layout.label
    ? `
      <g>
        <rect x="${layout.labelPosition.x - 34}" y="${layout.labelPosition.y - 17}" width="68" height="24" rx="12" fill="#f8fbff" stroke="#d6e4f5" />
        <text x="${layout.labelPosition.x}" y="${layout.labelPosition.y}" text-anchor="middle" font-size="12" font-family="Arial, sans-serif" fill="#315b8c">${escapeXml(layout.label)}</text>
      </g>
    `
    : "";

  return `
    <g>
      <path d="${layout.path}" fill="none" stroke="#2563eb" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" />
      ${bridgeMask}
      ${bridgeArcs}
      <circle cx="${layout.targetPoint.x}" cy="${layout.targetPoint.y}" r="4.5" fill="#2563eb" />
      ${label}
    </g>
  `;
}

function renderCanvas(workflow: Workflow, width: number, height: number, title: string, subtitle: string, showChrome = false) {
  const edgeLayouts = buildEdgeLayouts(workflow);
  const topInset = showChrome ? 92 : 24;
  const rightPanel = showChrome ? 250 : 0;
  const canvasWidth = width - 48 - rightPanel;
  const canvasHeight = height - topInset - 28;

  const toolbar = showChrome
    ? `
      <g>
        <rect x="24" y="24" width="${width - 48}" height="52" rx="18" fill="#0f172a" />
        <text x="48" y="56" font-size="18" font-weight="700" font-family="Arial, sans-serif" fill="#eff6ff">Workflow Canvas</text>
        <rect x="${width - 210}" y="38" width="78" height="24" rx="12" fill="#1d4ed8" />
        <text x="${width - 171}" y="54" text-anchor="middle" font-size="12" font-family="Arial, sans-serif" fill="#dbeafe">Connect</text>
        <rect x="${width - 118}" y="38" width="70" height="24" rx="12" fill="#16243d" stroke="#334155" />
        <text x="${width - 83}" y="54" text-anchor="middle" font-size="12" font-family="Arial, sans-serif" fill="#bfd2ea">Canvas</text>
      </g>
    `
    : "";

  const propertyPanel = showChrome
    ? `
      <g transform="translate(${width - 226}, ${topInset})">
        <rect width="202" height="${canvasHeight}" rx="22" fill="#f8fbff" stroke="#d6e4f5" />
        <text x="22" y="32" font-size="16" font-weight="700" font-family="Arial, sans-serif" fill="#11263c">Inspector</text>
        <text x="22" y="58" font-size="12" font-family="Arial, sans-serif" fill="#5d748f">Current routing policy</text>
        <rect x="22" y="74" width="158" height="30" rx="15" fill="#eaf2fb" />
        <text x="101" y="93" text-anchor="middle" font-size="12" font-family="Arial, sans-serif" fill="#315b8c">Minimize crossings</text>
        <text x="22" y="134" font-size="12" font-family="Arial, sans-serif" fill="#5d748f">Visual crossovers</text>
        <rect x="22" y="148" width="158" height="78" rx="18" fill="#f0f7ff" stroke="#d6e4f5" />
        <text x="38" y="176" font-size="12" font-family="Arial, sans-serif" fill="#315b8c">• Orthogonal paths</text>
        <text x="38" y="196" font-size="12" font-family="Arial, sans-serif" fill="#315b8c">• Fan-out / fan-in bundles</text>
        <text x="38" y="216" font-size="12" font-family="Arial, sans-serif" fill="#315b8c">• Bridge arcs for crossovers</text>
      </g>
    `
    : "";

  return `
    <svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
      <defs>
        <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="#f5f9ff" />
          <stop offset="100%" stop-color="#e7f0fb" />
        </linearGradient>
        <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
          <feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#9fb6d4" flood-opacity="0.28" />
        </filter>
      </defs>
      <rect width="${width}" height="${height}" fill="url(#bg)" />
      ${toolbar}
      <text x="24" y="${showChrome ? 108 : 34}" font-size="${showChrome ? 28 : 24}" font-weight="700" font-family="Arial, sans-serif" fill="#11263c">${escapeXml(title)}</text>
      <text x="24" y="${showChrome ? 136 : 58}" font-size="14" font-family="Arial, sans-serif" fill="#5d748f">${escapeXml(subtitle)}</text>
      <g transform="translate(24, ${topInset})">
        <rect width="${canvasWidth}" height="${canvasHeight}" rx="28" fill="#ffffff" stroke="#d6e4f5" filter="url(#shadow)" />
        <clipPath id="canvasClip">
          <rect width="${canvasWidth}" height="${canvasHeight}" rx="28" />
        </clipPath>
        <g clip-path="url(#canvasClip)">
          ${renderGrid(canvasWidth, canvasHeight)}
          ${edgeLayouts.map(renderEdge).join("")}
          ${workflow.nodes.map((node, index) => renderNode(node, showChrome && index === 1)).join("")}
        </g>
      </g>
      ${propertyPanel}
    </svg>
  `;
}

function scenarios(): Scenario[] {
  return [
    {
      fileName: "workflow-canvas-editor-overview-2026-03-21.svg",
      title: "画布编辑器总览",
      subtitle: "正交连线、减少交叉、不可避免交叉时用弧桥标识“仅跨越不连接”。",
      showChrome: true,
      width: 1360,
      height: 860,
      workflow: makeWorkflow(
        "editor-overview",
        [
          makeNode("start", 64, 138, "Start"),
          makeNode("planner", 280, 118, "Planner"),
          makeNode("research", 500, 54, "Research Agent"),
          makeNode("writer", 500, 262, "Writer Agent"),
          makeNode("review", 740, 138, "Review Agent"),
          makeNode("publish", 874, 138, "Publish")
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
      fileName: "workflow-canvas-routing-fanout-2026-03-21.svg",
      title: "同源多分支会先做 fan-out 收束",
      subtitle: "从同一节点发散的路径优先共享主干，再分别进入目标节点，减少不必要交叉。",
      width: 1100,
      height: 640,
      workflow: makeWorkflow(
        "fanout",
        [
          makeNode("source", 210, 100, "Planner"),
          makeNode("left", 54, 362, "Research"),
          makeNode("center", 330, 362, "Compliance"),
          makeNode("right", 612, 362, "Writer")
        ],
        [
          makeEdge("fanout-1", "source", "left"),
          makeEdge("fanout-2", "source", "center"),
          makeEdge("fanout-3", "source", "right")
        ]
      )
    },
    {
      fileName: "workflow-canvas-routing-fanin-2026-03-21.svg",
      title: "同目标多输入会先做 fan-in 汇流",
      subtitle: "多个上游进入同一节点时优先共用汇流段，让画布更整洁，也更容易阅读。",
      width: 1100,
      height: 640,
      workflow: makeWorkflow(
        "fanin",
        [
          makeNode("left", 56, 90, "Research"),
          makeNode("center", 350, 90, "Writer"),
          makeNode("right", 646, 90, "QA"),
          makeNode("target", 350, 360, "Review")
        ],
        [
          makeEdge("fanin-1", "left", "target"),
          makeEdge("fanin-2", "center", "target"),
          makeEdge("fanin-3", "right", "target")
        ]
      )
    },
    {
      fileName: "workflow-canvas-routing-bridge-2026-03-21.svg",
      title: "交叉不可避免时使用弧桥说明并非真实连接",
      subtitle: "优先避让；如果必须跨越，则在线上做跳线弧桥，明确表示只是视觉跨越。",
      width: 1100,
      height: 640,
      workflow: makeWorkflow(
        "bridge",
        [
          makeNode("left-top", 56, 72, "Intake"),
          makeNode("left-bottom", 56, 360, "Fallback"),
          makeNode("mid-top", 370, 72, "Planner"),
          makeNode("mid-bottom", 370, 360, "Recovery"),
          makeNode("right-top", 686, 72, "Review"),
          makeNode("right-bottom", 686, 360, "Archive")
        ],
        [
          makeEdge("bridge-1", "left-top", "right-bottom"),
          makeEdge("bridge-2", "left-bottom", "right-top"),
          makeEdge("bridge-3", "mid-top", "mid-bottom")
        ]
      )
    }
  ];
}

function writeScenarioAsset(scenario: Scenario) {
  const svg = renderCanvas(
    scenario.workflow,
    scenario.width,
    scenario.height,
    scenario.title,
    scenario.subtitle,
    scenario.showChrome ?? false
  );
  fs.writeFileSync(path.join(OUTPUT_DIR, scenario.fileName), svg, "utf8");
  return scenario.fileName;
}

function main() {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  const files = scenarios().map(writeScenarioAsset);
  console.log(`generated ${files.length} canvas doc assets`);
  for (const file of files) {
    console.log(`- ${path.join("Multi-Agent-Flow/Documentation/assets", file)}`);
  }
}

main();
