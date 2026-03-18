//
//  OpenClawConfig.swift
//  MultiAgentOrchestrator
//

import Foundation

struct OpenClawConfig: Codable {
    var host: String
    var port: Int
    var useSSL: Bool
    var apiKey: String
    var defaultAgent: String
    var timeout: Int
    var autoConnect: Bool
    
    static var `default`: OpenClawConfig {
        OpenClawConfig(
            host: "127.0.0.1",
            port: 18789,
            useSSL: false,
            apiKey: "",
            defaultAgent: "default",
            timeout: 30,
            autoConnect: true
        )
    }
    
    var baseURL: String {
        let scheme = useSSL ? "https" : "http"
        return "\(scheme)://\(host):\(port)"
    }
}

extension OpenClawConfig {
    static let storageKey = "openclaw_config"
    
    static func load() -> OpenClawConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let config = try? JSONDecoder().decode(OpenClawConfig.self, from: data) else {
            return .default
        }
        return config
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: OpenClawConfig.storageKey)
        }
    }
}
