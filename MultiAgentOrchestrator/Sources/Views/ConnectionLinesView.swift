//
//  ConnectionLinesView.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct ConnectionLinesView: View {
    let currentWorkflow: Workflow?
    let scale: CGFloat
    let offset: CGSize
    
    var body: some View {
        ForEach(currentWorkflow?.edges ?? []) { edge in
            if let fromNode = currentWorkflow?.nodes.first(where: { $0.id == edge.fromNodeID }),
               let toNode = currentWorkflow?.nodes.first(where: { $0.id == edge.toNodeID }) {
                ConnectionLine(
                    from: adjustedPosition(fromNode.position),
                    to: adjustedPosition(toNode.position)
                )
                .stroke(Color.blue.opacity(0.6), lineWidth: 2)
            }
        }
    }
    
    private func adjustedPosition(_ position: CGPoint) -> CGPoint {
        return CGPoint(
            x: position.x * scale + offset.width + 200,
            y: position.y * scale + offset.height + 200
        )
    }
}
