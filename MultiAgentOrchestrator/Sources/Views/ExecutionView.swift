//
//  ExecutionView.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct ExecutionView: View {  // 这应该是 ExecutionView，不是 ContentView
    @EnvironmentObject var appState: AppState
    @StateObject private var openClawService = OpenClawService()
    
    @State private var selectedWorkflowID: UUID?
    @State private var isExecuting = false
    @State private var showResults = false
    
    var workflows: [Workflow] {
        appState.currentProject?.workflows ?? []
    }
    
    var selectedWorkflow: Workflow? {
        if let id = selectedWorkflowID {
            return workflows.first { $0.id == id }
        }
        return nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 控制面板
            HStack {
                Text("Workflow Execution")
                    .font(.title2)
                
                Spacer()
                
                // 工作流选择器
                Picker("Workflow", selection: $selectedWorkflowID) {
                    Text("Select a workflow").tag(nil as UUID?)
                    ForEach(workflows) { workflow in
                        Text(workflow.name).tag(workflow.id as UUID?)
                    }
                }
                .frame(width: 200)
                
                Button("Execute") {
                    executeWorkflow()
                }
                .disabled(selectedWorkflow == nil || isExecuting)
                .buttonStyle(.borderedProminent)
                
                Button("Clear Results") {
                    openClawService.clearResults()
                }
                .disabled(openClawService.executionResults.isEmpty)
            }
            .padding()
            
            Divider()
            
            if isExecuting {
                // 执行进度
                executionProgressView
            } else if showResults {
                // 执行结果
                executionResultsView
            } else {
                // 默认视图
                defaultView
            }
        }
    }
    
    private var executionProgressView: some View {
        VStack(spacing: 20) {
            ProgressView(value: Double(openClawService.currentStep), total: Double(openClawService.totalSteps)) {
                Text("Executing Workflow...")
                    .font(.headline)
            }
            .progressViewStyle(.linear)
            .padding()
            
            Text("Step \(openClawService.currentStep) of \(openClawService.totalSteps)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let workflow = selectedWorkflow {
                let agentNodes = workflow.nodes.filter { $0.type == .agent }
                if openClawService.currentStep > 0 && openClawService.currentStep <= agentNodes.count {
                    let currentNode = agentNodes[openClawService.currentStep - 1]
                    if let agentID = currentNode.agentID,
                       let agent = appState.currentProject?.agents.first(where: { $0.id == agentID }) {
                        VStack {
                            Text("Executing: \(agent.name)")
                                .font(.headline)
                            Text("Node at position (\(Int(currentNode.position.x)), \(Int(currentNode.position.y)))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var executionResultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if openClawService.executionResults.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "chart.bar",
                        description: Text("Execute a workflow to see results")
                    )
                } else {
                    // 统计摘要
                    resultSummaryView
                    
                    // 详细结果
                    ForEach(openClawService.executionResults) { result in
                        ExecutionResultView(result: result)
                    }
                }
            }
            .padding()
        }
    }
    
    private var resultSummaryView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Execution Summary")
                .font(.headline)
            
            let total = openClawService.executionResults.count
            let completed = openClawService.executionResults.filter { $0.status == .completed }.count
            let failed = openClawService.executionResults.filter { $0.status == .failed }.count
            let successRate = total > 0 ? Double(completed) / Double(total) * 100 : 0
            
            HStack(spacing: 20) {
                StatCard(title: "Total", value: "\(total)", color: .primary)
                StatCard(title: "Completed", value: "\(completed)", color: .green)
                StatCard(title: "Failed", value: "\(failed)", color: .red)
                StatCard(title: "Success Rate", value: String(format: "%.1f%%", successRate),
                        color: successRate > 80 ? .green : .orange)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var defaultView: some View {
        VStack(spacing: 30) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .opacity(0.5)
            
            Text("Ready to Execute")
                .font(.title)
                .foregroundColor(.secondary)
            
            Text("Select a workflow and click Execute to run it")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if let workflow = selectedWorkflow {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected Workflow: \(workflow.name)")
                        .font(.headline)
                    
                    let agentNodes = workflow.nodes.filter { $0.type == .agent }
                    Text("\(agentNodes.count) agent nodes, \(workflow.edges.count) connections")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func executeWorkflow() {
        guard let workflow = selectedWorkflow,
              let agents = appState.currentProject?.agents else { return }
        
        isExecuting = true
        showResults = false
        
        openClawService.executeWorkflow(workflow, agents: agents) { results in
            isExecuting = false
            showResults = true
        }
    }
}
