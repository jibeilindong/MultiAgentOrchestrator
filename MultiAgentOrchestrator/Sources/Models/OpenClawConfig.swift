//
//  OpenClawConfig.swift
//  MultiAgentOrchestrator
//

import Foundation

enum OpenClawCLILogLevel: String, Codable, CaseIterable, Identifiable {
    case error
    case warning
    case info
    case debug

    var id: String { rawValue }

    var title: String {
        switch self {
        case .error: return "Error"
        case .warning: return "Warning"
        case .info: return "Info"
        case .debug: return "Debug"
        }
    }

    var cliValue: String { rawValue }
}

enum OpenClawDeploymentKind: String, Codable, CaseIterable, Identifiable {
    case local
    case remoteServer
    case container

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: return "本地"
        case .remoteServer: return "云端/远程"
        case .container: return "容器"
        }
    }
}

struct OpenClawContainerConfig: Codable, Hashable {
    var engine: String
    var containerName: String
    var workspaceMountPath: String

    init(
        engine: String = "docker",
        containerName: String = "",
        workspaceMountPath: String = "/workspace"
    ) {
        self.engine = engine
        self.containerName = containerName
        self.workspaceMountPath = workspaceMountPath
    }
}

struct OpenClawConfig: Codable {
    var deploymentKind: OpenClawDeploymentKind
    var host: String
    var port: Int
    var useSSL: Bool
    var apiKey: String
    var defaultAgent: String
    var timeout: Int
    var autoConnect: Bool
    var localBinaryPath: String
    var container: OpenClawContainerConfig
    var cliQuietMode: Bool
    var cliLogLevel: OpenClawCLILogLevel

    enum CodingKeys: String, CodingKey {
        case deploymentKind
        case host
        case port
        case useSSL
        case apiKey
        case defaultAgent
        case timeout
        case autoConnect
        case localBinaryPath
        case container
        case cliQuietMode
        case cliLogLevel
    }
    
    static var `default`: OpenClawConfig {
        OpenClawConfig(
            deploymentKind: .local,
            host: "127.0.0.1",
            port: 18789,
            useSSL: false,
            apiKey: "",
            defaultAgent: "default",
            timeout: 30,
            autoConnect: true,
            localBinaryPath: "/Users/chenrongze/.local/bin/openclaw",
            container: OpenClawContainerConfig(),
            cliQuietMode: true,
            cliLogLevel: .warning
        )
    }
    
    var baseURL: String {
        let scheme = useSSL ? "https" : "http"
        return "\(scheme)://\(host):\(port)"
    }

    var deploymentSummary: String {
        switch deploymentKind {
        case .local:
            return "Local CLI: \(localBinaryPath)"
        case .remoteServer:
            return baseURL
        case .container:
            let name = container.containerName.isEmpty ? "(未设置容器名)" : container.containerName
            return "\(container.engine): \(name)"
        }
    }

    init(
        deploymentKind: OpenClawDeploymentKind,
        host: String,
        port: Int,
        useSSL: Bool,
        apiKey: String,
        defaultAgent: String,
        timeout: Int,
        autoConnect: Bool,
        localBinaryPath: String,
        container: OpenClawContainerConfig,
        cliQuietMode: Bool,
        cliLogLevel: OpenClawCLILogLevel
    ) {
        self.deploymentKind = deploymentKind
        self.host = host
        self.port = port
        self.useSSL = useSSL
        self.apiKey = apiKey
        self.defaultAgent = defaultAgent
        self.timeout = timeout
        self.autoConnect = autoConnect
        self.localBinaryPath = localBinaryPath
        self.container = container
        self.cliQuietMode = cliQuietMode
        self.cliLogLevel = cliLogLevel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deploymentKind = try container.decodeIfPresent(OpenClawDeploymentKind.self, forKey: .deploymentKind) ?? .local
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? "127.0.0.1"
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 18789
        useSSL = try container.decodeIfPresent(Bool.self, forKey: .useSSL) ?? false
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        defaultAgent = try container.decodeIfPresent(String.self, forKey: .defaultAgent) ?? "default"
        timeout = try container.decodeIfPresent(Int.self, forKey: .timeout) ?? 30
        autoConnect = try container.decodeIfPresent(Bool.self, forKey: .autoConnect) ?? true
        localBinaryPath = try container.decodeIfPresent(String.self, forKey: .localBinaryPath) ?? "/Users/chenrongze/.local/bin/openclaw"
        self.container = try container.decodeIfPresent(OpenClawContainerConfig.self, forKey: .container) ?? OpenClawContainerConfig()
        cliQuietMode = try container.decodeIfPresent(Bool.self, forKey: .cliQuietMode) ?? true
        cliLogLevel = try container.decodeIfPresent(OpenClawCLILogLevel.self, forKey: .cliLogLevel) ?? .warning
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
