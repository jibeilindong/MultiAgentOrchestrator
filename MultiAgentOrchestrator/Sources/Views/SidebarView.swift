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
    @State private var agentLibraryHeight: CGFloat = 320
    @State private var agentLibraryHeightAtDragStart: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            projectHeader

            Divider()

            navigationSection

            if selectedTab == 0 {
                Divider()

                resizeHandle

                AgentLibrarySidebar(
                    onAddAll: { appState.generateArchitectureFromProjectAgents() },
                    isOpenClawConnected: appState.openClawManager.isConnected,
                    openClawAgents: appState.openClawManager.agents
                )
                .frame(height: agentLibraryHeight)
            } else {
                Spacer()
            }

            if selectedTab == 0 {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var projectHeader: some View {
        HStack {
            Button(action: { showingProjectPicker = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.currentProject?.name ?? "No Project")
                            .font(.headline)
                            .lineLimit(1)
                        Text(projectMeta)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)

            if appState.currentProject != nil {
                Button(action: { appState.closeProject() }) {
                    Image(systemName: "minus.circle")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .sheet(isPresented: $showingProjectPicker) {
            ProjectPickerView()
                .environmentObject(appState)
        }
    }

    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedString.navigation)
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 12)

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
        .padding(.bottom, selectedTab == 0 ? 12 : 0)
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.12))
            .frame(height: 8)
            .overlay(
                Capsule()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 46, height: 4)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let startHeight = agentLibraryHeightAtDragStart ?? agentLibraryHeight
                        if agentLibraryHeightAtDragStart == nil {
                            agentLibraryHeightAtDragStart = agentLibraryHeight
                        }
                        agentLibraryHeight = min(max(startHeight - value.translation.height, 180), 560)
                    }
                    .onEnded { _ in
                        agentLibraryHeightAtDragStart = nil
                    }
            )
            .help("拖拉调整智能体库高度")
    }

    private var projectMeta: String {
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
}

private struct NavigationItem: Identifiable {
    let tag: Int
    let title: String
    let icon: String

    var id: Int { tag }
}
