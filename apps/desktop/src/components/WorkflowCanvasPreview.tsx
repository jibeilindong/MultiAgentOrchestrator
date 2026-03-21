import type { Agent, Workflow } from "@multi-agent-flow/domain";
import {
  useEffect,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
  type WheelEvent as ReactWheelEvent
} from "react";
import { buildEdgeLayouts, draftEdgePath } from "./workflowCanvasRouting";

interface WorkflowCanvasPreviewProps {
  workflow: Workflow;
  agents: Agent[];
  zoom?: number;
  selectedNodeId?: string;
  selectedNodeIds?: string[];
  selectedEdgeId?: string;
  selectedFromNodeId?: string;
  selectedToNodeId?: string;
  onNodeConnect?: (fromNodeId: string, toNodeId: string) => void;
  onNodeSelect?: (nodeId: string, mode?: "replace" | "toggle") => void;
  onEdgeSelect?: (edgeId: string) => void;
  onSelectionBox?: (nodeIds: string[], mode?: "replace" | "add") => void;
  onWheelZoom?: (deltaY: number) => void;
  onNodePositionChange?: (nodeId: string, x: number, y: number) => void;
  onNodePositionCommit?: (nodeId: string, x: number, y: number) => void;
  onNodesPositionChange?: (updates: Array<{ nodeId: string; x: number; y: number }>) => void;
  onNodesPositionCommit?: (updates: Array<{ nodeId: string; x: number; y: number }>) => void;
  onNodeClick?: (nodeId: string) => void;
  onCanvasClick?: () => void;
}

const NODE_WIDTH = 188;
const NODE_HEIGHT = 92;
const CANVAS_PADDING = 80;
const SNAP_TOLERANCE = 10;

interface GuideLine {
  orientation: "vertical" | "horizontal";
  position: number;
}

interface CanvasPoint {
  x: number;
  y: number;
}

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
  zoom = 1,
  selectedNodeId,
  selectedNodeIds,
  selectedEdgeId,
  selectedFromNodeId,
  selectedToNodeId,
  onNodeConnect,
  onNodeSelect,
  onEdgeSelect,
  onSelectionBox,
  onWheelZoom,
  onNodePositionChange,
  onNodePositionCommit,
  onNodesPositionChange,
  onNodesPositionCommit,
  onNodeClick,
  onCanvasClick
}: WorkflowCanvasPreviewProps) {
  const bounds = getCanvasBounds(workflow);
  const edgeLayouts = buildEdgeLayouts(workflow);
  const edgeLayoutById = new Map(edgeLayouts.map((layout) => [layout.edgeId, layout]));
  const previewRef = useRef<HTMLDivElement | null>(null);
  const viewportRef = useRef<HTMLDivElement | null>(null);
  const dragStateRef = useRef<{
    nodeIds: string[];
    pointerId: number;
    startPointerX: number;
    startPointerY: number;
    startPositions: Record<string, { x: number; y: number }>;
    didMove: boolean;
    suppressClick: boolean;
  } | null>(null);
  const panStateRef = useRef<{
    pointerId: number;
    startPointerX: number;
    startPointerY: number;
    startScrollLeft: number;
    startScrollTop: number;
  } | null>(null);
  const [isSpacePressed, setIsSpacePressed] = useState(false);
  const [isAltPressed, setIsAltPressed] = useState(false);
  const [isPanning, setIsPanning] = useState(false);
  const [connectionDragState, setConnectionDragState] = useState<{
    pointerId: number;
    fromNodeId: string;
    currentX: number;
    currentY: number;
  } | null>(null);
  const [selectionBoxState, setSelectionBoxState] = useState<{
    pointerId: number;
    startX: number;
    startY: number;
    currentX: number;
    currentY: number;
    mode: "replace" | "add";
  } | null>(null);
  const [snapGuides, setSnapGuides] = useState<GuideLine[]>([]);

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (event.code === "Space") {
        setIsSpacePressed(true);
      }
      if (event.altKey) {
        setIsAltPressed(true);
      }
    }

    function handleKeyUp(event: KeyboardEvent) {
      if (event.code === "Space") {
        setIsSpacePressed(false);
      }
      if (!event.altKey) {
        setIsAltPressed(false);
      }
    }

    function clearPanKeys() {
      setIsSpacePressed(false);
      setIsAltPressed(false);
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

  function applyDragSnapping(
    rawUpdates: Array<{ nodeId: string; x: number; y: number }>,
    draggedNodeIds: string[]
  ) {
    if (rawUpdates.length === 0 || isAltPressed) {
      return { updates: rawUpdates, guides: [] as GuideLine[] };
    }

    const draggedNodeIdSet = new Set(draggedNodeIds);
    const draggedRects = rawUpdates.map((update) => ({
      left: update.x,
      centerX: update.x + NODE_WIDTH / 2,
      right: update.x + NODE_WIDTH,
      top: update.y,
      centerY: update.y + NODE_HEIGHT / 2,
      bottom: update.y + NODE_HEIGHT
    }));

    const groupBounds = {
      left: Math.min(...draggedRects.map((rect) => rect.left)),
      centerX: (Math.min(...draggedRects.map((rect) => rect.left)) + Math.max(...draggedRects.map((rect) => rect.right))) / 2,
      right: Math.max(...draggedRects.map((rect) => rect.right)),
      top: Math.min(...draggedRects.map((rect) => rect.top)),
      centerY: (Math.min(...draggedRects.map((rect) => rect.top)) + Math.max(...draggedRects.map((rect) => rect.bottom))) / 2,
      bottom: Math.max(...draggedRects.map((rect) => rect.bottom))
    };

    const candidateTargets = workflow.nodes
      .filter((node) => !draggedNodeIdSet.has(node.id))
      .map((node) => ({
        x: [node.position.x, node.position.x + NODE_WIDTH / 2, node.position.x + NODE_WIDTH],
        y: [node.position.y, node.position.y + NODE_HEIGHT / 2, node.position.y + NODE_HEIGHT]
      }));

    let snapDeltaX = 0;
    let snapGuideX: number | null = null;
    let bestXDistance = SNAP_TOLERANCE + 1;
    for (const anchor of [groupBounds.left, groupBounds.centerX, groupBounds.right]) {
      for (const target of candidateTargets) {
        for (const targetX of target.x) {
          const distance = Math.abs(targetX - anchor);
          if (distance <= SNAP_TOLERANCE && distance < bestXDistance) {
            bestXDistance = distance;
            snapDeltaX = targetX - anchor;
            snapGuideX = targetX;
          }
        }
      }
    }

    let snapDeltaY = 0;
    let snapGuideY: number | null = null;
    let bestYDistance = SNAP_TOLERANCE + 1;
    for (const anchor of [groupBounds.top, groupBounds.centerY, groupBounds.bottom]) {
      for (const target of candidateTargets) {
        for (const targetY of target.y) {
          const distance = Math.abs(targetY - anchor);
          if (distance <= SNAP_TOLERANCE && distance < bestYDistance) {
            bestYDistance = distance;
            snapDeltaY = targetY - anchor;
            snapGuideY = targetY;
          }
        }
      }
    }

    const guides: GuideLine[] = [];
    if (snapGuideX !== null) {
      guides.push({ orientation: "vertical", position: snapGuideX });
    }
    if (snapGuideY !== null) {
      guides.push({ orientation: "horizontal", position: snapGuideY });
    }

    return {
      updates: rawUpdates.map((update) => ({
        ...update,
        x: update.x + snapDeltaX,
        y: update.y + snapDeltaY
      })),
      guides
    };
  }

  function handlePointerDown(
    event: ReactPointerEvent<HTMLElement>,
    node: Workflow["nodes"][number]
  ) {
    const selectionMode =
      event.shiftKey || event.metaKey || event.ctrlKey ? "toggle" : "replace";
    const isAlreadySelected = selectedNodeIds?.includes(node.id) ?? selectedNodeId === node.id;
    if (selectionMode === "toggle" || !isAlreadySelected) {
      onNodeSelect?.(node.id, selectionMode);
    }
    const activeNodeIds =
      selectionMode === "replace"
        ? [node.id]
        : selectedNodeIds?.includes(node.id)
          ? selectedNodeIds.filter((id) => id !== node.id)
          : [...(selectedNodeIds ?? []), node.id];
    const dragNodeIds =
      selectionMode === "replace"
        ? [node.id]
        : activeNodeIds.includes(node.id) && activeNodeIds.length > 0
          ? activeNodeIds
          : [node.id];

    dragStateRef.current = {
      nodeIds: dragNodeIds,
      pointerId: event.pointerId,
      startPointerX: event.clientX,
      startPointerY: event.clientY,
      startPositions: Object.fromEntries(
        workflow.nodes
          .filter((entry) => dragNodeIds.includes(entry.id))
          .map((entry) => [entry.id, { x: entry.position.x, y: entry.position.y }])
      ),
      didMove: false,
      suppressClick: selectionMode === "toggle" || dragNodeIds.length > 1
    };

    event.currentTarget.setPointerCapture(event.pointerId);
  }

  function handlePointerMove(event: ReactPointerEvent<HTMLElement>) {
    const dragState = dragStateRef.current;
    if (!dragState || dragState.pointerId !== event.pointerId) {
      return;
    }

    const deltaX = (event.clientX - dragState.startPointerX) / zoom;
    const deltaY = (event.clientY - dragState.startPointerY) / zoom;
    const distance = Math.hypot(event.clientX - dragState.startPointerX, event.clientY - dragState.startPointerY);
    if (distance >= 3) {
      dragState.didMove = true;
    }
    const rawUpdates = dragState.nodeIds.map((nodeId) => {
      const startPosition = dragState.startPositions[nodeId];
      return {
        nodeId,
        x: startPosition.x + deltaX,
        y: startPosition.y + deltaY
      };
    });
    const { updates, guides } = applyDragSnapping(rawUpdates, dragState.nodeIds);
    setSnapGuides(guides);

    if (updates.length > 1) {
      onNodesPositionChange?.(updates);
    } else if (updates[0]) {
      onNodePositionChange?.(updates[0].nodeId, updates[0].x, updates[0].y);
    }
  }

  function finishPointerDrag(event: ReactPointerEvent<HTMLElement>) {
    const dragState = dragStateRef.current;
    if (!dragState || dragState.pointerId !== event.pointerId) {
      return;
    }

    const deltaX = (event.clientX - dragState.startPointerX) / zoom;
    const deltaY = (event.clientY - dragState.startPointerY) / zoom;
    const shouldTriggerClick = !dragState.didMove;
    const rawUpdates = dragState.nodeIds.map((nodeId) => {
      const startPosition = dragState.startPositions[nodeId];
      return {
        nodeId,
        x: startPosition.x + deltaX,
        y: startPosition.y + deltaY
      };
    });
    const { updates } = applyDragSnapping(rawUpdates, dragState.nodeIds);

    dragStateRef.current = null;
    setSnapGuides([]);
    if (updates.length > 1) {
      onNodesPositionCommit?.(updates);
    } else if (updates[0]) {
      onNodePositionCommit?.(updates[0].nodeId, updates[0].x, updates[0].y);
    }
    if (shouldTriggerClick && !dragState.suppressClick) {
      onNodeClick?.(updates[0]?.nodeId ?? "");
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

  function beginSelectionBox(event: ReactPointerEvent<HTMLDivElement>) {
    const target = event.target;
    if (target instanceof Element && target.closest(".canvasNode, .canvasEdgeHitArea")) {
      return false;
    }

    if (isSpacePressed || event.button !== 0) {
      return false;
    }

    const point = canvasPointFromClient(event.clientX, event.clientY);
    setSelectionBoxState({
      pointerId: event.pointerId,
      startX: point.x,
      startY: point.y,
      currentX: point.x,
      currentY: point.y,
      mode: event.shiftKey || event.metaKey || event.ctrlKey ? "add" : "replace"
    });
    event.currentTarget.setPointerCapture(event.pointerId);
    return true;
  }

  function updateSelectionBox(event: ReactPointerEvent<HTMLDivElement>) {
    if (!selectionBoxState || selectionBoxState.pointerId !== event.pointerId) {
      return;
    }

    const point = canvasPointFromClient(event.clientX, event.clientY);
    setSelectionBoxState((current) =>
      current
        ? {
            ...current,
            currentX: point.x,
            currentY: point.y
          }
        : current
    );
  }

  function finishSelectionBox(event: ReactPointerEvent<HTMLDivElement>) {
    if (!selectionBoxState || selectionBoxState.pointerId !== event.pointerId) {
      return;
    }

    const minX = Math.min(selectionBoxState.startX, selectionBoxState.currentX);
    const maxX = Math.max(selectionBoxState.startX, selectionBoxState.currentX);
    const minY = Math.min(selectionBoxState.startY, selectionBoxState.currentY);
    const maxY = Math.max(selectionBoxState.startY, selectionBoxState.currentY);
    const hasArea = Math.abs(selectionBoxState.currentX - selectionBoxState.startX) > 4 &&
      Math.abs(selectionBoxState.currentY - selectionBoxState.startY) > 4;

    if (hasArea) {
      const matchedNodeIds = workflow.nodes
        .filter((node) => {
          const left = node.position.x;
          const right = node.position.x + NODE_WIDTH;
          const top = node.position.y;
          const bottom = node.position.y + NODE_HEIGHT;
          return right >= minX && left <= maxX && bottom >= minY && top <= maxY;
        })
        .map((node) => node.id);
      onSelectionBox?.(matchedNodeIds, selectionBoxState.mode);
    } else if (selectionBoxState.mode === "replace") {
      onCanvasClick?.();
    }

    setSelectionBoxState(null);
    setSnapGuides([]);
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
    setSnapGuides([]);
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
    onNodeSelect?.(node.id, "replace");
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
      onPointerDown={(event) => {
        if (beginCanvasPan(event)) {
          return;
        }
        void beginSelectionBox(event);
      }}
      onPointerMove={(event) => {
        updateCanvasPan(event);
        updateSelectionBox(event);
      }}
      onPointerUp={(event) => {
        finishCanvasPan(event);
        finishSelectionBox(event);
      }}
      onPointerCancel={(event) => {
        finishCanvasPan(event);
        finishSelectionBox(event);
      }}
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
            {snapGuides.map((guide) =>
              guide.orientation === "vertical" ? (
                <line
                  key={`vertical-${guide.position}`}
                  x1={guide.position}
                  x2={guide.position}
                  y1="0"
                  y2={bounds.height}
                  className="canvasGuideLine"
                />
              ) : (
                <line
                  key={`horizontal-${guide.position}`}
                  x1="0"
                  x2={bounds.width}
                  y1={guide.position}
                  y2={guide.position}
                  className="canvasGuideLine"
                />
              )
            )}

            {workflow.edges.map((edge) => {
              const layout = edgeLayoutById.get(edge.id);
              if (!layout) {
                return null;
              }

              const isSelected = selectedEdgeId === edge.id;

              return (
                <g key={edge.id}>
                  <path
                    d={layout.path}
                    className="canvasEdgeHitArea"
                    onPointerDown={(event) => {
                      event.stopPropagation();
                      onEdgeSelect?.(edge.id);
                    }}
                  />
                  <path d={layout.path} className={isSelected ? "canvasEdgePath canvasEdgePathSelected" : "canvasEdgePath"} />
                  {layout.bridges.map((bridge) => (
                    <g key={bridge.id}>
                      <path
                        d={`M ${bridge.eraseFrom.x} ${bridge.eraseFrom.y} L ${bridge.eraseTo.x} ${bridge.eraseTo.y}`}
                        className="canvasEdgeBridgeMask"
                      />
                      <path
                        d={`M ${bridge.arcFrom.x} ${bridge.arcFrom.y} Q ${bridge.control.x} ${bridge.control.y} ${bridge.arcTo.x} ${bridge.arcTo.y}`}
                        className={isSelected ? "canvasEdgePath canvasEdgePathSelected" : "canvasEdgePath"}
                      />
                    </g>
                  ))}
                  <circle
                    cx={layout.targetPoint.x}
                    cy={layout.targetPoint.y}
                    r="4.5"
                    className={isSelected ? "canvasEdgeDot canvasEdgeDotSelected" : "canvasEdgeDot"}
                  />
                  {layout.label ? (
                    <text
                      x={layout.labelPosition.x}
                      y={layout.labelPosition.y}
                      className="canvasEdgeLabel"
                      textAnchor="middle"
                    >
                      {layout.label}
                    </text>
                  ) : null}
                </g>
              );
            })}

            {connectionDragState ? (
              <path
                d={draftEdgePath(
                  workflow.nodes.find((node) => node.id === connectionDragState.fromNodeId) ?? workflow.nodes[0],
                  {
                    x: connectionDragState.currentX,
                    y: connectionDragState.currentY
                  }
                )}
                className="canvasEdgePath canvasEdgePathDraft"
              />
            ) : null}

            {selectionBoxState ? (
              <rect
                x={Math.min(selectionBoxState.startX, selectionBoxState.currentX)}
                y={Math.min(selectionBoxState.startY, selectionBoxState.currentY)}
                width={Math.abs(selectionBoxState.currentX - selectionBoxState.startX)}
                height={Math.abs(selectionBoxState.currentY - selectionBoxState.startY)}
                className="canvasSelectionBox"
                rx="12"
              />
            ) : null}
          </svg>

          {workflow.nodes.map((node) => {
            const isSelected = selectedNodeIds?.includes(node.id) ?? selectedNodeId === node.id;
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
