//
//  SettingsView.swift
//  Multi-Agent-Flow
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(LocalizedString.settings)
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            
            Divider()
            
            HStack(spacing: 0) {
                List {
                    Section {
                        Button(action: { selectedTab = 0 }) {
                            HStack {
                                Image(systemName: "globe")
                                Text(LocalizedString.language)
                                Spacer()
                                if selectedTab == 0 {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Section {
                        Button(action: { selectedTab = 1 }) {
                            HStack {
                                Image(systemName: "paintbrush")
                                Text(LocalizedString.appearance)
                                Spacer()
                                if selectedTab == 1 {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Section {
                        Button(action: { selectedTab = 2 }) {
                            HStack {
                                Image(systemName: "network")
                                Text(LocalizedString.openclawConnection)
                                Spacer()
                                if selectedTab == 2 {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Section {
                        Button(action: { selectedTab = 3 }) {
                            HStack {
                                Image(systemName: "person.2.badge.gearshape")
                                Text(LocalizedString.text("openclaw_agents_management"))
                                Spacer()
                                if selectedTab == 3 {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Section {
                        Button(action: { selectedTab = 4 }) {
                            HStack {
                                Image(systemName: "gearshape.2")
                                Text(LocalizedString.advanced)
                                Spacer()
                                if selectedTab == 4 {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Section {
                        Button(action: { selectedTab = 5 }) {
                            HStack {
                                Image(systemName: "info.circle")
                                Text(LocalizedString.about)
                                Spacer()
                                if selectedTab == 5 {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(SidebarListStyle())
                .frame(width: 220)
                
                Divider()
                
                VStack {
                    switch selectedTab {
                    case 0:
                        LanguageSettingsView()
                    case 1:
                        ThemeSettingsView()
                    case 2:
                        OpenClawConfigView()
                    case 3:
                        OpenClawAgentManagementView()
                    case 4:
                        AdvancedSettingsView()
                    case 5:
                        AboutSettingsView()
                    default:
                        LanguageSettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 860, minHeight: 620)
    }
}

struct LanguageSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizedString.language)
                .font(.title2)
            
            ForEach(AppLanguage.allCases) { language in
                Button(action: {
                    appState.localizationManager.setLanguage(language)
                }) {
                    HStack {
                        Image(systemName: appState.localizationManager.currentLanguage == language ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(appState.localizationManager.currentLanguage == language ? .accentColor : .secondary)
                        Text(language.displayName)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(appState.localizationManager.currentLanguage == language ? Color.accentColor.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
        .padding()
    }
}

struct ThemeSettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizedString.appearance)
                .font(.title2)
            
            ForEach(["system", "light", "dark"], id: \.self) { mode in
                Button(action: {
                    appearanceMode = mode
                }) {
                    HStack {
                        Image(systemName: appearanceMode == mode ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(appearanceMode == mode ? .accentColor : .secondary)
                        Text(themeName(mode))
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(appearanceMode == mode ? Color.accentColor.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func themeName(_ mode: String) -> String {
        switch mode {
        case "system": return LocalizedString.system
        case "light": return LocalizedString.light
        case "dark": return LocalizedString.dark
        default: return mode
        }
    }
}

struct AdvancedSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizedString.advanced)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle(LocalizedString.text("debug_mode"), isOn: .constant(false))
                Toggle(LocalizedString.autoSave, isOn: .constant(true))
                Toggle(LocalizedString.text("show_hints"), isOn: .constant(true))
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            
            Spacer()
        }
        .padding()
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizedString.about)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(LocalizedString.appName)
                        .font(.headline)
                    Spacer()
                }
                
                Divider()
                
                HStack {
                    Text(LocalizedString.version)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("1.0.0")
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            
            Spacer()
        }
        .padding()
    }
}
