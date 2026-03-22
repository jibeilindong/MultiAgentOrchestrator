//
//  SidebarView.swift
//  Multi-Agent-Flow
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedTab: Int
    @ObservedObject var sessionState: WorkflowEditorSessionState
    @State private var showingProjectPicker = false

    var body: some View {
        VStack(spacing: 0) {
            projectFileSection

            Divider()

            navigationSection

            if selectedTab == 0 {
                Divider()

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
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.8))
        .sheet(isPresented: $showingProjectPicker) {
            ProjectPickerView()
                .environmentObject(appState)
        }
    }

    private var projectFileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
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
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(appState.currentProject?.name ?? LocalizedString.project)
                                .font(.headline)
                                .lineLimit(1)
                            Text(projectSummary)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.controlBackgroundColor).opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
                .contentShape(Rectangle())
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
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedString.navigation)
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)

            ForEach(navigationItems) { item in
                Button(action: { selectedTab = item.tag }) {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .frame(width: 16)
                        Text(item.title)
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selectedTab == item.tag ? Color.accentColor.opacity(0.16) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
            }
        }
        .padding(.bottom, selectedTab == 0 ? 8 : 0)
    }

    private var projectSummary: String {
        let agentCount = appState.currentProject?.agents.count ?? 0
        let workflowCount = appState.currentProject?.workflows.count ?? 0
        let taskCount = appState.taskManager.tasks.count
        return LocalizedString.format("project_summary_counts", agentCount, workflowCount, taskCount)
    }

    private var navigationItems: [NavigationItem] {
        [
            NavigationItem(tag: 0, title: LocalizedString.text("workflow_editor_nav"), icon: "square.grid.2x2"),
            NavigationItem(tag: 1, title: LocalizedString.text("workbench_nav"), icon: "message.badge.waveform"),
            NavigationItem(tag: 2, title: LocalizedString.text("monitoring_dashboard_nav"), icon: "gauge.with.dots.needle.33percent"),
            NavigationItem(tag: 3, title: LocalizedString.text("template_library_nav"), icon: "shippingbox")
        ]
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

private struct NavigationItem: Identifiable {
    let tag: Int
    let title: String
    let icon: String

    var id: Int { tag }
}
