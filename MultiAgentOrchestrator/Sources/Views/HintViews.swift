//
//  HintViews.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct HintViews: View {
    let geometry: GeometryProxy
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Text("Canvas Controls")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("• Drag to move canvas")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("• Pinch to zoom")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("• Double-click to connect")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.black.opacity(0.05))
                .cornerRadius(8)
                .padding()
            }
            Spacer()
        }
    }
}
