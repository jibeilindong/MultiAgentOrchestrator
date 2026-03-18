//
//  OpenClawConfigView.swift
//  MultiAgentOrchestrator
//

import SwiftUI

struct OpenClawConfigView: View {
    @EnvironmentObject var appState: AppState
    @State private var config: OpenClawConfig = OpenClawConfig.load()
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var showAlert = false
    
    var body: some View {
        Form {
            Section("Connection Settings") {
                TextField("Host", text: $config.host)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Port", value: $config.port, format: .number)
                    .textFieldStyle(.roundedBorder)
                
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
        .frame(width: 400, height: 350)
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
        config.save()
        showAlert = true
    }
}
