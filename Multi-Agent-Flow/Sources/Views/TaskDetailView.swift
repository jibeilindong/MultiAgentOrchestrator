//
//  TaskDetailView.swift
//  Multi-Agent-Flow
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
                Button(LocalizedString.cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(LocalizedString.save) {
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
                    SectionView(title: LocalizedString.text("task_information")) {
                        TextField(LocalizedString.text("title_label"), text: $editedTask.title)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.headline)
                        
                        TextField(LocalizedString.description, text: $editedTask.description)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(height: 80)
                    }
                    
                    HStack(spacing: 20) {
                        SectionView(title: LocalizedString.status) {
                            Picker(LocalizedString.status, selection: $editedTask.status) {
                                ForEach(TaskStatus.allCases, id: \.self) { status in
                                    Label(status.displayName, systemImage: status.icon)
                                        .tag(status)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        SectionView(title: LocalizedString.priority) {
                            Picker(LocalizedString.priority, selection: $editedTask.priority) {
                                ForEach(TaskPriority.allCases, id: \.self) { priority in
                                    Label(priority.displayName, systemImage: "flag.fill")
                                        .foregroundColor(priority.color)
                                        .tag(priority)
                                }
                            }
                        }
                    }
                    
                    SectionView(title: LocalizedString.text("assignment")) {
                        Picker(LocalizedString.text("assign_to_agent"), selection: $editedTask.assignedAgentID) {
                            Text(LocalizedString.unassigned).tag(nil as UUID?)
                            ForEach(agents) { agent in
                                Text(agent.name).tag(agent.id as UUID?)
                            }
                        }
                    }
                    
                    SectionView(title: LocalizedString.text("timeline")) {
                        TaskInfoRow(label: LocalizedString.text("created_label"), value: task.createdAt.formatted())
                        
                        if let startedAt = task.startedAt {
                            TaskInfoRow(label: LocalizedString.text("started_label"), value: startedAt.formatted())
                        }
                        
                        if let completedAt = task.completedAt {
                            TaskInfoRow(label: LocalizedString.text("completed_label"), value: completedAt.formatted())
                        }
                        
                        if let duration = task.duration {
                            TaskInfoRow(label: LocalizedString.text("duration_label"), value: formatDuration(duration))
                        } else if let timeSpent = task.timeSpent {
                            TaskInfoRow(label: LocalizedString.text("time_spent"), value: formatDuration(timeSpent))
                        }
                    }
                    
                    if !task.tags.isEmpty {
                        SectionView(title: LocalizedString.text("tags")) {
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
                    
                    SectionView(title: LocalizedString.actions) {
                        HStack {
                            Button(LocalizedString.text("simulate_execution")) {
                                // TODO: 模拟执行
                            }
                            .buttonStyle(.bordered)
                            
                            Button(LocalizedString.text("delete_task"), role: .destructive) {
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
