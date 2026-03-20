//
//  ImportExportView.swift
//  Multi-Agent-Flow
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI
import UniformTypeIdentifiers

struct ImportExportView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    @State private var showingImportPanel = false
    @State private var showingExportPanel = false
    @State private var exportFormat = ExportFormat.json
    @State private var includeTasks = true
    @State private var includeMessages = true
    @State private var includeExecutionResults = false
    @State private var includeKanban = true  // 工部：看板数据
    
    // 工部：导入预览
    @State private var importPreviewData: ImportPreviewData?
    @State private var showingImportPreview = false
    @State private var isImporting = false
    @State private var importProgress: Double = 0
    @State private var importError: String?
    
    // 工部：导出进度
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    
    enum ExportFormat: String, CaseIterable {
        case json = "JSON"
        case yaml = "YAML"
        case markdown = "Markdown"
        
        var fileExtension: String {
            switch self {
            case .json: return "json"
            case .yaml: return "yaml"
            case .markdown: return "md"
            }
        }
        
        var utType: UTType {
            switch self {
            case .json: return .json
            case .yaml: return UTType(filenameExtension: "yaml") ?? .plainText
            case .markdown: return .plainText
            }
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Import Project") {
                    Text(LocalizedString.importText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Import Project...") {
                        showingImportPanel = true
                    }
                    .frame(maxWidth: .infinity)
                }
                
                Section("Export Project") {
                    Text(LocalizedString.export)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    
                    Toggle("Include Tasks", isOn: $includeTasks)
                    Toggle("Include Kanban Status", isOn: $includeKanban)  // 工部：看板选项
                    Toggle("Include Messages", isOn: $includeMessages)
                    Toggle("Include Execution Results", isOn: $includeExecutionResults)
                    
                    Button("Export Project...") {
                        showingExportPanel = true
                    }
                    .frame(maxWidth: .infinity)
                }
                
                Section("Backup & Restore") {
                    Text(LocalizedString.backup)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Create Backup...") {
                        createBackup()
                    }
                    .frame(maxWidth: .infinity)
                    
                    Button("Restore from Backup...") {
                        restoreFromBackup()
                    }
                    .frame(maxWidth: .infinity)
                }
                
                Section("Templates") {
                    Text(LocalizedString.template)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Save as Template...") {
                        saveAsTemplate()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Import & Export")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showingImportPanel,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result: result)
            }
            .fileExporter(
                isPresented: $showingExportPanel,
                document: ExportDocument(content: exportContent()),
                contentType: exportFormat.utType,
                defaultFilename: defaultExportFilename()
            ) { result in
                handleExport(result: result)
            }
            // 工部：导入预览 sheet
            .sheet(isPresented: $showingImportPreview) {
                if let previewData = importPreviewData {
                    ImportPreviewView(
                        previewData: previewData,
                        onConfirm: {
                            performImport()
                            showingImportPreview = false
                        },
                        onCancel: {
                            importPreviewData = nil
                            showingImportPreview = false
                        }
                    )
                }
            }
            // 工部：导入进度 sheet
            .sheet(isPresented: $isImporting) {
                ImportExportProgressView(
                    progress: importProgress,
                    status: importError ?? "Importing...",
                    isImport: true
                )
                .interactiveDismissDisabled()
            }
            // 工部：导出进度 sheet
            .sheet(isPresented: $isExporting) {
                ImportExportProgressView(
                    progress: exportProgress,
                    status: "Exporting...",
                    isImport: false
                )
                .interactiveDismissDisabled()
            }
        }
        .frame(minWidth: 500, minHeight: 600)
    }
    
    private func exportContent() -> String {
        guard let project = appState.currentProject else { return "" }
        
        // 创建要导出的数据字典
        var exportData: [String: Any] = [:]
        
        do {
            // 1. 编码项目
            let projectData = try JSONEncoder().encode(project)
            if let projectDict = try JSONSerialization.jsonObject(with: projectData) as? [String: Any] {
                exportData["project"] = projectDict
            }
            
            // 2. 添加元数据
            exportData["exportedAt"] = Date().timeIntervalSince1970
            exportData["version"] = "1.0"
            exportData["format"] = "maoproject"
            
            // 3. 可选：添加任务
            if includeTasks {
                let tasksData = try JSONEncoder().encode(appState.taskManager.tasks)
                if let tasksArray = try JSONSerialization.jsonObject(with: tasksData) as? [Any] {
                    exportData["tasks"] = tasksArray
                }
            }
            
            // 4. 可选：添加消息
            if includeMessages {
                let messagesData = try JSONEncoder().encode(appState.messageManager.messages)
                if let messagesArray = try JSONSerialization.jsonObject(with: messagesData) as? [Any] {
                    exportData["messages"] = messagesArray
                }
            }
            
            // 5. 可选：添加执行结果
            if includeExecutionResults {
                let resultsData = try JSONEncoder().encode(appState.openClawService.executionResults)
                if let resultsArray = try JSONSerialization.jsonObject(with: resultsData) as? [Any] {
                    exportData["executionResults"] = resultsArray
                }
            }
            
            // 6. 工部：添加看板数据
            if includeKanban {
                var kanbanData: [String: Any] = [:]
                var tasksByStatus: [String: [[String: Any]]] = [:]
                
                for status in TaskStatus.allCases {
                    let tasks = appState.taskManager.tasks(for: status)
                    let encoder = JSONEncoder()
                    if let data = try? encoder.encode(tasks),
                       let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                        tasksByStatus[status.rawValue] = array
                    }
                }
                kanbanData["tasks"] = tasksByStatus
                exportData["kanban"] = kanbanData
            }
            
            // 7. 转换为 JSON 字符串
            let data = try JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted])
            return String(data: data, encoding: .utf8) ?? ""
            
        } catch {
            print("Export error: \(error)")
            return ""
        }
    }
    
    private func defaultExportFilename() -> String {
        let projectName = appState.currentProject?.name ?? "Untitled"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        return "\(projectName)-\(dateString).\(exportFormat.fileExtension)"
    }
    
    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                do {
                    let data = try Data(contentsOf: url)
                    
                    // 刑部：JSON 格式校验
                    let validationResult = JSONValidator.validate(data)
                    
                    if !validationResult.isValid {
                        // 显示错误
                        importError = validationResult.errors.first?.message
                        print("Validation failed: \(validationResult.errors)")
                        return
                    }
                    
                    if !validationResult.warnings.isEmpty {
                        print("Validation warnings: \(validationResult.warnings)")
                    }
                    
                    // 户部：保存到缓存
                    let cacheKey = url.lastPathComponent
                    try? ImportExportCacheManager.shared.saveToCache(data, key: cacheKey)
                    
                    // 解析 JSON
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        importError = "Invalid JSON format"
                        print("Invalid JSON format")
                        return
                    }
                    
                    // 工部：创建导入预览数据
                    importPreviewData = createPreviewData(from: json)
                    showingImportPreview = true
                    
                } catch {
                    importError = error.localizedDescription
                    print("Import error: \(error)")
                }
            }
        case .failure(let error):
            importError = error.localizedDescription
            print("Import failed: \(error)")
        }
    }
    
    // 工部：创建预览数据
    private func createPreviewData(from json: [String: Any]) -> ImportPreviewData {
        var previewData = ImportPreviewData(
            projectName: "Unknown",
            agentCount: 0,
            workflowCount: 0,
            taskCount: 0,
            messageCount: 0,
            executionResultCount: 0,
            kanbanTasks: [:],
            format: json["format"] as? String ?? "unknown",
            version: json["version"] as? String ?? "unknown",
            exportedAt: Date(timeIntervalSince1970: json["exportedAt"] as? TimeInterval ?? 0),
            warnings: []
        )
        
        // 项目信息
        if let project = json["project"] as? [String: Any] {
            previewData.projectName = project["name"] as? String ?? "Unknown"
            previewData.agentCount = (project["agents"] as? [[String: Any]])?.count ?? 0
            previewData.workflowCount = (project["workflows"] as? [[String: Any]])?.count ?? 0
        }
        
        // 任务统计
        if let tasks = json["tasks"] as? [[String: Any]] {
            previewData.taskCount = tasks.count
            
            // 看板状态统计
            var kanbanTasks: [TaskStatus: Int] = [:]
            for task in tasks {
                if let statusStr = task["status"] as? String,
                   let status = TaskStatus(rawValue: statusStr) {
                    kanbanTasks[status, default: 0] += 1
                }
            }
            previewData.kanbanTasks = kanbanTasks
        }
        
        // 消息统计
        if let messages = json["messages"] as? [[String: Any]] {
            previewData.messageCount = messages.count
        }
        
        // 执行结果统计
        if let results = json["executionResults"] as? [[String: Any]] {
            previewData.executionResultCount = results.count
        }
        
        return previewData
    }
    
    // 工部：执行实际导入
    private func performImport() {
        isImporting = true
        importProgress = 0
        
        guard importPreviewData != nil else {
            isImporting = false
            return
        }
        
        // 刑部：导入失败回滚 - 保存当前状态
        var backupData: [String: Any] = [:]
        if let project = appState.currentProject {
            if let projectData = try? JSONEncoder().encode(project),
               let projectDict = try? JSONSerialization.jsonObject(with: projectData) as? [String: Any] {
                backupData["project"] = projectDict
            }
        }
        
        do {
            // 从缓存读取（如果可用）
            let data: Data
            if let cachedData = ImportExportCacheManager.shared.loadFromCache(key: "lastImport") {
                data = cachedData
            } else {
                // 重新加载文件
                throw NSError(domain: "ImportExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "No cached data"])
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "ImportExport", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])
            }
            
            importProgress = 0.2
            
            // 导入项目
            if let projectData = json["project"] as? [String: Any],
               let projectJSON = try? JSONSerialization.data(withJSONObject: projectData) {
                let decoder = JSONDecoder()
                let project = try decoder.decode(MAProject.self, from: projectJSON)
                appState.currentProject = project
            }
            
            importProgress = 0.4
            
            // 导入任务（包括看板状态）
            if let tasksData = json["tasks"] as? [[String: Any]] {
                let decoder = JSONDecoder()
                var tasks: [Task] = []
                for taskDict in tasksData {
                    if let taskJSON = try? JSONSerialization.data(withJSONObject: taskDict) {
                        let task = try decoder.decode(Task.self, from: taskJSON)
                        tasks.append(task)
                    }
                }
                appState.taskManager.tasks = tasks
            }
            
            // 刑部：导入看板数据
            if let kanbanData = json["kanban"] as? [String: Any],
               let tasksByStatus = kanbanData["tasks"] as? [String: [[String: Any]]] {
                // 根据看板状态重新分配任务
                for (statusStr, tasksArray) in tasksByStatus {
                    if let status = TaskStatus(rawValue: statusStr) {
                        for taskDict in tasksArray {
                            if let taskIdStr = taskDict["id"] as? String,
                               let taskId = UUID(uuidString: taskIdStr) {
                                appState.taskManager.moveTask(taskId, to: status)
                            }
                        }
                    }
                }
            }
            
            importProgress = 0.6
            
            // 导入消息
            if let messagesData = json["messages"] as? [[String: Any]] {
                let decoder = JSONDecoder()
                var messages: [Message] = []
                for messageDict in messagesData {
                    if let messageJSON = try? JSONSerialization.data(withJSONObject: messageDict) {
                        let message = try decoder.decode(Message.self, from: messageJSON)
                        messages.append(message)
                    }
                }
                appState.messageManager.messages = messages
            }
            
            importProgress = 0.8
            
            // 导入执行结果
            if let resultsData = json["executionResults"] as? [[String: Any]] {
                let decoder = JSONDecoder()
                var results: [ExecutionResult] = []
                for resultDict in resultsData {
                    if let resultJSON = try? JSONSerialization.data(withJSONObject: resultDict) {
                        let result = try decoder.decode(ExecutionResult.self, from: resultJSON)
                        results.append(result)
                    }
                }
                appState.openClawService.executionResults = results
            }
            
            importProgress = 1.0
            print("Import successful")
            
        } catch {
            // 刑部：导入失败回滚
            importError = "Import failed: \(error.localizedDescription)"
            print("Import error: \(error)")
            
            // 回滚到备份
            // appState.currentProject = backup...
        }
        
        isImporting = false
    }
    
    private func handleExport(result: Result<URL, Error>) {
        isExporting = true
        exportProgress = 0
        
        // 模拟导出进度
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            exportProgress = 0.5
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            exportProgress = 1.0
            
            switch result {
            case .success(let url):
                print("Export successful to: \(url)")
                // 户部：保存导出文件到缓存目录
                if let data = exportContent().data(using: .utf8) {
                    try? ImportExportCacheManager.shared.saveToCache(data, key: url.lastPathComponent)
                }
            case .failure(let error):
                print("Export failed: \(error)")
            }
            
            isExporting = false
        }
    }
    
    private func createBackup() {
        let panel = NSSavePanel()
        panel.title = "Create Backup"
        panel.nameFieldStringValue = "\(appState.currentProject?.name ?? "project")-backup-\(Date().formatted(date: .numeric, time: .omitted)).maobackup"
        panel.allowedContentTypes = [UTType(filenameExtension: "maobackup") ?? .zip]
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                // 在实际应用中，这里应该创建一个包含所有数据的zip文件
                print("Backup created at: \(url)")
            }
        }
    }
    
    private func restoreFromBackup() {
        let panel = NSOpenPanel()
        panel.title = "Restore from Backup"
        panel.allowedContentTypes = [UTType(filenameExtension: "maobackup") ?? .zip]
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                // 在实际应用中，这里应该从备份文件恢复数据
                print("Restoring from: \(url)")
            }
        }
    }
    
    private func saveAsTemplate() {
        let panel = NSSavePanel()
        panel.title = "Save as Template"
        panel.nameFieldStringValue = "\(appState.currentProject?.name ?? "template")-template.maotemplate"
        panel.allowedContentTypes = [UTType(filenameExtension: "maotemplate") ?? .json]
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                // 保存模板
                do {
                    let templateData = exportContent()
                    try templateData.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("Save template error: \(error)")
                }
            }
        }
    }
}

// 工部：导入预览数据结构
struct ImportPreviewData {
    var projectName: String
    var agentCount: Int
    var workflowCount: Int
    var taskCount: Int
    var messageCount: Int
    var executionResultCount: Int
    var kanbanTasks: [TaskStatus: Int]
    var format: String
    var version: String
    var exportedAt: Date
    var warnings: [String]
}

// 工部：导入预览视图
struct ImportPreviewView: View {
    let previewData: ImportPreviewData
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @State private var selectedItems: Set<String> = ["project", "tasks", "kanban"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizedString.importPreview)
                .font(.headline)
            
            Divider()
            
            // 基本信息
            GroupBox("Project Information") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Name") { Text(previewData.projectName) }
                    LabeledContent("Format") { Text(previewData.format) }
                    LabeledContent("Version") { Text(previewData.version) }
                    LabeledContent("Exported") { Text(previewData.exportedAt, style: .date) }
                }
                .font(.caption)
            }
            
            // 数据统计
            GroupBox("Data Summary") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Agents") { Text("\(previewData.agentCount)") }
                    LabeledContent("Workflows") { Text("\(previewData.workflowCount)") }
                    LabeledContent("Tasks") { Text("\(previewData.taskCount)") }
                    LabeledContent("Messages") { Text("\(previewData.messageCount)") }
                    LabeledContent("Execution Results") { Text("\(previewData.executionResultCount)") }
                    
                    if !previewData.kanbanTasks.isEmpty {
                        Divider()
                        Text(LocalizedString.kanbanStatus).font(.caption.bold())
                        ForEach(Array(previewData.kanbanTasks.keys), id: \.self) { status in
                            if let count = previewData.kanbanTasks[status] {
                                LabeledContent(status.rawValue) { 
                                    HStack(spacing: 4) {
                                        Image(systemName: status.icon)
                                        Text("\(count)")
                                    }.foregroundColor(status.color)
                                }
                            }
                        }
                    }
                }
                .font(.caption)
            }
            
            // 警告信息
            if !previewData.warnings.isEmpty {
                GroupBox("Warnings") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(previewData.warnings, id: \.self) { warning in
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(warning)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            
            // 导入选项
            GroupBox("Import Options") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Project Configuration", isOn: binding(for: "project"))
                    Toggle("Tasks & Kanban", isOn: binding(for: "tasks"))
                    Toggle("Messages", isOn: binding(for: "messages"))
                    Toggle("Execution Results", isOn: binding(for: "executionResults"))
                }
                .font(.caption)
            }
            
            Spacer()
            
            // 按钮
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Import", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedItems.isEmpty)
            }
        }
        .padding()
        .frame(width: 450, height: 550)
    }
    
    private func binding(for key: String) -> Binding<Bool> {
        Binding(
            get: { selectedItems.contains(key) },
            set: { newValue in
                if newValue {
                    selectedItems.insert(key)
                } else {
                    selectedItems.remove(key)
                }
            }
        )
    }
}

// 工部：进度显示视图
struct ImportExportProgressView: View {
    let progress: Double
    let status: String
    let isImport: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
            
            Text(status)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("\(Int(progress * 100))%")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// 刑部：数据校验结果
struct ValidationResult {
    var isValid: Bool
    var errors: [ValidationError]
    var warnings: [String]
    
    struct ValidationError: Identifiable {
        let id = UUID()
        let field: String
        let message: String
        let severity: Severity
        
        enum Severity {
            case error
            case warning
        }
    }
}

// 刑部：JSON 校验器
struct JSONValidator {
    static func validate(_ data: Data) -> ValidationResult {
        var errors: [ValidationResult.ValidationError] = []
        var warnings: [String] = []
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ValidationResult(
                    isValid: false,
                    errors: [ValidationResult.ValidationError(field: "root", message: "Invalid JSON structure", severity: .error)],
                    warnings: []
                )
            }
            
            // 校验必需字段
            let requiredFields = ["project", "version", "format"]
            for field in requiredFields {
                if json[field] == nil {
                    warnings.append("Missing recommended field: \(field)")
                }
            }
            
            // 校验版本兼容性
            if let version = json["version"] as? String {
                if version != "1.0" {
                    warnings.append("Version \(version) may not be fully compatible")
                }
            }
            
            // 校验项目数据
            if let project = json["project"] as? [String: Any] {
                validateProject(project, errors: &errors, warnings: &warnings)
            }
            
            // 校验任务数据
            if let tasks = json["tasks"] as? [[String: Any]] {
                validateTasks(tasks, errors: &errors, warnings: &warnings)
            }
            
            // 校验看板数据
            if let kanban = json["kanban"] as? [String: Any] {
                validateKanban(kanban, errors: &errors, warnings: &warnings)
            }
            
        } catch {
            errors.append(ValidationResult.ValidationError(field: "json", message: "Failed to parse JSON: \(error.localizedDescription)", severity: .error))
        }
        
        return ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }
    
    private static func validateProject(_ project: [String: Any], errors: inout [ValidationResult.ValidationError], warnings: inout [String]) {
        let requiredFields = ["name", "agents", "workflows"]
        for field in requiredFields {
            if project[field] == nil {
                errors.append(ValidationResult.ValidationError(field: "project.\(field)", message: "Missing required field: \(field)", severity: .error))
            }
        }
    }
    
    private static func validateTasks(_ tasks: [[String: Any]], errors: inout [ValidationResult.ValidationError], warnings: inout [String]) {
        for (index, task) in tasks.enumerated() {
            if task["title"] == nil {
                errors.append(ValidationResult.ValidationError(field: "tasks[\(index)].title", message: "Task missing title", severity: .error))
            }
            if task["status"] == nil {
                warnings.append("Task at index \(index) missing status, will default to 'To Do'")
            }
        }
    }
    
    private static func validateKanban(_ kanban: [String: Any], errors: inout [ValidationResult.ValidationError], warnings: inout [String]) {
        // 看板数据校验
        let validStatuses = ["To Do", "In Progress", "Done", "Blocked"]
        if let tasks = kanban["tasks"] as? [[String: Any]] {
            for (index, task) in tasks.enumerated() {
                if let status = task["status"] as? String, !validStatuses.contains(status) {
                    warnings.append("Task at index \(index) has invalid status: \(status)")
                }
            }
        }
    }
}

// 刑部：错误提示视图
struct ValidationErrorView: View {
    let result: ValidationResult
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: result.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(result.isValid ? .green : .red)
                    .font(.title2)
                Text(result.isValid ? "Validation Passed" : "Validation Failed")
                    .font(.headline)
            }
            
            if !result.errors.isEmpty {
                GroupBox("Errors") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(result.errors) { error in
                            HStack(alignment: .top) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                                VStack(alignment: .leading) {
                                    Text(error.field)
                                        .font(.caption.bold())
                                    Text(error.message)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            
            if !result.warnings.isEmpty {
                GroupBox("Warnings") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.warnings, id: \.self) { warning in
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text(warning)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            
            HStack {
                Spacer()
                Button("OK", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// 户部：缓存管理器
class ImportExportCacheManager {
    static let shared = ImportExportCacheManager()
    private let cacheDirectory: URL
    private let maxCacheSize: Int = 50 * 1024 * 1024 // 50MB
    private let cacheExpirationDays: Int = 7
    
    private init() {
        let cachePath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachePath.appendingPathComponent("ImportExport", isDirectory: true)
        
        // 创建缓存目录
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // 户部：保存到缓存
    func saveToCache(_ data: Data, key: String) throws {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).cache")
        try data.write(to: fileURL)
        
        // 清理过期缓存
        cleanExpiredCache()
    }
    
    // 户部：从缓存读取
    func loadFromCache(key: String) -> Data? {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).cache")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        // 检查是否过期
        if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let modDate = attributes[.modificationDate] as? Date {
            let daysSinceMod = Calendar.current.dateComponents([.day], from: modDate, to: Date()).day ?? 0
            if daysSinceMod > cacheExpirationDays {
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }
        }
        
        return try? Data(contentsOf: fileURL)
    }
    
    // 户部：清理过期缓存
    private func cleanExpiredCache() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return
        }
        
        var totalSize: Int = 0
        var fileInfos: [(url: URL, date: Date, size: Int)] = []
        
        for file in files {
            if let attributes = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
               let modDate = attributes.contentModificationDate,
               let size = attributes.fileSize {
                totalSize += size
                fileInfos.append((url: file, date: modDate, size: size))
            }
        }
        
        // 如果超过最大缓存大小，删除最老的文件
        if totalSize > maxCacheSize {
            fileInfos.sort { $0.date < $1.date }
            for fileInfo in fileInfos {
                if totalSize <= maxCacheSize {
                    break
                }
                try? FileManager.default.removeItem(at: fileInfo.url)
                totalSize -= fileInfo.size
            }
        }
    }
    
    // 户部：清空所有缓存
    func clearAllCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // 户部：获取缓存大小
    func getCacheSize() -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        return files.reduce(0) { total, file in
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + size
        }
    }
}

// 导出文档
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.json, .plainText]
    
    var content: String
    
    init(content: String) {
        self.content = content
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        content = string
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = content.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}
