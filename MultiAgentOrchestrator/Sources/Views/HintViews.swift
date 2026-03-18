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
                    Text(LocalizedString.canvasControls)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(LocalizedString.dragToMoveCanvas)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(LocalizedString.pinchToZoom)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(LocalizedString.doubleClickToConnect)
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
