import type { Agent, Workflow } from "@multi-agent-flow/domain";
import { useRef, type PointerEvent as ReactPointerEvent } from "react";

interface WorkflowCanvasPreviewProps {
  workflow: Workflow;
  agents: Agent[];
  selectedFromNodeId?: string;
  selectedToNodeId?: string;
  onNodePositionChange?: (nodeId: string, x: number, y: number) => void;
  onNodePositionCommit?: (nodeId: string, x: number, y: number) => void;
  onNodeClick?: (nodeId: string) => void;
  onCanvasClick?: () => void;
}

const NODE_WIDTH = 188;
const NODE_HEIGHT = 92;
const CANVAS_PADDING = 80;

function getCanvasBounds(workflow: Workflow) {
  if (workflow.nodes.length === 0) {
    return {
      width: 920,
      height: 420
    };
  }

  const maxX = Math.max(...workflow.nodes.map((node) => node.position.x));
  const maxY = Math.max(...workflow.nodes.map((node) => node.position.y));

  return {
    width: Math.max(920, maxX + NODE_WIDTH + CANVAS_PADDING),
    height: Math.max(420, maxY + NODE_HEIGHT + CANVAS_PADDING)
  };
}

function centerPoint(node: Workflow["nodes"][number]) {
  return {
    x: node.position.x + NODE_WIDTH / 2,
    y: node.position.y + NODE_HEIGHT / 2
  };
}

function resolveNodeTitle(node: Workflow["nodes"][number], agents: Agent[]) {
  if (node.title.trim().length > 0) {
    return node.title;
  }

  if (node.agentID) {
    return agents.find((agent) => agent.id === node.agentID)?.name ?? "Agent";
  }

  return node.type === "start" ? "Start" : "Agent Node";
}

export function WorkflowCanvasPreview({
  workflow,
  agents,
  selectedFromNodeId,
  selectedToNodeId,
  onNodePositionChange,
  onNodePositionCommit,
  onNodeClick,
  onCanvasClick
}: WorkflowCanvasPreviewProps) {
  const bounds = getCanvasBounds(workflow);
  const dragStateRef = useRef<{
    nodeId: string;
    pointerId: number;
    startPointerX: number;
    startPointerY: number;
    startNodeX: number;
    startNodeY: number;
    didMove: boolean;
  } | null>(null);

  function handlePointerDown(
    event: ReactPointerEvent<HTMLElement>,
    node: Workflow["nodes"][number]
  ) {
    dragStateRef.current = {
      nodeId: node.id,
      pointerId: event.pointerId,
      startPointerX: event.clientX,
      startPointerY: event.clientY,
      startNodeX: node.position.x,
      startNodeY: node.position.y,
      didMove: false
    };

    event.currentTarget.setPointerCapture(event.pointerId);
  }

  function handlePointerMove(event: ReactPointerEvent<HTMLElement>) {
    const dragState = dragStateRef.current;
    if (!dragState || dragState.pointerId !== event.pointerId) {
      return;
    }

    const nextX = dragState.startNodeX + (event.clientX - dragState.startPointerX);
    const nextY = dragState.startNodeY + (event.clientY - dragState.startPointerY);
    const distance = Math.hypot(event.clientX - dragState.startPointerX, event.clientY - dragState.startPointerY);
    if (distance >= 3) {
      dragState.didMove = true;
    }
    onNodePositionChange?.(dragState.nodeId, nextX, nextY);
  }

  function finishPointerDrag(event: ReactPointerEvent<HTMLElement>) {
    const dragState = dragStateRef.current;
    if (!dragState || dragState.pointerId !== event.pointerId) {
      return;
    }

    const nextX = dragState.startNodeX + (event.clientX - dragState.startPointerX);
    const nextY = dragState.startNodeY + (event.clientY - dragState.startPointerY);
    const shouldTriggerClick = !dragState.didMove;
    dragStateRef.current = null;
    onNodePositionCommit?.(dragState.nodeId, nextX, nextY);
    if (shouldTriggerClick) {
      onNodeClick?.(dragState.nodeId);
    }
  }

  return (
    <div
      className="canvasPreview"
      onPointerDown={(event) => {
        if (event.target === event.currentTarget) {
          onCanvasClick?.();
        }
      }}
    >
      <div className="canvasViewport" style={{ width: bounds.width, height: bounds.height }}>
        <svg className="canvasEdges" width={bounds.width} height={bounds.height} viewBox={`0 0 ${bounds.width} ${bounds.height}`}>
          {workflow.edges.map((edge) => {
            const fromNode = workflow.nodes.find((node) => node.id === edge.fromNodeID);
            const toNode = workflow.nodes.find((node) => node.id === edge.toNodeID);
            if (!fromNode || !toNode) {
              return null;
            }

            const from = centerPoint(fromNode);
            const to = centerPoint(toNode);
            const curveOffset = Math.max(60, Math.abs(to.x - from.x) * 0.35);
            const path = `M ${from.x} ${from.y} C ${from.x + curveOffset} ${from.y}, ${to.x - curveOffset} ${to.y}, ${to.x} ${to.y}`;

            return (
              <g key={edge.id}>
                <path d={path} className="canvasEdgePath" />
                <circle cx={to.x} cy={to.y} r="4.5" className="canvasEdgeDot" />
              </g>
            );
          })}
        </svg>

        {workflow.nodes.map((node) => {
          const isFrom = selectedFromNodeId === node.id;
          const isTo = selectedToNodeId === node.id;
          const assignedAgent = node.agentID
            ? agents.find((agent) => agent.id === node.agentID) ?? null
            : null;

          return (
            <article
              key={node.id}
              className={[
                "canvasNode",
                node.type === "start" ? "canvasNodeStart" : "",
                isFrom ? "canvasNodeFrom" : "",
                isTo ? "canvasNodeTo" : ""
              ]
                .filter(Boolean)
                .join(" ")}
              style={{
                left: node.position.x,
                top: node.position.y,
                width: NODE_WIDTH,
                minHeight: NODE_HEIGHT
              }}
              onPointerDown={(event) => handlePointerDown(event, node)}
              onPointerMove={handlePointerMove}
              onPointerUp={finishPointerDrag}
              onPointerCancel={finishPointerDrag}
            >
              <div className="canvasNodeBadge">{node.type}</div>
              <strong>{resolveNodeTitle(node, agents)}</strong>
              <span>{assignedAgent?.name ?? "Unassigned agent"}</span>
              <span className="canvasNodeMeta">
                ({Math.round(node.position.x)}, {Math.round(node.position.y)})
              </span>
            </article>
          );
        })}
      </div>
    </div>
  );
}
