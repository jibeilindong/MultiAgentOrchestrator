//
//  MultiAgentOrchestratorApp.swift
//

import SwiftUI

@main
struct MultiAgentOrchestratorApp: App {
    @StateObject private var appState = AppState()
    @State private var showingSettings = false
    @State private var selectedTab = 0
    @State private var zoomScale: CGFloat = 1.0
    
    var body: some Scene {
        WindowGroup {
            ContentView(selectedTab: $selectedTab, zoomScale: $zoomScale)
                .environmentObject(appState)
                .sheet(isPresented: $showingSettings) {
                    SettingsView()
                        .environmentObject(appState)
                }
        }
        .commands {
            // ========== 应用菜单 ==========
            CommandGroup(replacing: .appInfo) {
                Button("About \(LocalizedString.appName)") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: LocalizedString.appName,
                            .applicationVersion: "1.0.0"
                        ]
                    )
                }
            }
            
            CommandGroup(replacing: .appSettings) {
                Button(LocalizedString.settings) {
                    showingSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            
            // ========== 文件菜单 ==========
            CommandMenu(LocalizedString.file) {
                Button(LocalizedString.newProject) {
                    appState.createNewProject()
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button(LocalizedString.openProject) {
                    appState.loadProject()
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Divider()
                
                Button(LocalizedString.saveProject) {
                    appState.saveProject()
                }
                .keyboardShortcut("s", modifiers: .command)
                
                Divider()
                
                Button(LocalizedString.importText) {
                    appState.importData()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                
                Button(LocalizedString.export) {
                    appState.exportData()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                
                Divider()
                
                Button(LocalizedString.exit) {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            
            // ========== 编辑菜单 ==========
            CommandMenu(LocalizedString.edit) {
                Button(LocalizedString.undo) {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                }
                .keyboardShortcut("z", modifiers: .command)
                
                Button(LocalizedString.redo) {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                
                Divider()
                
                Button(LocalizedString.cut) {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: .command)
                
                Button(LocalizedString.copy) {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: .command)
                
                Button(LocalizedString.paste) {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("v", modifiers: .command)
                
                Button(LocalizedString.selectAll) {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("a", modifiers: .command)
            }
            
            // ========== 视图菜单 ==========
            CommandMenu(LocalizedString.view) {
                Button(LocalizedString.workflow) {
                    selectedTab = 0
                }
                .keyboardShortcut("1", modifiers: .command)
                
                Button(LocalizedString.tasks) {
                    selectedTab = 1
                }
                .keyboardShortcut("2", modifiers: .command)
                
                Button(LocalizedString.dashboard) {
                    selectedTab = 2
                }
                .keyboardShortcut("3", modifiers: .command)
                
                Button(LocalizedString.controlPanel) {
                    selectedTab = 3
                }
                .keyboardShortcut("4", modifiers: .command)
                
                Button(LocalizedString.permissions) {
                    selectedTab = 4
                }
                .keyboardShortcut("5", modifiers: .command)
                
                Divider()
                
                Button(LocalizedString.zoomIn) {
                    zoomScale = min(zoomScale * 1.25, 3.0)
                }
                .keyboardShortcut("+", modifiers: .command)
                
                Button(LocalizedString.zoomOut) {
                    zoomScale = max(zoomScale / 1.25, 0.25)
                }
                .keyboardShortcut("-", modifiers: .command)
                
                Button(LocalizedString.resetZoom) {
                    zoomScale = 1.0
                }
                .keyboardShortcut("0", modifiers: .command)
                
                Divider()
                
                Button(LocalizedString.toggleSidebar) {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
            
            // ========== 工具菜单 ==========
            CommandMenu(LocalizedString.tools) {
                Button(LocalizedString.addAgent) {
                    appState.addNewAgent()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                
                Button(LocalizedString.addNode) {
                    appState.addNewNode()
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
                
                Divider()
                
                Button(LocalizedString.generateFromWorkflow) {
                    appState.generateTasksFromWorkflow()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                
                Divider()
                
                Button(LocalizedString.systemLogs) {
                    appState.showLogs.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            
            // ========== 语言菜单 ==========
            CommandMenu(LocalizedString.language) {
                ForEach(AppLanguage.allCases) { language in
                    Button(action: {
                        appState.localizationManager.setLanguage(language)
                    }) {
                        HStack {
                            Text(language.displayName)
                            if appState.localizationManager.currentLanguage == language {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            
            // ========== 窗口菜单 ==========
            CommandMenu(LocalizedString.window) {
                Button(LocalizedString.minimize) {
                    NSApp.keyWindow?.miniaturize(nil)
                }
                .keyboardShortcut("m", modifiers: .command)
                
                Button(LocalizedString.zoom) {
                    NSApp.keyWindow?.zoom(nil)
                }
                .keyboardShortcut("m", modifiers: [.command, .control])
                
                Divider()
                
                Button(LocalizedString.bringAllToFront) {
                    NSApp.arrangeInFront(nil)
                }
            }
            
            // ========== 帮助菜单 ==========
            CommandGroup(replacing: .help) {
                Button(LocalizedString.help) {
                    appState.showHelp()
                }
                .keyboardShortcut("?", modifiers: .command)
                
                Divider()
                
                Button(LocalizedString.reportIssue) {
                    if let url = URL(string: "https://github.com/chenrongze/MultiAgentOrchestrator/issues") {
                        NSWorkspace.shared.open(url)
                    }
                }
                
                Divider()
                
                Button(LocalizedString.viewOnGitHub) {
                    if let url = URL(string: "https://github.com/chenrongze/MultiAgentOrchestrator") {
                        NSWorkspace.shared.open(url)
                    }
                }
                
                Divider()
                
                Button(LocalizedString.keyboardShortcuts) {
                    appState.showKeyboardShortcuts()
                }
                .keyboardShortcut("/", modifiers: .command)
            }
        }
    }
}
