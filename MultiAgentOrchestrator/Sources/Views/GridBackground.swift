//
//  GridBackground.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct GridBackground: View {
    let gridSize: CGFloat = 20
    
    var body: some View {
        Canvas { context, size in
            // 绘制网格
            for x in stride(from: 0, through: size.width, by: gridSize) {
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(path, with: .color(Color.gray.opacity(0.3)), lineWidth: 1)
            }
            
            for y in stride(from: 0, through: size.height, by: gridSize) {
                let path = Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(Color.gray.opacity(0.3)), lineWidth: 1)
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
            
            // 原点标记
            let origin = Path { p in
                p.addEllipse(in: CGRect(x: centerX - 2, y: centerY - 2, width: 4, height: 4))
            }
            context.fill(origin, with: .color(Color.red))
        }
    }
}
