//
//  Untitled.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题
            Text(LocalizedString.navigation)
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor))
            
            Divider()
            
            // 内容列表
            List {
                Section("Agents") {
                    if let agents = appState.currentProject?.agents {
                        ForEach(agents) { agent in
                            AgentRow(agent: agent)
                        }
                    }
                }
                
                Section("Workflows") {
                    if let workflows = appState.currentProject?.workflows {
                        ForEach(workflows) { workflow in
                            Text(workflow.name)
                                .padding(.vertical, 4)
                        }
                    }
                }
                
                Section("Node Templates") {
                    NodeTemplateRow(type: .start, name: "Start Node", icon: "play.circle.fill", color: .green)
                    NodeTemplateRow(type: .end, name: "End Node", icon: "stop.circle.fill", color: .red)
                }
            }
            .listStyle(SidebarListStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func addNewAgent() {
        let newAgent = Agent(name: "New Agent \(Int.random(in: 1...100))")
        appState.currentProject?.agents.append(newAgent)
    }
    
    private func addNewWorkflow() {
        let newWorkflow = Workflow(name: "Workflow \(Int.random(in: 1...100))")
        appState.currentProject?.workflows.append(newWorkflow)
    }
}

struct AgentRow: View {
    let agent: Agent
    
    var body: some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .foregroundColor(.blue)
            VStack(alignment: .leading) {
                Text(agent.name)
                    .font(.headline)
                if !agent.description.isEmpty {
                    Text(agent.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text("\(agent.capabilities.count)")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.blue.opacity(0.2)))
        }
        .padding(.vertical, 4)
    }
}

struct NodeTemplateRow: View {
    let type: WorkflowNode.NodeType
    let name: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(name)
            Spacer()
        }
        .padding(.vertical, 4)
        .onDrag {
            // 创建拖拽数据
            let provider = NSItemProvider(object: "\(type.rawValue)" as NSString)
            provider.suggestedName = name
            return provider
        }
    }
}
