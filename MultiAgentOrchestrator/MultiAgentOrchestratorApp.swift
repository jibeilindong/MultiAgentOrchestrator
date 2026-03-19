//
//  MultiAgentOrchestratorApp.swift
//

import SwiftUI

// 通知名称扩展
extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}

@main
struct MultiAgentOrchestratorApp: App {
    @StateObject private var appState = AppState()
    @State private var showingSettings = false
    @State private var showingToolbarCustomization = false
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
                .sheet(isPresented: $showingToolbarCustomization) {
                    ToolbarCustomizationSheet()
                        .environmentObject(appState)
                }
                .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                    showingSettings = true
                }
        }
        .commands {
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

            CommandGroup(after: .appSettings) {
                Divider()

                Button("Customize Toolbar…") {
                    showingToolbarCustomization = true
                }

                Button("Reset Toolbar Layout") {
                    appState.resetToolbarLayout()
                }

                Divider()

                Button(languageMenuTitle(for: .simplifiedChinese)) {
                    appState.localizationManager.setLanguage(.simplifiedChinese)
                }

                Button(languageMenuTitle(for: .traditionalChinese)) {
                    appState.localizationManager.setLanguage(.traditionalChinese)
                }

                Button(languageMenuTitle(for: .english)) {
                    appState.localizationManager.setLanguage(.english)
                }
            }

            CommandGroup(replacing: .newItem) {
                Button(LocalizedString.newProject) {
                    appState.createNewProject()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button(LocalizedString.openProject) {
                    appState.openProject()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(replacing: .saveItem) {
                Button(LocalizedString.saveProject) {
                    appState.saveProject()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save Project As…") {
                    appState.saveProjectAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            CommandGroup(after: .saveItem) {
                Button("Import Architecture") {
                    appState.importData()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                
                Button("Export Architecture") {
                    appState.exportData()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                if appState.currentProject != nil {
                    Divider()

                    Button("Delete Project") {
                        appState.deleteCurrentProject()
                    }

                    Button("Close Project") {
                        appState.closeProject()
                    }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                }
            }

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
            }

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

            CommandMenu(LocalizedString.help) {
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

    private func addOpenClawAgentsToProject() {
        guard var project = appState.currentProject else { return }

        for name in appState.openClawManager.agents where !project.agents.contains(where: { $0.name == name }) {
            var agent = Agent(name: name)
            agent.description = "OpenClaw Agent: \(name)"
            project.agents.append(agent)
        }

        project.updatedAt = Date()
        appState.currentProject = project
    }

    private func languageMenuTitle(for language: AppLanguage) -> String {
        let prefix = appState.localizationManager.currentLanguage == language ? "✓ " : ""
        return prefix + language.displayName
    }
}
