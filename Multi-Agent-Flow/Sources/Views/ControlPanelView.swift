//
//  ControlPanelView.swift
//  Multi-Agent-Flow
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct ControlPanelView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        WorkbenchConversationView(messageManager: appState.messageManager)
            .environmentObject(appState)
    }
}
