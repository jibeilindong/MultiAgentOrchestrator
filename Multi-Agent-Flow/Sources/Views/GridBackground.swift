//
//  GridBackground.swift
//  Multi-Agent-Flow
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct GridBackground: View {
    var scale: CGFloat
    var offset: CGSize

    private let baseGridSize: CGFloat = 20
    private let minimumScreenStep: CGFloat = 18
    private let maximumScreenStep: CGFloat = 72
    private let majorLineMultiple: CGFloat = 5

    var body: some View {
        Canvas { context, size in
            let resolvedScale = max(scale, CanvasViewportConfiguration.zoomScaleRange.lowerBound)
            let worldStep = resolvedWorldStep(for: resolvedScale)
            let minorStep = worldStep * resolvedScale
            let majorStep = minorStep * majorLineMultiple
            let worldOrigin = CGPoint(
                x: size.width / 2 + offset.width,
                y: size.height / 2 + offset.height
            )

            drawGridLines(
                in: size,
                context: context,
                spacing: minorStep,
                origin: worldOrigin,
                color: Color.gray.opacity(0.2),
                lineWidth: 0.8
            )
            drawGridLines(
                in: size,
                context: context,
                spacing: majorStep,
                origin: worldOrigin,
                color: Color.gray.opacity(0.32),
                lineWidth: 1.0
            )

            if (0...size.width).contains(worldOrigin.x) {
                let yAxis = Path { path in
                    path.move(to: CGPoint(x: worldOrigin.x, y: 0))
                    path.addLine(to: CGPoint(x: worldOrigin.x, y: size.height))
                }
                context.stroke(yAxis, with: .color(Color.gray.opacity(0.48)), lineWidth: 1.1)
            }

            if (0...size.height).contains(worldOrigin.y) {
                let xAxis = Path { path in
                    path.move(to: CGPoint(x: 0, y: worldOrigin.y))
                    path.addLine(to: CGPoint(x: size.width, y: worldOrigin.y))
                }
                context.stroke(xAxis, with: .color(Color.gray.opacity(0.48)), lineWidth: 1.1)
            }
        }
    }

    private func resolvedWorldStep(for scale: CGFloat) -> CGFloat {
        var worldStep = baseGridSize

        while worldStep * scale < minimumScreenStep {
            worldStep *= 2
        }

        while worldStep > 2.5, worldStep * scale > maximumScreenStep {
            worldStep /= 2
        }

        return worldStep
    }

    private func drawGridLines(
        in size: CGSize,
        context: GraphicsContext,
        spacing: CGFloat,
        origin: CGPoint,
        color: Color,
        lineWidth: CGFloat
    ) {
        guard spacing > 0.5 else { return }

        var vertical = positiveRemainder(origin.x, spacing)
        while vertical > 0 {
            vertical -= spacing
        }

        while vertical <= size.width {
            let path = Path { path in
                path.move(to: CGPoint(x: vertical, y: 0))
                path.addLine(to: CGPoint(x: vertical, y: size.height))
            }
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
            vertical += spacing
        }

        var horizontal = positiveRemainder(origin.y, spacing)
        while horizontal > 0 {
            horizontal -= spacing
        }

        while horizontal <= size.height {
            let path = Path { path in
                path.move(to: CGPoint(x: 0, y: horizontal))
                path.addLine(to: CGPoint(x: size.width, y: horizontal))
            }
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
            horizontal += spacing
        }
    }

    private func positiveRemainder(_ value: CGFloat, _ divisor: CGFloat) -> CGFloat {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder >= 0 ? remainder : remainder + divisor
    }
}
