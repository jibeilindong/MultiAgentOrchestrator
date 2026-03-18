//
//  Untitled.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct NewTaskView: View {
    @Environment(\.dismiss) var dismiss
    let onSave: (Task) -> Void
    
    @State private var title = ""
    @State private var description = ""
    @State private var selectedStatus = TaskStatus.todo
    @State private var selectedPriority = TaskPriority.medium
    @State private var selectedAgentID: UUID?
    @State private var tags: [String] = []
    @State private var newTag = ""
    @State private var estimatedHours = 1
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text(LocalizedString.newTask)
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Create") {
                    createTask()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.isEmpty)
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            
            Divider()
            
            // 表单内容
            ScrollView {
                VStack(spacing: 20) {
                    // 任务详情
                    SectionView(title: "Task Details") {
                        TextField("Title", text: $title)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        TextField("Description", text: $description)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(height: 60)
                    }
                    
                    // 状态和优先级
                    HStack(spacing: 20) {
                        SectionView(title: "Status") {
                            Picker("Status", selection: $selectedStatus) {
                                ForEach(TaskStatus.allCases, id: \.self) { status in
                                    Label(status.rawValue, systemImage: status.icon)
                                        .tag(status)
                                }
                            }
                        }
                        
                        SectionView(title: "Priority") {
                            Picker("Priority", selection: $selectedPriority) {
                                ForEach(TaskPriority.allCases, id: \.self) { priority in
                                    Label(priority.rawValue, systemImage: "flag.fill")
                                        .foregroundColor(priority.color)
                                        .tag(priority)
                                }
                            }
                        }
                    }
                    
                    // 分配
                    SectionView(title: "Assignment") {
                        Picker("Assign to Agent", selection: $selectedAgentID) {
                            Text("Unassigned").tag(nil as UUID?)
                        }
                        
                        HStack {
                            Text("Estimated Time:")
                            Stepper("\(estimatedHours) hours", value: $estimatedHours, in: 1...24)
                        }
                    }
                    
                    // 标签
                    SectionView(title: "Tags") {
                        HStack {
                            TextField("Add tag", text: $newTag)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .onSubmit {
                                    addTag()
                                }
                            
                            Button("Add") {
                                addTag()
                            }
                            .disabled(newTag.isEmpty)
                        }
                        
                        if !tags.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(tags, id: \.self) { tag in
                                    HStack(spacing: 4) {
                                        Text(tag)
                                            .font(.caption)
                                        Button {
                                            removeTag(tag)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption2)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.blue.opacity(0.2)))
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 500, minHeight: 600)
    }
    
    private func addTag() {
        guard !newTag.isEmpty else { return }
        if !tags.contains(newTag) {
            tags.append(newTag)
        }
        newTag = ""
    }
    
    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
    
    private func createTask() {
        let estimatedDuration = TimeInterval(estimatedHours * 3600)
        
        let task = Task(
            title: title,
            description: description,
            status: selectedStatus,
            priority: selectedPriority,
            assignedAgentID: selectedAgentID,
            tags: tags,
            estimatedDuration: estimatedDuration
        )
        
        onSave(task)
    }
}
