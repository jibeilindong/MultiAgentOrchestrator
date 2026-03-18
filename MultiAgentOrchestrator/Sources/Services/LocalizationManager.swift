//
//  LocalizationManager.swift
//

import Foundation
import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .english: return "English"
        }
    }
}

class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    @Published var currentLanguage: AppLanguage = .simplifiedChinese {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "appLanguage")
            objectWillChange.send()
        }
    }
    
    private init() {
        if let savedLanguage = UserDefaults.standard.string(forKey: "appLanguage"),
           let language = AppLanguage(rawValue: savedLanguage) {
            currentLanguage = language
        }
    }
    
    func setLanguage(_ language: AppLanguage) {
        currentLanguage = language
    }
}

struct LocalizedString {
    static var manager: LocalizationManager { LocalizationManager.shared }
    
    private static func localized(_ key: String) -> String {
        let lang = manager.currentLanguage
        
        let en: [String: String] = [
            "app_name": "Multi-Agent Orchestrator",
            "save": "Save",
            "cancel": "Cancel",
            "delete": "Delete",
            "edit": "Edit",
            "add": "Add",
            "new": "New",
            "search": "Search",
            "settings": "Settings",
            "help": "Help",
            "close": "Close",
            "confirm": "Confirm",
            "name": "Name",
            "description": "Description",
            "status": "Status",
            "actions": "Actions",
            "create": "Create",
            "import": "Import",
            "export": "Export",
            "backup": "Backup",
            "restore": "Restore",
            "ok": "OK",
            "project": "Project",
            "projects": "Projects",
            "new_project": "New Project",
            "open_project": "Open Project",
            "save_project": "Save Project",
            "project_name": "Project Name",
            "workflow": "Workflow",
            "workflows": "Workflows",
            "workflow_editor": "Workflow Editor",
            "node": "Node",
            "nodes": "Nodes",
            "add_node": "Add Node",
            "delete_node": "Delete Node",
            "node_properties": "Node Properties",
            "start_node": "Start Node",
            "end_node": "End Node",
            "agent_node": "Agent Node",
            "connection": "Connection",
            "connections": "Connections",
            "create_connection": "Create Connection",
            "delete_connection": "Delete Connection",
            "agent": "Agent",
            "agents": "Agents",
            "add_agent": "Add Agent",
            "edit_agent": "Edit Agent",
            "delete_agent": "Delete Agent",
            "agent_name": "Agent Name",
            "no_agents": "No Agents",
            "unassigned": "Unassigned",
            "task": "Task",
            "tasks": "Tasks",
            "new_task": "New Task",
            "task_name": "Task Name",
            "task_status": "Task Status",
            "todo": "To Do",
            "in_progress": "In Progress",
            "completed": "Completed",
            "pending": "Pending",
            "blocked": "Blocked",
            "kanban": "Kanban",
            "task_board": "Task Board",
            "dashboard": "Dashboard",
            "statistics": "Statistics",
            "priority": "Priority",
            "low": "Low",
            "medium": "Medium",
            "high": "High",
            "message": "Message",
            "messages": "Messages",
            "send_message": "Send Message",
            "new_message": "New Message",
            "pending_approval": "Pending Approval",
            "approve": "Approve",
            "reject": "Reject",
            "no_messages": "No Messages",
            "send": "Send",
            "permission": "Permission",
            "permissions": "Permissions",
            "permission_matrix": "Permission Matrix",
            "access_control": "Access Control",
            "execute": "Execute",
            "executing": "Executing",
            "execution": "Execution",
            "execution_results": "Execution Results",
            "start_execution": "Start Execution",
            "stop_execution": "Stop Execution",
            "clear_results": "Clear Results",
            "execution_history": "Execution History",
            "select_workflow": "Select Workflow",
            "logs": "Logs",
            "control_panel": "Control Panel",
            "system_settings": "System Settings",
            "system_logs": "System Logs",
            "monitoring": "Monitoring",
            "performance": "Performance",
            "language": "Language",
            "switch_language": "Switch Language",
            "file": "File",
            "view": "View",
            "window": "Window",
            "minimize": "Minimize",
            "exit": "Exit",
            "undo": "Undo",
            "redo": "Redo",
            "cut": "Cut",
            "copy": "Copy",
            "paste": "Paste",
            "selectAll": "Select All",
            "toggleSidebar": "Toggle Sidebar",
            "generateFromWorkflow": "Generate from Workflow",
            "zoom": "Zoom",
            "bringAllToFront": "Bring All to Front",
            "reportIssue": "Report Issue...",
            "viewOnGitHub": "View on GitHub",
            "zoom_in": "Zoom In",
            "zoom_out": "Zoom Out",
            "reset_zoom": "Reset Zoom",
            "tools": "Tools",
            "general": "General",
            "appearance": "Appearance",
            "theme": "Theme",
            "light": "Light",
            "dark": "Dark",
            "system": "System",
            "system_status": "System Status",
            "agent_status": "Agent Status",
            "no_agents_available": "No agents available",
            "realtime_statistics": "Realtime Statistics",
            "active_total": "%@/%@",
            "about": "About",
            "version": "Version",
            "keyboard_shortcuts": "Keyboard Shortcuts",
            "advanced": "Advanced",
            "auto_save": "Auto Save",
            "auto_save_interval": "Auto Save Interval",
            "show_welcome_screen": "Show Welcome Screen",
            "enable_animations": "Enable Animations",
            "max_undo_steps": "Max Undo Steps",
            "drop_to_add_node": "Drop to add node",
            "connecting_to_openclaw": "Connecting to OpenClaw...",
            "node_execution": "Node Execution",
            "execution_logs": "Execution Logs",
            "execute_workflow_to_see_results": "Execute a workflow to see results",
            "import_preview": "Import Preview",
            "kanban_status": "Kanban Status",
            "add_agents_to_start_messaging": "Add agents to start messaging",
            "select_agent_to_view_messages": "Select an agent to view messages",
            "all_messages_approved": "All messages have been approved",
            "estimated_time": "Estimated Time:",
            "subflow": "Subflow",
            "no_agents_permission": "No Agents",
            "na": "N/A",
            "select_node_to_edit": "Select a node on the canvas to view and edit its properties.",
            "soul_md_config": "Soul.md Configuration",
            "capabilities": "Capabilities",
            "no_agents_created": "No agents created yet.",
            "export_project_backup": "Export your project for sharing or backup.",
            "no_subflow_assigned": "No Subflow Assigned",
            "create_or_select_subflow": "Create a new subflow or select an existing one.",
            "new_subflow_will_be_created": "A new subflow will be created and linked to this node.",
            "no_nodes_in_subflow": "No nodes in this subflow",
            "task_details": "Task Details",
            "select_target_agent": "Select target agent",
            "test": "Test",
            "auto_detect": "Auto Detect",
            "saving": "Saving...",
            "auto_saved": "Auto-saved",
            "position": "Position",
            "start_conversation": "Start a conversation with %@",
            "pending_approvals": "%@ pending",
            "canvas_controls": "Canvas Controls",
            "drag_to_move_canvas": "Drag to move canvas",
            "pinch_to_zoom": "Pinch to zoom",
            "double_click_to_connect": "Double-click to connect",
            "agent_permissions_matrix": "Agent Permissions Matrix",
            "from_to": "From > To",
            "navigation": "Navigation",
            "template": "Template",
            "select_node": "Select a node",
            "legend": "Legend",
            "allowed": "Allowed",
            "denied": "Denied",
            "self_na": "Self (N/A)",
            "openclaw_connection": "OpenClaw Connection",
            "connection_settings": "Connection Settings",
            "host": "Host",
            "port": "Port",
            "api_key": "API Key",
            "timeout": "Timeout",
            "seconds": "seconds",
            "connect": "Connect",
            "testing_connection": "Testing connection...",
            "connection_success": "Connection successful!",
            "connection_failed": "Connection failed",
            "default_agent": "Default Agent",
            "auto_connect": "Auto Connect on Startup",
            "agent_library": "Agent Library",
            "openclaw_agents": "OpenClaw Agents",
            "project_agents": "Project Agents",
            "node_types": "Node Types",
            "generate_architecture": "Generate Architecture",
            "add_agents_to_project": "Add Agents to Project",
            "close_project": "Close Project",
            "auto_detect_connect": "Auto Detect & Connect",
            "manual_connect": "Manual Connect",
            "disconnect": "Disconnect",
            "connected": "Connected",
            "disconnected": "Disconnected"
        ]
        
        let zhHans: [String: String] = [
            "app_name": "多智能体编排器",
            "save": "保存",
            "cancel": "取消",
            "delete": "删除",
            "edit": "编辑",
            "add": "添加",
            "new": "新建",
            "search": "搜索",
            "settings": "设置",
            "help": "帮助",
            "close": "关闭",
            "confirm": "确认",
            "name": "名称",
            "description": "描述",
            "status": "状态",
            "actions": "操作",
            "create": "创建",
            "import": "导入",
            "export": "导出",
            "backup": "备份",
            "restore": "恢复",
            "ok": "确定",
            "project": "项目",
            "projects": "项目集",
            "new_project": "新建项目",
            "open_project": "打开项目",
            "save_project": "保存项目",
            "project_name": "项目名称",
            "workflow": "工作流",
            "workflows": "工作流",
            "workflow_editor": "工作流编辑器",
            "node": "节点",
            "nodes": "节点",
            "add_node": "添加节点",
            "delete_node": "删除节点",
            "node_properties": "节点属性",
            "connection": "连接",
            "connections": "连接",
            "create_connection": "创建连接",
            "delete_connection": "删除连接",
            "agent": "智能体",
            "agents": "智能体",
            "add_agent": "添加智能体",
            "edit_agent": "编辑智能体",
            "delete_agent": "删除智能体",
            "agent_name": "智能体名称",
            "no_agents": "暂无智能体",
            "unassigned": "未分配",
            "task": "任务",
            "tasks": "任务",
            "new_task": "新建任务",
            "task_name": "任务名称",
            "task_status": "任务状态",
            "todo": "待办",
            "in_progress": "进行中",
            "completed": "已完成",
            "pending": "待处理",
            "blocked": "已阻塞",
            "kanban": "看板",
            "task_board": "任务看板",
            "dashboard": "仪表盘",
            "statistics": "统计",
            "priority": "优先级",
            "low": "低",
            "medium": "中",
            "high": "高",
            "message": "消息",
            "messages": "消息",
            "send_message": "发送消息",
            "new_message": "新消息",
            "pending_approval": "待审批",
            "approve": "批准",
            "reject": "拒绝",
            "no_messages": "暂无消息",
            "send": "发送",
            "permission": "权限",
            "permissions": "权限",
            "permission_matrix": "权限矩阵",
            "access_control": "访问控制",
            "execute": "执行",
            "executing": "执行中",
            "execution": "执行",
            "execution_results": "执行结果",
            "start_execution": "开始执行",
            "stop_execution": "停止执行",
            "clear_results": "清除结果",
            "execution_history": "执行历史",
            "select_workflow": "选择工作流",
            "logs": "日志",
            "control_panel": "控制面板",
            "system_settings": "系统设置",
            "system_logs": "系统日志",
            "monitoring": "监控",
            "performance": "性能",
            "language": "语言",
            "switch_language": "切换语言",
            "file": "文件",
            "view": "视图",
            "window": "窗口",
            "minimize": "最小化",
            "exit": "退出",
            "undo": "撤销",
            "redo": "重做",
            "cut": "剪切",
            "copy": "复制",
            "paste": "粘贴",
            "selectAll": "全选",
            "toggleSidebar": "切换侧边栏",
            "generateFromWorkflow": "从工作流生成",
            "zoom": "缩放",
            "bringAllToFront": "全部前置",
            "reportIssue": "报告问题...",
            "viewOnGitHub": "在 GitHub 上查看",
            "zoom_in": "放大",
            "zoom_out": "缩小",
            "reset_zoom": "重置缩放",
            "tools": "工具",
            "general": "常规",
            "appearance": "外观",
            "theme": "主题",
            "light": "浅色",
            "dark": "深色",
            "system": "跟随系统",
            "system_status": "系统状态",
            "agent_status": "智能体状态",
            "no_agents_available": "暂无可用智能体",
            "realtime_statistics": "实时统计",
            "active_total": "%@/%@",
            "about": "关于",
            "version": "版本",
            "keyboard_shortcuts": "键盘快捷键",
            "advanced": "高级",
            "auto_save": "自动保存",
            "auto_save_interval": "自动保存间隔",
            "show_welcome_screen": "显示欢迎屏幕",
            "enable_animations": "启用动画",
            "max_undo_steps": "最大撤销步骤",
            "drop_to_add_node": "释放以添加节点",
            "connecting_to_openclaw": "正在连接 OpenClaw...",
            "node_execution": "节点执行",
            "execution_logs": "执行日志",
            "execute_workflow_to_see_results": "执行工作流以查看结果",
            "import_preview": "导入预览",
            "kanban_status": "看板状态",
            "add_agents_to_start_messaging": "添加智能体以开始消息",
            "select_agent_to_view_messages": "选择智能体以查看消息",
            "all_messages_approved": "所有消息已批准",
            "estimated_time": "预计时间：",
            "subflow": "子流程",
            "no_agents_permission": "无智能体",
            "na": "N/A",
            "select_node_to_edit": "在画布上选择节点以查看和编辑其属性",
            "soul_md_config": "Soul.md 配置",
            "capabilities": "能力",
            "no_agents_created": "尚未创建智能体",
            "export_project_backup": "导出项目以共享或备份",
            "no_subflow_assigned": "未分配子流程",
            "create_or_select_subflow": "创建新子流程或选择现有子流程",
            "new_subflow_will_be_created": "将创建新子流程并链接到此节点",
            "no_nodes_in_subflow": "此子流程中没有节点",
            "task_details": "任务详情",
            "select_target_agent": "选择目标智能体",
            "test": "测试",
            "auto_detect": "自动检测",
            "saving": "保存中...",
            "auto_saved": "已自动保存",
            "agent_library": "智能体库",
            "openclaw_agents": "OpenClaw智能体",
            "project_agents": "项目智能体",
            "node_types": "节点类型",
            "generate_architecture": "生成架构",
            "add_agents_to_project": "添加智能体到项目",
            "close_project": "关闭项目",
            "auto_detect_connect": "自动检测并连接",
            "manual_connect": "手动连接",
            "connected": "已连接",
            "disconnected": "未连接",
            "agent_node": "智能体节点",
            "branch_node": "分支节点",
            "start_node": "起始节点",
            "end_node": "结束节点",
            "position": "位置",
            "start_conversation": "开始与 %@ 对话",
            "pending_approvals": "%@ 待审批"
        ]
        
        let zhHant: [String: String] = [
            "app_name": "多智慧體編排器",
            "save": "儲存",
            "cancel": "取消",
            "delete": "刪除",
            "edit": "編輯",
            "add": "新增",
            "new": "新建",
            "search": "搜尋",
            "settings": "設定",
            "help": "說明",
            "close": "關閉",
            "confirm": "確認",
            "name": "名稱",
            "description": "描述",
            "status": "狀態",
            "actions": "操作",
            "create": "建立",
            "import": "匯入",
            "export": "匯出",
            "backup": "備份",
            "restore": "還原",
            "ok": "確定",
            "project": "專案",
            "projects": "專案",
            "new_project": "新建專案",
            "open_project": "開啟專案",
            "save_project": "儲存專案",
            "project_name": "專案名稱",
            "workflow": "工作流",
            "workflows": "工作流",
            "workflow_editor": "工作流編輯器",
            "node": "節點",
            "nodes": "節點",
            "add_node": "新增節點",
            "delete_node": "刪除節點",
            "node_properties": "節點屬性",
            "start_node": "起始節點",
            "end_node": "結束節點",
            "agent_node": "智慧體節點",
            "connection": "連線",
            "connections": "連線",
            "create_connection": "建立連線",
            "delete_connection": "刪除連線",
            "agent": "智慧體",
            "agents": "智慧體",
            "add_agent": "新增智慧體",
            "edit_agent": "編輯智慧體",
            "delete_agent": "刪除智慧體",
            "agent_name": "智慧體名稱",
            "no_agents": "暫無智慧體",
            "unassigned": "未分配",
            "task": "任務",
            "tasks": "任務",
            "new_task": "新建任務",
            "task_name": "任務名稱",
            "task_status": "任務狀態",
            "todo": "待辦",
            "in_progress": "進行中",
            "completed": "已完成",
            "pending": "待處理",
            "blocked": "已阻塞",
            "kanban": "看板",
            "task_board": "任務看板",
            "dashboard": "儀表板",
            "statistics": "統計",
            "priority": "優先順序",
            "low": "低",
            "medium": "中",
            "high": "高",
            "message": "訊息",
            "messages": "訊息",
            "send_message": "傳送訊息",
            "new_message": "新訊息",
            "pending_approval": "待審批",
            "approve": "核准",
            "reject": "拒絕",
            "no_messages": "暫無訊息",
            "send": "傳送",
            "permission": "權限",
            "permissions": "權限",
            "permission_matrix": "權限矩陣",
            "access_control": "存取控制",
            "execute": "執行",
            "executing": "執行中",
            "execution": "執行",
            "execution_results": "執行結果",
            "start_execution": "開始執行",
            "stop_execution": "停止執行",
            "clear_results": "清除結果",
            "execution_history": "執行歷史",
            "select_workflow": "選擇工作流",
            "logs": "日誌",
            "control_panel": "控制面板",
            "system_settings": "系統設定",
            "system_logs": "系統日誌",
            "monitoring": "監控",
            "performance": "效能",
            "language": "語言",
            "switch_language": "切換語言",
            "file": "檔案",
            "view": "檢視",
            "window": "視窗",
            "minimize": "最小化",
            "exit": "結束",
            "undo": "復原",
            "redo": "重做",
            "cut": "剪下",
            "copy": "複製",
            "paste": "貼上",
            "selectAll": "全選",
            "toggleSidebar": "切換側邊欄",
            "generateFromWorkflow": "從工作流生成",
            "zoom": "縮放",
            "bringAllToFront": "全部前置",
            "reportIssue": "報告問題...",
            "viewOnGitHub": "在 GitHub 上查看",
            "zoom_in": "放大",
            "zoom_out": "縮小",
            "reset_zoom": "重設縮放",
            "tools": "工具",
            "general": "一般",
            "appearance": "外觀",
            "theme": "主題",
            "light": "淺色",
            "dark": "深色",
            "system": "跟隨系統",
            "system_status": "系統狀態",
            "agent_status": "智慧體狀態",
            "no_agents_available": "暫無可用智慧體",
            "realtime_statistics": "即時統計",
            "active_total": "%@/%@",
            "about": "關於",
            "version": "版本",
            "keyboard_shortcuts": "鍵盤快捷鍵",
            "advanced": "進階",
            "auto_save": "自動儲存",
            "auto_save_interval": "自動儲存間隔",
            "show_welcome_screen": "顯示歡迎畫面",
            "enable_animations": "啟用動畫",
            "max_undo_steps": "最大復原步驟",
            "drop_to_add_node": "釋放以新增節點",
            "connecting_to_openclaw": "正在連線 OpenClaw...",
            "node_execution": "節點執行",
            "execution_logs": "執行日誌",
            "execute_workflow_to_see_results": "執行工作流以查看結果",
            "import_preview": "匯入預覽",
            "kanban_status": "看板狀態",
            "add_agents_to_start_messaging": "新增智慧體以開始訊息",
            "select_agent_to_view_messages": "選擇智慧體以查看訊息",
            "all_messages_approved": "所有訊息已核准",
            "estimated_time": "預估時間：",
            "subflow": "子流程",
            "no_agents_permission": "無智慧體",
            "na": "N/A",
            "select_node_to_edit": "在畫布上選擇節點以檢視和編輯其屬性",
            "soul_md_config": "Soul.md 組態",
            "capabilities": "能力",
            "no_agents_created": "尚未建立智慧體",
            "export_project_backup": "匯出專案以共用或備份",
            "no_subflow_assigned": "未分配子流程",
            "create_or_select_subflow": "建立新子流程或選擇現有子流程",
            "new_subflow_will_be_created": "將建立新子流程並連結至此節點",
            "no_nodes_in_subflow": "此子流程中沒有節點",
            "task_details": "任務詳情",
            "select_target_agent": "選擇目標智慧體",
            "test": "測試",
            "auto_detect": "自動偵測",
            "saving": "儲存中...",
            "auto_saved": "已自動儲存",
            "agent_library": "智慧體庫",
            "openclaw_agents": "OpenClaw智慧體",
            "project_agents": "專案智慧體",
            "node_types": "節點類型",
            "generate_architecture": "產生架構",
            "add_agents_to_project": "新增智慧體至專案",
            "close_project": "關閉專案",
            "auto_detect_connect": "自動偵測並連線",
            "manual_connect": "手動連線",
            "connected": "已連線",
            "disconnected": "未連線",
            "position": "位置",
            "start_conversation": "開始與 %@ 對話",
            "pending_approvals": "%@ 待審批"
        ]
        
        let dict: [String: String]
        switch lang {
        case .english: dict = en
        case .simplifiedChinese: dict = zhHans
        case .traditionalChinese: dict = zhHant
        }
        
        return dict[key] ?? key
    }
    
    static var appName: String { localized("app_name") }
    static var save: String { localized("save") }
    static var cancel: String { localized("cancel") }
    static var delete: String { localized("delete") }
    static var edit: String { localized("edit") }
    static var add: String { localized("add") }
    static var new: String { localized("new") }
    static var search: String { localized("search") }
    static var settings: String { localized("settings") }
    static var help: String { localized("help") }
    static var close: String { localized("close") }
    static var confirm: String { localized("confirm") }
    static var name: String { localized("name") }
    static var description: String { localized("description") }
    static var status: String { localized("status") }
    static var actions: String { localized("actions") }
    static var create: String { localized("create") }
    static var importText: String { localized("import") }
    static var export: String { localized("export") }
    static var backup: String { localized("backup") }
    static var restore: String { localized("restore") }
    static var ok: String { localized("ok") }
    static var project: String { localized("project") }
    static var projects: String { localized("projects") }
    static var newProject: String { localized("new_project") }
    static var openProject: String { localized("open_project") }
    static var saveProject: String { localized("save_project") }
    static var projectName: String { localized("project_name") }
    static var workflow: String { localized("workflow") }
    static var workflows: String { localized("workflows") }
    static var workflowEditor: String { localized("workflow_editor") }
    static var node: String { localized("node") }
    static var nodes: String { localized("nodes") }
    static var addNode: String { localized("add_node") }
    static var deleteNode: String { localized("delete_node") }
    static var nodeProperties: String { localized("node_properties") }
    static var startNode: String { localized("start_node") }
    static var endNode: String { localized("end_node") }
    static var agentNode: String { localized("agent_node") }
    static var connection: String { localized("connection") }
    static var connections: String { localized("connections") }
    static var createConnection: String { localized("create_connection") }
    static var deleteConnection: String { localized("delete_connection") }
    static var agent: String { localized("agent") }
    static var agents: String { localized("agents") }
    static var addAgent: String { localized("add_agent") }
    static var editAgent: String { localized("edit_agent") }
    static var deleteAgent: String { localized("delete_agent") }
    static var agentName: String { localized("agent_name") }
    static var noAgents: String { localized("no_agents") }
    static var unassigned: String { localized("unassigned") }
    static var task: String { localized("task") }
    static var tasks: String { localized("tasks") }
    static var newTask: String { localized("new_task") }
    static var taskName: String { localized("task_name") }
    static var taskStatus: String { localized("task_status") }
    static var todo: String { localized("todo") }
    static var inProgress: String { localized("in_progress") }
    static var completed: String { localized("completed") }
    static var pending: String { localized("pending") }
    static var blocked: String { localized("blocked") }
    static var kanban: String { localized("kanban") }
    static var taskBoard: String { localized("task_board") }
    static var dashboard: String { localized("dashboard") }
    static var statistics: String { localized("statistics") }
    static var priority: String { localized("priority") }
    static var low: String { localized("low") }
    static var medium: String { localized("medium") }
    static var high: String { localized("high") }
    static var message: String { localized("message") }
    static var messages: String { localized("messages") }
    static var sendMessage: String { localized("send_message") }
    static var newMessage: String { localized("new_message") }
    static var pendingApproval: String { localized("pending_approval") }
    static var approve: String { localized("approve") }
    static var reject: String { localized("reject") }
    static var noMessages: String { localized("no_messages") }
    static var send: String { localized("send") }
    static var permission: String { localized("permission") }
    static var permissions: String { localized("permissions") }
    static var permissionMatrix: String { localized("permission_matrix") }
    static var accessControl: String { localized("access_control") }
    static var execute: String { localized("execute") }
    static var executing: String { localized("executing") }
    static var execution: String { localized("execution") }
    static var executionResults: String { localized("execution_results") }
    static var startExecution: String { localized("start_execution") }
    static var stopExecution: String { localized("stop_execution") }
    static var clearResults: String { localized("clear_results") }
    static var executionHistory: String { localized("execution_history") }
    static var selectWorkflow: String { localized("select_workflow") }
    static var logs: String { localized("logs") }
    static var controlPanel: String { localized("control_panel") }
    static var systemSettings: String { localized("system_settings") }
    static var systemLogs: String { localized("system_logs") }
    static var monitoring: String { localized("monitoring") }
    static var performance: String { localized("performance") }
    static var language: String { localized("language") }
    static var switchLanguage: String { localized("switch_language") }
    static var file: String { localized("file") }
    static var view: String { localized("view") }
    static var window: String { localized("window") }
    static var minimize: String { localized("minimize") }
    static var exit: String { localized("exit") }
    static var undo: String { localized("undo") }
    static var redo: String { localized("redo") }
    static var cut: String { localized("cut") }
    static var copy: String { localized("copy") }
    static var paste: String { localized("paste") }
    static var selectAll: String { localized("selectAll") }
    static var toggleSidebar: String { localized("toggleSidebar") }
    static var generateFromWorkflow: String { localized("generateFromWorkflow") }
    static var zoom: String { localized("zoom") }
    static var bringAllToFront: String { localized("bringAllToFront") }
    static var reportIssue: String { localized("reportIssue") }
    static var viewOnGitHub: String { localized("viewOnGitHub") }
    static var zoomIn: String { localized("zoom_in") }
    static var zoomOut: String { localized("zoom_out") }
    static var resetZoom: String { localized("reset_zoom") }
    static var tools: String { localized("tools") }
    static var general: String { localized("general") }
    static var appearance: String { localized("appearance") }
    static var theme: String { localized("theme") }
    static var light: String { localized("light") }
    static var dark: String { localized("dark") }
    static var system: String { localized("system") }
    static var about: String { localized("about") }
    static var version: String { localized("version") }
    static var canvasControls: String { localized("canvas_controls") }
    static var dragToMoveCanvas: String { localized("drag_to_move_canvas") }
    static var pinchToZoom: String { localized("pinch_to_zoom") }
    static var doubleClickToConnect: String { localized("double_click_to_connect") }
    static var agentPermissionsMatrix: String { localized("agent_permissions_matrix") }
    static var fromTo: String { localized("from_to") }
    static var navigation: String { localized("navigation") }
    static var template: String { localized("template") }
    static var selectNode: String { localized("select_node") }
    static var legend: String { localized("legend") }
    static var allowed: String { localized("allowed") }
    static var denied: String { localized("denied") }
    static var selfNA: String { localized("self_na") }
    static var openclawConnection: String { localized("openclaw_connection") }
    static var connectionSettings: String { localized("connection_settings") }
    static var host: String { localized("host") }
    static var port: String { localized("port") }
    static var apiKey: String { localized("api_key") }
    static var timeout: String { localized("timeout") }
    static var seconds: String { localized("seconds") }
    static var connect: String { localized("connect") }
    static var disconnect: String { localized("disconnect") }
    static var testingConnection: String { localized("testing_connection") }
    static var connectionSuccess: String { localized("connection_success") }
    static var connectionFailed: String { localized("connection_failed") }
    static var defaultAgent: String { localized("default_agent") }
    static var autoConnect: String { localized("auto_connect") }
    static var agentLibrary: String { localized("agent_library") }
    static var openclawAgents: String { localized("openclaw_agents") }
    static var projectAgents: String { localized("project_agents") }
    static var nodeTypes: String { localized("node_types") }
    static var generateArchitecture: String { localized("generate_architecture") }
    static var addAgentsToProject: String { localized("add_agents_to_project") }
    static var closeProject: String { localized("close_project") }
    static var autoDetectConnect: String { localized("auto_detect_connect") }
    static var manualConnect: String { localized("manual_connect") }
    static var connected: String { localized("connected") }
    static var disconnected: String { localized("disconnected") }
    static var systemStatus: String { localized("system_status") }
    static var agentStatus: String { localized("agent_status") }
    static var noAgentsAvailable: String { localized("no_agents_available") }
    static var realtimeStatistics: String { localized("realtime_statistics") }
    static var keyboardShortcuts: String { localized("keyboard_shortcuts") }
    static var advanced: String { localized("advanced") }
    static var autoSave: String { localized("auto_save") }
    static var autoSaveInterval: String { localized("auto_save_interval") }
    static var showWelcomeScreen: String { localized("show_welcome_screen") }
    static var enableAnimations: String { localized("enable_animations") }
    static var maxUndoSteps: String { localized("max_undo_steps") }
    static var dropToAddNode: String { localized("drop_to_add_node") }
    static var connectingToOpenClaw: String { localized("connecting_to_openclaw") }
    static var nodeExecution: String { localized("node_execution") }
    static var executionLogs: String { localized("execution_logs") }
    static var executeWorkflowToSeeResults: String { localized("execute_workflow_to_see_results") }
    static var importPreview: String { localized("import_preview") }
    static var kanbanStatus: String { localized("kanban_status") }
    static var addAgentsToStartMessaging: String { localized("add_agents_to_start_messaging") }
    static var selectAgentToViewMessages: String { localized("select_agent_to_view_messages") }
    static var allMessagesApproved: String { localized("all_messages_approved") }
    static var estimatedTime: String { localized("estimated_time") }
    static var subflow: String { localized("subflow") }
    static var noAgentsPermission: String { localized("no_agents_permission") }
    static var na: String { localized("na") }
    static var selectNodeToEdit: String { localized("select_node_to_edit") }
    static var soulMdConfig: String { localized("soul_md_config") }
    static var capabilities: String { localized("capabilities") }
    static var noAgentsCreated: String { localized("no_agents_created") }
    static var exportProjectBackup: String { localized("export_project_backup") }
    static var noSubflowAssigned: String { localized("no_subflow_assigned") }
    static var createOrSelectSubflow: String { localized("create_or_select_subflow") }
    static var newSubflowWillBeCreated: String { localized("new_subflow_will_be_created") }
    static var noNodesInSubflow: String { localized("no_nodes_in_subflow") }
    static var taskDetails: String { localized("task_details") }
    static var selectTargetAgent: String { localized("select_target_agent") }
    static var test: String { localized("test") }
    static var autoDetect: String { localized("auto_detect") }
    static var saving: String { localized("saving") }
    static var autoSaved: String { localized("auto_saved") }
    static var position: String { localized("position") }
    static var startConversation: String { localized("start_conversation") }
    static var pendingApprovals: String { localized("pending_approvals") }
}
