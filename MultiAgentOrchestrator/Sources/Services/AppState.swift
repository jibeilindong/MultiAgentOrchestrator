//
//  AppState.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

class AppState: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    
    @Published var currentProject: MAProject? {
        willSet {
            objectWillChange.send()
        }
    }
    
    // 选中的节点ID
    @Published var selectedNodeID: UUID?
    
    // 任务管理器
    @Published var taskManager = TaskManager()
    
    // 消息管理器
    @Published var messageManager = MessageManager()
    
    // OpenClaw 执行服务
    @Published var openClawService = OpenClawService()
    
    init() {
        createNewProject()
    }
    
    func createNewProject() {
        var project = MAProject(name: "Untitled Project")
        
        // 添加示例Agent
        var agent1 = Agent(name: "Research Assistant")
        agent1.description = "Helps with research tasks"
        agent1.soulMD = """
        # Research Assistant
        You are a research assistant that helps find and summarize information.
        """
        
        var agent2 = Agent(name: "Writer Agent")
        agent2.description = "Writes reports and documents"
        agent2.soulMD = """
        # Writer Agent
        You are a writer that creates documents based on research.
        """
        
        var agent3 = Agent(name: "Analyst Agent")
        agent3.description = "Analyzes data and provides insights"
        agent3.soulMD = """
        # Analyst Agent
        You analyze data and provide insights.
        """
        
        project.agents = [agent1, agent2, agent3]
        
        // 设置示例权限 - 明确指定 PermissionType
        project.setPermission(from: agent1, to: agent2, type: PermissionType.requireApproval)
        project.setPermission(from: agent2, to: agent3, type: PermissionType.deny)
        project.setPermission(from: agent3, to: agent1, type: PermissionType.allow)
        
        // 创建一个默认工作流
        let workflow = Workflow(name: "Research Workflow")
        project.workflows = [workflow]
        
        currentProject = project
        
        // 从工作流生成示例任务
        generateTasksFromWorkflow()
        
        // 添加示例消息
        messageManager.addSampleMessages(agents: project.agents, project: project)
    }
    
    func saveProject() {
        guard let project = currentProject else { return }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "maoproj") ?? .json]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    let data = try JSONEncoder().encode(project)
                    try data.write(to: url)
                } catch {
                    print("保存失败: \(error)")
                }
            }
        }
    }
    
    func loadProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "maoproj") ?? .json]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    let data = try Data(contentsOf: url)
                    let project = try JSONDecoder().decode(MAProject.self, from: data)
                    self.currentProject = project
                } catch {
                    print("加载失败: \(error)")
                }
            }
        }
    }
    
    // 工作流操作方法
    func getWorkflow(_ id: UUID) -> Workflow? {
        return currentProject?.workflows.first { $0.id == id }
    }
    
    func updateWorkflow(_ workflow: Workflow) {
        guard let index = currentProject?.workflows.firstIndex(where: { $0.id == workflow.id }) else { return }
        currentProject?.workflows[index] = workflow
        objectWillChange.send()
        
        // 当工作流更新时，重新生成任务
        generateTasksFromWorkflow()
    }
    
    func getAgent(for node: WorkflowNode) -> Agent? {
        guard let agentID = node.agentID else { return nil }
        return currentProject?.agents.first { $0.id == agentID }
    }
    
    // 节点选择
    func selectNode(_ nodeID: UUID?) {
        selectedNodeID = nodeID
    }
    
    // 从工作流生成任务
    func generateTasksFromWorkflow() {
        guard let workflow = currentProject?.workflows.first,
              let agents = currentProject?.agents else { return }
        
        taskManager.generateTasks(from: workflow, projectAgents: agents)
    }
    
    // 获取Agent的任务统计
    func getAgentTaskStats(_ agentID: UUID) -> (total: Int, active: Int, completed: Int) {
        let agentTasks = taskManager.tasks(for: agentID)
        let total = agentTasks.count
        let active = agentTasks.filter { $0.isActive }.count
        let completed = agentTasks.filter { $0.isCompleted }.count
        
        return (total, active, completed)
    }
    
    // 获取未分配的任务
    func unassignedTasks() -> [Task] {
        taskManager.tasks.filter { $0.assignedAgentID == nil }
    }
    
    // 模拟执行任务
    func simulateTaskExecution(_ taskID: UUID) {
        taskManager.simulateTaskExecution(taskID) { success in
            if success {
                print("任务执行完成: \(taskID)")
            }
        }
    }
}
