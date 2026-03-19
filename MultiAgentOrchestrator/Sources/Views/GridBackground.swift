//
//  GridBackground.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct GridBackground: View {
    let gridSize: CGFloat = 20
    let majorStep: Int = 5
    
    var body: some View {
        Canvas { context, size in
            let verticalCount = Int(ceil(size.width / gridSize))
            let horizontalCount = Int(ceil(size.height / gridSize))

            // 绘制网格（主网格线更明显）
            for index in 0...verticalCount {
                let x = CGFloat(index) * gridSize
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }
                let isMajor = index.isMultiple(of: majorStep)
                context.stroke(
                    path,
                    with: .color(Color.gray.opacity(isMajor ? 0.36 : 0.24)),
                    lineWidth: isMajor ? 1.1 : 0.8
                )
            }
            
            for index in 0...horizontalCount {
                let y = CGFloat(index) * gridSize
                let path = Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                let isMajor = index.isMultiple(of: majorStep)
                context.stroke(
                    path,
                    with: .color(Color.gray.opacity(isMajor ? 0.36 : 0.24)),
                    lineWidth: isMajor ? 1.1 : 0.8
                )
            }
            
            // 绘制坐标轴
            let centerX = size.width / 2
            let centerY = size.height / 2
            
            // X轴
            let xAxis = Path { p in
                p.move(to: CGPoint(x: 0, y: centerY))
                p.addLine(to: CGPoint(x: size.width, y: centerY))
            }
            context.stroke(xAxis, with: .color(Color.gray.opacity(0.5)), lineWidth: 1)
            
            // Y轴
            let yAxis = Path { p in
                p.move(to: CGPoint(x: centerX, y: 0))
                p.addLine(to: CGPoint(x: centerX, y: size.height))
            }
            context.stroke(yAxis, with: .color(Color.gray.opacity(0.5)), lineWidth: 1)
            
        }
    }
}
