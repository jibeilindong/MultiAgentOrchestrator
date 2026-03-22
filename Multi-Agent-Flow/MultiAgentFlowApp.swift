//
//  MultiAgentFlowApp.swift
//

import SwiftUI
import AppKit
import Combine

// 通知名称扩展
extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}

enum RuntimeEnvironment {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}

enum AppLaunchHooks {
    static var didFinishLaunching: (() -> Void)?
    static var willTerminate: (() -> Void)?
}

final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLaunchHooks.didFinishLaunching?()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLaunchHooks.willTerminate?()
    }
}

@MainActor
final class AppRuntimeContext: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    let isRunningTests: Bool
    let appState: AppState?
    let appLaunchBenchmarkRunner: AppLaunchBenchmarkRunner?

    init() {
        let runningTests = RuntimeEnvironment.isRunningTests
        self.isRunningTests = runningTests

        guard !runningTests else {
            self.appState = nil
            self.appLaunchBenchmarkRunner = nil
            AppLaunchHooks.didFinishLaunching = nil
            AppLaunchHooks.willTerminate = nil
            return
        }

        let appState = AppState()
        let benchmarkRunner = AppLaunchBenchmarkRunner()
        self.appState = appState
        self.appLaunchBenchmarkRunner = benchmarkRunner

        AppLaunchHooks.didFinishLaunching = {
            benchmarkRunner.runIfRequested(appState: appState)
        }
        AppLaunchHooks.willTerminate = {
            appState.shutdown()
        }
    }
}

@MainActor
final class AppWindowManager {
    static let shared = AppWindowManager()

    private let settings = SettingsManager.shared
    private let minimumWindowSize = NSSize(width: 720, height: 560)
    private weak var mainWindow: NSWindow?
    private var observerTokens: [NSObjectProtocol] = []

    private init() {}

    func bindMainWindow(_ window: NSWindow) {
        let isNewWindow = mainWindow !== window
        mainWindow = window

        configure(window)

        guard isNewWindow else { return }

        tearDownObservers()
        restoreFrame(for: window)
        installObservers(for: window)
    }

    func minimizeMainWindow() {
        activeWindow?.miniaturize(nil)
    }

    func zoomMainWindow() {
        activeWindow?.zoom(nil)
    }

    func toggleFullScreen() {
        activeWindow?.toggleFullScreen(nil)
    }

    func resetMainWindowFrame() {
        guard let window = activeWindow else { return }

        let targetFrame = defaultFrame(for: window.screen)
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak window] in
                guard let self, let window else { return }
                self.apply(frame: targetFrame, to: window, animate: true)
            }
            return
        }

        apply(frame: targetFrame, to: window, animate: true)
    }

    private var activeWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow ?? mainWindow
    }

    private func configure(_ window: NSWindow) {
        window.styleMask.insert(.resizable)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.minSize = minimumWindowSize
        window.setFrameAutosaveName("MultiAgentFlowMainWindow")
    }

    private func restoreFrame(for window: NSWindow) {
        let restoredFrame = settings.windowFrame.map { sanitizedFrame($0, on: window.screen) }
            ?? defaultFrame(for: window.screen)
        apply(frame: restoredFrame, to: window, animate: false)
    }

    private func apply(frame: NSRect, to window: NSWindow, animate: Bool) {
        window.setFrame(frame, display: true, animate: animate)
        persistFrame(for: window)
    }

    private func persistFrame(for window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen) else { return }
        settings.windowFrame = sanitizedFrame(window.frame, on: window.screen)
    }

    private func installObservers(for window: NSWindow) {
        let center = NotificationCenter.default

        observerTokens = [
            center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self, weak window] _ in
                DispatchQueue.main.async { [weak self, weak window] in
                    guard let self, let window else { return }
                    self.persistFrame(for: window)
                }
            },
            center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self, weak window] _ in
                DispatchQueue.main.async { [weak self, weak window] in
                    guard let self, let window else { return }
                    self.persistFrame(for: window)
                }
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self, weak window] _ in
                DispatchQueue.main.async { [weak self, weak window] in
                    guard let self else { return }
                    if let window {
                        self.persistFrame(for: window)
                    }
                    self.mainWindow = nil
                    self.tearDownObservers()
                }
            }
        ]
    }

    private func tearDownObservers() {
        let center = NotificationCenter.default
        observerTokens.forEach(center.removeObserver)
        observerTokens.removeAll()
    }

    private func defaultFrame(for screen: NSScreen?) -> NSRect {
        let visibleFrame = visibleFrame(for: screen)
        let width = min(max(visibleFrame.width * 0.78, minimumWindowSize.width), 1480)
        let height = min(max(visibleFrame.height * 0.82, minimumWindowSize.height), 980)
        let origin = NSPoint(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2
        )
        return NSRect(origin: origin, size: NSSize(width: width, height: height)).integral
    }

    private func sanitizedFrame(_ frame: NSRect, on screen: NSScreen?) -> NSRect {
        let visibleFrame = visibleFrame(for: screen)
        let width = min(max(frame.width, minimumWindowSize.width), visibleFrame.width)
        let height = min(max(frame.height, minimumWindowSize.height), visibleFrame.height)

        var originX = frame.origin.x
        var originY = frame.origin.y

        if originX < visibleFrame.minX || originX + width > visibleFrame.maxX {
            originX = visibleFrame.midX - width / 2
        }
        if originY < visibleFrame.minY || originY + height > visibleFrame.maxY {
            originY = visibleFrame.midY - height / 2
        }

        return NSRect(
            x: round(originX),
            y: round(originY),
            width: round(width),
            height: round(height)
        )
    }

    private func visibleFrame(for screen: NSScreen?) -> NSRect {
        screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }
}

private struct MainWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                AppWindowManager.shared.bindMainWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                AppWindowManager.shared.bindMainWindow(window)
            }
        }
    }
}

@main
struct MultiAgentFlowApp: App {
    @StateObject private var runtimeContext = AppRuntimeContext()
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @State private var showingSettings = false
    @State private var showingToolbarCustomization = false
    @State private var selectedTab = 0
    @State private var zoomScale: CGFloat = 1.0

    var body: some Scene {
        WindowGroup {
            if let appState = runtimeContext.appState {
                ContentView(selectedTab: $selectedTab, zoomScale: $zoomScale)
                    .environmentObject(appState)
                    .background(MainWindowAccessor())
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
            } else {
                EmptyView()
            }
        }
        .commands {
            if let appState = runtimeContext.appState {
                CommandGroup(replacing: .appInfo) {
                    Button(LocalizedString.format("about_app", LocalizedString.appName)) {
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

                    Button(LocalizedString.text("customize_toolbar")) {
                        showingToolbarCustomization = true
                    }

                    Button(LocalizedString.text("reset_toolbar_layout")) {
                        appState.resetToolbarLayout()
                    }

                    Divider()

                    Button(languageMenuTitle(for: .simplifiedChinese, appState: appState)) {
                        appState.localizationManager.setLanguage(.simplifiedChinese)
                    }

                    Button(languageMenuTitle(for: .traditionalChinese, appState: appState)) {
                        appState.localizationManager.setLanguage(.traditionalChinese)
                    }

                    Button(languageMenuTitle(for: .english, appState: appState)) {
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

                    Button(LocalizedString.text("save_project_as")) {
                        appState.saveProjectAs()
                    }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                }

                CommandGroup(after: .saveItem) {
                    Button(LocalizedString.text("import_architecture")) {
                        appState.importData()
                    }
                    .keyboardShortcut("i", modifiers: [.command, .shift])

                    Button(LocalizedString.text("export_architecture")) {
                        appState.exportData()
                    }
                    .keyboardShortcut("e", modifiers: [.command, .shift])

                    if appState.currentProject != nil {
                        Divider()

                        Button(LocalizedString.text("delete_project")) {
                            appState.deleteCurrentProject()
                        }

                        Button(LocalizedString.closeProject) {
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
                        AppWindowManager.shared.minimizeMainWindow()
                    }
                    .keyboardShortcut("m", modifiers: .command)

                    Button(LocalizedString.zoom) {
                        AppWindowManager.shared.zoomMainWindow()
                    }
                    .keyboardShortcut("m", modifiers: [.command, .control])

                    Button(LocalizedString.toggleFullScreen) {
                        AppWindowManager.shared.toggleFullScreen()
                    }
                    .keyboardShortcut("f", modifiers: [.command, .control])

                    Button(LocalizedString.resetWindowSize) {
                        AppWindowManager.shared.resetMainWindowFrame()
                    }
                    .keyboardShortcut("0", modifiers: [.command, .option])

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
                        if let url = URL(string: "https://github.com/chenrongze/Multi-Agent-Flow/issues") {
                            NSWorkspace.shared.open(url)
                        }
                    }

                    Divider()

                    Button(LocalizedString.viewOnGitHub) {
                        if let url = URL(string: "https://github.com/chenrongze/Multi-Agent-Flow") {
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

    private func languageMenuTitle(for language: AppLanguage, appState: AppState) -> String {
        let prefix = appState.localizationManager.currentLanguage == language ? "✓ " : ""
        return prefix + language.displayName
    }
}
