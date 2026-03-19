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
                ForEach(appState.projectManager.projects) { project in
                    Button(action: {
                        appState.openProject(at: project.url)
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: project.url == appState.currentProjectFileURL ? "folder.fill" : "folder")
                            Text(project.name)
                            Spacer()
                            if project.url == appState.currentProjectFileURL {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let project = appState.projectManager.projects[index]
                        appState.projectManager.deleteProject(
                            at: project.url,
                            projectID: appState.currentProjectFileURL == project.url ? appState.currentProject?.id : nil
                        )
                        if appState.currentProjectFileURL == project.url {
                            appState.closeProject()
                        }
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
                            appState.createNewProject(named: newProjectName)
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
