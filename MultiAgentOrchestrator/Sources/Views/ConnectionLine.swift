//
//  ConnectionLine.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct ConnectionLine: Shape {
    let from: CGPoint
    let to: CGPoint
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        
        // 计算控制点，创建平滑的贝塞尔曲线
        let dx = to.x - from.x
        let dy = to.y - from.y
        let distance = sqrt(dx * dx + dy * dy)
        
        let controlOffset = min(100, distance / 2)
        
        let controlPoint1: CGPoint
        let controlPoint2: CGPoint
        
        if abs(dx) > abs(dy) {
            // 水平连接为主
            controlPoint1 = CGPoint(x: from.x + controlOffset, y: from.y)
            controlPoint2 = CGPoint(x: to.x - controlOffset, y: to.y)
        } else {
            // 垂直连接为主
            controlPoint1 = CGPoint(x: from.x, y: from.y + controlOffset)
            controlPoint2 = CGPoint(x: to.x, y: to.y - controlOffset)
        }
        
        path.addCurve(to: to, control1: controlPoint1, control2: controlPoint2)
        
        // 添加箭头
        let angle = atan2(to.y - controlPoint2.y, to.x - controlPoint2.x)
        let arrowLength: CGFloat = 10
        let arrowAngle: CGFloat = .pi / 6
        
        let arrowPoint1 = CGPoint(
            x: to.x - arrowLength * cos(angle - arrowAngle),
            y: to.y - arrowLength * sin(angle - arrowAngle)
        )
        
        let arrowPoint2 = CGPoint(
            x: to.x - arrowLength * cos(angle + arrowAngle),
            y: to.y - arrowLength * sin(angle + arrowAngle)
        )
        
        path.move(to: to)
        path.addLine(to: arrowPoint1)
        path.move(to: to)
        path.addLine(to: arrowPoint2)
        
        return path
    }
}
