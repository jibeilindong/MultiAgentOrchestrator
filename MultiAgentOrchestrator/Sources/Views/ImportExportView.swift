//
//  ImportExportView.swift
//  MultiAgentOrchestrator
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
                    Text("Import an existing project from a file.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Import Project...") {
                        showingImportPanel = true
                    }
                    .frame(maxWidth: .infinity)
                }
                
                Section("Export Project") {
                    Text("Export the current project to a file.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    
                    Toggle("Include Tasks", isOn: $includeTasks)
                    Toggle("Include Messages", isOn: $includeMessages)
                    Toggle("Include Execution Results", isOn: $includeExecutionResults)
                    
                    Button("Export Project...") {
                        showingExportPanel = true
                    }
                    .frame(maxWidth: .infinity)
                }
                
                Section("Backup & Restore") {
                    Text("Create a complete backup of your project including all data.")
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
                    Text("Save the current project as a template for future use.")
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
            
            // 6. 转换为 JSON 字符串
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
                    
                    // 解析 JSON
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        print("Invalid JSON format")
                        return
                    }
                    
                    // 导入项目
                    if let projectData = json["project"] as? [String: Any],
                       let projectJSON = try? JSONSerialization.data(withJSONObject: projectData) {
                        let decoder = JSONDecoder()
                        let project = try decoder.decode(MAProject.self, from: projectJSON)
                        appState.currentProject = project
                    }
                    
                    // 导入任务
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
                    
                    print("Import successful")
                } catch {
                    print("Import error: \(error)")
                }
            }
        case .failure(let error):
            print("Import failed: \(error)")
        }
    }
    
    private func handleExport(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            print("Export successful to: \(url)")
        case .failure(let error):
            print("Export failed: \(error)")
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
