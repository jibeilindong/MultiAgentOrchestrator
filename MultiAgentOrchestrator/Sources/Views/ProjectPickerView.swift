//
//  ProjectPickerView.swift
//  MultiAgentOrchestrator
//

import SwiftUI

struct ProjectPickerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var newProjectName = ""
    @State private var showingNewProject = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Text(LocalizedString.projects)
                    .font(.headline)
                Spacer()
                Button(action: { showingNewProject = true }) {
                    Image(systemName: "plus")
                }
            }
            .padding()
            
            Divider()
            
            // 项目列表
            List {
                ForEach(appState.projectManager.projects, id: \.self) { projectName in
                    Button(action: {
                        if let project = appState.projectManager.loadProject(name: projectName) {
                            appState.currentProject = project
                        }
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: projectName == appState.currentProject?.name ? "folder.fill" : "folder")
                            Text(projectName)
                            Spacer()
                            if projectName == appState.currentProject?.name {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let name = appState.projectManager.projects[index]
                        appState.projectManager.deleteProject(name: name)
                    }
                }
            }
            
            Divider()
            
            // 新建项目
            if showingNewProject {
                HStack {
                    TextField("Project Name", text: $newProjectName)
                        .textFieldStyle(.roundedBorder)
                    Button("Create") {
                        if !newProjectName.isEmpty {
                            let project = appState.projectManager.createProject(name: newProjectName)
                            appState.currentProject = project
                            dismiss()
                        }
                    }
                    Button("Cancel") {
                        showingNewProject = false
                        newProjectName = ""
                    }
                }
                .padding()
            }
        }
        .frame(width: 300, height: 400)
    }
}
