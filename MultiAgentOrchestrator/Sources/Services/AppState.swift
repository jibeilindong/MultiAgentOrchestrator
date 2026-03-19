//
//  AppState.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

extension UTType {
    static let maoproject = UTType(filenameExtension: "maoproj") ?? .json
}

struct ProjectFileReference: Identifiable, Hashable {
    var id: String { url.path }
    let name: String
    let url: URL
}

// 项目文件管理器
class ProjectManager: ObservableObject {
    static let shared = ProjectManager()
    
    @Published var projects: [ProjectFileReference] = []
    
    var projectsDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("MultiAgentOrchestrator", isDirectory: true)
    }
    
    var backupsDirectory: URL {
        return projectsDirectory.appendingPathComponent("backups", isDirectory: true)
    }

    var defaultWorkspaceRootDirectory: URL {
        let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupportPath.appendingPathComponent("MultiAgentOrchestrator/Workspaces", isDirectory: true)
    }
    
    private init() {
        createDirectoriesIfNeeded()
        loadProjectList()
    }
    
    func createDirectoriesIfNeeded() {
        try? FileManager.default.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: defaultWorkspaceRootDirectory, withIntermediateDirectories: true)
    }
    
    func loadProjectList() {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: nil) else {
            projects = []
            return
        }
        projects = contents
            .filter { $0.pathExtension == "maoproj" }
            .map { ProjectFileReference(name: $0.deletingPathExtension().lastPathComponent, url: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    func projectURL(for name: String) -> URL {
        projectsDirectory.appendingPathComponent("\(name).maoproj")
    }
    
    func saveProject(_ project: MAProject, to url: URL? = nil) throws -> URL {
        let destinationURL = url ?? projectURL(for: project.name)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        try data.write(to: destinationURL, options: .atomic)
        loadProjectList()
        return destinationURL
    }
    
    func loadProject(from url: URL) throws -> MAProject {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(MAProject.self, from: data)
    }
    
    func uniqueProjectName(baseName: String = "New Project") -> String {
        var candidate = baseName
        var counter = 2
        let existingNames = Set(projects.map(\.name))

        while existingNames.contains(candidate) {
            candidate = "\(baseName) \(counter)"
            counter += 1
        }

        return candidate
    }
    
    func relativeWorkspacePath(projectID: UUID, taskID: UUID) -> String {
        "\(projectID.uuidString)/\(taskID.uuidString)"
    }

    func workspaceURL(for relativePath: String) -> URL {
        defaultWorkspaceRootDirectory.appendingPathComponent(relativePath, isDirectory: true)
    }

    func ensureWorkspaceDirectory(relativePath: String) -> URL {
        let url = workspaceURL(for: relativePath)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func deleteProject(at url: URL, projectID: UUID? = nil) {
        try? FileManager.default.removeItem(at: url)
        if let projectID {
            try? FileManager.default.removeItem(
                at: defaultWorkspaceRootDirectory.appendingPathComponent(projectID.uuidString, isDirectory: true)
            )
        }
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

enum ContentToolbarItem: String, CaseIterable, Codable, Identifiable {
    case file
    case project
    case view
    case display
    case language

    var id: String { rawValue }

    var title: String {
        switch self {
        case .file: return "文件"
        case .project: return "项目信息"
        case .view: return "视图"
        case .display: return "显示控制"
        case .language: return "语言"
        }
    }

    static let defaultOrder: [ContentToolbarItem] = [.file, .project, .display, .view, .language]
}

struct CanvasDisplaySettings: Codable {
    var lineWidth: CGFloat = 2
    var textScale: CGFloat = 1
    var lineColor: CanvasColorPreset = .blue
    var textColor: CanvasColorPreset = .primary
}

class AppState: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    private var cancellables = Set<AnyCancellable>()
    
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
    @Published var currentProjectFileURL: URL?
    
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
    @Published var orderedToolbarItems = ContentToolbarItem.defaultOrder
    @Published var visibleToolbarItems = Set(ContentToolbarItem.defaultOrder)
    
    // 自动保存定时器
    private var autoSaveTimer: Timer?
    private let autoSaveInterval: TimeInterval = 60 // 每60秒自动保存
    @Published var autoSaveEnabled: Bool = true
    @Published var lastAutoSaveTime: Date?
    @Published var isAutoSaving: Bool = false
    
    init() {
        loadToolbarPreferences()
        bindProjectState()
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

    private func bindProjectState() {
        taskManager.$tasks
            .sink { [weak self] _ in
                self?.syncCurrentProjectFromManagers()
            }
            .store(in: &cancellables)

        messageManager.$messages
            .sink { [weak self] _ in
                self?.syncCurrentProjectFromManagers()
            }
            .store(in: &cancellables)

        openClawService.$executionResults
            .sink { [weak self] _ in
                self?.syncCurrentProjectFromManagers()
            }
            .store(in: &cancellables)

        openClawService.$executionLogs
            .sink { [weak self] _ in
                self?.syncCurrentProjectFromManagers()
            }
            .store(in: &cancellables)

        openClawManager.$config
            .sink { [weak self] _ in
                self?.syncCurrentProjectFromManagers()
            }
            .store(in: &cancellables)

        openClawManager.$agents
            .sink { [weak self] _ in
                self?.syncCurrentProjectFromManagers()
            }
            .store(in: &cancellables)

        openClawManager.$activeAgents
            .sink { [weak self] _ in
                self?.syncCurrentProjectFromManagers()
            }
            .store(in: &cancellables)

        openClawManager.$isConnected
            .sink { [weak self] _ in
                self?.syncCurrentProjectFromManagers()
            }
            .store(in: &cancellables)
    }

    private func syncCurrentProjectFromManagers() {
        guard var project = currentProject else { return }

        project.tasks = taskManager.tasks
        project.messages = messageManager.messages
        project.executionResults = openClawService.executionResults
        project.executionLogs = openClawService.executionLogs
        project.openClaw = openClawManager.snapshot()
        project.taskData.lastUpdatedAt = Date()
        project.workspaceIndex = ensureWorkspaceIndex(for: project.id, tasks: taskManager.tasks, existing: project.workspaceIndex)
        project.memoryData = buildMemoryData(project: project)
        project.runtimeState.lastUpdated = Date()
        currentProject = project
    }
    
    private func performAutoSave() {
        guard autoSaveEnabled, let project = snapshotCurrentProject() else { return }
        
        isAutoSaving = true
        
        // 保存到用户默认目录
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let projectDir = appSupport.appendingPathComponent("MultiAgentOrchestrator/AutoSave")
        
        do {
            try fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)
            
            let fileName = "autosave_\(project.id.uuidString.prefix(8)).maoproj"
            let fileURL = projectDir.appendingPathComponent(fileName)
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(project)
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
                return try projectManager.loadProject(from: latestFile)
            }
        } catch {
            print("加载自动保存失败: \(error)")
        }
        
        return nil
    }
    
    func createNewProject() {
        createNewProject(named: projectManager.uniqueProjectName())
    }

    func createNewProject(named projectName: String) {
        let resolvedName: String
        if FileManager.default.fileExists(atPath: projectManager.projectURL(for: projectName).path) {
            resolvedName = projectManager.uniqueProjectName(baseName: projectName)
        } else {
            resolvedName = projectName
        }

        let project = MAProject(name: resolvedName)
        taskManager.reset()
        messageManager.reset()
        openClawService.resetExecutionSnapshot()
        openClawManager.restore(from: project.openClaw)
        currentProject = project

        do {
            currentProjectFileURL = try projectManager.saveProject(project, to: projectManager.projectURL(for: resolvedName))
        } catch {
            print("创建项目失败: \(error)")
            currentProjectFileURL = nil
        }
    }
    
    func saveProject() {
        guard currentProject != nil else { return }

        if let currentProjectFileURL {
            saveProject(to: currentProjectFileURL)
        } else {
            saveProjectAs()
        }
    }

    func saveProjectAs() {
        guard let project = snapshotCurrentProject() else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.maoproject]
        panel.directoryURL = currentProjectFileURL?.deletingLastPathComponent() ?? projectManager.projectsDirectory
        panel.nameFieldStringValue = "\(project.name).maoproj"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            self.saveProject(to: url)
        }
    }

    private func saveProject(to url: URL) {
        guard let project = snapshotCurrentProject() else { return }

        do {
            currentProjectFileURL = try projectManager.saveProject(project, to: url)
            currentProject = project
        } catch {
            print("保存项目失败: \(error)")
        }
    }
    
    // 关闭当前项目
    func closeProject() {
        currentProjectFileURL = nil
        taskManager.reset()
        messageManager.reset()
        openClawService.resetExecutionSnapshot()
        openClawManager.disconnect()
        currentProject = nil
    }
    
    func deleteCurrentProject() {
        guard let project = currentProject, let currentProjectFileURL else { return }
        projectManager.deleteProject(at: currentProjectFileURL, projectID: project.id)
        closeProject()
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.maoproject]
        panel.directoryURL = projectManager.projectsDirectory
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.openProject(at: url)
            }
        }
    }

    func openProject(at url: URL) {
        do {
            let project = try projectManager.loadProject(from: url)
            restoreProject(project, from: url)
        } catch {
            print("加载失败: \(error)")
        }
    }

    func loadProject() {
        openProject()
    }

    private func restoreProject(_ project: MAProject, from url: URL?) {
        currentProjectFileURL = url
        taskManager.replaceTasks(project.tasks)
        messageManager.replaceMessages(project.messages)
        openClawService.restoreExecutionSnapshot(results: project.executionResults, logs: project.executionLogs)
        openClawManager.restore(from: project.openClaw)

        var hydratedProject = project
        hydratedProject.workspaceIndex = ensureWorkspaceIndex(
            for: hydratedProject.id,
            tasks: project.tasks,
            existing: project.workspaceIndex
        )
        currentProject = hydratedProject
    }

    private func snapshotCurrentProject() -> MAProject? {
        guard var project = currentProject else { return nil }

        project.fileVersion = "2.0"
        project.tasks = taskManager.tasks
        project.messages = messageManager.messages
        project.executionResults = openClawService.executionResults
        project.executionLogs = openClawService.executionLogs
        project.openClaw = openClawManager.snapshot()
        project.taskData.lastUpdatedAt = Date()
        project.workspaceIndex = ensureWorkspaceIndex(for: project.id, tasks: taskManager.tasks, existing: project.workspaceIndex)
        project.memoryData = buildMemoryData(project: project)
        project.runtimeState.lastUpdated = Date()
        project.updatedAt = Date()
        return project
    }

    private func ensureWorkspaceIndex(
        for projectID: UUID,
        tasks: [Task],
        existing: [ProjectWorkspaceRecord]
    ) -> [ProjectWorkspaceRecord] {
        let existingByTaskID = Dictionary(uniqueKeysWithValues: existing.map { ($0.taskID, $0) })

        return tasks.map { task in
            let relativePath = existingByTaskID[task.id]?.workspaceRelativePath
                ?? projectManager.relativeWorkspacePath(projectID: projectID, taskID: task.id)
            _ = ensureWorkspaceDirectory(relativePath: relativePath)

            var record = existingByTaskID[task.id] ?? ProjectWorkspaceRecord(
                taskID: task.id,
                workspaceRelativePath: relativePath,
                workspaceName: task.title
            )
            record.workspaceName = task.title
            record.updatedAt = Date()
            return record
        }
        .sorted { $0.workspaceName.localizedCaseInsensitiveCompare($1.workspaceName) == .orderedAscending }
    }

    func absoluteWorkspaceURL(for taskID: UUID) -> URL? {
        guard let project = currentProject else { return nil }

        let workspaceIndex = ensureWorkspaceIndex(for: project.id, tasks: taskManager.tasks, existing: project.workspaceIndex)
        guard let record = workspaceIndex.first(where: { $0.taskID == taskID }) else {
            return nil
        }

        return workspaceRootURL(for: project).appendingPathComponent(record.workspaceRelativePath, isDirectory: true)
    }

    func importProjectData(_ project: MAProject, tasks: [Task]) {
        currentProjectFileURL = nil
        taskManager.replaceTasks(tasks)
        messageManager.reset()
        openClawService.resetExecutionSnapshot()
        currentProject = project
        if let snapshot = snapshotCurrentProject() {
            currentProject = snapshot
        }
    }

    func chooseTaskDataRootDirectory() {
        guard currentProject != nil else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = currentProject.flatMap(workspaceRootURL(for:))
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            self.updateTaskDataRootDirectory(url.path)
        }
    }

    func resetTaskDataRootDirectory() {
        updateTaskDataRootDirectory(nil)
    }

    func updateTaskDataRootDirectory(_ path: String?) {
        guard var project = currentProject else { return }
        project.taskData.workspaceRootPath = path
        project.taskData.lastUpdatedAt = Date()
        currentProject = project
        currentProject?.workspaceIndex = ensureWorkspaceIndex(for: project.id, tasks: taskManager.tasks, existing: project.workspaceIndex)
    }

    func addBoundary(around nodeIDs: Set<UUID>) {
        guard !nodeIDs.isEmpty,
              let workflow = currentProject?.workflows.first else { return }

        let nodes = workflow.nodes.filter { nodeIDs.contains($0.id) }
        guard !nodes.isEmpty else { return }

        let xValues = nodes.map(\.position.x)
        let yValues = nodes.map(\.position.y)
        let minX = (xValues.min() ?? 0) - 110
        let maxX = (xValues.max() ?? 0) + 110
        let minY = (yValues.min() ?? 0) - 80
        let maxY = (yValues.max() ?? 0) + 80

        updateMainWorkflow { workflow in
            var boundary = WorkflowBoundary(
                title: "Boundary \(workflow.boundaries.count + 1)",
                rect: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
                memberNodeIDs: nodes.map(\.id)
            )
            boundary.updatedAt = Date()
            workflow.boundaries.append(boundary)
        }
    }

    func boundary(for nodeID: UUID) -> WorkflowBoundary? {
        currentProject?.workflows.first?.boundary(containing: nodeID)
    }

    private func buildMemoryData(project: MAProject) -> ProjectMemoryData {
        let taskMemories = project.workspaceIndex.map {
            TaskMemoryBackupRecord(
                taskID: $0.taskID,
                workspaceRelativePath: $0.workspaceRelativePath,
                backupLabel: $0.workspaceName,
                lastCapturedAt: $0.updatedAt
            )
        }

        let agentMemories = project.agents.map { agent in
            AgentMemoryBackupRecord(
                agentID: agent.id,
                agentName: agent.name,
                sourcePath: agent.openClawDefinition.memoryBackupPath,
                lastCapturedAt: agent.updatedAt
            )
        }

        return ProjectMemoryData(
            backupOnly: true,
            taskExecutionMemories: taskMemories,
            agentMemories: agentMemories,
            lastBackupAt: Date()
        )
    }

    private func workspaceRootURL(for project: MAProject) -> URL {
        if let configuredPath = project.taskData.workspaceRootPath, !configuredPath.isEmpty {
            let url = URL(fileURLWithPath: configuredPath, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        let url = projectManager.defaultWorkspaceRootDirectory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func ensureWorkspaceDirectory(relativePath: String) -> URL {
        guard let project = currentProject else {
            return projectManager.ensureWorkspaceDirectory(relativePath: relativePath)
        }

        let url = workspaceRootURL(for: project).appendingPathComponent(relativePath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
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
            workflow.boundaries = workflow.boundaries.compactMap { boundary in
                var updated = boundary
                updated.memberNodeIDs.removeAll { nodeIDs.contains($0) }
                updated.updatedAt = Date()
                return updated.memberNodeIDs.isEmpty ? nil : updated
            }
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

    func generateArchitectureFromProjectAgents() {
        guard var project = currentProject,
              var workflow = project.workflows.first else { return }

        workflow.nodes.removeAll()
        workflow.edges.removeAll()

        let agentPositions = calculateAgentPositions(agents: project.agents)
        for (agent, position) in agentPositions {
            var newNode = WorkflowNode(type: .agent)
            newNode.agentID = agent.id
            newNode.position = position
            workflow.nodes.append(newNode)
        }

        let connections = analyzeAndGenerateConnections(agents: project.agents)
        for (fromName, toName) in connections {
            if let fromAgent = project.agents.first(where: { $0.name == fromName }),
               let toAgent = project.agents.first(where: { $0.name == toName }),
               let fromNode = workflow.nodes.first(where: { $0.agentID == fromAgent.id }),
               let toNode = workflow.nodes.first(where: { $0.agentID == toAgent.id }) {
                workflow.edges.append(WorkflowEdge(from: fromNode.id, to: toNode.id))
                project.permissions.append(
                    Permission(fromAgentID: fromAgent.id, toAgentID: toAgent.id, permissionType: .allow)
                )
            }
        }

        if let index = project.workflows.firstIndex(where: { $0.id == workflow.id }) {
            project.workflows[index] = workflow
            project.updatedAt = Date()
            currentProject = project
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

    func workflow(for workflowID: UUID?) -> Workflow? {
        guard let project = currentProject else { return nil }
        if let workflowID {
            return project.workflows.first { $0.id == workflowID }
        }
        return project.workflows.first
    }

    @discardableResult
    func submitWorkbenchPrompt(_ prompt: String, workflowID: UUID? = nil) -> Bool {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty,
              !openClawService.isExecuting,
              let project = currentProject,
              let workflow = self.workflow(for: workflowID) else {
            return false
        }

        let executionPlan = openClawService.executionPlan(for: workflow)
        guard let leadNode = executionPlan.first ?? workflow.nodes.first(where: { $0.type == .agent }),
              let leadAgentID = leadNode.agentID,
              let leadAgent = project.agents.first(where: { $0.id == leadAgentID }) else {
            openClawService.addLog(.error, "Workbench publish failed: workflow has no executable agent node")
            return false
        }

        var task = Task(
            title: workbenchTaskTitle(from: trimmedPrompt),
            description: trimmedPrompt,
            status: .todo,
            priority: .high,
            assignedAgentID: leadAgent.id,
            workflowNodeID: leadNode.id,
            createdBy: nil,
            tags: ["workbench", workflow.name]
        )
        task.metadata["source"] = "workbench"
        task.metadata["workflowID"] = workflow.id.uuidString
        task.metadata["entryAgentID"] = leadAgent.id.uuidString
        taskManager.addTask(task)

        var userMessage = Message(from: leadAgent.id, to: leadAgent.id, type: .task, content: trimmedPrompt)
        userMessage.status = .read
        userMessage.metadata["channel"] = "workbench"
        userMessage.metadata["role"] = "user"
        userMessage.metadata["workflowID"] = workflow.id.uuidString
        userMessage.metadata["taskID"] = task.id.uuidString
        messageManager.appendMessage(userMessage)

        var queuedMessage = Message(
            from: leadAgent.id,
            to: leadAgent.id,
            type: .notification,
            content: "任务已发布到 \(workflow.name)，由 \(leadAgent.name) 发起编排。"
        )
        queuedMessage.status = .read
        queuedMessage.metadata["channel"] = "workbench"
        queuedMessage.metadata["role"] = "assistant"
        queuedMessage.metadata["workflowID"] = workflow.id.uuidString
        queuedMessage.metadata["taskID"] = task.id.uuidString
        messageManager.appendMessage(queuedMessage)

        taskManager.moveTask(task.id, to: .inProgress)
        openClawService.addLog(.info, "Workbench published task '\(task.title)' to workflow \(workflow.name)")

        if var mutableProject = currentProject {
            mutableProject.runtimeState.messageQueue.append(trimmedPrompt)
            mutableProject.runtimeState.agentStates[leadAgent.id.uuidString] = "queued"
            mutableProject.runtimeState.lastUpdated = Date()
            mutableProject.updatedAt = Date()
            currentProject = mutableProject
        }

        openClawService.executeWorkflow(workflow, agents: project.agents) { [weak self] results in
            guard let self else { return }

            let completedCount = results.filter { $0.status == .completed }.count
            let failedCount = results.filter { $0.status == .failed }.count
            let finalStatus: TaskStatus = results.isEmpty ? .blocked : (failedCount == 0 ? .done : .blocked)
            self.taskManager.moveTask(task.id, to: finalStatus)

            let responseText: String
            if results.isEmpty {
                responseText = "工作流未返回执行结果，请检查 OpenClaw 连接、Agent 定义或部署配置。"
            } else {
                responseText = "工作流 \(workflow.name) 执行完成，\(completedCount) 个节点完成，\(failedCount) 个节点失败。"
            }

            var responseMessage = Message(
                from: leadAgent.id,
                to: leadAgent.id,
                type: failedCount == 0 ? .notification : .data,
                content: responseText
            )
            responseMessage.status = .read
            responseMessage.metadata["channel"] = "workbench"
            responseMessage.metadata["role"] = "assistant"
            responseMessage.metadata["workflowID"] = workflow.id.uuidString
            responseMessage.metadata["taskID"] = task.id.uuidString
            self.messageManager.appendMessage(responseMessage)

            if var mutableProject = self.currentProject {
                if let queueIndex = mutableProject.runtimeState.messageQueue.firstIndex(of: trimmedPrompt) {
                    mutableProject.runtimeState.messageQueue.remove(at: queueIndex)
                }

                for result in results {
                    mutableProject.runtimeState.agentStates[result.agentID.uuidString] = result.status.rawValue.lowercased()
                }
                mutableProject.runtimeState.lastUpdated = Date()
                mutableProject.updatedAt = Date()
                self.currentProject = mutableProject
            }
        }

        return true
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
                   let (project, tasks, _) = self.importExportService.importProject(from: data) {
                    self.importProjectData(project, tasks: tasks)
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

    private func workbenchTaskTitle(from prompt: String) -> String {
        let firstLine = prompt
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? prompt
        guard !firstLine.isEmpty else { return "Workbench Task" }
        return firstLine.count > 36 ? String(firstLine.prefix(36)) + "..." : firstLine
    }

    func setToolbarItem(_ item: ContentToolbarItem, visible: Bool) {
        if visible {
            visibleToolbarItems.insert(item)
        } else {
            visibleToolbarItems.remove(item)
        }
        persistToolbarPreferences()
    }

    func moveToolbarItem(_ item: ContentToolbarItem, by offset: Int) {
        guard let index = orderedToolbarItems.firstIndex(of: item) else { return }
        let targetIndex = index + offset
        guard orderedToolbarItems.indices.contains(targetIndex) else { return }

        let moved = orderedToolbarItems.remove(at: index)
        orderedToolbarItems.insert(moved, at: targetIndex)
        persistToolbarPreferences()
    }

    func resetToolbarLayout() {
        orderedToolbarItems = ContentToolbarItem.defaultOrder
        visibleToolbarItems = Set(ContentToolbarItem.defaultOrder)
        persistToolbarPreferences()
    }

    var toolbarItemsInDisplayOrder: [ContentToolbarItem] {
        orderedToolbarItems.filter { visibleToolbarItems.contains($0) }
    }

    private func loadToolbarPreferences() {
        let defaults = UserDefaults.standard
        if let orderRaw = defaults.string(forKey: "content.toolbar.order"), !orderRaw.isEmpty {
            let parsed = orderRaw
                .split(separator: ",")
                .compactMap { ContentToolbarItem(rawValue: String($0)) }
            orderedToolbarItems = normalizedToolbarOrder(parsed)
        }

        if let visibleRaw = defaults.string(forKey: "content.toolbar.visible"), !visibleRaw.isEmpty {
            let parsed = Set(
                visibleRaw
                    .split(separator: ",")
                    .compactMap { ContentToolbarItem(rawValue: String($0)) }
            )
            visibleToolbarItems = parsed.isEmpty ? Set(ContentToolbarItem.defaultOrder) : parsed
        }
    }

    private func persistToolbarPreferences() {
        let defaults = UserDefaults.standard
        defaults.set(orderedToolbarItems.map(\.rawValue).joined(separator: ","), forKey: "content.toolbar.order")
        defaults.set(
            orderedToolbarItems.filter { visibleToolbarItems.contains($0) }.map(\.rawValue).joined(separator: ","),
            forKey: "content.toolbar.visible"
        )
    }

    private func normalizedToolbarOrder(_ items: [ContentToolbarItem]) -> [ContentToolbarItem] {
        var unique: [ContentToolbarItem] = []
        for item in items where !unique.contains(item) {
            unique.append(item)
        }
        for item in ContentToolbarItem.defaultOrder where !unique.contains(item) {
            unique.append(item)
        }
        return unique
    }

    private func calculateAgentPositions(agents: [Agent]) -> [(Agent, CGPoint)] {
        var positions: [(Agent, CGPoint)] = []

        let tier1 = ["taizi", "太子"]
        let tier2 = ["zhongshu", "中书省"]
        let tier3 = ["shangshu", "尚书省"]
        let tier4 = ["menxia", "门下省"]

        var tier1Agents: [Agent] = []
        var tier2Agents: [Agent] = []
        var tier3Agents: [Agent] = []
        var tier4Agents: [Agent] = []
        var deptAgents: [Agent] = []

        for agent in agents {
            let name = agent.name.lowercased()
            if tier1.contains(where: { name.contains($0.lowercased()) }) {
                tier1Agents.append(agent)
            } else if tier2.contains(where: { name.contains($0.lowercased()) }) {
                tier2Agents.append(agent)
            } else if tier3.contains(where: { name.contains($0.lowercased()) }) {
                tier3Agents.append(agent)
            } else if tier4.contains(where: { name.contains($0.lowercased()) }) {
                tier4Agents.append(agent)
            } else {
                deptAgents.append(agent)
            }
        }

        let startX: CGFloat = 100
        let startY: CGFloat = 80
        let tierSpacing: CGFloat = 200
        let nodeSpacing: CGFloat = 160

        for (index, agent) in tier1Agents.enumerated() {
            positions.append((agent, CGPoint(x: startX + CGFloat(index) * nodeSpacing, y: startY)))
        }
        for (index, agent) in tier2Agents.enumerated() {
            positions.append((agent, CGPoint(x: startX + CGFloat(index) * nodeSpacing, y: startY + tierSpacing)))
        }
        for (index, agent) in tier3Agents.enumerated() {
            positions.append((agent, CGPoint(x: startX + CGFloat(index) * nodeSpacing, y: startY + tierSpacing * 2)))
        }
        for (index, agent) in tier4Agents.enumerated() {
            positions.append((agent, CGPoint(x: startX + CGFloat(index) * nodeSpacing, y: startY + tierSpacing * 3)))
        }

        let columns = 4
        for (index, agent) in deptAgents.enumerated() {
            let col = index % columns
            let row = index / columns
            positions.append((agent, CGPoint(x: startX + CGFloat(col) * nodeSpacing, y: startY + tierSpacing * 4 + CGFloat(row) * 100)))
        }

        return positions
    }

    private func analyzeAndGenerateConnections(agents: [Agent]) -> [(String, String)] {
        var connections: [(String, String)] = []

        if agents.contains(where: { $0.name == "taizi" || $0.name == "太子" }) &&
            agents.contains(where: { $0.name == "zhongshu" || $0.name == "中书省" }) {
            connections.append(("taizi", "zhongshu"))
            connections.append(("太子", "中书省"))
        }

        if agents.contains(where: { $0.name == "zhongshu" || $0.name == "中书省" }) &&
            agents.contains(where: { $0.name == "shangshu" || $0.name == "尚书省" }) {
            connections.append(("zhongshu", "shangshu"))
            connections.append(("中书省", "尚书省"))
        }

        if agents.contains(where: { $0.name == "shangshu" || $0.name == "尚书省" }) &&
            agents.contains(where: { $0.name == "taizi" || $0.name == "太子" }) {
            connections.append(("shangshu", "taizi"))
            connections.append(("尚书省", "太子"))
        }

        let departments = ["libu", "吏部", "hubu", "户部", "bingbu", "兵部", "xingbu", "刑部", "gongbu", "工部", "libu_hr", "menxia", "门下省"]
        for dept in departments {
            if agents.contains(where: { $0.name == "zhongshu" || $0.name == "中书省" }) &&
                agents.contains(where: { $0.name == dept }) {
                connections.append(("zhongshu", dept))
                connections.append(("中书省", dept))
            }
        }

        for dept in departments {
            if agents.contains(where: { $0.name == "shangshu" || $0.name == "尚书省" }) &&
                agents.contains(where: { $0.name == dept }) {
                connections.append((dept, "shangshu"))
                connections.append((dept, "尚书省"))
            }
        }

        return connections
    }
}
