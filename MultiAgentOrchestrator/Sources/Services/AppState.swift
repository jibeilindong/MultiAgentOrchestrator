//
//  AppState.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

// 项目文件管理器
class ProjectManager: ObservableObject {
    static let shared = ProjectManager()
    
    @Published var projects: [String] = []  // 项目名称列表
    
    var projectsDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("MultiAgentOrchestrator", isDirectory: true)
    }
    
    var backupsDirectory: URL {
        return projectsDirectory.appendingPathComponent("backups", isDirectory: true)
    }
    
    private init() {
        createDirectoriesIfNeeded()
        loadProjectList()
    }
    
    func createDirectoriesIfNeeded() {
        try? FileManager.default.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
    }
    
    func loadProjectList() {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: nil) else {
            projects = []
            return
        }
        projects = contents
            .filter { $0.pathExtension == "maoproj" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }
    
    func projectURL(for name: String) -> URL {
        return projectsDirectory.appendingPathComponent("\(name).maoproj")
    }
    
    func createProject(name: String) -> MAProject {
        var project = MAProject(name: name)
        // 添加示例Agent
        var agent1 = Agent(name: "Research Assistant")
        agent1.description = "Helps with research tasks"
        agent1.soulMD = "# Research Assistant\nYou are a research assistant."
        var agent2 = Agent(name: "Writer Agent")
        agent2.description = "Writes reports and documents"
        agent2.soulMD = "# Writer Agent\nYou are a writer."
        var agent3 = Agent(name: "Analyst Agent")
        agent3.description = "Analyzes data and provides insights"
        agent3.soulMD = "# Analyst Agent\nYou analyze data."
        project.agents = [agent1, agent2, agent3]
        
        // 保存到文件
        saveProject(project)
        loadProjectList()
        return project
    }
    
    func saveProject(_ project: MAProject) {
        let url = projectURL(for: project.name)
        do {
            let data = try JSONEncoder().encode(project)
            try data.write(to: url)
        } catch {
            print("保存项目失败: \(error)")
        }
    }
    
    func loadProject(name: String) -> MAProject? {
        let url = projectURL(for: name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MAProject.self, from: data)
    }
    
    func deleteProject(name: String) {
        let url = projectURL(for: name)
        try? FileManager.default.removeItem(at: url)
        loadProjectList()
    }
}

class AppState: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    
    // 项目管理器
    let projectManager = ProjectManager.shared
    
    // OpenClaw管理器
    let openClawManager = OpenClawManager.shared
    
    // 本地化管理器
    @Published var localizationManager = LocalizationManager.shared
    
    @Published var currentProject: MAProject? {
        willSet {
            objectWillChange.send()
        }
    }
    
    // 选中的节点ID
    @Published var selectedNodeID: UUID?
    
    // 任务管理器
    @Published var taskManager = TaskManager()
    
    // 导入导出服务
    let importExportService = ImportExportService.shared
    
    // 消息管理器
    @Published var messageManager = MessageManager()
    
    // OpenClaw 执行服务
    @Published var openClawService = OpenClawService()
    
    // 自动保存定时器
    private var autoSaveTimer: Timer?
    private let autoSaveInterval: TimeInterval = 60 // 每60秒自动保存
    @Published var autoSaveEnabled: Bool = true
    @Published var lastAutoSaveTime: Date?
    @Published var isAutoSaving: Bool = false
    
    init() {
        createNewProject()
        startAutoSave()
    }
    
    deinit {
        stopAutoSave()
    }
    
    // 自动保存功能
    func startAutoSave() {
        stopAutoSave()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: autoSaveInterval, repeats: true) { [weak self] _ in
            self?.performAutoSave()
        }
    }
    
    func stopAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
    }
    
    private func performAutoSave() {
        guard autoSaveEnabled, currentProject != nil else { return }
        
        isAutoSaving = true
        
        // 保存到用户默认目录
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let projectDir = appSupport.appendingPathComponent("MultiAgentOrchestrator/AutoSave")
        
        do {
            try fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)
            
            let fileName = "autosave_\(currentProject?.id.uuidString.prefix(8) ?? "project").maoproj"
            let fileURL = projectDir.appendingPathComponent(fileName)
            
            let data = try JSONEncoder().encode(currentProject)
            try data.write(to: fileURL)
            
            lastAutoSaveTime = Date()
            print("自动保存成功: \(fileURL.path)")
        } catch {
            print("自动保存失败: \(error)")
        }
        
        isAutoSaving = false
    }
    
    // 加载自动保存的项目
    func loadAutoSavedProject() -> MAProject? {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let projectDir = appSupport.appendingPathComponent("MultiAgentOrchestrator/AutoSave")
        
        do {
            let files = try fileManager.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey])
            let latestFile = files.filter { $0.pathExtension == "maoproj" }
                .sorted { (url1: URL, url2: URL) in
                    let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                    return date1 > date2
                }
                .first
            
            if let latestFile = latestFile {
                let data = try Data(contentsOf: latestFile)
                return try JSONDecoder().decode(MAProject.self, from: data)
            }
        } catch {
            print("加载自动保存失败: \(error)")
        }
        
        return nil
    }
    
    func createNewProject() {
        // 生成新项目名称
        let baseName = "New Project"
        var projectName = baseName
        var counter = 1
        while projectManager.projects.contains(projectName) {
            counter += 1
            projectName = "\(baseName) \(counter)"
        }
        
        // 使用ProjectManager创建项目
        currentProject = projectManager.createProject(name: projectName)
        
        // 从工作流生成示例任务
        generateTasksFromWorkflow()
    }
    
    func saveProject() {
        guard let project = currentProject else { return }
        
        // 使用ProjectManager保存到Documents目录
        projectManager.saveProject(project)
        
        // 刷新项目列表
        projectManager.loadProjectList()
    }
    
    func loadProject() {
        // 显示项目选择菜单
        // 这里可以显示一个Alert让用户选择项目
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "maoproj") ?? .json]
        panel.directoryURL = projectManager.projectsDirectory
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    let data = try Data(contentsOf: url)
                    let project = try JSONDecoder().decode(MAProject.self, from: data)
                    self.currentProject = project
                } catch {
                    print("加载失败: \(error)")
                }
            }
        }
    }
    
    // 工作流操作方法
    func getWorkflow(_ id: UUID) -> Workflow? {
        return currentProject?.workflows.first { $0.id == id }
    }
    
    func updateWorkflow(_ workflow: Workflow) {
        guard let index = currentProject?.workflows.firstIndex(where: { $0.id == workflow.id }) else { return }
        currentProject?.workflows[index] = workflow
        objectWillChange.send()
        
        // 当工作流更新时，重新生成任务
        generateTasksFromWorkflow()
    }
    
    func getAgent(for node: WorkflowNode) -> Agent? {
        guard let agentID = node.agentID else { return nil }
        return currentProject?.agents.first { $0.id == agentID }
    }
    
    // 节点选择
    func selectNode(_ nodeID: UUID?) {
        selectedNodeID = nodeID
    }
    
    // 从工作流生成任务
    func generateTasksFromWorkflow() {
        guard let workflow = currentProject?.workflows.first,
              let agents = currentProject?.agents else { return }
        
        taskManager.generateTasks(from: workflow, projectAgents: agents)
    }
    
    // 获取Agent的任务统计
    func getAgentTaskStats(_ agentID: UUID) -> (total: Int, active: Int, completed: Int) {
        let agentTasks = taskManager.tasks(for: agentID)
        let total = agentTasks.count
        let active = agentTasks.filter { $0.isActive }.count
        let completed = agentTasks.filter { $0.isCompleted }.count
        
        return (total, active, completed)
    }
    
    // 获取未分配的任务
    func unassignedTasks() -> [Task] {
        taskManager.tasks.filter { $0.assignedAgentID == nil }
    }
    
    // 模拟执行任务
    func simulateTaskExecution(_ taskID: UUID) {
        taskManager.simulateTaskExecution(taskID) { success in
            if success {
                print("任务执行完成: \(taskID)")
            }
        }
    }
    
    // ========== 菜单操作支持方法 ==========
    
    // 显示日志面板
    @Published var showLogs: Bool = false
    
    // 导入数据
    func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Select Multi-Agent Architecture file"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                if let data = self.importExportService.loadFromFile(url),
                   let (project, tasks, openClawMapping) = self.importExportService.importProject(from: data) {
                    self.currentProject = project
                    // 导入任务
                    for task in tasks {
                        self.taskManager.addTask(task)
                    }
                    print("导入成功: \(project.name), \(project.agents.count) agents, \(tasks.count) tasks")
                } else {
                    print("导入失败: Invalid file format")
                }
            }
        }
    }
    
    // 导出数据
    func exportData() {
        guard let project = currentProject else { return }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(project.name)-architecture.json"
        panel.message = "Export Multi-Agent Architecture"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                // 收集OpenClaw映射
                let openClawMapping: [UUID: String] = [:]
                
                if let data = self.importExportService.exportProject(
                    project,
                    tasks: self.taskManager.tasks,
                    openClawMapping: openClawMapping
                ) {
                    do {
                        try data.write(to: url)
                        print("导出成功: \(url.lastPathComponent)")
                    } catch {
                        print("导出失败: \(error)")
                    }
                }
            }
        }
    }
    
    // 添加新 Agent
    func addNewAgent() {
        guard var project = currentProject else { return }
        var newAgent = Agent(name: "New Agent")
        newAgent.description = "Description"
        project.agents.append(newAgent)
        currentProject = project
        objectWillChange.send()
    }
    
    // 添加新节点
    func addNewNode() {
        guard var project = currentProject,
              var workflow = project.workflows.first else { return }
        
        var newNode = WorkflowNode(type: .agent)
        newNode.position = CGPoint(x: 200, y: 200)
        workflow.nodes.append(newNode)
        
        if let index = project.workflows.firstIndex(where: { $0.id == workflow.id }) {
            project.workflows[index] = workflow
            currentProject = project
        }
        objectWillChange.send()
        
        generateTasksFromWorkflow()
    }
    
    // 显示帮助
    func showHelp() {
        if let url = URL(string: "https://github.com/chenrongze/MultiAgentOrchestrator#readme") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // 显示键盘快捷键
    func showKeyboardShortcuts() {
        print("显示键盘快捷键...")
    }
}
