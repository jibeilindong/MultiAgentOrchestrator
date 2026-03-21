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

interface NodeRect {
  left: number;
  right: number;
  top: number;
  bottom: number;
  centerX: number;
  centerY: number;
}

interface OrthogonalSegment {
  start: CanvasPoint;
  end: CanvasPoint;
  isHorizontal: boolean;
  isVertical: boolean;
}

interface BridgeOverlay {
  id: string;
  eraseFrom: CanvasPoint;
  eraseTo: CanvasPoint;
  arcFrom: CanvasPoint;
  control: CanvasPoint;
  arcTo: CanvasPoint;
}

interface RoutedEdgeLayout {
  edgeId: string;
  points: CanvasPoint[];
  path: string;
  bridges: BridgeOverlay[];
  label: string;
  labelPosition: CanvasPoint;
  targetPoint: CanvasPoint;
}

const EDGE_CLEARANCE = 16;
const EDGE_BRIDGE_RADIUS = 10;
const OBSTACLE_PADDING = 16;

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

function nodeRect(node: Workflow["nodes"][number]): NodeRect {
  return {
    left: node.position.x,
    right: node.position.x + NODE_WIDTH,
    top: node.position.y,
    bottom: node.position.y + NODE_HEIGHT,
    centerX: node.position.x + NODE_WIDTH / 2,
    centerY: node.position.y + NODE_HEIGHT / 2
  };
}

function pointKey(point: CanvasPoint) {
  return `${Math.round(point.x * 10)}:${Math.round(point.y * 10)}`;
}

function pointsPath(points: CanvasPoint[]) {
  if (points.length === 0) {
    return "";
  }
  const [first, ...rest] = points;
  return `M ${first.x} ${first.y}${rest.map((point) => ` L ${point.x} ${point.y}`).join("")}`;
}

function simplifyPoints(points: CanvasPoint[]) {
  if (points.length <= 2) {
    return points;
  }

  const simplified: CanvasPoint[] = [points[0]];
  for (const point of points.slice(1)) {
    while (simplified.length >= 2) {
      const a = simplified[simplified.length - 2];
      const b = simplified[simplified.length - 1];
      const sameX = Math.abs(a.x - b.x) < 0.5 && Math.abs(b.x - point.x) < 0.5;
      const sameY = Math.abs(a.y - b.y) < 0.5 && Math.abs(b.y - point.y) < 0.5;
      if (!sameX && !sameY) {
        break;
      }
      simplified.pop();
    }
    simplified.push(point);
  }

  return simplified;
}

function pathLength(points: CanvasPoint[]) {
  return points.slice(1).reduce((total, point, index) => {
    const previous = points[index];
    return total + Math.hypot(point.x - previous.x, point.y - previous.y);
  }, 0);
}

function segmentRect(start: CanvasPoint, end: CanvasPoint) {
  return {
    left: Math.min(start.x, end.x) - 1,
    right: Math.max(start.x, end.x) + 1,
    top: Math.min(start.y, end.y) - 1,
    bottom: Math.max(start.y, end.y) + 1
  };
}

function intersectsRect(segment: OrthogonalSegment, rect: NodeRect) {
  const segmentBounds = segmentRect(segment.start, segment.end);
  return !(
    segmentBounds.right < rect.left - OBSTACLE_PADDING ||
    segmentBounds.left > rect.right + OBSTACLE_PADDING ||
    segmentBounds.bottom < rect.top - OBSTACLE_PADDING ||
    segmentBounds.top > rect.bottom + OBSTACLE_PADDING
  );
}

function orthogonalSegments(points: CanvasPoint[]): OrthogonalSegment[] {
  return points.slice(1).flatMap((point, index) => {
    const start = points[index];
    const isHorizontal = Math.abs(start.y - point.y) < 0.5;
    const isVertical = Math.abs(start.x - point.x) < 0.5;
    if (!isHorizontal && !isVertical) {
      return [];
    }
    return [{ start, end: point, isHorizontal, isVertical }];
  });
}

function segmentCrosses(a: OrthogonalSegment, b: OrthogonalSegment) {
  if (a.isHorizontal === b.isHorizontal) {
    return false;
  }

  const horizontal = a.isHorizontal ? a : b;
  const vertical = a.isHorizontal ? b : a;
  const x = vertical.start.x;
  const y = horizontal.start.y;
  const horizontalMinX = Math.min(horizontal.start.x, horizontal.end.x) + 0.5;
  const horizontalMaxX = Math.max(horizontal.start.x, horizontal.end.x) - 0.5;
  const verticalMinY = Math.min(vertical.start.y, vertical.end.y) + 0.5;
  const verticalMaxY = Math.max(vertical.start.y, vertical.end.y) - 0.5;

  return x > horizontalMinX && x < horizontalMaxX && y > verticalMinY && y < verticalMaxY;
}

function routePath(start: CanvasPoint, end: CanvasPoint, obstacles: NodeRect[], existingPaths: CanvasPoint[][]) {
  const candidates: CanvasPoint[][] = [];
  const seen = new Set<string>();
  const xs = [
    (start.x + end.x) / 2,
    start.x - EDGE_CLEARANCE * 2,
    start.x + EDGE_CLEARANCE * 2,
    end.x - EDGE_CLEARANCE * 2,
    end.x + EDGE_CLEARANCE * 2,
    ...obstacles.flatMap((rect) => [rect.left - OBSTACLE_PADDING - EDGE_CLEARANCE, rect.right + OBSTACLE_PADDING + EDGE_CLEARANCE])
  ];
  const ys = [
    (start.y + end.y) / 2,
    start.y - EDGE_CLEARANCE * 2,
    start.y + EDGE_CLEARANCE * 2,
    end.y - EDGE_CLEARANCE * 2,
    end.y + EDGE_CLEARANCE * 2,
    ...obstacles.flatMap((rect) => [rect.top - OBSTACLE_PADDING - EDGE_CLEARANCE, rect.bottom + OBSTACLE_PADDING + EDGE_CLEARANCE])
  ];

  const append = (rawPoints: CanvasPoint[]) => {
    const path = simplifyPoints(rawPoints);
    const key = path.map(pointKey).join("|");
    if (!seen.has(key)) {
      seen.add(key);
      candidates.push(path);
    }
  };

  if (Math.abs(start.x - end.x) < 0.5 || Math.abs(start.y - end.y) < 0.5) {
    append([start, end]);
  }

  append([start, { x: end.x, y: start.y }, end]);
  append([start, { x: start.x, y: end.y }, end]);

  for (const x of xs) {
    append([start, { x, y: start.y }, { x, y: end.y }, end]);
  }
  for (const y of ys) {
    append([start, { x: start.x, y }, { x: end.x, y }, end]);
  }
  for (const x of xs) {
    for (const y of ys) {
      append([start, { x: start.x, y }, { x, y }, { x, y: end.y }, end]);
      append([start, { x, y: start.y }, { x, y }, { x: end.x, y }, end]);
    }
  }

  const isClear = (points: CanvasPoint[]) => {
    const segments = orthogonalSegments(points);
    return segments.every((segment) => obstacles.every((rect) => !intersectsRect(segment, rect)));
  };

  const candidateScores = candidates.map((points, index) => {
    const segments = orthogonalSegments(points);
    const crossings = existingPaths.reduce((total, existingPath) => {
      const existingSegments = orthogonalSegments(existingPath);
      return total + existingSegments.reduce((count, existingSegment) => (
        count + (segments.some((segment) => segmentCrosses(segment, existingSegment)) ? 1 : 0)
      ), 0);
    }, 0);

    return {
      points,
      index,
      clear: isClear(points),
      crossings,
      bends: Math.max(0, points.length - 2),
      length: pathLength(points)
    };
  });

  candidateScores.sort((a, b) => {
    if (a.clear !== b.clear) {
      return a.clear ? -1 : 1;
    }
    if (a.crossings !== b.crossings) {
      return a.crossings - b.crossings;
    }
    if (a.bends !== b.bends) {
      return a.bends - b.bends;
    }
    if (Math.abs(a.length - b.length) > 0.5) {
      return a.length - b.length;
    }
    return a.index - b.index;
  });

  return candidateScores[0]?.points ?? [start, end];
}

function labelForEdge(edge: Workflow["edges"][number]) {
  if (edge.label.trim()) {
    return edge.label.trim();
  }
  if (edge.requiresApproval) {
    return "approval";
  }
  if (edge.isBidirectional) {
    return "two-way";
  }
  return "";
}

function labelPosition(points: CanvasPoint[]) {
  if (points.length === 0) {
    return { x: 0, y: 0 };
  }

  const total = pathLength(points);
  const halfway = total / 2;
  let walked = 0;

  for (let index = 1; index < points.length; index += 1) {
    const from = points[index - 1];
    const to = points[index];
    const segmentLength = Math.hypot(to.x - from.x, to.y - from.y);
    if (walked + segmentLength >= halfway && segmentLength > 0) {
      const ratio = (halfway - walked) / segmentLength;
      return {
        x: from.x + (to.x - from.x) * ratio,
        y: from.y + (to.y - from.y) * ratio - 10
      };
    }
    walked += segmentLength;
  }

  return { x: points[0].x, y: points[0].y - 10 };
}

function buildBridgeOverlays(layouts: RoutedEdgeLayout[]) {
  const segmentRefs = layouts.flatMap((layout) =>
    orthogonalSegments(layout.points).map((segment, segmentIndex) => ({
      edgeId: layout.edgeId,
      segmentIndex,
      ...segment
    }))
  );

  const verticalSegments = segmentRefs.filter((segment) => segment.isVertical);
  const overlaysByEdgeId = new Map<string, BridgeOverlay[]>();

  for (const horizontalSegment of segmentRefs.filter((segment) => segment.isHorizontal)) {
    const intersections = verticalSegments
      .filter((verticalSegment) => verticalSegment.edgeId !== horizontalSegment.edgeId)
      .map((verticalSegment) => {
        const x = verticalSegment.start.x;
        const y = horizontalSegment.start.y;
        return segmentCrosses(horizontalSegment, verticalSegment) ? { x, y } : null;
      })
      .filter((point): point is CanvasPoint => point !== null)
      .sort((a, b) => a.x - b.x);

    const kept: CanvasPoint[] = [];
    for (const point of intersections) {
      const last = kept[kept.length - 1];
      if (last && Math.abs(last.x - point.x) < EDGE_BRIDGE_RADIUS * 2.4) {
        continue;
      }
      kept.push(point);
    }

    const minX = Math.min(horizontalSegment.start.x, horizontalSegment.end.x);
    const maxX = Math.max(horizontalSegment.start.x, horizontalSegment.end.x);
    const forward = horizontalSegment.end.x >= horizontalSegment.start.x;

    for (const point of kept) {
      const radius = Math.min(EDGE_BRIDGE_RADIUS, point.x - minX - 4, maxX - point.x - 4);
      if (radius < 5) {
        continue;
      }

      const left = { x: point.x - radius, y: point.y };
      const right = { x: point.x + radius, y: point.y };
      const bridge: BridgeOverlay = {
        id: `${horizontalSegment.edgeId}-${horizontalSegment.segmentIndex}-${Math.round(point.x * 10)}-${Math.round(point.y * 10)}`,
        eraseFrom: left,
        eraseTo: right,
        arcFrom: forward ? left : right,
        control: { x: point.x, y: point.y - radius * 1.8 },
        arcTo: forward ? right : left
      };

      overlaysByEdgeId.set(horizontalSegment.edgeId, [...(overlaysByEdgeId.get(horizontalSegment.edgeId) ?? []), bridge]);
    }
  }

  return layouts.map((layout) => ({
    ...layout,
    bridges: overlaysByEdgeId.get(layout.edgeId) ?? []
  }));
}

function buildEdgeLayouts(workflow: Workflow) {
  const nodesById = new Map(workflow.nodes.map((node) => [node.id, node]));
  const routed: RoutedEdgeLayout[] = [];
  const existingPaths: CanvasPoint[][] = [];

  for (const edge of workflow.edges) {
    const fromNode = nodesById.get(edge.fromNodeID);
    const toNode = nodesById.get(edge.toNodeID);
    if (!fromNode || !toNode) {
      continue;
    }

    const fromRect = nodeRect(fromNode);
    const toRect = nodeRect(toNode);
    const dx = toRect.centerX - fromRect.centerX;
    const dy = toRect.centerY - fromRect.centerY;
    const start = Math.abs(dx) >= Math.abs(dy)
      ? { x: dx >= 0 ? fromRect.right + EDGE_CLEARANCE : fromRect.left - EDGE_CLEARANCE, y: fromRect.centerY }
      : { x: fromRect.centerX, y: dy >= 0 ? fromRect.bottom + EDGE_CLEARANCE : fromRect.top - EDGE_CLEARANCE };
    const end = Math.abs(dx) >= Math.abs(dy)
      ? { x: dx >= 0 ? toRect.left - EDGE_CLEARANCE : toRect.right + EDGE_CLEARANCE, y: toRect.centerY }
      : { x: toRect.centerX, y: dy >= 0 ? toRect.top - EDGE_CLEARANCE : toRect.bottom + EDGE_CLEARANCE };
    const obstacles = workflow.nodes
      .filter((node) => node.id !== fromNode.id && node.id !== toNode.id)
      .map(nodeRect);
    const points = routePath(start, end, obstacles, existingPaths);
    existingPaths.push(points);

    routed.push({
      edgeId: edge.id,
      points,
      path: pointsPath(points),
      bridges: [],
      label: labelForEdge(edge),
      labelPosition: labelPosition(points),
      targetPoint: end
    });
  }

  return buildBridgeOverlays(routed);
}

function draftEdgePath(node: Workflow["nodes"][number] | undefined, current: CanvasPoint) {
  if (!node) {
    return pointsPath([current]);
  }

  const origin = centerPoint(node);
  const dx = current.x - origin.x;
  const dy = current.y - origin.y;
  const start = Math.abs(dx) >= Math.abs(dy)
    ? { x: dx >= 0 ? node.position.x + NODE_WIDTH + EDGE_CLEARANCE : node.position.x - EDGE_CLEARANCE, y: origin.y }
    : { x: origin.x, y: dy >= 0 ? node.position.y + NODE_HEIGHT + EDGE_CLEARANCE : node.position.y - EDGE_CLEARANCE };

  return pointsPath(routePath(start, current, [], []));
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
