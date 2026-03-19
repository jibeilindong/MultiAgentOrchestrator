//
//  PermissionsView.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct PermissionsView: View {
    @EnvironmentObject var appState: AppState
    @State private var agents: [Agent] = []
    @State private var permissionMatrix: [[Bool]] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizedString.agentPermissionsMatrix)
                .font(.title2)
                .padding(.horizontal)
            
            if agents.isEmpty {
                ContentUnavailableView("No Agents", systemImage: "person.slash", description: Text("Add some agents in the sidebar to configure permissions"))
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        // 表头
                        HStack(spacing: 0) {
                            Text(LocalizedString.fromTo)
                                .frame(width: 150, alignment: .leading)
                                .padding(.leading, 8)
                            
                            ForEach(agents) { agent in
                                Text(agent.name)
                                    .frame(width: 100, alignment: .center)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .font(.headline)
                        .padding(.vertical, 8)
                        .background(Color(.controlBackgroundColor))
                        
                        // 表格内容
                        ForEach(agents) { fromAgent in
                            HStack(spacing: 0) {
                                Text(fromAgent.name)
                                    .frame(width: 150, alignment: .leading)
                                    .lineLimit(1)
                                    .padding(.leading, 8)
                                
                                ForEach(agents) { toAgent in
                                    PermissionCell(
                                        fromAgent: fromAgent,
                                        toAgent: toAgent,
                                        isAllowed: isPermissionAllowed(from: fromAgent, to: toAgent)
                                    )
                                    .frame(width: 100, height: 40)
                                    .onTapGesture {
                                        togglePermission(from: fromAgent, to: toAgent)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            .background(Color(.windowBackgroundColor))
                        }
                    }
                }
                .border(Color.gray.opacity(0.3), width: 1)
                .padding(.horizontal)
            }
            
            Spacer()
            
            // 权限说明
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedString.legend)
                    .font(.headline)
                
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 12, height: 12)
                        Text(LocalizedString.allowed)
                    }
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                        Text(LocalizedString.denied)
                    }
                    
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.yellow)
                            .frame(width: 12, height: 12)
                        Text(LocalizedString.selfNA)
                    }
                }
                .font(.caption)
            }
            .padding()
        }
        .onAppear {
            loadAgents()
            initializeMatrix()
        }
        .onChange(of: appState.currentProject?.agents) { _, _ in
            loadAgents()
            initializeMatrix()
        }
    }
    
    private func loadAgents() {
        agents = appState.currentProject?.agents ?? []
    }
    
    private func initializeMatrix() {
        let count = agents.count
        if permissionMatrix.count != count {
            permissionMatrix = Array(repeating: Array(repeating: true, count: count), count: count)
        }
    }
    
    private func isPermissionAllowed(from: Agent, to: Agent) -> Bool? {
        guard let fromIndex = agents.firstIndex(where: { $0.id == from.id }),
              let toIndex = agents.firstIndex(where: { $0.id == to.id }) else {
            return nil
        }
        
        if fromIndex == toIndex {
            return nil  // 自身不需要权限设置
        }
        
        return permissionMatrix[fromIndex][toIndex]
    }
    
    private func togglePermission(from: Agent, to: Agent) {
        guard let fromIndex = agents.firstIndex(where: { $0.id == from.id }),
              let toIndex = agents.firstIndex(where: { $0.id == to.id }),
              fromIndex != toIndex else {
            return
        }
        
        permissionMatrix[fromIndex][toIndex].toggle()
    }
}

struct PermissionCell: View {
    let fromAgent: Agent
    let toAgent: Agent
    let isAllowed: Bool?
    
    var body: some View {
        Group {
            if fromAgent.id == toAgent.id {
                // 自身
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.yellow.opacity(0.3))
                    .overlay(
                        Text("N/A")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    )
            } else {
                // 权限单元格
                RoundedRectangle(cornerRadius: 4)
                    .fill(isAllowed == true ? Color.green.opacity(0.3) : Color.red.opacity(0.3))
                    .overlay(
                        Image(systemName: isAllowed == true ? "checkmark" : "xmark")
                            .font(.caption)
                            .foregroundColor(isAllowed == true ? .green : .red)
                    )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.gray.opacity(0.5), lineWidth: 1)
        )
    }
}
