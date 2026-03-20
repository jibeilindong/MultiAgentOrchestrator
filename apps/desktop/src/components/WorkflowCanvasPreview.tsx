import type { Agent, Workflow } from "@multi-agent-flow/domain";
import {
  useEffect,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
  type WheelEvent as ReactWheelEvent
} from "react";

interface WorkflowCanvasPreviewProps {
  workflow: Workflow;
  agents: Agent[];
  zoom?: number;
  selectedNodeId?: string;
  selectedEdgeId?: string;
  selectedFromNodeId?: string;
  selectedToNodeId?: string;
  onNodeConnect?: (fromNodeId: string, toNodeId: string) => void;
  onNodeSelect?: (nodeId: string) => void;
  onEdgeSelect?: (edgeId: string) => void;
  onWheelZoom?: (deltaY: number) => void;
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

function edgePath(from: { x: number; y: number }, to: { x: number; y: number }) {
  const curveOffset = Math.max(60, Math.abs(to.x - from.x) * 0.35);
  return `M ${from.x} ${from.y} C ${from.x + curveOffset} ${from.y}, ${to.x - curveOffset} ${to.y}, ${to.x} ${to.y}`;
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
  zoom = 1,
  selectedNodeId,
  selectedEdgeId,
  selectedFromNodeId,
  selectedToNodeId,
  onNodeConnect,
  onNodeSelect,
  onEdgeSelect,
  onWheelZoom,
  onNodePositionChange,
  onNodePositionCommit,
  onNodeClick,
  onCanvasClick
}: WorkflowCanvasPreviewProps) {
  const bounds = getCanvasBounds(workflow);
  const previewRef = useRef<HTMLDivElement | null>(null);
  const viewportRef = useRef<HTMLDivElement | null>(null);
  const dragStateRef = useRef<{
    nodeId: string;
    pointerId: number;
    startPointerX: number;
    startPointerY: number;
    startNodeX: number;
    startNodeY: number;
    didMove: boolean;
  } | null>(null);
  const panStateRef = useRef<{
    pointerId: number;
    startPointerX: number;
    startPointerY: number;
    startScrollLeft: number;
    startScrollTop: number;
  } | null>(null);
  const [isSpacePressed, setIsSpacePressed] = useState(false);
  const [isPanning, setIsPanning] = useState(false);
  const [connectionDragState, setConnectionDragState] = useState<{
    pointerId: number;
    fromNodeId: string;
    currentX: number;
    currentY: number;
  } | null>(null);

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (event.code === "Space") {
        setIsSpacePressed(true);
      }
    }

    function handleKeyUp(event: KeyboardEvent) {
      if (event.code === "Space") {
        setIsSpacePressed(false);
      }
    }

    function clearPanKeys() {
      setIsSpacePressed(false);
    }

    window.addEventListener("keydown", handleKeyDown);
    window.addEventListener("keyup", handleKeyUp);
    window.addEventListener("blur", clearPanKeys);

    return () => {
      window.removeEventListener("keydown", handleKeyDown);
      window.removeEventListener("keyup", handleKeyUp);
      window.removeEventListener("blur", clearPanKeys);
    };
  }, []);

  function canvasPointFromClient(clientX: number, clientY: number) {
    const rect = viewportRef.current?.getBoundingClientRect();
    if (!rect) {
      return { x: 0, y: 0 };
    }

    return {
      x: (clientX - rect.left) / zoom,
      y: (clientY - rect.top) / zoom
    };
  }

  function handlePointerDown(
    event: ReactPointerEvent<HTMLElement>,
    node: Workflow["nodes"][number]
  ) {
    onNodeSelect?.(node.id);
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

    const nextX = dragState.startNodeX + (event.clientX - dragState.startPointerX) / zoom;
    const nextY = dragState.startNodeY + (event.clientY - dragState.startPointerY) / zoom;
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

    const nextX = dragState.startNodeX + (event.clientX - dragState.startPointerX) / zoom;
    const nextY = dragState.startNodeY + (event.clientY - dragState.startPointerY) / zoom;
    const shouldTriggerClick = !dragState.didMove;
    dragStateRef.current = null;
    onNodePositionCommit?.(dragState.nodeId, nextX, nextY);
    if (shouldTriggerClick) {
      onNodeClick?.(dragState.nodeId);
    }
  }

  function handleWheel(event: ReactWheelEvent<HTMLDivElement>) {
    if (!event.ctrlKey && !event.metaKey) {
      return;
    }

    event.preventDefault();
    onWheelZoom?.(event.deltaY);
  }

  function beginCanvasPan(event: ReactPointerEvent<HTMLDivElement>) {
    const preview = previewRef.current;
    if (!preview) {
      return false;
    }

    const target = event.target;
    if (target instanceof Element && target.closest(".canvasNode, .canvasEdgeHitArea, .canvasConnectHandle")) {
      return false;
    }

    const shouldPan = event.button === 1 || isSpacePressed;
    if (!shouldPan) {
      return false;
    }

    event.preventDefault();
    panStateRef.current = {
      pointerId: event.pointerId,
      startPointerX: event.clientX,
      startPointerY: event.clientY,
      startScrollLeft: preview.scrollLeft,
      startScrollTop: preview.scrollTop
    };
    setIsPanning(true);
    event.currentTarget.setPointerCapture(event.pointerId);
    return true;
  }

  function updateCanvasPan(event: ReactPointerEvent<HTMLDivElement>) {
    const panState = panStateRef.current;
    const preview = previewRef.current;
    if (!panState || !preview || panState.pointerId !== event.pointerId) {
      return;
    }

    preview.scrollLeft = panState.startScrollLeft - (event.clientX - panState.startPointerX);
    preview.scrollTop = panState.startScrollTop - (event.clientY - panState.startPointerY);
  }

  function finishCanvasPan(event: ReactPointerEvent<HTMLDivElement>) {
    const panState = panStateRef.current;
    if (!panState || panState.pointerId !== event.pointerId) {
      return;
    }

    panStateRef.current = null;
    setIsPanning(false);
  }

  function beginConnectionDrag(
    event: ReactPointerEvent<HTMLButtonElement>,
    node: Workflow["nodes"][number]
  ) {
    event.preventDefault();
    event.stopPropagation();
    const origin = centerPoint(node);
    setConnectionDragState({
      pointerId: event.pointerId,
      fromNodeId: node.id,
      currentX: origin.x,
      currentY: origin.y
    });
    event.currentTarget.setPointerCapture(event.pointerId);
    onNodeSelect?.(node.id);
  }

  function updateConnectionDrag(event: ReactPointerEvent<HTMLButtonElement>) {
    if (!connectionDragState || connectionDragState.pointerId !== event.pointerId) {
      return;
    }

    const point = canvasPointFromClient(event.clientX, event.clientY);
    setConnectionDragState((current) =>
      current
        ? {
            ...current,
            currentX: point.x,
            currentY: point.y
          }
        : current
    );
  }

  function finishConnectionDrag(event: ReactPointerEvent<HTMLButtonElement>) {
    if (!connectionDragState || connectionDragState.pointerId !== event.pointerId) {
      return;
    }

    const targetElement = document.elementFromPoint(event.clientX, event.clientY);
    const targetNodeId = targetElement instanceof Element
      ? targetElement.closest<HTMLElement>("[data-node-id]")?.dataset.nodeId ?? null
      : null;

    if (targetNodeId && targetNodeId !== connectionDragState.fromNodeId) {
      onNodeConnect?.(connectionDragState.fromNodeId, targetNodeId);
    }

    setConnectionDragState(null);
  }

  return (
    <div
      ref={previewRef}
      className={[
        "canvasPreview",
        isSpacePressed ? "canvasPreviewPanReady" : "",
        isPanning ? "canvasPreviewPanning" : ""
      ]
        .filter(Boolean)
        .join(" ")}
      onWheel={handleWheel}
      onPointerDown={beginCanvasPan}
      onPointerMove={updateCanvasPan}
      onPointerUp={finishCanvasPan}
      onPointerCancel={finishCanvasPan}
    >
      <div
        className="canvasViewportSizer"
        style={{ width: bounds.width * zoom, height: bounds.height * zoom }}
      >
        <div
          ref={viewportRef}
          className="canvasViewport"
          style={{
            width: bounds.width,
            height: bounds.height,
            transform: `scale(${zoom})`
          }}
          onPointerDown={(event) => {
            if (panStateRef.current?.pointerId === event.pointerId) {
              return;
            }

            const target = event.target;
            if (target instanceof Element && target.closest(".canvasNode")) {
              return;
            }

            onCanvasClick?.();
          }}
        >
          <svg className="canvasEdges" width={bounds.width} height={bounds.height} viewBox={`0 0 ${bounds.width} ${bounds.height}`}>
            {workflow.edges.map((edge) => {
              const fromNode = workflow.nodes.find((node) => node.id === edge.fromNodeID);
              const toNode = workflow.nodes.find((node) => node.id === edge.toNodeID);
              if (!fromNode || !toNode) {
                return null;
              }

              const from = centerPoint(fromNode);
              const to = centerPoint(toNode);
              const path = edgePath(from, to);
              const isSelected = selectedEdgeId === edge.id;
              const labelX = (from.x + to.x) / 2;
              const labelY = (from.y + to.y) / 2 - 10;

              return (
                <g key={edge.id}>
                  <path
                    d={path}
                    className="canvasEdgeHitArea"
                    onPointerDown={(event) => {
                      event.stopPropagation();
                      onEdgeSelect?.(edge.id);
                    }}
                  />
                  <path d={path} className={isSelected ? "canvasEdgePath canvasEdgePathSelected" : "canvasEdgePath"} />
                  <circle cx={to.x} cy={to.y} r="4.5" className={isSelected ? "canvasEdgeDot canvasEdgeDotSelected" : "canvasEdgeDot"} />
                  {(edge.label || edge.requiresApproval || edge.isBidirectional) ? (
                    <text x={labelX} y={labelY} className="canvasEdgeLabel" textAnchor="middle">
                      {edge.label || (edge.requiresApproval ? "approval" : edge.isBidirectional ? "two-way" : "")}
                    </text>
                  ) : null}
                </g>
              );
            })}

            {connectionDragState ? (
              <path
                d={edgePath(
                  centerPoint(
                    workflow.nodes.find((node) => node.id === connectionDragState.fromNodeId) ?? workflow.nodes[0]
                  ),
                  {
                    x: connectionDragState.currentX,
                    y: connectionDragState.currentY
                  }
                )}
                className="canvasEdgePath canvasEdgePathDraft"
              />
            ) : null}
          </svg>

          {workflow.nodes.map((node) => {
            const isSelected = selectedNodeId === node.id;
            const isFrom = selectedFromNodeId === node.id || connectionDragState?.fromNodeId === node.id;
            const isTo = selectedToNodeId === node.id;
            const assignedAgent = node.agentID
              ? agents.find((agent) => agent.id === node.agentID) ?? null
              : null;

            return (
              <article
                key={node.id}
                data-node-id={node.id}
                className={[
                  "canvasNode",
                  node.type === "start" ? "canvasNodeStart" : "",
                  isSelected ? "canvasNodeSelected" : "",
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
                <button
                  type="button"
                  className={isFrom ? "canvasConnectHandle canvasConnectHandleActive" : "canvasConnectHandle"}
                  onPointerDown={(event) => beginConnectionDrag(event, node)}
                  onPointerMove={updateConnectionDrag}
                  onPointerUp={finishConnectionDrag}
                  onPointerCancel={finishConnectionDrag}
                  aria-label={`Create connection from ${resolveNodeTitle(node, agents)}`}
                />
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
    </div>
  );
}
