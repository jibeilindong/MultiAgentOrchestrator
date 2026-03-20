//
//  ImportExportService.swift
//  MultiAgentOrchestrator
//
//  多智能体架构导入导出服务
//

import Foundation

// 导入导出数据结构
struct MultiAgentArchitecture: Codable {
    var version: String = "1.0"
    var exportedAt: Date
    var projectName: String
    var agents: [AgentExport]
    var workflows: [WorkflowExport]
    var permissions: [PermissionExport]
    var tasks: [TaskExport]?
    
    struct AgentExport: Codable {
        var id: UUID
        var name: String
        var description: String
        var soulMD: String
        var position: CGPoint
        var capabilities: [String]
        var openClawAgentID: String?
    }
    
    struct WorkflowExport: Codable {
        var id: UUID
        var name: String
        var nodes: [NodeExport]
        var edges: [EdgeExport]
    }
    
    struct NodeExport: Codable {
        var id: UUID
        var agentID: UUID?
        var type: String
        var position: CGPoint
        var title: String?
        var conditionExpression: String?
        var loopEnabled: Bool?
        var maxIterations: Int?
    }
    
    struct EdgeExport: Codable {
        var id: UUID
        var fromNodeID: UUID
        var toNodeID: UUID
        var label: String?
        var conditionExpression: String?
        var requiresApproval: Bool?
        var isBidirectional: Bool?
    }
    
    struct PermissionExport: Codable {
        var fromAgentID: UUID
        var toAgentID: UUID
        var permissionType: String
    }
    
    struct TaskExport: Codable {
        var id: UUID
        var title: String
        var description: String
        var status: String
        var priority: String
        var assignedAgentID: UUID?
        var workflowNodeID: UUID?
        var createdBy: UUID?
        var tags: [String]
    }
}

class ImportExportService {
    static let shared = ImportExportService()
    
    private let fileManager = FileManager.default
    
    // 导出项目
    func exportProject(_ project: MAProject, tasks: [Task] = [], openClawMapping: [UUID: String] = [:]) -> Data? {
        let architecture = buildArchitecture(project: project, tasks: tasks, openClawMapping: openClawMapping)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            return try encoder.encode(architecture)
        } catch {
            print("Export error: \(error)")
            return nil
        }
    }
    
    // 构建导出数据结构
    private func buildArchitecture(project: MAProject, tasks: [Task], openClawMapping: [UUID: String]) -> MultiAgentArchitecture {
        let agentExports = project.agents.map { agent in
            MultiAgentArchitecture.AgentExport(
                id: agent.id,
                name: agent.name,
                description: agent.description,
                soulMD: agent.soulMD,
                position: agent.position,
                capabilities: agent.capabilities,
                openClawAgentID: openClawMapping[agent.id] ?? agent.openClawDefinition.agentIdentifier
            )
        }
        
        let workflowExports = project.workflows.map { workflow in
            let nodeExports = workflow.nodes.map { node in
                MultiAgentArchitecture.NodeExport(
                    id: node.id,
                    agentID: node.agentID,
                    type: node.type.rawValue,
                    position: node.position,
                    title: node.title,
                    conditionExpression: node.conditionExpression,
                    loopEnabled: node.loopEnabled,
                    maxIterations: node.maxIterations
                )
            }
            
            let edgeExports = workflow.edges.map { edge in
                MultiAgentArchitecture.EdgeExport(
                    id: edge.id,
                    fromNodeID: edge.fromNodeID,
                    toNodeID: edge.toNodeID,
                    label: edge.label,
                    conditionExpression: edge.conditionExpression,
                    requiresApproval: edge.requiresApproval,
                    isBidirectional: edge.isBidirectional
                )
            }
            
            return MultiAgentArchitecture.WorkflowExport(
                id: workflow.id,
                name: workflow.name,
                nodes: nodeExports,
                edges: edgeExports
            )
        }
        
        let permissionExports = project.permissions.map { perm in
            MultiAgentArchitecture.PermissionExport(
                fromAgentID: perm.fromAgentID,
                toAgentID: perm.toAgentID,
                permissionType: perm.permissionType.rawValue
            )
        }
        
        let taskExports = tasks.map { task in
            MultiAgentArchitecture.TaskExport(
                id: task.id,
                title: task.title,
                description: task.description,
                status: task.status.rawValue,
                priority: task.priority.rawValue,
                assignedAgentID: task.assignedAgentID,
                workflowNodeID: task.workflowNodeID,
                createdBy: task.createdBy,
                tags: task.tags
            )
        }
        
        return MultiAgentArchitecture(
            exportedAt: Date(),
            projectName: project.name,
            agents: agentExports,
            workflows: workflowExports,
            permissions: permissionExports,
            tasks: taskExports.isEmpty ? nil : taskExports
        )
    }
    
    // 导入项目
    func importProject(from data: Data) -> (MAProject, [Task], [UUID: String])? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            let architecture = try decoder.decode(MultiAgentArchitecture.self, from: data)
            return parseArchitecture(architecture)
        } catch {
            print("Import error: \(error)")
            return nil
        }
    }
    
    // 解析导入数据
    private func parseArchitecture(_ arch: MultiAgentArchitecture) -> (MAProject, [Task], [UUID: String]) {
        // 构建Agent映射
        var idMapping: [UUID: UUID] = [:]
        
        // 转换Agent
        var agents: [Agent] = []
        for agentExport in arch.agents {
            let newID = UUID()
            idMapping[agentExport.id] = newID
            var agent = Agent(name: agentExport.name)
            agent.description = agentExport.description
            agent.soulMD = agentExport.soulMD
            agent.position = agentExport.position
            agent.capabilities = agentExport.capabilities
            if let openClawAgentID = agentExport.openClawAgentID {
                agent.openClawDefinition.agentIdentifier = openClawAgentID
            }
            agents.append(agent)
        }
        
        // 收集OpenClaw映射
        var openClawMapping: [UUID: String] = [:]
        for agentExport in arch.agents {
            if let oldID = idMapping[agentExport.id], let openClawID = agentExport.openClawAgentID {
                openClawMapping[oldID] = openClawID
            }
        }
        
        // 转换Workflow
        var nodeIDMapping: [UUID: UUID] = [:]
        var workflows: [Workflow] = []
        
        for workflowExport in arch.workflows {
            var workflow = Workflow(name: workflowExport.name)
            
            // 转换节点
            for nodeExport in workflowExport.nodes {
                let newNodeID = UUID()
                nodeIDMapping[nodeExport.id] = newNodeID
                var node = WorkflowNode(type: WorkflowNode.NodeType(rawValue: nodeExport.type) ?? WorkflowNode.NodeType.decoded(from: nodeExport.type))
                node.agentID = nodeExport.agentID.flatMap { idMapping[$0] }
                node.position = nodeExport.position
                node.title = nodeExport.title ?? ""
                node.conditionExpression = nodeExport.conditionExpression ?? ""
                node.loopEnabled = nodeExport.loopEnabled ?? false
                node.maxIterations = nodeExport.maxIterations ?? 1
                workflow.nodes.append(node)
            }
            
            // 转换边
            for edgeExport in workflowExport.edges {
                var edge = WorkflowEdge(from: nodeIDMapping[edgeExport.fromNodeID] ?? edgeExport.fromNodeID,
                                        to: nodeIDMapping[edgeExport.toNodeID] ?? edgeExport.toNodeID)
                edge.label = edgeExport.label ?? ""
                edge.conditionExpression = edgeExport.conditionExpression ?? ""
                edge.requiresApproval = edgeExport.requiresApproval ?? false
                edge.isBidirectional = edgeExport.isBidirectional ?? false
                workflow.edges.append(edge)
            }
            
            workflows.append(workflow)
        }
        
        // 转换权限
        var permissions: [Permission] = []
        for permExport in arch.permissions {
            if let fromID = idMapping[permExport.fromAgentID],
               let toID = idMapping[permExport.toAgentID],
               let permType = PermissionType(rawValue: permExport.permissionType) {
                let permission = Permission(fromAgentID: fromID, toAgentID: toID, permissionType: permType)
                permissions.append(permission)
            }
        }
        
        // 转换任务
        var tasks: [Task] = []
        for taskExport in (arch.tasks ?? []) {
            let task = Task(
                title: taskExport.title,
                description: taskExport.description,
                status: TaskStatus(rawValue: taskExport.status) ?? .todo,
                priority: TaskPriority(rawValue: taskExport.priority) ?? .medium,
                assignedAgentID: taskExport.assignedAgentID.flatMap { idMapping[$0] },
                workflowNodeID: taskExport.workflowNodeID.flatMap { idMapping[$0] },
                createdBy: taskExport.createdBy.flatMap { idMapping[$0] },
                tags: taskExport.tags
            )
            tasks.append(task)
        }
        
        // 创建项目
        var project = MAProject(name: arch.projectName)
        project.agents = agents
        project.workflows = workflows
        project.permissions = permissions
        
        return (project, tasks, openClawMapping)
    }
    
    // 保存到文件
    func saveToFile(_ data: Data, filename: String) -> URL? {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("Save error: \(error)")
            return nil
        }
    }
    
    // 从文件读取
    func loadFromFile(_ url: URL) -> Data? {
        try? Data(contentsOf: url)
    }
    
    // 从OpenClaw agents目录读取Soul配置
    func loadOpenClawAgentConfigs() -> [String: OpenClawAgentInfo] {
        var configs: [String: OpenClawAgentInfo] = [:]
        
        let agentsPath = NSHomeDirectory() + "/.openclaw/agents"
        guard let contents = try? fileManager.contentsOfDirectory(atPath: agentsPath) else {
            return configs
        }
        
        for agentDir in contents {
            let dirURL = URL(fileURLWithPath: agentsPath, isDirectory: true)
                .appendingPathComponent(agentDir, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: dirURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }

            let workspacePath = OpenClawManager.shared.localAgentWorkspacePath(matching: [agentDir]) ?? dirURL.path
            let sourceRootURL = URL(fileURLWithPath: workspacePath, isDirectory: true)
            var soulMD = ""
            var skills: [String] = []

            let soulSourcePath = preferredSoulSourcePath(in: sourceRootURL)
            if let content = try? String(contentsOf: soulSourcePath, encoding: .utf8) {
                soulMD = content
            }

            let skillsPath = preferredSkillsDirectory(in: sourceRootURL)
            if let skillContents = try? fileManager.contentsOfDirectory(atPath: skillsPath.path) {
                skills = skillContents.filter { $0.hasSuffix(".md") || $0.hasSuffix(".MD") }
            }
            
            configs[agentDir] = OpenClawAgentInfo(
                agentID: agentDir,
                soulMD: soulMD,
                workspacePath: workspacePath,
                soulSourcePath: soulSourcePath.path,
                skills: skills
            )
        }
        
        return configs
    }

    private func preferredSoulSourcePath(in agentRoot: URL) -> URL {
        let preferred = agentRoot.appendingPathComponent("SOUL.md")
        if fileManager.fileExists(atPath: preferred.path) {
            return preferred
        }

        let fallback = agentRoot.appendingPathComponent("soul.md")
        if fileManager.fileExists(atPath: fallback.path) {
            return fallback
        }

        let nestedRoot = agentRoot.appendingPathComponent("agent", isDirectory: true)
        let nestedPreferred = nestedRoot.appendingPathComponent("SOUL.md")
        if fileManager.fileExists(atPath: nestedPreferred.path) {
            return nestedPreferred
        }

        let nestedFallback = nestedRoot.appendingPathComponent("soul.md")
        if fileManager.fileExists(atPath: nestedFallback.path) {
            return nestedFallback
        }

        return preferred
    }

    private func preferredSkillsDirectory(in agentRoot: URL) -> URL {
        let preferred = agentRoot.appendingPathComponent("skills", isDirectory: true)
        if fileManager.fileExists(atPath: preferred.path) {
            return preferred
        }

        let nested = agentRoot.appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
        if fileManager.fileExists(atPath: nested.path) {
            return nested
        }

        return preferred
    }
}

struct OpenClawAgentInfo {
    var agentID: String
    var soulMD: String
    var workspacePath: String
    var soulSourcePath: String
    var skills: [String]
}
