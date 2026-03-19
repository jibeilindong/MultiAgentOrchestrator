//
//  SubflowEditorView.swift
//  MultiAgentOrchestrator
//
//  子流程编辑器弹窗
//  用于编辑子流程的工作流内容
//

import SwiftUI

struct SubflowEditorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    
    let parentNode: WorkflowNode
    let parentWorkflow: Workflow
    @Binding var isPresented: Bool
    
    @State private var newSubflowName: String = ""
    @State private var isCreatingNew: Bool = false
    
    // 子流程工作流
    private var currentSubflow: Workflow? {
        if let subflowID = parentNode.subflowID {
            return appState.currentProject?.workflows.first { $0.id == subflowID }
        }
        return nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Image(systemName: "arrow.down.doc.fill")
                    .foregroundColor(.purple)
                Text(isCreatingNew ? "Create Subflow" : "Edit Subflow")
                    .font(.headline)
                
                if let subflow = currentSubflow {
                    Text("- \(subflow.name)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            
            Divider()
            
            // 内容区域
            if isCreatingNew {
                createNewSubflowView
            } else if let subflow = currentSubflow {
                editExistingSubflowView(subflow: subflow)
            } else {
                noSubflowView
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // 没有子流程时的视图
    private var noSubflowView: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 60))
                .foregroundColor(.purple.opacity(0.5))
            
            Text(LocalizedString.noSubflowAssigned)
                .font(.headline)
            
            Text(LocalizedString.createOrSelectSubflow)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                Button("Create New Subflow") {
                    isCreatingNew = true
                    newSubflowName = "Subflow \(parentWorkflow.name)_\(parentNode.id.uuidString.prefix(4))"
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // 创建新子流程视图
    private var createNewSubflowView: some View {
        VStack(spacing: 20) {
            SectionView(title: "Subflow Details") {
                TextField("Subflow Name", text: $newSubflowName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            SectionView(title: "Description") {
                Text("A new subflow will be created and linked to this node.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Button("Cancel") {
                    isCreatingNew = false
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Create Subflow") {
                    createSubflow()
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(newSubflowName.isEmpty)
            }
        }
        .padding()
    }
    
    // 编辑现有子流程视图
    private func editExistingSubflowView(subflow: Workflow) -> some View {
        VStack(spacing: 0) {
            // 子流程信息
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nodes: \(subflow.nodes.count)")
                        .font(.caption)
                    Text("Connections: \(subflow.edges.count)")
                        .font(.caption)
                }
                
                Spacer()
                
                // 嵌套层级
                HStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up")
                        .foregroundColor(.orange)
                    Text("Nesting Level: \(parentNode.nestingLevel + 1)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            
            Divider()
            
            // 预览区域
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SectionView(title: "Nodes Preview") {
                        if subflow.nodes.isEmpty {
                            Text("No nodes in this subflow")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            ForEach(subflow.nodes) { node in
                                HStack {
                                    Image(systemName: nodeIcon(for: node.type))
                                        .foregroundColor(nodeColor(for: node.type))
                                    Text(nodeTitle(for: node))
                                    Spacer()
                                    Text("(\(Int(node.position.x)), \(Int(node.position.y)))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    
                    SectionView(title: "Actions") {
                        HStack {
                            Button("View Full Editor") {
                                // TODO: 打开完整的子流程编辑器
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Delete Subflow", role: .destructive) {
                                deleteSubflow()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
            }
        }
    }
    
    // 创建子流程
    private func createSubflow() {
        var newSubflow = Workflow(name: newSubflowName)
        newSubflow.parentNodeID = parentNode.id

        var entryNode = WorkflowNode(type: .start)
        entryNode.position = CGPoint(x: 200, y: 100)
        entryNode.nestingLevel = parentNode.nestingLevel + 1

        newSubflow.nodes = [entryNode]
        
        // 添加到项目
        appState.currentProject?.workflows.append(newSubflow)
        
        // 更新父节点的subflowID
        updateParentNodeSubflowID(newSubflow.id)
        
        isCreatingNew = false
    }
    
    // 删除子流程
    private func deleteSubflow() {
        guard let subflowID = parentNode.subflowID else { return }
        
        // 从项目中移除子流程
        appState.currentProject?.workflows.removeAll { $0.id == subflowID }
        
        // 清除父节点的subflowID
        updateParentNodeSubflowID(nil)
    }
    
    // 更新父节点的subflowID
    private func updateParentNodeSubflowID(_ newSubflowID: UUID?) {
        guard var workflow = appState.currentProject?.workflows.first(where: { $0.id == parentWorkflow.id }),
              let index = workflow.nodes.firstIndex(where: { $0.id == parentNode.id }) else { return }
        
        workflow.nodes[index].subflowID = newSubflowID
        
        if let projectIndex = appState.currentProject?.workflows.firstIndex(where: { $0.id == parentWorkflow.id }) {
            appState.currentProject?.workflows[projectIndex] = workflow
        }
    }
    
    // 辅助函数
    private func nodeIcon(for type: WorkflowNode.NodeType) -> String {
        switch type {
        case .start: return "play.circle.fill"
        case .agent: return "person.circle.fill"
        }
    }
    
    private func nodeColor(for type: WorkflowNode.NodeType) -> Color {
        switch type {
        case .start: return .orange
        case .agent: return .blue
        }
    }
    
    private func nodeTitle(for node: WorkflowNode) -> String {
        switch node.type {
        case .start: return "Start"
        case .agent: return "Agent Node"
        }
    }
}

// 预览
struct SubflowEditorView_Previews: PreviewProvider {
    static var previews: some View {
        SubflowEditorView(
            parentNode: WorkflowNode(type: .agent),
            parentWorkflow: Workflow(name: "Main"),
            isPresented: .constant(true)
        )
        .environmentObject(AppState())
    }
}
