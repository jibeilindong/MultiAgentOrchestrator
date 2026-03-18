//
//  SettingsManager.swift
//  MultiAgentOrchestrator
//
//  设置持久化管理器
//

import Foundation

class SettingsManager {
    static let shared = SettingsManager()
    
    private let defaults = UserDefaults.standard
    
    // 设置键
    private enum Keys {
        static let appVersion = "appVersion"
        static let language = "appLanguage"
        static let appearanceMode = "appearanceMode"
        static let autoSaveEnabled = "autoSaveEnabled"
        static let autoSaveInterval = "autoSaveInterval"
        static let showWelcomeScreen = "showWelcomeScreen"
        static let enableAnimations = "enableAnimations"
        static let maxUndoSteps = "maxUndoSteps"
        static let lastOpenedProject = "lastOpenedProject"
        static let recentProjects = "recentProjects"
        static let windowFrame = "windowFrame"
        static let sidebarWidth = "sidebarWidth"
        static let propertiesPanelWidth = "propertiesPanelWidth"
    }
    
    // 当前应用版本（用于迁移）
    private let currentAppVersion = "1.0.0"
    
    private init() {
        // 初始化时执行迁移
        migrateIfNeeded()
    }
    
    // MARK: - 版本迁移
    
    private func migrateIfNeeded() {
        let savedVersion = defaults.string(forKey: Keys.appVersion) ?? "0.0.0"
        
        if savedVersion != currentAppVersion {
            performMigration(from: savedVersion, to: currentAppVersion)
            defaults.set(currentAppVersion, forKey: Keys.appVersion)
        }
    }
    
    private func performMigration(from oldVersion: String, to newVersion: String) {
        // 在这里处理旧版本的迁移逻辑
        // 例如：v0.9.x -> v1.0.0
        
        print("执行设置迁移: \(oldVersion) -> \(newVersion)")
        
        // 示例迁移：如果是从旧版本来的，设置默认值
        if oldVersion == "0.0.0" {
            // 首次安装，设置默认值
            defaults.set(true, forKey: Keys.autoSaveEnabled)
            defaults.set(5, forKey: Keys.autoSaveInterval)
            defaults.set(true, forKey: Keys.showWelcomeScreen)
            defaults.set(true, forKey: Keys.enableAnimations)
            defaults.set(50, forKey: Keys.maxUndoSteps)
        }
    }
    
    // MARK: - 语言设置
    
    var language: AppLanguage {
        get {
            if let saved = defaults.string(forKey: Keys.language),
               let lang = AppLanguage(rawValue: saved) {
                return lang
            }
            return .simplifiedChinese
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.language)
        }
    }
    
    // MARK: - 外观设置
    
    var appearanceMode: String {
        get { defaults.string(forKey: Keys.appearanceMode) ?? "system" }
        set { defaults.set(newValue, forKey: Keys.appearanceMode) }
    }
    
    // MARK: - 自动保存设置
    
    var autoSaveEnabled: Bool {
        get { defaults.bool(forKey: Keys.autoSaveEnabled) }
        set { defaults.set(newValue, forKey: Keys.autoSaveEnabled) }
    }
    
    var autoSaveInterval: Int {
        get {
            let value = defaults.integer(forKey: Keys.autoSaveInterval)
            return value > 0 ? value : 5
        }
        set { defaults.set(newValue, forKey: Keys.autoSaveInterval) }
    }
    
    // MARK: - 欢迎屏幕
    
    var showWelcomeScreen: Bool {
        get { defaults.bool(forKey: Keys.showWelcomeScreen) }
        set { defaults.set(newValue, forKey: Keys.showWelcomeScreen) }
    }
    
    // MARK: - 动画设置
    
    var enableAnimations: Bool {
        get {
            if defaults.object(forKey: Keys.enableAnimations) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.enableAnimations)
        }
        set { defaults.set(newValue, forKey: Keys.enableAnimations) }
    }
    
    // MARK: - 撤销步骤
    
    var maxUndoSteps: Int {
        get {
            let value = defaults.integer(forKey: Keys.maxUndoSteps)
            return value > 0 ? value : 50
        }
        set { defaults.set(newValue, forKey: Keys.maxUndoSteps) }
    }
    
    // MARK: - 最近项目
    
    var lastOpenedProject: URL? {
        get {
            if let path = defaults.string(forKey: Keys.lastOpenedProject) {
                return URL(fileURLWithPath: path)
            }
            return nil
        }
        set {
            defaults.set(newValue?.path, forKey: Keys.lastOpenedProject)
        }
    }
    
    var recentProjects: [URL] {
        get {
            guard let paths = defaults.stringArray(forKey: Keys.recentProjects) else {
                return []
            }
            return paths.map { URL(fileURLWithPath: $0) }
        }
        set {
            // 限制最多保存10个最近项目
            let limited = Array(newValue.prefix(10))
            defaults.set(limited.map { $0.path }, forKey: Keys.recentProjects)
        }
    }
    
    func addRecentProject(_ url: URL) {
        var recent = recentProjects
        // 移除已存在的
        recent.removeAll { $0 == url }
        // 添加到开头
        recent.insert(url, at: 0)
        // 保存
        recentProjects = recent
    }
    
    // MARK: - 窗口设置
    
    var windowFrame: NSRect? {
        get {
            guard let data = defaults.data(forKey: Keys.windowFrame) else {
                return nil
            }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSValue.self, from: data)?.rectValue
        }
        set {
            if let rect = newValue {
                let value = NSValue(rect: rect)
                if let data = try? NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true) {
                    defaults.set(data, forKey: Keys.windowFrame)
                }
            } else {
                defaults.removeObject(forKey: Keys.windowFrame)
            }
        }
    }
    
    var sidebarWidth: CGFloat {
        get {
            let value = defaults.double(forKey: Keys.sidebarWidth)
            return value > 0 ? value : 250
        }
        set { defaults.set(newValue, forKey: Keys.sidebarWidth) }
    }
    
    var propertiesPanelWidth: CGFloat {
        get {
            let value = defaults.double(forKey: Keys.propertiesPanelWidth)
            return value > 0 ? value : 250
        }
        set { defaults.set(newValue, forKey: Keys.propertiesPanelWidth) }
    }
    
    // MARK: - 数据校验
    
    func validateSettings() -> [String] {
        var issues: [String] = []
        
        // 验证语言
        if defaults.string(forKey: Keys.language) == nil {
            issues.append("语言设置缺失，使用默认值")
        }
        
        // 验证自动保存间隔
        let interval = defaults.integer(forKey: Keys.autoSaveInterval)
        if interval < 1 || interval > 60 {
            issues.append("自动保存间隔无效，范围应为1-60分钟")
        }
        
        // 验证最大撤销步骤
        let undoSteps = defaults.integer(forKey: Keys.maxUndoSteps)
        if undoSteps < 10 || undoSteps > 200 {
            issues.append("最大撤销步骤无效，范围应为10-200")
        }
        
        return issues
    }
    
    // MARK: - 重置设置
    
    func resetToDefaults() {
        let domain = Bundle.main.bundleIdentifier ?? "com.example.app"
        defaults.removePersistentDomain(forName: domain)
        defaults.set(currentAppVersion, forKey: Keys.appVersion)
    }
    
    // MARK: - 导出/导入设置
    
    func exportSettings() -> Data? {
        let settings: [String: Any] = [
            Keys.language: language.rawValue,
            Keys.appearanceMode: appearanceMode,
            Keys.autoSaveEnabled: autoSaveEnabled,
            Keys.autoSaveInterval: autoSaveInterval,
            Keys.showWelcomeScreen: showWelcomeScreen,
            Keys.enableAnimations: enableAnimations,
            Keys.maxUndoSteps: maxUndoSteps
        ]
        
        return try? JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)
    }
    
    func importSettings(from data: Data) -> Bool {
        guard let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        
        if let lang = settings[Keys.language] as? String,
           let appLang = AppLanguage(rawValue: lang) {
            language = appLang
        }
        
        if let mode = settings[Keys.appearanceMode] as? String {
            appearanceMode = mode
        }
        
        if let autoSave = settings[Keys.autoSaveEnabled] as? Bool {
            autoSaveEnabled = autoSave
        }
        
        if let interval = settings[Keys.autoSaveInterval] as? Int {
            autoSaveInterval = interval
        }
        
        if let welcome = settings[Keys.showWelcomeScreen] as? Bool {
            showWelcomeScreen = welcome
        }
        
        if let animations = settings[Keys.enableAnimations] as? Bool {
            enableAnimations = animations
        }
        
        if let undo = settings[Keys.maxUndoSteps] as? Int {
            maxUndoSteps = undo
        }
        
        return true
    }
}
