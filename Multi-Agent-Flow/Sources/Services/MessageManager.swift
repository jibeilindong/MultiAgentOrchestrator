//
//  MessageManager.swift
//  Multi-Agent-Flow
//
//  Created by 陈荣泽 on 2026/3/18.
//

import Foundation
import Combine

class MessageManager: ObservableObject {
    @Published var messages: [Message] = []
    @Published var pendingApprovals: [Message] = []
    
    private var cancellables = Set<AnyCancellable>()

    func replaceMessages(_ newMessages: [Message]) {
        messages = newMessages
        pendingApprovals = newMessages.filter { $0.status == .waitingForApproval }
    }

    func reset() {
        messages.removeAll()
        pendingApprovals.removeAll()
    }

    func appendMessage(_ message: Message) {
        messages.append(message)
        if message.status == .waitingForApproval {
            pendingApprovals.append(message)
        }
    }

    func updateMessage(_ messageID: UUID, mutate: (inout Message) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        var message = messages[index]
        mutate(&message)
        messages[index] = message

        if let pendingIndex = pendingApprovals.firstIndex(where: { $0.id == messageID }) {
            if message.status == .waitingForApproval {
                pendingApprovals[pendingIndex] = message
            } else {
                pendingApprovals.remove(at: pendingIndex)
            }
        } else if message.status == .waitingForApproval {
            pendingApprovals.append(message)
        }
    }

    func workbenchMessages(for workflowID: UUID?) -> [Message] {
        messages
            .filter { message in
                message.metadata["channel"] == "workbench"
                    && (workflowID == nil || message.metadata["workflowID"] == workflowID?.uuidString)
            }
            .sorted { $0.timestamp < $1.timestamp }
    }
    
    // 发送消息
    func sendMessage(_ message: Message, project: MAProject?) -> Bool {
        guard let project = project else { return false }
        
        // 检查权限
        guard let fromAgent = project.agents.first(where: { $0.id == message.fromAgentID }),
              let toAgent = project.agents.first(where: { $0.id == message.toAgentID }) else {
            var failedMessage = message
            failedMessage.status = .failed
            failedMessage.metadata["error"] = "Agent not found"
            messages.append(failedMessage)
            return false
        }
        
        // 检查权限
        let permission = project.permission(from: fromAgent, to: toAgent)
        
        switch permission {
        case .allow:
            var sentMessage = message
            sentMessage.status = .sent
            messages.append(sentMessage)
            
            // 模拟消息传递
            simulateMessageDelivery(messageId: sentMessage.id)
            return true
            
        case .deny:
            var failedMessage = message
            failedMessage.status = .failed
            failedMessage.metadata["error"] = "Permission denied"
            messages.append(failedMessage)
            return false
            
        case .requireApproval:
            var pendingMessage = message
            pendingMessage.requiresApproval = true
            pendingMessage.status = .waitingForApproval
            messages.append(pendingMessage)
            pendingApprovals.append(pendingMessage)
            return true
        }
    }
    
    // 模拟消息传递
    private func simulateMessageDelivery(messageId: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if let index = self?.messages.firstIndex(where: { $0.id == messageId }) {
                self?.messages[index].status = MessageStatus.delivered
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self?.messages[index].status = MessageStatus.read
                }
            }
        }
    }
    
    // 审批消息
    func approveMessage(_ messageId: UUID, approvedBy: UUID) -> Bool {
        guard let messageIndex = messages.firstIndex(where: { $0.id == messageId }),
              let approvalIndex = pendingApprovals.firstIndex(where: { $0.id == messageId }) else {
            return false
        }
        
        var updatedMessage = messages[messageIndex]
        updatedMessage.status = MessageStatus.approved
        updatedMessage.approvedBy = approvedBy
        updatedMessage.approvalTimestamp = Date()
        
        messages[messageIndex] = updatedMessage
        pendingApprovals.remove(at: approvalIndex)
        
        // 发送已批准的消息
        var sentMessage = updatedMessage
        sentMessage.status = MessageStatus.sent
        sentMessage.requiresApproval = false
        simulateMessageDelivery(messageId: sentMessage.id)
        
        return true
    }

    // 拒绝消息
    func rejectMessage(_ messageId: UUID, rejectedBy: UUID) -> Bool {
        guard let messageIndex = messages.firstIndex(where: { $0.id == messageId }),
              let approvalIndex = pendingApprovals.firstIndex(where: { $0.id == messageId }) else {
            return false
        }
        
        var updatedMessage = messages[messageIndex]
        updatedMessage.status = MessageStatus.rejected
        updatedMessage.approvedBy = rejectedBy
        updatedMessage.approvalTimestamp = Date()
        updatedMessage.metadata["rejection_reason"] = "Manually rejected"
        
        messages[messageIndex] = updatedMessage
        pendingApprovals.remove(at: approvalIndex)
        
        return true
    }
    
    // 获取两个Agent之间的消息
    func messagesBetween(agent1: UUID, agent2: UUID) -> [Message] {
        messages.filter { ($0.fromAgentID == agent1 && $0.toAgentID == agent2) ||
                         ($0.fromAgentID == agent2 && $0.toAgentID == agent1) }
            .sorted { $0.timestamp < $1.timestamp }
    }
    
    // 获取Agent相关的消息
    func messagesForAgent(_ agentID: UUID) -> [Message] {
        messages.filter { $0.toAgentID == agentID }
            .sorted { $0.timestamp < $1.timestamp }
    }
    
    func messagesFromAgent(_ agentID: UUID) -> [Message] {
        messages.filter { $0.fromAgentID == agentID }
            .sorted { $0.timestamp < $1.timestamp }
    }
    
    // 添加示例数据
    func addSampleMessages(agents: [Agent], project: MAProject) {
        guard agents.count >= 2 else { return }
        
        let agent1 = agents[0]
        let agent2 = agents[1]
        
        let sampleMessages = [
            Message(from: agent1.id, to: agent2.id, type: MessageType.text,
                   content: "Hello, can you help me with the research task?",
                   requiresApproval: project.permission(from: agent1, to: agent2) == PermissionType.requireApproval),
            Message(from: agent2.id, to: agent1.id, type: MessageType.text,
                   content: "Sure, what do you need help with?",
                   requiresApproval: project.permission(from: agent2, to: agent1) == PermissionType.requireApproval),
            Message(from: agent1.id, to: agent2.id, type: MessageType.task,
                   content: "Please analyze the AI trends data",
                   requiresApproval: project.permission(from: agent1, to: agent2) == PermissionType.requireApproval),
            Message(from: agent2.id, to: agent1.id, type: MessageType.data,
                   content: "Here's the analysis report: AI is growing rapidly",
                   requiresApproval: project.permission(from: agent2, to: agent1) == PermissionType.requireApproval),
            Message(from: agent1.id, to: agent2.id, type: MessageType.command,
                   content: "Execute the data processing pipeline",
                   requiresApproval: project.permission(from: agent1, to: agent2) == PermissionType.requireApproval),
        ]
        
        // 处理消息状态
        var processedMessages: [Message] = []
        for (index, var message) in sampleMessages.enumerated() {
            message.timestamp = Date().addingTimeInterval(TimeInterval(-index * 3600))
            
            if message.requiresApproval {
                message.status = MessageStatus.waitingForApproval
                pendingApprovals.append(message)
            } else {
                message.status = MessageStatus.read
            }
            
            processedMessages.append(message)
        }
        
        messages.append(contentsOf: processedMessages)
    }
    
    // 清理旧消息
    func cleanupOldMessages(olderThan hours: Int = 24) {
        let cutoffDate = Date().addingTimeInterval(TimeInterval(-hours * 3600))
        messages.removeAll { $0.timestamp < cutoffDate && $0.status != .waitingForApproval }
    }
}
