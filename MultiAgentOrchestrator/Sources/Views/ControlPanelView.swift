//
//  ControlPanelView.swift
//  MultiAgentOrchestrator
//
//  Created by 陈荣泽 on 2026/3/18.
//

import SwiftUI

struct ControlPanelView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        MessagesView(messageManager: appState.messageManager)
            .environmentObject(appState)
    }
}
