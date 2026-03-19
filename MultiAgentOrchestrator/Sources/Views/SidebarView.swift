//
//  SidebarView.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedTab: Int
    @State private var showingProjectPicker = false

    var body: some View {
        VStack(spacing: 0) {
            projectFileSection

            Divider()

            navigationSection

            if selectedTab == 0 {
                Divider()

                AgentLibrarySidebar(
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
        .background(Color(.windowBackgroundColor).opacity(0.8))
        .sheet(isPresented: $showingProjectPicker) {
            ProjectPickerView()
                .environmentObject(appState)
        }
    }

    private var projectFileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Menu {
                    Section("当前项目") {
                        Button(action: { showingProjectPicker = true }) {
                            Label("切换或管理项目", systemImage: "rectangle.stack")
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
                    Button(action: { appState.saveProjectAs() }) {
                        Label("另存为", systemImage: "square.and.arrow.down.on.square")
                    }

                    Divider()

                    Button(action: { appState.importData() }) {
                        Label("导入架构", systemImage: "square.and.arrow.down.on.square")
                    }
                    Button(action: { appState.exportData() }) {
                        Label("导出架构", systemImage: "square.and.arrow.up")
                    }

                    if appState.currentProject != nil {
                        Divider()

                        Button(action: { appState.deleteCurrentProject() }) {
                            Label("删除项目", systemImage: "trash")
                        }

                        Button(action: { appState.closeProject() }) {
                            Label("关闭项目", systemImage: "xmark.circle")
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(appState.currentProject?.name ?? "项目")
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
                    Label("保存", systemImage: "square.and.arrow.down")
                        .font(.caption)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.bordered)
                .help("保存项目")
                .disabled(appState.currentProject == nil)

                if appState.currentProject != nil {
                    Button(action: { appState.closeProject() }) {
                        Label("关闭", systemImage: "xmark.circle")
                            .font(.caption)
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.bordered)
                    .help("关闭项目")
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
        return "\(agentCount) agents • \(workflowCount) workflows • \(taskCount) tasks"
    }

    private var navigationItems: [NavigationItem] {
        [
            NavigationItem(tag: 0, title: "工作流编辑器", icon: "square.grid.2x2"),
            NavigationItem(tag: 1, title: "工作台对话", icon: "message.badge.waveform"),
            NavigationItem(tag: 2, title: "监控仪表盘", icon: "gauge.with.dots.needle.33percent")
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
