//
//  Untitled.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import Foundation
import Combine

class TaskManager: ObservableObject {
    @Published var tasks: [Task] = []
    @Published var statistics: TaskStatistics = TaskStatistics()
    
    private var cancellables = Set<AnyCancellable>()
    
    init(seedSampleData: Bool = false) {
        if seedSampleData {
            setupSampleData()
        }
        startStatisticsUpdate()
    }
    
    // MARK: - 任务管理
    
    func addTask(_ task: Task) {
        tasks.append(task)
        updateStatistics()
    }

    func replaceTasks(_ newTasks: [Task]) {
        tasks = newTasks
        updateStatistics()
    }

    func reset() {
        tasks.removeAll()
        updateStatistics()
    }
    
    func updateTask(_ task: Task) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
            updateStatistics()
        }
    }
    
    func deleteTask(_ taskID: UUID) {
        tasks.removeAll { $0.id == taskID }
        updateStatistics()
    }
    
    func moveTask(_ taskID: UUID, to newStatus: TaskStatus) {
        if let index = tasks.firstIndex(where: { $0.id == taskID }) {
            var task = tasks[index]
            
            // 更新开始/完成时间
            if newStatus == .inProgress && task.status != .inProgress {
                task.start()
            } else if newStatus == .done && task.status != .done {
                task.complete()
            } else if newStatus == .blocked && task.status != .blocked {
                task.block()
            }
            
            task.status = newStatus
            tasks[index] = task
            updateStatistics()
        }
    }
    
    func assignTask(_ taskID: UUID, to agentID: UUID?) {
        if let index = tasks.firstIndex(where: { $0.id == taskID }) {
            var task = tasks[index]
            task.reassign(to: agentID)
            tasks[index] = task
        }
    }
    
    // MARK: - 查询
    
    func tasks(for status: TaskStatus) -> [Task] {
        tasks.filter { $0.status == status }
    }
    
    func tasks(for agentID: UUID) -> [Task] {
        tasks.filter { $0.assignedAgentID == agentID }
    }
    
    func task(with id: UUID) -> Task? {
        tasks.first { $0.id == id }
    }
    
    func activeTasks(for agentID: UUID) -> [Task] {
        tasks.filter { $0.assignedAgentID == agentID && $0.isActive }
    }
    
    // MARK: - 从工作流生成任务
    
    func generateTasks(from workflow: Workflow, projectAgents: [Agent]) {
        let agentNodes = workflow.nodes.filter { $0.type == .agent }
        let agentNodeIDs = Set(agentNodes.map(\.id))

        let manualTasks = tasks.filter { task in
            guard let workflowNodeID = task.workflowNodeID else {
                return true
            }
            return !agentNodeIDs.contains(workflowNodeID)
        }

        var generatedTasks: [Task] = []
        for node in agentNodes {
            guard let agentID = node.agentID,
                  let agent = projectAgents.first(where: { $0.id == agentID }) else {
                continue
            }

            if var existingTask = tasks.first(where: { $0.workflowNodeID == node.id }) {
                existingTask.title = "Execute: \(agent.name)"
                existingTask.description = "Execute workflow node for \(agent.name)"
                existingTask.assignedAgentID = agentID
                generatedTasks.append(existingTask)
            } else {
                generatedTasks.append(
                    Task(
                        title: "Execute: \(agent.name)",
                        description: "Execute workflow node for \(agent.name)",
                        status: .todo,
                        priority: .medium,
                        assignedAgentID: agentID,
                        workflowNodeID: node.id,
                        createdBy: nil
                    )
                )
            }
        }

        tasks = manualTasks + generatedTasks
        updateStatistics()
    }
    
    // MARK: - 模拟执行
    
    func simulateTaskExecution(_ taskID: UUID, completion: @escaping (Bool) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else {
            completion(false)
            return
        }
        
        var task = tasks[index]
        
        // 模拟任务执行过程
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            task.start()
            self.tasks[index] = task
            self.updateStatistics()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                task.complete()
                self.tasks[index] = task
                self.updateStatistics()
                completion(true)
            }
        }
    }
    
    // MARK: - 统计数据
    
    struct TaskStatistics {
        var total: Int = 0
        var todo: Int = 0
        var inProgress: Int = 0
        var done: Int = 0
        var blocked: Int = 0
        var completionRate: Double = 0.0
        var averageCompletionTime: TimeInterval = 0
    }
    
    private func updateStatistics() {
        let total = tasks.count
        let todo = tasks.filter { $0.status == .todo }.count
        let inProgress = tasks.filter { $0.status == .inProgress }.count
        let done = tasks.filter { $0.status == .done }.count
        let blocked = tasks.filter { $0.status == .blocked }.count
        let completionRate = total > 0 ? Double(done) / Double(total) : 0.0
        
        // 计算平均完成时间
        let completedTasks = tasks.filter { $0.isCompleted && $0.duration != nil }
        let totalDuration = completedTasks.reduce(0) { $0 + ($1.duration ?? 0) }
        let averageCompletionTime = completedTasks.isEmpty ? 0 : totalDuration / Double(completedTasks.count)
        
        statistics = TaskStatistics(
            total: total,
            todo: todo,
            inProgress: inProgress,
            done: done,
            blocked: blocked,
            completionRate: completionRate,
            averageCompletionTime: averageCompletionTime
        )
    }
    
    private func startStatisticsUpdate() {
        Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateStatistics()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 示例数据
    
    private func setupSampleData() {
        let sampleTasks = [
            Task(
                title: "Research AI Trends",
                description: "Gather information about latest AI trends and technologies",
                status: .todo,
                priority: .high,
                tags: ["research", "ai"]  // 现在这个调用是有效的
            ),
            Task(
                title: "Write Report",
                description: "Create summary report based on research findings",
                status: .inProgress,
                priority: .medium,
                tags: ["writing", "documentation"]
            ),
            Task(
                title: "Analyze Data",
                description: "Process and analyze the collected data",
                status: .inProgress,
                priority: .high,
                tags: ["analysis", "data"]
            ),
            Task(
                title: "Setup Project",
                description: "Initialize the project structure and dependencies",
                status: .done,
                priority: .low,
                tags: ["setup", "configuration"]
            ),
            Task(
                title: "Review Code",
                description: "Code review and quality assurance",
                status: .blocked,
                priority: .medium,
                tags: ["review", "qa"]
            ),
            Task(
                title: "Deploy Application",
                description: "Deploy to production environment",
                status: .todo,
                priority: .critical,
                tags: ["deployment", "production"]
            )
        ]
        
        tasks = sampleTasks
        updateStatistics()
    }
}
