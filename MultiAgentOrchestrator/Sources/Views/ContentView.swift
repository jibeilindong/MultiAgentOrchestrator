import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedTab: Int
    @Binding var zoomScale: CGFloat
    @State private var openClawMessage: String?
    @State private var isConnectingOpenClaw = false
    
    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 250)
            
            Divider()
            
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.currentProject?.name ?? LocalizedString.appName)
                            .font(.headline)
                        Text(projectSummary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(minWidth: 190, alignment: .leading)

                    TopToolbarGroup {
                        Menu {
                            Button(action: { appState.createNewProject() }) {
                                Label(LocalizedString.new, systemImage: "plus")
                            }
                            Button(action: { appState.saveProject() }) {
                                Label(LocalizedString.save, systemImage: "square.and.arrow.down")
                            }
                            Divider()
                            Button(action: { appState.importData() }) {
                                Label("Import", systemImage: "square.and.arrow.down.on.square")
                            }
                            Button(action: { appState.exportData() }) {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            if appState.currentProject != nil {
                                Divider()
                                Button(action: { appState.closeProject() }) {
                                    Label("Close Project", systemImage: "xmark.circle")
                                }
                            }
                        } label: {
                            Label("File", systemImage: "doc")
                        }

                        Button(action: { appState.saveProject() }) {
                            Label(LocalizedString.save, systemImage: "square.and.arrow.down")
                        }
                    }

                    TopToolbarGroup {
                        Menu {
                            Button("Zoom Out") {
                                zoomScale = max(zoomScale / 1.25, 0.25)
                            }
                            Button("Reset Zoom") {
                                zoomScale = 1.0
                            }
                            Button("Zoom In") {
                                zoomScale = min(zoomScale * 1.25, 3.0)
                            }
                            Divider()
                            Button(appState.showLogs ? "Hide Logs" : "Show Logs") {
                                appState.showLogs.toggle()
                            }
                        } label: {
                            Label("View", systemImage: "eye")
                        }

                        HStack(spacing: 4) {
                            Button(action: { zoomScale = max(zoomScale / 1.25, 0.25) }) {
                                Image(systemName: "minus.magnifyingglass")
                            }
                            Text("\(Int(zoomScale * 100))%")
                                .font(.caption)
                                .frame(width: 44)
                            Button(action: { zoomScale = min(zoomScale * 1.25, 3.0) }) {
                                Image(systemName: "plus.magnifyingglass")
                            }
                        }
                    }

                    TopToolbarGroup {
                        Menu {
                            statusMenuRow

                            Divider()

                            if appState.openClawManager.isConnected {
                                Button(action: { appState.openClawManager.disconnect() }) {
                                    Label("Disconnect", systemImage: "link.badge.minus")
                                }
                                Button(action: { addOpenClawAgentsToProject() }) {
                                    Label("Add Agents to Project", systemImage: "person.badge.plus")
                                }
                            } else {
                                Button(action: { autoDetectAndConnect() }) {
                                    Label("Auto Detect & Connect", systemImage: "antenna.radiowaves.left.and.right")
                                }
                            }

                            Divider()

                            Button(action: { NotificationCenter.default.post(name: .openSettings, object: nil) }) {
                                Label(LocalizedString.settings, systemImage: "gear")
                            }
                        } label: {
                            Label("OpenClaw", systemImage: "bolt.horizontal.circle")
                        }
                    }

                    TopToolbarGroup {
                        Menu {
                            ForEach(AppLanguage.allCases) { language in
                                Button(action: { appState.localizationManager.setLanguage(language) }) {
                                    HStack {
                                        Text(language.displayName)
                                        if appState.localizationManager.currentLanguage == language {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "globe")
                                Text(appState.localizationManager.currentLanguage == .simplifiedChinese ? "简体" : "EN")
                            }
                        }
                    }

                    Spacer(minLength: 12)

                    Picker("", selection: $selectedTab) {
                        Label(LocalizedString.workflow, systemImage: "square.grid.2x2").tag(0)
                        Label(LocalizedString.tasks, systemImage: "square.stack.3d.up").tag(1)
                        Label(LocalizedString.dashboard, systemImage: "chart.bar").tag(2)
                        Label(LocalizedString.controlPanel, systemImage: "gearshape.2").tag(3)
                        Label(LocalizedString.permissions, systemImage: "lock.shield").tag(4)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 500)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.windowBackgroundColor))
                
                Divider()
                
                Group {
                    switch selectedTab {
                    case 0: WorkflowEditorView(zoomScale: $zoomScale)
                    case 1: KanbanView()
                    case 2: TaskDashboardView(taskManager: appState.taskManager)
                    case 3: ControlPanelView()
                    case 4: PermissionsView()
                    default: WorkflowEditorView(zoomScale: $zoomScale)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            Divider()
            
            PropertiesPanelView()
                .frame(width: 250)
        }
        .overlay(alignment: .bottom) {
            if isConnectingOpenClaw {
                HStack {
                    ProgressView()
                    Text(LocalizedString.connectingToOpenClaw)
                        .font(.caption)
                }
                .padding()
                .background(Color(.windowBackgroundColor).opacity(0.95))
                .cornerRadius(8)
                .padding(.bottom)
            }
        }
        .alert("OpenClaw", isPresented: Binding(
            get: { openClawMessage != nil },
            set: { if !$0 { openClawMessage = nil } }
        )) {
            Button("OK") { }
        } message: {
            Text(openClawMessage ?? "")
        }
    }

    private var projectSummary: String {
        let agentCount = appState.currentProject?.agents.count ?? 0
        let workflowCount = appState.currentProject?.workflows.count ?? 0
        let edgeCount = appState.currentProject?.workflows.first?.edges.count ?? 0
        return "\(agentCount) agents • \(workflowCount) workflows • \(edgeCount) routes"
    }

    private var statusMenuRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appState.openClawManager.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(appState.openClawManager.isConnected ? "Connected" : "Disconnected")
        }
        .padding(.vertical, 4)
    }
    
    private func autoDetectAndConnect() {
        let paths = ["/Users/chenrongze/.local/bin/openclaw", "/usr/local/bin/openclaw"]
        var found = false
        for p in paths {
            if FileManager.default.fileExists(atPath: p) { found = true; break }
        }
        if !found {
            openClawMessage = "OpenClaw not found!"
            return
        }
        isConnectingOpenClaw = true
        appState.openClawManager.connect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.isConnectingOpenClaw = false
            if self.appState.openClawManager.isConnected {
                self.openClawMessage = "Connected! Found \(self.appState.openClawManager.agents.count) agents."
            } else {
                self.openClawMessage = "Connection failed."
            }
        }
    }
    
    private func addOpenClawAgentsToProject() {
        guard var project = appState.currentProject else {
            openClawMessage = "Please create or open a project first."
            return
        }
        for name in appState.openClawManager.agents {
            if !project.agents.contains(where: { $0.name == name }) {
                var agent = Agent(name: name)
                agent.description = "OpenClaw Agent: \(name)"
                project.agents.append(agent)
            }
        }
        appState.currentProject = project
        openClawMessage = "Added \(appState.openClawManager.agents.count) agents."
    }
}

private struct TopToolbarGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) {
            content
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
