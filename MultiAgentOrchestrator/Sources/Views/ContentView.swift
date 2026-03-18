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
}
