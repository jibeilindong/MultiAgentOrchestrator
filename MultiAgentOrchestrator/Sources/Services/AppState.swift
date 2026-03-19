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

    var openClawSessionRootDirectory: URL {
        return projectsDirectory.appendingPathComponent("openclaw-sessions", isDirectory: true)
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
        try? FileManager.default.createDirectory(at: openClawSessionRootDirectory, withIntermediateDirectories: true)
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
            try? FileManager.default.removeItem(
                at: openClawSessionRootDirectory.appendingPathComponent(projectID.uuidString, isDirectory: true)
            )
        }
        loadProjectList()
    }

    func openClawProjectRoot(for projectID: UUID) -> URL {
        openClawSessionRootDirectory.appendingPathComponent(projectID.uuidString, isDirectory: true)
    }

    func openClawBackupDirectory(for projectID: UUID) -> URL {
        openClawProjectRoot(for: projectID).appendingPathComponent("backup", isDirectory: true)
    }

    func openClawMirrorDirectory(for projectID: UUID) -> URL {
        openClawProjectRoot(for: projectID).appendingPathComponent("mirror", isDirectory: true)
    }

    func openClawImportedAgentsDirectory(for projectID: UUID) -> URL {
        openClawProjectRoot(for: projectID).appendingPathComponent("agents", isDirectory: true)
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
    case view
    case display
    case language

    var id: String { rawValue }

    var title: String {
        switch self {
        case .view: return "视图"
        case .display: return "显示控制"
        case .language: return "语言"
        }
    }

    static let defaultOrder: [ContentToolbarItem] = [.display, .view, .language]
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

        openClawManager.$discoveryResults
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

    private func syncConversationPermissions(for workflows: [Workflow], in project: inout MAProject) {
        let permissions = conversationPermissions(for: workflows)
        project.permissions = permissions
    }

    private func conversationPermissions(for workflows: [Workflow]) -> [Permission] {
        var permissions: [Permission] = []
        var seenPairs = Set<String>()

        for workflow in workflows {
            let nodeByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })

            for edge in workflow.edges {
                guard let fromNode = nodeByID[edge.fromNodeID],
                      let toNode = nodeByID[edge.toNodeID],
                      let fromAgentID = fromNode.agentID,
                      let toAgentID = toNode.agentID,
                      fromAgentID != toAgentID else {
                    continue
                }

                let key = "\(fromAgentID.uuidString)->\(toAgentID.uuidString)"
                guard seenPairs.insert(key).inserted else { continue }

                permissions.append(Permission(fromAgentID: fromAgentID, toAgentID: toAgentID, permissionType: .allow))
            }
        }

        return permissions.sorted { lhs, rhs in
            let leftKey = "\(lhs.fromAgentID.uuidString)->\(lhs.toAgentID.uuidString)"
            let rightKey = "\(rhs.fromAgentID.uuidString)->\(rhs.toAgentID.uuidString)"
            return leftKey < rightKey
        }
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

        let project = openClawManager.isConnected
            ? MAProject(name: resolvedName)
            : makeOfflineTemplateProject(named: resolvedName)
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

    private func persistCurrentProjectSilently() {
        guard let project = snapshotCurrentProject() else { return }

        do {
            let destinationURL = currentProjectFileURL ?? projectManager.projectURL(for: project.name)
            currentProjectFileURL = try projectManager.saveProject(project, to: destinationURL)
            currentProject = project
        } catch {
            print("静默保存项目失败: \(error)")
        }
    }
    
    // 关闭当前项目
    func closeProject() {
        persistCurrentProjectSilently()

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

    func shutdown() {
        if currentProject != nil {
            persistCurrentProjectSilently()
        }

        openClawManager.disconnect()
        stopAutoSave()
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
        if !hydratedProject.workflows.isEmpty {
            hydratedProject.permissions = conversationPermissions(for: hydratedProject.workflows)
        }
        currentProject = hydratedProject
    }

    private func makeOfflineTemplateProject(named projectName: String) -> MAProject {
        var project = MAProject(name: projectName)
        let agents = makeOfflineTemplateAgents()
        project.agents = agents
        project.workflows = [makeOfflineTemplateWorkflow(agents: agents)]
        project.permissions = conversationPermissions(for: project.workflows)
        return project
    }

    private func makeOfflineTemplateAgents() -> [Agent] {
        let templates: [(String, String, [String])] = [
            ("Coordinator", "负责拆解目标、分配任务并跟踪进度。", ["planning", "coordination"]),
            ("Researcher", "负责收集背景信息、验证假设并输出摘要。", ["research", "analysis"]),
            ("Implementer", "负责把计划落实为实现细节和可执行结果。", ["implementation", "delivery"]),
            ("Reviewer", "负责审查输出、发现风险并提出修正意见。", ["review", "quality"])
        ]

        return templates.enumerated().map { index, entry in
            var agent = Agent(name: entry.0)
            agent.description = entry.1
            agent.soulMD = """
            # \(entry.0)

            \(entry.1)
            """
            agent.position = CGPoint(x: CGFloat(180 + (index * 220)), y: CGFloat(180 + ((index % 2) * 130)))
            agent.capabilities = entry.2
            agent.openClawDefinition.agentIdentifier = entry.0
            return agent
        }
    }

    private func makeOfflineTemplateWorkflow(agents: [Agent]) -> Workflow {
        var workflow = Workflow(name: "Offline Template Workflow")
        var x: CGFloat = 160
        let y: CGFloat = 220
        let startNode = makeStartNode(position: CGPoint(x: 80, y: y))
        workflow.nodes.append(startNode)
        var previousNodeID: UUID? = startNode.id

        for agent in agents {
            var node = WorkflowNode(type: .agent)
            node.agentID = agent.id
            node.title = agent.name
            node.position = CGPoint(x: x, y: y)
            workflow.nodes.append(node)

            if let previousNodeID {
                workflow.edges.append(WorkflowEdge(from: previousNodeID, to: node.id))
            }

            previousNodeID = node.id
            x += 220
        }

        return workflow
    }

    private func makeStartNode(position: CGPoint = .zero) -> WorkflowNode {
        var node = WorkflowNode(type: .start)
        node.position = position
        node.title = "Start"
        return node
    }

    func detectOpenClawAgents(using config: OpenClawConfig? = nil, completion: ((Bool, String, [String]) -> Void)? = nil) {
        let resolvedConfig = config ?? openClawManager.config
        openClawManager.testConnection(using: resolvedConfig) { [weak self] success, message, names in
            guard let self else { return }
            DispatchQueue.main.async {
                self.syncCurrentProjectFromManagers()
                completion?(success, message, names)
            }
        }
    }

    func connectOpenClaw(using config: OpenClawConfig? = nil, completion: ((Bool, String) -> Void)? = nil) {
        guard let projectID = currentProject?.id else {
            completion?(false, "请先创建或打开项目，再确认连接 OpenClaw。")
            return
        }

        if let config {
            openClawManager.config = config
            openClawManager.config.save()
        }

        openClawManager.connect(for: projectID) { [weak self] success, message in
            guard let self else { return }
            DispatchQueue.main.async {
                self.syncCurrentProjectFromManagers()
                if success {
                    self.persistCurrentProjectSilently()
                }
                completion?(success, message)
            }
        }
    }

    func disconnectOpenClaw(completion: ((Bool, String) -> Void)? = nil) {
        if currentProject != nil {
            persistCurrentProjectSilently()
        }

        openClawManager.disconnect()
        syncCurrentProjectFromManagers()
        completion?(true, "OpenClaw 已断开并恢复到连接前状态。")
    }

    @discardableResult
    func importDetectedOpenClawAgents(selectedRecordIDs: Set<String>) -> [ProjectOpenClawDetectedAgentRecord] {
        guard var project = currentProject else { return [] }
        guard !selectedRecordIDs.isEmpty else { return [] }

        let imported = openClawManager.importDetectedAgents(into: &project, selectedRecordIDs: selectedRecordIDs)
        guard !imported.isEmpty else { return [] }

        currentProject = project
        syncCurrentProjectFromManagers()
        persistCurrentProjectSilently()
        return imported
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

    func removeBoundary(around nodeIDs: Set<UUID>) {
        guard !nodeIDs.isEmpty else { return }

        updateMainWorkflow { workflow in
            workflow.boundaries.removeAll { boundary in
                boundary.matchesSelection(nodeIDs)
            }
        }
    }

    func removeBoundary(containing nodeID: UUID) {
        updateMainWorkflow { workflow in
            workflow.boundaries.removeAll { $0.contains(nodeID) }
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
            var workflow = Workflow(name: "Main Workflow")
            workflow.nodes.append(makeStartNode())
            project.workflows.append(workflow)
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
        syncConversationPermissions(for: project.workflows, in: &project)
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
        switch type {
        case .start:
            updateMainWorkflow { workflow in
                guard !workflow.nodes.contains(where: { $0.type == .start }) else { return }
                var node = WorkflowNode(type: .start)
                node.position = position
                workflow.nodes.insert(node, at: 0)
            }
        case .agent:
            updateMainWorkflow { workflow in
                var node = WorkflowNode(type: type)
                node.position = position
                workflow.nodes.append(node)
            }
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

        let workflowSnapshot = currentProject?.workflows.first
        let removedAgentIDs = Set((workflowSnapshot?.nodes ?? [])
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
        guard let workflow = currentProject?.workflows.first,
              workflow.edges.contains(where: { $0.id == edgeID }) else { return }

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

        var createdPairs: [(UUID, UUID)] = []

        updateMainWorkflow { workflow in
            appendEdgeIfNeeded(from: fromNodeID, to: toNodeID, workflow: &workflow)
            createdPairs.append((fromNodeID, toNodeID))

            if bidirectional {
                appendEdgeIfNeeded(from: toNodeID, to: fromNodeID, workflow: &workflow)
                createdPairs.append((toNodeID, fromNodeID))
            }
        }

        for (sourceNodeID, targetNodeID) in createdPairs {
            if let sourceAgentID = currentProject?.workflows.first?.nodes.first(where: { $0.id == sourceNodeID })?.agentID,
               let targetAgentID = currentProject?.workflows.first?.nodes.first(where: { $0.id == targetNodeID })?.agentID {
                setPermission(fromAgentID: sourceAgentID, toAgentID: targetAgentID, type: .allow)
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

        // 当前编辑器支持 start/agent 两类节点连线；仅在 agent<->agent 时自动补权限。
        let supportedTypes: Set<WorkflowNode.NodeType> = [.start, .agent]
        if !supportedTypes.contains(sourceNode.type) || !supportedTypes.contains(targetNode.type) {
            return
        }

        updateMainWorkflow { workflow in
            appendEdgeIfNeeded(from: sourceNodeID, to: targetNodeID, workflow: &workflow)
            if bidirectional {
                appendEdgeIfNeeded(from: targetNodeID, to: sourceNodeID, workflow: &workflow)
            }
        }

        if sourceNode.type == .agent,
           targetNode.type == .agent,
           let sourceAgentID = sourceNode.agentID,
           let targetAgentID = targetNode.agentID {
            setPermission(fromAgentID: sourceAgentID, toAgentID: targetAgentID, type: .allow)
            if bidirectional {
                setPermission(fromAgentID: targetAgentID, toAgentID: sourceAgentID, type: .allow)
            }
        }
    }

    func generateArchitectureFromProjectAgents() {
        guard var project = currentProject else { return }

        if project.workflows.isEmpty {
            project.workflows.append(Workflow(name: "Main Workflow"))
        }

        guard var workflow = project.workflows.first else { return }

        let descriptors: [ArchitectureAgentDescriptor] = buildArchitectureDescriptors(for: project.agents)
        let existingAgentNodes: [UUID: WorkflowNode] = Dictionary(uniqueKeysWithValues: workflow.nodes.compactMap { node -> (UUID, WorkflowNode)? in
            guard node.type == .agent, let agentID = node.agentID else { return nil }
            return (agentID, node)
        })

        let positionedAgents: [ArchitectureGeneratedNode] = calculateAgentPositions(
            descriptors: descriptors,
            existingNodesByAgentID: existingAgentNodes
        )

        let nonAgentNodes: [WorkflowNode] = workflow.nodes.filter { $0.type != .agent }
        let generatedAgentNodes: [WorkflowNode] = positionedAgents.map { $0.node }
        let generatedAgentNodeIDs: Set<UUID> = Set(generatedAgentNodes.map { $0.id })
        let generatedNodeIDByAgentID: [UUID: UUID] = Dictionary(uniqueKeysWithValues: generatedAgentNodes.compactMap { node -> (UUID, UUID)? in
            guard let agentID = node.agentID else { return nil }
            return (agentID, node.id)
        })

        workflow.nodes = nonAgentNodes + generatedAgentNodes

        let preservedEdges: [WorkflowEdge] = workflow.edges.filter { edge in
            !(generatedAgentNodeIDs.contains(edge.fromNodeID) && generatedAgentNodeIDs.contains(edge.toNodeID))
        }
        let generatedEdges: [WorkflowEdge] = buildArchitectureEdges(
            descriptors: descriptors,
            nodeIDByAgentID: generatedNodeIDByAgentID
        )
        workflow.edges = preservedEdges + generatedEdges

        workflow.boundaries = mergeArchitectureBoundaries(
            existing: workflow.boundaries,
            generated: buildArchitectureBoundaries(from: positionedAgents)
        )

        project.permissions = mergeArchitecturePermissions(
            existing: project.permissions,
            descriptors: descriptors,
            edges: generatedEdges,
            nodeIDByAgentID: generatedNodeIDByAgentID
        )

        if let index = project.workflows.firstIndex(where: { $0.id == workflow.id }) {
            project.workflows[index] = workflow
        } else {
            project.workflows.append(workflow)
        }

        project.permissions = conversationPermissions(for: project.workflows)

        project.updatedAt = Date()
        currentProject = project
        objectWillChange.send()
        generateTasksFromWorkflow()
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

        let previousAgent = project.agents[index]
        project.agents[index] = updatedAgent
        project.updatedAt = Date()
        currentProject = project
        objectWillChange.send()

        openClawManager.updateAgentSoulMD(
            matching: [previousAgent.name, previousAgent.openClawDefinition.agentIdentifier, updatedAgent.name, updatedAgent.openClawDefinition.agentIdentifier],
            soulMD: updatedAgent.soulMD
        ) { [weak self] success, message in
            guard let self else { return }
            DispatchQueue.main.async {
                self.openClawService.addLog(success ? .success : .warning, message)
            }
        }

        if reload {
            reloadAgent(updatedAgent.id)
        }
    }

    func updateAgentOpenClawDefinition(
        for agentID: UUID,
        mutate: (inout OpenClawAgentDefinition) -> Void
    ) {
        guard var project = currentProject,
              let index = project.agents.firstIndex(where: { $0.id == agentID }) else { return }

        mutate(&project.agents[index].openClawDefinition)
        project.agents[index].updatedAt = Date()
        project.updatedAt = Date()
        currentProject = project
        objectWillChange.send()
        persistCurrentProjectSilently()
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

        let entryAgentNodes = entryConnectedAgentNodes(in: workflow)
        guard let leadNode = entryAgentNodes.first,
              let leadAgentID = leadNode.agentID,
              let leadAgent = project.agents.first(where: { $0.id == leadAgentID }) else {
            openClawService.addLog(
                .error,
                "Workbench publish failed: no agent is connected to the workflow entry(start) node."
            )
            return false
        }

        let entryAgentIDs = Set(entryAgentNodes.compactMap(\.agentID))
        let entryAgentNames = project.agents
            .filter { entryAgentIDs.contains($0.id) }
            .map(\.name)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if !entryAgentNames.isEmpty {
            openClawService.addLog(
                .info,
                "Workbench entry routing: prompt will be delivered to entry-connected agent(s): \(entryAgentNames.joined(separator: ", "))"
            )
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
        task.metadata["entryNodeAgentIDs"] = entryAgentIDs.map(\.uuidString).sorted().joined(separator: ",")
        taskManager.addTask(task)

        var userMessage = Message(from: leadAgent.id, to: leadAgent.id, type: .task, content: trimmedPrompt)
        userMessage.status = .read
        userMessage.metadata["channel"] = "workbench"
        userMessage.metadata["role"] = "user"
        userMessage.metadata["kind"] = "input"
        userMessage.metadata["workflowID"] = workflow.id.uuidString
        userMessage.metadata["taskID"] = task.id.uuidString
        userMessage.metadata["tokenEstimate"] = String(estimatedTokenCount(for: trimmedPrompt))
        messageManager.appendMessage(userMessage)

        var queuedMessage = Message(
            from: leadAgent.id,
            to: leadAgent.id,
            type: .notification,
            content: "任务已发布到 \(workflow.name)，入口节点已路由给 \(leadAgent.name)。"
        )
        queuedMessage.status = .read
        queuedMessage.metadata["channel"] = "workbench"
        queuedMessage.metadata["role"] = "assistant"
        queuedMessage.metadata["kind"] = "system"
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

        openClawService.executeWorkflow(workflow, agents: project.agents, prompt: trimmedPrompt) { [weak self] results in
            guard let self else { return }

            let completedCount = results.filter { $0.status == .completed }.count
            let failedCount = results.filter { $0.status == .failed }.count
            let finalStatus: TaskStatus = results.isEmpty ? .blocked : (failedCount == 0 ? .done : .blocked)
            self.taskManager.moveTask(task.id, to: finalStatus)

            let entryResult = results.first { entryAgentIDs.contains($0.agentID) }
            let respondingAgent = entryResult
                .flatMap { result in project.agents.first(where: { $0.id == result.agentID }) }
                ?? leadAgent

            let responseText: String
            if results.isEmpty {
                responseText = "工作流未返回执行结果，请检查 OpenClaw 连接、Agent 定义或部署配置。"
            } else if let entryResult {
                let output = entryResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                responseText = output.isEmpty
                    ? "\(respondingAgent.name) 已从入口链路执行完成，\(completedCount) 个节点完成，\(failedCount) 个节点失败。"
                    : output
            } else {
                responseText = "工作流 \(workflow.name) 执行完成，\(completedCount) 个节点完成，\(failedCount) 个节点失败。"
            }

            var responseMessage = Message(
                from: respondingAgent.id,
                to: respondingAgent.id,
                type: failedCount == 0 ? .notification : .data,
                content: responseText
            )
            responseMessage.status = .read
            responseMessage.metadata["channel"] = "workbench"
            responseMessage.metadata["role"] = "assistant"
            responseMessage.metadata["kind"] = "output"
            responseMessage.metadata["workflowID"] = workflow.id.uuidString
            responseMessage.metadata["taskID"] = task.id.uuidString
            responseMessage.metadata["entryReply"] = "true"
            responseMessage.metadata["tokenEstimate"] = String(self.estimatedTokenCount(for: responseText))
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
    @discardableResult
    func addNewAgent(named name: String = "New Agent") -> Agent? {
        guard var project = currentProject else { return nil }
        let resolvedName = uniqueAgentName(baseName: name, suffix: "")
        var newAgent = Agent(name: resolvedName)
        newAgent.description = "Description"
        project.agents.append(newAgent)
        project.updatedAt = Date()
        currentProject = project
        objectWillChange.send()
        return newAgent
    }

    func copyAgent(_ agent: Agent) -> Bool {
        guard let data = try? JSONEncoder().encode(agent),
              let jsonString = String(data: data, encoding: .utf8) else {
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(jsonString, forType: .string)
    }

    @discardableResult
    func pasteAgentFromPasteboard(offset: CGPoint = CGPoint(x: 40, y: 40)) -> Agent? {
        guard let jsonString = NSPasteboard.general.string(forType: .string),
              let data = jsonString.data(using: .utf8),
              var sourceAgent = try? JSONDecoder().decode(Agent.self, from: data) else {
            return nil
        }

        sourceAgent = makeCopiedAgent(from: sourceAgent, suffix: "Copy", offset: offset)
        guard var project = currentProject else { return nil }

        project.agents.append(sourceAgent)
        project.updatedAt = Date()
        currentProject = project
        objectWillChange.send()
        return sourceAgent
    }

    @discardableResult
    func duplicateAgent(_ agentID: UUID, suffix: String = "Copy", offset: CGPoint = CGPoint(x: 40, y: 40)) -> Agent? {
        guard let agent = currentProject?.agents.first(where: { $0.id == agentID }),
              var project = currentProject else { return nil }

        let duplicated = makeCopiedAgent(from: agent, suffix: suffix, offset: offset)
        project.agents.append(duplicated)
        project.updatedAt = Date()
        currentProject = project
        objectWillChange.send()
        return duplicated
    }

    func cutAgent(_ agentID: UUID) -> Bool {
        guard let agent = currentProject?.agents.first(where: { $0.id == agentID }) else { return false }
        guard copyAgent(agent) else { return false }
        deleteAgent(agentID)
        return true
    }

    func deleteAgent(_ agentID: UUID) {
        guard var project = currentProject else { return }

        project.agents.removeAll { $0.id == agentID }
        project.permissions.removeAll { $0.fromAgentID == agentID || $0.toAgentID == agentID }

        for index in project.workflows.indices {
            project.workflows[index].nodes.removeAll { $0.agentID == agentID }
            let remainingNodeIDs = Set(project.workflows[index].nodes.map(\.id))
            project.workflows[index].edges.removeAll { edge in
                !remainingNodeIDs.contains(edge.fromNodeID) || !remainingNodeIDs.contains(edge.toNodeID)
            }
            project.workflows[index].boundaries = project.workflows[index].boundaries.compactMap { boundary in
                var updated = boundary
                updated.memberNodeIDs.removeAll { !remainingNodeIDs.contains($0) }
                updated.updatedAt = Date()
                return updated.memberNodeIDs.isEmpty ? nil : updated
            }
        }

        project.updatedAt = Date()
        currentProject = project
        objectWillChange.send()
        openClawManager.terminateAgent(agentID)
    }

    private func makeCopiedAgent(from agent: Agent, suffix: String, offset: CGPoint) -> Agent {
        var copied = Agent(name: uniqueAgentName(baseName: agent.name, suffix: suffix))
        copied.identity = agent.identity
        copied.description = agent.description
        copied.soulMD = agent.soulMD
        copied.position = CGPoint(x: agent.position.x + offset.x, y: agent.position.y + offset.y)
        copied.capabilities = agent.capabilities
        copied.colorHex = agent.colorHex
        copied.openClawDefinition = agent.openClawDefinition
        copied.openClawDefinition.agentIdentifier = copied.name
        copied.updatedAt = Date()
        return copied
    }

    private func uniqueAgentName(baseName: String, suffix: String) -> String {
        guard let project = currentProject else { return suffix.isEmpty ? baseName : "\(baseName) \(suffix)" }
        let existingNames = Set(project.agents.map(\.name))
        var candidate = suffix.isEmpty ? baseName : "\(baseName) \(suffix)"
        var counter = 2
        while existingNames.contains(candidate) {
            candidate = suffix.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(suffix) \(counter)"
            counter += 1
        }
        return candidate
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

    private func entryConnectedAgentNodes(in workflow: Workflow) -> [WorkflowNode] {
        let nodeByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })
        let startNodes = workflow.nodes
            .filter { $0.type == .start }
            .sorted(by: workbenchNodeSort)

        guard let entryNode = startNodes.first else {
            return []
        }

        var seen = Set<UUID>()
        let connectedAgents = workflow.edges
            .filter { $0.fromNodeID == entryNode.id }
            .compactMap { nodeByID[$0.toNodeID] }
            .filter { node in
                guard node.type == .agent, let agentID = node.agentID else { return false }
                return seen.insert(agentID).inserted
            }
            .sorted(by: workbenchNodeSort)

        return connectedAgents
    }

    private func workbenchNodeSort(_ lhs: WorkflowNode, _ rhs: WorkflowNode) -> Bool {
        if lhs.position.y != rhs.position.y {
            return lhs.position.y < rhs.position.y
        }
        if lhs.position.x != rhs.position.x {
            return lhs.position.x < rhs.position.x
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func workbenchTaskTitle(from prompt: String) -> String {
        let firstLine = prompt
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? prompt
        guard !firstLine.isEmpty else { return "Workbench Task" }
        return firstLine.count > 36 ? String(firstLine.prefix(36)) + "..." : firstLine
    }

    private func estimatedTokenCount(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let scalarCount = trimmed.unicodeScalars.count
        return max(1, Int(ceil(Double(scalarCount) / 4.0)))
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

    private func calculateAgentPositions(
        descriptors: [ArchitectureAgentDescriptor],
        existingNodesByAgentID: [UUID: WorkflowNode]
    ) -> [ArchitectureGeneratedNode] {
        let startX: CGFloat = 140
        let startY: CGFloat = 110
        let laneSpacing: CGFloat = 190
        let nodeSpacing: CGFloat = 190
        let executionRowSpacing: CGFloat = 110
        let executionColumns = 4

        let groupedByLane = Dictionary(grouping: descriptors, by: \.lane)
        var generated: [ArchitectureGeneratedNode] = []

        for lane in ArchitectureLane.allCases {
            let laneDescriptors = (groupedByLane[lane] ?? []).sorted {
                if $0.clusterKey == $1.clusterKey {
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                return $0.clusterKey.localizedCaseInsensitiveCompare($1.clusterKey) == .orderedAscending
            }

            guard !laneDescriptors.isEmpty else { continue }

            for (index, descriptor) in laneDescriptors.enumerated() {
                let proposedPosition: CGPoint

                if lane == .execution {
                    let row = index / executionColumns
                    let column = index % executionColumns
                    proposedPosition = CGPoint(
                        x: startX + CGFloat(column) * nodeSpacing,
                        y: startY + CGFloat(lane.rawValue) * laneSpacing + CGFloat(row) * executionRowSpacing
                    )
                } else {
                    proposedPosition = CGPoint(
                        x: startX + CGFloat(index) * nodeSpacing,
                        y: startY + CGFloat(lane.rawValue) * laneSpacing
                    )
                }

                var node = existingNodesByAgentID[descriptor.agent.id] ?? WorkflowNode(type: .agent)
                node.agentID = descriptor.agent.id
                node.title = descriptor.agent.name
                if existingNodesByAgentID[descriptor.agent.id] == nil || node.position == .zero {
                    node.position = proposedPosition
                }

                generated.append(
                    ArchitectureGeneratedNode(
                        node: node,
                        descriptor: descriptor,
                        proposedPosition: proposedPosition
                    )
                )
            }
        }

        return generated
    }

    private func buildArchitectureDescriptors(for agents: [Agent]) -> [ArchitectureAgentDescriptor] {
        agents.map { agent in
            let searchCorpus = [
                agent.name,
                agent.identity,
                agent.description,
                agent.soulMD,
                agent.capabilities.joined(separator: " "),
                agent.openClawDefinition.agentIdentifier,
                agent.openClawDefinition.runtimeProfile
            ]
            .joined(separator: " ")
            .lowercased()

            let lane = architectureLane(for: searchCorpus)
            let clusterKey = architectureClusterKey(for: agent, lane: lane, searchCorpus: searchCorpus)

            return ArchitectureAgentDescriptor(
                agent: agent,
                lane: lane,
                clusterKey: clusterKey,
                searchCorpus: searchCorpus
            )
        }
    }

    private func architectureLane(for searchCorpus: String) -> ArchitectureLane {
        if matchesAnyKeyword(in: searchCorpus, keywords: ["taizi", "太子", "lead", "leader", "chief", "owner", "director", "战略", "决策"]) {
            return .leadership
        }
        if matchesAnyKeyword(in: searchCorpus, keywords: ["zhongshu", "中书", "shangshu", "尚书", "coord", "coordinator", "manager", "router", "dispatcher", "planner", "orchestrator", "调度", "编排", "规划"]) {
            return .coordination
        }
        if matchesAnyKeyword(in: searchCorpus, keywords: ["menxia", "门下", "review", "reviewer", "qa", "audit", "approver", "validator", "审批", "审查", "质检", "验证"]) {
            return .review
        }
        if matchesAnyKeyword(in: searchCorpus, keywords: ["memory", "knowledge", "archive", "history", "记忆", "知识", "归档", "档案"]) {
            return .memory
        }
        return .execution
    }

    private func architectureClusterKey(for agent: Agent, lane: ArchitectureLane, searchCorpus: String) -> String {
        if lane != .execution {
            return lane.title
        }

        let identity = agent.identity.trimmingCharacters(in: .whitespacesAndNewlines)
        if !identity.isEmpty, identity != "generalist" {
            return identity
        }

        if let firstCapability = agent.capabilities.first, !firstCapability.isEmpty {
            return firstCapability
        }

        if matchesAnyKeyword(in: searchCorpus, keywords: ["libu", "吏部"]) { return "吏部" }
        if matchesAnyKeyword(in: searchCorpus, keywords: ["hubu", "户部"]) { return "户部" }
        if matchesAnyKeyword(in: searchCorpus, keywords: ["bingbu", "兵部"]) { return "兵部" }
        if matchesAnyKeyword(in: searchCorpus, keywords: ["xingbu", "刑部"]) { return "刑部" }
        if matchesAnyKeyword(in: searchCorpus, keywords: ["gongbu", "工部"]) { return "工部" }

        return lane.title
    }

    private func buildArchitectureEdges(
        descriptors: [ArchitectureAgentDescriptor],
        nodeIDByAgentID: [UUID: UUID]
    ) -> [WorkflowEdge] {
        var pairs = Set<ArchitectureEdgePair>()
        let descriptorsByLane = Dictionary(grouping: descriptors, by: \.lane)

        if let leadership = descriptorsByLane[.leadership], let coordination = descriptorsByLane[.coordination] {
            pairs.formUnion(pairAdjacentDescriptors(from: leadership, to: coordination))
        }
        if let coordination = descriptorsByLane[.coordination], let execution = descriptorsByLane[.execution] {
            pairs.formUnion(pairAdjacentDescriptors(from: coordination, to: execution))
        }
        if let execution = descriptorsByLane[.execution], let review = descriptorsByLane[.review] {
            pairs.formUnion(pairAdjacentDescriptors(from: execution, to: review))
        }
        if let review = descriptorsByLane[.review], let memory = descriptorsByLane[.memory] {
            pairs.formUnion(pairAdjacentDescriptors(from: review, to: memory))
        } else if let execution = descriptorsByLane[.execution], let memory = descriptorsByLane[.memory] {
            pairs.formUnion(pairAdjacentDescriptors(from: execution, to: memory))
        }

        if pairs.isEmpty {
            let ordered = descriptors.sorted {
                if $0.lane == $1.lane {
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                return $0.lane.rawValue < $1.lane.rawValue
            }
            for index in 0..<max(ordered.count - 1, 0) {
                pairs.insert(ArchitectureEdgePair(fromAgentID: ordered[index].agent.id, toAgentID: ordered[index + 1].agent.id))
            }
        }

        return pairs.compactMap { pair in
            guard let sourceNodeID = nodeIDByAgentID[pair.fromAgentID],
                  let targetNodeID = nodeIDByAgentID[pair.toAgentID] else { return nil }
            return WorkflowEdge(from: sourceNodeID, to: targetNodeID)
        }
    }

    private func pairAdjacentDescriptors(
        from sources: [ArchitectureAgentDescriptor],
        to targets: [ArchitectureAgentDescriptor]
    ) -> Set<ArchitectureEdgePair> {
        guard !sources.isEmpty, !targets.isEmpty else { return [] }

        let orderedSources = sources.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        let orderedTargets = targets.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        if orderedSources.count == 1 {
            return Set(orderedTargets.map { ArchitectureEdgePair(fromAgentID: orderedSources[0].agent.id, toAgentID: $0.agent.id) })
        }

        if orderedTargets.count == 1 {
            return Set(orderedSources.map { ArchitectureEdgePair(fromAgentID: $0.agent.id, toAgentID: orderedTargets[0].agent.id) })
        }

        let pairCount = max(orderedSources.count, orderedTargets.count)
        return Set((0..<pairCount).map { index in
            let source = orderedSources[min(index, orderedSources.count - 1)]
            let target = orderedTargets[min(index, orderedTargets.count - 1)]
            return ArchitectureEdgePair(fromAgentID: source.agent.id, toAgentID: target.agent.id)
        })
    }

    private func buildArchitectureBoundaries(from generatedNodes: [ArchitectureGeneratedNode]) -> [WorkflowBoundary] {
        let grouped = Dictionary(grouping: generatedNodes, by: \.descriptor.clusterKey)

        return grouped.compactMap { clusterKey, members in
            guard members.count > 1 else { return nil }

            let xValues = members.map { $0.node.position.x }
            let yValues = members.map { $0.node.position.y }
            let minX = (xValues.min() ?? 0) - 110
            let maxX = (xValues.max() ?? 0) + 110
            let minY = (yValues.min() ?? 0) - 80
            let maxY = (yValues.max() ?? 0) + 80

            var boundary = WorkflowBoundary(
                title: "\(architectureBoundaryPrefix) \(clusterKey)",
                rect: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
                memberNodeIDs: members.map { $0.node.id }
            )
            boundary.updatedAt = Date()
            return boundary
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func mergeArchitectureBoundaries(
        existing: [WorkflowBoundary],
        generated: [WorkflowBoundary]
    ) -> [WorkflowBoundary] {
        existing.filter { !$0.title.hasPrefix(architectureBoundaryPrefix) } + generated
    }

    private func mergeArchitecturePermissions(
        existing: [Permission],
        descriptors: [ArchitectureAgentDescriptor],
        edges: [WorkflowEdge],
        nodeIDByAgentID: [UUID: UUID]
    ) -> [Permission] {
        let agentIDByNodeID = Dictionary(uniqueKeysWithValues: nodeIDByAgentID.map { ($1, $0) })
        var uniquePermissions: [String: Permission] = [:]

        for permission in existing {
            uniquePermissions[permissionKey(from: permission.fromAgentID, to: permission.toAgentID)] = permission
        }

        let descriptorLookup = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.agent.id, $0) })

        for edge in edges {
            guard let fromAgentID = agentIDByNodeID[edge.fromNodeID],
                  let toAgentID = agentIDByNodeID[edge.toNodeID] else { continue }

            let key = permissionKey(from: fromAgentID, to: toAgentID)
            if uniquePermissions[key] == nil {
                uniquePermissions[key] = Permission(
                    fromAgentID: fromAgentID,
                    toAgentID: toAgentID,
                    permissionType: .allow
                )
            } else if uniquePermissions[key]?.permissionType == .allow {
                uniquePermissions[key]?.updatedAt = Date()
            }

            if let fromDescriptor = descriptorLookup[fromAgentID],
               let toDescriptor = descriptorLookup[toAgentID],
               fromDescriptor.lane == .coordination,
               toDescriptor.lane == .execution {
                let reverseKey = permissionKey(from: toAgentID, to: fromAgentID)
                if uniquePermissions[reverseKey] == nil {
                    uniquePermissions[reverseKey] = Permission(
                        fromAgentID: toAgentID,
                        toAgentID: fromAgentID,
                        permissionType: .allow
                    )
                }
            }
        }

        return uniquePermissions.values.sorted { lhs, rhs in
            let leftKey = permissionKey(from: lhs.fromAgentID, to: lhs.toAgentID)
            let rightKey = permissionKey(from: rhs.fromAgentID, to: rhs.toAgentID)
            return leftKey < rightKey
        }
    }

    private func permissionKey(from: UUID, to: UUID) -> String {
        "\(from.uuidString)->\(to.uuidString)"
    }

    private func matchesAnyKeyword(in searchCorpus: String, keywords: [String]) -> Bool {
        keywords.contains { keyword in
            searchCorpus.contains(keyword.lowercased())
        }
    }

    private var architectureBoundaryPrefix: String {
        "Auto Boundary:"
    }

    private enum ArchitectureLane: Int, CaseIterable {
        case leadership
        case coordination
        case execution
        case review
        case memory

        var title: String {
            switch self {
            case .leadership: return "Leadership"
            case .coordination: return "Coordination"
            case .execution: return "Execution"
            case .review: return "Review"
            case .memory: return "Memory"
            }
        }
    }

    private struct ArchitectureAgentDescriptor {
        let agent: Agent
        let lane: ArchitectureLane
        let clusterKey: String
        let searchCorpus: String

        var displayName: String { agent.name }
    }

    private struct ArchitectureGeneratedNode {
        let node: WorkflowNode
        let descriptor: ArchitectureAgentDescriptor
        let proposedPosition: CGPoint
    }

    private struct ArchitectureEdgePair: Hashable {
        let fromAgentID: UUID
        let toAgentID: UUID
    }
}
