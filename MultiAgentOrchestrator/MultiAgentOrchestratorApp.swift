//
//  MultiAgentOrchestratorApp.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

@main
struct MultiAgentOrchestratorApp: App {
    @StateObject private var appState = AppState()
    @State private var showingImportExport = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .commands {
            // 文件菜单
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    appState.createNewProject()
                }
                .keyboardShortcut("n")
                
                Divider()
                
                Button("Open Project...") {
                    appState.loadProject()
                }
                .keyboardShortcut("o")
                
                Button("Save Project") {
                    appState.saveProject()
                }
                .keyboardShortcut("s")
                
                Divider()
                
                Button("Import/Export...") {
                    showingImportExport = true
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            
            // 编辑菜单
            CommandGroup(after: .pasteboard) {
                Divider()
                
                Button("Run Workflow") {
                    // 执行当前工作流
                }
                .keyboardShortcut("r", modifiers: [.command])
                
                Button("Stop Execution") {
                    // 停止执行
                }
                .keyboardShortcut(".", modifiers: [.command])
            }
            
            // 视图菜单
            CommandGroup(after: .toolbar) {
                Divider()
                
                Button("Show/Hide Sidebar") {
                    // 切换侧边栏
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
