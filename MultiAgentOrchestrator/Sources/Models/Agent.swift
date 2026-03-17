//
//  Agent.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import Foundation
import CoreGraphics

struct Agent: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var description: String
    var soulMD: String
    var position: CGPoint
    var createdAt: Date
    var updatedAt: Date
    var capabilities: [String]
    
    // 不需要为 CGPoint 定义 Codable，因为我们有单独的扩展文件
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.description = ""
        self.soulMD = "# 新智能体\n这是我的配置..."
        self.position = .zero
        self.createdAt = Date()
        self.updatedAt = Date()
        self.capabilities = ["basic"]
    }
    
    // 自动合成 Equatable 和 Hashable
    // 因为所有属性都符合 Hashable，所以不需要手动实现
}
