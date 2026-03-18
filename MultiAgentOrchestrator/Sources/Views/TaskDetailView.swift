//
//  TaskDetailView.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct TaskDetailView: View {
    @Environment(\.dismiss) var dismiss
    let task: Task
    let agents: [Agent]
    let onSave: (Task) -> Void
    let onDelete: () -> Void
    
    @State private var editedTask: Task
    
    init(task: Task, agents: [Agent], onSave: @escaping (Task) -> Void, onDelete: @escaping () -> Void) {
        self.task = task
        self.agents = agents
        self.onSave = onSave
        self.onDelete = onDelete
        self._editedTask = State(initialValue: task)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text(LocalizedString.taskDetails)
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(editedTask)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            
            Divider()
            
            // 表单内容
            ScrollView {
                VStack(spacing: 20) {
                    SectionView(title: "Task Information") {
                        TextField("Title", text: $editedTask.title)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.headline)
                        
                        TextField("Description", text: $editedTask.description)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(height: 80)
                    }
                    
                    HStack(spacing: 20) {
                        SectionView(title: "Status") {
                            Picker("Status", selection: $editedTask.status) {
                                ForEach(TaskStatus.allCases, id: \.self) { status in
                                    Label(status.rawValue, systemImage: status.icon)
                                        .tag(status)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        SectionView(title: "Priority") {
                            Picker("Priority", selection: $editedTask.priority) {
                                ForEach(TaskPriority.allCases, id: \.self) { priority in
                                    Label(priority.rawValue, systemImage: "flag.fill")
                                        .foregroundColor(priority.color)
                                        .tag(priority)
                                }
                            }
                        }
                    }
                    
                    SectionView(title: "Assignment") {
                        Picker("Assign to Agent", selection: $editedTask.assignedAgentID) {
                            Text("Unassigned").tag(nil as UUID?)
                            ForEach(agents) { agent in
                                Text(agent.name).tag(agent.id as UUID?)
                            }
                        }
                    }
                    
                    SectionView(title: "Timeline") {
                        TaskInfoRow(label: "Created", value: task.createdAt.formatted())
                        
                        if let startedAt = task.startedAt {
                            TaskInfoRow(label: "Started", value: startedAt.formatted())
                        }
                        
                        if let completedAt = task.completedAt {
                            TaskInfoRow(label: "Completed", value: completedAt.formatted())
                        }
                        
                        if let duration = task.duration {
                            TaskInfoRow(label: "Duration", value: formatDuration(duration))
                        } else if let timeSpent = task.timeSpent {
                            TaskInfoRow(label: "Time Spent", value: formatDuration(timeSpent))
                        }
                    }
                    
                    if !task.tags.isEmpty {
                        SectionView(title: "Tags") {
                            HStack {
                                ForEach(task.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.blue.opacity(0.2)))
                                }
                            }
                        }
                    }
                    
                    SectionView(title: "Actions") {
                        HStack {
                            Button("Simulate Execution") {
                                // TODO: 模拟执行
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Delete Task", role: .destructive) {
                                onDelete()
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 500, minHeight: 600)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0s"
    }
}
