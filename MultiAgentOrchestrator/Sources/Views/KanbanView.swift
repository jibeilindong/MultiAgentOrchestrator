//
//  KanbanView.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI
import Combine

struct KanbanView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = KanbanViewModel()
    
    @State private var draggingTask: Task?
    @State private var showingNewTaskSheet = false
    @State private var showingTaskDetails = false
    @State private var selectedTask: Task?
    
    var body: some View {
        VStack(spacing: 0) {
            // 统计信息栏
            StatsBarView(taskManager: appState.taskManager)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.controlBackgroundColor))
            
            Divider()
            
            // 主看板区域
            HStack(alignment: .top, spacing: 16) {
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    KanbanColumnView(
                        status: status,
                        tasks: appState.taskManager.tasks(for: status),
                        draggingTask: $draggingTask,
                        onTaskSelected: { task in
                            selectedTask = task
                            showingTaskDetails = true
                        },
                        onTaskMoved: { taskID in
                            appState.taskManager.moveTask(taskID, to: status)
                        },
                        onTaskSimulated: { taskID in
                            appState.simulateTaskExecution(taskID)
                        }
                    )
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem {
                Button(action: { showingNewTaskSheet = true }) {
                    Label("New Task", systemImage: "plus")
                }
            }
            
            ToolbarItem {
                Menu {
                    Button("Generate from Workflow") {
                        appState.generateTasksFromWorkflow()
                    }
                    
                    Button("Clear Completed Tasks") {
                        clearCompletedTasks()
                    }
                    
                    Button("Simulate All", action: simulateAllTasks)
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingNewTaskSheet) {
            NewTaskView(onSave: { newTask in
                appState.taskManager.addTask(newTask)
            })
        }
        .sheet(isPresented: $showingTaskDetails) {
            if let task = selectedTask {
                TaskDetailView(
                    task: task,
                    agents: appState.currentProject?.agents ?? [],
                    onSave: { updatedTask in
                        appState.taskManager.updateTask(updatedTask)
                    },
                    onDelete: {
                        if let selectedTask {
                            appState.taskManager.deleteTask(selectedTask.id)
                        }
                    }
                )
            }
        }
        .navigationTitle("Task Board")
    }
    
    private func clearCompletedTasks() {
        let completedTasks = appState.taskManager.tasks.filter { $0.isCompleted }
        for task in completedTasks {
            appState.taskManager.deleteTask(task.id)
        }
    }
    
    private func simulateAllTasks() {
        let todoTasks = appState.taskManager.tasks(for: .todo)
        for task in todoTasks {
            appState.simulateTaskExecution(task.id)
        }
    }
}

// MARK: - 看板列视图
struct KanbanColumnView: View {
    let status: TaskStatus
    let tasks: [Task]
    @Binding var draggingTask: Task?
    var onTaskSelected: (Task) -> Void
    var onTaskMoved: (UUID) -> Void
    var onTaskSimulated: (UUID) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 列标题
            HStack {
                Image(systemName: status.icon)
                    .foregroundColor(status.color)
                Text(status.rawValue)
                    .font(.headline)
                Text("\(tasks.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(status.color.opacity(0.2)))
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            
            // 任务列表
            ScrollView {
                LazyVStack(spacing: 8) {
                    if tasks.isEmpty {
                        EmptyColumnView(status: status)
                            .frame(maxWidth: .infinity, minHeight: 100)
                    } else {
                        ForEach(tasks) { task in
                            TaskCardView(
                                task: task,
                                onTap: { onTaskSelected(task) },
                                onSimulate: { onTaskSimulated(task.id) }
                            )
                            .onDrag {
                                self.draggingTask = task
                                return NSItemProvider(object: task.id.uuidString as NSString)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            .dropDestination(for: String.self) { items, location in
                if draggingTask != nil,
                   let item = items.first,
                   let taskID = UUID(uuidString: item) {
                    
                    onTaskMoved(taskID)
                    draggingTask = nil
                    return true
                }
                return false
            } isTargeted: { _ in }
        }
        .frame(width: 320)
    }
}

// MARK: - 任务卡片视图
struct TaskCardView: View {
    let task: Task
    var onTap: () -> Void
    var onSimulate: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题和优先级
            HStack {
                Text(task.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                priorityBadge
            }
            
            // 描述
            if !task.description.isEmpty {
                Text(task.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            // 元信息
            HStack {
                // Agent
                if let agent = getAssignedAgent() {
                    HStack(spacing: 4) {
                        Image(systemName: "person.circle.fill")
                            .font(.caption2)
                        Text(agent.name)
                            .font(.caption2)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "person.slash")
                            .font(.caption2)
                        Text(LocalizedString.unassigned)
                            .font(.caption2)
                    }
                }
                
                Spacer()
                
                // 时间
                if let started = task.startedAt {
                    Text("Started: \(started.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Created: \(task.createdAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // 标签
            if !task.tags.isEmpty {
                HStack {
                    ForEach(task.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue.opacity(0.1)))
                    }
                }
            }
            
            // 操作按钮
            if task.status == .todo {
                Button("Simulate Execution") {
                    onSimulate()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(task.priority.color.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button("Edit") { onTap() }
            Button("Duplicate") { /* TODO: 复制任务 */ }
            Divider()
            Button("Delete", role: .destructive) { /* TODO: 删除任务 */ }
        }
    }
    
    private var priorityBadge: some View {
        Text(task.priority.rawValue)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(task.priority.color.opacity(0.2))
            )
            .foregroundColor(task.priority.color)
    }
    
    private func getAssignedAgent() -> Agent? {
        // 在实际应用中，这里需要通过AppState获取Agent
        // 为了简化，我们暂时返回nil
        return nil
    }
}

// MARK: - 空列视图
struct EmptyColumnView: View {
    let status: TaskStatus
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: status.icon)
                .font(.largeTitle)
                .foregroundColor(status.color.opacity(0.3))
            
            Text("No \(status.rawValue) Tasks")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(LocalizedString.tasks)
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - 统计信息栏
struct StatsBarView: View {
    @ObservedObject var taskManager: TaskManager
    
    var body: some View {
        HStack(spacing: 20) {
            StatItemView(
                title: "Total",
                value: "\(taskManager.statistics.total)",
                color: .primary
            )
            
            StatItemView(
                title: "To Do",
                value: "\(taskManager.statistics.todo)",
                color: .gray
            )
            
            StatItemView(
                title: "In Progress",
                value: "\(taskManager.statistics.inProgress)",
                color: .blue
            )
            
            StatItemView(
                title: "Done",
                value: "\(taskManager.statistics.done)",
                color: .green
            )
            
            StatItemView(
                title: "Blocked",
                value: "\(taskManager.statistics.blocked)",
                color: .red
            )
            
            Divider()
                .frame(height: 20)
            
            StatItemView(
                title: "Completion",
                value: "\(Int(taskManager.statistics.completionRate * 100))%",
                color: taskManager.statistics.completionRate > 0.7 ? .green : .orange
            )
            
            if taskManager.statistics.averageCompletionTime > 0 {
                StatItemView(
                    title: "Avg Time",
                    value: formatDuration(taskManager.statistics.averageCompletionTime),
                    color: .secondary
                )
            }
            
            Spacer()
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return "\(Int(duration))s"
        } else if duration < 3600 {
            return "\(Int(duration / 60))m"
        } else {
            return "\(Int(duration / 3600))h"
        }
    }
}

struct StatItemView: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
                .foregroundColor(color)
        }
    }
}

// MARK: - ViewModel
class KanbanViewModel: ObservableObject {
    // 如果有需要，可以在这里添加视图特定的状态和逻辑
    // 例如：搜索过滤、排序等
    
    @Published var searchText: String = ""
    @Published var sortBy: SortOption = .createdAt
    @Published var showOnlyUnassigned: Bool = false
    
    enum SortOption: String, CaseIterable {
        case createdAt = "Created Date"
        case priority = "Priority"
        case title = "Title"
    }
    
    // 显式提供初始化器
    init() {
        // 可以在这里初始化一些状态
    }
    
    // 可以根据需要添加过滤和排序逻辑
    func filterAndSort(tasks: [Task]) -> [Task] {
        var filteredTasks = tasks
        
        // 搜索过滤
        if !searchText.isEmpty {
            filteredTasks = filteredTasks.filter { task in
                task.title.localizedCaseInsensitiveContains(searchText) ||
                task.description.localizedCaseInsensitiveContains(searchText) ||
                task.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
            }
        }
        
        // 只显示未分配的任务
        if showOnlyUnassigned {
            filteredTasks = filteredTasks.filter { $0.assignedAgentID == nil }
        }
        
        // 排序
        switch sortBy {
        case .createdAt:
            filteredTasks.sort { $0.createdAt > $1.createdAt }
        case .priority:
            filteredTasks.sort { $0.priority.rawValue > $1.priority.rawValue }
        case .title:
            filteredTasks.sort { $0.title < $1.title }
        }
        
        return filteredTasks
    }
}

// MARK: - 预览
struct KanbanView_Previews: PreviewProvider {
    static var previews: some View {
        KanbanView()
            .environmentObject(AppState())
            .frame(width: 1200, height: 800)
    }
}
