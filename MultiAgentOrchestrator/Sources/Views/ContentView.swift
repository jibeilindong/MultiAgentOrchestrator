import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedTab: Int
    @Binding var zoomScale: CGFloat
    
    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 250)
            
            Divider()
            
            VStack(spacing: 0) {
                HStack {
                    Text(appState.currentProject?.name ?? LocalizedString.appName)
                        .font(.headline)
                        .padding(.leading)
                    
                    Spacer()
                    
                    Picker("", selection: $selectedTab) {
                        Label(LocalizedString.workflow, systemImage: "square.grid.2x2").tag(0)
                        Label(LocalizedString.tasks, systemImage: "square.stack.3d.up").tag(1)
                        Label(LocalizedString.dashboard, systemImage: "chart.bar").tag(2)
                        Label(LocalizedString.controlPanel, systemImage: "gearshape.2").tag(3)
                        Label(LocalizedString.permissions, systemImage: "lock.shield").tag(4)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 500)
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        // 缩放控制
                        HStack(spacing: 4) {
                            Button(action: { zoomScale = max(zoomScale / 1.25, 0.25) }) {
                                Image(systemName: "minus.magnifyingglass")
                            }
                            .help(LocalizedString.zoomOut)
                            
                            Text("\(Int(zoomScale * 100))%")
                                .font(.caption)
                                .frame(width: 40)
                            
                            Button(action: { zoomScale = min(zoomScale * 1.25, 3.0) }) {
                                Image(systemName: "plus.magnifyingglass")
                            }
                            .help(LocalizedString.zoomIn)
                            
                            Button(action: { zoomScale = 1.0 }) {
                                Image(systemName: "1.magnifyingglass")
                            }
                            .help(LocalizedString.resetZoom)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(6)
                        
                        Menu {
                            ForEach(AppLanguage.allCases) { language in
                                Button(action: {
                                    appState.localizationManager.setLanguage(language)
                                }) {
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
                                Text(appState.localizationManager.currentLanguage == .simplifiedChinese ? "简" : (appState.localizationManager.currentLanguage == .traditionalChinese ? "繁" : "EN"))
                            }
                        }
                        .help(LocalizedString.switchLanguage)
                        .menuStyle(.borderlessButton)
                        .frame(width: 40)
                        
                        // Tools 菜单
                        Menu {
                            // OpenClaw连接状态
                            HStack {
                                Image(systemName: appState.openClawManager.isConnected ? "checkmark.circle.fill" : "circle.slash")
                                    .foregroundColor(appState.openClawManager.isConnected ? .green : .red)
                                Text(appState.openClawManager.isConnected ? "Connected (\(appState.openClawManager.agents.count) agents)" : "Disconnected")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                            
                            Divider()
                            
                            // 连接/断开
                            if appState.openClawManager.isConnected {
                                Button(action: {
                                    appState.openClawManager.disconnect()
                                }) {
                                    Label("Disconnect OpenClaw", systemImage: "link.badge.minus")
                                }
                                
                                Divider()
                                
                                // 添加Agents到项目
                                Button(action: {
                                    addOpenClawAgentsToProject()
                                }) {
                                    Label("Add Agents to Project", systemImage: "person.badge.plus")
                                }
                                
                                Divider()
                                
                                // 应用配置到OpenClaw
                                Button(action: {
                                    if let agents = appState.currentProject?.agents {
                                        _ = appState.openClawManager.applyConfiguration(agents: agents)
                                    }
                                }) {
                                    Label("Apply Configuration", systemImage: "arrow.up.doc")
                                }
                                
                                // 还原配置
                                Menu {
                                    ForEach(appState.openClawManager.listBackups(), id: \.self) { backup in
                                        Button(action: {
                                            _ = appState.openClawManager.restore(backupPath: backup)
                                        }) {
                                            Text(backup.lastPathComponent)
                                        }
                                    }
                                } label: {
                                    Label("Restore Backup", systemImage: "arrow.down.doc")
                                }
                            } else {
                                // 自动检测并连接
                                Button(action: {
                                    autoDetectAndConnect()
                                }) {
                                    Label("Auto Detect & Connect", systemImage: "antenna.radiowaves.left.and.right")
                                }
                                
                                Button(action: {
                                    appState.openClawManager.connect()
                                }) {
                                    Label("Manual Connect", systemImage: "link.badge.plus")
                                }
                            }
                            
                            Divider()
                            
                            // OpenClaw设置
                            Button(action: {
                                NotificationCenter.default.post(name: .openSettings, object: nil)
                            }) {
                                Label("OpenClaw Settings", systemImage: "gear")
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "wrench.and.screwdriver")
                                Text("Tools")
                            }
                        }
                        .help("Tools")
                        .menuStyle(.borderlessButton)
                        .frame(width: 60)
                        
                        Button(action: { appState.createNewProject() }) {
                            Label(LocalizedString.new, systemImage: "plus")
                        }
                        .help(LocalizedString.newProject)
                        
                        Button(action: { appState.saveProject() }) {
                            Label(LocalizedString.save, systemImage: "square.and.arrow.down")
                        }
                        .help(LocalizedString.saveProject)
                    }
                    .padding(.trailing)
                }
                .padding(.vertical, 8)
                .background(Color(.windowBackgroundColor))
                
                Divider()
                
                Group {
                    switch selectedTab {
                    case 0:
                        WorkflowEditorView(zoomScale: $zoomScale)
                    case 1:
                        KanbanView()
                    case 2:
                        TaskDashboardView(taskManager: appState.taskManager)
                    case 3:
                        ControlPanelView()
                    case 4:
                        PermissionsView()
                    default:
                        WorkflowEditorView(zoomScale: $zoomScale)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            Divider()
            
            PropertiesPanelView()
                .frame(width: 250)
        }
    }
    
    // 将OpenClaw agents添加到当前项目
    private func addOpenClawAgentsToProject() {
        guard var project = appState.currentProject else { return }
        
        for agentName in appState.openClawManager.agents {
            // 检查是否已存在
            if !project.agents.contains(where: { $0.name == agentName }) {
                var agent = Agent(name: agentName)
                agent.description = "OpenClaw Agent: \(agentName)"
                agent.soulMD = "# \(agentName)\nOpenClaw Agent"
                project.agents.append(agent)
            }
        }
        
        appState.currentProject = project
    }

    // 自动检测OpenClaw并连接
    private func autoDetectAndConnect() {
        print("Auto Detect OpenClaw starting...")
        
        let fileManager = FileManager.default
        let possiblePaths = [
            "/Users/chenrongze/.local/bin/openclaw",
            "/usr/local/bin/openclaw",
            "/opt/homebrew/bin/openclaw", 
            "/usr/bin/openclaw"
        ]
        
        var foundPath: String?
        for path in possiblePaths {
            if fileManager.fileExists(atPath: path) {
                foundPath = path
                print("Found OpenClaw at: \(path)")
                break
            }
        }
        
        if foundPath == nil {
            print("OpenClaw not found in any location!")
        }
        
        // 无论如何都尝试连接
        print("Calling connect...")
        appState.openClawManager.connect()
    }
}
