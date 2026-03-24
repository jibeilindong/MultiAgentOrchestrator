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

    var id: String { rawValue }

    var title: String {
        "App Managed"
    }
}

enum OpenClawManagedRuntimeTerminationBehavior: String, Codable, CaseIterable, Identifiable {
    case stopWithApplication
    case keepRunning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stopWithApplication:
            return "Stop With App"
        case .keepRunning:
            return "Keep Running"
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
    var managedRuntimeTerminationBehavior: OpenClawManagedRuntimeTerminationBehavior
    var managedRuntimeAutoRestartOnCrash: Bool
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
        case managedRuntimeTerminationBehavior
        case managedRuntimeAutoRestartOnCrash
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
            managedRuntimeTerminationBehavior: .stopWithApplication,
            managedRuntimeAutoRestartOnCrash: true,
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
            return "App Managed Local Runtime"
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
        managedRuntimeTerminationBehavior: OpenClawManagedRuntimeTerminationBehavior,
        managedRuntimeAutoRestartOnCrash: Bool,
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
        self.runtimeOwnership = deploymentKind == .local ? .appManaged : runtimeOwnership
        self.managedRuntimeTerminationBehavior = managedRuntimeTerminationBehavior
        self.managedRuntimeAutoRestartOnCrash = managedRuntimeAutoRestartOnCrash
        self.host = host
        self.port = port
        self.useSSL = useSSL
        self.apiKey = apiKey
        self.defaultAgent = defaultAgent
        self.timeout = timeout
        self.autoConnect = autoConnect
        self.localBinaryPath = deploymentKind == .local
            ? ""
            : localBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.container = container
        self.cliQuietMode = cliQuietMode
        self.cliLogLevel = cliLogLevel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deploymentKind = try container.decodeIfPresent(OpenClawDeploymentKind.self, forKey: .deploymentKind) ?? .local
        let decodedLocalBinaryPath = try container.decodeIfPresent(String.self, forKey: .localBinaryPath) ?? ""
        let decodedRuntimeOwnership = OpenClawRuntimeOwnership(
            rawValue: try container.decodeIfPresent(String.self, forKey: .runtimeOwnership) ?? ""
        )
        runtimeOwnership = deploymentKind == .local ? .appManaged : (decodedRuntimeOwnership ?? .appManaged)
        managedRuntimeTerminationBehavior = try container.decodeIfPresent(
            OpenClawManagedRuntimeTerminationBehavior.self,
            forKey: .managedRuntimeTerminationBehavior
        ) ?? .stopWithApplication
        managedRuntimeAutoRestartOnCrash = try container.decodeIfPresent(
            Bool.self,
            forKey: .managedRuntimeAutoRestartOnCrash
        ) ?? true
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? "127.0.0.1"
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 18789
        useSSL = try container.decodeIfPresent(Bool.self, forKey: .useSSL) ?? false
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        defaultAgent = try container.decodeIfPresent(String.self, forKey: .defaultAgent) ?? "default"
        timeout = try container.decodeIfPresent(Int.self, forKey: .timeout) ?? 30
        autoConnect = try container.decodeIfPresent(Bool.self, forKey: .autoConnect) ?? true
        localBinaryPath = deploymentKind == .local
            ? ""
            : decodedLocalBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.container = try container.decodeIfPresent(OpenClawContainerConfig.self, forKey: .container) ?? OpenClawContainerConfig()
        cliQuietMode = try container.decodeIfPresent(Bool.self, forKey: .cliQuietMode) ?? true
        cliLogLevel = try container.decodeIfPresent(OpenClawCLILogLevel.self, forKey: .cliLogLevel) ?? .warning
    }
}

extension OpenClawConfig {
    nonisolated var requiresExplicitLocalBinaryPath: Bool {
        false
    }

    nonisolated var usesManagedLocalRuntime: Bool {
        deploymentKind == .local
    }

    nonisolated var shouldStopManagedRuntimeOnApplicationTermination: Bool {
        usesManagedLocalRuntime && managedRuntimeTerminationBehavior == .stopWithApplication
    }

    nonisolated var shouldAutoRestartManagedRuntimeOnCrash: Bool {
        usesManagedLocalRuntime && managedRuntimeAutoRestartOnCrash
    }
}

extension OpenClawConfig {
    static let storageKey = "openclaw_config"

    nonisolated var normalizedForPersistence: OpenClawConfig {
        OpenClawConfig(
            deploymentKind: deploymentKind,
            runtimeOwnership: deploymentKind == .local ? .appManaged : runtimeOwnership,
            managedRuntimeTerminationBehavior: managedRuntimeTerminationBehavior,
            managedRuntimeAutoRestartOnCrash: managedRuntimeAutoRestartOnCrash,
            host: host,
            port: port,
            useSSL: useSSL,
            apiKey: apiKey,
            defaultAgent: defaultAgent,
            timeout: timeout,
            autoConnect: autoConnect,
            localBinaryPath: deploymentKind == .local ? "" : localBinaryPath,
            container: container,
            cliQuietMode: cliQuietMode,
            cliLogLevel: cliLogLevel
        )
    }
    
    static func load() -> OpenClawConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let config = try? JSONDecoder().decode(OpenClawConfig.self, from: data) else {
            return .default
        }
        return config.normalizedForPersistence
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(normalizedForPersistence) {
            UserDefaults.standard.set(data, forKey: OpenClawConfig.storageKey)
        }
    }
}
