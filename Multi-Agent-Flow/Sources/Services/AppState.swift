//
//  AppState.swift
//  Multi-Agent-Flow
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

    private let fileManager = FileManager.default
    
    var projectsDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("Multi-Agent-Flow", isDirectory: true)
    }

    var legacyProjectsDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("MultiAgentOrchestrator", isDirectory: true)
    }
    
    var backupsDirectory: URL {
        return projectsDirectory.appendingPathComponent("backups", isDirectory: true)
    }

    var openClawSessionRootDirectory: URL {
        return projectsDirectory.appendingPathComponent("openclaw-sessions", isDirectory: true)
    }

    var appSupportRootDirectory: URL {
        let appSupportPath = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupportPath.appendingPathComponent("Multi-Agent-Flow", isDirectory: true)
    }

    var legacyAppSupportRootDirectory: URL {
        let appSupportPath = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupportPath.appendingPathComponent("MultiAgentOrchestrator", isDirectory: true)
    }

    var defaultWorkspaceRootDirectory: URL {
        appSupportRootDirectory.appendingPathComponent("Workspaces", isDirectory: true)
    }

    var autoSaveDirectory: URL {
        appSupportRootDirectory.appendingPathComponent("AutoSave", isDirectory: true)
    }
    
    private init() {
        migrateLegacyStorageIfNeeded()
        createDirectoriesIfNeeded()
        loadProjectList()
    }
    
    func createDirectoriesIfNeeded() {
        try? fileManager.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: openClawSessionRootDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: defaultWorkspaceRootDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: autoSaveDirectory, withIntermediateDirectories: true)
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

    private func migrateLegacyStorageIfNeeded() {
        mergeDirectoryIfNeeded(from: legacyProjectsDirectory, to: projectsDirectory)
        mergeDirectoryIfNeeded(from: legacyAppSupportRootDirectory, to: appSupportRootDirectory)
    }

    private func mergeDirectoryIfNeeded(from legacyURL: URL, to currentURL: URL) {
        var isLegacyDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: legacyURL.path, isDirectory: &isLegacyDirectory), isLegacyDirectory.boolValue else {
            return
        }

        var isCurrentDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: currentURL.path, isDirectory: &isCurrentDirectory) {
            try? fileManager.moveItem(at: legacyURL, to: currentURL)
            return
        }

        guard isCurrentDirectory.boolValue else { return }

        let legacyContents = (try? fileManager.contentsOfDirectory(
            at: legacyURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for sourceURL in legacyContents {
            let destinationURL = currentURL.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)
            var isSourceDirectory: ObjCBool = false

            if !fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.moveItem(at: sourceURL, to: destinationURL)
                continue
            }

            guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isSourceDirectory), isSourceDirectory.boolValue else {
                continue
            }

            mergeDirectoryIfNeeded(from: sourceURL, to: destinationURL)
        }

        let remainingLegacyContents = (try? fileManager.contentsOfDirectory(at: legacyURL, includingPropertiesForKeys: nil)) ?? []
        if remainingLegacyContents.isEmpty {
            try? fileManager.removeItem(at: legacyURL)
        }
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
        case .blue: return LocalizedString.text("color_blue")
        case .graphite: return LocalizedString.text("color_graphite")
        case .green: return LocalizedString.text("color_green")
        case .orange: return LocalizedString.text("color_orange")
        case .red: return LocalizedString.text("color_red")
        case .primary: return LocalizedString.text("color_default")
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

enum CanvasGroupKind: String, Codable, Hashable, CaseIterable {
    case node
    case edge
}

struct CanvasColorGroup: Identifiable, Codable, Hashable {
    var kind: CanvasGroupKind
    var colorHex: String
    var title: String

    var id: String {
        "\(kind.rawValue)-\(CanvasStylePalette.normalizedHex(colorHex) ?? colorHex.uppercased())"
    }
}

enum CanvasAccentColorPreset: String, CaseIterable, Identifiable {
    case blue
    case teal
    case green
    case amber
    case orange
    case red
    case pink
    case violet
    case slate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: return LocalizedString.text("color_blue")
        case .teal: return LocalizedString.text("color_teal")
        case .green: return LocalizedString.text("color_green")
        case .amber: return LocalizedString.text("color_amber")
        case .orange: return LocalizedString.text("color_orange")
        case .red: return LocalizedString.text("color_red")
        case .pink: return LocalizedString.text("color_pink")
        case .violet: return LocalizedString.text("color_violet")
        case .slate: return LocalizedString.text("color_slate")
        }
    }

    var hex: String {
        switch self {
        case .blue: return "2563EB"
        case .teal: return "0F766E"
        case .green: return "16A34A"
        case .amber: return "D97706"
        case .orange: return "EA580C"
        case .red: return "DC2626"
        case .pink: return "DB2777"
        case .violet: return "7C3AED"
        case .slate: return "475569"
        }
    }

    var color: Color {
        Color(canvasHex: hex) ?? .accentColor
    }
}

enum CanvasStylePalette {
    static func normalizedHex(_ hex: String?) -> String? {
        guard let hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).uppercased()
        guard cleaned.count == 6 || cleaned.count == 8 else { return nil }
        return cleaned
    }

    static func color(from hex: String?) -> Color? {
        guard let normalized = normalizedHex(hex) else { return nil }
        return Color(canvasHex: normalized)
    }
}

extension Color {
    init?(canvasHex: String) {
        let cleaned = canvasHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6 || cleaned.count == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }

        let r, g, b, a: UInt64
        if cleaned.count == 8 {
            r = (value >> 24) & 0xff
            g = (value >> 16) & 0xff
            b = (value >> 8) & 0xff
            a = value & 0xff
        } else {
            r = (value >> 16) & 0xff
            g = (value >> 8) & 0xff
            b = value & 0xff
            a = 0xff
        }

        self = Color(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

enum ContentToolbarItem: String, CaseIterable, Codable, Identifiable {
    case view
    case display
    case language

    var id: String { rawValue }

    var title: String {
        switch self {
        case .view: return LocalizedString.text("view_menu")
        case .display: return LocalizedString.text("display_controls")
        case .language: return LocalizedString.language
        }
    }

    static let defaultOrder: [ContentToolbarItem] = [.display, .view, .language]
}

struct CanvasDisplaySettings: Codable {
    var lineWidth: CGFloat = 2
    var textScale: CGFloat = 1
    var lineColor: CanvasColorPreset = .blue
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
    @Published private(set) var canUndoWorkflowChange: Bool = false
    @Published private(set) var canRedoWorkflowChange: Bool = false
    
    // 自动保存定时器
    private var autoSaveTimer: Timer?
    private let autoSaveInterval: TimeInterval = 60 // 每60秒自动保存
    @Published var autoSaveEnabled: Bool = true
    @Published var lastAutoSaveTime: Date?
    @Published var isAutoSaving: Bool = false
    private var workflowUndoStack: [MAProject] = []
    private var workflowRedoStack: [MAProject] = []
    private let persistenceQueue = DispatchQueue(label: "MultiAgentFlow.AppState.persistence", qos: .utility)
    private var latestSilentPersistToken = UUID()
    private var taskGenerationWorkItem: DispatchWorkItem?
    
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
        localizationManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

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

        openClawManager.$status
            .sink { [weak self] status in
                self?.openClawService.syncConnectionStatus(with: status)
            }
            .store(in: &cancellables)

        openClawManager.$isConnected
            .sink { [weak self] isConnected in
                self?.handleOpenClawConnectionChange(isConnected)
            }
            .store(in: &cancellables)
    }

    func updateCanvasDisplaySettings(_ updates: (inout CanvasDisplaySettings) -> Void) {
        var settings = canvasDisplaySettings
        updates(&settings)
        canvasDisplaySettings = settings
        objectWillChange.send()
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

    private func handleOpenClawConnectionChange(_ isConnected: Bool) {
        if !isConnected {
            clearTransientRuntimeState()
        }
        syncCurrentProjectFromManagers()
    }

    private func clearTransientRuntimeState() {
        let blockedCount = taskManager.blockActiveTasks { task in
            task.metadata["source"] == "workbench"
        }

        if var project = currentProject {
            project.runtimeState.messageQueue.removeAll()
            project.runtimeState.agentStates.removeAll()
            project.runtimeState.lastUpdated = Date()
            currentProject = project
        }

        if blockedCount > 0 {
            openClawService.addLog(
                .warning,
                "OpenClaw disconnected. \(blockedCount) active workbench task(s) were marked as blocked."
            )
        }

        openClawService.restoreExecutionSnapshot(
            results: openClawService.executionResults,
            logs: openClawService.executionLogs,
            state: nil
        )
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

                if edge.isBidirectional {
                    let reverseKey = "\(toAgentID.uuidString)->\(fromAgentID.uuidString)"
                    guard seenPairs.insert(reverseKey).inserted else { continue }
                    permissions.append(Permission(fromAgentID: toAgentID, toAgentID: fromAgentID, permissionType: .allow))
                }
            }
        }

        return permissions.sorted { lhs, rhs in
            let leftKey = "\(lhs.fromAgentID.uuidString)->\(lhs.toAgentID.uuidString)"
            let rightKey = "\(rhs.fromAgentID.uuidString)->\(rhs.toAgentID.uuidString)"
            return leftKey < rightKey
        }
    }

    private func enforceUniqueAgentNodes(in workflow: Workflow) -> (workflow: Workflow, removedNodeIDs: [UUID], removedSelfEdgeCount: Int) {
        var mutableWorkflow = workflow
        var seenAgentIDs = Set<UUID>()
        var removedNodeIDs = Set<UUID>()

        mutableWorkflow.nodes = workflow.nodes.filter { node in
            guard node.type == .agent, let agentID = node.agentID else {
                return true
            }
            if seenAgentIDs.insert(agentID).inserted {
                return true
            }
            removedNodeIDs.insert(node.id)
            return false
        }

        let removedSelfEdgeCount = mutableWorkflow.edges.filter { $0.fromNodeID == $0.toNodeID }.count

        mutableWorkflow.edges.removeAll {
            $0.fromNodeID == $0.toNodeID || removedNodeIDs.contains($0.fromNodeID) || removedNodeIDs.contains($0.toNodeID)
        }

        mutableWorkflow.boundaries = mutableWorkflow.boundaries.compactMap { boundary in
            var updatedBoundary = boundary
            let originalCount = updatedBoundary.memberNodeIDs.count
            updatedBoundary.memberNodeIDs.removeAll { removedNodeIDs.contains($0) }
            guard !updatedBoundary.memberNodeIDs.isEmpty else { return nil }
            if updatedBoundary.memberNodeIDs.count != originalCount {
                updatedBoundary.updatedAt = Date()
            }
            return updatedBoundary
        }

        guard !removedNodeIDs.isEmpty || removedSelfEdgeCount > 0 else {
            let normalizedEdges = normalizeWorkflowEdges(in: mutableWorkflow)
            guard normalizedEdges.removedEdgeCount > 0 else {
                return (workflow, [], 0)
            }
            mutableWorkflow = normalizedEdges.workflow
            return (mutableWorkflow, [], normalizedEdges.removedEdgeCount)
        }

        let normalizedEdges = normalizeWorkflowEdges(in: mutableWorkflow)
        mutableWorkflow = normalizedEdges.workflow
        return (mutableWorkflow, Array(removedNodeIDs), removedSelfEdgeCount + normalizedEdges.removedEdgeCount)
    }

    private func enforceUniqueAgentNodes(in workflows: [Workflow]) -> (workflows: [Workflow], removedNodeCount: Int, removedSelfEdgeCount: Int) {
        var totalRemoved = 0
        var totalSelfEdgeRemoved = 0
        let sanitized = workflows.map { workflow -> Workflow in
            let result = enforceUniqueAgentNodes(in: workflow)
            totalRemoved += result.removedNodeIDs.count
            totalSelfEdgeRemoved += result.removedSelfEdgeCount
            return result.workflow
        }
        return (sanitized, totalRemoved, totalSelfEdgeRemoved)
    }

    private func normalizeWorkflowEdges(in workflow: Workflow) -> (workflow: Workflow, removedEdgeCount: Int) {
        guard !workflow.edges.isEmpty else { return (workflow, 0) }

        var mutableWorkflow = workflow
        var grouped: [String: [WorkflowEdge]] = [:]
        for edge in workflow.edges {
            let key = undirectedEdgeKey(from: edge.fromNodeID, to: edge.toNodeID)
            grouped[key, default: []].append(edge)
        }

        var normalizedEdges: [WorkflowEdge] = []
        var removedEdgeCount = 0

        for group in grouped.values {
            guard let first = group.first else { continue }
            var edge = first
            edge.isBidirectional = group.contains(where: { $0.isBidirectional }) || Set(group.map { directedEdgeKey(from: $0.fromNodeID, to: $0.toNodeID) }).count > 1
            normalizedEdges.append(edge)
            removedEdgeCount += max(0, group.count - 1)
        }

        normalizedEdges.sort { lhs, rhs in
            let leftKey = "\(lhs.fromNodeID.uuidString)->\(lhs.toNodeID.uuidString)"
            let rightKey = "\(rhs.fromNodeID.uuidString)->\(rhs.toNodeID.uuidString)"
            return leftKey < rightKey
        }

        mutableWorkflow.edges = normalizedEdges
        return (mutableWorkflow, removedEdgeCount)
    }
    
    private func performAutoSave() {
        guard autoSaveEnabled, let project = snapshotCurrentProject() else { return }
        
        isAutoSaving = true
        
        // 保存到用户默认目录
        let fileManager = FileManager.default
        let projectDir = projectManager.autoSaveDirectory
        
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
        let projectDir = projectManager.autoSaveDirectory
        
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
        teardownCurrentProjectSession(persistProject: currentProject != nil, clearProjectReference: true)

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
        persistProjectSilently(project)
    }

    private func teardownCurrentProjectSession(
        persistProject: Bool,
        clearProjectReference: Bool
    ) {
        let shouldPersist = persistProject && currentProject != nil
        openClawManager.disconnect()
        if shouldPersist {
            syncCurrentProjectFromManagers()
            persistCurrentProjectSilently()
        }
        taskManager.reset()
        messageManager.reset()
        openClawService.resetExecutionSnapshot()
        selectedNodeID = nil

        if clearProjectReference {
            currentProjectFileURL = nil
            currentProject = nil
        }
    }

    @discardableResult
    private func writeAgentSoulToProjectMirror(
        agent: Agent,
        project: MAProject
    ) -> (success: Bool, message: String, path: String?) {
        guard let soulURL = openClawManager.projectMirrorSoulURL(for: agent, in: project) else {
            return (false, "未找到可写入的项目镜像 SOUL.md 路径。", nil)
        }

        do {
            try FileManager.default.createDirectory(at: soulURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try agent.soulMD.write(to: soulURL, atomically: true, encoding: .utf8)
            return (true, "已写入 \(soulURL.path)", soulURL.path)
        } catch {
            return (false, "写入项目镜像 SOUL.md 失败: \(error.localizedDescription)", nil)
        }
    }
    
    // 关闭当前项目
    func closeProject() {
        teardownCurrentProjectSession(persistProject: true, clearProjectReference: true)
    }
    
    func deleteCurrentProject() {
        guard let project = currentProject, let currentProjectFileURL else { return }
        teardownCurrentProjectSession(persistProject: false, clearProjectReference: true)
        projectManager.deleteProject(at: currentProjectFileURL, projectID: project.id)
    }

    func shutdown() {
        openClawManager.disconnect()
        if currentProject != nil {
            syncCurrentProjectFromManagers()
            persistCurrentProjectSilently()
        }
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
            teardownCurrentProjectSession(persistProject: currentProject != nil, clearProjectReference: true)
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
        let deduplication = enforceUniqueAgentNodes(in: hydratedProject.workflows)
        hydratedProject.workflows = deduplication.workflows
        hydratedProject.workspaceIndex = ensureWorkspaceIndex(
            for: hydratedProject.id,
            tasks: project.tasks,
            existing: project.workspaceIndex
        )
        if !hydratedProject.workflows.isEmpty {
            hydratedProject.permissions = conversationPermissions(for: hydratedProject.workflows)
        }
        currentProject = hydratedProject

        if deduplication.removedNodeCount > 0 {
            openClawService.addLog(
                .warning,
                "检测到重复 Agent 节点，已自动清理 \(deduplication.removedNodeCount) 个重复节点。"
            )
        }
        if deduplication.removedSelfEdgeCount > 0 {
            openClawService.addLog(
                .warning,
                "检测到自连接，已自动清理 \(deduplication.removedSelfEdgeCount) 条非法连线。"
            )
        }
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
        guard let project = snapshotCurrentProject() else {
            completion?(false, "请先创建或打开项目，再确认连接 OpenClaw。")
            return
        }

        if let config {
            openClawManager.config = config
            openClawManager.config.save()
        }

        currentProject = project
        openClawManager.connect(for: project) { [weak self] success, message in
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
        openClawManager.disconnect()
        syncCurrentProjectFromManagers()
        if currentProject != nil {
            persistCurrentProjectSilently()
        }
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

    private func persistProjectSilently(_ project: MAProject) {
        let destinationURL = currentProjectFileURL ?? projectManager.projectURL(for: project.name)
        let token = UUID()
        latestSilentPersistToken = token

        persistenceQueue.async { [weak self] in
            guard let self else { return }

            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(project)
                try data.write(to: destinationURL, options: .atomic)

                DispatchQueue.main.async {
                    guard self.latestSilentPersistToken == token else { return }
                    self.currentProjectFileURL = destinationURL
                    self.projectManager.loadProjectList()
                }
            } catch {
                DispatchQueue.main.async {
                    print("静默保存项目失败: \(error)")
                }
            }
        }
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
        var normalizedProject = project
        let deduplication = enforceUniqueAgentNodes(in: normalizedProject.workflows)
        normalizedProject.workflows = deduplication.workflows
        if !normalizedProject.workflows.isEmpty {
            normalizedProject.permissions = conversationPermissions(for: normalizedProject.workflows)
        }

        currentProjectFileURL = nil
        taskManager.replaceTasks(tasks)
        messageManager.reset()
        openClawService.resetExecutionSnapshot()
        currentProject = normalizedProject
        if let snapshot = snapshotCurrentProject() {
            currentProject = snapshot
        }

        if deduplication.removedNodeCount > 0 {
            openClawService.addLog(
                .warning,
                "导入项目时清理了 \(deduplication.removedNodeCount) 个重复 Agent 节点。"
            )
        }
        if deduplication.removedSelfEdgeCount > 0 {
            openClawService.addLog(
                .warning,
                "导入项目时清理了 \(deduplication.removedSelfEdgeCount) 条自连接。"
            )
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
        let snappedRect = snapRectToGrid(
            CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        )

        updateMainWorkflow { workflow in
            var boundary = WorkflowBoundary(
                title: "Boundary \(workflow.boundaries.count + 1)",
                rect: snappedRect,
                memberNodeIDs: nodes.map(\.id)
            )
            boundary.updatedAt = Date()
            workflow.boundaries.append(boundary)
        }
    }

    func removeBoundary(around nodeIDs: Set<UUID>) {
        guard !nodeIDs.isEmpty else { return }

        guard let workflow = currentProject?.workflows.first else { return }
        let selectedNodePositions = workflow.nodes
            .filter { nodeIDs.contains($0.id) }
            .map(\.position)
        guard !selectedNodePositions.isEmpty else { return }

        updateMainWorkflow { workflow in
            workflow.boundaries.removeAll { boundary in
                selectedNodePositions.allSatisfy { boundary.contains(point: $0) }
            }
        }
    }

    func removeBoundary(containing nodeID: UUID) {
        guard let workflow = currentProject?.workflows.first,
              let node = workflow.nodes.first(where: { $0.id == nodeID }) else { return }
        updateMainWorkflow { workflow in
            workflow.boundaries.removeAll { $0.contains(point: node.position) }
        }
    }

    func removeBoundaries(_ boundaryIDs: Set<UUID>) {
        guard !boundaryIDs.isEmpty else { return }
        updateMainWorkflow { workflow in
            workflow.boundaries.removeAll { boundaryIDs.contains($0.id) }
        }
    }

    func boundary(for nodeID: UUID) -> WorkflowBoundary? {
        guard let workflow = currentProject?.workflows.first,
              let node = workflow.nodes.first(where: { $0.id == nodeID }) else {
            return nil
        }
        return workflow.boundary(containing: node.position)
    }

    func snapPointToGrid(
        _ point: CGPoint,
        gridSize: CGFloat = 20,
        threshold: CGFloat = 8
    ) -> CGPoint {
        _ = threshold
        func snap(_ value: CGFloat) -> CGFloat {
            (value / gridSize).rounded() * gridSize
        }

        return CGPoint(x: snap(point.x), y: snap(point.y))
    }

    func snapRectToGrid(
        _ rect: CGRect,
        gridSize: CGFloat = 20,
        threshold: CGFloat = 8
    ) -> CGRect {
        let snappedMinX = snapPointToGrid(CGPoint(x: rect.minX, y: 0), gridSize: gridSize, threshold: threshold).x
        let snappedMinY = snapPointToGrid(CGPoint(x: 0, y: rect.minY), gridSize: gridSize, threshold: threshold).y
        let snappedMaxX = snapPointToGrid(CGPoint(x: rect.maxX, y: 0), gridSize: gridSize, threshold: threshold).x
        let snappedMaxY = snapPointToGrid(CGPoint(x: 0, y: rect.maxY), gridSize: gridSize, threshold: threshold).y

        return CGRect(
            x: min(snappedMinX, snappedMaxX),
            y: min(snappedMinY, snappedMaxY),
            width: abs(snappedMaxX - snappedMinX),
            height: abs(snappedMaxY - snappedMinY)
        )
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
        let deduplication = enforceUniqueAgentNodes(in: workflow)
        currentProject?.workflows[index] = deduplication.workflow
        if var syncedWorkflow = currentProject?.workflows[index] {
            syncCanvasColorGroups(in: &syncedWorkflow)
            currentProject?.workflows[index] = syncedWorkflow
        }
        currentProject?.updatedAt = Date()
        objectWillChange.send()
        
        // 避免频繁拖拽/编辑时反复同步任务列表。
        scheduleTaskGeneration()

        if !deduplication.removedNodeIDs.isEmpty {
            openClawService.addLog(
                .warning,
                "工作流中存在重复 Agent 节点，已移除 \(deduplication.removedNodeIDs.count) 个重复项。"
            )
        }
        if deduplication.removedSelfEdgeCount > 0 {
            openClawService.addLog(
                .warning,
                "工作流中存在自连接，已移除 \(deduplication.removedSelfEdgeCount) 条非法连线。"
            )
        }
    }

    func updateMainWorkflow(_ updates: (inout Workflow) -> Void) {
        guard ensureMainWorkflow() != nil,
              var project = currentProject,
              let index = project.workflows.indices.first else { return }

        pushWorkflowUndoSnapshot()
        updates(&project.workflows[index])
        let deduplication = enforceUniqueAgentNodes(in: project.workflows[index])
        project.workflows[index] = deduplication.workflow
        syncCanvasColorGroups(in: &project.workflows[index])
        syncConversationPermissions(for: project.workflows, in: &project)
        project.updatedAt = Date()
        currentProject = project
        objectWillChange.send()
        scheduleTaskGeneration()

        if !deduplication.removedNodeIDs.isEmpty {
            openClawService.addLog(
                .warning,
                "工作流中存在重复 Agent 节点，已移除 \(deduplication.removedNodeIDs.count) 个重复项。"
            )
        }
        if deduplication.removedSelfEdgeCount > 0 {
            openClawService.addLog(
                .warning,
                "工作流中存在自连接，已移除 \(deduplication.removedSelfEdgeCount) 条非法连线。"
            )
        }
    }

    func undoWorkflowChange() {
        guard let current = currentProject,
              let previous = workflowUndoStack.popLast() else { return }

        workflowRedoStack.append(current)
        currentProject = previous
        canUndoWorkflowChange = !workflowUndoStack.isEmpty
        canRedoWorkflowChange = true
        scheduleTaskGeneration()
    }

    func redoWorkflowChange() {
        guard let current = currentProject,
              let next = workflowRedoStack.popLast() else { return }

        workflowUndoStack.append(current)
        currentProject = next
        canUndoWorkflowChange = !workflowUndoStack.isEmpty
        canRedoWorkflowChange = !workflowRedoStack.isEmpty
        scheduleTaskGeneration()
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

    private func pushWorkflowUndoSnapshot() {
        guard let project = currentProject else { return }
        workflowUndoStack.append(project)
        if workflowUndoStack.count > 50 {
            workflowUndoStack.removeFirst(workflowUndoStack.count - 50)
        }
        workflowRedoStack.removeAll()
        canUndoWorkflowChange = true
        canRedoWorkflowChange = false
    }

    func addNode(type: WorkflowNode.NodeType, position: CGPoint) {
        let snappedPosition = snapPointToGrid(position)
        switch type {
        case .start:
            updateMainWorkflow { workflow in
                guard !workflow.nodes.contains(where: { $0.type == .start }) else { return }
                var node = WorkflowNode(type: .start)
                node.position = snappedPosition
                workflow.nodes.insert(node, at: 0)
            }
        case .agent:
            updateMainWorkflow { workflow in
                var node = WorkflowNode(type: type)
                node.position = snappedPosition
                workflow.nodes.append(node)
            }
        }
    }

    func addAgentNode(agentName: String, position: CGPoint) {
        guard let agent = ensureAgent(named: agentName, description: "OpenClaw Agent: \(agentName)") else { return }

        _ = ensureAgentNode(agentID: agent.id, suggestedPosition: snapPointToGrid(position))
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

        updateMainWorkflow { workflow in
            upsertEdge(from: fromNodeID, to: toNodeID, bidirectional: bidirectional, workflow: &workflow)
        }

        if let sourceAgentID = currentProject?.workflows.first?.nodes.first(where: { $0.id == fromNodeID })?.agentID,
           let targetAgentID = currentProject?.workflows.first?.nodes.first(where: { $0.id == toNodeID })?.agentID {
            setPermission(fromAgentID: sourceAgentID, toAgentID: targetAgentID, type: .allow)
            if bidirectional {
                setPermission(fromAgentID: targetAgentID, toAgentID: sourceAgentID, type: .allow)
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

        guard sourceNodeID != targetNodeID else { return }

        // 当前编辑器支持 start/agent 两类节点连线；仅在 agent<->agent 时自动补权限。
        let supportedTypes: Set<WorkflowNode.NodeType> = [.start, .agent]
        if !supportedTypes.contains(sourceNode.type) || !supportedTypes.contains(targetNode.type) {
            return
        }

        updateMainWorkflow { workflow in
            upsertEdge(from: sourceNodeID, to: targetNodeID, bidirectional: bidirectional, workflow: &workflow)
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
        scheduleTaskGeneration()
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

    func setNodeColor(_ colorHex: String?, for nodeIDs: Set<UUID>) {
        guard !nodeIDs.isEmpty else { return }
        let normalizedColorHex = CanvasStylePalette.normalizedHex(colorHex)
        updateMainWorkflow { workflow in
            for index in workflow.nodes.indices where nodeIDs.contains(workflow.nodes[index].id) {
                workflow.nodes[index].displayColorHex = normalizedColorHex
            }
            syncCanvasColorGroups(in: &workflow)
        }
    }

    func setEdgeColor(_ colorHex: String?, for edgeIDs: Set<UUID>) {
        guard !edgeIDs.isEmpty else { return }
        let normalizedColorHex = CanvasStylePalette.normalizedHex(colorHex)
        updateMainWorkflow { workflow in
            for index in workflow.edges.indices where edgeIDs.contains(workflow.edges[index].id) {
                workflow.edges[index].displayColorHex = normalizedColorHex
            }
            syncCanvasColorGroups(in: &workflow)
        }
    }

    func updateColorGroupTitle(kind: CanvasGroupKind, colorHex: String, title: String) {
        guard let normalizedHex = CanvasStylePalette.normalizedHex(colorHex) else { return }
        updateMainWorkflow { workflow in
            upsertCanvasColorGroup(
                in: &workflow,
                group: CanvasColorGroup(
                    kind: kind,
                    colorHex: normalizedHex,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
            syncCanvasColorGroups(in: &workflow)
        }
    }

    private func upsertCanvasColorGroup(in workflow: inout Workflow, group: CanvasColorGroup) {
        if let index = workflow.colorGroups.firstIndex(where: {
            $0.kind == group.kind && CanvasStylePalette.normalizedHex($0.colorHex) == CanvasStylePalette.normalizedHex(group.colorHex)
        }) {
            workflow.colorGroups[index].colorHex = group.colorHex
            workflow.colorGroups[index].title = group.title
        } else {
            workflow.colorGroups.append(group)
        }
    }

    private func syncCanvasColorGroups(in workflow: inout Workflow) {
        let usedNodeColors = Set(workflow.nodes.compactMap { CanvasStylePalette.normalizedHex($0.displayColorHex) })
        let usedEdgeColors = Set(workflow.edges.compactMap { CanvasStylePalette.normalizedHex($0.displayColorHex) })

        var syncedGroups: [CanvasColorGroup] = []
        for kind in CanvasGroupKind.allCases {
            let usedColors = kind == .node ? usedNodeColors : usedEdgeColors
            let existingGroups = workflow.colorGroups.filter { $0.kind == kind }

            for colorHex in usedColors.sorted() {
                if let existing = existingGroups.first(where: {
                    CanvasStylePalette.normalizedHex($0.colorHex) == colorHex
                }) {
                    syncedGroups.append(
                        CanvasColorGroup(
                            kind: kind,
                            colorHex: colorHex,
                            title: existing.title
                        )
                    )
                } else {
                    syncedGroups.append(
                        CanvasColorGroup(
                            kind: kind,
                            colorHex: colorHex,
                            title: ""
                        )
                    )
                }
            }
        }

        workflow.colorGroups = syncedGroups.sorted {
            if $0.kind != $1.kind {
                return ($0.kind == .node ? 0 : 1) < ($1.kind == .node ? 0 : 1)
            }
            return $0.colorHex < $1.colorHex
        }
    }

    func setEdgeCommunicationDirection(edgeID: UUID, bidirectional: Bool) {
        guard let workflow = currentProject?.workflows.first,
              let edge = workflow.edges.first(where: { $0.id == edgeID }) else { return }

        updateMainWorkflow { workflow in
            guard let edgeIndex = workflow.edges.firstIndex(where: { $0.id == edgeID }) else { return }
            workflow.edges[edgeIndex].isBidirectional = bidirectional
        }

        if let sourceAgentID = workflow.nodes.first(where: { $0.id == edge.fromNodeID })?.agentID,
           let targetAgentID = workflow.nodes.first(where: { $0.id == edge.toNodeID })?.agentID {
            setPermission(fromAgentID: sourceAgentID, toAgentID: targetAgentID, type: .allow)
            if bidirectional {
                setPermission(fromAgentID: targetAgentID, toAgentID: sourceAgentID, type: .allow)
            }
        }
    }

    func flipEdgeDirection(edgeID: UUID) {
        updateMainWorkflow { workflow in
            guard let index = workflow.edges.firstIndex(where: { $0.id == edgeID }),
                  !workflow.edges[index].isBidirectional else { return }
            let fromNodeID = workflow.edges[index].fromNodeID
            workflow.edges[index].fromNodeID = workflow.edges[index].toNodeID
            workflow.edges[index].toNodeID = fromNodeID
        }
    }

    func updateAgent(_ updatedAgent: Agent, reload: Bool = false) {
        guard var project = currentProject,
              let index = project.agents.firstIndex(where: { $0.id == updatedAgent.id }) else { return }

        project.agents[index] = updatedAgent
        project.updatedAt = Date()
        currentProject = project
        objectWillChange.send()

        let mirrorWrite = writeAgentSoulToProjectMirror(agent: updatedAgent, project: project)
        if mirrorWrite.success, let path = mirrorWrite.path,
           let refreshedProject = currentProject,
           let refreshedIndex = refreshedProject.agents.firstIndex(where: { $0.id == updatedAgent.id }) {
            currentProject?.agents[refreshedIndex].openClawDefinition.soulSourcePath = path
        }
        persistCurrentProjectSilently()

        openClawManager.syncProjectAgentsToActiveSession(project) { [weak self] success, message in
            guard let self else { return }
            DispatchQueue.main.async {
                self.openClawService.addLog(success ? .success : .warning, message)
            }
        }

        if reload {
            reloadAgent(updatedAgent.id)
        }
    }

    func loadAgentSoulMDFromSource(agentID: UUID) -> (content: String, sourcePath: String?)? {
        guard let project = currentProject,
              let agent = project.agents.first(where: { $0.id == agentID }) else { return nil }

        if let mirrorURL = openClawManager.projectMirrorSoulURL(for: agent, in: project),
           FileManager.default.fileExists(atPath: mirrorURL.path),
           let content = try? String(contentsOf: mirrorURL, encoding: .utf8) {
            return (content, mirrorURL.path)
        }

        guard let soulURL = existingAgentSoulFileURL(for: agent) else {
            return (agent.soulMD, nil)
        }

        if let content = try? String(contentsOf: soulURL, encoding: .utf8) {
            return (content, soulURL.path)
        }
        return (agent.soulMD, nil)
    }

    func persistAgentSoulMDToSource(agentID: UUID, soulMD: String) -> (success: Bool, message: String) {
        guard var project = currentProject,
              let index = project.agents.firstIndex(where: { $0.id == agentID }) else {
            return (false, "未找到目标 Agent。")
        }

        var agent = project.agents[index]
        agent.soulMD = soulMD

        let mirrorWrite = writeAgentSoulToProjectMirror(agent: agent, project: project)
        guard mirrorWrite.success else {
            return (false, mirrorWrite.message)
        }

        if let path = mirrorWrite.path {
            project.agents[index].openClawDefinition.soulSourcePath = path
        }
        project.agents[index].soulMD = soulMD
        project.agents[index].updatedAt = Date()
        project.updatedAt = Date()
        currentProject = project
        objectWillChange.send()
        persistCurrentProjectSilently()

        return (true, mirrorWrite.message)
    }

    func refreshAgentSoulMDFromSource(agentID: UUID) -> (success: Bool, message: String) {
        guard var project = currentProject,
              let index = project.agents.firstIndex(where: { $0.id == agentID }) else {
            return (false, "未找到目标 Agent。")
        }

        let agent = project.agents[index]
        guard let soulURL = existingAgentSoulFileURL(for: agent) else {
            return (false, "未找到真实 SOUL.md 文件，当前仅存在项目缓存。")
        }

        do {
            let content = try String(contentsOf: soulURL, encoding: .utf8)
            project.agents[index].soulMD = content
            project.agents[index].openClawDefinition.soulSourcePath = soulURL.path
            project.agents[index].updatedAt = Date()
            project.updatedAt = Date()
            currentProject = project
            objectWillChange.send()
            persistCurrentProjectSilently()
            return (true, "已从 \(soulURL.path) 重新加载")
        } catch {
            return (false, "读取 SOUL.md 失败: \(error.localizedDescription)")
        }
    }

    func agentSoulFileURL(for agentID: UUID) -> URL? {
        guard let agent = currentProject?.agents.first(where: { $0.id == agentID }) else { return nil }
        return existingAgentSoulFileURL(for: agent)
    }

    func agentWorkspaceURL(for agentID: UUID) -> URL? {
        guard let agent = currentProject?.agents.first(where: { $0.id == agentID }) else { return nil }

        let candidateNames = [
            agent.openClawDefinition.agentIdentifier,
            agent.name
        ]

        if let workspacePath = openClawManager.localAgentWorkspacePath(matching: candidateNames) {
            return URL(fileURLWithPath: workspacePath, isDirectory: true)
        }

        if let soulURL = existingAgentSoulFileURL(for: agent) {
            return soulURL.deletingLastPathComponent()
        }

        return agentSoulRootURL(for: agent)
    }

    @discardableResult
    func focusAgentNode(
        agentID: UUID,
        createIfMissing: Bool = true,
        suggestedPosition: CGPoint = .zero
    ) -> UUID? {
        let nodeID: UUID?
        if createIfMissing {
            nodeID = ensureAgentNode(agentID: agentID, suggestedPosition: suggestedPosition)
        } else {
            nodeID = workflowNodeID(for: agentID)
        }

        if let nodeID {
            selectedNodeID = nodeID
        }
        return nodeID
    }

    func workflowNodeID(for agentID: UUID) -> UUID? {
        currentProject?.workflows.first?.nodes.first(where: { $0.agentID == agentID && $0.type == .agent })?.id
    }

    func connectionSummary(for agentID: UUID) -> (incoming: Int, outgoing: Int) {
        guard let workflow = currentProject?.workflows.first,
              let nodeID = workflowNodeID(for: agentID) else {
            return (0, 0)
        }

        let incoming = workflow.edges.filter { $0.toNodeID == nodeID }.count
        let outgoing = workflow.edges.filter { $0.fromNodeID == nodeID }.count
        return (incoming, outgoing)
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

    private func resolveAgentSoulFileURL(for agent: Agent) -> URL? {
        if let existingSoulURL = existingAgentSoulFileURL(for: agent) {
            return existingSoulURL
        }

        guard let rootURL = agentSoulRootURL(for: agent) else { return nil }
        return preferredSoulURL(in: rootURL)
    }

    private func existingAgentSoulFileURL(for agent: Agent) -> URL? {
        if let directPath = firstNonEmptyPath(agent.openClawDefinition.soulSourcePath) {
            let directURL = URL(fileURLWithPath: directPath, isDirectory: false)
            if FileManager.default.fileExists(atPath: directURL.path) {
                return directURL
            }
            if let nearbySoulURL = existingSoulFileURL(in: directURL.deletingLastPathComponent()) {
                return nearbySoulURL
            }
        }

        for rootURL in agentSoulRootCandidates(for: agent) {
            if let soulURL = existingSoulFileURL(in: rootURL) {
                return soulURL
            }
        }
        return nil
    }

    private func agentSoulRootCandidates(for agent: Agent) -> [URL] {
        var roots: [URL] = []

        if let project = currentProject,
           let mirrorURL = openClawManager.projectMirrorSoulURL(for: agent, in: project) {
            roots.append(mirrorURL.deletingLastPathComponent())
        }

        let candidateNames = [
            agent.openClawDefinition.agentIdentifier,
            agent.name
        ]

        if let workspaceSoulURL = openClawManager.localAgentSoulURL(matching: candidateNames) {
            roots.append(workspaceSoulURL.deletingLastPathComponent())
        }

        if let directPath = firstNonEmptyPath(agent.openClawDefinition.soulSourcePath) {
            let directURL = URL(fileURLWithPath: directPath, isDirectory: false)
            roots.append(directURL.deletingLastPathComponent())
        }

        let keys = Set(candidateNames.map(normalizeAgentKey).filter { !$0.isEmpty })

        if !keys.isEmpty {
            if let record = openClawManager.discoveryResults.first(where: { keys.contains(normalizeAgentKey($0.name)) }) {
                if let copied = firstNonEmptyPath(record.copiedToProjectPath) {
                    roots.append(URL(fileURLWithPath: copied, isDirectory: true))
                }
                if let directory = firstNonEmptyPath(record.directoryPath) {
                    roots.append(URL(fileURLWithPath: directory, isDirectory: true))
                }
            }
        }

        if let memoryBackupPath = firstNonEmptyPath(agent.openClawDefinition.memoryBackupPath) {
            let privateURL = URL(fileURLWithPath: memoryBackupPath, isDirectory: true)
            let rootURL = privateURL.lastPathComponent == "private" ? privateURL.deletingLastPathComponent() : privateURL
            roots.append(rootURL)
        }

        var seen: Set<String> = []
        return roots.filter { seen.insert($0.path).inserted }
    }

    private func agentSoulRootURL(for agent: Agent) -> URL? {
        agentSoulRootCandidates(for: agent).first
    }

    private func existingSoulFileURL(in rootURL: URL) -> URL? {
        for ancestor in ancestorDirectories(from: rootURL, maxDepth: 3) {
            let preferred = ancestor.appendingPathComponent("SOUL.md")
            if FileManager.default.fileExists(atPath: preferred.path) {
                return preferred
            }

            let fallback = ancestor.appendingPathComponent("soul.md")
            if FileManager.default.fileExists(atPath: fallback.path) {
                return fallback
            }
        }
        return nil
    }

    private func ancestorDirectories(from url: URL, maxDepth: Int) -> [URL] {
        var directories: [URL] = [url]
        var current = url

        for _ in 0..<maxDepth {
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path || parent.path.isEmpty {
                break
            }
            directories.append(parent)
            current = parent
        }

        return directories
    }

    private func preferredSoulURL(in rootURL: URL) -> URL {
        let preferred = rootURL.appendingPathComponent("SOUL.md")
        let fallback = rootURL.appendingPathComponent("soul.md")
        if FileManager.default.fileExists(atPath: preferred.path) { return preferred }
        if FileManager.default.fileExists(atPath: fallback.path) { return fallback }
        return preferred
    }

    private func firstNonEmptyPath(_ candidates: String?...) -> String? {
        for candidate in candidates {
            guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                continue
            }
            return trimmed
        }
        return nil
    }

    private func normalizeAgentKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

        syncOpenClawCommunicationAllowListIfNeeded(project: project, reason: "permission_updated")
    }

    private func syncOpenClawCommunicationAllowListIfNeeded(
        project: MAProject,
        reason: String,
        then: (() -> Void)? = nil
    ) {
        var projected = project
        projected.permissions = conversationPermissions(for: projected.workflows)

        openClawManager.syncAgentCommunicationAllowLists(from: projected, using: openClawManager.config) { [weak self] success, message in
            guard let self else {
                then?()
                return
            }

            let level: ExecutionLogEntry.LogLevel = success ? .info : .warning
            self.openClawService.addLog(level, "[\(reason)] \(message)")
            then?()
        }
    }

    private func upsertEdge(from sourceNodeID: UUID, to targetNodeID: UUID, bidirectional: Bool, workflow: inout Workflow) {
        if let index = workflow.edges.firstIndex(where: {
            (directedEdgeKey(from: $0.fromNodeID, to: $0.toNodeID) == directedEdgeKey(from: sourceNodeID, to: targetNodeID)) ||
            (directedEdgeKey(from: $0.fromNodeID, to: $0.toNodeID) == directedEdgeKey(from: targetNodeID, to: sourceNodeID))
        }) {
            workflow.edges[index].fromNodeID = sourceNodeID
            workflow.edges[index].toNodeID = targetNodeID
            workflow.edges[index].isBidirectional = bidirectional
        } else {
            var edge = WorkflowEdge(from: sourceNodeID, to: targetNodeID)
            edge.isBidirectional = bidirectional
            workflow.edges.append(edge)
        }
    }

    private func directedEdgeKey(from sourceNodeID: UUID, to targetNodeID: UUID) -> String {
        "\(sourceNodeID.uuidString)->\(targetNodeID.uuidString)"
    }

    private func undirectedEdgeKey(from sourceNodeID: UUID, to targetNodeID: UUID) -> String {
        let first = sourceNodeID.uuidString
        let second = targetNodeID.uuidString
        return first < second ? "\(first)|\(second)" : "\(second)|\(first)"
    }
    
    // 从工作流生成任务
    func generateTasksFromWorkflow() {
        guard let workflow = currentProject?.workflows.first,
              let agents = currentProject?.agents else { return }
        
        taskManager.generateTasks(from: workflow, projectAgents: agents)
    }

    private func scheduleTaskGeneration(delay: TimeInterval = 0.12) {
        taskGenerationWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.generateTasksFromWorkflow()
        }
        taskGenerationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func workflow(for workflowID: UUID?) -> Workflow? {
        guard let project = currentProject else { return nil }
        if let workflowID {
            return project.workflows.first { $0.id == workflowID }
        }
        return project.workflows.first
    }

    @discardableResult
    func runWorkflowLaunchVerification(
        workflowID: UUID? = nil,
        completion: ((WorkflowLaunchVerificationReport) -> Void)? = nil
    ) -> Bool {
        guard let project = currentProject,
              let workflow = self.workflow(for: workflowID) else {
            return false
        }

        guard !openClawService.isExecuting else {
            openClawService.addLog(.warning, "Launch verification is unavailable while another workflow execution is in progress.")
            return false
        }

        openClawService.addLog(.info, "Manual launch verification requested for workflow \(workflow.name).")
        verifyWorkflowBeforeLaunch(workflow, agents: project.agents) { [weak self] report in
            guard let self else { return }

            switch report.status {
            case .fail:
                self.openClawService.addLog(.error, "Workflow launch verification failed for \(workflow.name).")
            case .warn:
                self.openClawService.addLog(.warning, "Workflow launch verification completed with warnings for \(workflow.name).")
            case .pass:
                self.openClawService.addLog(.success, "Workflow launch verification passed for \(workflow.name).")
            }

            completion?(report)
        }

        return true
    }

    private func verifyWorkflowBeforeLaunch(
        _ workflow: Workflow,
        agents: [Agent],
        completion: @escaping (WorkflowLaunchVerificationReport) -> Void
    ) {
        let signature = workflowVerificationSignature(for: workflow, agents: agents)
        var report = WorkflowLaunchVerificationReport(
            workflowID: workflow.id,
            workflowName: workflow.name,
            workflowSignature: signature
        )
        persistLaunchVerificationReport(report, for: workflow.id)

        let staticEvaluation = staticVerificationFindings(for: workflow, agents: agents)
        report.staticFindings = staticEvaluation.findings
        report.status = staticEvaluation.status
        persistLaunchVerificationReport(report, for: workflow.id)

        let testCases = effectiveLaunchTestCases(for: workflow, agents: agents)
        if workflow.launchTestCases.isEmpty {
            openClawService.addLog(.info, "Workflow \(workflow.name) 未配置自定义启动验证用例，已使用系统自动生成的默认用例集。")
        }

        guard staticEvaluation.status != .fail else {
            report.completedAt = Date()
            persistLaunchVerificationReport(report, for: workflow.id)
            completion(report)
            return
        }

        guard !testCases.isEmpty else {
            report.completedAt = Date()
            persistLaunchVerificationReport(report, for: workflow.id)
            completion(report)
            return
        }

        openClawService.addLog(.info, "Starting launch verification for workflow \(workflow.name) with \(testCases.count) test case(s).")

        func runCase(at index: Int) {
            if index >= testCases.count {
                report.completedAt = Date()
                report.status = aggregateVerificationStatus(
                    initial: staticEvaluation.status,
                    report.runtimeFindings,
                    caseReports: report.testCaseReports
                )
                persistLaunchVerificationReport(report, for: workflow.id)
                completion(report)
                return
            }

            let testCase = testCases[index]
            let logStartIndex = openClawService.executionLogs.count
            openClawService.addLog(.info, "Launch verification case \(index + 1)/\(testCases.count): \(testCase.name)")

            openClawService.executeWorkflow(
                workflow,
                agents: agents,
                prompt: testCase.prompt,
                agentOutputMode: .structuredJSON
            ) { [weak self] results in
                guard let self else { return }

                let caseLogs = Array(self.openClawService.executionLogs.dropFirst(logStartIndex))
                let caseReport = self.evaluateLaunchTestCase(
                    testCase,
                    workflow: workflow,
                    agents: agents,
                    results: results,
                    logs: caseLogs
                )
                report.testCaseReports.append(caseReport)

                if caseReport.status == .fail {
                    self.openClawService.addLog(.error, "Launch verification case failed: \(testCase.name)")
                } else if caseReport.status == .warn {
                    self.openClawService.addLog(.warning, "Launch verification case warned: \(testCase.name)")
                } else {
                    self.openClawService.addLog(.success, "Launch verification case passed: \(testCase.name)")
                }

                let routingWarnings = caseLogs.compactMap { entry -> String? in
                    guard entry.isRoutingEvent || entry.level == .error else { return nil }
                    return entry.message
                }
                report.runtimeFindings.append(contentsOf: routingWarnings)
                runCase(at: index + 1)
            }
        }

        runCase(at: 0)
    }

    private func effectiveLaunchTestCases(for workflow: Workflow, agents: [Agent]) -> [WorkflowLaunchTestCase] {
        if !workflow.launchTestCases.isEmpty {
            return workflow.launchTestCases
        }
        return defaultLaunchTestCases(for: workflow, agents: agents)
    }

    private func defaultLaunchTestCases(for workflow: Workflow, agents: [Agent]) -> [WorkflowLaunchTestCase] {
        let entryNodes = entryConnectedAgentNodes(in: workflow)
        let entryAgentIDs = Set(entryNodes.compactMap(\.agentID))
        let entryAgentNames = agents
            .filter { entryAgentIDs.contains($0.id) }
            .map(\.name)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let nonEntryAgentNames = agents
            .filter { !entryAgentIDs.contains($0.id) }
            .map(\.name)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        let strictStepLimit = max(1, entryAgentNames.count)
        var cases: [WorkflowLaunchTestCase] = [
            WorkflowLaunchTestCase(
                name: "Greeting Smoke",
                prompt: "你好",
                requiredAgentNames: entryAgentNames,
                forbiddenAgentNames: nonEntryAgentNames,
                expectedRoutingActions: ["stop"],
                expectedOutputTypes: [ExecutionOutputType.agentFinalResponse.rawValue],
                maxSteps: strictStepLimit,
                notes: "简单问候不应误触发下游协作。"
            ),
            WorkflowLaunchTestCase(
                name: "Direct Reply Smoke",
                prompt: "请用一句话确认你已准备就绪；如果不需要下游协作，就不要联系任何下游。",
                requiredAgentNames: entryAgentNames,
                forbiddenAgentNames: nonEntryAgentNames,
                expectedRoutingActions: ["stop"],
                expectedOutputTypes: [ExecutionOutputType.agentFinalResponse.rawValue],
                maxSteps: strictStepLimit,
                notes: "入口 agent 应能直接回复并显式停止路由。"
            )
        ]

        if !nonEntryAgentNames.isEmpty {
            cases.append(
                WorkflowLaunchTestCase(
                    name: "Routing Contract Smoke",
                    prompt: "如果完成任务确实需要下游协作，请只选择最少必要的下游，并在最终回复后附加有效的路由 JSON。",
                    requiredAgentNames: entryAgentNames,
                    expectedOutputTypes: [ExecutionOutputType.agentFinalResponse.rawValue],
                    notes: "验证 OpenClaw 运行时仍能稳定产出可解析的路由指令。"
                )
            )
        }

        return cases
    }

    private func staticVerificationFindings(
        for workflow: Workflow,
        agents: [Agent]
    ) -> (status: WorkflowVerificationStatus, findings: [String]) {
        var failures: [String] = []
        var warnings: [String] = []

        if !openClawManager.isConnected {
            failures.append("OpenClaw 当前未连接，无法执行启动验证。")
        }

        let entryNodes = entryConnectedAgentNodes(in: workflow)
        if entryNodes.isEmpty {
            failures.append("工作流没有连接到 Start 的入口 agent。")
        }

        let agentByID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        let agentNodes = workflow.nodes.filter { $0.type == .agent }
        let missingAgentNodes = agentNodes.filter { node in
            guard let agentID = node.agentID else { return true }
            return agentByID[agentID] == nil
        }
        if !missingAgentNodes.isEmpty {
            failures.append("存在 \(missingAgentNodes.count) 个 agent 节点没有绑定有效的 agent。")
        }

        let invalidIdentifiers = agents.filter { agent in
            agent.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            agent.openClawDefinition.agentIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !invalidIdentifiers.isEmpty {
            failures.append("存在 \(invalidIdentifiers.count) 个 agent 缺少可用的 OpenClaw 标识。")
        }

        let reachableAgentIDs = Set(openClawService.executionPlan(for: workflow).map(\.id))
        let unreachableAgents = agentNodes.filter { !reachableAgentIDs.contains($0.id) }
        if !unreachableAgents.isEmpty {
            warnings.append("存在 \(unreachableAgents.count) 个 agent 节点当前从入口不可达，启动时不会被触发。")
        }

        if workflow.fallbackRoutingPolicy != .stop {
            warnings.append("当前工作流启用了 '\(workflow.fallbackRoutingPolicy.displayName)' 兜底策略，未输出路由指令时仍可能继续触发下游。")
        }

        let findings = failures + warnings
        if !failures.isEmpty {
            return (.fail, findings)
        }
        if !warnings.isEmpty {
            return (.warn, findings)
        }
        return (.pass, findings)
    }

    private func evaluateLaunchTestCase(
        _ testCase: WorkflowLaunchTestCase,
        workflow: Workflow,
        agents: [Agent],
        results: [ExecutionResult],
        logs: [ExecutionLogEntry]
    ) -> WorkflowLaunchTestCaseReport {
        let agentNameByID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0.name) })
        let actualAgents = results.map { agentNameByID[$0.agentID] ?? String($0.agentID.uuidString.prefix(8)) }
        let actualRoutingActions = results.compactMap(\.routingAction).map { $0.lowercased() }
        let actualRoutingTargets = Array(Set(results.flatMap(\.routingTargets))).sorted()
        let actualOutputTypes = results.map { $0.outputType.rawValue }

        var failures: [String] = []
        var warnings: [String] = []

        if results.isEmpty {
            failures.append("未返回任何执行结果。")
        }

        let failedResults = results.filter { $0.status == .failed }
        if !failedResults.isEmpty {
            failures.append("有 \(failedResults.count) 个节点执行失败。")
        }

        for required in testCase.requiredAgentNames where !actualAgents.contains(required) {
            failures.append("缺少必需 agent: \(required)")
        }

        for forbidden in testCase.forbiddenAgentNames where actualAgents.contains(forbidden) {
            failures.append("命中了禁止触发的 agent: \(forbidden)")
        }

        if let maxSteps = testCase.maxSteps, results.count > maxSteps {
            failures.append("实际步数 \(results.count) 超过上限 \(maxSteps)。")
        }

        for expectedAction in testCase.expectedRoutingActions.map({ $0.lowercased() }) where !actualRoutingActions.contains(expectedAction) {
            failures.append("未观测到期望的路由动作: \(expectedAction)")
        }

        for expectedOutputType in testCase.expectedOutputTypes where !actualOutputTypes.contains(expectedOutputType) {
            failures.append("未观测到期望的输出类型: \(expectedOutputType)")
        }

        if !testCase.expectedRoutingActions.isEmpty && actualRoutingActions.isEmpty {
            warnings.append("本用例未捕获到任何显式路由指令，说明 agent 可能依赖了兜底策略。")
        }

        let interestingLogs = logs.filter { $0.isRoutingEvent || $0.level == .error }
        for entry in interestingLogs where entry.level == .error {
            warnings.append(entry.message)
        }
        if interestingLogs.contains(where: { $0.routingBadge == "MISS" || $0.routingBadge == "WARN" }) {
            warnings.append("执行日志中出现了路由匹配异常或目标缺失。")
        }

        let notes = failures + warnings
        let status: WorkflowVerificationStatus
        if !failures.isEmpty {
            status = .fail
        } else if !warnings.isEmpty {
            status = .warn
        } else {
            status = .pass
        }

        return WorkflowLaunchTestCaseReport(
            testCaseID: testCase.id,
            name: testCase.name,
            prompt: testCase.prompt,
            status: status,
            actualStepCount: results.count,
            actualAgents: actualAgents,
            actualRoutingActions: actualRoutingActions,
            actualRoutingTargets: actualRoutingTargets,
            actualOutputTypes: actualOutputTypes,
            notes: notes
        )
    }

    private func workflowVerificationSignature(for workflow: Workflow, agents: [Agent]) -> String {
        let agentIDs = agents
            .map { "\($0.id.uuidString):\($0.name):\($0.openClawDefinition.agentIdentifier)" }
            .sorted()
            .joined(separator: "|")
        return [
            workflow.id.uuidString,
            workflow.name,
            workflow.fallbackRoutingPolicy.rawValue,
            "nodes:\(workflow.nodes.count)",
            "edges:\(workflow.edges.count)",
            agentIDs
        ].joined(separator: "::")
    }

    private func aggregateVerificationStatus(
        initial: WorkflowVerificationStatus,
        _ runtimeFindings: [String],
        caseReports: [WorkflowLaunchTestCaseReport]
    ) -> WorkflowVerificationStatus {
        if initial == .fail || caseReports.contains(where: { $0.status == .fail }) {
            return .fail
        }
        if initial == .warn || caseReports.contains(where: { $0.status == .warn }) || !runtimeFindings.isEmpty {
            return .warn
        }
        return .pass
    }

    private func persistLaunchVerificationReport(_ report: WorkflowLaunchVerificationReport, for workflowID: UUID) {
        guard var workflow = workflow(for: workflowID) else { return }
        workflow.lastLaunchVerificationReport = report
        updateWorkflow(workflow)
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

        guard openClawManager.isConnected else {
            openClawService.addLog(
                .error,
                "Workbench publish failed: OpenClaw is not connected."
            )
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

        let beginWorkbenchExecution: () -> Void = { [weak self] in
            guard let self else { return }
            let workbenchStart = Date()
            let workbenchSessionID = self.workbenchSessionID(
                projectRuntimeSessionID: project.runtimeState.sessionID,
                workflowID: workflow.id,
                agentID: leadAgent.id
            )
            let workbenchThinkingLevel = self.workbenchThinkingLevel(for: trimmedPrompt)

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
            task.metadata["workbenchSessionID"] = workbenchSessionID
            task.metadata["workbenchThinkingLevel"] = workbenchThinkingLevel.rawValue
            self.taskManager.addTask(task)

            var userMessage = Message(from: leadAgent.id, to: leadAgent.id, type: .task, content: trimmedPrompt)
            userMessage.status = .read
            userMessage.metadata["channel"] = "workbench"
            userMessage.metadata["role"] = "user"
            userMessage.metadata["kind"] = "input"
            userMessage.metadata["workflowID"] = workflow.id.uuidString
            userMessage.metadata["taskID"] = task.id.uuidString
            userMessage.metadata["workbenchSessionID"] = workbenchSessionID
            userMessage.metadata["workbenchThinkingLevel"] = workbenchThinkingLevel.rawValue
            userMessage.metadata["tokenEstimate"] = String(self.estimatedTokenCount(for: trimmedPrompt))
            self.messageManager.appendMessage(userMessage)

            self.taskManager.moveTask(task.id, to: .inProgress)
            self.openClawService.addLog(.info, "Workbench published task '\(task.title)' to workflow \(workflow.name)")

            if var mutableProject = self.currentProject {
                mutableProject.runtimeState.messageQueue.append(trimmedPrompt)
                mutableProject.runtimeState.agentStates[leadAgent.id.uuidString] = "queued"
                mutableProject.runtimeState.lastUpdated = Date()
                mutableProject.updatedAt = Date()
                self.currentProject = mutableProject
            }

            let otherEntryNodes = entryAgentNodes.filter { $0.id != leadNode.id }
            var streamingMessageID: UUID?
            var streamingContent = ""
            var firstChunkAt: Date?
            var firstReplyAt: Date?
            var fullWorkflowAt: Date?

            var placeholderMessage = Message(
                from: leadAgent.id,
                to: leadAgent.id,
                type: .notification,
                content: "已收到，正在生成回复..."
            )
            placeholderMessage.status = .read
            placeholderMessage.metadata["channel"] = "workbench"
            placeholderMessage.metadata["role"] = "assistant"
            placeholderMessage.metadata["kind"] = "output"
            placeholderMessage.metadata["workflowID"] = workflow.id.uuidString
            placeholderMessage.metadata["taskID"] = task.id.uuidString
            placeholderMessage.metadata["entryReply"] = "true"
            placeholderMessage.metadata["streamed"] = "true"
            placeholderMessage.metadata["thinking"] = "true"
            placeholderMessage.metadata["agentName"] = leadAgent.name
            placeholderMessage.metadata["outputType"] = ExecutionOutputType.runtimeLog.rawValue
            placeholderMessage.metadata["workbenchSessionID"] = workbenchSessionID
            placeholderMessage.metadata["workbenchThinkingLevel"] = workbenchThinkingLevel.rawValue
            placeholderMessage.metadata["tokenEstimate"] = String(self.estimatedTokenCount(for: placeholderMessage.content))
            self.messageManager.appendMessage(placeholderMessage)
            streamingMessageID = placeholderMessage.id

            func upsertWorkbenchAssistantMessage(
                agent: Agent,
                content: String,
                type: MessageType,
                outputType: ExecutionOutputType,
                isThinking: Bool
            ) {
                let cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking
                    ? "已收到任务，正在继续处理。"
                    : content

                if let messageID = streamingMessageID {
                    self.messageManager.updateMessage(messageID) { message in
                        message.content = cleanedContent
                        message.timestamp = Date()
                        message.type = type
                        message.metadata["thinking"] = isThinking ? "true" : "false"
                        message.metadata["streamed"] = "true"
                        message.metadata["agentName"] = agent.name
                        message.metadata["outputType"] = outputType.rawValue
                        message.metadata["workbenchSessionID"] = workbenchSessionID
                        message.metadata["workbenchThinkingLevel"] = workbenchThinkingLevel.rawValue
                        message.metadata["tokenEstimate"] = String(self.estimatedTokenCount(for: cleanedContent))
                    }
                } else {
                    var responseMessage = Message(
                        from: agent.id,
                        to: agent.id,
                        type: type,
                        content: cleanedContent
                    )
                    responseMessage.status = .read
                    responseMessage.metadata["channel"] = "workbench"
                    responseMessage.metadata["role"] = "assistant"
                    responseMessage.metadata["kind"] = "output"
                    responseMessage.metadata["workflowID"] = workflow.id.uuidString
                    responseMessage.metadata["taskID"] = task.id.uuidString
                    responseMessage.metadata["entryReply"] = "true"
                    responseMessage.metadata["streamed"] = "true"
                    responseMessage.metadata["thinking"] = isThinking ? "true" : "false"
                    responseMessage.metadata["agentName"] = agent.name
                    responseMessage.metadata["outputType"] = outputType.rawValue
                    responseMessage.metadata["workbenchSessionID"] = workbenchSessionID
                    responseMessage.metadata["workbenchThinkingLevel"] = workbenchThinkingLevel.rawValue
                    responseMessage.metadata["tokenEstimate"] = String(self.estimatedTokenCount(for: cleanedContent))
                    self.messageManager.appendMessage(responseMessage)
                    streamingMessageID = responseMessage.id
                }
            }

            func recordWorkbenchLatency(_ key: String, label: String, at timestamp: Date) {
                let latency = self.latencyMillisecondsString(since: workbenchStart, until: timestamp)
                self.persistWorkbenchLatencyMetric(
                    taskID: task.id,
                    messageID: streamingMessageID,
                    key: key,
                    value: latency
                )
                self.openClawService.addLog(.info, "Workbench latency: \(label)=\(latency)ms")
            }

            func completeWorkbenchExecution(results: [ExecutionResult]) {
                if fullWorkflowAt == nil {
                    let finishedAt = Date()
                    fullWorkflowAt = finishedAt
                    recordWorkbenchLatency("fullWorkflowMs", label: "full_workflow", at: finishedAt)
                }

                let failedCount = results.filter { $0.status == .failed }.count
                let finalStatus: TaskStatus = results.isEmpty ? .blocked : (failedCount == 0 ? .done : .blocked)
                self.taskManager.moveTask(task.id, to: finalStatus)

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

                self.openClawService.isExecuting = false
                self.openClawService.currentNodeID = nil
            }

            func orderedUniqueNodes(_ nodes: [WorkflowNode]) -> [WorkflowNode] {
                var seen = Set<UUID>()
                return nodes.filter { seen.insert($0.id).inserted }
            }

            self.openClawService.isExecuting = true
            self.openClawService.currentNodeID = leadNode.id
            self.openClawService.currentStep = 0
            self.openClawService.totalSteps = max(entryAgentNodes.count, 1)
            self.openClawService.lastError = nil
            self.openClawService.addLog(.info, "Workbench is generating the first reply from entry agent \(leadAgent.name).")
            self.openClawService.addLog(.info, "Workbench entry thinking level selected: \(workbenchThinkingLevel.rawValue).")

            self.openClawService.executeWorkbenchEntryNode(
                node: leadNode,
                workflow: workflow,
                agents: project.agents,
                prompt: trimmedPrompt,
                sessionID: workbenchSessionID,
                thinkingLevel: workbenchThinkingLevel,
                onStream: { [weak self] chunk in
                    guard self != nil else { return }
                    guard !chunk.isEmpty,
                          !chunk.allSatisfy({ $0.isWhitespace || $0.isNewline }) else { return }

                    streamingContent += chunk
                    upsertWorkbenchAssistantMessage(
                        agent: leadAgent,
                        content: streamingContent,
                        type: .notification,
                        outputType: .agentFinalResponse,
                        isThinking: true
                    )

                    if firstChunkAt == nil {
                        let timestamp = Date()
                        firstChunkAt = timestamp
                        recordWorkbenchLatency("firstChunkMs", label: "first_chunk", at: timestamp)
                    }
                }
            ) { [weak self] entryExecution in
                guard let self else { return }

                let entryResult = entryExecution.result
                let visibleOutput = entryResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !visibleOutput.isEmpty {
                    upsertWorkbenchAssistantMessage(
                        agent: leadAgent,
                        content: visibleOutput.isEmpty ? streamingContent : visibleOutput,
                        type: entryResult.status == .completed ? .notification : .data,
                        outputType: entryResult.outputType,
                        isThinking: false
                    )
                } else if let messageID = streamingMessageID {
                    self.messageManager.updateMessage(messageID) { message in
                        message.metadata["thinking"] = "false"
                    }
                }

                if firstReplyAt == nil {
                    let timestamp = Date()
                    firstReplyAt = timestamp
                    recordWorkbenchLatency("firstReplyMs", label: "first_reply", at: timestamp)
                }

                guard entryResult.status == .completed else {
                    self.openClawService.executionResults = [entryResult]
                    completeWorkbenchExecution(results: [entryResult])
                    return
                }

                let backgroundNodes = orderedUniqueNodes(otherEntryNodes + entryExecution.downstreamNodes)
                if backgroundNodes.isEmpty {
                    self.openClawService.executionResults = [entryResult]
                    self.openClawService.addLog(.info, "Workbench reply completed with no additional workflow nodes queued.")
                    completeWorkbenchExecution(results: [entryResult])
                    return
                }

                let backgroundEntryNodeIDs = Set(otherEntryNodes.map(\.id))
                self.openClawService.addLog(
                    .info,
                    "Workbench reply completed. Continuing workflow in background with \(backgroundNodes.count) queued node(s)."
                )

                self.openClawService.executeWorkflow(
                    workflow,
                    agents: project.agents,
                    prompt: trimmedPrompt,
                    startingNodes: backgroundNodes,
                    entryNodeIDsOverride: backgroundEntryNodeIDs,
                    preloadedResults: [entryResult],
                    precompletedNodeIDs: [leadNode.id],
                    agentOutputMode: .plainStreaming
                ) { [weak self] results in
                    guard self != nil else { return }
                    completeWorkbenchExecution(results: results)
                }
            }
        }

        beginWorkbenchExecution()

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
    func addNewAgent(named name: String = "New Agent", templateID: String? = nil) -> Agent? {
        guard var project = currentProject else { return nil }
        let resolvedName = uniqueAgentName(baseName: name, suffix: "")
        var newAgent = Agent(name: resolvedName)
        if let templateID, let template = AgentTemplateCatalog.template(withID: templateID) {
            newAgent.apply(template: template)
        } else {
            newAgent.description = "Description"
        }
        newAgent.openClawDefinition.agentIdentifier = resolvedName
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
        persistCurrentProjectSilently()
        return duplicated
    }

    func duplicateAgentsForWorkflowPaste(
        _ sourceAgentIDs: [UUID],
        suffix: String = "Copy",
        offset: CGPoint = .zero
    ) -> [UUID: UUID] {
        var mapping: [UUID: UUID] = [:]
        var seen = Set<UUID>()

        for sourceAgentID in sourceAgentIDs {
            guard seen.insert(sourceAgentID).inserted else { continue }
            guard let duplicated = duplicateAgent(sourceAgentID, suffix: suffix, offset: offset) else { continue }
            mapping[sourceAgentID] = duplicated.id
        }

        return mapping
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
        }

        project.updatedAt = Date()
        currentProject = project
        objectWillChange.send()
        persistCurrentProjectSilently()
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
        
        scheduleTaskGeneration()
    }
    
    // 显示帮助
    func showHelp() {
        if let url = URL(string: "https://github.com/chenrongze/Multi-Agent-Flow#readme") {
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

    private func workbenchThinkingLevel(for prompt: String) -> AgentThinkingLevel {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .off }

        let tokenEstimate = estimatedTokenCount(for: trimmed)
        let scalarCount = trimmed.unicodeScalars.count
        let lineCount = trimmed.components(separatedBy: .newlines).count
        let containsStructuredInput = trimmed.contains("\n")
            || trimmed.contains("1.")
            || trimmed.contains("2.")
            || trimmed.contains("3.")
            || trimmed.contains("- ")
            || trimmed.contains("•")

        let complexityHints = [
            "分析", "原因", "方案", "设计", "架构", "排查", "调试", "优化",
            "比较", "对比", "步骤", "计划", "详细", "复杂", "实现",
            "analyze", "analysis", "debug", "diagnose", "design", "plan",
            "compare", "complex", "refactor", "architecture", "step by step"
        ]
        let normalized = trimmed.lowercased()
        let hasComplexityHint = complexityHints.contains { normalized.contains($0) }

        if tokenEstimate > 48 || scalarCount > 120 || lineCount > 1 || containsStructuredInput || hasComplexityHint {
            return .minimal
        }
        return .off
    }

    private func workbenchSessionID(projectRuntimeSessionID: String, workflowID: UUID, agentID: UUID) -> String {
        let base = projectRuntimeSessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBase = base.isEmpty ? UUID().uuidString : base
        return "workbench-\(resolvedBase)-\(workflowID.uuidString)-\(agentID.uuidString)"
    }

    private func latencyMillisecondsString(since start: Date, until end: Date = Date()) -> String {
        let milliseconds = max(0, Int((end.timeIntervalSince(start) * 1000).rounded()))
        return String(milliseconds)
    }

    private func persistWorkbenchLatencyMetric(taskID: UUID, messageID: UUID?, key: String, value: String) {
        if var updatedTask = taskManager.task(with: taskID) {
            updatedTask.metadata[key] = value
            taskManager.updateTask(updatedTask)
        }

        guard let messageID else { return }
        messageManager.updateMessage(messageID) { message in
            message.metadata[key] = value
        }
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
        var proposedPositionsByAgentID: [UUID: CGPoint] = [:]

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

                proposedPositionsByAgentID[descriptor.agent.id] = proposedPosition
            }
        }

        guard !proposedPositionsByAgentID.isEmpty else {
            return []
        }

        let allProposed = Array(proposedPositionsByAgentID.values)
        let minX = allProposed.map(\.x).min() ?? 0
        let maxX = allProposed.map(\.x).max() ?? 0
        let minY = allProposed.map(\.y).min() ?? 0
        let maxY = allProposed.map(\.y).max() ?? 0
        let center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)

        for descriptor in descriptors {
            guard let proposedPosition = proposedPositionsByAgentID[descriptor.agent.id] else { continue }
            let centeredPosition = snapPointToGrid(
                CGPoint(x: proposedPosition.x - center.x, y: proposedPosition.y - center.y)
            )

            var node = existingNodesByAgentID[descriptor.agent.id] ?? WorkflowNode(type: .agent)
            node.agentID = descriptor.agent.id
            node.title = descriptor.agent.name
            node.position = centeredPosition

            generated.append(
                ArchitectureGeneratedNode(
                    node: node,
                    descriptor: descriptor,
                    proposedPosition: centeredPosition
                )
            )
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
            let snappedRect = snapRectToGrid(
                CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            )

            var boundary = WorkflowBoundary(
                title: "\(architectureBoundaryPrefix) \(clusterKey)",
                rect: snappedRect,
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
