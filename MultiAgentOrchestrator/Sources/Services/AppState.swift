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

enum CanvasColorPreset: String, CaseIterable, Codable, Identifiable {
    case blue
    case graphite
    case green
    case orange
    case red
    case primary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: return "蓝"
        case .graphite: return "石墨"
        case .green: return "绿"
        case .orange: return "橙"
        case .red: return "红"
        case .primary: return "默认"
        }
    }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .graphite: return .gray
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .primary: return .primary
        }
    }
}

struct CanvasDisplaySettings: Codable {
    var lineWidth: CGFloat = 2
    var textScale: CGFloat = 1
    var lineColor: CanvasColorPreset = .blue
    var textColor: CanvasColorPreset = .primary
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
    @Published var canvasDisplaySettings = CanvasDisplaySettings()
    
    // 自动保存定时器
    private var autoSaveTimer: Timer?
    private let autoSaveInterval: TimeInterval = 60 // 每60秒自动保存
    @Published var autoSaveEnabled: Bool = true
    @Published var lastAutoSaveTime: Date?
    @Published var isAutoSaving: Bool = false
    
    init() {
        // 不自动创建项目，让用户手动创建
        // createNewProject()
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
    
    // 关闭当前项目
    func closeProject() {
        currentProject = nil
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

    @discardableResult
    func ensureMainWorkflow() -> Workflow? {
        guard var project = currentProject else { return nil }
        if project.workflows.isEmpty {
            project.workflows.append(Workflow(name: "Main Workflow"))
            project.updatedAt = Date()
            currentProject = project
        }
        return currentProject?.workflows.first
    }
    
    func updateWorkflow(_ workflow: Workflow) {
        guard let index = currentProject?.workflows.firstIndex(where: { $0.id == workflow.id }) else { return }
        currentProject?.workflows[index] = workflow
        currentProject?.updatedAt = Date()
        objectWillChange.send()
        
        // 当工作流更新时，重新生成任务
        generateTasksFromWorkflow()
    }

    func updateMainWorkflow(_ updates: (inout Workflow) -> Void) {
        guard ensureMainWorkflow() != nil,
              var project = currentProject,
              let index = project.workflows.indices.first else { return }

        updates(&project.workflows[index])
        project.updatedAt = Date()
        currentProject = project
        objectWillChange.send()
        generateTasksFromWorkflow()
    }

    @discardableResult
    func ensureAgent(named name: String, description: String? = nil) -> Agent? {
        guard var project = currentProject else { return nil }

        if let existing = project.agents.first(where: { $0.name == name }) {
            return existing
        }

        var agent = Agent(name: name)
        if let description {
            agent.description = description
        }
        project.agents.append(agent)
        project.updatedAt = Date()
        currentProject = project
        objectWillChange.send()
        return agent
    }
    
    func getAgent(for node: WorkflowNode) -> Agent? {
        guard let agentID = node.agentID else { return nil }
        return currentProject?.agents.first { $0.id == agentID }
    }
    
    // 节点选择
    func selectNode(_ nodeID: UUID?) {
        selectedNodeID = nodeID
    }

    func addNode(type: WorkflowNode.NodeType, position: CGPoint) {
        updateMainWorkflow { workflow in
            var node = WorkflowNode(type: type)
            node.position = position
            if type == .branch {
                node.title = "Branch"
                node.conditionExpression = "workflow.hasAgents == true"
                node.maxIterations = 2
            }
            workflow.nodes.append(node)
        }
    }

    func addAgentNode(agentName: String, position: CGPoint) {
        guard let agent = ensureAgent(named: agentName, description: "OpenClaw Agent: \(agentName)") else { return }

        updateMainWorkflow { workflow in
            var node = WorkflowNode(type: .agent)
            node.agentID = agent.id
            node.position = position
            node.title = agent.name
            workflow.nodes.append(node)
        }
        openClawManager.activateAgent(agent)
    }

    func removeNodes(_ nodeIDs: Set<UUID>) {
        guard !nodeIDs.isEmpty else { return }

        let removedAgentIDs = Set((currentProject?.workflows.first?.nodes ?? [])
            .filter { nodeIDs.contains($0.id) }
            .compactMap(\.agentID))

        updateMainWorkflow { workflow in
            workflow.nodes.removeAll { nodeIDs.contains($0.id) }
            workflow.edges.removeAll { nodeIDs.contains($0.fromNodeID) || nodeIDs.contains($0.toNodeID) }
        }

        removedAgentIDs.forEach(openClawManager.terminateAgent)
    }

    func removeNode(_ nodeID: UUID) {
        removeNodes([nodeID])
    }

    func removeEdge(_ edgeID: UUID) {
        updateMainWorkflow { workflow in
            workflow.edges.removeAll { $0.id == edgeID }
        }
    }

    func addEdge(
        from fromNodeID: UUID,
        to toNodeID: UUID,
        label: String = "",
        conditionExpression: String = "",
        requiresApproval: Bool = false,
        bidirectional: Bool = false
    ) {
        guard fromNodeID != toNodeID else { return }

        updateMainWorkflow { workflow in
            var edge = WorkflowEdge(from: fromNodeID, to: toNodeID)
            edge.label = label
            edge.conditionExpression = conditionExpression
            edge.requiresApproval = requiresApproval
            workflow.edges.append(edge)

            if bidirectional {
                var reverse = WorkflowEdge(from: toNodeID, to: fromNodeID)
                reverse.label = label
                reverse.conditionExpression = conditionExpression
                reverse.requiresApproval = requiresApproval
                workflow.edges.append(reverse)
            }
        }
    }

    @discardableResult
    func ensureAgentNode(agentID: UUID, suggestedPosition: CGPoint = CGPoint(x: 0, y: 0)) -> UUID? {
        guard let workflow = ensureMainWorkflow() else { return nil }

        if let existingNode = workflow.nodes.first(where: { $0.agentID == agentID && $0.type == .agent }) {
            return existingNode.id
        }

        var createdNodeID: UUID?
        updateMainWorkflow { workflow in
            if let existingNode = workflow.nodes.first(where: { $0.agentID == agentID && $0.type == .agent }) {
                createdNodeID = existingNode.id
                return
            }

            var newNode = WorkflowNode(type: .agent)
            newNode.agentID = agentID
            newNode.position = suggestedPosition
            createdNodeID = newNode.id
            workflow.nodes.append(newNode)
        }

        return createdNodeID
    }

    func connectNodes(from sourceNodeID: UUID, to targetNodeID: UUID, bidirectional: Bool = false) {
        guard let project = currentProject,
              let workflow = project.workflows.first,
              let sourceNode = workflow.nodes.first(where: { $0.id == sourceNodeID }),
              let targetNode = workflow.nodes.first(where: { $0.id == targetNodeID }) else { return }

        updateMainWorkflow { workflow in
            appendEdgeIfNeeded(from: sourceNodeID, to: targetNodeID, workflow: &workflow)
            if bidirectional {
                appendEdgeIfNeeded(from: targetNodeID, to: sourceNodeID, workflow: &workflow)
            }
        }

        if let sourceAgentID = sourceNode.agentID, let targetAgentID = targetNode.agentID {
            setPermission(fromAgentID: sourceAgentID, toAgentID: targetAgentID, type: .allow)
            if bidirectional {
                setPermission(fromAgentID: targetAgentID, toAgentID: sourceAgentID, type: .allow)
            }
        }
    }

    func updateNode(_ nodeID: UUID, updates: (inout WorkflowNode) -> Void) {
        updateMainWorkflow { workflow in
            guard let index = workflow.nodes.firstIndex(where: { $0.id == nodeID }) else { return }
            updates(&workflow.nodes[index])
        }
    }

    func updateNode(_ updatedNode: WorkflowNode) {
        updateMainWorkflow { workflow in
            guard let index = workflow.nodes.firstIndex(where: { $0.id == updatedNode.id }) else { return }
            workflow.nodes[index] = updatedNode
        }
    }

    func updateEdge(_ edgeID: UUID, updates: (inout WorkflowEdge) -> Void) {
        updateMainWorkflow { workflow in
            guard let index = workflow.edges.firstIndex(where: { $0.id == edgeID }) else { return }
            updates(&workflow.edges[index])
        }
    }

    func updateEdge(_ updatedEdge: WorkflowEdge) {
        updateMainWorkflow { workflow in
            guard let index = workflow.edges.firstIndex(where: { $0.id == updatedEdge.id }) else { return }
            workflow.edges[index] = updatedEdge
        }
    }

    func updateAgent(_ updatedAgent: Agent, reload: Bool = false) {
        guard var project = currentProject,
              let index = project.agents.firstIndex(where: { $0.id == updatedAgent.id }) else { return }

        project.agents[index] = updatedAgent
        project.updatedAt = Date()
        currentProject = project
        objectWillChange.send()

        if reload {
            reloadAgent(updatedAgent.id)
        }
    }

    func reloadAgent(_ agentID: UUID) {
        guard let agent = currentProject?.agents.first(where: { $0.id == agentID }) else { return }
        openClawManager.reloadAgent(agent)
        openClawService.reloadAgent(agent) { [weak self] success, message in
            guard let self else { return }
            DispatchQueue.main.async {
                self.currentProject?.runtimeState.agentStates[agentID.uuidString] = success ? "reloaded" : "reload_failed"
                self.currentProject?.runtimeState.lastUpdated = Date()
                self.openClawService.addLog(success ? .success : .error, message)
                self.objectWillChange.send()
            }
        }
    }

    func setPermission(fromAgentID: UUID, toAgentID: UUID, type: PermissionType) {
        guard var project = currentProject else { return }

        if let index = project.permissions.firstIndex(where: {
            $0.fromAgentID == fromAgentID && $0.toAgentID == toAgentID
        }) {
            project.permissions[index].permissionType = type
            project.permissions[index].updatedAt = Date()
        } else {
            project.permissions.append(
                Permission(fromAgentID: fromAgentID, toAgentID: toAgentID, permissionType: type)
            )
        }

        project.updatedAt = Date()
        currentProject = project
        objectWillChange.send()
    }

    private func appendEdgeIfNeeded(from sourceNodeID: UUID, to targetNodeID: UUID, workflow: inout Workflow) {
        let edgeExists = workflow.edges.contains {
            $0.fromNodeID == sourceNodeID && $0.toNodeID == targetNodeID
        }

        if !edgeExists {
            workflow.edges.append(WorkflowEdge(from: sourceNodeID, to: targetNodeID))
        }
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
