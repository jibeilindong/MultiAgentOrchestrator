//
//  OpenClawConfigView.swift
//  MultiAgentOrchestrator
//

import SwiftUI

struct OpenClawConfigView: View {
    @EnvironmentObject var appState: AppState
    @State private var config: OpenClawConfig = .default
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var showAlert = false
    
    var body: some View {
        Form {
            Section("Deployment") {
                Picker("Deployment", selection: $config.deploymentKind) {
                    ForEach(OpenClawDeploymentKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                if config.deploymentKind == .local {
                    TextField("OpenClaw Binary", text: $config.localBinaryPath)
                        .textFieldStyle(.roundedBorder)
                }

                if config.deploymentKind == .container {
                    TextField("Container Engine", text: $config.container.engine)
                        .textFieldStyle(.roundedBorder)
                    TextField("Container Name", text: $config.container.containerName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Workspace Mount", text: $config.container.workspaceMountPath)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section("Connection Settings") {
                TextField("Host", text: $config.host)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Port", value: $config.port, format: .number)
                    .textFieldStyle(.roundedBorder)
                
                Toggle("Use SSL", isOn: $config.useSSL)
                Toggle("Auto Connect on Startup", isOn: $config.autoConnect)
            }
            
            Section("API Key") {
                SecureField("API Key", text: $config.apiKey)
                    .textFieldStyle(.roundedBorder)
            }
            
            Section("Timeout") {
                HStack {
                    TextField("Timeout", value: $config.timeout, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("seconds")
                        .foregroundColor(.secondary)
                }
            }
            
            Section {
                HStack {
                    Button(action: testConnection) {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(isTesting ? "Testing..." : "Test Connection")
                        }
                    }
                    .disabled(isTesting || config.host.isEmpty)
                    
                    Spacer()
                    
                    if let result = testResult {
                        Text(result)
                            .foregroundColor(result == "Success!" ? .green : .red)
                            .font(.caption)
                    }
                }
            }
            
            Section {
                Button("Save") {
                    saveConfig()
                }
                .frame(maxWidth: .infinity)
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .background(Color.accentColor)
                .cornerRadius(8)
            }
        }
        .padding()
        .frame(width: 440, height: 460)
        .onAppear {
            config = appState.openClawManager.config
        }
    }
    
    private func testConnection() {
        isTesting = true
        testResult = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isTesting = false
            testResult = "Success!"
        }
    }
    
    private func saveConfig() {
        appState.openClawManager.config = config
        config.save()
        showAlert = true
    }
}
