//
//  SidebarView.swift
//  Multi-Agent-Flow
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var sessionState: WorkflowEditorSessionState

    var body: some View {
        VStack(spacing: 0) {
            AgentLibrarySidebar(
                selectedAgentID: Binding(
                    get: { sessionState.selectedAgentID },
                    set: { sessionState.selectedAgentID = $0 }
                ),
                onAddAll: { appState.generateArchitectureFromProjectAgents() },
                isOpenClawConnected: appState.openClawManager.isConnected,
                openClawAgents: filteredOpenClawAgents
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.8))
    }

    private var projectSummary: String {
        let agentCount = appState.currentProject?.agents.count ?? 0
        let workflowCount = appState.currentProject?.workflows.count ?? 0
        let taskCount = appState.taskManager.tasks.count
        return LocalizedString.format("project_summary_counts", agentCount, workflowCount, taskCount)
    }

    private var filteredOpenClawAgents: [String] {
        let projectAgentNames = Set(
            (appState.currentProject?.agents ?? [])
                .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
        return appState.openClawManager.agents.filter { agentName in
            !projectAgentNames.contains(agentName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }
}

enum ProjectControlsStyle {
    case sidebar
    case toolbar
}

struct ProjectControlsView: View {
    @EnvironmentObject var appState: AppState
    let style: ProjectControlsStyle

    @State private var showingProjectPicker = false

    var body: some View {
        Group {
            switch style {
            case .sidebar:
                sidebarLayout
            case .toolbar:
                toolbarLayout
            }
        }
        .sheet(isPresented: $showingProjectPicker) {
            ProjectPickerView()
                .environmentObject(appState)
        }
    }

    private var sidebarLayout: some View {
        HStack(spacing: 8) {
            projectMenu
                .frame(maxWidth: .infinity)

            Button(action: { appState.saveProject() }) {
                Label(LocalizedString.save, systemImage: "square.and.arrow.down")
                    .font(.caption)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.bordered)
            .help(LocalizedString.saveProject)
            .disabled(appState.currentProject == nil)

            Button(action: { appState.saveDraft() }) {
                Label(LocalizedString.text("save_draft"), systemImage: "square.and.arrow.down.on.square")
                    .font(.caption)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.bordered)
            .help(LocalizedString.text("save_draft_tooltip"))
            .disabled(appState.currentProject == nil)

            if appState.currentProject != nil {
                Button(action: { appState.closeProject() }) {
                    Label(LocalizedString.close, systemImage: "xmark.circle")
                        .font(.caption)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.bordered)
                .help(LocalizedString.closeProject)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var toolbarLayout: some View {
        HStack(spacing: 8) {
            projectMenu
                .frame(minWidth: 172, idealWidth: 188, maxWidth: 210)

            workflowMenu
                .frame(minWidth: 148, idealWidth: 164, maxWidth: 188)

            workflowPackageMenu

            toolbarDivider

            compactActionButton(
                systemName: "square.and.arrow.down",
                helpText: LocalizedString.saveProject,
                isDisabled: appState.currentProject == nil
            ) {
                appState.saveProject()
            }

            compactActionButton(
                systemName: "square.and.arrow.down.on.square",
                helpText: LocalizedString.text("save_draft_tooltip"),
                isDisabled: appState.currentProject == nil
            ) {
                appState.saveDraft()
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.controlBackgroundColor).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var workflowMenu: some View {
        Menu {
            ForEach(appState.currentProject?.workflows ?? []) { workflow in
                Button(action: { appState.setActiveWorkflow(workflow.id) }) {
                    Label(
                        workflow.name,
                        systemImage: workflow.id == appState.activeWorkflowID ? "checkmark.circle.fill" : "circle"
                    )
                }
            }
        } label: {
            toolbarAccessoryMenuLabel(
                title: appState.currentProject == nil
                    ? LocalizedString.text("no_workflow_selected")
                    : appState.currentWorkflowName,
                systemName: "point.3.connected.trianglepath.dotted"
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .disabled(appState.currentProject?.workflows.isEmpty ?? true)
        .opacity((appState.currentProject?.workflows.isEmpty ?? true) ? 0.55 : 1)
    }

    private var workflowPackageMenu: some View {
        Menu {
            Button("导入设计包", action: { appState.importWorkflowPackage() })
            Button("导出当前设计包", action: { appState.exportCurrentWorkflowPackage() })
                .disabled(appState.currentProject == nil || appState.workflow(for: nil) == nil)
        } label: {
            toolbarAccessoryMenuLabel(title: "设计包", systemName: "shippingbox")
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .disabled(appState.currentProject == nil)
        .opacity(appState.currentProject == nil ? 0.55 : 1)
    }

    private var projectMenu: some View {
        Menu {
            Section(LocalizedString.text("current_project")) {
                Button(action: { showingProjectPicker = true }) {
                    Label(LocalizedString.text("switch_or_manage_project"), systemImage: "rectangle.stack")
                }

                ForEach(appState.projectManager.projects.prefix(8)) { project in
                    Button(action: { appState.openProject(at: project.url) }) {
                        Label(project.name, systemImage: project.url == appState.currentProjectFileURL ? "checkmark.circle.fill" : "folder")
                    }
                }
            }

            Divider()

            Button(action: { appState.createNewProject() }) {
                Label(LocalizedString.new, systemImage: "plus")
            }
            Button(action: { appState.openProject() }) {
                Label(LocalizedString.openProject, systemImage: "folder")
            }
            Button(action: { appState.saveProject() }) {
                Label(LocalizedString.save, systemImage: "square.and.arrow.down")
            }
            Button(action: { appState.saveDraft() }) {
                Label(LocalizedString.text("save_draft"), systemImage: "square.and.arrow.down.on.square")
            }
            Button(action: { appState.saveProjectAs() }) {
                Label(LocalizedString.text("save_as"), systemImage: "square.and.arrow.down.on.square")
            }

            Divider()

            Button(action: { appState.importData() }) {
                Label(LocalizedString.text("import_architecture"), systemImage: "square.and.arrow.down.on.square")
            }
            Button(action: { appState.exportData() }) {
                Label(LocalizedString.text("export_architecture"), systemImage: "square.and.arrow.up")
            }

            Divider()

            Button(action: { appState.importWorkflowPackage() }) {
                Label("导入工作流设计包", systemImage: "shippingbox")
            }
            .disabled(appState.currentProject == nil)

            Button(action: { appState.exportCurrentWorkflowPackage() }) {
                Label("导出当前工作流设计包", systemImage: "archivebox")
            }
            .disabled(appState.currentProject == nil || appState.workflow(for: nil) == nil)

            if appState.currentProject != nil {
                Divider()

                Button(action: { appState.deleteCurrentProject() }) {
                    Label(LocalizedString.text("delete_project"), systemImage: "trash")
                }

                Button(action: { appState.closeProject() }) {
                    Label(LocalizedString.closeProject, systemImage: "xmark.circle")
                }
            }
        } label: {
            projectMenuLabel
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var projectMenuLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")

            if style == .sidebar {
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.currentProject?.name ?? LocalizedString.project)
                        .font(.headline)
                        .lineLimit(1)
                    Text(projectSummary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(LocalizedString.project)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(appState.currentProject?.name ?? LocalizedString.project)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, style == .sidebar ? 10 : 8)
        .background(Color(.controlBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 22)
    }

    private func toolbarAccessoryMenuLabel(title: String, systemName: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.caption)
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .foregroundColor(Color.primary.opacity(0.84))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Color.white.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func compactActionButton(
        systemName: String,
        helpText: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(helpText)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }

    private var projectSummary: String {
        let agentCount = appState.currentProject?.agents.count ?? 0
        let workflowCount = appState.currentProject?.workflows.count ?? 0
        let taskCount = appState.taskManager.tasks.count
        return LocalizedString.format("project_summary_counts", agentCount, workflowCount, taskCount)
    }
}
