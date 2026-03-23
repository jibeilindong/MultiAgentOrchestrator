//
//  OpenClawConfig.swift
//  Multi-Agent-Flow
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
        case .error: return LocalizedString.text("log_level_error")
        case .warning: return LocalizedString.text("log_level_warning")
        case .info: return LocalizedString.text("log_level_info")
        case .debug: return LocalizedString.text("log_level_debug")
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
        case .local: return LocalizedString.text("deployment_local")
        case .remoteServer: return LocalizedString.text("deployment_remote")
        case .container: return LocalizedString.text("deployment_container")
        }
    }
}

enum OpenClawRuntimeOwnership: String, Codable, CaseIterable, Identifiable {
    case appManaged
    case externalLocal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appManaged:
            return "App Managed"
        case .externalLocal:
            return "External Binary"
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
    var runtimeOwnership: OpenClawRuntimeOwnership
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
        case runtimeOwnership
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
            runtimeOwnership: .appManaged,
            host: "127.0.0.1",
            port: 18789,
            useSSL: false,
            apiKey: "",
            defaultAgent: "default",
            timeout: 30,
            autoConnect: true,
            localBinaryPath: "",
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
            switch runtimeOwnership {
            case .appManaged:
                return "App Managed Local Runtime"
            case .externalLocal:
                let resolvedPath = localBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
                return "External Local CLI: \(resolvedPath.isEmpty ? "(auto-detect)" : resolvedPath)"
            }
        case .remoteServer:
            return baseURL
        case .container:
            let name = container.containerName.isEmpty ? LocalizedString.text("container_name_not_set") : container.containerName
            return "\(container.engine): \(name)"
        }
    }

    init(
        deploymentKind: OpenClawDeploymentKind,
        runtimeOwnership: OpenClawRuntimeOwnership,
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
        self.runtimeOwnership = runtimeOwnership
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
        let decodedLocalBinaryPath = try container.decodeIfPresent(String.self, forKey: .localBinaryPath) ?? ""
        if let decodedRuntimeOwnership = try container.decodeIfPresent(OpenClawRuntimeOwnership.self, forKey: .runtimeOwnership) {
            runtimeOwnership = decodedRuntimeOwnership
        } else if deploymentKind == .local {
            runtimeOwnership = decodedLocalBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .appManaged
                : .externalLocal
        } else {
            runtimeOwnership = .appManaged
        }
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? "127.0.0.1"
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 18789
        useSSL = try container.decodeIfPresent(Bool.self, forKey: .useSSL) ?? false
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        defaultAgent = try container.decodeIfPresent(String.self, forKey: .defaultAgent) ?? "default"
        timeout = try container.decodeIfPresent(Int.self, forKey: .timeout) ?? 30
        autoConnect = try container.decodeIfPresent(Bool.self, forKey: .autoConnect) ?? true
        localBinaryPath = decodedLocalBinaryPath
        self.container = try container.decodeIfPresent(OpenClawContainerConfig.self, forKey: .container) ?? OpenClawContainerConfig()
        cliQuietMode = try container.decodeIfPresent(Bool.self, forKey: .cliQuietMode) ?? true
        cliLogLevel = try container.decodeIfPresent(OpenClawCLILogLevel.self, forKey: .cliLogLevel) ?? .warning
    }
}

extension OpenClawConfig {
    nonisolated var requiresExplicitLocalBinaryPath: Bool {
        deploymentKind == .local && runtimeOwnership == .externalLocal
    }

    nonisolated var usesManagedLocalRuntime: Bool {
        deploymentKind == .local && runtimeOwnership == .appManaged
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
