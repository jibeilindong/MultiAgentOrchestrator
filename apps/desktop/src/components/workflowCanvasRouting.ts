import type { Workflow } from "@multi-agent-flow/domain";

const NODE_WIDTH = 188;
const NODE_HEIGHT = 92;
const EDGE_CLEARANCE = 16;
const EDGE_BRIDGE_RADIUS = 10;
const OBSTACLE_PADDING = 16;

export interface CanvasPoint {
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

export interface BridgeOverlay {
  id: string;
  eraseFrom: CanvasPoint;
  eraseTo: CanvasPoint;
  arcFrom: CanvasPoint;
  control: CanvasPoint;
  arcTo: CanvasPoint;
}

export interface RoutedEdgeLayout {
  edgeId: string;
  points: CanvasPoint[];
  path: string;
  bridges: BridgeOverlay[];
  label: string;
  labelPosition: CanvasPoint;
  targetPoint: CanvasPoint;
}

type EdgeAnchorSide = "left" | "right" | "top" | "bottom";

interface PreparedEdgeRoute {
  edge: Workflow["edges"][number];
  fromNode: Workflow["nodes"][number];
  toNode: Workflow["nodes"][number];
  fromRect: NodeRect;
  toRect: NodeRect;
  start: CanvasPoint;
  end: CanvasPoint;
  outgoingSide: EdgeAnchorSide;
  incomingSide: EdgeAnchorSide;
}

interface FanoutBundle {
  side: EdgeAnchorSide;
  turnX?: number;
  turnY?: number;
  targetAnchorXById?: Map<string, number>;
  targetAnchorYById?: Map<string, number>;
}

interface FaninBundle {
  side: EdgeAnchorSide;
  mergeX?: number;
  mergeY?: number;
  trunkX?: number;
  trunkY?: number;
}

function clamp(value: number, min: number, max: number) {
  return Math.min(Math.max(value, min), max);
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

function preferredOutgoingSide(fromRect: NodeRect, toRect: NodeRect): EdgeAnchorSide {
  const dx = toRect.centerX - fromRect.centerX;
  const dy = toRect.centerY - fromRect.centerY;
  const verticalThreshold = Math.max(32, NODE_HEIGHT * 0.55);

  if (dy >= verticalThreshold) {
    return "bottom";
  }
  if (dy <= -verticalThreshold) {
    return "top";
  }
  if (Math.abs(dx) > Math.abs(dy) * 1.2) {
    return dx >= 0 ? "right" : "left";
  }
  return dy >= 0 ? "bottom" : "top";
}

function preferredIncomingSide(fromRect: NodeRect, toRect: NodeRect): EdgeAnchorSide {
  const dx = fromRect.centerX - toRect.centerX;
  const dy = fromRect.centerY - toRect.centerY;
  const verticalThreshold = Math.max(32, NODE_HEIGHT * 0.55);

  if (dy <= -verticalThreshold) {
    return "top";
  }
  if (dy >= verticalThreshold) {
    return "bottom";
  }
  if (Math.abs(dx) > Math.abs(dy) * 1.2) {
    return dx >= 0 ? "right" : "left";
  }
  return dy >= 0 ? "bottom" : "top";
}

function anchorPoint(rect: NodeRect, side: EdgeAnchorSide) {
  switch (side) {
    case "left":
      return { x: rect.left - EDGE_CLEARANCE, y: rect.centerY };
    case "right":
      return { x: rect.right + EDGE_CLEARANCE, y: rect.centerY };
    case "top":
      return { x: rect.centerX, y: rect.top - EDGE_CLEARANCE };
    case "bottom":
      return { x: rect.centerX, y: rect.bottom + EDGE_CLEARANCE };
  }
}

function routeIsClear(points: CanvasPoint[], obstacles: NodeRect[]) {
  const segments = orthogonalSegments(points);
  return segments.every((segment) => obstacles.every((rect) => !intersectsRect(segment, rect)));
}

function clampedTargetAnchorX(rect: NodeRect, preferredX: number) {
  const inset = Math.min(18, Math.max(10, NODE_WIDTH * 0.18));
  return clamp(preferredX, rect.left + inset, rect.right - inset);
}

function clampedTargetAnchorY(rect: NodeRect, preferredY: number) {
  const inset = Math.min(18, Math.max(10, NODE_HEIGHT * 0.18));
  return clamp(preferredY, rect.top + inset, rect.bottom - inset);
}

function buildPreparedRoutes(workflow: Workflow) {
  const nodesById = new Map(workflow.nodes.map((node) => [node.id, node]));

  return workflow.edges.flatMap((edge) => {
    const fromNode = nodesById.get(edge.fromNodeID);
    const toNode = nodesById.get(edge.toNodeID);
    if (!fromNode || !toNode) {
      return [];
    }

    const fromRect = nodeRect(fromNode);
    const toRect = nodeRect(toNode);
    const outgoingSide = preferredOutgoingSide(fromRect, toRect);
    const incomingSide = preferredIncomingSide(fromRect, toRect);

    return [{
      edge,
      fromNode,
      toNode,
      fromRect,
      toRect,
      start: anchorPoint(fromRect, outgoingSide),
      end: anchorPoint(toRect, incomingSide),
      outgoingSide,
      incomingSide
    }];
  });
}

function buildFanoutBundles(routes: PreparedEdgeRoute[]) {
  const bundles = new Map<string, FanoutBundle>();
  const grouped = new Map<string, PreparedEdgeRoute[]>();

  for (const route of routes) {
    const key = `${route.edge.fromNodeID}:${route.outgoingSide}`;
    const current = grouped.get(key) ?? [];
    current.push(route);
    grouped.set(key, current);
  }

  for (const [bundleKey, group] of grouped) {
    if (group.length < 2) {
      continue;
    }

    const side = group[0].outgoingSide;
    const sourceRect = group[0].fromRect;

    if (side === "bottom") {
      const downward = group.filter((route) => route.incomingSide === "top");
      if (downward.length < 2) {
        continue;
      }

      const sourceBottom = sourceRect.bottom + EDGE_CLEARANCE;
      const nearestTargetTop = Math.min(...downward.map((route) => route.toRect.top - EDGE_CLEARANCE));
      const verticalGap = nearestTargetTop - sourceBottom;
      if (verticalGap < 48) {
        continue;
      }

      const turnY = Math.min(sourceBottom + Math.max(28, Math.min(76, verticalGap * 0.4)), nearestTargetTop - 20);
      const sortedTargets = [...downward].sort((a, b) => a.toRect.centerX - b.toRect.centerX);
      const center = (sortedTargets.length - 1) / 2;
      const targetAnchorXById = new Map<string, number>();

      for (const [index, route] of sortedTargets.entries()) {
        const slotOffset = (index - center) * Math.min(38, Math.max(22, NODE_WIDTH * 0.22));
        targetAnchorXById.set(route.edge.toNodeID, clampedTargetAnchorX(route.toRect, sourceRect.centerX + slotOffset));
      }

      bundles.set(bundleKey, { side, turnY, targetAnchorXById });
      continue;
    }

    if (side === "top") {
      const upward = group.filter((route) => route.incomingSide === "bottom");
      if (upward.length < 2) {
        continue;
      }

      const sourceTop = sourceRect.top - EDGE_CLEARANCE;
      const nearestTargetBottom = Math.max(...upward.map((route) => route.toRect.bottom + EDGE_CLEARANCE));
      const verticalGap = sourceTop - nearestTargetBottom;
      if (verticalGap < 48) {
        continue;
      }

      const turnY = Math.max(sourceTop - Math.max(28, Math.min(76, verticalGap * 0.4)), nearestTargetBottom + 20);
      const sortedTargets = [...upward].sort((a, b) => a.toRect.centerX - b.toRect.centerX);
      const center = (sortedTargets.length - 1) / 2;
      const targetAnchorXById = new Map<string, number>();

      for (const [index, route] of sortedTargets.entries()) {
        const slotOffset = (index - center) * Math.min(38, Math.max(22, NODE_WIDTH * 0.22));
        targetAnchorXById.set(route.edge.toNodeID, clampedTargetAnchorX(route.toRect, sourceRect.centerX + slotOffset));
      }

      bundles.set(bundleKey, { side, turnY, targetAnchorXById });
      continue;
    }

    if (side === "right") {
      const rightward = group.filter((route) => route.incomingSide === "left");
      if (rightward.length < 2) {
        continue;
      }

      const sourceRight = sourceRect.right + EDGE_CLEARANCE;
      const nearestTargetLeft = Math.min(...rightward.map((route) => route.toRect.left - EDGE_CLEARANCE));
      const horizontalGap = nearestTargetLeft - sourceRight;
      if (horizontalGap < 48) {
        continue;
      }

      const turnX = Math.min(sourceRight + Math.max(28, Math.min(76, horizontalGap * 0.4)), nearestTargetLeft - 20);
      const sortedTargets = [...rightward].sort((a, b) => a.toRect.centerY - b.toRect.centerY);
      const center = (sortedTargets.length - 1) / 2;
      const targetAnchorYById = new Map<string, number>();

      for (const [index, route] of sortedTargets.entries()) {
        const slotOffset = (index - center) * Math.min(32, Math.max(18, NODE_HEIGHT * 0.24));
        targetAnchorYById.set(route.edge.toNodeID, clampedTargetAnchorY(route.toRect, sourceRect.centerY + slotOffset));
      }

      bundles.set(bundleKey, { side, turnX, targetAnchorYById });
      continue;
    }

    if (side === "left") {
      const leftward = group.filter((route) => route.incomingSide === "right");
      if (leftward.length < 2) {
        continue;
      }

      const sourceLeft = sourceRect.left - EDGE_CLEARANCE;
      const nearestTargetRight = Math.max(...leftward.map((route) => route.toRect.right + EDGE_CLEARANCE));
      const horizontalGap = sourceLeft - nearestTargetRight;
      if (horizontalGap < 48) {
        continue;
      }

      const turnX = Math.max(sourceLeft - Math.max(28, Math.min(76, horizontalGap * 0.4)), nearestTargetRight + 20);
      const sortedTargets = [...leftward].sort((a, b) => a.toRect.centerY - b.toRect.centerY);
      const center = (sortedTargets.length - 1) / 2;
      const targetAnchorYById = new Map<string, number>();

      for (const [index, route] of sortedTargets.entries()) {
        const slotOffset = (index - center) * Math.min(32, Math.max(18, NODE_HEIGHT * 0.24));
        targetAnchorYById.set(route.edge.toNodeID, clampedTargetAnchorY(route.toRect, sourceRect.centerY + slotOffset));
      }

      bundles.set(bundleKey, { side, turnX, targetAnchorYById });
    }
  }

  return bundles;
}

function buildFaninBundles(routes: PreparedEdgeRoute[]) {
  const bundles = new Map<string, FaninBundle>();
  const grouped = new Map<string, PreparedEdgeRoute[]>();

  for (const route of routes) {
    const key = `${route.edge.toNodeID}:${route.incomingSide}`;
    const current = grouped.get(key) ?? [];
    current.push(route);
    grouped.set(key, current);
  }

  for (const [key, group] of grouped) {
    if (group.length < 2) {
      continue;
    }

    const targetRect = group[0].toRect;
    const side = group[0].incomingSide;

    if (side === "top") {
      const sourcesAbove = group.filter((route) => route.fromRect.centerY < targetRect.centerY - 18);
      if (sourcesAbove.length < 2) {
        continue;
      }

      const targetTop = targetRect.top - EDGE_CLEARANCE;
      const nearestSourceBottom = Math.max(...sourcesAbove.map((route) => route.fromRect.bottom + EDGE_CLEARANCE));
      const verticalGap = targetTop - nearestSourceBottom;
      if (verticalGap < 36) {
        continue;
      }

      const mergeY = Math.max(nearestSourceBottom + 18, targetTop - Math.max(18, Math.min(48, verticalGap * 0.28)));
      bundles.set(key, { side, mergeY, trunkX: targetRect.centerX });
      continue;
    }

    if (side === "bottom") {
      const sourcesBelow = group.filter((route) => route.fromRect.centerY > targetRect.centerY + 18);
      if (sourcesBelow.length < 2) {
        continue;
      }

      const targetBottom = targetRect.bottom + EDGE_CLEARANCE;
      const nearestSourceTop = Math.min(...sourcesBelow.map((route) => route.fromRect.top - EDGE_CLEARANCE));
      const verticalGap = nearestSourceTop - targetBottom;
      if (verticalGap < 36) {
        continue;
      }

      const mergeY = Math.min(targetBottom + Math.max(18, Math.min(48, verticalGap * 0.28)), nearestSourceTop - 18);
      bundles.set(key, { side, mergeY, trunkX: targetRect.centerX });
      continue;
    }

    if (side === "left") {
      const sourcesLeft = group.filter((route) => route.fromRect.centerX < targetRect.centerX - 18);
      if (sourcesLeft.length < 2) {
        continue;
      }

      const targetLeft = targetRect.left - EDGE_CLEARANCE;
      const nearestSourceRight = Math.max(...sourcesLeft.map((route) => route.fromRect.right + EDGE_CLEARANCE));
      const horizontalGap = targetLeft - nearestSourceRight;
      if (horizontalGap < 36) {
        continue;
      }

      const mergeX = Math.max(targetLeft - Math.max(18, Math.min(48, horizontalGap * 0.28)), nearestSourceRight + 18);
      bundles.set(key, { side, mergeX, trunkY: targetRect.centerY });
      continue;
    }

    if (side === "right") {
      const sourcesRight = group.filter((route) => route.fromRect.centerX > targetRect.centerX + 18);
      if (sourcesRight.length < 2) {
        continue;
      }

      const targetRight = targetRect.right + EDGE_CLEARANCE;
      const nearestSourceLeft = Math.min(...sourcesRight.map((route) => route.fromRect.left - EDGE_CLEARANCE));
      const horizontalGap = nearestSourceLeft - targetRight;
      if (horizontalGap < 36) {
        continue;
      }

      const mergeX = Math.min(targetRight + Math.max(18, Math.min(48, horizontalGap * 0.28)), nearestSourceLeft - 18);
      bundles.set(key, { side, mergeX, trunkY: targetRect.centerY });
    }
  }

  return bundles;
}

function fanoutPath(route: PreparedEdgeRoute, bundle: FanoutBundle) {
  if (bundle.side === "bottom" || bundle.side === "top") {
    const targetAnchorX = bundle.targetAnchorXById?.get(route.edge.toNodeID) ?? route.toRect.centerX;
    const turnY = bundle.turnY ?? route.start.y;
    return simplifyPoints([
      route.start,
      { x: route.fromRect.centerX, y: turnY },
      { x: targetAnchorX, y: turnY },
      { x: targetAnchorX, y: route.end.y },
      route.end
    ]);
  }

  const targetAnchorY = bundle.targetAnchorYById?.get(route.edge.toNodeID) ?? route.toRect.centerY;
  const turnX = bundle.turnX ?? route.start.x;
  return simplifyPoints([
    route.start,
    { x: turnX, y: route.fromRect.centerY },
    { x: turnX, y: targetAnchorY },
    { x: route.end.x, y: targetAnchorY },
    route.end
  ]);
}

function faninPath(route: PreparedEdgeRoute, bundle: FaninBundle) {
  if (bundle.side === "top" || bundle.side === "bottom") {
    const mergeY = bundle.mergeY ?? route.end.y;
    const trunkX = bundle.trunkX ?? route.toRect.centerX;
    return simplifyPoints([
      route.start,
      { x: route.start.x, y: mergeY },
      { x: trunkX, y: mergeY },
      { x: trunkX, y: route.end.y },
      route.end
    ]);
  }

  const mergeX = bundle.mergeX ?? route.end.x;
  const trunkY = bundle.trunkY ?? route.toRect.centerY;
  return simplifyPoints([
    route.start,
    { x: mergeX, y: route.start.y },
    { x: mergeX, y: trunkY },
    { x: route.end.x, y: trunkY },
    route.end
  ]);
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
      clear: routeIsClear(points, obstacles),
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

function pathCrossingCount(points: CanvasPoint[], existingPaths: CanvasPoint[][]) {
  const segments = orthogonalSegments(points);
  return existingPaths.reduce((total, existingPath) => {
    const existingSegments = orthogonalSegments(existingPath);
    return total + (existingSegments.some((existingSegment) => segments.some((segment) => segmentCrosses(segment, existingSegment))) ? 1 : 0);
  }, 0);
}

function comparePaths(a: CanvasPoint[], b: CanvasPoint[], existingPaths: CanvasPoint[][]) {
  const crossingsA = pathCrossingCount(a, existingPaths);
  const crossingsB = pathCrossingCount(b, existingPaths);
  if (crossingsA !== crossingsB) {
    return crossingsA - crossingsB;
  }

  const bendsA = Math.max(0, a.length - 2);
  const bendsB = Math.max(0, b.length - 2);
  if (bendsA !== bendsB) {
    return bendsA - bendsB;
  }

  const lengthDelta = pathLength(a) - pathLength(b);
  if (Math.abs(lengthDelta) > 0.5) {
    return lengthDelta;
  }

  return a.length - b.length;
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

export function buildBridgeOverlays(layouts: RoutedEdgeLayout[]) {
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

export function buildEdgeLayouts(workflow: Workflow) {
  const preparedRoutes = buildPreparedRoutes(workflow);
  const fanoutBundles = buildFanoutBundles(preparedRoutes);
  const faninBundles = buildFaninBundles(preparedRoutes);
  const routed: RoutedEdgeLayout[] = [];
  const existingPaths: CanvasPoint[][] = [];

  const sortedRoutes = [...preparedRoutes].sort((a, b) => {
    if (Math.abs(a.toRect.centerY - b.toRect.centerY) > 0.5) {
      return a.toRect.centerY - b.toRect.centerY;
    }
    if (Math.abs(a.toRect.centerX - b.toRect.centerX) > 0.5) {
      return a.toRect.centerX - b.toRect.centerX;
    }
    if (Math.abs(a.fromRect.centerY - b.fromRect.centerY) > 0.5) {
      return a.fromRect.centerY - b.fromRect.centerY;
    }
    return a.fromRect.centerX - b.fromRect.centerX;
  });

  for (const route of sortedRoutes) {
    const obstacles = workflow.nodes
      .filter((node) => node.id !== route.fromNode.id && node.id !== route.toNode.id)
      .map(nodeRect);
    const candidatePaths: CanvasPoint[][] = [];
    const fanoutBundle = fanoutBundles.get(`${route.edge.fromNodeID}:${route.outgoingSide}`);
    if (fanoutBundle) {
      const fanoutCandidate = fanoutPath(route, fanoutBundle);
      if (routeIsClear(fanoutCandidate, obstacles)) {
        candidatePaths.push(fanoutCandidate);
      }
    }

    const faninBundle = faninBundles.get(`${route.edge.toNodeID}:${route.incomingSide}`);
    if (faninBundle) {
      const faninCandidate = faninPath(route, faninBundle);
      if (routeIsClear(faninCandidate, obstacles)) {
        candidatePaths.push(faninCandidate);
      }
    }

    const fallback = routePath(route.start, route.end, obstacles, existingPaths);
    const resolvedPoints = [...candidatePaths, fallback].sort((a, b) => comparePaths(a, b, existingPaths))[0] ?? fallback;
    existingPaths.push(resolvedPoints);

    routed.push({
      edgeId: route.edge.id,
      points: resolvedPoints,
      path: pointsPath(resolvedPoints),
      bridges: [],
      label: labelForEdge(route.edge),
      labelPosition: labelPosition(resolvedPoints),
      targetPoint: route.end
    });
  }

  return buildBridgeOverlays(routed);
}

export function draftEdgePath(node: Workflow["nodes"][number] | undefined, current: CanvasPoint) {
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
