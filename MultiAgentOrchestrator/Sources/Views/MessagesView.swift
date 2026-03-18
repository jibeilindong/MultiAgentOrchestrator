//
//  MessagesView.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct MessagesView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var messageManager: MessageManager
    
    @State private var selectedAgentID: UUID?
    @State private var messageText: String = ""
    @State private var messageType: MessageType = .text
    @State private var showingNewMessage = false
    @State private var showingApprovals = false
    
    var agents: [Agent] {
        appState.currentProject?.agents ?? []
    }
    
    var selectedAgent: Agent? {
        if let id = selectedAgentID {
            return agents.first { $0.id == id }
        }
        return nil
    }
    
    var currentAgent: Agent? {
        // 假设第一个Agent是当前用户
        agents.first
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Text(LocalizedString.messages)
                    .font(.title2)
                
                Spacer()
                
                // 待审批消息计数
                if messageManager.pendingApprovals.count > 0 {
                    Button {
                        showingApprovals = true
                    } label: {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                            Text("\(messageManager.pendingApprovals.count) pending")
                        }
                        .foregroundColor(.orange)
                    }
                }
                
                Button("New Message") {
                    showingNewMessage = true
                }
            }
            .padding()
            
            Divider()
            
            if agents.isEmpty {
                ContentUnavailableView(
                    "No Agents",
                    systemImage: "person.slash",
                    description: Text(LocalizedString.addAgentsToStartMessaging)
                )
            } else {
                HStack(spacing: 0) {
                    // Agent列表
                    VStack(alignment: .leading, spacing: 0) {
                        Text(LocalizedString.agents)
                            .font(.headline)
                            .padding()
                        
                        List(selection: $selectedAgentID) {
                            ForEach(agents) { agent in
                                AgentMessageRow(agent: agent, unreadCount: unreadCount(for: agent.id))
                                    .tag(agent.id)
                            }
                        }
                        .listStyle(.plain)
                    }
                    .frame(width: 250)
                    .background(Color(.controlBackgroundColor))
                    
                    Divider()
                    
                    // 消息区域
                    if let agent = selectedAgent, let current = currentAgent {
                        MessageConversationView(
                            fromAgent: current,
                            toAgent: agent,
                            messageManager: messageManager,
                            project: appState.currentProject
                        )
                        .environmentObject(appState)
                    } else {
                        ContentUnavailableView(
                            "Select an Agent",
                            systemImage: "person.crop.circle",
                            description: Text(LocalizedString.selectAgentToViewMessages)
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewMessage) {
            NewMessageView(agents: agents) { message in
                if messageManager.sendMessage(message, project: appState.currentProject) {
                    print("Message sent successfully")
                }
            }
        }
        .sheet(isPresented: $showingApprovals) {
            ApprovalsView(messageManager: messageManager)
        }
    }
    
    private func unreadCount(for agentID: UUID) -> Int {
        messageManager.messagesForAgent(agentID)
            .filter { $0.status == .delivered || $0.status == .sent }
            .count
    }
}

// Agent消息行
struct AgentMessageRow: View {
    let agent: Agent
    let unreadCount: Int
    
    var body: some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .foregroundColor(.blue)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.headline)
                Text(agent.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.blue))
                    .foregroundColor(.white)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

// 消息对话视图
struct MessageConversationView: View {
    @EnvironmentObject var appState: AppState
    let fromAgent: Agent
    let toAgent: Agent
    @ObservedObject var messageManager: MessageManager
    let project: MAProject?
    
    @State private var newMessageText: String = ""
    @State private var selectedMessageType: MessageType = .text
    
    var messages: [Message] {
        messageManager.messagesBetween(agent1: fromAgent.id, agent2: toAgent.id)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 对话标题
            HStack {
                Image(systemName: "person.circle.fill")
                    .foregroundColor(.blue)
                Text(toAgent.name)
                    .font(.headline)
                Spacer()
                
                // 权限指示器
                if let project = project {
                    let permission = project.permission(from: fromAgent, to: toAgent)
                    Label(permission.rawValue, systemImage: permission.icon)
                        .foregroundColor(permission.color)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(permission.color.opacity(0.1)))
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            
            // 消息列表
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if messages.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.largeTitle)
                                    .foregroundColor(.gray)
                                Text(LocalizedString.noMessages)
                                    .foregroundColor(.secondary)
                                Text("Start a conversation with \(toAgent.name)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                        } else {
                            ForEach(messages) { message in
                                MessageBubbleView(message: message, isFromCurrentUser: message.fromAgentID == fromAgent.id)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // 输入区域
            HStack {
                Picker("", selection: $selectedMessageType) {
                    ForEach(MessageType.allCases, id: \.self) { type in
                        Label(type.rawValue, systemImage: type.icon).tag(type)
                    }
                }
                .frame(width: 100)
                .labelsHidden()
                
                TextField("Type a message...", text: $newMessageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                    .lineLimit(1...5)
                    .onSubmit {
                        sendMessage()
                    }
                
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
    
    private func sendMessage() {
        guard !newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let message = Message(
            from: fromAgent.id,
            to: toAgent.id,
            type: selectedMessageType,
            content: newMessageText,
            requiresApproval: project?.permission(from: fromAgent, to: toAgent) == .requireApproval
        )
        
        if messageManager.sendMessage(message, project: project) {
            newMessageText = ""
        }
    }
}

// 消息气泡视图
struct MessageBubbleView: View {
    let message: Message
    let isFromCurrentUser: Bool
    
    var body: some View {
        HStack(alignment: .bottom) {
            if !isFromCurrentUser {
                Image(systemName: "person.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
            }
            
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // 消息类型标签
                HStack {
                    Image(systemName: message.type.icon)
                        .font(.caption2)
                    Text(message.type.rawValue)
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
                
                // 消息内容
                Text(message.content)
                    .padding(12)
                    .background(isFromCurrentUser ? Color.blue : Color(.controlBackgroundColor))
                    .foregroundColor(isFromCurrentUser ? .white : .primary)
                    .cornerRadius(12)
                
                // 消息状态和时间
                HStack(spacing: 8) {
                    if isFromCurrentUser {
                        Image(systemName: message.status.icon)
                            .font(.caption2)
                            .foregroundColor(message.status.color)
                    }
                    
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            if isFromCurrentUser {
                Image(systemName: "person.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            }
        }
        .frame(maxWidth: .infinity, alignment: isFromCurrentUser ? .trailing : .leading)
        .padding(.horizontal, 4)
    }
}

// 新消息视图
struct NewMessageView: View {
    let agents: [Agent]
    let onSend: (Message) -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedAgentID: UUID?
    @State private var messageText: String = ""
    @State private var messageType: MessageType = .text
    
    var body: some View {
        NavigationView {
            Form {
                Section("Recipient") {
                    Picker("To", selection: $selectedAgentID) {
                        Text("Select").tag(nil as UUID?)
                        ForEach(agents) { agent in
                            Text(agent.name).tag(agent.id as UUID?)
                        }
                    }
                }
                
                Section("Message") {
                    Picker("Type", selection: $messageType) {
                        ForEach(MessageType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                    
                    TextEditor(text: $messageText)
                        .frame(height: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Message")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        if let agentID = selectedAgentID,
                           let fromAgent = agents.first {
                            let message = Message(
                                from: fromAgent.id,
                                to: agentID,
                                type: messageType,
                                content: messageText
                            )
                            onSend(message)
                            dismiss()
                        }
                    }
                    .disabled(selectedAgentID == nil || messageText.isEmpty)
                }
            }
            .frame(minWidth: 400, minHeight: 300)
        }
    }
}

// 审批视图
struct ApprovalsView: View {
    @ObservedObject var messageManager: MessageManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                if messageManager.pendingApprovals.isEmpty {
                    ContentUnavailableView(
                        "No Pending Approvals",
                        systemImage: "checkmark.shield",
                        description: Text("All messages have been approved")
                    )
                } else {
                    List {
                        ForEach(messageManager.pendingApprovals) { message in
                            ApprovalRowView(message: message, messageManager: messageManager)
                        }
                    }
                }
            }
            .navigationTitle("Pending Approvals")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .frame(minWidth: 500, minHeight: 400)
        }
    }
}

// 审批行视图
struct ApprovalRowView: View {
    let message: Message
    @ObservedObject var messageManager: MessageManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: message.type.icon)
                Text(message.type.rawValue)
                    .font(.headline)
                Spacer()
                Text(message.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(message.content)
                .font(.body)
                .foregroundColor(.secondary)
            
            HStack {
                Button("Approve") {
                    approveMessage()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                
                Button("Reject") {
                    rejectMessage()
                }
                .buttonStyle(.bordered)
                .tint(.red)
                
                Spacer()
            }
        }
        .padding(.vertical, 8)
    }
    
    private func approveMessage() {
        // 因为 fromAgentID 是 UUID 类型（非可选），我们可以直接使用
        _ = messageManager.approveMessage(message.id, approvedBy: message.fromAgentID)
    }
    
    private func rejectMessage() {
        // 因为 fromAgentID 是 UUID 类型（非可选），我们可以直接使用
        _ = messageManager.rejectMessage(message.id, rejectedBy: message.fromAgentID)
    }
}
