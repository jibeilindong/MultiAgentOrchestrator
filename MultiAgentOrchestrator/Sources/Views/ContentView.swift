import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    
    var body: some View {
        // 使用简单的三栏布局，不需要 NavigationView
        HStack(spacing: 0) {
            // 左侧边栏
            SidebarView()
                .frame(width: 250)
            
            Divider()
            
            // 主画布区域
            VStack(spacing: 0) {
                // 标题栏
                HStack {
                    Text(appState.currentProject?.name ?? "MultiAgent Orchestrator")
                        .font(.headline)
                        .padding(.leading)
                    
                    Spacer()
                    
                    // 标签选择器
                    Picker("", selection: $selectedTab) {
                        Label("Workflow", systemImage: "square.grid.2x2").tag(0)
                        Label("Tasks", systemImage: "square.stack.3d.up").tag(1)
                        Label("Dashboard", systemImage: "chart.bar").tag(2)
                        Label("Control", systemImage: "gearshape.2").tag(3)
                        Label("Permissions", systemImage: "lock.shield").tag(4)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 500)
                    
                    Spacer()
                    
                    // 窗口控制按钮
                    HStack(spacing: 8) {
                        Button(action: { appState.createNewProject() }) {
                            Label("New", systemImage: "plus")
                        }
                        .help("Create new project")
                        
                        Button(action: { appState.saveProject() }) {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                        .help("Save project")
                    }
                    .padding(.trailing)
                }
                .padding(.vertical, 8)
                .background(Color(.windowBackgroundColor))
                
                Divider()
                
                // 根据选中的标签显示对应的视图
                Group {
                    switch selectedTab {
                    case 0:
                        CanvasView()
                    case 1:
                        KanbanView()
                    case 2:
                        TaskDashboardView(taskManager: appState.taskManager)
                    case 3:
                        ControlPanelView()
                    case 4:
                        PermissionsView()
                    default:
                        CanvasView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            Divider()
            
            // 右侧属性面板
            PropertiesPanelView()
                .frame(width: 250)
        }
    }
}
