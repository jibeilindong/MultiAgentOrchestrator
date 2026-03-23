//
//  OpenClawManager.swift
//  Multi-Agent-Flow
//

import Foundation
import Combine
import CryptoKit

private let openClawSoulFileNames = ["SOUL.md", "soul.md"]
private let openClawSoulNestedDirectories = ["", "agent", "private"]

func openClawSoulCandidateURLs(in rootURL: URL, maxAncestorDepth: Int = 2) -> [URL] {
    var directories: [URL] = []
    var current = rootURL

    for depth in 0...max(0, maxAncestorDepth) {
        directories.append(current)
        if depth == maxAncestorDepth {
            break
        }

        let parent = current.deletingLastPathComponent()
        if parent.path == current.path || parent.path.isEmpty {
            break
        }
        current = parent
    }

    var candidates: [URL] = []
    var seen = Set<String>()

    for directory in directories {
        for nested in openClawSoulNestedDirectories {
            let baseDirectory = nested.isEmpty
                ? directory
                : directory.appendingPathComponent(nested, isDirectory: true)

            for filename in openClawSoulFileNames {
                let candidate = baseDirectory.appendingPathComponent(filename, isDirectory: false)
                if seen.insert(candidate.path).inserted {
                    candidates.append(candidate)
                }
            }
        }
    }

    return candidates
}

func existingOpenClawSoulURL(
    in rootURL: URL,
    maxAncestorDepth: Int = 2,
    fileManager: FileManager = .default
) -> URL? {
    openClawSoulCandidateURLs(in: rootURL, maxAncestorDepth: maxAncestorDepth)
        .first { fileManager.fileExists(atPath: $0.path) }
}

func preferredOpenClawSoulURL(
    in rootURL: URL,
    maxAncestorDepth: Int = 2,
    fileManager: FileManager = .default
) -> URL {
    existingOpenClawSoulURL(in: rootURL, maxAncestorDepth: maxAncestorDepth, fileManager: fileManager)
        ?? openClawSoulCandidateURLs(in: rootURL, maxAncestorDepth: maxAncestorDepth).first
        ?? rootURL.appendingPathComponent("SOUL.md", isDirectory: false)
}

class OpenClawManager: ObservableObject {
    static let shared = OpenClawManager()
    private let fileManager: FileManager
    private let host: OpenClawHost
    private let managedRuntimeSupervisor: OpenClawManagedRuntimeSupervisor
    private let notificationCenter: NotificationCenter
    private let gatewayClient = OpenClawGatewayClient()
    private var gatewayDisconnectObserver: NSObjectProtocol?
    
    @Published var isConnected: Bool = false
    @Published var agents: [String] = []
    @Published var discoveryResults: [ProjectOpenClawDetectedAgentRecord] = []
    @Published var availableChannelAccounts: [OpenClawChannelAccountRecord] = []
    @Published var runtimeConfigurations: [AgentRuntimeConfigurationRecord] = []
    @Published var activeAgents: [UUID: ActiveAgentRuntime] = [:]
    @Published var status: OpenClawStatus = .disconnected
    @Published var config: OpenClawConfig = .load()
    @Published var connectionState: OpenClawConnectionStateSnapshot = OpenClawConnectionStateSnapshot()
    @Published var projectAttachment: OpenClawProjectAttachmentSnapshot = OpenClawProjectAttachmentSnapshot()
    @Published var sessionLifecycle: OpenClawSessionLifecycleSnapshot = OpenClawSessionLifecycleSnapshot()
    @Published var lastProbeReport: OpenClawProbeReportSnapshot?
    @Published var managedRuntimeStatus: OpenClawManagedRuntimeStatusSnapshot = OpenClawManagedRuntimeStatusSnapshot(state: .unmanaged)
    private var cachedLocalWorkspaceMap: [String: String] = [:]
    private var cachedLocalWorkspaceConfigModificationDate: Date?
    private var cachedLocalGatewayConfig: OpenClawConfig?
    private var cachedLocalGatewayConfigModificationDate: Date?
    private var cachedLocalGatewayConfigFallbackKey: String?
    
    var backupDirectory: URL {
        localOpenClawRootURL().appendingPathComponent("backups", isDirectory: true)
    }

    var canRunWorkflow: Bool {
        connectionState.canRunWorkflow
    }

    var canRunConversation: Bool {
        connectionState.canRunConversation
    }

    var canAttachProject: Bool {
        connectionState.canAttachProject
    }

    var canReadSessionHistory: Bool {
        connectionState.canReadSessionHistory
    }

    var hasAttachedProjectSession: Bool {
        projectAttachment.state == .attached
    }

    var attachedProjectID: UUID? {
        projectAttachment.projectID
    }

    static func localBinaryPathCandidates(
        for config: OpenClawConfig,
        bundleResourceURL: URL? = Bundle.main.resourceURL,
        managedRuntimeRootURL: URL? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String] {
        let configured = config.localBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard config.deploymentKind == .local else {
            return configured.isEmpty ? [] : [configured]
        }

        if config.requiresExplicitLocalBinaryPath {
            return configured.isEmpty ? [] : [configured]
        }

        let managedRoot = managedRuntimeRootURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("Multi-Agent-Flow", isDirectory: true)
                .appendingPathComponent("openclaw", isDirectory: true)
                .appendingPathComponent("runtime", isDirectory: true)

        let bundleCandidates = [bundleResourceURL].compactMap { $0 }.flatMap { resourceURL in
            [
                resourceURL.appendingPathComponent("OpenClaw/bin/openclaw", isDirectory: false).path,
                resourceURL.appendingPathComponent("openclaw/bin/openclaw", isDirectory: false).path,
                resourceURL.appendingPathComponent("OpenClaw/openclaw", isDirectory: false).path,
                resourceURL.appendingPathComponent("openclaw/openclaw", isDirectory: false).path
            ]
        }
        let managedCandidates = [managedRoot].compactMap { $0 }.flatMap { rootURL in
            [
                rootURL.appendingPathComponent("bin/openclaw", isDirectory: false).path,
                rootURL.appendingPathComponent("openclaw", isDirectory: false).path
            ]
        }
        let systemCandidates = [
            homeDirectory.appendingPathComponent(".local/bin/openclaw", isDirectory: false).path,
            "/usr/local/bin/openclaw",
            "/opt/homebrew/bin/openclaw",
            "/usr/bin/openclaw"
        ]

        var seen = Set<String>()
        return (bundleCandidates + managedCandidates + systemCandidates).compactMap { candidate in
            let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return nil }
            guard seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }
    
    enum OpenClawStatus {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    struct ActiveAgentRuntime: Codable, Hashable {
        var agentID: UUID
        var name: String
        var status: String
        var lastReloadedAt: Date?
    }

    struct AgentRuntimeCommandResult {
        let terminationStatus: Int32
        let standardOutput: Data
        let standardError: Data
        let channelKey: String
        let executionCount: Int
        let createdAt: Date
        let lastUsedAt: Date

        var reusedExistingChannel: Bool {
            executionCount > 1
        }
    }

    struct ManagedAgentSkillRecord: Identifiable, Hashable {
        var id: String { name }
        var name: String
        var path: String
    }

    private struct OpenClawDiscoverySnapshotContext {
        let snapshotURL: URL
        let scopeKey: String
        let deploymentRootPath: String
    }

    private struct OpenClawDiscoveryContext {
        let deploymentKind: OpenClawDeploymentKind
        let deploymentRootPath: String?
        let inspectionRootURL: URL?
        let configURL: URL?
        let usesSnapshot: Bool
    }

    struct OpenClawGovernancePaths {
        let rootURL: URL?
        let configURL: URL?
        let approvalsURL: URL?
    }

    struct ManagedAgentRecord: Identifiable, Hashable {
        var id: String
        var projectAgentID: UUID?
        var configIndex: Int?
        var name: String
        var targetIdentifier: String
        var agentDirPath: String?
        var workspacePath: String?
        var modelIdentifier: String
        var installedSkills: [ManagedAgentSkillRecord]

        init(
            id: String,
            projectAgentID: UUID? = nil,
            configIndex: Int? = nil,
            name: String,
            targetIdentifier: String,
            agentDirPath: String? = nil,
            workspacePath: String? = nil,
            modelIdentifier: String = "",
            installedSkills: [ManagedAgentSkillRecord] = []
        ) {
            self.id = id
            self.projectAgentID = projectAgentID
            self.configIndex = configIndex
            self.name = name
            self.targetIdentifier = targetIdentifier
            self.agentDirPath = agentDirPath
            self.workspacePath = workspacePath
            self.modelIdentifier = modelIdentifier
            self.installedSkills = installedSkills
        }
    }

    private struct LocalAgentConfigEntry: Hashable {
        let configIndex: Int
        let id: String?
        let name: String?
        let workspacePath: String?
        let agentDirPath: String?
        let modelIdentifier: String?

        var candidateKeys: Set<String> {
            Set(
                [id, name]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .map { $0.lowercased() }
            )
        }
    }

    private enum LocalAgentConfigResolutionStatus {
        case missing
        case invalid
        case ambiguous
        case uniqueValid
    }

    private struct LocalAgentConfigResolution {
        let status: LocalAgentConfigResolutionStatus
        let entries: [LocalAgentConfigEntry]
        let selectedEntry: LocalAgentConfigEntry?
    }

    struct ManagedAgentBindingRecord: Hashable {
        var agentIdentifier: String
        var channelID: String
        var accountID: String

        var binding: AgentRuntimeChannelBinding {
            AgentRuntimeChannelBinding(channelID: channelID, accountID: accountID)
        }
    }

    struct WorkspaceIsolationConflict: Hashable {
        let normalizedPath: String
        let displayPath: String
        let agentNames: [String]
        let agentIdentifiers: [String]
    }

    struct RuntimeIsolationAssessment {
        let workflowAgents: [Agent]
        let missingWorkspaceAgents: [Agent]
        let workspaceConflicts: [WorkspaceIsolationConflict]
        let remoteMultiAgentBlocked: Bool
        let runtimeSecurityMessages: [String]

        var advisoryMessages: [String] {
            var messages: [String] = []

            if !missingWorkspaceAgents.isEmpty {
                let names = missingWorkspaceAgents
                    .map(\.name)
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                    .joined(separator: ", ")
                messages.append("未解析到以下 agent 的独立 workspace：\(names)")
            }

            if !workspaceConflicts.isEmpty {
                let summaries = workspaceConflicts.map { conflict in
                    "\(conflict.agentNames.joined(separator: " / ")) -> \(conflict.displayPath)"
                }
                messages.append("检测到 agent workspace 冲突：\(summaries.joined(separator: "；"))")
            }

            if remoteMultiAgentBlocked {
                messages.append("remoteServer 模式当前无法对多 agent 工作流强制执行运行时隔离，请切换到 local/container，或将当前工作流收敛为单 agent 执行。")
            }

            messages.append(contentsOf: runtimeSecurityMessages)

            return messages
        }

        var blockingMessages: [String] {
            []
        }
    }

    private struct AgentSandboxSecurityInspection {
        let agentIdentifier: String
        let sandboxMode: String
        let sessionIsSandboxed: Bool
        let allowedTools: Set<String>
        let elevatedAllowedByConfig: Bool
        let elevatedAlwaysAllowedByConfig: Bool
    }

    internal struct ExecApprovalSnapshot {
        let hasCustomEntries: Bool
    }

    struct ClawHubSkillRecord: Identifiable, Hashable {
        var id: String { slug }
        var slug: String
        var summary: String
    }

    private struct SessionContext {
        let projectID: UUID
        let rootURL: URL
        let backupURL: URL
        let mirrorURL: URL
        let importedAgentsURL: URL
        let deployment: SessionDeploymentDescriptor
    }

    private struct SessionDeploymentDescriptor {
        let config: OpenClawConfig
        let scopeKey: String
        let localRootURL: URL?
        let deploymentRootPath: String?

        var deploymentKind: OpenClawDeploymentKind {
            config.deploymentKind
        }

        var supportsRuntimeSync: Bool {
            deploymentKind != .remoteServer
        }
    }

    private struct MirrorStageResult {
        var updatedAgentCount: Int = 0
        var unresolvedAgentNames: [String] = []
        var cleanedEntryNames: [String] = []
    }

    private struct PreparedMirrorAgentStage {
        let agentName: String
        let temporaryRootURL: URL
        let stagedAgentRootURL: URL
        let relativeAgentRootPath: String
    }

    private enum ManagedWorkspaceStageOutcome {
        case noManagedWorkspace
        case unchanged
        case changed
    }

    private static let managedSessionMirrorTopLevelEntries: Set<String> = ["agents"]

    private enum LocalRuntimeRegistrationStage: String {
        case workspaceResolution
        case canonicalConfig
        case runtimeRecognition
        case cliRegistrationFallback
        case bootstrap
        case activation
    }

    private enum LocalRuntimeRegistrationStageStatus {
        case succeeded
        case failed
        case skipped
    }

    private struct LocalRuntimeRegistrationStageReport {
        let stage: LocalRuntimeRegistrationStage
        let status: LocalRuntimeRegistrationStageStatus
        let changed: Bool
        let detail: String?
    }

    private struct LocalRuntimeAgentRegistrationReport {
        let agentName: String
        let identifier: String
        let success: Bool
        let message: String
        let bootstrapPathRequired: Bool
        let workspaceRequirement: LocalRuntimeWorkspaceRequirement?
        let stageReports: [LocalRuntimeRegistrationStageReport]

        var changed: Bool {
            stageReports.contains(where: \.changed)
        }

        var usedCLIRegistrationFallback: Bool {
            stageReports.contains {
                $0.stage == .cliRegistrationFallback && $0.status == .succeeded && $0.changed
            }
        }

        var provisionedByCanonicalConfig: Bool {
            stageReports.contains {
                $0.stage == .canonicalConfig && $0.status == .succeeded && $0.changed
            }
        }

        var activationChanged: Bool {
            stageReports.contains {
                $0.stage == .activation && $0.status == .succeeded && $0.changed
            }
        }
    }

    private struct LocalRuntimeRegistrationResult {
        var changedAgentNames: [String] = []
        var warnings: [String] = []
        var failureMessages: [String] = []
        var bootstrapPathRequiredAgentNames: [String] = []
        var workspacePathRequirements: [LocalRuntimeWorkspaceRequirement] = []
        var agentReports: [LocalRuntimeAgentRegistrationReport] = []

        var workspacePathRequiredAgentNames: [String] {
            Array(Set(workspacePathRequirements.map(\.agentName))).sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
        }

        var cliFallbackAgentNames: [String] {
            Array(Set(agentReports.filter(\.usedCLIRegistrationFallback).map(\.agentName))).sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
        }

        var canonicalProvisionedAgentNames: [String] {
            Array(Set(agentReports.filter(\.provisionedByCanonicalConfig).map(\.agentName))).sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
        }

        var activationUpdatedAgentNames: [String] {
            Array(Set(agentReports.filter(\.activationChanged).map(\.agentName))).sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
        }

        var success: Bool {
            failureMessages.isEmpty
        }

        var changed: Bool {
            !changedAgentNames.isEmpty
        }
    }

    struct LocalRuntimeWorkspaceRequirement: Identifiable, Hashable {
        var id: String {
            nodeID.uuidString
        }

        let agentID: UUID
        let workflowID: UUID
        let nodeID: UUID
        let agentName: String
        let targetIdentifier: String
        let diagnosticMessage: String?

        init(
            agentID: UUID,
            workflowID: UUID,
            nodeID: UUID,
            agentName: String,
            targetIdentifier: String,
            diagnosticMessage: String? = nil
        ) {
            self.agentID = agentID
            self.workflowID = workflowID
            self.nodeID = nodeID
            self.agentName = agentName
            self.targetIdentifier = targetIdentifier
            self.diagnosticMessage = diagnosticMessage
        }
    }

    private struct LocalRuntimeRegistrationSpec {
        let agent: Agent
        let workflowID: UUID
        let nodeID: UUID
        let targetIdentifier: String
    }

    private struct LocalRuntimeActivationDonor {
        let identifier: String
        let modelIdentifier: String?
        let bindings: [AgentRuntimeChannelBinding]
        let sourceDescription: String
    }

    private struct LocalRuntimeActivationPlan {
        let modelIdentifier: String?
        let desiredBindings: [AgentRuntimeChannelBinding]?
        let sourceDescription: String?
    }

    private struct LocalRuntimeBindingsBatchPlanItem {
        let identifier: String
        let currentBindings: [ManagedAgentBindingRecord]
        let desiredBindings: [AgentRuntimeChannelBinding]
        let sourceDescription: String?
    }

    private enum LocalRuntimeBindingsApplicationState {
        case pending
        case applied(message: String?)
        case failed(message: String)
    }

    private struct LocalRuntimeBindingsBatchExecutionResult {
        var statesByIdentifier: [String: LocalRuntimeBindingsApplicationState] = [:]
    }

    private struct LocalRuntimePreparedActivation {
        let stateIndex: Int
        let runtimeRecord: ManagedAgentRecord
        let activationPlan: LocalRuntimeActivationPlan
        let currentBindings: [ManagedAgentBindingRecord]
    }

    private struct LocalRuntimeActivationBatchProcessingResult {
        var batchStates: [LocalRuntimeBatchRegistrationState]
        var warnings: [String] = []
    }

    private struct LocalRuntimeConfigBatchVerification {
        let identifier: String
        let expectedWorkspacePath: String?
        let expectedAgentDirPath: String?
    }

    private struct LocalRuntimeConfigBatchMutationResult {
        let success: Bool
        let message: String
        let changed: Bool
    }

    private struct LocalRuntimeConfigBatchContext {
        let configURL: URL
        var root: [String: Any]
        var list: [[String: Any]]
        let originalFileData: Data?
        var verifications: [LocalRuntimeConfigBatchVerification] = []

        var hasPendingChanges: Bool {
            !verifications.isEmpty
        }
    }

    private struct LocalRuntimeBatchRegistrationState {
        let agent: Agent
        let identifier: String
        let runtimeAgentDirectory: URL
        let runtimeWorkspaceURL: URL
        let initialRuntimeRecord: ManagedAgentRecord?
        let allowSeedFromOtherAgents: Bool
        let workspaceRequirement: LocalRuntimeWorkspaceRequirement?
        var stageReports: [LocalRuntimeRegistrationStageReport]
        var bootstrapPathRequired: Bool
    }

    enum ActiveSessionProjectSyncDeploymentStatus: String {
        case appliedToRuntime
        case skippedNoPendingChanges
        case deferredNoActiveSession
        case blockedStageIncomplete
        case unsupportedRemote
        case failed
    }

    struct ActiveSessionProjectSyncResult {
        let updatedAgentCount: Int
        let unresolvedAgentNames: [String]
        let deploymentStatus: ActiveSessionProjectSyncDeploymentStatus
        let message: String
        let errorMessage: String?
        let runtimeWarnings: [String]
        let bootstrapPathRequiredAgentNames: [String]
        let workspacePathRequirements: [LocalRuntimeWorkspaceRequirement]

        var workspacePathRequiredAgentNames: [String] {
            Array(Set(workspacePathRequirements.map(\.agentName))).sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
        }

        init(
            updatedAgentCount: Int,
            unresolvedAgentNames: [String],
            deploymentStatus: ActiveSessionProjectSyncDeploymentStatus,
            message: String,
            errorMessage: String?,
            runtimeWarnings: [String] = [],
            bootstrapPathRequiredAgentNames: [String] = [],
            workspacePathRequirements: [LocalRuntimeWorkspaceRequirement] = []
        ) {
            self.updatedAgentCount = updatedAgentCount
            self.unresolvedAgentNames = unresolvedAgentNames
            self.deploymentStatus = deploymentStatus
            self.message = message
            self.errorMessage = errorMessage
            self.runtimeWarnings = runtimeWarnings
            self.bootstrapPathRequiredAgentNames = bootstrapPathRequiredAgentNames
            self.workspacePathRequirements = workspacePathRequirements
        }

        var didCompleteRuntimeWrite: Bool {
            deploymentStatus == .appliedToRuntime || deploymentStatus == .skippedNoPendingChanges
        }
    }

    enum SoulReconcileStatus: String, Hashable {
        case overwritten
        case keptLocal
        case unchanged
        case conflict
        case missingSource
    }

    struct SoulReconcileAgentReport: Hashable {
        let agentID: UUID
        let agentName: String
        let status: SoulReconcileStatus
        let sourcePath: String?
        let message: String
    }

    struct SoulReconcileReport: Hashable {
        let projectID: UUID
        let agentReports: [SoulReconcileAgentReport]

        var overwrittenCount: Int {
            agentReports.filter { $0.status == .overwritten }.count
        }

        var keptLocalCount: Int {
            agentReports.filter { $0.status == .keptLocal }.count
        }

        var unchangedCount: Int {
            agentReports.filter { $0.status == .unchanged }.count
        }

        var conflictCount: Int {
            agentReports.filter { $0.status == .conflict }.count
        }

        var missingSourceCount: Int {
            agentReports.filter { $0.status == .missingSource }.count
        }

        var summaryText: String? {
            guard !agentReports.isEmpty else { return nil }

            var parts: [String] = []
            if overwrittenCount > 0 { parts.append("自动更新 \(overwrittenCount) 个") }
            if unchangedCount > 0 { parts.append("确认一致 \(unchangedCount) 个") }
            if keptLocalCount > 0 { parts.append("保留本地 \(keptLocalCount) 个") }
            if conflictCount > 0 { parts.append("待人工处理冲突 \(conflictCount) 个") }
            if missingSourceCount > 0 { parts.append("未找到源文件 \(missingSourceCount) 个") }
            guard !parts.isEmpty else { return nil }
            return "SOUL 同步结果：\(parts.joined(separator: "；"))"
        }
    }

    private struct SoulReconcileAgentUpdate {
        let agentID: UUID
        let soulMD: String?
        let soulSourcePath: String?
        let lastImportedSoulHash: String?
        let lastImportedSoulPath: String?
        let lastImportedAt: Date?
    }

    private struct PendingSoulReconcileResult {
        let projectID: UUID
        let updates: [SoulReconcileAgentUpdate]
        let report: SoulReconcileReport
    }

    private struct ConnectedSessionPreparationResult {
        let stageNote: String?
        let reconcileNote: String?
    }

    private enum SoulMirrorStagePolicy {
        case projectContent
        case backupContent
    }

    private final class AgentRuntimeChannel {
        private let key: String
        private let commandPlan: OpenClawHostCommandPlan
        private let stateLock = NSLock()
        private var executionCount = 0
        private let createdAt = Date()
        private var lastUsedAt = Date()

        init(key: String, commandPlan: OpenClawHostCommandPlan) {
            self.key = key
            self.commandPlan = commandPlan
        }

        func execute(
            arguments: [String],
            standardInput: FileHandle? = nil,
            onStdoutChunk: ((String) -> Void)? = nil
        ) throws -> AgentRuntimeCommandResult {
            let result = try OpenClawHost.executeProcessAndCaptureOutput(
                executableURL: commandPlan.executableURL,
                arguments: commandPlan.arguments + arguments,
                standardInput: standardInput,
                onStdoutChunk: onStdoutChunk.map { callback in
                    { data in
                        callback(String(decoding: data, as: UTF8.self))
                    }
                }
            )

            let snapshot = markExecutionFinished()
            return AgentRuntimeCommandResult(
                terminationStatus: result.terminationStatus,
                standardOutput: result.standardOutput,
                standardError: result.standardError,
                channelKey: key,
                executionCount: snapshot.executionCount,
                createdAt: snapshot.createdAt,
                lastUsedAt: snapshot.lastUsedAt
            )
        }

        private func markExecutionFinished() -> (executionCount: Int, createdAt: Date, lastUsedAt: Date) {
            stateLock.lock()
            executionCount += 1
            lastUsedAt = Date()
            let snapshot = (executionCount: executionCount, createdAt: createdAt, lastUsedAt: lastUsedAt)
            stateLock.unlock()
            return snapshot
        }
    }

    private var sessionContext: SessionContext?
    private var pendingSoulReconcileResult: PendingSoulReconcileResult?
    private var discoverySnapshotContext: OpenClawDiscoverySnapshotContext?
    private var pluginStageCleanupPerformed = false
    private let pluginStageCleanupLock = NSLock()
    private var agentRuntimeChannels: [String: AgentRuntimeChannel] = [:]
    private let agentRuntimeChannelLock = NSLock()
    private var sessionDeploymentModified = false
    private var sessionDeploymentBackupPrepared = false
    private var userProvidedLocalBootstrapDirectory: URL?
    private var userProvidedLocalWorkspaceDirectoriesByNodeID: [UUID: URL] = [:]
    private var userProvidedLocalWorkspaceDirectoriesByAgentID: [UUID: URL] = [:]

    private var discoverySnapshotURL: URL? {
        discoverySnapshotContext?.snapshotURL
    }

    init(
        notificationCenter: NotificationCenter = .default,
        fileManager: FileManager = .default,
        host: OpenClawHost? = nil,
        managedRuntimeSupervisor: OpenClawManagedRuntimeSupervisor? = nil
    ) {
        self.fileManager = fileManager
        self.host = host ?? OpenClawHost(fileManager: fileManager)
        self.managedRuntimeSupervisor = managedRuntimeSupervisor
            ?? OpenClawManagedRuntimeSupervisor(fileManager: fileManager, host: self.host)
        self.notificationCenter = notificationCenter
        // 创建备份目录
        try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        connectionState = OpenClawConnectionStateSnapshot(
            phase: .idle,
            deploymentKind: config.deploymentKind
        )
        self.managedRuntimeStatus = self.managedRuntimeSupervisor.refreshStatus(using: config)
        gatewayDisconnectObserver = notificationCenter.addObserver(
            forName: OpenClawGatewayClient.disconnectNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let rawMessage = notification.userInfo?[OpenClawGatewayClient.disconnectMessageUserInfoKey] as? String
            let message = rawMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.handleUnexpectedGatewayDisconnect(message: message)
        }
    }

    deinit {
        if let gatewayDisconnectObserver {
            notificationCenter.removeObserver(gatewayDisconnectObserver)
        }
    }
    
    // 连接OpenClaw - 使用配置
    func connect(completion: ((Bool, String) -> Void)? = nil) {
        connect(for: nil, completion: completion)
    }

    func connect(for projectID: UUID? = nil, completion: ((Bool, String) -> Void)? = nil) {
        connect(for: projectID, project: nil, completion: completion)
    }

    func connect(for project: MAProject, completion: ((Bool, String) -> Void)? = nil) {
        connect(for: project.id, project: project, completion: completion)
    }

    private func connect(
        for projectID: UUID? = nil,
        project: MAProject? = nil,
        completion: ((Bool, String) -> Void)? = nil
    ) {
        status = .connecting
        config.save()
        pendingSoulReconcileResult = nil
        updateConnectionState(
            phase: .discovering,
            deploymentKind: config.deploymentKind,
            capabilities: inferredCapabilities(for: config, success: false, message: "", agentNames: []),
            health: OpenClawConnectionHealthSnapshot(lastMessage: "正在探测 OpenClaw 连接...")
        )

        let cleanupResult = cleanupStalePluginInstallStageArtifactsIfNeeded(using: config)
        let cleanupNote: String? = cleanupResult.success ? nil : cleanupResult.message
        let resolvedConfig = config

        let proceedWithConnectionConfirmation = {
            self.confirmConnection(using: resolvedConfig) { [weak self] success, message in
                guard let self else { return }
                guard success else {
                    self.pendingSoulReconcileResult = nil
                    completion?(false, self.connectionCompletionMessage(baseMessage: message, cleanupNote: cleanupNote))
                    return
                }

                completion?(
                    true,
                    self.connectionCompletionMessage(
                        baseMessage: message,
                        cleanupNote: cleanupNote
                    )
                )
            }
        }

        guard resolvedConfig.usesManagedLocalRuntime else {
            proceedWithConnectionConfirmation()
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let runtimeStatus = try self.managedRuntimeSupervisor.ensureRunning(using: resolvedConfig)
                DispatchQueue.main.async {
                    self.managedRuntimeStatus = runtimeStatus
                    proceedWithConnectionConfirmation()
                }
            } catch {
                let failureMessage = "启动托管 OpenClaw Runtime 失败：\(error.localizedDescription)"
                let runtimeStatus = self.managedRuntimeSupervisor.markGatewayDisconnect(message: failureMessage)
                DispatchQueue.main.async {
                    self.managedRuntimeStatus = runtimeStatus
                    self.pendingSoulReconcileResult = nil
                    self.failConnectionPreparation(using: resolvedConfig, message: failureMessage)
                    completion?(
                        false,
                        self.connectionCompletionMessage(
                            baseMessage: failureMessage,
                            cleanupNote: cleanupNote
                        )
                    )
                }
            }
        }
    }

    private func prepareConnectedSession(
        for projectID: UUID,
        project: MAProject?
    ) throws -> ConnectedSessionPreparationResult {
        try beginSession(for: projectID)
        try ensureSessionDeploymentBackup()

        guard let project else {
            return ConnectedSessionPreparationResult(stageNote: nil, reconcileNote: nil)
        }

        let reconciledProject = reconcileProjectAgentsFromSessionBackup(project)
        pendingSoulReconcileResult = PendingSoulReconcileResult(
            projectID: project.id,
            updates: reconciledProject.updates,
            report: reconciledProject.report
        )

        let stageResult = stageProjectAgentsIntoMirror(
            reconciledProject.project,
            stagePolicies: reconciledProject.stagePolicies
        )
        if stageResult.updatedAgentCount > 0 {
            markSessionPendingSync()
        } else {
            ensureSessionPrepared()
        }

        return ConnectedSessionPreparationResult(
            stageNote: stagedMirrorPreparationMessage(from: stageResult),
            reconcileNote: reconciledProject.report.summaryText
        )
    }

    private func failConnectionPreparation(using config: OpenClawConfig, message: String) {
        isConnected = false
        activeAgents.removeAll()
        resetAgentRuntimeChannels()
        resetGatewayConnection()
        status = .error(message)

        var health = connectionState.health
        health.lastHeartbeatAt = Date()
        health.degradationReason = message
        health.lastMessage = message
        updateConnectionState(
            phase: .failed,
            deploymentKind: config.deploymentKind,
            capabilities: connectionState.capabilities,
            health: health
        )
    }

    private func connectionCompletionMessage(
        baseMessage: String,
        stageNote: String? = nil,
        reconcileNote: String? = nil,
        cleanupNote: String? = nil
    ) -> String {
        var extraNotes: [String] = []
        if let stageNote, !stageNote.isEmpty {
            extraNotes.append(stageNote)
        }
        if let reconcileNote, !reconcileNote.isEmpty {
            extraNotes.append(reconcileNote)
        }
        if let cleanupNote, !cleanupNote.isEmpty {
            extraNotes.append(cleanupNote)
        }

        guard !extraNotes.isEmpty else {
            return baseMessage
        }

        return "\(baseMessage)（附加信息：\(extraNotes.joined(separator: "；"))）"
    }

    func attachProjectSession(
        for project: MAProject,
        completion: @escaping (Bool, String) -> Void
    ) {
        guard config.deploymentKind != .remoteServer else {
            completion(false, "远程网关模式当前不支持项目附着。")
            return
        }

        guard canAttachProject else {
            let detail = connectionState.health.lastMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = detail?.isEmpty == false
                ? "当前 OpenClaw 运行态不具备项目附着能力：\(detail!)"
                : "当前 OpenClaw 运行态不具备项目附着能力。"
            completion(false, message)
            return
        }

        let previousSessionLifecycle = sessionLifecycle
        let previousProjectAttachment = projectAttachment

        _Concurrency.Task { [self] in
            do {
                let message = try await MainActor.run { () throws -> String in
                    if let sessionContext = self.sessionContext,
                       sessionContext.projectID != project.id {
                        self.endSession(restoreOriginalState: true)
                    }

                    let preparationResult = try self.prepareConnectedSession(
                        for: project.id,
                        project: project
                    )

                    return self.connectionCompletionMessage(
                        baseMessage: "当前项目已附着到 OpenClaw 运行时。",
                        stageNote: preparationResult.stageNote,
                        reconcileNote: preparationResult.reconcileNote
                    )
                }
                await MainActor.run {
                    completion(true, message)
                }
            } catch {
                await MainActor.run {
                    if self.sessionContext?.projectID == project.id {
                        self.endSession(restoreOriginalState: true)
                    }
                    self.pendingSoulReconcileResult = nil
                    self.projectAttachment = previousProjectAttachment
                    self.sessionLifecycle = previousSessionLifecycle

                    completion(false, "附着当前项目失败：\(error.localizedDescription)")
                }
            }
        }
    }

    func cleanupStalePluginInstallStageArtifactsIfNeeded(
        using config: OpenClawConfig? = nil
    ) -> (success: Bool, message: String) {
        let resolvedConfig = config ?? self.config

        pluginStageCleanupLock.lock()
        let alreadyCleaned = pluginStageCleanupPerformed
        pluginStageCleanupLock.unlock()
        if alreadyCleaned {
            return (true, "")
        }

        switch resolvedConfig.deploymentKind {
        case .remoteServer:
            return (true, "")
        case .local:
            do {
                let extensionsDirectory = localOpenClawRootURL(using: resolvedConfig).appendingPathComponent("extensions", isDirectory: true)
                guard FileManager.default.fileExists(atPath: extensionsDirectory.path) else {
                    pluginStageCleanupLock.lock()
                    pluginStageCleanupPerformed = true
                    pluginStageCleanupLock.unlock()
                    return (true, "")
                }

                let contents = try FileManager.default.contentsOfDirectory(
                    at: extensionsDirectory,
                    includingPropertiesForKeys: [.isDirectoryKey]
                )
                let stagedDirectories = contents.filter { url in
                    guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return false }
                    return url.lastPathComponent.hasPrefix(".openclaw-install-stage-")
                }

                for directory in stagedDirectories {
                    try? FileManager.default.removeItem(at: directory)
                }

                pluginStageCleanupLock.lock()
                pluginStageCleanupPerformed = true
                pluginStageCleanupLock.unlock()

                if stagedDirectories.isEmpty {
                    return (true, "")
                }
                return (true, "已清理 \(stagedDirectories.count) 个 OpenClaw 插件安装残留目录。")
            } catch {
                return (false, "清理 OpenClaw 插件安装残留目录失败：\(error.localizedDescription)")
            }
        case .container:
            do {
                guard let containerName = containerName(for: resolvedConfig),
                      let deploymentRootPath = containerOpenClawRootPath(for: resolvedConfig) else {
                    return (false, "容器模式下无法定位 OpenClaw 根目录，未完成插件残留清理。")
                }

                let cleanupCommand = """
                shopt -s nullglob >/dev/null 2>&1 || true
                for d in \(shellQuoted(deploymentRootPath))/extensions/.openclaw-install-stage-*; do
                  [ -e "$d" ] || continue
                  rm -rf "$d"
                done
                """

                let result = try runDeploymentCommand(
                    using: resolvedConfig,
                    arguments: ["exec", containerName, "sh", "-lc", cleanupCommand]
                )

                guard result.terminationStatus == 0 else {
                    let stderr = String(data: result.standardError, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return (false, stderr.isEmpty ? "容器模式插件残留清理失败。" : stderr)
                }

                pluginStageCleanupLock.lock()
                pluginStageCleanupPerformed = true
                pluginStageCleanupLock.unlock()
                return (true, "已执行容器内 OpenClaw 插件残留清理。")
            } catch {
                return (false, "容器模式插件残留清理失败：\(error.localizedDescription)")
            }
        }
    }

    func refreshAgents(completion: @escaping ([String]) -> Void) {
        testConnection(using: config) { [weak self] success, message, agentNames in
            guard let self else { return }
            DispatchQueue.main.async {
                self.agents = success ? (self.discoveryResults.isEmpty ? agentNames : self.discoveryResults.map(\.name)) : []
                self.isConnected = success
                self.status = success ? .connected : .error(message)
                self.recordProbeResult(using: self.config, success: success, message: message, agentNames: agentNames)
                completion(self.agents)
            }
        }
    }

    func confirmConnection(using config: OpenClawConfig, completion: @escaping (Bool, String) -> Void) {
        status = .connecting
        testConnection(using: config) { [weak self] success, message, agentNames in
            guard let self else { return }
            DispatchQueue.main.async {
                self.config = config
                self.config.save()
                self.agents = success ? (self.discoveryResults.isEmpty ? agentNames : self.discoveryResults.map(\.name)) : []
                self.isConnected = success
                self.status = success ? .connected : .error(message)
                self.recordProbeResult(using: config, success: success, message: message, agentNames: agentNames)
                if config.usesManagedLocalRuntime {
                    self.managedRuntimeStatus = success
                        ? self.managedRuntimeSupervisor.markGatewayHeartbeatSucceeded(message: "托管 OpenClaw Gateway 已连通。")
                        : self.managedRuntimeSupervisor.markGatewayDisconnect(message: message)
                } else {
                    self.managedRuntimeStatus = self.managedRuntimeSupervisor.refreshStatus(using: config)
                }
                if !success {
                    self.activeAgents.removeAll()
                    self.resetAgentRuntimeChannels()
                    self.resetGatewayConnection()
                }
                completion(success, message)
            }
        }
    }

    func beginSession(for projectID: UUID) throws {
        guard config.deploymentKind != .remoteServer else { return }
        guard sessionContext == nil else { return }

        let sessionDeployment = try resolveSessionDeploymentDescriptor(using: config)

        let projectRoot = ProjectManager.shared.openClawProjectRoot(for: projectID)
        let backupURL = ProjectManager.shared.openClawBackupDirectory(for: projectID)
        let mirrorURL = ProjectManager.shared.openClawMirrorDirectory(for: projectID)
        let importedAgentsURL = ProjectManager.shared.openClawImportedAgentsDirectory(for: projectID)

        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mirrorURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: importedAgentsURL, withIntermediateDirectories: true)

        sessionDeploymentBackupPrepared = false
        switch sessionDeployment.deploymentKind {
        case .local:
            guard sessionDeployment.localRootURL != nil else {
                throw NSError(domain: "OpenClawManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法解析本地 OpenClaw 路径"])
            }
            try removeDirectoryContents(at: backupURL)
        case .container:
            guard let deploymentRootPath = sessionDeployment.deploymentRootPath else {
                throw NSError(domain: "OpenClawManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法解析容器内 OpenClaw 路径"])
            }

            _ = try copyDeploymentContentsToLocal(
                backupURL,
                deploymentRootPath: deploymentRootPath,
                using: sessionDeployment.config
            )
            sessionDeploymentBackupPrepared = true
        case .remoteServer:
            break
        }

        sessionDeploymentModified = false
        ensureSessionPrepared()
        markProjectAttached(projectID: projectID)

        sessionContext = SessionContext(
            projectID: projectID,
            rootURL: projectRoot,
            backupURL: backupURL,
            mirrorURL: mirrorURL,
            importedAgentsURL: importedAgentsURL,
            deployment: sessionDeployment
        )
    }

    func endSession(restoreOriginalState: Bool = true) {
        guard let context = sessionContext else { return }

        do {
            try FileManager.default.createDirectory(at: context.mirrorURL, withIntermediateDirectories: true)
            switch context.deployment.deploymentKind {
            case .local:
                guard let openClawRoot = context.deployment.localRootURL else {
                    throw NSError(domain: "OpenClawManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法解析本地 OpenClaw 路径"])
                }
                if restoreOriginalState && sessionDeploymentModified && sessionDeploymentBackupPrepared {
                    _ = try replaceDirectoryContents(of: openClawRoot, withContentsOf: context.backupURL)
                }
            case .container:
                guard let deploymentRootPath = context.deployment.deploymentRootPath else {
                    throw NSError(domain: "OpenClawManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法解析容器内 OpenClaw 路径"])
                }

                if restoreOriginalState && sessionDeploymentModified && sessionDeploymentBackupPrepared {
                    try copyLocalContentsToDeployment(
                        context.backupURL,
                        deploymentRootPath: deploymentRootPath,
                        using: context.deployment.config
                    )
                }
            case .remoteServer:
                break
            }
        } catch {
            print("OpenClaw session finalization failed: \(error)")
        }

        sessionContext = nil
        sessionDeploymentModified = false
        sessionDeploymentBackupPrepared = false
        markProjectDetached()
        finalizeDetachedSessionLifecycle()
    }

    func testConnection(
        using config: OpenClawConfig,
        completion: @escaping (Bool, String, [String]) -> Void
    ) {
        switch config.deploymentKind {
        case .local:
            runLocalConnectionTest(config: config, completion: completion)
        case .container:
            runContainerConnectionTest(config: config, completion: completion)
        case .remoteServer:
            runRemoteConnectionTest(config: config, completion: completion)
        }
    }

    @discardableResult
    func refreshManagedRuntimeStatus(using config: OpenClawConfig? = nil) -> OpenClawManagedRuntimeStatusSnapshot {
        let resolvedConfig = config ?? self.config
        let snapshot = managedRuntimeSupervisor.refreshStatus(using: resolvedConfig)
        managedRuntimeStatus = snapshot
        return snapshot
    }

    func startManagedRuntime(completion: ((Bool, String) -> Void)? = nil) {
        let resolvedConfig = config
        guard resolvedConfig.usesManagedLocalRuntime else {
            let snapshot = refreshManagedRuntimeStatus(using: resolvedConfig)
            completion?(false, snapshot.lastMessage ?? "当前配置未启用托管 OpenClaw Runtime。")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let snapshot = try self.managedRuntimeSupervisor.start(using: resolvedConfig)
                DispatchQueue.main.async {
                    self.managedRuntimeStatus = snapshot
                    completion?(true, snapshot.lastMessage ?? "托管 OpenClaw Runtime 已启动。")
                }
            } catch {
                let snapshot = self.managedRuntimeSupervisor.markGatewayDisconnect(message: error.localizedDescription)
                DispatchQueue.main.async {
                    self.managedRuntimeStatus = snapshot
                    completion?(false, "启动托管 OpenClaw Runtime 失败：\(error.localizedDescription)")
                }
            }
        }
    }

    func stopManagedRuntime(completion: ((Bool, String) -> Void)? = nil) {
        let resolvedConfig = config
        guard resolvedConfig.usesManagedLocalRuntime else {
            let snapshot = refreshManagedRuntimeStatus(using: resolvedConfig)
            completion?(false, snapshot.lastMessage ?? "当前配置未启用托管 OpenClaw Runtime。")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let snapshot = try self.managedRuntimeSupervisor.stop(using: resolvedConfig)
                DispatchQueue.main.async {
                    self.managedRuntimeStatus = snapshot
                    self.resetGatewayConnection()
                    self.isConnected = false
                    self.activeAgents.removeAll()
                    self.resetAgentRuntimeChannels()
                    self.status = .disconnected
                    completion?(true, snapshot.lastMessage ?? "托管 OpenClaw Runtime 已停止。")
                }
            } catch {
                let snapshot = self.managedRuntimeSupervisor.markGatewayDisconnect(message: error.localizedDescription)
                DispatchQueue.main.async {
                    self.managedRuntimeStatus = snapshot
                    completion?(false, "停止托管 OpenClaw Runtime 失败：\(error.localizedDescription)")
                }
            }
        }
    }

    func restartManagedRuntime(completion: ((Bool, String) -> Void)? = nil) {
        let resolvedConfig = config
        guard resolvedConfig.usesManagedLocalRuntime else {
            let snapshot = refreshManagedRuntimeStatus(using: resolvedConfig)
            completion?(false, snapshot.lastMessage ?? "当前配置未启用托管 OpenClaw Runtime。")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let snapshot = try self.managedRuntimeSupervisor.restart(using: resolvedConfig)
                DispatchQueue.main.async {
                    self.managedRuntimeStatus = snapshot
                    self.resetGatewayConnection()
                    self.isConnected = false
                    self.activeAgents.removeAll()
                    self.resetAgentRuntimeChannels()
                    self.status = .disconnected
                    completion?(true, snapshot.lastMessage ?? "托管 OpenClaw Runtime 已重启。")
                }
            } catch {
                let snapshot = self.managedRuntimeSupervisor.markGatewayDisconnect(message: error.localizedDescription)
                DispatchQueue.main.async {
                    self.managedRuntimeStatus = snapshot
                    completion?(false, "重启托管 OpenClaw Runtime 失败：\(error.localizedDescription)")
                }
            }
        }
    }
    
    // 断开连接
    func disconnect() {
        if sessionContext != nil {
            endSession(restoreOriginalState: true)
        }
        pendingSoulReconcileResult = nil
        isConnected = false
        agents = []
        activeAgents.removeAll()
        discoveryResults = []
        availableChannelAccounts = []
        runtimeConfigurations = []
        clearDiscoverySnapshot()
        resetAgentRuntimeChannels()
        resetGatewayConnection()
        status = .disconnected
        managedRuntimeStatus = config.usesManagedLocalRuntime
            ? managedRuntimeSupervisor.markGatewayDisconnect(message: "应用已断开 OpenClaw 会话；托管 Runtime 保持运行。")
            : managedRuntimeSupervisor.refreshStatus(using: config)
        markProjectDetached()
        var health = connectionState.health
        health.degradationReason = nil
        health.lastMessage = "OpenClaw 已断开。"
        updateConnectionState(
            phase: .detached,
            deploymentKind: config.deploymentKind,
            capabilities: connectionState.capabilities,
            health: health
        )
    }

    func activateAgent(_ agent: Agent) {
        activeAgents[agent.id] = ActiveAgentRuntime(
            agentID: agent.id,
            name: agent.name,
            status: "active",
            lastReloadedAt: nil
        )
    }

    func terminateAgent(_ agentID: UUID) {
        activeAgents.removeValue(forKey: agentID)
    }

    func reloadAgent(_ agent: Agent) {
        var runtime = activeAgents[agent.id] ?? ActiveAgentRuntime(
            agentID: agent.id,
            name: agent.name,
            status: "active",
            lastReloadedAt: nil
        )
        runtime.name = agent.name
        runtime.status = "reloading"
        runtime.lastReloadedAt = Date()
        activeAgents[agent.id] = runtime

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            var updated = runtime
            updated.status = "active"
            self.activeAgents[agent.id] = updated
        }
    }

    func snapshot() -> ProjectOpenClawSnapshot {
        ProjectOpenClawSnapshot(
            config: config,
            isConnected: isConnected,
            availableAgents: agents,
            availableChannelAccounts: availableChannelAccounts,
            activeAgents: activeAgents.values
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map {
                    ProjectOpenClawAgentRecord(
                        id: $0.agentID,
                        name: $0.name,
                        status: $0.status,
                        lastReloadedAt: $0.lastReloadedAt
                    )
                },
            detectedAgents: discoveryResults,
            runtimeConfigurations: runtimeConfigurations,
            connectionState: connectionState,
            projectAttachment: projectAttachment,
            sessionLifecycle: sessionLifecycle,
            lastProbeReport: lastProbeReport,
            sessionBackupPath: sessionContext?.backupURL.path,
            sessionMirrorPath: sessionContext?.mirrorURL.path,
            localRuntimeBootstrapDirectory: userProvidedLocalBootstrapDirectory?.path,
            localRuntimeWorkspaceDirectoriesByNodeID: Dictionary(
                uniqueKeysWithValues: userProvidedLocalWorkspaceDirectoriesByNodeID.map { ($0.key.uuidString, $0.value.path) }
            ),
            localRuntimeWorkspaceDirectoriesByAgentID: Dictionary(
                uniqueKeysWithValues: userProvidedLocalWorkspaceDirectoriesByAgentID.map { ($0.key.uuidString, $0.value.path) }
            ),
            lastSyncedAt: Date()
        )
    }

    func restore(from snapshot: ProjectOpenClawSnapshot) {
        config = snapshot.config
        config.save()
        agents = snapshot.availableAgents
        discoveryResults = snapshot.detectedAgents
        availableChannelAccounts = snapshot.availableChannelAccounts
        runtimeConfigurations = snapshot.runtimeConfigurations
        var restoredConnectionState = snapshot.connectionState
        restoredConnectionState.deploymentKind = snapshot.config.deploymentKind
        if restoredConnectionState.phase == .ready {
            restoredConnectionState.phase = .detached
            restoredConnectionState.health.lastMessage = "已从项目快照恢复 OpenClaw 状态，尚未重新连接运行时。"
        }
        connectionState = restoredConnectionState
        projectAttachment = restoredProjectAttachment(from: snapshot.projectAttachment)
        sessionLifecycle = restoredSessionLifecycle(from: snapshot.sessionLifecycle)
        lastProbeReport = snapshot.lastProbeReport
        activeAgents = Dictionary(uniqueKeysWithValues: snapshot.activeAgents.map {
            (
                $0.id,
                ActiveAgentRuntime(
                    agentID: $0.id,
                    name: $0.name,
                    status: $0.status,
                    lastReloadedAt: $0.lastReloadedAt
                )
            )
        })
        userProvidedLocalBootstrapDirectory = firstNonEmptyPath(snapshot.localRuntimeBootstrapDirectory).map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        userProvidedLocalWorkspaceDirectoriesByNodeID = snapshot.localRuntimeWorkspaceDirectoriesByNodeID.reduce(into: [:]) {
            partial, entry in
            guard let nodeID = UUID(uuidString: entry.key),
                  let path = firstNonEmptyPath(entry.value) else {
                return
            }
            partial[nodeID] = URL(fileURLWithPath: path, isDirectory: true)
        }
        userProvidedLocalWorkspaceDirectoriesByAgentID = snapshot.localRuntimeWorkspaceDirectoriesByAgentID.reduce(into: [:]) {
            partial, entry in
            guard let agentID = UUID(uuidString: entry.key),
                  let path = firstNonEmptyPath(entry.value) else {
                return
            }
            partial[agentID] = URL(fileURLWithPath: path, isDirectory: true)
        }
        isConnected = false
        status = .disconnected
    }

    func noteProjectMirrorChangesPendingSync() {
        guard config.deploymentKind != .remoteServer else { return }
        guard projectAttachment.state == .attached else { return }
        guard sessionLifecycle.stage != .inactive else { return }
        markSessionPendingSync()
    }

    @discardableResult
    func importDetectedAgents(
        into project: inout MAProject,
        selections: [AgentImportSelection]? = nil,
        selectedRecordIDs: Set<String>? = nil
    ) -> [ProjectOpenClawDetectedAgentRecord] {
        let importRoot = ProjectManager.shared.openClawImportedAgentsDirectory(for: project.id)
        try? FileManager.default.createDirectory(at: importRoot, withIntermediateDirectories: true)

        var importedRecords: [ProjectOpenClawDetectedAgentRecord] = []
        let selectionMap = Dictionary(uniqueKeysWithValues: (selections ?? []).map { ($0.recordID, $0) })
        let selectedRecords = discoveryResults.filter { record in
            if selections != nil {
                return selectionMap[record.id] != nil
            }
            guard let selectedRecordIDs else { return true }
            return selectedRecordIDs.contains(record.id)
        }

        for record in selectedRecords {
            guard record.directoryValidated,
                  let sourceDirectoryPath = record.directoryPath else {
                continue
            }

            let sourceDirectory = URL(fileURLWithPath: sourceDirectoryPath, isDirectory: true)
            guard FileManager.default.fileExists(atPath: sourceDirectory.path) else { continue }

            let agentRoot = importRoot.appendingPathComponent(safePathComponent(record.id), isDirectory: true)
            let privateRoot = agentRoot.appendingPathComponent("private", isDirectory: true)
            let workspaceRoot = agentRoot.appendingPathComponent("workspace", isDirectory: true)
            let stateRoot = agentRoot.appendingPathComponent("state", isDirectory: true)
            try? FileManager.default.createDirectory(at: agentRoot, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: privateRoot, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: stateRoot, withIntermediateDirectories: true)

            var copiedItemCount = 0
            let sourcePrivateURL: URL? = {
                let nestedPrivateURL = sourceDirectory.appendingPathComponent("private", isDirectory: true)
                if FileManager.default.fileExists(atPath: nestedPrivateURL.path) {
                    return nestedPrivateURL
                }

                if let statePath = record.statePath {
                    let candidate = URL(fileURLWithPath: statePath, isDirectory: true)
                    if candidate.lastPathComponent == "private",
                       FileManager.default.fileExists(atPath: candidate.path) {
                        return candidate
                    }
                }

                return nil
            }()

            if let sourcePrivateURL {
                copiedItemCount += (try? replaceDirectoryContents(of: privateRoot, withContentsOf: sourcePrivateURL)) ?? 0
            }

            if let workspacePath = record.workspacePath {
                let workspaceURL = URL(fileURLWithPath: workspacePath, isDirectory: true)
                if FileManager.default.fileExists(atPath: workspaceURL.path) {
                    copiedItemCount += (try? replaceDirectoryContents(of: workspaceRoot, withContentsOf: workspaceURL)) ?? 0
                }
            }

            if let statePath = record.statePath {
                let stateURL = URL(fileURLWithPath: statePath, isDirectory: true)
                if FileManager.default.fileExists(atPath: stateURL.path),
                   stateURL.standardizedFileURL.path != sourcePrivateURL?.standardizedFileURL.path {
                    copiedItemCount += (try? replaceDirectoryContents(of: stateRoot, withContentsOf: stateURL)) ?? 0
                }
            }

            var soulText = "# \(record.name)\n"
            let resolvedSoulURL = firstNonEmptyPath(record.soulPath)
                .map { URL(fileURLWithPath: $0, isDirectory: false) }
                ?? existingOpenClawSoulURL(in: sourceDirectory, maxAncestorDepth: 0)
            if let resolvedSoulURL,
               let content = try? String(contentsOf: resolvedSoulURL, encoding: .utf8) {
                soulText = content
            }

            let managedSoulURL = preferredOpenClawSoulURL(in: workspaceRoot, maxAncestorDepth: 0)
            try? FileManager.default.createDirectory(at: managedSoulURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? soulText.write(to: managedSoulURL, atomically: true, encoding: .utf8)

            let skillsDirectory = sourceDirectory.appendingPathComponent("skills", isDirectory: true)
            var capabilities: [String] = ["basic"]
            if let skillContents = try? FileManager.default.contentsOfDirectory(at: skillsDirectory, includingPropertiesForKeys: nil) {
                capabilities = skillContents
                    .filter { ["md", "MD"].contains($0.pathExtension) }
                    .map { $0.deletingPathExtension().lastPathComponent }
                if capabilities.isEmpty {
                    capabilities = ["basic"]
                }
            }

            if FileManager.default.fileExists(atPath: skillsDirectory.path) {
                let managedSkillsDirectory = workspaceRoot.appendingPathComponent("skills", isDirectory: true)
                try? FileManager.default.createDirectory(at: managedSkillsDirectory, withIntermediateDirectories: true)
                copiedItemCount += (try? replaceDirectoryContents(of: managedSkillsDirectory, withContentsOf: skillsDirectory)) ?? 0
            }

            let resolution = AgentImportNamingService.resolveImportedAgent(
                rawName: record.name,
                soulMD: soulText,
                capabilities: capabilities
            )
            let importedAt = Date()
            let selection = selectionMap[record.id]
            let resolvedFunctionDescription = selection?.functionDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            let functionDescription = {
                if let resolvedFunctionDescription, !resolvedFunctionDescription.isEmpty {
                    return resolvedFunctionDescription
                }

                if let recommended = resolution.recommendedFunctionDescription,
                   !recommended.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return recommended
                }

                return AgentImportNamingService.fallbackFunctionDescription(from: record.name)
            }()
            let normalizedName = Agent.normalizedName(
                requestedName: functionDescription,
                existingAgents: project.agents
            )

            if project.agents.contains(where: {
                $0.name == normalizedName
                || $0.openClawDefinition.agentIdentifier == record.name
            }) {
                continue
            }

            var agent = Agent(name: normalizedName)
            if let selectedTemplateID = selection?.selectedTemplateID ?? resolution.recommendedTemplateID,
               let template = AgentTemplateLibraryStore.shared.template(withID: selectedTemplateID) {
                agent.identity = template.identity
                agent.description = template.summary
                agent.colorHex = template.colorHex
            } else {
                agent.description = "Imported from OpenClaw"
            }
            agent.soulMD = soulText
            agent.capabilities = capabilities
            agent.openClawDefinition.agentIdentifier = record.name
            agent.openClawDefinition.memoryBackupPath = privateRoot.path
            agent.openClawDefinition.soulSourcePath = managedSoulURL.path
            agent.openClawDefinition.lastImportedSoulHash = soulContentHash(soulText)
            agent.openClawDefinition.lastImportedSoulPath = managedSoulURL.path
            agent.openClawDefinition.lastImportedAt = importedAt
            agent.openClawDefinition.runtimeProfile = "imported"
            agent.updatedAt = importedAt
            project.agents.append(agent)

            var updatedRecord = record
            updatedRecord.copiedToProjectPath = agentRoot.path
            updatedRecord.workspacePath = workspaceRoot.path
            updatedRecord.statePath = stateRoot.path
            updatedRecord.soulPath = managedSoulURL.path
            updatedRecord.copiedFileCount = copiedItemCount
            updatedRecord.importedAt = importedAt
            importedRecords.append(updatedRecord)
        }

        if !importedRecords.isEmpty {
            discoveryResults = mergeImportedRecords(importedRecords)
        }

        return importedRecords
    }

    func loadManagedAgents(
        for project: MAProject?,
        using config: OpenClawConfig? = nil,
        completion: @escaping (Bool, String, [ManagedAgentRecord]) -> Void
    ) {
        let resolvedConfig = config ?? self.config

        guard let project else {
            completion(false, "请先创建或打开项目，再管理 target agents。", [])
            return
        }

        guard resolvedConfig.deploymentKind != .remoteServer else {
            completion(false, "远程网关模式下暂不支持直接修改 OpenClaw agent 配置。", [])
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var runtimeRecords: [ManagedAgentRecord] = []
            var runtimeWarning: String?

            do {
                let result = try self.runOpenClawCommand(using: resolvedConfig, arguments: ["agents", "list", "--json"])
                if result.terminationStatus == 0 {
                    runtimeRecords = self.parseManagedAgents(from: result.standardOutput, using: resolvedConfig)
                } else {
                    let fallback = String(data: result.standardError, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    runtimeWarning = fallback.isEmpty ? "读取 OpenClaw agents 失败" : fallback
                }
            } catch {
                runtimeWarning = error.localizedDescription
            }

            let records = self.mergeManagedAgents(for: project, runtimeRecords: runtimeRecords, using: resolvedConfig)
            DispatchQueue.main.async {
                if records.isEmpty, let runtimeWarning {
                    completion(false, runtimeWarning, [])
                } else {
                    let message: String
                    if let runtimeWarning, !runtimeWarning.isEmpty {
                        message = "已加载 \(records.count) 个项目 target agents，运行时信息部分不可用：\(runtimeWarning)"
                    } else {
                        message = "已加载 \(records.count) 个项目 target agents。"
                    }
                    completion(true, message, records)
                }
            }
        }
    }

    func loadAvailableModels(
        using config: OpenClawConfig? = nil,
        completion: @escaping (Bool, String, [String]) -> Void
    ) {
        let resolvedConfig = config ?? self.config

        guard resolvedConfig.deploymentKind != .remoteServer else {
            completion(false, "远程网关模式下无法读取本地模型目录。", [])
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try self.runOpenClawCommand(using: resolvedConfig, arguments: ["models", "list", "--plain"])
                guard result.terminationStatus == 0 else {
                    let fallback = String(data: result.standardError, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    throw NSError(
                        domain: "OpenClawManager",
                        code: Int(result.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "读取模型列表失败" : fallback]
                    )
                }

                let rawModels = self.parsePlainTextList(from: result.standardOutput)
                var seen = Set<String>()
                let models = rawModels.filter { seen.insert($0).inserted }
                DispatchQueue.main.async {
                    completion(true, "已加载 \(models.count) 个模型。", models)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription, [])
                }
            }
        }
    }

    func loadRuntimeConfigurationInventory(
        for project: MAProject?,
        using config: OpenClawConfig? = nil,
        completion: @escaping (Bool, String, [AgentRuntimeConfigurationRecord], [OpenClawChannelAccountRecord]) -> Void
    ) {
        let resolvedConfig = config ?? self.config

        guard let project else {
            completion(false, "请先创建或打开项目，再加载 Agent 运行时配置。", [], [])
            return
        }

        guard resolvedConfig.deploymentKind != .remoteServer else {
            completion(false, "远程网关模式下暂不支持读取 Agent channel 绑定配置。", [], [])
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var warnings: [String] = []
            let runtimeAgents: [ManagedAgentRecord]

            do {
                let result = try self.runOpenClawCommand(using: resolvedConfig, arguments: ["agents", "list", "--json"])
                guard result.terminationStatus == 0 else {
                    let fallback = String(data: result.standardError, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    throw NSError(
                        domain: "OpenClawManager",
                        code: Int(result.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "读取 OpenClaw agents 失败" : fallback]
                    )
                }
                runtimeAgents = self.parseManagedAgents(from: result.standardOutput, using: resolvedConfig)
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription, [], [])
                }
                return
            }

            let channelAccounts: [OpenClawChannelAccountRecord]
            do {
                let result = try self.runOpenClawCommand(using: resolvedConfig, arguments: ["channels", "list", "--json"])
                if result.terminationStatus == 0 {
                    channelAccounts = self.parseChannelAccounts(from: result.standardOutput)
                } else {
                    let fallback = String(data: result.standardError, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    channelAccounts = []
                    if !fallback.isEmpty {
                        warnings.append(fallback)
                    }
                }
            } catch {
                channelAccounts = []
                warnings.append(error.localizedDescription)
            }

            let bindingRecords: [ManagedAgentBindingRecord]
            do {
                let result = try self.runOpenClawCommand(using: resolvedConfig, arguments: ["agents", "bindings", "--json"])
                if result.terminationStatus == 0 {
                    bindingRecords = self.parseManagedAgentBindings(from: result.standardOutput)
                } else {
                    let fallback = String(data: result.standardError, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    bindingRecords = []
                    if !fallback.isEmpty {
                        warnings.append(fallback)
                    }
                }
            } catch {
                bindingRecords = []
                warnings.append(error.localizedDescription)
            }

            let persistedRuntimeConfigurations = Dictionary(
                uniqueKeysWithValues: project.openClaw.runtimeConfigurations.map { ($0.agentID, $0) }
            )
            let detectedRecords = project.openClaw.detectedAgents.isEmpty ? self.discoveryResults : project.openClaw.detectedAgents

            let records = project.agents.map { projectAgent -> AgentRuntimeConfigurationRecord in
                let persisted = persistedRuntimeConfigurations[projectAgent.id]
                let candidateKeys = self.managedAgentLookupKeys(for: projectAgent)
                let runtimeRecord = runtimeAgents.first { runtime in
                    candidateKeys.contains(self.normalizeAgentKey(runtime.targetIdentifier))
                        || candidateKeys.contains(self.normalizeAgentKey(runtime.name))
                }
                let runtimeBindings = bindingRecords
                    .filter { candidateKeys.contains(self.normalizeAgentKey($0.agentIdentifier)) }
                    .map(\.binding)
                let detectedRecord = detectedRecords.first { record in
                    candidateKeys.contains(self.normalizeAgentKey(record.name))
                }
                let resolvedPaths = self.resolveManagedAgentPaths(
                    for: projectAgent,
                    runtimeRecord: runtimeRecord,
                    detectedRecord: detectedRecord
                )
                let resolvedBindings = runtimeBindings.isEmpty ? (persisted?.bindings ?? []) : runtimeBindings
                let runtimeModelIdentifier = runtimeRecord?.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let persistedModelIdentifier = persisted?.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let modelIdentifier: String
                if !runtimeModelIdentifier.isEmpty {
                    modelIdentifier = runtimeModelIdentifier
                } else if !persistedModelIdentifier.isEmpty {
                    modelIdentifier = persistedModelIdentifier
                } else {
                    modelIdentifier = projectAgent.openClawDefinition.modelIdentifier
                }
                let nodeID = self.nodeBinding(for: projectAgent.id, in: project)?.nodeID ?? persisted?.nodeID

                return AgentRuntimeConfigurationRecord(
                    agentID: projectAgent.id,
                    nodeID: nodeID,
                    modelIdentifier: modelIdentifier,
                    runtimeProfile: persisted?.runtimeProfile ?? projectAgent.openClawDefinition.runtimeProfile,
                    channelEnabled: persisted?.channelEnabled ?? !resolvedBindings.isEmpty,
                    bindings: self.uniqueBindings(resolvedBindings),
                    source: (runtimeRecord != nil || !runtimeBindings.isEmpty) ? .runtimeExisting : (persisted?.source ?? .manualOverride),
                    resolvedManagedPath: resolvedPaths.workspacePath ?? persisted?.resolvedManagedPath,
                    lastResolvedAt: Date(),
                    isStale: runtimeRecord == nil,
                    updatedAt: persisted?.updatedAt ?? Date()
                )
            }

            DispatchQueue.main.async {
                self.availableChannelAccounts = channelAccounts
                self.runtimeConfigurations = records

                let warningText = warnings
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "；")
                let message: String
                if warningText.isEmpty {
                    message = "已加载 \(records.count) 个 Agent 的运行时配置。"
                } else {
                    message = "已加载 \(records.count) 个 Agent 的运行时配置，但部分 channel 信息不可用：\(warningText)"
                }
                completion(true, message, records, channelAccounts)
            }
        }
    }

    func applyRuntimeConfiguration(
        _ desiredConfiguration: AgentRuntimeConfigurationRecord,
        for agent: Agent,
        in project: MAProject,
        using config: OpenClawConfig? = nil,
        completion: @escaping (Bool, String, AgentRuntimeConfigurationRecord?) -> Void
    ) {
        let resolvedConfig = config ?? self.config

        guard resolvedConfig.deploymentKind != .remoteServer else {
            completion(false, "远程网关模式下暂不支持写回 Agent channel 绑定配置。", nil)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let identifier = self.normalizedTargetIdentifier(for: agent).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identifier.isEmpty else {
                DispatchQueue.main.async {
                    completion(false, "当前 Agent 缺少可写回的 runtime 标识。", nil)
                }
                return
            }

            do {
                let agentsResult = try self.runOpenClawCommand(using: resolvedConfig, arguments: ["agents", "list", "--json"])
                guard agentsResult.terminationStatus == 0 else {
                    let fallback = String(data: agentsResult.standardError, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    throw NSError(
                        domain: "OpenClawManager",
                        code: Int(agentsResult.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "读取 OpenClaw agents 失败" : fallback]
                    )
                }

                let runtimeAgents = self.parseManagedAgents(from: agentsResult.standardOutput, using: resolvedConfig)
                guard let runtimeAgent = runtimeAgents.first(where: {
                    self.normalizeAgentKey($0.targetIdentifier) == self.normalizeAgentKey(identifier)
                        || self.normalizeAgentKey($0.name) == self.normalizeAgentKey(identifier)
                }) else {
                    throw NSError(
                        domain: "OpenClawManager",
                        code: 1301,
                        userInfo: [NSLocalizedDescriptionKey: "尚未在 OpenClaw 运行时中找到对应 Agent：\(identifier)。请先确认镜像已同步且 agent 已注册。"]
                    )
                }

                let trimmedModel = desiredConfiguration.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedModel.isEmpty, trimmedModel != runtimeAgent.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines) {
                    try self.writeManagedAgentModel(trimmedModel, for: runtimeAgent, using: resolvedConfig)
                }

                let currentBindings = try self.loadManagedAgentBindings(
                    forAgentIdentifier: runtimeAgent.targetIdentifier,
                    using: resolvedConfig
                )
                try self.applyManagedAgentBindings(
                    forAgentIdentifier: runtimeAgent.targetIdentifier,
                    currentBindings: currentBindings,
                    desiredBindings: desiredConfiguration.channelEnabled ? desiredConfiguration.bindings : [],
                    using: resolvedConfig
                )

                let refreshedBindings = try self.loadManagedAgentBindings(
                    forAgentIdentifier: runtimeAgent.targetIdentifier,
                    using: resolvedConfig
                )
                let refreshedUniqueBindings = self.uniqueBindings(refreshedBindings.map(\.binding))
                let refreshedRecord = AgentRuntimeConfigurationRecord(
                    agentID: desiredConfiguration.agentID,
                    nodeID: desiredConfiguration.nodeID ?? self.nodeBinding(for: agent.id, in: project)?.nodeID,
                    modelIdentifier: trimmedModel.isEmpty ? runtimeAgent.modelIdentifier : trimmedModel,
                    runtimeProfile: desiredConfiguration.runtimeProfile,
                    channelEnabled: desiredConfiguration.channelEnabled && !refreshedUniqueBindings.isEmpty,
                    bindings: refreshedUniqueBindings,
                    source: .manualOverride,
                    resolvedManagedPath: desiredConfiguration.resolvedManagedPath,
                    lastResolvedAt: Date(),
                    isStale: false,
                    updatedAt: Date()
                )

                DispatchQueue.main.async {
                    if let index = self.runtimeConfigurations.firstIndex(where: { $0.agentID == refreshedRecord.agentID }) {
                        self.runtimeConfigurations[index] = refreshedRecord
                    } else {
                        self.runtimeConfigurations.append(refreshedRecord)
                    }
                    completion(true, "\(agent.name) 的运行时模型与 channel 绑定已应用到 OpenClaw。", refreshedRecord)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription, nil)
                }
            }
        }
    }

    func updateManagedAgentModel(
        _ agent: ManagedAgentRecord,
        model: String,
        using config: OpenClawConfig? = nil,
        completion: @escaping (Bool, String) -> Void
    ) {
        let resolvedConfig = config ?? self.config

        guard resolvedConfig.deploymentKind != .remoteServer else {
            completion(false, "远程网关模式下暂不支持修改单个 agent 的 model。")
            return
        }

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            completion(false, "Model 不能为空。")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.writeManagedAgentModel(trimmedModel, for: agent, using: resolvedConfig)

                DispatchQueue.main.async {
                    completion(true, "\(agent.name) 的 model 已更新为 \(trimmedModel)。建议重新连接或重启 OpenClaw 使其完全生效。")
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription)
                }
            }
        }
    }

    func syncAgentCommunicationAllowLists(
        from project: MAProject,
        using config: OpenClawConfig? = nil,
        completion: @escaping (Bool, String) -> Void
    ) {
        let resolvedConfig = config ?? self.config

        guard resolvedConfig.deploymentKind != .remoteServer else {
            completion(false, "远程网关模式下暂不支持同步 agent 通信白名单。")
            return
        }

        let desiredAllowMap = desiredAllowAgentsMap(for: project)
        guard !desiredAllowMap.isEmpty else {
            completion(true, "当前项目未配置可同步的 agent 通信白名单。")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let getResult = try self.runOpenClawCommand(
                    using: resolvedConfig,
                    arguments: ["config", "get", "agents.list"]
                )
                guard getResult.terminationStatus == 0 else {
                    let fallback = String(data: getResult.standardError, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    throw NSError(
                        domain: "OpenClawManager",
                        code: Int(getResult.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "读取 OpenClaw agents.list 失败" : fallback]
                    )
                }

                let payloadData = self.extractJSONPayload(from: getResult.standardOutput) ?? getResult.standardOutput
                guard let jsonObject = try? JSONSerialization.jsonObject(with: payloadData),
                      var runtimeAgents = jsonObject as? [[String: Any]] else {
                    throw NSError(
                        domain: "OpenClawManager",
                        code: 1010,
                        userInfo: [NSLocalizedDescriptionKey: "解析 OpenClaw agents.list 失败"]
                    )
                }

                var changedCount = 0
                for index in runtimeAgents.indices {
                    var entry = runtimeAgents[index]
                    let runtimeID = (entry["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !runtimeID.isEmpty else { continue }

                    let key = self.normalizeAgentKey(runtimeID)
                    guard let desiredAllowAgents = desiredAllowMap[key] else { continue }

                    var subagents = (entry["subagents"] as? [String: Any]) ?? [:]
                    let currentAllow = ((subagents["allowAgents"] as? [String]) ?? [])
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

                    if currentAllow == desiredAllowAgents {
                        continue
                    }

                    subagents["allowAgents"] = desiredAllowAgents
                    entry["subagents"] = subagents
                    runtimeAgents[index] = entry
                    changedCount += 1
                }

                guard changedCount > 0 else {
                    DispatchQueue.main.async {
                        completion(true, "OpenClaw 通信白名单已与当前项目一致。")
                    }
                    return
                }

                let updatedData = try JSONSerialization.data(withJSONObject: runtimeAgents, options: [])
                guard let updatedJSON = String(data: updatedData, encoding: .utf8) else {
                    throw NSError(
                        domain: "OpenClawManager",
                        code: 1011,
                        userInfo: [NSLocalizedDescriptionKey: "序列化更新后的 agents.list 失败"]
                    )
                }

                let setResult = try self.runOpenClawCommand(
                    using: resolvedConfig,
                    arguments: ["config", "set", "agents.list", updatedJSON]
                )

                guard setResult.terminationStatus == 0 else {
                    let fallback = String(data: setResult.standardError, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    throw NSError(
                        domain: "OpenClawManager",
                        code: Int(setResult.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "写回 OpenClaw agents.list 失败" : fallback]
                    )
                }

                DispatchQueue.main.async {
                    completion(true, "已同步 \(changedCount) 个 agent 的通信白名单到 OpenClaw（建议重连 OpenClaw）。")
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription)
                }
            }
        }
    }

    func installSkill(
        _ skillSlug: String,
        for agent: ManagedAgentRecord,
        using config: OpenClawConfig? = nil,
        completion: @escaping (Bool, String) -> Void
    ) {
        let resolvedConfig = config ?? self.config

        guard resolvedConfig.deploymentKind != .remoteServer else {
            completion(false, "远程网关模式下暂不支持通过本应用安装技能。")
            return
        }

        let trimmedSkill = skillSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSkill.isEmpty else {
            completion(false, "请先输入 skill slug。")
            return
        }

        guard let workspacePath = agent.workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines), !workspacePath.isEmpty else {
            completion(false, "\(agent.name) 未配置 workspace，无法安装技能。")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                if resolvedConfig.deploymentKind == .local {
                    let workspaceURL = URL(fileURLWithPath: workspacePath, isDirectory: true)
                    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
                }

                let result = try self.runClawHubCommand(
                    using: resolvedConfig,
                    arguments: ["install", trimmedSkill, "--workdir", workspacePath]
                )

                guard result.terminationStatus == 0 else {
                    let fallback = String(data: result.standardError, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    throw NSError(
                        domain: "OpenClawManager",
                        code: Int(result.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "安装技能失败" : fallback]
                    )
                }

                DispatchQueue.main.async {
                    completion(true, "\(trimmedSkill) 已安装到 \(agent.name) 的 workspace。")
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription)
                }
            }
        }
    }

    func searchClawHubSkills(
        query: String,
        using config: OpenClawConfig? = nil,
        completion: @escaping (Bool, String, [ClawHubSkillRecord]) -> Void
    ) {
        let resolvedConfig = config ?? self.config
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            completion(true, "请输入关键词后再搜索。", [])
            return
        }

        guard resolvedConfig.deploymentKind != .remoteServer else {
            completion(false, "远程网关模式下暂不支持 ClawHub 搜索。", [])
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let searchResult = try self.runClawHubCommand(
                    using: resolvedConfig,
                    arguments: ["search", trimmedQuery, "--plain"]
                )

                if searchResult.terminationStatus == 0 {
                    let parsed = self.parseClawHubSkillRecords(from: searchResult.standardOutput)
                    let filtered = self.filterSkillRecords(parsed, with: trimmedQuery)
                    DispatchQueue.main.async {
                        completion(true, "搜索到 \(filtered.count) 条技能结果。", filtered)
                    }
                    return
                }

                let listResult = try self.runClawHubCommand(using: resolvedConfig, arguments: ["list", "--plain"])
                guard listResult.terminationStatus == 0 else {
                    let fallback = String(data: searchResult.standardError, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    throw NSError(
                        domain: "OpenClawManager",
                        code: Int(searchResult.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "ClawHub 搜索失败" : fallback]
                    )
                }

                let parsed = self.parseClawHubSkillRecords(from: listResult.standardOutput)
                let filtered = self.filterSkillRecords(parsed, with: trimmedQuery)
                DispatchQueue.main.async {
                    completion(true, "搜索到 \(filtered.count) 条技能结果。", filtered)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription, [])
                }
            }
        }
    }

    func removeSkill(
        _ skillName: String,
        from agent: ManagedAgentRecord,
        using config: OpenClawConfig? = nil,
        completion: @escaping (Bool, String) -> Void
    ) {
        let resolvedConfig = config ?? self.config

        guard resolvedConfig.deploymentKind != .remoteServer else {
            completion(false, "远程网关模式下暂不支持移除技能。")
            return
        }

        let trimmedSkill = skillName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSkill.isEmpty else {
            completion(false, "技能名称不能为空。")
            return
        }

        guard let workspacePath = agent.workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines), !workspacePath.isEmpty else {
            completion(false, "\(agent.name) 未配置 workspace，无法移除技能。")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let skillsPath = URL(fileURLWithPath: workspacePath, isDirectory: true)
                    .appendingPathComponent("skills", isDirectory: true)
                    .appendingPathComponent(trimmedSkill, isDirectory: true)

                switch resolvedConfig.deploymentKind {
                case .local:
                    if FileManager.default.fileExists(atPath: skillsPath.path) {
                        try FileManager.default.removeItem(at: skillsPath)
                    }
                case .container:
                    guard let containerName = self.containerName(for: resolvedConfig) else {
                        throw NSError(domain: "OpenClawManager", code: 20, userInfo: [NSLocalizedDescriptionKey: "容器名称未配置"])
                    }
                    let result = try self.runDeploymentCommand(
                        using: resolvedConfig,
                        arguments: ["exec", containerName, "rm", "-rf", skillsPath.path]
                    )
                    guard result.terminationStatus == 0 else {
                        let fallback = String(data: result.standardError, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        throw NSError(
                            domain: "OpenClawManager",
                            code: Int(result.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "移除技能失败" : fallback]
                        )
                    }
                case .remoteServer:
                    break
                }

                DispatchQueue.main.async {
                    completion(true, "\(trimmedSkill) 已从 \(agent.name) 的 workspace 移除。")
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription)
                }
            }
        }
    }

    func updateAgentSoulMD(
        matching candidateNames: [String],
        soulMD: String,
        completion: @escaping (Bool, String) -> Void
    ) {
        let normalizedNames = Set(candidateNames.map(normalizeAgentKey).filter { !$0.isEmpty })
        guard !normalizedNames.isEmpty else {
            completion(false, "未提供可定位的 OpenClaw agent 标识。")
            return
        }

        guard let soulURL = localAgentSoulURL(matching: candidateNames) else {
            completion(false, "未找到对应的 OpenClaw SOUL.md，仅更新了项目缓存。")
            return
        }

        do {
            try FileManager.default.createDirectory(at: soulURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try soulMD.write(to: soulURL, atomically: true, encoding: .utf8)
            completion(true, "SOUL.md 已同步到 OpenClaw: \(soulURL.path)")
        } catch {
            completion(false, "同步 SOUL.md 失败: \(error.localizedDescription)")
        }
    }

    func projectMirrorSoulURL(for agent: Agent, in project: MAProject) -> URL? {
        let mirrorURL: URL
        let backupURL: URL?

        if let sessionContext, sessionContext.projectID == project.id {
            mirrorURL = sessionContext.mirrorURL
            backupURL = sessionContext.backupURL
        } else {
            mirrorURL = ProjectManager.shared.openClawMirrorDirectory(for: project.id)
            backupURL = ProjectManager.shared.openClawBackupDirectory(for: project.id)
        }

        return resolveProjectMirrorSoulURL(for: agent, in: project, mirrorURL: mirrorURL, backupURL: backupURL)
    }

    func syncProjectAgentsToActiveSession(
        _ project: MAProject,
        workflowID: UUID? = nil,
        completion: @escaping (ActiveSessionProjectSyncResult) -> Void
    ) {
        if let sessionContext,
           sessionContext.projectID == project.id {
            guard sessionContext.deployment.supportsRuntimeSync else {
                completion(
                    ActiveSessionProjectSyncResult(
                        updatedAgentCount: 0,
                        unresolvedAgentNames: [],
                        deploymentStatus: .unsupportedRemote,
                        message: "远程网关模式下暂不支持将项目镜像写回 OpenClaw 会话。",
                        errorMessage: "远程网关模式下暂不支持将项目镜像写回 OpenClaw 会话。"
                    )
                )
                return
            }
        } else if config.deploymentKind == .remoteServer {
            completion(
                ActiveSessionProjectSyncResult(
                    updatedAgentCount: 0,
                    unresolvedAgentNames: [],
                    deploymentStatus: .unsupportedRemote,
                    message: "远程网关模式下暂不支持将项目镜像写回 OpenClaw 会话。",
                    errorMessage: "远程网关模式下暂不支持将项目镜像写回 OpenClaw 会话。"
                )
            )
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let stageResult = self.stageProjectAgentsIntoMirror(project, workflowID: workflowID)
            if stageResult.updatedAgentCount > 0 {
                self.markSessionPendingSync()
            }

            if !stageResult.unresolvedAgentNames.isEmpty {
                let message = self.mirrorStageMessage(from: stageResult)
                    ?? "项目镜像准备不完整，未写回当前 OpenClaw 会话。"
                DispatchQueue.main.async {
                    completion(
                        ActiveSessionProjectSyncResult(
                            updatedAgentCount: stageResult.updatedAgentCount,
                            unresolvedAgentNames: stageResult.unresolvedAgentNames,
                            deploymentStatus: .blockedStageIncomplete,
                            message: message,
                            errorMessage: "项目镜像准备不完整，未写回当前 OpenClaw 会话。"
                        )
                    )
                }
                return
            }

            guard let sessionContext = self.sessionContext,
                  sessionContext.projectID == project.id,
                  self.isConnected else {
                let note = self.mirrorStageMessage(from: stageResult) ?? "项目镜像已更新，待连接后显式同步到 OpenClaw 会话。"
                DispatchQueue.main.async {
                    completion(
                        ActiveSessionProjectSyncResult(
                            updatedAgentCount: stageResult.updatedAgentCount,
                            unresolvedAgentNames: stageResult.unresolvedAgentNames,
                            deploymentStatus: .deferredNoActiveSession,
                            message: note,
                            errorMessage: nil
                        )
                    )
                }
                return
            }

            if stageResult.updatedAgentCount == 0,
               stageResult.cleanedEntryNames.isEmpty,
               !self.sessionLifecycle.hasPendingMirrorChanges,
               self.sessionLifecycle.stage == .synced {
                DispatchQueue.main.async {
                    completion(
                        ActiveSessionProjectSyncResult(
                            updatedAgentCount: 0,
                            unresolvedAgentNames: stageResult.unresolvedAgentNames,
                            deploymentStatus: .skippedNoPendingChanges,
                            message: "项目镜像与当前 OpenClaw 会话均已是最新，无需重复同步。",
                            errorMessage: nil
                        )
                    )
                }
                return
            }

            guard self.sessionLifecycle.hasPendingMirrorChanges else {
                let registrationResult = self.synchronizeProjectAgentsIntoLocalRuntime(
                    project,
                    workflowID: workflowID,
                    using: sessionContext.deployment.config
                )
                let baseMessage = self.mirrorStageMessage(from: stageResult) ?? "项目镜像已是最新，当前 OpenClaw 会话无需同步。"
                let registrationMessage = self.localRuntimeRegistrationSummary(from: registrationResult)
                let message = [baseMessage, registrationMessage]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                let deploymentStatus: ActiveSessionProjectSyncDeploymentStatus = registrationResult.changed
                    ? .appliedToRuntime
                    : .skippedNoPendingChanges
                let errorMessage = registrationResult.success
                    ? nil
                    : registrationResult.failureMessages.joined(separator: " ")

                DispatchQueue.main.async {
                    completion(
                        ActiveSessionProjectSyncResult(
                            updatedAgentCount: stageResult.updatedAgentCount,
                            unresolvedAgentNames: stageResult.unresolvedAgentNames,
                            deploymentStatus: registrationResult.success ? deploymentStatus : .failed,
                            message: registrationResult.success ? message : (errorMessage ?? message),
                            errorMessage: errorMessage,
                            runtimeWarnings: registrationResult.warnings,
                            bootstrapPathRequiredAgentNames: registrationResult.bootstrapPathRequiredAgentNames,
                            workspacePathRequirements: registrationResult.workspacePathRequirements
                        )
                    )
                }
                return
            }

            do {
                try self.applySessionMirrorToDeployment()
                let registrationResult = self.synchronizeProjectAgentsIntoLocalRuntime(
                    project,
                    workflowID: workflowID,
                    using: sessionContext.deployment.config
                )
                let registrationMessage = self.localRuntimeRegistrationSummary(from: registrationResult)
                let message = [
                    self.mirrorStageMessage(from: stageResult) ?? "项目镜像已同步到当前 OpenClaw 会话。",
                    registrationMessage
                ]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                let errorMessage = registrationResult.success
                    ? nil
                    : registrationResult.failureMessages.joined(separator: " ")

                DispatchQueue.main.async {
                    completion(
                        ActiveSessionProjectSyncResult(
                            updatedAgentCount: stageResult.updatedAgentCount,
                            unresolvedAgentNames: stageResult.unresolvedAgentNames,
                            deploymentStatus: registrationResult.success ? .appliedToRuntime : .failed,
                            message: registrationResult.success ? message : (errorMessage ?? message),
                            errorMessage: errorMessage,
                            runtimeWarnings: registrationResult.warnings,
                            bootstrapPathRequiredAgentNames: registrationResult.bootstrapPathRequiredAgentNames,
                            workspacePathRequirements: registrationResult.workspacePathRequirements
                        )
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    let message = "同步项目镜像到 OpenClaw 会话失败: \(error.localizedDescription)"
                    completion(
                        ActiveSessionProjectSyncResult(
                            updatedAgentCount: stageResult.updatedAgentCount,
                            unresolvedAgentNames: stageResult.unresolvedAgentNames,
                            deploymentStatus: .failed,
                            message: message,
                            errorMessage: message
                        )
                    )
                }
            }
        }
    }

    private func synchronizeProjectAgentsIntoLocalRuntime(
        _ project: MAProject,
        workflowID: UUID? = nil,
        using config: OpenClawConfig
    ) -> LocalRuntimeRegistrationResult {
        guard config.deploymentKind == .local else {
            return LocalRuntimeRegistrationResult()
        }

        var result = LocalRuntimeRegistrationResult()
        var changedNames = Set<String>()
        var expectedIdentifiers = Set<String>()
        let registrationSpecs = buildLocalRuntimeRegistrationSpecs(in: project, workflowID: workflowID)
        let registerableAgents = registrationSpecs.map(\.agent)
        let registerableAgentIDs = Set(registerableAgents.map(\.id))
        let skippedAgents = project.agents.filter { !registerableAgentIDs.contains($0.id) }
        let runtimeRecords: [ManagedAgentRecord]
        let bindingRecords: [ManagedAgentBindingRecord]

        do {
            let listResult = try runOpenClawCommand(using: config, arguments: ["agents", "list", "--json"])
            runtimeRecords = parseManagedAgents(from: listResult.standardOutput, using: config)
        } catch {
            result.failureMessages.append("读取本地 OpenClaw agent 列表失败：\(error.localizedDescription)")
            return result
        }

        do {
            let bindingsResult = try runOpenClawCommand(using: config, arguments: ["agents", "bindings", "--json"])
            if bindingsResult.terminationStatus == 0 {
                bindingRecords = parseManagedAgentBindings(from: bindingsResult.standardOutput)
            } else {
                let fallback = String(data: bindingsResult.standardError, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                bindingRecords = []
                if !fallback.isEmpty {
                    result.warnings.append("读取本地 OpenClaw agent bindings 失败：\(fallback)")
                }
            }
        } catch {
            bindingRecords = []
            result.warnings.append("读取本地 OpenClaw agent bindings 失败：\(error.localizedDescription)")
        }

        let batchContextResult = loadLocalRuntimeConfigBatchContext(using: config)
        guard let configBatchContextValue = batchContextResult.context else {
            result.failureMessages.append(batchContextResult.message ?? "读取本地 OpenClaw 配置失败。")
            return result
        }
        var configBatchContext = configBatchContextValue

        if !skippedAgents.isEmpty {
            let skippedNames = skippedAgents
                .map(\.name)
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .joined(separator: "、")
            let scopeDescription = workflowID == nil ? "任何 workflow 节点" : "当前 workflow 节点"
            result.warnings.append("以下 agent 未绑定到\(scopeDescription)，已跳过自动注册：\(skippedNames)")
        }

        func makeWorkspaceRequirement(
            for agent: Agent,
            identifier: String
        ) -> LocalRuntimeWorkspaceRequirement? {
            guard let binding = nodeBinding(for: agent.id, in: project, workflowID: workflowID) else {
                return nil
            }

            return LocalRuntimeWorkspaceRequirement(
                agentID: agent.id,
                workflowID: binding.workflowID,
                nodeID: binding.nodeID,
                agentName: agent.name,
                targetIdentifier: identifier,
                diagnosticMessage: unresolvedWorkspaceDiagnosticMessage(for: agent, in: project, workflowID: workflowID)
            )
        }

        func combineMessages(from stageReports: [LocalRuntimeRegistrationStageReport]) -> String {
            stageReports
                .compactMap(\.detail)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }

        func makeImmediateReport(
            agent: Agent,
            identifier: String,
            bootstrapPathRequired: Bool,
            workspaceRequirement: LocalRuntimeWorkspaceRequirement?,
            stageReports: [LocalRuntimeRegistrationStageReport]
        ) -> LocalRuntimeAgentRegistrationReport {
            LocalRuntimeAgentRegistrationReport(
                agentName: agent.name,
                identifier: identifier,
                success: !hasBlockingLocalRuntimeRegistrationFailure(
                    stageReports: stageReports,
                    bootstrapPathRequired: bootstrapPathRequired
                ),
                message: combineMessages(from: stageReports),
                bootstrapPathRequired: bootstrapPathRequired,
                workspaceRequirement: workspaceRequirement,
                stageReports: stageReports
            )
        }

        var immediateReports: [LocalRuntimeAgentRegistrationReport] = []
        var batchStates: [LocalRuntimeBatchRegistrationState] = []

        for spec in registrationSpecs {
            let agent = spec.agent
            let expectedIdentifier = spec.targetIdentifier
            if !expectedIdentifier.isEmpty {
                expectedIdentifiers.insert(normalizeAgentKey(expectedIdentifier))
            }

            let identifier = normalizedTargetIdentifier(for: agent).trimmingCharacters(in: .whitespacesAndNewlines)
            let workspaceRequirement = makeWorkspaceRequirement(for: agent, identifier: identifier)
            var stageReports: [LocalRuntimeRegistrationStageReport] = []

            func appendStage(
                _ stage: LocalRuntimeRegistrationStage,
                _ status: LocalRuntimeRegistrationStageStatus,
                changed: Bool = false,
                detail: String? = nil
            ) {
                stageReports.append(
                    LocalRuntimeRegistrationStageReport(
                        stage: stage,
                        status: status,
                        changed: changed,
                        detail: detail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? detail : nil
                    )
                )
            }

            guard !identifier.isEmpty else {
                appendStage(.workspaceResolution, .failed, detail: "当前节点缺少可用的本地 runtime agent 标识。")
                immediateReports.append(
                    makeImmediateReport(
                        agent: agent,
                        identifier: "",
                        bootstrapPathRequired: false,
                        workspaceRequirement: nil,
                        stageReports: stageReports
                    )
                )
                continue
            }

            let matchedRecord = runtimeRecords.first(where: {
                normalizeAgentKey($0.targetIdentifier) == normalizeAgentKey(identifier)
                    || normalizeAgentKey($0.name) == normalizeAgentKey(identifier)
            })
            let allowSeedFromOtherAgents = matchedRecord == nil
            let runtimeWorkspaceURL = localRuntimeAgentWorkspaceURL(for: identifier, using: config)

            if let matchedRecord {
                appendStage(.runtimeRecognition, .succeeded, detail: "已匹配到现有本地 runtime agent \(matchedRecord.targetIdentifier)。")
                let runtimeAgentDirectory = firstNonEmptyPath(matchedRecord.agentDirPath)
                    .map { URL(fileURLWithPath: $0, isDirectory: true) }
                    ?? localOpenClawRootURL(using: config)
                        .appendingPathComponent("agents", isDirectory: true)
                        .appendingPathComponent(identifier, isDirectory: true)
                        .appendingPathComponent("agent", isDirectory: true)

                let workspaceSourcePath = firstNonEmptyPath(
                    resolvedWorkspaceSourcePath(for: agent, in: project, workflowID: workflowID),
                    matchedRecord.workspacePath
                )
                if let workspaceSourcePath {
                    let workspaceSync = synchronizeLocalRuntimeWorkspace(
                        from: workspaceSourcePath,
                        to: runtimeWorkspaceURL,
                        identifier: matchedRecord.targetIdentifier
                    )
                    appendStage(
                        .workspaceResolution,
                        workspaceSync.success ? .succeeded : .failed,
                        changed: !workspaceSync.message.isEmpty,
                        detail: workspaceSync.message
                    )
                }

                let desiredModelIdentifier = qualifiedLocalRuntimeModelIdentifier(
                    agent.openClawDefinition.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? matchedRecord.modelIdentifier
                        : agent.openClawDefinition.modelIdentifier,
                    preferredAgentDirectory: runtimeAgentDirectory
                )
                let configMutation = applyLocalRuntimeConfigBatchMutation(
                    &configBatchContext,
                    configIndex: matchedRecord.configIndex,
                    identifier: identifier,
                    name: agent.openClawDefinition.agentIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? matchedRecord.name
                        : agent.openClawDefinition.agentIdentifier,
                    workspacePath: runtimeWorkspaceURL.path,
                    agentDirPath: runtimeAgentDirectory.path,
                    modelIdentifier: desiredModelIdentifier
                )
                appendStage(
                    .canonicalConfig,
                    configMutation.success ? .succeeded : .failed,
                    changed: configMutation.changed,
                    detail: configMutation.message
                )

                let bootstrap = ensureLocalRuntimeAgentBootstrapFiles(
                    at: runtimeAgentDirectory,
                    displayIdentifier: matchedRecord.targetIdentifier,
                    using: config
                )
                appendStage(
                    .bootstrap,
                    bootstrap.success ? .succeeded : .failed,
                    changed: !bootstrap.message.isEmpty,
                    detail: bootstrap.message
                )

                batchStates.append(
                    LocalRuntimeBatchRegistrationState(
                        agent: agent,
                        identifier: matchedRecord.targetIdentifier,
                        runtimeAgentDirectory: runtimeAgentDirectory,
                        runtimeWorkspaceURL: runtimeWorkspaceURL,
                        initialRuntimeRecord: matchedRecord,
                        allowSeedFromOtherAgents: allowSeedFromOtherAgents,
                        workspaceRequirement: nil,
                        stageReports: stageReports,
                        bootstrapPathRequired: bootstrap.requiresUserProvidedBootstrapPath
                    )
                )
                continue
            }

            guard let workspaceSourcePath = resolvedWorkspaceSourcePath(for: agent, in: project, workflowID: workflowID)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !workspaceSourcePath.isEmpty else {
                let diagnosticMessage = unresolvedWorkspaceDiagnosticMessage(for: agent, in: project, workflowID: workflowID)
                let baseMessage = "本地 workflow agent \(identifier) 尚未解析到可用 workspace，因此无法自动注册到 OpenClaw CLI。"
                let message = [baseMessage, diagnosticMessage]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                appendStage(.workspaceResolution, .failed, detail: message)
                immediateReports.append(
                    makeImmediateReport(
                        agent: agent,
                        identifier: identifier,
                        bootstrapPathRequired: false,
                        workspaceRequirement: workspaceRequirement,
                        stageReports: stageReports
                    )
                )
                continue
            }

            let workspaceSync = synchronizeLocalRuntimeWorkspace(
                from: workspaceSourcePath,
                to: runtimeWorkspaceURL,
                identifier: identifier
            )
            appendStage(
                .workspaceResolution,
                workspaceSync.success ? .succeeded : .failed,
                changed: !workspaceSync.message.isEmpty,
                detail: workspaceSync.message
            )
            guard workspaceSync.success else {
                immediateReports.append(
                    makeImmediateReport(
                        agent: agent,
                        identifier: identifier,
                        bootstrapPathRequired: false,
                        workspaceRequirement: workspaceRequirement,
                        stageReports: stageReports
                    )
                )
                continue
            }

            let runtimeAgentDirectory = localOpenClawRootURL(using: config)
                .appendingPathComponent("agents", isDirectory: true)
                .appendingPathComponent(identifier, isDirectory: true)
                .appendingPathComponent("agent", isDirectory: true)
            let configMutation = applyLocalRuntimeConfigBatchMutation(
                &configBatchContext,
                identifier: identifier,
                name: agent.openClawDefinition.agentIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? agent.name
                    : agent.openClawDefinition.agentIdentifier,
                workspacePath: runtimeWorkspaceURL.path,
                agentDirPath: runtimeAgentDirectory.path,
                modelIdentifier: nil,
                updateModel: false
            )
            appendStage(
                .canonicalConfig,
                configMutation.success ? .succeeded : .failed,
                changed: configMutation.changed,
                detail: configMutation.message
            )

            let bootstrap = ensureLocalRuntimeAgentBootstrapFiles(
                at: runtimeAgentDirectory,
                displayIdentifier: identifier,
                using: config
            )
            appendStage(
                .bootstrap,
                bootstrap.success ? .succeeded : .failed,
                changed: !bootstrap.message.isEmpty,
                detail: bootstrap.message
            )

            if configMutation.success {
                appendStage(.runtimeRecognition, .skipped, detail: "canonical 配置已写入，待批量提交后统一校验 runtime 识别结果。")
            }

            batchStates.append(
                LocalRuntimeBatchRegistrationState(
                    agent: agent,
                    identifier: identifier,
                    runtimeAgentDirectory: runtimeAgentDirectory,
                    runtimeWorkspaceURL: runtimeWorkspaceURL,
                    initialRuntimeRecord: nil,
                    allowSeedFromOtherAgents: allowSeedFromOtherAgents,
                    workspaceRequirement: nil,
                    stageReports: stageReports,
                    bootstrapPathRequired: bootstrap.requiresUserProvidedBootstrapPath
                )
            )
        }

        let commitResult = commitLocalRuntimeConfigBatch(&configBatchContext)
        if !commitResult.success {
            result.failureMessages.append(commitResult.message)
        }

        var verifiedRuntimeRecords = runtimeRecords
        do {
            let listResult = try runOpenClawCommand(using: config, arguments: ["agents", "list", "--json"])
            verifiedRuntimeRecords = parseManagedAgents(from: listResult.standardOutput, using: config)
        } catch {
            result.failureMessages.append("本地 runtime 注册校验失败：\(error.localizedDescription)")
        }

        if commitResult.success {
            let availableIdentifiers = Set(verifiedRuntimeRecords.map { normalizeAgentKey($0.targetIdentifier) })
            let missingNewStateIndices = batchStates.indices.filter { index in
                let state = batchStates[index]
                return state.initialRuntimeRecord == nil
                    && !availableIdentifiers.contains(normalizeAgentKey(state.identifier))
                    && !state.stageReports.contains(where: { $0.status == .failed })
            }

            if !missingNewStateIndices.isEmpty {
                for index in missingNewStateIndices {
                    var state = batchStates[index]
                    let explicitModel = qualifiedLocalRuntimeModelIdentifier(
                        state.agent.openClawDefinition.modelIdentifier,
                        preferredAgentDirectory: state.runtimeAgentDirectory
                    )
                    var arguments = [
                        "agents", "add", state.identifier,
                        "--workspace", state.runtimeWorkspaceURL.path,
                        "--agent-dir", state.runtimeAgentDirectory.path,
                        "--non-interactive",
                        "--json"
                    ]
                    if !explicitModel.isEmpty {
                        arguments.append(contentsOf: ["--model", explicitModel])
                    }

                    do {
                        let cliResult = try runOpenClawCommand(using: config, arguments: arguments)
                        if cliResult.terminationStatus == 0 {
                            let registeredIdentifier = resolvedRegisteredAgentIdentifier(
                                from: cliResult.standardOutput,
                                fallbackName: state.identifier,
                                using: config
                            )
                            state.stageReports.append(
                                LocalRuntimeRegistrationStageReport(
                                    stage: .cliRegistrationFallback,
                                    status: .succeeded,
                                    changed: true,
                                    detail: "已将本地 workflow agent \(state.identifier) 自动注册到 OpenClaw CLI（runtime id: \(registeredIdentifier)）。"
                                )
                            )
                        } else {
                            let stderr = String(data: cliResult.standardError, encoding: .utf8)?
                                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            let stdout = String(data: cliResult.standardOutput, encoding: .utf8)?
                                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            let detail = !stderr.isEmpty ? stderr : stdout
                            state.stageReports.append(
                                LocalRuntimeRegistrationStageReport(
                                    stage: .cliRegistrationFallback,
                                    status: .failed,
                                    changed: false,
                                    detail: "自动注册本地 workflow agent \(state.identifier) 失败：\(detail)"
                                )
                            )
                        }
                    } catch {
                        state.stageReports.append(
                            LocalRuntimeRegistrationStageReport(
                                stage: .cliRegistrationFallback,
                                status: .failed,
                                changed: false,
                                detail: "自动注册本地 workflow agent \(state.identifier) 失败：\(error.localizedDescription)"
                            )
                        )
                    }

                    batchStates[index] = state
                }

                do {
                    let listResult = try runOpenClawCommand(using: config, arguments: ["agents", "list", "--json"])
                    verifiedRuntimeRecords = parseManagedAgents(from: listResult.standardOutput, using: config)
                } catch {
                    result.failureMessages.append("本地 runtime 注册校验失败：\(error.localizedDescription)")
                }
            }
        }

        let activationBatchResult = applyLocalRuntimeActivationBatch(
            batchStates,
            in: project,
            workflowID: workflowID,
            runtimeRecords: verifiedRuntimeRecords,
            initialBindingRecords: bindingRecords,
            using: config
        )
        batchStates = activationBatchResult.batchStates
        result.warnings.append(contentsOf: activationBatchResult.warnings)

        result.agentReports = immediateReports + batchStates.map { state in
            LocalRuntimeAgentRegistrationReport(
                agentName: state.agent.name,
                identifier: state.identifier,
                success: !hasBlockingLocalRuntimeRegistrationFailure(
                    stageReports: state.stageReports,
                    bootstrapPathRequired: state.bootstrapPathRequired
                ),
                message: combineMessages(from: state.stageReports),
                bootstrapPathRequired: state.bootstrapPathRequired,
                workspaceRequirement: state.workspaceRequirement,
                stageReports: state.stageReports
            )
        }

        for registration in result.agentReports {
            if !registration.success {
                let failureMessage = localRuntimeRegistrationFailureMessage(for: registration)
                result.failureMessages.append(failureMessage)
                if registration.bootstrapPathRequired {
                    result.bootstrapPathRequiredAgentNames.append(registration.agentName)
                }
                if let workspaceRequirement = registration.workspaceRequirement {
                    result.workspacePathRequirements.append(workspaceRequirement)
                }
                continue
            }

            if registration.bootstrapPathRequired {
                result.warnings.append(localRuntimeRegistrationFailureMessage(for: registration))
                result.bootstrapPathRequiredAgentNames.append(registration.agentName)
            }

            if registration.changed {
                changedNames.insert(registration.agentName)
            }
        }

        if !changedNames.isEmpty {
            result.changedAgentNames = changedNames.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
        }

        if !result.bootstrapPathRequiredAgentNames.isEmpty {
            result.bootstrapPathRequiredAgentNames = Array(Set(result.bootstrapPathRequiredAgentNames)).sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
        }

        guard result.failureMessages.isEmpty, !expectedIdentifiers.isEmpty else {
            return result
        }

        let availableIdentifiers = Set(verifiedRuntimeRecords.map { normalizeAgentKey($0.targetIdentifier) })
        let missing = expectedIdentifiers.subtracting(availableIdentifiers)
        if !missing.isEmpty {
            let missingText = registerableAgents
                .filter { missing.contains(normalizeAgentKey(normalizedTargetIdentifier(for: $0))) }
                .map(\.name)
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .joined(separator: "、")
            result.failureMessages.append("本地 runtime 注册校验失败，以下 agent 仍未出现在 OpenClaw CLI 中：\(missingText)")
        }

        return result
    }

    private func buildLocalRuntimeRegistrationSpecs(
        in project: MAProject,
        workflowID: UUID? = nil
    ) -> [LocalRuntimeRegistrationSpec] {
        workflowBoundProjectAgents(in: project, workflowID: workflowID).compactMap { agent in
            guard let binding = nodeBinding(for: agent.id, in: project, workflowID: workflowID) else {
                return nil
            }

            return LocalRuntimeRegistrationSpec(
                agent: agent,
                workflowID: binding.workflowID,
                nodeID: binding.nodeID,
                targetIdentifier: normalizedTargetIdentifier(for: agent).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private func workflowBoundProjectAgents(
        in project: MAProject,
        workflowID: UUID? = nil
    ) -> [Agent] {
        var boundAgentIDs = Set<UUID>()
        let scopedWorkflows = workflows(in: project, matching: workflowID)

        for workflow in scopedWorkflows {
            for node in workflow.nodes where node.type == .agent {
                guard let agentID = node.agentID else { continue }
                boundAgentIDs.insert(agentID)
            }
        }

        return project.agents.filter { boundAgentIDs.contains($0.id) }
    }

    private func localRuntimeRegistrationStageTitle(_ stage: LocalRuntimeRegistrationStage) -> String {
        switch stage {
        case .workspaceResolution:
            return "workspace 解析"
        case .canonicalConfig:
            return "canonical 配置写入"
        case .runtimeRecognition:
            return "runtime 识别"
        case .cliRegistrationFallback:
            return "CLI 注册兜底"
        case .bootstrap:
            return "bootstrap 补齐"
        case .activation:
            return "model / channel 激活"
        }
    }

    private func localRuntimeRegistrationFailureMessage(for report: LocalRuntimeAgentRegistrationReport) -> String {
        let failedStages = report.stageReports
            .filter { $0.status == .failed }
            .map { stageReport -> String in
                let title = localRuntimeRegistrationStageTitle(stageReport.stage)
                let detail = stageReport.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return detail.isEmpty ? title : "\(title)：\(detail)"
            }
        let stageSummary = failedStages.joined(separator: "；")
        let baseMessage = report.message.trimmingCharacters(in: .whitespacesAndNewlines)

        if baseMessage.isEmpty {
            if stageSummary.isEmpty {
                return "本地 workflow agent \(report.agentName) 自动注册失败。"
            }
            return "本地 workflow agent \(report.agentName) 自动注册失败。失败阶段：\(stageSummary)。"
        }

        guard !stageSummary.isEmpty, !baseMessage.contains(stageSummary) else {
            return baseMessage
        }
        return "\(baseMessage) 失败阶段：\(stageSummary)。"
    }

    private func hasBlockingLocalRuntimeRegistrationFailure(
        stageReports: [LocalRuntimeRegistrationStageReport],
        bootstrapPathRequired: Bool
    ) -> Bool {
        let failedStages = stageReports
            .filter { $0.status == .failed }
            .map(\.stage)

        guard !failedStages.isEmpty else {
            return false
        }

        if bootstrapPathRequired {
            return failedStages.contains { $0 != .bootstrap }
        }

        return true
    }

    private func localRuntimeRegistrationSummary(from result: LocalRuntimeRegistrationResult) -> String {
        guard result.success, !result.changedAgentNames.isEmpty else {
            return ""
        }

        var parts = ["已补齐并校验本地 runtime agent 注册：\(result.changedAgentNames.joined(separator: "、"))。"]
        if !result.canonicalProvisionedAgentNames.isEmpty {
            parts.append("已同步 canonical 配置：\(result.canonicalProvisionedAgentNames.joined(separator: "、"))。")
        }
        if !result.cliFallbackAgentNames.isEmpty {
            parts.append("其中 \(result.cliFallbackAgentNames.joined(separator: "、")) 通过 CLI add 兼容兜底完成显式注册。")
        }
        if !result.activationUpdatedAgentNames.isEmpty {
            parts.append("已自动补齐 model / channel：\(result.activationUpdatedAgentNames.joined(separator: "、"))。")
        }
        return parts.joined(separator: " ")
    }

    func executeOpenClawCLI(
        arguments: [String],
        using config: OpenClawConfig? = nil,
        standardInput: FileHandle? = nil
    ) throws -> (terminationStatus: Int32, standardOutput: Data, standardError: Data) {
        try runOpenClawCommand(using: config ?? self.config, arguments: arguments, standardInput: standardInput)
    }

    func registerUserProvidedLocalBootstrapDirectory(_ directoryURL: URL) -> (success: Bool, message: String) {
        guard let resolved = normalizedUserProvidedLocalBootstrapDirectory(directoryURL) else {
            return (
                false,
                "所选路径中未找到可复用的 OpenClaw 鉴权配置。请选择包含 auth-profiles.json / models.json 的 agent 目录，或其上级 agents 目录。"
            )
        }

        userProvidedLocalBootstrapDirectory = resolved

        return (true, "已记录手动指定的 OpenClaw bootstrap 路径：\(resolved.path)")
    }

    func registerUserProvidedLocalWorkspaceDirectory(
        _ directoryURL: URL,
        for requirement: LocalRuntimeWorkspaceRequirement
    ) -> (success: Bool, message: String) {
        guard let resolved = normalizedUserProvidedLocalWorkspaceDirectory(directoryURL) else {
            return (
                false,
                "所选路径不是有效的 workspace 目录。请选择该 agent 对应的工作目录。"
            )
        }

        userProvidedLocalWorkspaceDirectoriesByNodeID[requirement.nodeID] = resolved
        userProvidedLocalWorkspaceDirectoriesByAgentID[requirement.agentID] = resolved
        return (true, "已记录 \(requirement.agentName) 的手动 workspace 路径：\(resolved.path)")
    }

    func executeAgentRuntimeCommand(
        arguments: [String],
        using config: OpenClawConfig? = nil,
        standardInput: FileHandle? = nil,
        onStdoutChunk: ((String) -> Void)? = nil
    ) throws -> AgentRuntimeCommandResult {
        let resolvedConfig = config ?? self.config
        let channel = try agentRuntimeChannel(for: resolvedConfig)
        return try channel.execute(
            arguments: arguments,
            standardInput: standardInput,
            onStdoutChunk: onStdoutChunk
        )
    }

    func resetAgentRuntimeChannels() {
        agentRuntimeChannelLock.lock()
        agentRuntimeChannels.removeAll()
        agentRuntimeChannelLock.unlock()
    }

    func resetGatewayConnection() {
        _Concurrency.Task {
            await gatewayClient.disconnect()
        }
    }

    private func handleUnexpectedGatewayDisconnect(message: String?) {
        let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let finalMessage = trimmedMessage.isEmpty
            ? "OpenClaw Gateway 连接已断开。"
            : "OpenClaw Gateway 连接已断开：\(trimmedMessage)"

        let isCurrentlyConnecting: Bool = {
            if case .connecting = status {
                return true
            }
            return false
        }()

        guard isConnected || isCurrentlyConnecting else { return }

        isConnected = false
        activeAgents.removeAll()
        status = .error(finalMessage)
        if config.usesManagedLocalRuntime {
            managedRuntimeStatus = managedRuntimeSupervisor.markGatewayDisconnect(message: finalMessage)
        }

        var capabilities = connectionState.capabilities
        capabilities.gatewayReachable = false
        capabilities.gatewayAuthenticated = false
        capabilities.gatewayAgentAvailable = false
        capabilities.gatewayChatAvailable = false
        capabilities.sessionHistoryAvailable = false

        let degradedPhase: OpenClawConnectionPhase = capabilities.cliAvailable ? .degraded : .failed
        let health = OpenClawConnectionHealthSnapshot(
            lastProbeAt: connectionState.health.lastProbeAt,
            lastHeartbeatAt: Date(),
            latencyMs: connectionState.health.latencyMs,
            degradationReason: finalMessage,
            lastMessage: finalMessage
        )
        updateConnectionState(
            phase: degradedPhase,
            deploymentKind: config.deploymentKind,
            capabilities: capabilities,
            health: health
        )
    }

    private func updateConnectionState(
        phase: OpenClawConnectionPhase,
        deploymentKind: OpenClawDeploymentKind,
        capabilities: OpenClawConnectionCapabilitiesSnapshot,
        health: OpenClawConnectionHealthSnapshot
    ) {
        connectionState = OpenClawConnectionStateSnapshot(
            phase: phase,
            deploymentKind: deploymentKind,
            capabilities: capabilities,
            health: health
        )
    }

    private func endpointDescription(for config: OpenClawConfig) -> String {
        switch config.deploymentKind {
        case .local:
            let binaryPath = resolveOpenClawPath(for: config)
            return "local:\(binaryPath)"
        case .container:
            let engine = config.container.engine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "docker"
                : config.container.engine.trimmingCharacters(in: .whitespacesAndNewlines)
            let containerName = config.container.containerName.trimmingCharacters(in: .whitespacesAndNewlines)
            return "container:\(engine):\(containerName)"
        case .remoteServer:
            return "\((config.useSSL ? "wss" : "ws"))://\(config.host):\(config.port)"
        }
    }

    private func inferredCapabilities(
        for config: OpenClawConfig,
        success: Bool,
        message: String,
        agentNames: [String]
    ) -> OpenClawConnectionCapabilitiesSnapshot {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        switch config.deploymentKind {
        case .local:
            if success {
                return OpenClawConnectionCapabilitiesSnapshot(
                    cliAvailable: true,
                    gatewayReachable: true,
                    gatewayAuthenticated: true,
                    agentListingAvailable: true,
                    sessionHistoryAvailable: true,
                    gatewayAgentAvailable: true,
                    gatewayChatAvailable: true,
                    projectAttachmentSupported: true
                )
            }

            let cliAvailable = trimmedMessage.contains("CLI 可用")
            let hasAgents = !agentNames.isEmpty
            return OpenClawConnectionCapabilitiesSnapshot(
                cliAvailable: cliAvailable,
                gatewayReachable: false,
                gatewayAuthenticated: false,
                agentListingAvailable: cliAvailable && hasAgents,
                sessionHistoryAvailable: false,
                gatewayAgentAvailable: false,
                gatewayChatAvailable: false,
                projectAttachmentSupported: true
            )
        case .container:
            if success {
                return OpenClawConnectionCapabilitiesSnapshot(
                    cliAvailable: true,
                    gatewayReachable: true,
                    gatewayAuthenticated: true,
                    agentListingAvailable: true,
                    sessionHistoryAvailable: true,
                    gatewayAgentAvailable: true,
                    gatewayChatAvailable: true,
                    projectAttachmentSupported: true
                )
            }

            let cliAvailable = trimmedMessage.contains("CLI 可用")
            let hasAgents = !agentNames.isEmpty
            return OpenClawConnectionCapabilitiesSnapshot(
                cliAvailable: cliAvailable,
                gatewayReachable: false,
                gatewayAuthenticated: false,
                agentListingAvailable: cliAvailable && hasAgents,
                sessionHistoryAvailable: false,
                gatewayAgentAvailable: false,
                gatewayChatAvailable: false,
                projectAttachmentSupported: true
            )
        case .remoteServer:
            return OpenClawConnectionCapabilitiesSnapshot(
                cliAvailable: false,
                gatewayReachable: success,
                gatewayAuthenticated: success,
                agentListingAvailable: success,
                sessionHistoryAvailable: success,
                gatewayAgentAvailable: success,
                gatewayChatAvailable: success,
                projectAttachmentSupported: false
            )
        }
    }

    private func observedDefaultTransports(
        for config: OpenClawConfig,
        capabilities: OpenClawConnectionCapabilitiesSnapshot
    ) -> [String] {
        var transports: [String] = []
        if capabilities.gatewayAgentAvailable {
            transports.append("gateway_agent")
        }
        if capabilities.gatewayChatAvailable {
            transports.append("gateway_chat")
        }
        if capabilities.cliAvailable {
            transports.append("cli")
        }

        if transports.isEmpty {
            switch config.deploymentKind {
            case .local, .container:
                transports = ["cli"]
            case .remoteServer:
                transports = []
            }
        }

        return transports
    }

    private func inferredProbeLayers(
        for config: OpenClawConfig,
        capabilities: OpenClawConnectionCapabilitiesSnapshot
    ) -> OpenClawProbeLayersSnapshot {
        switch config.deploymentKind {
        case .container:
            return OpenClawProbeLayersSnapshot(
                transport: capabilities.cliAvailable && capabilities.gatewayReachable ? .ready : ((capabilities.cliAvailable || capabilities.gatewayReachable) ? .degraded : .unavailable),
                authentication: capabilities.gatewayReachable ? (capabilities.gatewayAuthenticated ? .ready : .degraded) : (capabilities.cliAvailable ? .degraded : .unavailable),
                session: capabilities.cliAvailable && capabilities.agentListingAvailable && capabilities.gatewayAuthenticated ? .ready : ((capabilities.cliAvailable || capabilities.gatewayReachable) ? .degraded : .unavailable),
                inventory: capabilities.agentListingAvailable ? .ready : (capabilities.cliAvailable ? .degraded : .unavailable)
            )
        case .remoteServer:
            return OpenClawProbeLayersSnapshot(
                transport: capabilities.gatewayReachable ? .ready : .unavailable,
                authentication: capabilities.gatewayReachable ? (capabilities.gatewayAuthenticated ? .ready : .degraded) : .unavailable,
                session: capabilities.gatewayAuthenticated ? .ready : (capabilities.gatewayReachable ? .degraded : .unavailable),
                inventory: capabilities.agentListingAvailable ? .ready : (capabilities.gatewayAuthenticated ? .degraded : .unavailable)
            )
        case .local:
            return OpenClawProbeLayersSnapshot(
                transport: capabilities.cliAvailable && capabilities.gatewayReachable ? .ready : ((capabilities.cliAvailable || capabilities.gatewayReachable) ? .degraded : .unavailable),
                authentication: capabilities.gatewayReachable ? (capabilities.gatewayAuthenticated ? .ready : .degraded) : (capabilities.cliAvailable ? .degraded : .unavailable),
                session: capabilities.cliAvailable && capabilities.agentListingAvailable && capabilities.gatewayAuthenticated ? .ready : ((capabilities.cliAvailable || capabilities.gatewayReachable) ? .degraded : .unavailable),
                inventory: capabilities.agentListingAvailable ? .ready : (capabilities.cliAvailable ? .degraded : .unavailable)
            )
        }
    }

    private func recordProbeResult(
        using config: OpenClawConfig,
        success: Bool,
        message: String,
        agentNames: [String]
    ) {
        let capabilities = inferredCapabilities(for: config, success: success, message: message, agentNames: agentNames)
        let phase: OpenClawConnectionPhase = {
            if success {
                return .ready
            }
            if capabilities.cliAvailable || capabilities.gatewayReachable || capabilities.agentListingAvailable {
                return .degraded
            }
            return .failed
        }()

        let health = OpenClawConnectionHealthSnapshot(
            lastProbeAt: Date(),
            lastHeartbeatAt: success ? Date() : nil,
            latencyMs: nil,
            degradationReason: success ? nil : (phase == .degraded ? message : nil),
            lastMessage: message
        )

        updateConnectionState(
            phase: phase,
            deploymentKind: config.deploymentKind,
            capabilities: capabilities,
            health: health
        )

        let layers = inferredProbeLayers(for: config, capabilities: capabilities)
        let sourceOfTruth: String = {
            guard success else { return "probe" }
            switch config.deploymentKind {
            case .remoteServer:
                return "gateway"
            case .local, .container:
                return capabilities.gatewayReachable ? "cli+gateway+inspection" : "cli+inspection"
            }
        }()
        lastProbeReport = OpenClawProbeReportSnapshot(
            success: success,
            deploymentKind: config.deploymentKind,
            endpoint: endpointDescription(for: config),
            layers: layers,
            capabilities: capabilities,
            health: health,
            availableAgents: agentNames,
            message: message,
            warnings: success ? [] : [message],
            sourceOfTruth: sourceOfTruth,
            observedDefaultTransports: observedDefaultTransports(for: config, capabilities: capabilities)
        )
    }

    func preferredGatewayConfig(using config: OpenClawConfig? = nil) -> OpenClawConfig? {
        let resolvedConfig = config ?? self.config

        switch resolvedConfig.deploymentKind {
        case .remoteServer:
            let host = resolvedConfig.host.trimmingCharacters(in: .whitespacesAndNewlines)
            return host.isEmpty ? nil : resolvedConfig
        case .local:
            return localLoopbackGatewayConfig(using: resolvedConfig)
        case .container:
            return containerGatewayConfig(using: resolvedConfig)
        }
    }

    func executeGatewayAgentCommand(
        message: String,
        agentIdentifier: String,
        sessionKey: String?,
        thinkingLevel: AgentThinkingLevel?,
        timeoutSeconds: Int,
        using config: OpenClawConfig? = nil,
        onAssistantTextUpdated: @escaping @Sendable (String) -> Void
    ) async throws -> OpenClawGatewayClient.AgentExecutionResult {
        try await gatewayClient.executeAgent(
            using: config ?? self.config,
            message: message,
            agentIdentifier: agentIdentifier,
            sessionKey: sessionKey,
            thinkingLevel: thinkingLevel,
            timeoutSeconds: timeoutSeconds,
            onAssistantTextUpdated: onAssistantTextUpdated
        )
    }

    func executeGatewayChatCommand(
        message: String,
        sessionKey: String,
        thinkingLevel: AgentThinkingLevel?,
        timeoutSeconds: Int,
        using config: OpenClawConfig? = nil,
        onRunStarted: (@Sendable (String, String) -> Void)? = nil,
        onAssistantTextUpdated: @escaping @Sendable (String) -> Void
    ) async throws -> OpenClawGatewayClient.AgentExecutionResult {
        try await gatewayClient.executeChat(
            using: config ?? self.config,
            message: message,
            sessionKey: sessionKey,
            thinkingLevel: thinkingLevel,
            timeoutSeconds: timeoutSeconds,
            onRunStarted: onRunStarted,
            onAssistantTextUpdated: onAssistantTextUpdated
        )
    }

    func listGatewaySessions(
        using config: OpenClawConfig? = nil,
        limit: Int? = nil
    ) async throws -> [OpenClawGatewayClient.ChatSessionRecord] {
        try await gatewayClient.listSessions(using: config ?? self.config, limit: limit)
    }

    func gatewayChatHistory(
        sessionKey: String,
        using config: OpenClawConfig? = nil,
        limit: Int? = nil
    ) async throws -> [OpenClawGatewayClient.ChatTranscriptMessage] {
        try await gatewayClient.chatHistory(
            using: config ?? self.config,
            sessionKey: sessionKey,
            limit: limit
        )
    }

    func abortGatewayChatRun(
        sessionKey: String,
        runID: String,
        using config: OpenClawConfig? = nil
    ) async throws {
        try await gatewayClient.abortChatRun(
            using: config ?? self.config,
            sessionKey: sessionKey,
            runID: runID
        )
    }

    func resolvedOpenClawPath(using config: OpenClawConfig? = nil) -> String {
        host.resolveLocalBinaryPath(for: config ?? self.config)
    }

    private func agentRuntimeChannel(for config: OpenClawConfig) throws -> AgentRuntimeChannel {
        let key = agentRuntimeChannelKey(for: config)

        agentRuntimeChannelLock.lock()
        if let existing = agentRuntimeChannels[key] {
            agentRuntimeChannelLock.unlock()
            return existing
        }
        agentRuntimeChannelLock.unlock()

        let commandPlan = try host.buildOpenClawCommandPlan(
            for: config,
            arguments: []
        )
        let channel = AgentRuntimeChannel(
            key: key,
            commandPlan: commandPlan
        )

        agentRuntimeChannelLock.lock()
        if let existing = agentRuntimeChannels[key] {
            agentRuntimeChannelLock.unlock()
            return existing
        }
        agentRuntimeChannels[key] = channel
        agentRuntimeChannelLock.unlock()
        return channel
    }

    private func agentRuntimeChannelKey(for config: OpenClawConfig) -> String {
        switch config.deploymentKind {
        case .local:
            return "local|\(resolveOpenClawPath(for: config))"
        case .container:
            let engine = config.container.engine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "docker"
                : config.container.engine.trimmingCharacters(in: .whitespacesAndNewlines)
            let containerName = config.container.containerName.trimmingCharacters(in: .whitespacesAndNewlines)
            return "container|\(engine)|\(containerName)"
        case .remoteServer:
            let host = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
            return "remote|\(host)|\(config.port)|\(config.useSSL)"
        }
    }

    private func parseManagedAgents(from data: Data, using config: OpenClawConfig) -> [ManagedAgentRecord] {
        guard
            let jsonData = extractJSONPayload(from: data),
            let jsonObject = try? JSONSerialization.jsonObject(with: jsonData),
            let dictionaries = dictionaryArray(in: jsonObject)
        else {
            let names = parsePlainTextList(from: data)
            return names.enumerated().map { index, name in
                ManagedAgentRecord(
                    id: name,
                    name: name,
                    targetIdentifier: name,
                    modelIdentifier: ""
                )
            }
        }

        return dictionaries.enumerated().map { index, dictionary in
            let id = stringValue(dictionary, keys: ["id", "agentID", "agentId", "name"]) ?? "agent-\(index)"
            let name = stringValue(dictionary, keys: ["name", "displayName", "agentName"]) ?? id
            let agentDirPath = stringValue(dictionary, keys: ["agentDir", "agentDirPath", "directory", "agentDirectory"])
            let workspacePath = stringValue(dictionary, keys: ["workspace", "workspacePath", "workdir", "workPath"])
            let modelIdentifier = stringValue(dictionary, keys: ["model", "modelIdentifier", "primaryModel", "defaultModel"]) ?? ""

            let installedSkills = loadInstalledSkills(
                forWorkspacePath: workspacePath,
                using: config
            )

            return ManagedAgentRecord(
                id: id,
                configIndex: index,
                name: name,
                targetIdentifier: id,
                agentDirPath: agentDirPath,
                workspacePath: workspacePath,
                modelIdentifier: modelIdentifier,
                installedSkills: installedSkills
            )
        }
    }

    private func resolvedRegisteredAgentIdentifier(
        from data: Data,
        fallbackName: String,
        using config: OpenClawConfig
    ) -> String {
        guard
            let jsonData = extractJSONPayload(from: data),
            let jsonObject = try? JSONSerialization.jsonObject(with: jsonData),
            let dictionary = jsonObject as? [String: Any],
            let agentID = stringValue(dictionary, keys: ["agentId", "agentID", "id", "name"])
        else {
            return fallbackName
        }

        let trimmed = agentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallbackName }

        let runtimeRecords = parseManagedAgents(from: data, using: config)
        if let matched = runtimeRecords.first(where: {
            normalizeAgentKey($0.targetIdentifier) == normalizeAgentKey(trimmed)
                || normalizeAgentKey($0.name) == normalizeAgentKey(trimmed)
        }) {
            return matched.targetIdentifier
        }
        return trimmed
    }

    private func qualifiedLocalRuntimeModelIdentifier(
        _ modelIdentifier: String,
        preferredAgentDirectory: URL? = nil
    ) -> String {
        let trimmed = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            return trimmed
        }

        let authProviders = localRuntimeAuthProviders(preferredAgentDirectory: preferredAgentDirectory)
        let providerModels = localRuntimeModelCatalog(preferredAgentDirectory: preferredAgentDirectory)

        if let matchedProvider = providerModels.first(where: { entry in
            entry.modelIDs.contains(trimmed) && authProviders.contains(entry.provider)
        })?.provider {
            return "\(matchedProvider)/\(trimmed)"
        }

        if let matchedProvider = providerModels.first(where: { $0.modelIDs.contains(trimmed) })?.provider {
            return "\(matchedProvider)/\(trimmed)"
        }

        if trimmed.localizedCaseInsensitiveContains("minimax") {
            if authProviders.contains("minimax") {
                return "minimax/\(trimmed)"
            }
            if authProviders.contains("minimax-portal") {
                return "minimax-portal/\(trimmed)"
            }
        }

        return trimmed
    }

    private func canonicalLocalRuntimePath(_ path: String?) -> String? {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed, isDirectory: true)
            .standardizedFileURL
            .path
    }

    private func localRuntimeAgentWorkspaceURL(
        for identifier: String,
        using config: OpenClawConfig? = nil
    ) -> URL {
        localOpenClawRootURL(using: config)
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
            .appendingPathComponent("workspace", isDirectory: true)
    }

    private func resolvedWorkspaceSourcePath(
        for agent: Agent,
        in project: MAProject? = nil,
        workflowID: UUID? = nil
    ) -> String? {
        if let managedWorkspace = projectManagedWorkspacePath(for: agent, in: project, workflowID: workflowID) {
            return managedWorkspace
        }

        if let userProvidedWorkspace = userProvidedLocalWorkspacePath(for: agent, in: project, workflowID: workflowID) {
            return userProvidedWorkspace
        }

        let candidateNames = [
            agent.openClawDefinition.agentIdentifier,
            agent.name
        ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let localWorkspace = localAgentWorkspacePath(matching: candidateNames) {
            return localWorkspace
        }

        let normalizedNames = Set(candidateNames.map(normalizeAgentKey))
        if !normalizedNames.isEmpty,
           let record = discoveryResults.first(where: { normalizedNames.contains(normalizeAgentKey($0.name)) }) {
            return firstNonEmptyPath(record.workspacePath)
        }

        return nil
    }

    private func synchronizeLocalRuntimeWorkspace(
        from sourceWorkspacePath: String,
        to targetWorkspaceURL: URL,
        identifier: String
    ) -> (success: Bool, message: String) {
        let sourceURL = URL(fileURLWithPath: sourceWorkspacePath, isDirectory: true).standardizedFileURL
        let targetURL = targetWorkspaceURL.standardizedFileURL

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return (false, "本地 workflow agent \(identifier) 的源 workspace 不存在：\(sourceURL.path)")
        }

        do {
            try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)
            guard sourceURL.path != targetURL.path else {
                return (true, "")
            }

            _ = try replaceDirectoryContents(of: targetURL, withContentsOf: sourceURL)
            return (true, "已将 \(identifier) 的 workspace 同步到 OpenClaw runtime 路径。")
        } catch {
            return (false, "同步本地 workflow agent \(identifier) 的 runtime workspace 失败：\(error.localizedDescription)")
        }
    }

    private func writeOpenClawConfigRoot(
        _ root: [String: Any],
        to configURL: URL
    ) throws {
        let updatedData = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        let serialized = String(data: updatedData, encoding: .utf8) ?? "{}"
        let normalized = serialized.replacingOccurrences(of: "\\/", with: "/")
        try Data(normalized.utf8).write(to: configURL, options: .atomic)
    }

    private func localRuntimeAuthProviders(preferredAgentDirectory: URL? = nil) -> Set<String> {
        let authFiles = candidateLocalRuntimeAgentDirectories(preferredAgentDirectory: preferredAgentDirectory)
            .map { $0.appendingPathComponent("auth-profiles.json", isDirectory: false) }

        var providers = Set<String>()
        for authURL in authFiles {
            guard
                let data = try? Data(contentsOf: authURL),
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                let profiles = object["profiles"] as? [String: Any]
            else {
                continue
            }

            for value in profiles.values {
                guard let profile = value as? [String: Any],
                      let provider = stringValue(profile, keys: ["provider"]) else {
                    continue
                }
                providers.insert(provider)
            }
        }
        return providers
    }

    private func localRuntimeModelCatalog(preferredAgentDirectory: URL? = nil) -> [(provider: String, modelIDs: Set<String>)] {
        let modelFiles = candidateLocalRuntimeAgentDirectories(preferredAgentDirectory: preferredAgentDirectory)
            .map { $0.appendingPathComponent("models.json", isDirectory: false) }

        var orderedProviders: [(provider: String, modelIDs: Set<String>)] = []
        var providerIndexByName: [String: Int] = [:]

        for modelURL in modelFiles {
            guard
                let data = try? Data(contentsOf: modelURL),
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                let providers = object["providers"] as? [String: Any]
            else {
                continue
            }

            for (provider, value) in providers {
                guard let dictionary = value as? [String: Any],
                      let models = dictionary["models"] as? [[String: Any]] else {
                    continue
                }

                let modelIDs = Set(models.compactMap { stringValue($0, keys: ["id", "name"]) })
                guard !modelIDs.isEmpty else { continue }

                if let existingIndex = providerIndexByName[provider] {
                    var existingEntry = orderedProviders[existingIndex]
                    existingEntry.modelIDs.formUnion(modelIDs)
                    orderedProviders[existingIndex] = existingEntry
                } else {
                    providerIndexByName[provider] = orderedProviders.count
                    orderedProviders.append((provider: provider, modelIDs: modelIDs))
                }
            }
        }

        return orderedProviders
    }

    private func candidateLocalRuntimeAgentDirectories(preferredAgentDirectory: URL? = nil) -> [URL] {
        let agentsDirectory = localOpenClawRootURL().appendingPathComponent("agents", isDirectory: true)
        let discoveredDirectories = (try? fileManager.contentsOfDirectory(
            at: agentsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var directories: [URL] = []
        if let preferredAgentDirectory {
            directories.append(preferredAgentDirectory)
        }
        directories.append(contentsOf: discoveredDirectories.map {
            $0.appendingPathComponent("agent", isDirectory: true)
        })

        var seen = Set<String>()
        return directories.filter { directory in
            seen.insert(directory.path).inserted && fileManager.fileExists(atPath: directory.path)
        }
    }

    private func loadLocalRuntimeConfigBatchContext(
        using config: OpenClawConfig? = nil
    ) -> (context: LocalRuntimeConfigBatchContext?, message: String?) {
        let configURL = resolveLocalOpenClawConfigURL(using: config)
            ?? localOpenClawRootURL(using: config).appendingPathComponent("openclaw.json", isDirectory: false)

        do {
            let root: [String: Any]
            let originalFileData = fileManager.fileExists(atPath: configURL.path) ? try Data(contentsOf: configURL) : nil

            if let originalFileData {
                guard let parsedRoot = (try JSONSerialization.jsonObject(with: originalFileData)) as? [String: Any] else {
                    return (nil, "本地 OpenClaw 配置存在，但根对象无法解析，未能自动同步 runtime agent 配置。")
                }
                root = parsedRoot
            } else {
                root = [:]
            }

            let agents = (root["agents"] as? [String: Any]) ?? [:]
            let list = (agents["list"] as? [[String: Any]]) ?? []
            return (
                LocalRuntimeConfigBatchContext(
                    configURL: configURL,
                    root: root,
                    list: list,
                    originalFileData: originalFileData
                ),
                nil
            )
        } catch {
            return (nil, "读取本地 OpenClaw 配置失败：\(error.localizedDescription)")
        }
    }

    private func applyLocalRuntimeConfigBatchMutation(
        _ context: inout LocalRuntimeConfigBatchContext,
        configIndex: Int? = nil,
        identifier: String,
        name: String,
        workspacePath: String?,
        agentDirPath: String?,
        modelIdentifier: String?,
        updateModel: Bool = true
    ) -> LocalRuntimeConfigBatchMutationResult {
        let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIdentifier.isEmpty else {
            return LocalRuntimeConfigBatchMutationResult(
                success: false,
                message: "同步本地 runtime agent 配置失败：缺少有效的 agent 标识。",
                changed: false
            )
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let desiredName = trimmedName.isEmpty ? trimmedIdentifier : trimmedName
        let trimmedWorkspacePath: String? = {
            let trimmed = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }()
        let trimmedAgentDirPath = canonicalLocalRuntimePath(agentDirPath)
        let trimmedModelIdentifier: String? = {
            let trimmed = modelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }()
        let normalizedWorkspacePath = canonicalLocalRuntimePath(trimmedWorkspacePath)
        let normalizedAgentDirPath = canonicalLocalRuntimePath(trimmedAgentDirPath)
        let normalizedIdentifier = normalizeAgentKey(trimmedIdentifier)

        let exactMatchingIndices = context.list.enumerated().compactMap { index, item in
            let existingIdentifier = normalizeAgentKey(stringValue(item, keys: ["id", "agentID", "agentId"]) ?? "")
            return existingIdentifier == normalizedIdentifier ? index : nil
        }

        let canonicalIndex: Int?
        if let configIndex, configIndex >= 0, configIndex < context.list.count {
            canonicalIndex = configIndex
        } else {
            if exactMatchingIndices.count > 1 {
                return LocalRuntimeConfigBatchMutationResult(
                    success: false,
                    message: "openclaw.json 中存在多条 id 为 \(trimmedIdentifier) 的 agent 记录，已停止自动写入以避免污染配置。",
                    changed: false
                )
            }
            canonicalIndex = exactMatchingIndices.first
        }

        var entry: [String: Any] = canonicalIndex.flatMap { index in
            guard index >= 0 && index < context.list.count else { return nil }
            return context.list[index]
        } ?? [:]
        var updatedFields: [String] = []

        if (stringValue(entry, keys: ["id"]) ?? "") != trimmedIdentifier {
            entry["id"] = trimmedIdentifier
            updatedFields.append("id")
        }

        if (stringValue(entry, keys: ["name"]) ?? "") != desiredName {
            entry["name"] = desiredName
            updatedFields.append("name")
        }

        if let normalizedWorkspacePath,
           (stringValue(entry, keys: ["workspace"]) ?? "") != normalizedWorkspacePath {
            entry["workspace"] = normalizedWorkspacePath
            updatedFields.append("workspace")
        }

        if let normalizedAgentDirPath,
           (stringValue(entry, keys: ["agentDir"]) ?? "") != normalizedAgentDirPath {
            entry["agentDir"] = normalizedAgentDirPath
            updatedFields.append("agentDir")
        }

        if updateModel,
           let trimmedModelIdentifier,
           (stringValue(entry, keys: ["model"]) ?? "") != trimmedModelIdentifier {
            entry["model"] = trimmedModelIdentifier
            updatedFields.append("model")
        }

        if let canonicalIndex {
            context.list[canonicalIndex] = entry
        } else {
            context.list.append(entry)
            updatedFields.append("new")
        }

        guard !updatedFields.isEmpty else {
            return LocalRuntimeConfigBatchMutationResult(success: true, message: "", changed: false)
        }

        context.verifications.append(
            LocalRuntimeConfigBatchVerification(
                identifier: trimmedIdentifier,
                expectedWorkspacePath: normalizedWorkspacePath,
                expectedAgentDirPath: normalizedAgentDirPath
            )
        )

        var messageParts: [String] = []
        if updatedFields.contains("new") {
            messageParts.append("已写入本地 runtime agent \(trimmedIdentifier) 的 canonical 配置。")
        } else {
            let displayFields = updatedFields.filter { $0 != "new" }
            if !displayFields.isEmpty {
                messageParts.append("已同步本地 runtime agent \(trimmedIdentifier) 的 \(displayFields.joined(separator: "、")) 配置。")
            }
        }

        return LocalRuntimeConfigBatchMutationResult(
            success: true,
            message: messageParts.joined(separator: " "),
            changed: true
        )
    }

    private func commitLocalRuntimeConfigBatch(
        _ context: inout LocalRuntimeConfigBatchContext
    ) -> LocalRuntimeConfigBatchMutationResult {
        guard context.hasPendingChanges else {
            return LocalRuntimeConfigBatchMutationResult(success: true, message: "", changed: false)
        }

        var root = context.root
        var agents = (root["agents"] as? [String: Any]) ?? [:]
        agents["list"] = context.list
        root["agents"] = agents

        do {
            try writeOpenClawConfigRoot(root, to: context.configURL)
            cachedLocalWorkspaceMap = [:]
            cachedLocalWorkspaceConfigModificationDate = nil

            let refreshedEntries = readLocalAgentConfigEntries(at: context.configURL)
            for verification in context.verifications {
                let normalizedIdentifier = normalizeAgentKey(verification.identifier)
                let exactEntries = refreshedEntries.filter {
                    normalizeAgentKey($0.id ?? "") == normalizedIdentifier
                }
                guard exactEntries.count == 1, let selectedEntry = exactEntries.first else {
                    if let originalFileData = context.originalFileData {
                        try? originalFileData.write(to: context.configURL, options: .atomic)
                    } else {
                        try? fileManager.removeItem(at: context.configURL)
                    }
                    return LocalRuntimeConfigBatchMutationResult(
                        success: false,
                        message: "已尝试批量写回本地 runtime agent 配置，但回读校验未通过：未找到 \(verification.identifier) 的唯一精确 id 记录，已回滚本次写入。",
                        changed: false
                    )
                }

                if let expectedWorkspacePath = verification.expectedWorkspacePath,
                   canonicalLocalRuntimePath(selectedEntry.workspacePath) != expectedWorkspacePath {
                    if let originalFileData = context.originalFileData {
                        try? originalFileData.write(to: context.configURL, options: .atomic)
                    } else {
                        try? fileManager.removeItem(at: context.configURL)
                    }
                    return LocalRuntimeConfigBatchMutationResult(
                        success: false,
                        message: "已尝试批量写回本地 runtime agent 配置，但回读校验未通过：\(verification.identifier) 的 workspace 未收敛到 runtime 目标路径，已回滚本次写入。",
                        changed: false
                    )
                }

                if let expectedAgentDirPath = verification.expectedAgentDirPath,
                   canonicalLocalRuntimePath(selectedEntry.agentDirPath) != expectedAgentDirPath {
                    if let originalFileData = context.originalFileData {
                        try? originalFileData.write(to: context.configURL, options: .atomic)
                    } else {
                        try? fileManager.removeItem(at: context.configURL)
                    }
                    return LocalRuntimeConfigBatchMutationResult(
                        success: false,
                        message: "已尝试批量写回本地 runtime agent 配置，但回读校验未通过：\(verification.identifier) 的 agentDir 未收敛到 runtime 目标路径，已回滚本次写入。",
                        changed: false
                    )
                }
            }

            context.root = root
            context.verifications.removeAll()
            return LocalRuntimeConfigBatchMutationResult(success: true, message: "", changed: true)
        } catch {
            return LocalRuntimeConfigBatchMutationResult(
                success: false,
                message: "批量写回本地 runtime agent 配置失败：\(error.localizedDescription)",
                changed: false
            )
        }
    }

    private func synchronizeLocalRuntimeAgentConfigEntry(
        configIndex: Int? = nil,
        identifier: String,
        name: String,
        workspacePath: String?,
        agentDirPath: String?,
        modelIdentifier: String?,
        updateModel: Bool = true
    ) -> (success: Bool, message: String) {
        let configURL = resolveLocalOpenClawConfigURL()
            ?? localOpenClawRootURL().appendingPathComponent("openclaw.json", isDirectory: false)

        do {
            let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedIdentifier.isEmpty else {
                return (false, "同步本地 runtime agent 配置失败：缺少有效的 agent 标识。")
            }

            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let desiredName = trimmedName.isEmpty ? trimmedIdentifier : trimmedName
            let trimmedWorkspacePath: String? = {
                let trimmed = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }()
            let trimmedAgentDirPath: String? = {
                canonicalLocalRuntimePath(agentDirPath)
            }()
            let trimmedModelIdentifier: String? = {
                let trimmed = modelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }()
            let normalizedWorkspacePath = canonicalLocalRuntimePath(trimmedWorkspacePath)
            let normalizedAgentDirPath = canonicalLocalRuntimePath(trimmedAgentDirPath)

            var root: [String: Any]
            if fileManager.fileExists(atPath: configURL.path) {
                let data = try Data(contentsOf: configURL)
                guard let parsedRoot = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    return (false, "本地 OpenClaw 配置存在，但根对象无法解析，未能自动同步 runtime agent 配置。")
                }
                root = parsedRoot
            } else {
                root = [:]
            }
            var agents = (root["agents"] as? [String: Any]) ?? [:]
            var list = (agents["list"] as? [[String: Any]]) ?? []

            let normalizedIdentifier = normalizeAgentKey(trimmedIdentifier)
            let exactMatchingIndices = list.enumerated().compactMap { index, item in
                let existingIdentifier = normalizeAgentKey(stringValue(item, keys: ["id", "agentID", "agentId"]) ?? "")
                return existingIdentifier == normalizedIdentifier ? index : nil
            }

            let canonicalIndex: Int?
            if let configIndex, configIndex >= 0, configIndex < list.count {
                canonicalIndex = configIndex
            } else {
                if exactMatchingIndices.count > 1 {
                    return (false, "openclaw.json 中存在多条 id 为 \(trimmedIdentifier) 的 agent 记录，已停止自动写入以避免污染配置。")
                }
                canonicalIndex = exactMatchingIndices.first
            }

            var entry: [String: Any] = canonicalIndex.flatMap { index in
                guard index >= 0 && index < list.count else { return nil }
                return list[index]
            } ?? [:]
            var updatedFields: [String] = []
            let originalFileData = fileManager.fileExists(atPath: configURL.path) ? try Data(contentsOf: configURL) : nil

            if (stringValue(entry, keys: ["id"]) ?? "") != trimmedIdentifier {
                entry["id"] = trimmedIdentifier
                updatedFields.append("id")
            }

            if (stringValue(entry, keys: ["name"]) ?? "") != desiredName {
                entry["name"] = desiredName
                updatedFields.append("name")
            }

            if let normalizedWorkspacePath,
               (stringValue(entry, keys: ["workspace"]) ?? "") != normalizedWorkspacePath {
                entry["workspace"] = normalizedWorkspacePath
                updatedFields.append("workspace")
            }

            if let normalizedAgentDirPath,
               (stringValue(entry, keys: ["agentDir"]) ?? "") != normalizedAgentDirPath {
                entry["agentDir"] = normalizedAgentDirPath
                updatedFields.append("agentDir")
            }

            if updateModel,
               let trimmedModelIdentifier,
               (stringValue(entry, keys: ["model"]) ?? "") != trimmedModelIdentifier {
                entry["model"] = trimmedModelIdentifier
                updatedFields.append("model")
            }

            if let canonicalIndex {
                list[canonicalIndex] = entry
            } else {
                list.append(entry)
                updatedFields.append("new")
            }

            guard !updatedFields.isEmpty else {
                return (true, "")
            }

            agents["list"] = list
            root["agents"] = agents

            try writeOpenClawConfigRoot(root, to: configURL)
            cachedLocalWorkspaceMap = [:]
            cachedLocalWorkspaceConfigModificationDate = nil

            let refreshedEntries = readLocalAgentConfigEntries(at: configURL)
            let exactEntries = refreshedEntries.filter { normalizeAgentKey($0.id ?? "") == normalizedIdentifier }
            guard exactEntries.count == 1, let selectedEntry = exactEntries.first else {
                if let originalFileData {
                    try? originalFileData.write(to: configURL, options: .atomic)
                } else {
                    try? fileManager.removeItem(at: configURL)
                }
                return (false, "已尝试写回本地 runtime agent \(trimmedIdentifier) 配置，但回读校验未通过：未找到唯一精确 id 记录，已回滚本次写入。")
            }

            if let normalizedWorkspacePath,
               canonicalLocalRuntimePath(selectedEntry.workspacePath) != normalizedWorkspacePath {
                if let originalFileData {
                    try? originalFileData.write(to: configURL, options: .atomic)
                } else {
                    try? fileManager.removeItem(at: configURL)
                }
                return (false, "已尝试写回本地 runtime agent \(trimmedIdentifier) 配置，但回读校验未通过：workspace 未收敛到 runtime 目标路径，已回滚本次写入。")
            }

            if let normalizedAgentDirPath,
               canonicalLocalRuntimePath(selectedEntry.agentDirPath) != normalizedAgentDirPath {
                if let originalFileData {
                    try? originalFileData.write(to: configURL, options: .atomic)
                } else {
                    try? fileManager.removeItem(at: configURL)
                }
                return (false, "已尝试写回本地 runtime agent \(trimmedIdentifier) 配置，但回读校验未通过：agentDir 未收敛到 runtime 目标路径，已回滚本次写入。")
            }

            var messageParts: [String] = []
            if updatedFields.contains("new") {
                messageParts.append("已写入本地 runtime agent \(trimmedIdentifier) 的 canonical 配置。")
            } else {
                let displayFields = updatedFields.filter { $0 != "new" }
                if !displayFields.isEmpty {
                    messageParts.append("已同步本地 runtime agent \(trimmedIdentifier) 的 \(displayFields.joined(separator: "、")) 配置。")
                }
            }

            return (true, messageParts.joined(separator: " "))
        } catch {
            return (false, "同步本地 runtime agent \(identifier) 配置失败：\(error.localizedDescription)")
        }
    }

    private func parseLocalAgentConfigEntries(from list: [[String: Any]]) -> [LocalAgentConfigEntry] {
        list.enumerated().map { index, entry in
            LocalAgentConfigEntry(
                configIndex: index,
                id: stringValue(entry, keys: ["id", "agentID", "agentId"]),
                name: stringValue(entry, keys: ["name", "displayName", "agentName"]),
                workspacePath: stringValue(entry, keys: ["workspace", "workspacePath", "workdir", "workPath"]),
                agentDirPath: stringValue(entry, keys: ["agentDir", "agentDirPath", "directory", "agentDirectory"]),
                modelIdentifier: stringValue(entry, keys: ["model", "modelIdentifier", "primaryModel", "defaultModel"])
            )
        }
    }

    private func localAgentConfigEntryMatches(
        _ entry: LocalAgentConfigEntry,
        normalizedIdentifier: String,
        normalizedName: String,
        normalizedWorkspacePath: String?,
        normalizedAgentDirPath: String?
    ) -> Bool {
        if entry.candidateKeys.contains(normalizedIdentifier) {
            return true
        }

        if !normalizedName.isEmpty, entry.candidateKeys.contains(normalizedName) {
            return true
        }

        if let normalizedWorkspacePath,
           normalizeWorkspacePath(entry.workspacePath ?? "") == normalizedWorkspacePath {
            return true
        }

        if let normalizedAgentDirPath,
           normalizeWorkspacePath(entry.agentDirPath ?? "") == normalizedAgentDirPath {
            return true
        }

        return false
    }

    private func bestLocalAgentConfigCanonicalIndex(
        _ matchingIndices: [Int],
        in list: [[String: Any]],
        normalizedIdentifier: String,
        normalizedName: String,
        normalizedWorkspacePath: String?,
        normalizedAgentDirPath: String?
    ) -> Int? {
        matchingIndices.max { lhs, rhs in
            localAgentConfigCanonicalScore(
                for: list[lhs],
                normalizedIdentifier: normalizedIdentifier,
                normalizedName: normalizedName,
                normalizedWorkspacePath: normalizedWorkspacePath,
                normalizedAgentDirPath: normalizedAgentDirPath
            ) < localAgentConfigCanonicalScore(
                for: list[rhs],
                normalizedIdentifier: normalizedIdentifier,
                normalizedName: normalizedName,
                normalizedWorkspacePath: normalizedWorkspacePath,
                normalizedAgentDirPath: normalizedAgentDirPath
            )
        }
    }

    private func localAgentConfigCanonicalScore(
        for entry: [String: Any],
        normalizedIdentifier: String,
        normalizedName: String,
        normalizedWorkspacePath: String?,
        normalizedAgentDirPath: String?
    ) -> Int {
        let normalizedEntryID = normalizeAgentKey(stringValue(entry, keys: ["id", "agentID", "agentId"]) ?? "")
        let normalizedEntryName = normalizeAgentKey(stringValue(entry, keys: ["name", "displayName", "agentName"]) ?? "")
        let normalizedEntryWorkspacePath = normalizeWorkspacePath(
            stringValue(entry, keys: ["workspace", "workspacePath", "workdir", "workPath"]) ?? ""
        )
        let normalizedEntryAgentDirPath = normalizeWorkspacePath(
            stringValue(entry, keys: ["agentDir", "agentDirPath", "directory", "agentDirectory"]) ?? ""
        )

        var score = 0
        if normalizedEntryID == normalizedIdentifier {
            score += 100
        }
        if !normalizedName.isEmpty, normalizedEntryName == normalizedName {
            score += 60
        }
        if let normalizedWorkspacePath,
           normalizedEntryWorkspacePath == normalizedWorkspacePath {
            score += 30
        }
        if let normalizedAgentDirPath,
           normalizedEntryAgentDirPath == normalizedAgentDirPath {
            score += 20
        }
        if normalizedEntryWorkspacePath != nil {
            score += 5
        }
        if normalizedEntryAgentDirPath != nil {
            score += 3
        }
        return score
    }

    private func loadInstalledSkills(
        forWorkspacePath workspacePath: String?,
        using config: OpenClawConfig
    ) -> [ManagedAgentSkillRecord] {
        guard let workspacePath, !workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        switch config.deploymentKind {
        case .local:
            let skillsPath = URL(fileURLWithPath: workspacePath, isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true)
            guard let contents = try? FileManager.default.contentsOfDirectory(at: skillsPath, includingPropertiesForKeys: [.isDirectoryKey]) else {
                return []
            }

            return contents.compactMap { item in
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey])
                if values?.isDirectory == true {
                    return ManagedAgentSkillRecord(name: item.lastPathComponent, path: item.path)
                }
                if item.pathExtension.lowercased() == "md" {
                    return ManagedAgentSkillRecord(name: item.deletingPathExtension().lastPathComponent, path: item.path)
                }
                return nil
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .container:
            guard let containerName = containerName(for: config) else { return [] }

            let skillsPath = URL(fileURLWithPath: workspacePath, isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true)
                .path

            let script = """
            if [ -d \(shellQuoted(skillsPath)) ]; then
              find \(shellQuoted(skillsPath)) -mindepth 1 -maxdepth 1 -print 2>/dev/null
            fi
            """

            guard let result = try? runDeploymentCommand(
                using: config,
                arguments: ["exec", containerName, "sh", "-lc", script]
            ), result.terminationStatus == 0 else {
                return []
            }

            let paths = parsePlainTextList(from: result.standardOutput)
            return paths.map {
                ManagedAgentSkillRecord(name: URL(fileURLWithPath: $0).lastPathComponent, path: $0)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .remoteServer:
            return []
        }
    }

    private func parsePlainTextList(from data: Data) -> [String] {
        let output = String(data: data, encoding: .utf8)?
            .replacingOccurrences(of: "\\n", with: "\n") ?? ""
        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty && !isDiagnosticOutputLine(line)
            }
    }

    private func parseClawHubSkillRecords(from data: Data) -> [ClawHubSkillRecord] {
        let lines = parsePlainTextList(from: data)
        var records: [ClawHubSkillRecord] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("NAME") || line.hasPrefix("SLUG") {
                continue
            }
            if line.allSatisfy({ $0 == "-" || $0 == "|" }) {
                continue
            }

            if line.contains("|") {
                let columns = line
                    .split(separator: "|")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if let slug = columns.first, !slug.isEmpty {
                    let summary = columns.dropFirst().joined(separator: " | ")
                    records.append(ClawHubSkillRecord(slug: slug, summary: summary))
                    continue
                }
            }

            if let range = line.range(of: " - ") {
                let slug = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let summary = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !slug.isEmpty {
                    records.append(ClawHubSkillRecord(slug: slug, summary: summary))
                    continue
                }
            }

            let parts = line
                .split(maxSplits: 1, omittingEmptySubsequences: true) { $0 == " " || $0 == "\t" }
                .map(String.init)
            if let slug = parts.first, !slug.isEmpty {
                let summary = parts.count > 1 ? parts[1].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) : ""
                records.append(ClawHubSkillRecord(slug: slug, summary: summary))
            }
        }

        var seen = Set<String>()
        return records
            .filter { seen.insert($0.slug.lowercased()).inserted }
            .sorted { $0.slug.localizedCaseInsensitiveCompare($1.slug) == .orderedAscending }
    }

    private func filterSkillRecords(_ records: [ClawHubSkillRecord], with query: String) -> [ClawHubSkillRecord] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return records }

        return records.filter { record in
            record.slug.lowercased().contains(normalizedQuery) || record.summary.lowercased().contains(normalizedQuery)
        }
    }

    private func dictionaryArray(in value: Any) -> [[String: Any]]? {
        if let array = value as? [[String: Any]] {
            return array
        }

        if let dictionary = value as? [String: Any] {
            for key in ["agents", "list", "items", "data"] {
                if let nested = dictionary[key], let nestedArray = dictionaryArray(in: nested) {
                    return nestedArray
                }
            }
        }

        return nil
    }

    private func mergeManagedAgents(
        for project: MAProject,
        runtimeRecords: [ManagedAgentRecord],
        using config: OpenClawConfig
    ) -> [ManagedAgentRecord] {
        let detectedRecords = project.openClaw.detectedAgents.isEmpty ? discoveryResults : project.openClaw.detectedAgents

        return project.agents.map { projectAgent in
            let candidateKeys = managedAgentLookupKeys(for: projectAgent)
            let runtimeRecord = runtimeRecords.first { runtime in
                candidateKeys.contains(normalizeAgentKey(runtime.targetIdentifier))
                    || candidateKeys.contains(normalizeAgentKey(runtime.name))
            }
            let detectedRecord = detectedRecords.first { record in
                candidateKeys.contains(normalizeAgentKey(record.name))
            }

            let resolvedPaths = resolveManagedAgentPaths(
                for: projectAgent,
                runtimeRecord: runtimeRecord,
                detectedRecord: detectedRecord
            )

            let runtimeModel = runtimeRecord?.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let projectModel = projectAgent.openClawDefinition.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelIdentifier = runtimeModel.isEmpty ? projectModel : runtimeModel

            return ManagedAgentRecord(
                id: projectAgent.id.uuidString,
                projectAgentID: projectAgent.id,
                configIndex: runtimeRecord?.configIndex,
                name: projectAgent.name,
                targetIdentifier: normalizedTargetIdentifier(for: projectAgent),
                agentDirPath: resolvedPaths.agentDirPath,
                workspacePath: resolvedPaths.workspacePath,
                modelIdentifier: modelIdentifier,
                installedSkills: loadInstalledSkills(
                    forWorkspacePath: resolvedPaths.workspacePath,
                    using: config
                )
            )
        }
    }

    private func managedAgentLookupKeys(for agent: Agent) -> Set<String> {
        var keys = Set<String>()
        let identifier = normalizedTargetIdentifier(for: agent)
        if !identifier.isEmpty {
            keys.insert(normalizeAgentKey(identifier))
        }
        let normalizedName = normalizeAgentKey(agent.name)
        if !normalizedName.isEmpty {
            keys.insert(normalizedName)
        }
        return keys
    }

    private func normalizedTargetIdentifier(for agent: Agent) -> String {
        let identifier = agent.openClawDefinition.agentIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return identifier.isEmpty ? agent.name : identifier
    }

    private func resolveManagedAgentPaths(
        for projectAgent: Agent,
        runtimeRecord: ManagedAgentRecord?,
        detectedRecord: ProjectOpenClawDetectedAgentRecord?
    ) -> (agentDirPath: String?, workspacePath: String?) {
        let projectPaths = resolveProjectManagedAgentPaths(for: projectAgent, detectedRecord: detectedRecord)
        let workspacePath = firstNonEmptyPath(
            runtimeRecord?.workspacePath,
            projectPaths.workspacePath,
            detectedRecord?.workspacePath
        )
        let agentDirPath = firstNonEmptyPath(
            runtimeRecord?.agentDirPath,
            projectPaths.agentDirPath,
            detectedRecord?.directoryPath
        )
        return (agentDirPath, workspacePath)
    }

    private func resolveProjectManagedAgentPaths(
        for projectAgent: Agent,
        detectedRecord: ProjectOpenClawDetectedAgentRecord?
    ) -> (agentDirPath: String?, workspacePath: String?) {
        if let memoryBackupPath = firstNonEmptyPath(projectAgent.openClawDefinition.memoryBackupPath) {
            let privateURL = URL(fileURLWithPath: memoryBackupPath, isDirectory: true)
            let agentRoot = privateURL.lastPathComponent == "private" ? privateURL.deletingLastPathComponent() : privateURL
            let workspaceURL = agentRoot.appendingPathComponent("workspace", isDirectory: true)

            return (
                agentDirPath: FileManager.default.fileExists(atPath: privateURL.path) ? privateURL.path : nil,
                workspacePath: FileManager.default.fileExists(atPath: workspaceURL.path) ? workspaceURL.path : nil
            )
        }

        if let copiedRootPath = firstNonEmptyPath(detectedRecord?.copiedToProjectPath) {
            let copiedRootURL = URL(fileURLWithPath: copiedRootPath, isDirectory: true)
            let privateURL = copiedRootURL.appendingPathComponent("private", isDirectory: true)
            let workspaceURL = copiedRootURL.appendingPathComponent("workspace", isDirectory: true)

            return (
                agentDirPath: FileManager.default.fileExists(atPath: privateURL.path) ? privateURL.path : nil,
                workspacePath: FileManager.default.fileExists(atPath: workspaceURL.path) ? workspaceURL.path : nil
            )
        }

        return (nil, nil)
    }

    private func firstNonEmptyPath(_ candidates: String?...) -> String? {
        for candidate in candidates {
            guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                continue
            }
            return trimmed
        }
        return nil
    }

    private func isDiagnosticOutputLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }
        if trimmed.hasPrefix("[plugins]") || trimmed.hasPrefix("Config warnings:") {
            return true
        }
        if trimmed.hasPrefix("- plugins.") || trimmed.contains("duplicate plugin id detected") {
            return true
        }
        return false
    }

    private func extractJSONPayload(from data: Data) -> Data? {
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        let characters = Array(output)

        for startIndex in characters.indices {
            let opening = characters[startIndex]
            guard opening == "[" || opening == "{" else { continue }

            var stack: [Character] = [opening]
            var isInsideString = false
            var isEscaping = false

            for index in characters.index(after: startIndex)..<characters.endIndex {
                let character = characters[index]

                if isInsideString {
                    if isEscaping {
                        isEscaping = false
                    } else if character == "\\" {
                        isEscaping = true
                    } else if character == "\"" {
                        isInsideString = false
                    }
                    continue
                }

                if character == "\"" {
                    isInsideString = true
                    continue
                }

                if character == "[" || character == "{" {
                    stack.append(character)
                    continue
                }

                if character == "]" || character == "}" {
                    guard let last = stack.last else { break }
                    let matches = (last == "[" && character == "]") || (last == "{" && character == "}")
                    guard matches else { break }
                    stack.removeLast()

                    if stack.isEmpty {
                        let payload = String(characters[startIndex...index])
                        guard let payloadData = payload.data(using: .utf8) else { return nil }
                        if (try? JSONSerialization.jsonObject(with: payloadData)) != nil {
                            return payloadData
                        }
                        break
                    }
                }
            }
        }

        return nil
    }

    private func runOpenClawCommand(
        using config: OpenClawConfig,
        arguments: [String],
        standardInput: FileHandle? = nil,
        timeoutSeconds: TimeInterval? = nil
    ) throws -> (terminationStatus: Int32, standardOutput: Data, standardError: Data) {
        try host.runOpenClawCommand(
            using: config,
            arguments: arguments,
            standardInput: standardInput,
            timeoutSeconds: timeoutSeconds
        )
    }

    private func runClawHubCommand(
        using config: OpenClawConfig,
        arguments: [String],
        standardInput: FileHandle? = nil,
        timeoutSeconds: TimeInterval? = nil
    ) throws -> (terminationStatus: Int32, standardOutput: Data, standardError: Data) {
        try host.runClawHubCommand(
            using: config,
            arguments: arguments,
            standardInput: standardInput,
            timeoutSeconds: timeoutSeconds
        )
    }

    private func mergeImportedRecords(_ importedRecords: [ProjectOpenClawDetectedAgentRecord]) -> [ProjectOpenClawDetectedAgentRecord] {
        var merged = discoveryResults
        for imported in importedRecords {
            if let index = merged.firstIndex(where: { $0.id == imported.id }) {
                merged[index] = imported
            } else {
                merged.append(imported)
            }
        }
        return merged.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func fallbackLocalOpenClawRootURL() -> URL {
        host.fallbackLocalOpenClawRootURL()
    }

    func resolveLocalOpenClawConfigURL(
        using config: OpenClawConfig? = nil,
        allowFallback: Bool = true
    ) -> URL? {
        let resolvedConfig = config ?? self.config
        guard resolvedConfig.deploymentKind == .local else { return nil }
        if resolvedConfig.usesManagedLocalRuntime,
           let runtimeRootPath = managedRuntimeStatus.runtimeRootPath?
                .trimmingCharacters(in: .whitespacesAndNewlines),
           !runtimeRootPath.isEmpty {
            return URL(fileURLWithPath: runtimeRootPath, isDirectory: true)
                .appendingPathComponent("openclaw.json", isDirectory: false)
        }
        return host.resolveLocalOpenClawConfigURL(
            using: resolvedConfig,
            allowFallback: allowFallback
        )
    }

    func localOpenClawRootURL(using config: OpenClawConfig? = nil) -> URL {
        let resolvedConfig = config ?? self.config
        if resolvedConfig.usesManagedLocalRuntime,
           let runtimeRootPath = managedRuntimeStatus.runtimeRootPath?
                .trimmingCharacters(in: .whitespacesAndNewlines),
           !runtimeRootPath.isEmpty {
            return URL(fileURLWithPath: runtimeRootPath, isDirectory: true)
        }
        return resolveLocalOpenClawConfigURL(using: resolvedConfig)?
            .deletingLastPathComponent() ?? fallbackLocalOpenClawRootURL()
    }

    func ensureLocalDefaultAgentAuthFallback(
        using config: OpenClawConfig? = nil
    ) -> (success: Bool, message: String) {
        let resolvedConfig = config ?? self.config
        guard resolvedConfig.deploymentKind == .local else {
            return (true, "")
        }

        let mainAgentDirectory = localOpenClawRootURL(using: resolvedConfig)
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent("main", isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
        let mainAuthProfilesURL = mainAgentDirectory.appendingPathComponent("auth-profiles.json", isDirectory: false)
        let mainModelsURL = mainAgentDirectory.appendingPathComponent("models.json", isDirectory: false)
        let needsAuthProfiles = !fileManager.fileExists(atPath: mainAuthProfilesURL.path)
        let needsModels = !fileManager.fileExists(atPath: mainModelsURL.path)

        guard needsAuthProfiles || needsModels else {
            return (true, "")
        }

        guard let bootstrapCandidate = preferredLocalAgentBootstrapCandidate(excluding: ["main"], using: resolvedConfig) else {
            if needsAuthProfiles {
                return (false, "本地默认 agent main 缺少 auth-profiles.json，且当前未找到可复用的本地 agent 鉴权配置。")
            }
            return (true, "")
        }

        do {
            try fileManager.createDirectory(at: mainAgentDirectory, withIntermediateDirectories: true)

            var copiedItems: [String] = []

            if needsAuthProfiles, let sourceAuthProfilesURL = bootstrapCandidate.authProfilesURL {
                if fileManager.fileExists(atPath: mainAuthProfilesURL.path) {
                    try fileManager.removeItem(at: mainAuthProfilesURL)
                }
                try fileManager.copyItem(at: sourceAuthProfilesURL, to: mainAuthProfilesURL)
                copiedItems.append("auth-profiles.json")
            }

            if needsModels, let sourceModelsURL = bootstrapCandidate.modelsURL {
                if fileManager.fileExists(atPath: mainModelsURL.path) {
                    try fileManager.removeItem(at: mainModelsURL)
                }
                try fileManager.copyItem(at: sourceModelsURL, to: mainModelsURL)
                copiedItems.append("models.json")
            }

            if needsAuthProfiles && !fileManager.fileExists(atPath: mainAuthProfilesURL.path) {
                return (false, "本地默认 agent main 缺少 auth-profiles.json，且未能从其他本地 agent 自动补齐。")
            }

            guard !copiedItems.isEmpty else {
                return (true, "")
            }

            return (
                true,
                "已为本地默认 agent main 自动补齐 \(copiedItems.joined(separator: "、"))，来源于\(bootstrapCandidate.sourceDescription)。"
            )
        } catch {
            return (false, "为本地默认 agent main 自动补齐鉴权配置失败：\(error.localizedDescription)")
        }
    }

    private func performLocalRuntimeAgentRegistration(
        for agent: Agent,
        in project: MAProject? = nil,
        workflowID: UUID? = nil,
        cachedRuntimeRecords: [ManagedAgentRecord]? = nil,
        cachedBindingRecords: [ManagedAgentBindingRecord]? = nil,
        using config: OpenClawConfig? = nil
    ) -> LocalRuntimeAgentRegistrationReport {
        let resolvedConfig = config ?? self.config
        var stageReports: [LocalRuntimeRegistrationStageReport] = []

        func appendStage(
            _ stage: LocalRuntimeRegistrationStage,
            _ status: LocalRuntimeRegistrationStageStatus,
            changed: Bool = false,
            detail: String? = nil
        ) {
            stageReports.append(
                LocalRuntimeRegistrationStageReport(
                    stage: stage,
                    status: status,
                    changed: changed,
                    detail: detail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? detail : nil
                )
            )
        }

        func makeReport(
            success: Bool,
            identifier: String,
            message: String,
            bootstrapPathRequired: Bool,
            workspaceRequirement: LocalRuntimeWorkspaceRequirement?
        ) -> LocalRuntimeAgentRegistrationReport {
            LocalRuntimeAgentRegistrationReport(
                agentName: agent.name,
                identifier: identifier,
                success: success,
                message: message,
                bootstrapPathRequired: bootstrapPathRequired,
                workspaceRequirement: workspaceRequirement,
                stageReports: stageReports
            )
        }

        guard resolvedConfig.deploymentKind == .local else {
            let identifier = normalizedTargetIdentifier(for: agent).trimmingCharacters(in: .whitespacesAndNewlines)
            return makeReport(
                success: true,
                identifier: identifier,
                message: "",
                bootstrapPathRequired: false,
                workspaceRequirement: nil
            )
        }

        let identifier = normalizedTargetIdentifier(for: agent).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else {
            appendStage(.workspaceResolution, .failed, detail: "当前节点缺少可用的本地 runtime agent 标识。")
            return makeReport(
                success: false,
                identifier: "",
                message: "当前节点缺少可用的本地 runtime agent 标识。",
                bootstrapPathRequired: false,
                workspaceRequirement: nil
            )
        }

        let runtimeRecords: [ManagedAgentRecord]
        if let cachedRuntimeRecords {
            runtimeRecords = cachedRuntimeRecords
        } else {
            do {
                runtimeRecords = try loadManagedRuntimeRecords(using: resolvedConfig)
            } catch {
                let message = "读取本地 OpenClaw agent 列表失败：\(error.localizedDescription)"
                appendStage(.runtimeRecognition, .failed, detail: message)
                return makeReport(
                    success: false,
                    identifier: identifier,
                    message: message,
                    bootstrapPathRequired: false,
                    workspaceRequirement: nil
                )
            }
        }
        let bindingRecords = cachedBindingRecords ?? (try? loadAllManagedAgentBindings(using: resolvedConfig)) ?? []

        let workspaceRequirement: LocalRuntimeWorkspaceRequirement? = {
            guard let project,
                  let binding = nodeBinding(for: agent.id, in: project, workflowID: workflowID) else {
                return nil
            }

            return LocalRuntimeWorkspaceRequirement(
                agentID: agent.id,
                workflowID: binding.workflowID,
                nodeID: binding.nodeID,
                agentName: agent.name,
                targetIdentifier: identifier,
                diagnosticMessage: unresolvedWorkspaceDiagnosticMessage(for: agent, in: project, workflowID: workflowID)
            )
        }()

        func combineMessages(_ parts: String?...) -> String {
            parts
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }

        if runtimeRecords.contains(where: {
            normalizeAgentKey($0.targetIdentifier) == normalizeAgentKey(identifier)
                || normalizeAgentKey($0.name) == normalizeAgentKey(identifier)
        }), let matchedRecord = runtimeRecords.first(where: {
            normalizeAgentKey($0.targetIdentifier) == normalizeAgentKey(identifier)
                || normalizeAgentKey($0.name) == normalizeAgentKey(identifier)
        }) {
            appendStage(.runtimeRecognition, .succeeded, detail: "已匹配到现有本地 runtime agent \(matchedRecord.targetIdentifier)。")
            let runtimeAgentDirectory = firstNonEmptyPath(matchedRecord.agentDirPath)
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? localOpenClawRootURL(using: resolvedConfig)
                    .appendingPathComponent("agents", isDirectory: true)
                    .appendingPathComponent(identifier, isDirectory: true)
                    .appendingPathComponent("agent", isDirectory: true)
            let runtimeWorkspaceURL = localRuntimeAgentWorkspaceURL(
                for: identifier,
                using: resolvedConfig
            )
            let workspaceSourcePath = firstNonEmptyPath(
                resolvedWorkspaceSourcePath(for: agent, in: project, workflowID: workflowID),
                matchedRecord.workspacePath
            )
            if let workspaceSourcePath {
                let workspaceSync = synchronizeLocalRuntimeWorkspace(
                    from: workspaceSourcePath,
                    to: runtimeWorkspaceURL,
                    identifier: matchedRecord.targetIdentifier
                )
                appendStage(.workspaceResolution, workspaceSync.success ? .succeeded : .failed, changed: !workspaceSync.message.isEmpty, detail: workspaceSync.message)
                guard workspaceSync.success else {
                    return makeReport(
                        success: false,
                        identifier: matchedRecord.targetIdentifier,
                        message: workspaceSync.message,
                        bootstrapPathRequired: false,
                        workspaceRequirement: nil
                    )
                }
            }
            let desiredModelIdentifier = qualifiedLocalRuntimeModelIdentifier(
                agent.openClawDefinition.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? matchedRecord.modelIdentifier
                    : agent.openClawDefinition.modelIdentifier,
                preferredAgentDirectory: runtimeAgentDirectory
            )
            let bootstrap = ensureLocalRuntimeAgentBootstrapFiles(
                at: runtimeAgentDirectory,
                displayIdentifier: matchedRecord.targetIdentifier,
                using: resolvedConfig
            )
            let syncResult = synchronizeLocalRuntimeAgentConfigEntry(
                configIndex: matchedRecord.configIndex,
                identifier: identifier,
                name: agent.openClawDefinition.agentIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? matchedRecord.name
                    : agent.openClawDefinition.agentIdentifier,
                workspacePath: runtimeWorkspaceURL.path,
                agentDirPath: runtimeAgentDirectory.path,
                modelIdentifier: desiredModelIdentifier
            )
            appendStage(.canonicalConfig, syncResult.success ? .succeeded : .failed, changed: !syncResult.message.isEmpty, detail: syncResult.message)
            let activation = applyLocalRuntimeActivationPlan(
                for: agent,
                in: project,
                workflowID: workflowID,
                runtimeRecord: matchedRecord,
                runtimeRecords: runtimeRecords,
                bindingRecords: bindingRecords,
                currentBindings: currentManagedAgentBindings(
                    forAgentIdentifier: matchedRecord.targetIdentifier,
                    from: bindingRecords
                ),
                allowSeedFromOtherAgents: false,
                using: resolvedConfig
            )
            appendStage(.bootstrap, bootstrap.success ? .succeeded : .failed, changed: !bootstrap.message.isEmpty, detail: bootstrap.message)
            appendStage(.activation, activation.success ? .succeeded : .failed, changed: !activation.message.isEmpty, detail: activation.message)
            let combinedMessages = combineMessages(
                stageReports.last(where: { $0.stage == .workspaceResolution })?.detail,
                syncResult.message,
                bootstrap.message,
                activation.message
            )
            return makeReport(
                success: bootstrap.success && syncResult.success && activation.success,
                identifier: matchedRecord.targetIdentifier,
                message: combinedMessages,
                bootstrapPathRequired: bootstrap.requiresUserProvidedBootstrapPath,
                workspaceRequirement: nil
            )
        }

        guard let workspaceSourcePath = resolvedWorkspaceSourcePath(for: agent, in: project, workflowID: workflowID)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !workspaceSourcePath.isEmpty else {
            let diagnosticMessage = unresolvedWorkspaceDiagnosticMessage(for: agent, in: project, workflowID: workflowID)
            let baseMessage = "本地 workflow agent \(identifier) 尚未解析到可用 workspace，因此无法自动注册到 OpenClaw CLI。"
            let message = [baseMessage, diagnosticMessage].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            appendStage(.workspaceResolution, .failed, detail: message)
            return makeReport(
                success: false,
                identifier: identifier,
                message: message,
                bootstrapPathRequired: false,
                workspaceRequirement: workspaceRequirement
            )
        }
        let runtimeWorkspaceURL = localRuntimeAgentWorkspaceURL(for: identifier, using: resolvedConfig)
        let workspaceSync = synchronizeLocalRuntimeWorkspace(
            from: workspaceSourcePath,
            to: runtimeWorkspaceURL,
            identifier: identifier
        )
        appendStage(.workspaceResolution, workspaceSync.success ? .succeeded : .failed, changed: !workspaceSync.message.isEmpty, detail: workspaceSync.message)
        guard workspaceSync.success else {
            return makeReport(
                success: false,
                identifier: identifier,
                message: workspaceSync.message,
                bootstrapPathRequired: false,
                workspaceRequirement: workspaceRequirement
            )
        }

        let agentDirectory = localOpenClawRootURL(using: resolvedConfig)
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
        let modelIdentifier = qualifiedLocalRuntimeModelIdentifier(
            agent.openClawDefinition.modelIdentifier,
            preferredAgentDirectory: agentDirectory
        )

        let configSyncResult = synchronizeLocalRuntimeAgentConfigEntry(
            identifier: identifier,
            name: agent.openClawDefinition.agentIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? agent.name
                : agent.openClawDefinition.agentIdentifier,
            workspacePath: runtimeWorkspaceURL.path,
            agentDirPath: agentDirectory.path,
            modelIdentifier: nil,
            updateModel: false
        )
        guard configSyncResult.success else {
            appendStage(.canonicalConfig, .failed, changed: !configSyncResult.message.isEmpty, detail: configSyncResult.message)
            return makeReport(
                success: false,
                identifier: identifier,
                message: configSyncResult.message,
                bootstrapPathRequired: false,
                workspaceRequirement: nil
            )
        }
        appendStage(.canonicalConfig, .succeeded, changed: !configSyncResult.message.isEmpty, detail: configSyncResult.message)

        if let refreshedRuntimeRecords = try? loadManagedRuntimeRecords(using: resolvedConfig),
           let refreshedRuntimeRecord = refreshedRuntimeRecords.first(where: {
               normalizeAgentKey($0.targetIdentifier) == normalizeAgentKey(identifier)
                   || normalizeAgentKey($0.name) == normalizeAgentKey(identifier)
           }) {
            appendStage(.runtimeRecognition, .succeeded, detail: "canonical 配置已被本地 runtime 识别为 agent \(refreshedRuntimeRecord.targetIdentifier)。")
            let refreshedBindingRecords = (try? loadAllManagedAgentBindings(using: resolvedConfig)) ?? bindingRecords
            let bootstrap = ensureLocalRuntimeAgentBootstrapFiles(
                at: agentDirectory,
                displayIdentifier: refreshedRuntimeRecord.targetIdentifier,
                using: resolvedConfig
            )
            let activation = applyLocalRuntimeActivationPlan(
                for: agent,
                in: project,
                workflowID: workflowID,
                runtimeRecord: refreshedRuntimeRecord,
                runtimeRecords: refreshedRuntimeRecords,
                bindingRecords: refreshedBindingRecords,
                currentBindings: currentManagedAgentBindings(
                    forAgentIdentifier: refreshedRuntimeRecord.targetIdentifier,
                    from: refreshedBindingRecords
                ),
                allowSeedFromOtherAgents: true,
                using: resolvedConfig
            )
            appendStage(.bootstrap, bootstrap.success ? .succeeded : .failed, changed: !bootstrap.message.isEmpty, detail: bootstrap.message)
            appendStage(.activation, activation.success ? .succeeded : .failed, changed: !activation.message.isEmpty, detail: activation.message)
            return makeReport(
                success: bootstrap.success && activation.success,
                identifier: refreshedRuntimeRecord.targetIdentifier,
                message: combineMessages(configSyncResult.message, bootstrap.message, activation.message),
                bootstrapPathRequired: bootstrap.requiresUserProvidedBootstrapPath,
                workspaceRequirement: nil
            )
        }
        appendStage(.runtimeRecognition, .skipped, detail: "canonical 配置已写入，但当前 runtime 尚未直接识别该 agent，准备走 CLI add 兼容兜底。")

        var arguments = [
            "agents", "add", identifier,
            "--workspace", runtimeWorkspaceURL.path,
            "--agent-dir", agentDirectory.path,
            "--non-interactive",
            "--json"
        ]
        if !modelIdentifier.isEmpty {
            arguments.append(contentsOf: ["--model", modelIdentifier])
        }

        do {
            let result = try runOpenClawCommand(using: resolvedConfig, arguments: arguments)
            guard result.terminationStatus == 0 else {
                let stderr = String(data: result.standardError, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let stdout = String(data: result.standardOutput, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let detail = !stderr.isEmpty ? stderr : stdout
                let message = "自动注册本地 workflow agent \(identifier) 失败：\(detail)"
                appendStage(.cliRegistrationFallback, .failed, detail: message)
                return makeReport(
                    success: false,
                    identifier: identifier,
                    message: message,
                    bootstrapPathRequired: false,
                    workspaceRequirement: nil
                )
            }

            let registeredIdentifier = resolvedRegisteredAgentIdentifier(
                from: result.standardOutput,
                fallbackName: identifier,
                using: resolvedConfig
            )
            let registrationMessage = "已将本地 workflow agent \(identifier) 自动注册到 OpenClaw CLI（runtime id: \(registeredIdentifier)）。"
            appendStage(.cliRegistrationFallback, .succeeded, changed: true, detail: registrationMessage)
            let refreshedRuntimeRecords = (try? loadManagedRuntimeRecords(using: resolvedConfig)) ?? runtimeRecords
            let refreshedBindingRecords = (try? loadAllManagedAgentBindings(using: resolvedConfig)) ?? bindingRecords
            let refreshedRuntimeRecord = refreshedRuntimeRecords.first(where: {
                normalizeAgentKey($0.targetIdentifier) == normalizeAgentKey(registeredIdentifier)
                    || normalizeAgentKey($0.name) == normalizeAgentKey(registeredIdentifier)
            })
            let bootstrap = ensureLocalRuntimeAgentBootstrapFiles(
                at: agentDirectory,
                displayIdentifier: registeredIdentifier,
                using: resolvedConfig
            )
            let syncResult = synchronizeLocalRuntimeAgentConfigEntry(
                configIndex: refreshedRuntimeRecord?.configIndex,
                identifier: identifier,
                name: agent.openClawDefinition.agentIdentifier,
                workspacePath: runtimeWorkspaceURL.path,
                agentDirPath: agentDirectory.path,
                modelIdentifier: modelIdentifier
            )
            appendStage(.canonicalConfig, syncResult.success ? .succeeded : .failed, changed: !syncResult.message.isEmpty, detail: syncResult.message)
            let activation = refreshedRuntimeRecord.map {
                applyLocalRuntimeActivationPlan(
                    for: agent,
                    in: project,
                    workflowID: workflowID,
                    runtimeRecord: $0,
                    runtimeRecords: refreshedRuntimeRecords,
                    bindingRecords: refreshedBindingRecords,
                    currentBindings: currentManagedAgentBindings(
                        forAgentIdentifier: $0.targetIdentifier,
                        from: refreshedBindingRecords
                    ),
                    allowSeedFromOtherAgents: true,
                    using: resolvedConfig
                )
            } ?? (success: true, message: "")
            appendStage(.bootstrap, bootstrap.success ? .succeeded : .failed, changed: !bootstrap.message.isEmpty, detail: bootstrap.message)
            if refreshedRuntimeRecord != nil {
                appendStage(.runtimeRecognition, .succeeded, detail: "CLI add 后已识别本地 runtime agent \(registeredIdentifier)。")
            } else {
                appendStage(.runtimeRecognition, .skipped, detail: "CLI add 已返回成功，但本轮未重新识别到 runtime 记录。")
            }
            appendStage(.activation, activation.success ? .succeeded : .failed, changed: !activation.message.isEmpty, detail: activation.message)
            let messageParts = [registrationMessage, configSyncResult.message, bootstrap.message, syncResult.message, activation.message]
                .filter { !$0.isEmpty }
            return makeReport(
                success: bootstrap.success && syncResult.success && activation.success,
                identifier: registeredIdentifier,
                message: messageParts.joined(separator: " "),
                bootstrapPathRequired: bootstrap.requiresUserProvidedBootstrapPath,
                workspaceRequirement: nil
            )
        } catch {
            let message = "自动注册本地 workflow agent \(identifier) 失败：\(error.localizedDescription)"
            appendStage(.cliRegistrationFallback, .failed, detail: message)
            return makeReport(
                success: false,
                identifier: identifier,
                message: message,
                bootstrapPathRequired: false,
                workspaceRequirement: nil
            )
        }
    }

    func ensureLocalRuntimeAgentRegistration(
        for agent: Agent,
        in project: MAProject? = nil,
        workflowID: UUID? = nil,
        cachedRuntimeRecords: [ManagedAgentRecord]? = nil,
        cachedBindingRecords: [ManagedAgentBindingRecord]? = nil,
        using config: OpenClawConfig? = nil
    ) -> (
        success: Bool,
        identifier: String,
        message: String,
        bootstrapPathRequired: Bool,
        workspaceRequirement: LocalRuntimeWorkspaceRequirement?
    ) {
        let report = performLocalRuntimeAgentRegistration(
            for: agent,
            in: project,
            workflowID: workflowID,
            cachedRuntimeRecords: cachedRuntimeRecords,
            cachedBindingRecords: cachedBindingRecords,
            using: config
        )
        return (
            report.success,
            report.identifier,
            report.message,
            report.bootstrapPathRequired,
            report.workspaceRequirement
        )
    }

    func localAgentSoulURL(matching candidateNames: [String]) -> URL? {
        if let existing = existingLocalAgentSoulURL(matching: candidateNames) {
            return existing
        }

        guard let workspacePath = localAgentWorkspacePath(matching: candidateNames) else {
            return nil
        }

        return preferredSoulURL(in: URL(fileURLWithPath: workspacePath, isDirectory: true))
    }

    func localAgentWorkspacePath(matching candidateNames: [String]) -> String? {
        let resolution = resolveLocalAgentConfigResolution(matching: candidateNames)
        guard resolution.status == .uniqueValid else { return nil }
        return resolution.selectedEntry?.workspacePath
    }

    func workspaceIsolationConflicts(for agents: [Agent]) -> [WorkspaceIsolationConflict] {
        var agentsByPath: [String: [Agent]] = [:]
        var displayPathByNormalizedPath: [String: String] = [:]

        for agent in agents {
            guard let workspacePath = resolvedWorkspacePath(for: agent),
                  let normalizedPath = normalizeWorkspacePath(workspacePath) else {
                continue
            }

            agentsByPath[normalizedPath, default: []].append(agent)
            displayPathByNormalizedPath[normalizedPath] = workspacePath
        }

        return agentsByPath
            .compactMap { entry in
                let uniqueAgents = Array(Set(entry.value)).sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                guard uniqueAgents.count > 1 else { return nil }

                let identifiers = uniqueAgents.map { agent in
                    let identifier = agent.openClawDefinition.agentIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
                    return identifier.isEmpty ? agent.name : identifier
                }

                return WorkspaceIsolationConflict(
                    normalizedPath: entry.key,
                    displayPath: displayPathByNormalizedPath[entry.key] ?? entry.key,
                    agentNames: uniqueAgents.map(\.name),
                    agentIdentifiers: identifiers
                )
            }
            .sorted { lhs, rhs in
                lhs.displayPath.localizedCaseInsensitiveCompare(rhs.displayPath) == .orderedAscending
            }
    }

    func workspaceIsolationConflicts(for workflow: Workflow, agents: [Agent]) -> [WorkspaceIsolationConflict] {
        let agentByID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        let workflowAgents = workflow.nodes.compactMap { node in
            node.agentID.flatMap { agentByID[$0] }
        }
        return workspaceIsolationConflicts(for: workflowAgents)
    }

    func runtimeIsolationAssessment(
        for workflow: Workflow,
        agents: [Agent],
        using config: OpenClawConfig? = nil
    ) -> RuntimeIsolationAssessment {
        let resolvedConfig = config ?? self.config
        let agentByID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        var seenAgentIDs = Set<UUID>()
        let workflowAgents = workflow.nodes.compactMap { node -> Agent? in
            guard let agentID = node.agentID,
                  seenAgentIDs.insert(agentID).inserted else {
                return nil
            }
            return agentByID[agentID]
        }

        let missingWorkspaceAgents = workflowAgents.filter { agent in
            guard let workspacePath = resolvedWorkspacePath(for: agent),
                  normalizeWorkspacePath(workspacePath) != nil else {
                return true
            }
            return false
        }

        return RuntimeIsolationAssessment(
            workflowAgents: workflowAgents,
            missingWorkspaceAgents: missingWorkspaceAgents,
            workspaceConflicts: workspaceIsolationConflicts(for: workflowAgents),
            remoteMultiAgentBlocked: resolvedConfig.deploymentKind == .remoteServer && workflowAgents.count > 1,
            runtimeSecurityMessages: runtimeSecurityMessages(for: workflowAgents, using: resolvedConfig)
        )
    }

    func resolvedWorkspacePath(
        for agent: Agent,
        in project: MAProject? = nil,
        workflowID: UUID? = nil
    ) -> String? {
        if let managedWorkspace = projectManagedWorkspacePath(for: agent, in: project, workflowID: workflowID) {
            return managedWorkspace
        }

        if let userProvidedWorkspace = userProvidedLocalWorkspacePath(for: agent, in: project, workflowID: workflowID) {
            return userProvidedWorkspace
        }

        let candidateNames = [
            agent.openClawDefinition.agentIdentifier,
            agent.name
        ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let localWorkspace = localAgentWorkspacePath(matching: candidateNames) {
            return localWorkspace
        }

        let normalizedNames = Set(candidateNames.map(normalizeAgentKey))
        if !normalizedNames.isEmpty,
           let record = discoveryResults.first(where: { normalizedNames.contains(normalizeAgentKey($0.name)) }) {
            return firstNonEmptyPath(record.workspacePath, record.directoryPath, record.copiedToProjectPath)
        }

        return nil
    }

    private func projectManagedWorkspacePath(
        for agent: Agent,
        in project: MAProject? = nil,
        workflowID: UUID? = nil
    ) -> String? {
        if let project,
           let managedWorkspaceURL = managedNodeOpenClawWorkspaceURL(for: agent, in: project, workflowID: workflowID) {
            try? FileManager.default.createDirectory(at: managedWorkspaceURL, withIntermediateDirectories: true)
            return managedWorkspaceURL.path
        }

        if let memoryBackupPath = firstNonEmptyPath(agent.openClawDefinition.memoryBackupPath) {
            let privateURL = URL(fileURLWithPath: memoryBackupPath, isDirectory: true)
            let workspaceURL = (privateURL.lastPathComponent == "private"
                ? privateURL.deletingLastPathComponent()
                : privateURL
            ).appendingPathComponent("workspace", isDirectory: true)

            if FileManager.default.fileExists(atPath: workspaceURL.path) {
                return workspaceURL.path
            }
        }

        if let sourcePath = firstNonEmptyPath(agent.openClawDefinition.soulSourcePath) {
            let candidateRoot = URL(fileURLWithPath: sourcePath, isDirectory: false).deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: candidateRoot.path) {
                return candidateRoot.path
            }
        }

        return nil
    }

    private func userProvidedLocalWorkspacePath(
        for agent: Agent,
        in project: MAProject? = nil,
        workflowID: UUID? = nil
    ) -> String? {
        if let project,
           let binding = nodeBinding(for: agent.id, in: project, workflowID: workflowID),
           let url = userProvidedLocalWorkspaceDirectoriesByNodeID[binding.nodeID] {
            return url.path
        }

        if let project {
            let scopedBindings = workflows(in: project, matching: workflowID)
                .flatMap { workflow in
                    workflow.nodes
                        .filter { $0.type == .agent && $0.agentID == agent.id }
                        .map { (workflowID: workflow.id, nodeID: $0.id) }
                }
            if scopedBindings.count <= 1, let url = userProvidedLocalWorkspaceDirectoriesByAgentID[agent.id] {
                return url.path
            }
        }

        if project == nil, let url = userProvidedLocalWorkspaceDirectoriesByAgentID[agent.id] {
            return url.path
        }

        return nil
    }

    private func normalizeWorkspacePath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = URL(fileURLWithPath: trimmed, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : normalized
    }

    private func runtimeSecurityMessages(
        for workflowAgents: [Agent],
        using config: OpenClawConfig
    ) -> [String] {
        guard workflowAgents.count > 1 else { return [] }
        guard config.deploymentKind != .remoteServer else { return [] }

        let dangerousTools: Set<String> = [
            "subagents",
            "sessions_send",
            "sessions_spawn"
        ]

        let approvalsSnapshot: ExecApprovalSnapshot?
        do {
            approvalsSnapshot = try inspectExecApprovalSnapshot(using: config)
        } catch {
            return ["无法读取 OpenClaw exec approvals 配置，当前无法确认 agent 不会通过底层工具绕过软件权限：\(error.localizedDescription)"]
        }

        var messages: [String] = []
        var seenIdentifiers = Set<String>()

        for agent in workflowAgents {
            let identifier = normalizedTargetIdentifier(for: agent).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identifier.isEmpty, seenIdentifiers.insert(identifier.lowercased()).inserted else { continue }

            let inspection: AgentSandboxSecurityInspection
            do {
                inspection = try inspectSandboxSecurity(forAgentIdentifier: identifier, using: config)
            } catch {
                messages.append("无法检查 agent \(identifier) 的 OpenClaw sandbox 策略：\(error.localizedDescription)")
                continue
            }

            if inspection.sandboxMode.lowercased() == "off" || !inspection.sessionIsSandboxed {
                messages.append("agent \(identifier) 的 OpenClaw sandbox 未启用隔离运行，当前无法阻止其在运行时绕过软件自行建立额外会话。")
            }

            let dangerousAllowedTools = Array(inspection.allowedTools.intersection(dangerousTools)).sorted()
            if !dangerousAllowedTools.isEmpty {
                messages.append("agent \(identifier) 当前允许高风险会话工具：\(dangerousAllowedTools.joined(separator: ", "))。请先在 OpenClaw sandbox 中禁用后再运行多 agent 工作流。")
            }

            if approvalsSnapshot?.hasCustomEntries == true,
               inspection.allowedTools.contains("exec") || inspection.allowedTools.contains("process") {
                messages.append("检测到 OpenClaw exec approvals 已配置自定义 allowlist，且 agent \(identifier) 仍可执行本地命令；当前无法证明其不会自行启动额外 agent/session。")
            }

            if inspection.elevatedAllowedByConfig || inspection.elevatedAlwaysAllowedByConfig {
                messages.append("agent \(identifier) 当前允许 OpenClaw elevated 执行策略，存在越过软件编排直接调用底层能力的风险。")
            }
        }

        return Array(Set(messages)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private func writeManagedAgentModel(
        _ model: String,
        for agent: ManagedAgentRecord,
        using config: OpenClawConfig
    ) throws {
        guard let configIndex = agent.configIndex else {
            throw NSError(
                domain: "OpenClawManager",
                code: 1302,
                userInfo: [NSLocalizedDescriptionKey: "未找到 \(agent.name) 对应的 OpenClaw 运行时配置，无法直接写回。"]
            )
        }

        let result = try runOpenClawCommand(
            using: config,
            arguments: ["config", "set", "agents.list[\(configIndex)].model", model]
        )

        guard result.terminationStatus == 0 else {
            let fallback = String(data: result.standardError, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw NSError(
                domain: "OpenClawManager",
                code: Int(result.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "更新 agent model 失败" : fallback]
            )
        }
    }

    private func loadManagedRuntimeRecords(using config: OpenClawConfig) throws -> [ManagedAgentRecord] {
        let result = try runOpenClawCommand(using: config, arguments: ["agents", "list", "--json"])
        guard result.terminationStatus == 0 else {
            let fallback = String(data: result.standardError, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw NSError(
                domain: "OpenClawManager",
                code: Int(result.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "读取 OpenClaw agents 失败" : fallback]
            )
        }
        return parseManagedAgents(from: result.standardOutput, using: config)
    }

    private func loadAllManagedAgentBindings(using config: OpenClawConfig) throws -> [ManagedAgentBindingRecord] {
        let result = try runOpenClawCommand(using: config, arguments: ["agents", "bindings", "--json"])
        guard result.terminationStatus == 0 else {
            let fallback = String(data: result.standardError, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw NSError(
                domain: "OpenClawManager",
                code: Int(result.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "读取 Agent bindings 失败" : fallback]
            )
        }
        return parseManagedAgentBindings(from: result.standardOutput)
    }

    private func loadManagedAgentBindings(
        forAgentIdentifier agentIdentifier: String,
        using config: OpenClawConfig
    ) throws -> [ManagedAgentBindingRecord] {
        let result = try runOpenClawCommand(
            using: config,
            arguments: ["agents", "bindings", "--agent", agentIdentifier, "--json"]
        )
        guard result.terminationStatus == 0 else {
            let fallback = String(data: result.standardError, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw NSError(
                domain: "OpenClawManager",
                code: Int(result.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "读取 Agent bindings 失败" : fallback]
            )
        }
        return parseManagedAgentBindings(from: result.standardOutput)
            .filter { normalizeAgentKey($0.agentIdentifier) == normalizeAgentKey(agentIdentifier) }
    }

    private func currentManagedAgentBindings(
        forAgentIdentifier agentIdentifier: String,
        from bindingRecords: [ManagedAgentBindingRecord]
    ) -> [ManagedAgentBindingRecord] {
        let normalizedIdentifier = normalizeAgentKey(agentIdentifier)
        return bindingRecords.filter {
            normalizeAgentKey($0.agentIdentifier) == normalizedIdentifier
        }
    }

    private func localRuntimeBindingsUpdateMessage(
        forAgentIdentifier agentIdentifier: String,
        desiredBindings: [AgentRuntimeChannelBinding],
        sourceDescription: String?
    ) -> String {
        if desiredBindings.isEmpty {
            return "已清空 \(agentIdentifier) 的 channel bindings。"
        }
        if let sourceDescription, !sourceDescription.isEmpty {
            return "已为 \(agentIdentifier) 自动沿用\(sourceDescription) 的 channel bindings。"
        }
        return "已为 \(agentIdentifier) 写入 channel bindings。"
    }

    private func executeLocalRuntimeBindingsBatchPlan(
        _ planItems: [LocalRuntimeBindingsBatchPlanItem],
        using config: OpenClawConfig
    ) -> LocalRuntimeBindingsBatchExecutionResult {
        var result = LocalRuntimeBindingsBatchExecutionResult()

        for planItem in planItems.sorted(by: {
            $0.identifier.localizedCaseInsensitiveCompare($1.identifier) == .orderedAscending
        }) {
            let normalizedIdentifier = normalizeAgentKey(planItem.identifier)
            let currentSet = Set(planItem.currentBindings.map(\.binding))
            let desiredBindings = uniqueBindings(planItem.desiredBindings)
            let desiredSet = Set(desiredBindings)

            if currentSet == desiredSet {
                result.statesByIdentifier[normalizedIdentifier] = .applied(message: nil)
                continue
            }

            do {
                try applyManagedAgentBindings(
                    forAgentIdentifier: planItem.identifier,
                    currentBindings: planItem.currentBindings,
                    desiredBindings: desiredBindings,
                    using: config
                )
                result.statesByIdentifier[normalizedIdentifier] = .applied(
                    message: localRuntimeBindingsUpdateMessage(
                        forAgentIdentifier: planItem.identifier,
                        desiredBindings: desiredBindings,
                        sourceDescription: planItem.sourceDescription
                    )
                )
            } catch {
                result.statesByIdentifier[normalizedIdentifier] = .failed(
                    message: "为本地 workflow agent \(planItem.identifier) 自动补齐 channel 配置失败：\(error.localizedDescription)"
                )
            }
        }

        return result
    }

    private func applyLocalRuntimeActivationBatch(
        _ batchStates: [LocalRuntimeBatchRegistrationState],
        in project: MAProject,
        workflowID: UUID? = nil,
        runtimeRecords: [ManagedAgentRecord],
        initialBindingRecords: [ManagedAgentBindingRecord],
        using config: OpenClawConfig
    ) -> LocalRuntimeActivationBatchProcessingResult {
        let finalBindingRecords: [ManagedAgentBindingRecord]
        do {
            let bindingsResult = try runOpenClawCommand(using: config, arguments: ["agents", "bindings", "--json"])
            if bindingsResult.terminationStatus == 0 {
                finalBindingRecords = parseManagedAgentBindings(from: bindingsResult.standardOutput)
            } else {
                finalBindingRecords = initialBindingRecords
            }
        } catch {
            finalBindingRecords = initialBindingRecords
        }

        let finalBindingRecordsByIdentifier = Dictionary(
            grouping: finalBindingRecords,
            by: { normalizeAgentKey($0.agentIdentifier) }
        )
        let activationModelBatchContextResult = loadLocalRuntimeConfigBatchContext(using: config)
        var activationModelBatchContext = activationModelBatchContextResult.context
        var activationModelBatchAppliedIdentifiers = Set<String>()
        var activationModelBatchMessagesByIdentifier: [String: String] = [:]
        var bindingsBatchPlanItems: [LocalRuntimeBindingsBatchPlanItem] = []
        var preparedActivations: [LocalRuntimePreparedActivation] = []
        var updatedBatchStates = batchStates
        var warnings: [String] = []

        for index in updatedBatchStates.indices {
            var state = updatedBatchStates[index]
            let hasFailedPreparationStage = state.stageReports.contains {
                $0.status == .failed && $0.stage != .activation && $0.stage != .cliRegistrationFallback
            }
            let runtimeRecord = runtimeRecords.first(where: {
                normalizeAgentKey($0.targetIdentifier) == normalizeAgentKey(state.identifier)
                    || normalizeAgentKey($0.name) == normalizeAgentKey(state.identifier)
            })

            if state.initialRuntimeRecord == nil,
               !state.stageReports.contains(where: { $0.stage == .runtimeRecognition && $0.status == .succeeded }) {
                let detail: String
                let status: LocalRuntimeRegistrationStageStatus
                if let runtimeRecord {
                    detail = "canonical 配置已被本地 runtime 识别为 agent \(runtimeRecord.targetIdentifier)。"
                    status = .succeeded
                } else {
                    detail = "批量提交完成后，当前 runtime 仍未识别 agent \(state.identifier)。"
                    status = .skipped
                }
                state.stageReports.append(
                    LocalRuntimeRegistrationStageReport(
                        stage: .runtimeRecognition,
                        status: status,
                        changed: false,
                        detail: detail
                    )
                )
            }

            if !hasFailedPreparationStage, let runtimeRecord {
                let currentBindings = finalBindingRecordsByIdentifier[normalizeAgentKey(runtimeRecord.targetIdentifier)] ?? []
                let activationPlan = localRuntimeActivationPlan(
                    for: state.agent,
                    in: project,
                    workflowID: workflowID,
                    runtimeRecords: runtimeRecords,
                    bindingRecords: finalBindingRecords,
                    allowSeedFromOtherAgents: state.allowSeedFromOtherAgents,
                    using: config
                )

                preparedActivations.append(
                    LocalRuntimePreparedActivation(
                        stateIndex: index,
                        runtimeRecord: runtimeRecord,
                        activationPlan: activationPlan,
                        currentBindings: currentBindings
                    )
                )

                if let desiredBindings = activationPlan.desiredBindings {
                    bindingsBatchPlanItems.append(
                        LocalRuntimeBindingsBatchPlanItem(
                            identifier: runtimeRecord.targetIdentifier,
                            currentBindings: currentBindings,
                            desiredBindings: desiredBindings,
                            sourceDescription: activationPlan.sourceDescription
                        )
                    )
                }

                let normalizedRuntimeIdentifier = normalizeAgentKey(runtimeRecord.targetIdentifier)
                if let desiredModel = activationPlan.modelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !desiredModel.isEmpty,
                   var batchContext = activationModelBatchContext {
                    let runtimeAgentDirectory = firstNonEmptyPath(runtimeRecord.agentDirPath)
                        .map { URL(fileURLWithPath: $0, isDirectory: true) }
                    let qualifiedModelIdentifier = qualifiedLocalRuntimeModelIdentifier(
                        desiredModel,
                        preferredAgentDirectory: runtimeAgentDirectory
                    )
                    let currentModelIdentifier = runtimeRecord.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)

                    if qualifiedModelIdentifier != currentModelIdentifier {
                        let mutation = applyLocalRuntimeConfigBatchMutation(
                            &batchContext,
                            configIndex: runtimeRecord.configIndex,
                            identifier: runtimeRecord.targetIdentifier,
                            name: runtimeRecord.name,
                            workspacePath: firstNonEmptyPath(runtimeRecord.workspacePath, state.runtimeWorkspaceURL.path),
                            agentDirPath: firstNonEmptyPath(runtimeRecord.agentDirPath, state.runtimeAgentDirectory.path),
                            modelIdentifier: qualifiedModelIdentifier
                        )

                        if mutation.success {
                            activationModelBatchContext = batchContext
                            if mutation.changed {
                                activationModelBatchAppliedIdentifiers.insert(normalizedRuntimeIdentifier)
                                activationModelBatchMessagesByIdentifier[normalizedRuntimeIdentifier] = "已为 \(runtimeRecord.targetIdentifier) 写入 model。"
                            }
                        }
                    }
                }
            }

            updatedBatchStates[index] = state
        }

        var activationModelBatchCommitSucceeded = activationModelBatchAppliedIdentifiers.isEmpty
        if var batchContext = activationModelBatchContext, batchContext.hasPendingChanges {
            let commitResult = commitLocalRuntimeConfigBatch(&batchContext)
            activationModelBatchContext = batchContext
            if commitResult.success {
                activationModelBatchCommitSucceeded = true
            } else {
                warnings.append("批量写回本地 runtime agent model 失败，已回退到逐 agent 更新：\(commitResult.message)")
            }
        }

        let bindingsBatchExecutionResult = executeLocalRuntimeBindingsBatchPlan(
            bindingsBatchPlanItems,
            using: config
        )

        for preparedActivation in preparedActivations {
            var state = updatedBatchStates[preparedActivation.stateIndex]
            let normalizedRuntimeIdentifier = normalizeAgentKey(preparedActivation.runtimeRecord.targetIdentifier)
            let modelAlreadyApplied = activationModelBatchCommitSucceeded
                && activationModelBatchAppliedIdentifiers.contains(normalizedRuntimeIdentifier)
            let bindingsApplicationState = bindingsBatchExecutionResult.statesByIdentifier[normalizedRuntimeIdentifier] ?? .pending
            let activation = applyLocalRuntimeActivationPlan(
                for: state.agent,
                in: project,
                workflowID: workflowID,
                runtimeRecord: preparedActivation.runtimeRecord,
                runtimeRecords: runtimeRecords,
                bindingRecords: finalBindingRecords,
                currentBindings: preparedActivation.currentBindings,
                precomputedPlan: preparedActivation.activationPlan,
                modelAlreadyApplied: modelAlreadyApplied,
                preAppliedModelMessage: modelAlreadyApplied
                    ? activationModelBatchMessagesByIdentifier[normalizedRuntimeIdentifier]
                    : nil,
                bindingsApplicationState: bindingsApplicationState,
                allowSeedFromOtherAgents: state.allowSeedFromOtherAgents,
                using: config
            )
            state.stageReports.append(
                LocalRuntimeRegistrationStageReport(
                    stage: .activation,
                    status: activation.success ? .succeeded : .failed,
                    changed: !activation.message.isEmpty,
                    detail: activation.message
                )
            )
            updatedBatchStates[preparedActivation.stateIndex] = state
        }

        return LocalRuntimeActivationBatchProcessingResult(
            batchStates: updatedBatchStates,
            warnings: warnings
        )
    }

    private func applyManagedAgentBindings(
        forAgentIdentifier agentIdentifier: String,
        currentBindings: [ManagedAgentBindingRecord],
        desiredBindings: [AgentRuntimeChannelBinding],
        using config: OpenClawConfig
    ) throws {
        let currentSet = Set(currentBindings.map(\.binding))
        let desiredSet = Set(uniqueBindings(desiredBindings))
        let bindingsToAdd = desiredSet.subtracting(currentSet)
        let bindingsToRemove = currentSet.subtracting(desiredSet)

        if desiredSet.isEmpty, !currentSet.isEmpty {
            let result = try runOpenClawCommand(
                using: config,
                arguments: ["agents", "unbind", "--agent", agentIdentifier, "--all", "--json"]
            )
            guard result.terminationStatus == 0 else {
                let fallback = String(data: result.standardError, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw NSError(
                    domain: "OpenClawManager",
                    code: Int(result.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "移除 Agent bindings 失败" : fallback]
                )
            }
            return
        }

        if !bindingsToRemove.isEmpty {
            let bindSpecs = bindingsToRemove.map(bindingSpec(for:))
            let result = try runOpenClawCommand(
                using: config,
                arguments: ["agents", "unbind", "--agent", agentIdentifier] + bindSpecs.flatMap { ["--bind", $0] } + ["--json"]
            )
            guard result.terminationStatus == 0 else {
                let fallback = String(data: result.standardError, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw NSError(
                    domain: "OpenClawManager",
                    code: Int(result.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "移除 Agent bindings 失败" : fallback]
                )
            }
        }

        if !bindingsToAdd.isEmpty {
            let bindSpecs = bindingsToAdd.map(bindingSpec(for:))
            let result = try runOpenClawCommand(
                using: config,
                arguments: ["agents", "bind", "--agent", agentIdentifier] + bindSpecs.flatMap { ["--bind", $0] } + ["--json"]
            )
            guard result.terminationStatus == 0 else {
                let fallback = String(data: result.standardError, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw NSError(
                    domain: "OpenClawManager",
                    code: Int(result.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "写入 Agent bindings 失败" : fallback]
                )
            }
        }
    }

    private func desiredRuntimeConfiguration(
        for agent: Agent,
        in project: MAProject?,
        workflowID: UUID? = nil
    ) -> AgentRuntimeConfigurationRecord? {
        guard let project else { return nil }
        let bindingNodeID = nodeBinding(for: agent.id, in: project, workflowID: workflowID)?.nodeID
        let matchingRecords = project.openClaw.runtimeConfigurations.filter { $0.agentID == agent.id }
        if let bindingNodeID,
           let exactRecord = matchingRecords.first(where: { $0.nodeID == bindingNodeID }) {
            return exactRecord
        }
        return matchingRecords.first(where: { $0.nodeID == nil }) ?? matchingRecords.first
    }

    private func preferredLocalRuntimeActivationDonor(
        excluding identifier: String,
        runtimeRecords: [ManagedAgentRecord],
        bindingRecords: [ManagedAgentBindingRecord],
        using config: OpenClawConfig
    ) -> LocalRuntimeActivationDonor? {
        let preferredIdentifiers = [
            preferredLocalAgentBootstrapCandidate(excluding: [identifier], using: config)?.identifier,
            "main"
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let excludedKey = normalizeAgentKey(identifier)

        var candidateIdentifiers = preferredIdentifiers
        candidateIdentifiers.append(contentsOf: runtimeRecords.map(\.targetIdentifier))

        var seen = Set<String>()
        for candidateIdentifier in candidateIdentifiers {
            let normalizedCandidate = normalizeAgentKey(candidateIdentifier)
            guard !normalizedCandidate.isEmpty,
                  normalizedCandidate != excludedKey,
                  seen.insert(normalizedCandidate).inserted else {
                continue
            }

            let runtimeRecord = runtimeRecords.first(where: {
                normalizeAgentKey($0.targetIdentifier) == normalizedCandidate
                    || normalizeAgentKey($0.name) == normalizedCandidate
            })
            let bindings = uniqueBindings(
                bindingRecords
                    .filter { normalizeAgentKey($0.agentIdentifier) == normalizedCandidate }
                    .map(\.binding)
            )
            let modelIdentifier = runtimeRecord?.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            if (modelIdentifier?.isEmpty == false) || !bindings.isEmpty {
                return LocalRuntimeActivationDonor(
                    identifier: runtimeRecord?.targetIdentifier ?? candidateIdentifier,
                    modelIdentifier: modelIdentifier,
                    bindings: bindings,
                    sourceDescription: "已注册 agent \(runtimeRecord?.targetIdentifier ?? candidateIdentifier)"
                )
            }
        }

        return nil
    }

    private func localRuntimeActivationPlan(
        for agent: Agent,
        in project: MAProject?,
        workflowID: UUID? = nil,
        runtimeRecords: [ManagedAgentRecord],
        bindingRecords: [ManagedAgentBindingRecord],
        allowSeedFromOtherAgents: Bool,
        using config: OpenClawConfig
    ) -> LocalRuntimeActivationPlan {
        let persistedConfiguration = desiredRuntimeConfiguration(for: agent, in: project, workflowID: workflowID)
        let explicitModel = firstNonEmptyPath(
            persistedConfiguration?.modelIdentifier,
            agent.openClawDefinition.modelIdentifier
        )

        if let persistedConfiguration {
            let desiredBindings = persistedConfiguration.channelEnabled
                ? uniqueBindings(persistedConfiguration.bindings)
                : []
            let shouldWriteBindings = persistedConfiguration.channelEnabled || !persistedConfiguration.bindings.isEmpty
            return LocalRuntimeActivationPlan(
                modelIdentifier: explicitModel,
                desiredBindings: shouldWriteBindings ? desiredBindings : [],
                sourceDescription: shouldWriteBindings ? "项目运行时配置" : nil
            )
        }

        guard allowSeedFromOtherAgents,
              let donor = preferredLocalRuntimeActivationDonor(
                  excluding: normalizedTargetIdentifier(for: agent),
                  runtimeRecords: runtimeRecords,
                  bindingRecords: bindingRecords,
                  using: config
              ) else {
            return LocalRuntimeActivationPlan(
                modelIdentifier: explicitModel,
                desiredBindings: nil,
                sourceDescription: nil
            )
        }

        return LocalRuntimeActivationPlan(
            modelIdentifier: explicitModel ?? donor.modelIdentifier,
            desiredBindings: donor.bindings.isEmpty ? nil : donor.bindings,
            sourceDescription: donor.bindings.isEmpty && explicitModel != nil ? nil : donor.sourceDescription
        )
    }

    private func applyLocalRuntimeActivationPlan(
        for agent: Agent,
        in project: MAProject?,
        workflowID: UUID? = nil,
        runtimeRecord: ManagedAgentRecord,
        runtimeRecords: [ManagedAgentRecord],
        bindingRecords: [ManagedAgentBindingRecord],
        currentBindings: [ManagedAgentBindingRecord]? = nil,
        precomputedPlan: LocalRuntimeActivationPlan? = nil,
        modelAlreadyApplied: Bool = false,
        preAppliedModelMessage: String? = nil,
        bindingsApplicationState: LocalRuntimeBindingsApplicationState = .pending,
        allowSeedFromOtherAgents: Bool,
        using config: OpenClawConfig
    ) -> (success: Bool, message: String) {
        let activationPlan = precomputedPlan ?? localRuntimeActivationPlan(
            for: agent,
            in: project,
            workflowID: workflowID,
            runtimeRecords: runtimeRecords,
            bindingRecords: bindingRecords,
            allowSeedFromOtherAgents: allowSeedFromOtherAgents,
            using: config
        )

        let runtimeAgentDirectory = firstNonEmptyPath(runtimeRecord.agentDirPath)
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        var messages: [String] = []

        do {
            if let desiredModel = activationPlan.modelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
               !desiredModel.isEmpty {
                let qualifiedModelIdentifier = qualifiedLocalRuntimeModelIdentifier(
                    desiredModel,
                    preferredAgentDirectory: runtimeAgentDirectory
                )
                if modelAlreadyApplied {
                    if let preAppliedModelMessage,
                       !preAppliedModelMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        messages.append(preAppliedModelMessage)
                    }
                } else if qualifiedModelIdentifier != runtimeRecord.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines) {
                    try writeManagedAgentModel(qualifiedModelIdentifier, for: runtimeRecord, using: config)
                    messages.append("已为 \(runtimeRecord.targetIdentifier) 写入 model。")
                }
            }

            if let desiredBindings = activationPlan.desiredBindings {
                switch bindingsApplicationState {
                case .pending:
                    let resolvedCurrentBindings: [ManagedAgentBindingRecord]
                    if let currentBindings {
                        resolvedCurrentBindings = currentBindings
                    } else {
                        resolvedCurrentBindings = try loadManagedAgentBindings(
                            forAgentIdentifier: runtimeRecord.targetIdentifier,
                            using: config
                        )
                    }
                    let currentSet = Set(resolvedCurrentBindings.map(\.binding))
                    let desiredSet = Set(uniqueBindings(desiredBindings))
                    if currentSet != desiredSet {
                        try applyManagedAgentBindings(
                            forAgentIdentifier: runtimeRecord.targetIdentifier,
                            currentBindings: resolvedCurrentBindings,
                            desiredBindings: desiredBindings,
                            using: config
                        )
                        messages.append(
                            localRuntimeBindingsUpdateMessage(
                                forAgentIdentifier: runtimeRecord.targetIdentifier,
                                desiredBindings: desiredBindings,
                                sourceDescription: activationPlan.sourceDescription
                            )
                        )
                    }
                case .applied(let message):
                    if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        messages.append(message)
                    }
                case .failed(let message):
                    let combinedMessage = (messages + [message])
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    return (false, combinedMessage.isEmpty ? message : combinedMessage)
                }
            }

            return (true, messages.joined(separator: " "))
        } catch {
            return (false, "为本地 workflow agent \(runtimeRecord.targetIdentifier) 自动补齐 model / channel 配置失败：\(error.localizedDescription)")
        }
    }

    private func bindingSpec(for binding: AgentRuntimeChannelBinding) -> String {
        let channel = binding.channelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = binding.accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !channel.isEmpty else { return "" }
        return account.isEmpty ? channel : "\(channel):\(account)"
    }

    private func uniqueBindings(_ bindings: [AgentRuntimeChannelBinding]) -> [AgentRuntimeChannelBinding] {
        var seen = Set<String>()
        return bindings.filter { binding in
            let key = binding.id
            return !key.isEmpty && seen.insert(key).inserted
        }
    }

    private func parseChannelAccounts(from data: Data) -> [OpenClawChannelAccountRecord] {
        guard
            let jsonData = extractJSONPayload(from: data),
            let jsonObject = try? JSONSerialization.jsonObject(with: jsonData)
        else {
            return []
        }

        var records: [OpenClawChannelAccountRecord] = []
        let reservedContainerKeys: Set<String> = [
            "accounts", "auth", "channels", "chat", "data", "items",
            "providers", "results", "usage", "windows"
        ]

        func appendAccount(channelID: String?, accountID: String?, displayName: String?, isDefault: Bool) {
            guard
                let rawChannelID = channelID?.trimmingCharacters(in: .whitespacesAndNewlines),
                !rawChannelID.isEmpty
            else {
                return
            }

            let normalizedAccountID = accountID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? accountID!.trimmingCharacters(in: .whitespacesAndNewlines)
                : "default"
            let normalizedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            records.append(
                OpenClawChannelAccountRecord(
                    channelID: rawChannelID,
                    accountID: normalizedAccountID,
                    displayName: normalizedDisplayName?.isEmpty == false ? normalizedDisplayName : "\(rawChannelID):\(normalizedAccountID)",
                    isDefaultAccount: isDefault || normalizedAccountID == "default"
                )
            )
        }

        func shouldTreatAsChannelMapKey(_ key: String, value: Any) -> Bool {
            guard !reservedContainerKeys.contains(key.lowercased()) else {
                return false
            }
            return value is [String: Any] || value is [Any]
        }

        func walk(_ value: Any, inheritedChannelID: String?) {
            if let dictionary = value as? [String: Any] {
                let explicitChannelID = stringValue(dictionary, keys: ["channel", "channelId", "channelID"])
                let childChannelID: String?
                if explicitChannelID != nil {
                    childChannelID = explicitChannelID
                } else if dictionary["accounts"] != nil {
                    childChannelID = stringValue(dictionary, keys: ["id", "name", "slug", "type"]) ?? inheritedChannelID
                } else {
                    childChannelID = inheritedChannelID
                }

                let explicitAccountID = stringValue(dictionary, keys: ["account", "accountId", "accountID"])
                    ?? (dictionary["accounts"] == nil ? stringValue(dictionary, keys: ["id"]) : nil)
                let explicitDisplayName = stringValue(dictionary, keys: ["displayName", "label", "title", "name"])
                let isDefaultAccount = (dictionary["isDefault"] as? Bool) == true
                    || (dictionary["default"] as? Bool) == true

                if let childChannelID,
                   let explicitAccountID,
                   dictionary["accounts"] == nil,
                   (dictionary["account"] != nil
                        || dictionary["accountId"] != nil
                        || dictionary["accountID"] != nil
                        || dictionary["isDefault"] != nil
                        || dictionary["default"] != nil
                        || dictionary["displayName"] != nil
                        || dictionary["label"] != nil) {
                    appendAccount(
                        channelID: childChannelID,
                        accountID: explicitAccountID,
                        displayName: explicitDisplayName,
                        isDefault: isDefaultAccount
                    )
                }

                if dictionary["accounts"] == nil,
                   let childChannelID,
                   inheritedChannelID == nil,
                   explicitAccountID == nil,
                   (dictionary["enabled"] != nil || dictionary["status"] != nil || dictionary["health"] != nil) {
                    appendAccount(channelID: childChannelID, accountID: "default", displayName: explicitDisplayName, isDefault: true)
                }

                for (key, child) in dictionary {
                    if key == "accounts", let accountMap = child as? [String: Any] {
                        for (accountKey, accountValue) in accountMap {
                            if let accountDictionary = accountValue as? [String: Any] {
                                appendAccount(
                                    channelID: childChannelID,
                                    accountID: stringValue(accountDictionary, keys: ["account", "accountId", "accountID"]) ?? accountKey,
                                    displayName: stringValue(accountDictionary, keys: ["displayName", "label", "title", "name"]),
                                    isDefault: accountKey == "default"
                                )
                            } else {
                                appendAccount(
                                    channelID: childChannelID,
                                    accountID: accountKey,
                                    displayName: nil,
                                    isDefault: accountKey == "default"
                                )
                            }
                        }
                    } else {
                        let nextInheritedChannelID: String?
                        if let childChannelID {
                            nextInheritedChannelID = childChannelID
                        } else if shouldTreatAsChannelMapKey(key, value: child) {
                            nextInheritedChannelID = key
                        } else {
                            nextInheritedChannelID = inheritedChannelID
                        }
                        walk(child, inheritedChannelID: nextInheritedChannelID)
                    }
                }
            } else if let array = value as? [Any] {
                for child in array {
                    walk(child, inheritedChannelID: inheritedChannelID)
                }
            }
        }

        walk(jsonObject, inheritedChannelID: nil)

        var seen = Set<String>()
        return records
            .filter { seen.insert($0.id).inserted }
            .sorted {
                if $0.channelID == $1.channelID {
                    if $0.isDefaultAccount != $1.isDefaultAccount {
                        return $0.isDefaultAccount
                    }
                    return $0.accountID.localizedCaseInsensitiveCompare($1.accountID) == .orderedAscending
                }
                return $0.channelID.localizedCaseInsensitiveCompare($1.channelID) == .orderedAscending
            }
    }

    private func parseManagedAgentBindings(from data: Data) -> [ManagedAgentBindingRecord] {
        guard
            let jsonData = extractJSONPayload(from: data),
            let jsonObject = try? JSONSerialization.jsonObject(with: jsonData)
        else {
            return []
        }

        var records: [ManagedAgentBindingRecord] = []
        let reservedContainerKeys: Set<String> = [
            "accounts", "bindings", "channels", "chat", "data",
            "items", "results", "routes"
        ]

        func shouldTreatAsAgentMapKey(_ key: String, value: Any) -> Bool {
            guard !reservedContainerKeys.contains(key.lowercased()) else {
                return false
            }
            return value is [String: Any] || value is [Any] || value is String
        }

        func walk(_ value: Any, inheritedAgentIdentifier: String?) {
            if let dictionary = value as? [String: Any] {
                let agentIdentifier = stringValue(dictionary, keys: ["agent", "agentId", "agentID", "agentIdentifier", "target"])
                    ?? inheritedAgentIdentifier
                let channelID = stringValue(dictionary, keys: ["channel", "channelId", "channelID"])
                let accountID = stringValue(dictionary, keys: ["account", "accountId", "accountID"]) ?? "default"

                if let agentIdentifier, let channelID {
                    records.append(
                        ManagedAgentBindingRecord(
                            agentIdentifier: agentIdentifier,
                            channelID: channelID,
                            accountID: accountID
                        )
                    )
                }

                for (key, child) in dictionary {
                    let nextInheritedAgentIdentifier: String?
                    if let agentIdentifier {
                        nextInheritedAgentIdentifier = agentIdentifier
                    } else if shouldTreatAsAgentMapKey(key, value: child) {
                        nextInheritedAgentIdentifier = key
                    } else {
                        nextInheritedAgentIdentifier = inheritedAgentIdentifier
                    }
                    walk(child, inheritedAgentIdentifier: nextInheritedAgentIdentifier)
                }
            } else if let array = value as? [Any] {
                for child in array {
                    walk(child, inheritedAgentIdentifier: inheritedAgentIdentifier)
                }
            } else if let bindingSpec = value as? String,
                      let inheritedAgentIdentifier {
                let components = bindingSpec.split(separator: ":", maxSplits: 1).map(String.init)
                guard let channelID = components.first, !channelID.isEmpty else { return }
                let accountID = components.count > 1 ? components[1] : "default"
                records.append(
                    ManagedAgentBindingRecord(
                        agentIdentifier: inheritedAgentIdentifier,
                        channelID: channelID,
                        accountID: accountID
                    )
                )
            }
        }

        walk(jsonObject, inheritedAgentIdentifier: nil)

        var seen = Set<String>()
        return records.filter { record in
            let key = "\(normalizeAgentKey(record.agentIdentifier))|\(record.channelID)|\(record.accountID)"
            return seen.insert(key).inserted
        }
    }

    private func inspectSandboxSecurity(
        forAgentIdentifier agentIdentifier: String,
        using config: OpenClawConfig
    ) throws -> AgentSandboxSecurityInspection {
        let result = try runOpenClawCommand(
            using: config,
            arguments: ["sandbox", "explain", "--agent", agentIdentifier, "--json"]
        )
        guard result.terminationStatus == 0 else {
            let fallback = String(data: result.standardError, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw NSError(
                domain: "OpenClawManager",
                code: Int(result.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "读取 OpenClaw sandbox 策略失败" : fallback]
            )
        }

        guard let payload = extractJSONPayload(from: result.standardOutput) ?? extractJSONPayload(from: result.standardError),
              let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw NSError(
                domain: "OpenClawManager",
                code: 1201,
                userInfo: [NSLocalizedDescriptionKey: "解析 OpenClaw sandbox explain 输出失败"]
            )
        }

        let sandbox = (object["sandbox"] as? [String: Any]) ?? [:]
        let tools = (sandbox["tools"] as? [String: Any]) ?? [:]
        let elevated = (object["elevated"] as? [String: Any]) ?? [:]
        let allowedTools = ((tools["allow"] as? [String]) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        return AgentSandboxSecurityInspection(
            agentIdentifier: agentIdentifier,
            sandboxMode: ((sandbox["mode"] as? String) ?? "unknown").trimmingCharacters(in: .whitespacesAndNewlines),
            sessionIsSandboxed: (sandbox["sessionIsSandboxed"] as? Bool) ?? false,
            allowedTools: Set(allowedTools),
            elevatedAllowedByConfig: (elevated["allowedByConfig"] as? Bool) ?? false,
            elevatedAlwaysAllowedByConfig: (elevated["alwaysAllowedByConfig"] as? Bool) ?? false
        )
    }

    private func inspectExecApprovalSnapshot(using config: OpenClawConfig) throws -> ExecApprovalSnapshot {
        do {
            let result = try runOpenClawCommand(
                using: config,
                arguments: ["approvals", "get", "--json"]
            )
            guard result.terminationStatus == 0 else {
                let fallback = String(data: result.standardError, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw NSError(
                    domain: "OpenClawManager",
                    code: Int(result.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: fallback.isEmpty ? "读取 OpenClaw exec approvals 失败" : fallback]
                )
            }

            guard let payload = extractJSONPayload(from: result.standardOutput) ?? extractJSONPayload(from: result.standardError),
                  let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
                throw NSError(
                    domain: "OpenClawManager",
                    code: 1202,
                    userInfo: [NSLocalizedDescriptionKey: "解析 OpenClaw approvals get 输出失败"]
                )
            }

            let fileRecord = (object["file"] as? [String: Any]) ?? [:]
            return execApprovalSnapshot(fromApprovalFileRecord: fileRecord)
        } catch {
            if let fallbackSnapshot = try? inspectExecApprovalSnapshotFromGovernanceFiles(using: config) {
                return fallbackSnapshot
            }
            throw error
        }
    }

    private func inspectExecApprovalSnapshotFromGovernanceFiles(using config: OpenClawConfig) throws -> ExecApprovalSnapshot {
        let governancePaths = try resolveOpenClawGovernancePaths(using: config, requiresInspectionRoot: true)
        guard let rootURL = governancePaths.rootURL else {
            throw NSError(
                domain: "OpenClawManager",
                code: 1203,
                userInfo: [NSLocalizedDescriptionKey: "无法解析 OpenClaw governance 根目录"]
            )
        }

        guard let approvalsURL = governancePaths.approvalsURL else {
            return ExecApprovalSnapshot(hasCustomEntries: false)
        }

        guard let approvalsRecord = readOpenClawConfigRecord(at: approvalsURL) else {
            throw NSError(
                domain: "OpenClawManager",
                code: 1204,
                userInfo: [NSLocalizedDescriptionKey: "无法读取 \(rootURL.lastPathComponent)/exec-approvals.json"]
            )
        }

        return execApprovalSnapshot(fromApprovalFileRecord: approvalsRecord)
    }

    func execApprovalSnapshot(fromApprovalFileRecord fileRecord: [String: Any]) -> ExecApprovalSnapshot {
        let defaults = (fileRecord["defaults"] as? [String: Any]) ?? [:]
        let agents = (fileRecord["agents"] as? [String: Any]) ?? [:]

        return ExecApprovalSnapshot(
            hasCustomEntries: !defaults.isEmpty || !agents.isEmpty
        )
    }

    private func existingLocalAgentSoulURL(matching candidateNames: [String]) -> URL? {
        if let workspacePath = localAgentWorkspacePath(matching: candidateNames) {
            let workspaceURL = URL(fileURLWithPath: workspacePath, isDirectory: true)
            if let soulURL = existingSoulURL(in: workspaceURL) {
                return soulURL
            }
        }

        let normalizedNames = Set(candidateNames.map(normalizeAgentKey).filter { !$0.isEmpty })
        if !normalizedNames.isEmpty {
            if let record = discoveryResults.first(where: { normalizedNames.contains(normalizeAgentKey($0.name)) }) {
                if let soulPath = firstNonEmptyPath(record.soulPath) {
                    let soulURL = URL(fileURLWithPath: soulPath, isDirectory: false)
                    if FileManager.default.fileExists(atPath: soulURL.path) {
                        return soulURL
                    }
                }
                if let copiedRoot = firstNonEmptyPath(record.copiedToProjectPath),
                   let soulURL = existingSoulURL(in: URL(fileURLWithPath: copiedRoot, isDirectory: true)) {
                    return soulURL
                }
                if let directoryPath = firstNonEmptyPath(record.directoryPath),
                   let soulURL = existingSoulURL(in: URL(fileURLWithPath: directoryPath, isDirectory: true)) {
                    return soulURL
                }
            }
        }

        return nil
    }

    func applyPendingSoulReconcileResult(to project: inout MAProject) -> SoulReconcileReport? {
        guard let pendingSoulReconcileResult, pendingSoulReconcileResult.projectID == project.id else {
            return nil
        }

        let updatesByAgentID = Dictionary(uniqueKeysWithValues: pendingSoulReconcileResult.updates.map { ($0.agentID, $0) })
        var didChangeProject = false

        for index in project.agents.indices {
            let agentID = project.agents[index].id
            guard let update = updatesByAgentID[agentID] else { continue }

            var didChangeAgent = false

            if let soulMD = update.soulMD, project.agents[index].soulMD != soulMD {
                project.agents[index].soulMD = soulMD
                didChangeAgent = true
            }

            if project.agents[index].openClawDefinition.soulSourcePath != update.soulSourcePath {
                project.agents[index].openClawDefinition.soulSourcePath = update.soulSourcePath
                didChangeAgent = true
            }

            if project.agents[index].openClawDefinition.lastImportedSoulHash != update.lastImportedSoulHash {
                project.agents[index].openClawDefinition.lastImportedSoulHash = update.lastImportedSoulHash
                didChangeAgent = true
            }

            if project.agents[index].openClawDefinition.lastImportedSoulPath != update.lastImportedSoulPath {
                project.agents[index].openClawDefinition.lastImportedSoulPath = update.lastImportedSoulPath
                didChangeAgent = true
            }

            if project.agents[index].openClawDefinition.lastImportedAt != update.lastImportedAt {
                project.agents[index].openClawDefinition.lastImportedAt = update.lastImportedAt
                didChangeAgent = true
            }

            if didChangeAgent {
                project.agents[index].updatedAt = Date()
                didChangeProject = true
            }
        }

        if didChangeProject {
            project.updatedAt = Date()
        }

        let report = pendingSoulReconcileResult.report
        self.pendingSoulReconcileResult = nil
        return report
    }

    private struct SoulReconcileComputation {
        let project: MAProject
        let updates: [SoulReconcileAgentUpdate]
        let report: SoulReconcileReport
        let stagePolicies: [UUID: SoulMirrorStagePolicy]
    }

    private func reconcileProjectAgentsFromSessionBackup(_ project: MAProject) -> SoulReconcileComputation {
        guard let sessionContext else {
            return SoulReconcileComputation(
                project: project,
                updates: [],
                report: SoulReconcileReport(projectID: project.id, agentReports: []),
                stagePolicies: [:]
            )
        }

        var reconciledProject = project
        var updates: [SoulReconcileAgentUpdate] = []
        var reports: [SoulReconcileAgentReport] = []
        var stagePolicies: [UUID: SoulMirrorStagePolicy] = [:]
        let now = Date()

        for index in reconciledProject.agents.indices {
            let agent = reconciledProject.agents[index]
            guard let sourceURL = resolveSessionBackupSoulURL(for: agent, in: project, backupURL: sessionContext.backupURL),
                  let remoteContent = try? String(contentsOf: sourceURL, encoding: .utf8) else {
                reports.append(
                    SoulReconcileAgentReport(
                        agentID: agent.id,
                        agentName: agent.name,
                        status: .missingSource,
                        sourcePath: nil,
                        message: "未在连接前备份中定位到可用的 SOUL 文件。"
                    )
                )
                stagePolicies[agent.id] = .backupContent
                continue
            }

            let localHash = soulContentHash(agent.soulMD)
            let remoteHash = soulContentHash(remoteContent)
            let baselineHash = normalizedNonEmptyString(agent.openClawDefinition.lastImportedSoulHash)
            let sourcePath = sourceURL.path

            if localHash == remoteHash {
                let update = SoulReconcileAgentUpdate(
                    agentID: agent.id,
                    soulMD: nil,
                    soulSourcePath: sourcePath,
                    lastImportedSoulHash: remoteHash,
                    lastImportedSoulPath: sourcePath,
                    lastImportedAt: now
                )
                applySoulReconcileUpdate(update, to: &reconciledProject.agents[index], at: now)
                updates.append(update)
                stagePolicies[agent.id] = .projectContent
                reports.append(
                    SoulReconcileAgentReport(
                        agentID: agent.id,
                        agentName: agent.name,
                        status: .unchanged,
                        sourcePath: sourcePath,
                        message: "本地 SOUL 与 OpenClaw 一致，已刷新同步基线。"
                    )
                )
                continue
            }

            if isPlaceholderSoulContent(agent.soulMD) {
                let update = SoulReconcileAgentUpdate(
                    agentID: agent.id,
                    soulMD: remoteContent,
                    soulSourcePath: sourcePath,
                    lastImportedSoulHash: remoteHash,
                    lastImportedSoulPath: sourcePath,
                    lastImportedAt: now
                )
                applySoulReconcileUpdate(update, to: &reconciledProject.agents[index], at: now)
                updates.append(update)
                stagePolicies[agent.id] = .projectContent
                reports.append(
                    SoulReconcileAgentReport(
                        agentID: agent.id,
                        agentName: agent.name,
                        status: .overwritten,
                        sourcePath: sourcePath,
                        message: "本地 SOUL 仍为默认模板，已自动替换为 OpenClaw 内容。"
                    )
                )
                continue
            }

            if let baselineHash {
                if localHash == baselineHash && remoteHash != baselineHash {
                    let update = SoulReconcileAgentUpdate(
                        agentID: agent.id,
                        soulMD: remoteContent,
                        soulSourcePath: sourcePath,
                        lastImportedSoulHash: remoteHash,
                        lastImportedSoulPath: sourcePath,
                        lastImportedAt: now
                    )
                    applySoulReconcileUpdate(update, to: &reconciledProject.agents[index], at: now)
                    updates.append(update)
                    stagePolicies[agent.id] = .projectContent
                    reports.append(
                        SoulReconcileAgentReport(
                            agentID: agent.id,
                            agentName: agent.name,
                            status: .overwritten,
                            sourcePath: sourcePath,
                            message: "本地自上次同步后未修改，已自动更新为 OpenClaw 最新内容。"
                        )
                    )
                    continue
                }

                if localHash != baselineHash && remoteHash == baselineHash {
                    let update = SoulReconcileAgentUpdate(
                        agentID: agent.id,
                        soulMD: nil,
                        soulSourcePath: sourcePath,
                        lastImportedSoulHash: baselineHash,
                        lastImportedSoulPath: sourcePath,
                        lastImportedAt: agent.openClawDefinition.lastImportedAt
                    )
                    applySoulReconcileUpdate(update, to: &reconciledProject.agents[index], at: now)
                    updates.append(update)
                    stagePolicies[agent.id] = .projectContent
                    reports.append(
                        SoulReconcileAgentReport(
                            agentID: agent.id,
                            agentName: agent.name,
                            status: .keptLocal,
                            sourcePath: sourcePath,
                            message: "检测到仅本地发生修改，已保留本地 SOUL。"
                        )
                    )
                    continue
                }

                if localHash != baselineHash && remoteHash != baselineHash {
                    let update = SoulReconcileAgentUpdate(
                        agentID: agent.id,
                        soulMD: nil,
                        soulSourcePath: sourcePath,
                        lastImportedSoulHash: baselineHash,
                        lastImportedSoulPath: agent.openClawDefinition.lastImportedSoulPath ?? sourcePath,
                        lastImportedAt: agent.openClawDefinition.lastImportedAt
                    )
                    reconciledProject.agents[index].soulMD = remoteContent
                    applySoulReconcileUpdate(update, to: &reconciledProject.agents[index], at: now)
                    updates.append(update)
                    stagePolicies[agent.id] = .backupContent
                    reports.append(
                        SoulReconcileAgentReport(
                            agentID: agent.id,
                            agentName: agent.name,
                            status: .conflict,
                            sourcePath: sourcePath,
                            message: "本地与 OpenClaw 自上次同步后都发生了变化，需由用户手动处理。"
                        )
                    )
                    continue
                }
            }

            let update = SoulReconcileAgentUpdate(
                agentID: agent.id,
                soulMD: nil,
                soulSourcePath: sourcePath,
                lastImportedSoulHash: agent.openClawDefinition.lastImportedSoulHash,
                lastImportedSoulPath: agent.openClawDefinition.lastImportedSoulPath,
                lastImportedAt: agent.openClawDefinition.lastImportedAt
            )
            reconciledProject.agents[index].soulMD = remoteContent
            applySoulReconcileUpdate(update, to: &reconciledProject.agents[index], at: now)
            updates.append(update)
            stagePolicies[agent.id] = .backupContent
            reports.append(
                SoulReconcileAgentReport(
                    agentID: agent.id,
                    agentName: agent.name,
                    status: .conflict,
                    sourcePath: sourcePath,
                    message: "首次同步检测到本地与 OpenClaw 不一致，已保留本地 SOUL，等待用户判断。"
                )
            )
        }

        return SoulReconcileComputation(
            project: reconciledProject,
            updates: updates,
            report: SoulReconcileReport(projectID: project.id, agentReports: reports),
            stagePolicies: stagePolicies
        )
    }

    private func applySoulReconcileUpdate(_ update: SoulReconcileAgentUpdate, to agent: inout Agent, at timestamp: Date) {
        if let soulMD = update.soulMD {
            agent.soulMD = soulMD
        }
        agent.openClawDefinition.soulSourcePath = update.soulSourcePath
        agent.openClawDefinition.lastImportedSoulHash = update.lastImportedSoulHash
        agent.openClawDefinition.lastImportedSoulPath = update.lastImportedSoulPath
        agent.openClawDefinition.lastImportedAt = update.lastImportedAt
        agent.updatedAt = timestamp
    }

    private func resolveSessionBackupSoulURL(for agent: Agent, in project: MAProject, backupURL: URL) -> URL? {
        let candidateNames = Array(
            Set([
                agent.name,
                agent.openClawDefinition.agentIdentifier,
                normalizedTargetIdentifier(for: agent)
            ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        )

        let sourceCandidates = mirrorSourceCandidates(for: agent, in: project, matching: candidateNames)
        for sourceURL in sourceCandidates {
            if let translated = translateURLToBackup(sourceURL, backupURL: backupURL, project: project),
               FileManager.default.fileExists(atPath: translated.path) {
                return translated
            }

            if let translated = lazilyCacheCurrentLocalSoulBaseline(
                from: sourceURL,
                for: project,
                backupURL: backupURL
            ) {
                return translated
            }
        }

        if let backupMatch = findMatchingSoulURL(in: backupURL, matching: candidateNames) {
            return backupMatch
        }

        if let translated = lazilyCacheCurrentLocalSoulBaseline(
            matching: candidateNames,
            for: project,
            backupURL: backupURL
        ) {
            return translated
        }

        return nil
    }

    private func normalizedNonEmptyString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func normalizeSoulContent(_ content: String) -> String {
        var normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        while normalized.hasSuffix("\n\n") {
            normalized.removeLast()
        }

        return normalized
    }

    private func soulContentHash(_ content: String) -> String {
        let normalized = normalizeSoulContent(content)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func isPlaceholderSoulContent(_ content: String) -> Bool {
        let normalized = normalizeSoulContent(content)
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || normalized == normalizeSoulContent("# 新智能体\n这是我的配置...")
    }

    private func stageProjectAgentsIntoMirror(
        _ project: MAProject,
        workflowID: UUID? = nil,
        stagePolicies: [UUID: SoulMirrorStagePolicy] = [:]
    ) -> MirrorStageResult {
        let mirrorURL = ProjectManager.shared.openClawMirrorDirectory(for: project.id)
        let backupURL: URL? = {
            if let sessionContext, sessionContext.projectID == project.id {
                return sessionContext.backupURL
            }
            return ProjectManager.shared.openClawBackupDirectory(for: project.id)
        }()

        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: mirrorURL, withIntermediateDirectories: true)

        let stagingMirrorURL = fileManager.temporaryDirectory
            .appendingPathComponent("openclaw-project-mirror-\(project.id.uuidString)-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: stagingMirrorURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingMirrorURL) }

        var result = MirrorStageResult()
        let workflowAgents = workflowBoundProjectAgents(in: project, workflowID: workflowID)
        let preparationLock = NSLock()
        var preparedStages: [PreparedMirrorAgentStage] = []
        var unresolvedAgentNames: [String] = []

        DispatchQueue.concurrentPerform(iterations: workflowAgents.count) { index in
            let agent = workflowAgents[index]
            let preparedStage = prepareMirrorStageForAgent(
                agent,
                in: project,
                workflowID: workflowID,
                stagePolicy: stagePolicies[agent.id] ?? .projectContent,
                backupURL: backupURL
            )

            preparationLock.lock()
            defer { preparationLock.unlock() }

            if let stage = preparedStage.stage {
                preparedStages.append(stage)
            } else if let agentName = preparedStage.unresolvedAgentName {
                unresolvedAgentNames.append(agentName)
            }
        }

        preparedStages.sort {
            $0.relativeAgentRootPath.localizedCaseInsensitiveCompare($1.relativeAgentRootPath) == .orderedAscending
        }
        result.unresolvedAgentNames = unresolvedAgentNames.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        defer {
            for preparedStage in preparedStages {
                try? fileManager.removeItem(at: preparedStage.temporaryRootURL)
            }
        }

        var stagedAgentRootRelativePaths = Set<String>()
        for preparedStage in preparedStages {
            let destinationAgentRootURL = stagingMirrorURL.appendingPathComponent(
                preparedStage.relativeAgentRootPath,
                isDirectory: true
            )
            try? fileManager.createDirectory(
                at: destinationAgentRootURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            _ = try? replaceDirectoryContents(
                of: destinationAgentRootURL,
                withContentsOf: preparedStage.stagedAgentRootURL
            )
            stagedAgentRootRelativePaths.insert(preparedStage.relativeAgentRootPath)
        }

        let cleanedEntryNames = visibleDirectoryEntryNames(in: mirrorURL)
            .subtracting(visibleDirectoryEntryNames(in: stagingMirrorURL))
            .subtracting(Self.managedSessionMirrorTopLevelEntries)
        result.cleanedEntryNames = Array(cleanedEntryNames).sorted()

        let mirrorChanged = !fileSystemItemsEqual(at: stagingMirrorURL, and: mirrorURL)
        guard mirrorChanged else {
            result.updatedAgentCount = 0
            return result
        }

        for relativeAgentRootPath in stagedAgentRootRelativePaths.sorted() {
            let stagedAgentRootURL = stagingMirrorURL.appendingPathComponent(relativeAgentRootPath, isDirectory: true)
            let currentAgentRootURL = mirrorURL.appendingPathComponent(relativeAgentRootPath, isDirectory: true)
            if !fileSystemItemsEqual(at: stagedAgentRootURL, and: currentAgentRootURL) {
                result.updatedAgentCount += 1
            }
        }

        _ = try? replaceDirectoryContents(of: mirrorURL, withContentsOf: stagingMirrorURL)

        return result
    }

    private func prepareMirrorStageForAgent(
        _ agent: Agent,
        in project: MAProject,
        workflowID: UUID? = nil,
        stagePolicy: SoulMirrorStagePolicy,
        backupURL: URL?
    ) -> (stage: PreparedMirrorAgentStage?, unresolvedAgentName: String?) {
        let fileManager = FileManager.default
        let temporaryRootURL = fileManager.temporaryDirectory
            .appendingPathComponent("openclaw-agent-stage-\(project.id.uuidString)-\(agent.id.uuidString)-\(UUID().uuidString)", isDirectory: true)

        do {
            try fileManager.createDirectory(at: temporaryRootURL, withIntermediateDirectories: true)

            guard let soulURL = resolveProjectMirrorSoulURL(
                for: agent,
                in: project,
                mirrorURL: temporaryRootURL,
                backupURL: backupURL
            ) else {
                try? fileManager.removeItem(at: temporaryRootURL)
                return (nil, agent.name)
            }

            var stagedFromManagedWorkspace = false
            switch try stageManagedWorkspaceDocuments(
                for: agent,
                in: project,
                workflowID: workflowID,
                mirrorSoulURL: soulURL
            ) {
            case .changed:
                stagedFromManagedWorkspace = true
            case .unchanged:
                stagedFromManagedWorkspace = true
            case .noManagedWorkspace:
                break
            }

            if !stagedFromManagedWorkspace {
                let contentToStage: String
                switch stagePolicy {
                case .projectContent:
                    contentToStage = agent.soulMD
                case .backupContent:
                    guard let backupContent = backupSoulContent(
                        for: agent,
                        in: project,
                        mirrorSoulURL: soulURL,
                        mirrorURL: temporaryRootURL,
                        backupURL: backupURL
                    ) else {
                        try? fileManager.removeItem(at: temporaryRootURL)
                        return (nil, agent.name)
                    }
                    contentToStage = backupContent
                }

                _ = try writeTextIfNeeded(contentToStage, to: soulURL)
            }

            guard let relativeAgentRootPath = relativePath(
                of: soulURL.deletingLastPathComponent(),
                from: temporaryRootURL
            ) else {
                try? fileManager.removeItem(at: temporaryRootURL)
                return (nil, agent.name)
            }

            return (
                PreparedMirrorAgentStage(
                    agentName: agent.name,
                    temporaryRootURL: temporaryRootURL,
                    stagedAgentRootURL: soulURL.deletingLastPathComponent(),
                    relativeAgentRootPath: relativeAgentRootPath
                ),
                nil
            )
        } catch {
            try? fileManager.removeItem(at: temporaryRootURL)
            return (nil, agent.name)
        }
    }

    private func stageManagedWorkspaceDocuments(
        for agent: Agent,
        in project: MAProject,
        workflowID: UUID? = nil,
        mirrorSoulURL: URL
    ) throws -> ManagedWorkspaceStageOutcome {
        guard let workspaceURL = managedNodeOpenClawWorkspaceURL(for: agent, in: project, workflowID: workflowID),
              FileManager.default.fileExists(atPath: workspaceURL.path) else {
            return .noManagedWorkspace
        }

        let agentRootURL = mirrorSoulURL.deletingLastPathComponent()
        let workspaceMirrorURL = agentRootURL.appendingPathComponent("workspace", isDirectory: true)

        let existingManagedFiles = ProjectFileSystem.managedOpenClawWorkspaceMarkdownFiles.filter { fileName in
            FileManager.default.fileExists(atPath: workspaceURL.appendingPathComponent(fileName, isDirectory: false).path)
        }

        guard !existingManagedFiles.isEmpty else {
            return .noManagedWorkspace
        }

        let shouldMirrorSoulIntoWorkspace = existingManagedFiles.contains { $0 != "SOUL.md" }
        if shouldMirrorSoulIntoWorkspace {
            try FileManager.default.createDirectory(at: workspaceMirrorURL, withIntermediateDirectories: true)
        }

        var wroteAny = false
        for fileName in existingManagedFiles {
            let sourceURL = workspaceURL.appendingPathComponent(fileName, isDirectory: false)
            let content = try String(contentsOf: sourceURL, encoding: .utf8)
            let targetURLs: [URL]
            if fileName == "SOUL.md" {
                if shouldMirrorSoulIntoWorkspace {
                    targetURLs = [
                        mirrorSoulURL,
                        workspaceMirrorURL.appendingPathComponent(fileName, isDirectory: false)
                    ]
                } else {
                    targetURLs = [mirrorSoulURL]
                }
            } else {
                targetURLs = [workspaceMirrorURL.appendingPathComponent(fileName, isDirectory: false)]
            }

            for targetURL in targetURLs {
                if try writeTextIfNeeded(content, to: targetURL) {
                    wroteAny = true
                }
            }
        }

        return wroteAny ? .changed : .unchanged
    }

    private func managedNodeOpenClawWorkspaceURL(
        for agent: Agent,
        in project: MAProject,
        workflowID: UUID? = nil
    ) -> URL? {
        guard let binding = nodeBinding(for: agent.id, in: project, workflowID: workflowID) else { return nil }

        return ProjectFileSystem.shared.nodeOpenClawWorkspaceDirectory(
            for: binding.nodeID,
            workflowID: binding.workflowID,
            projectID: project.id,
            under: ProjectManager.shared.appSupportRootDirectory
        )
    }

    private func nodeBinding(
        for agentID: UUID,
        in project: MAProject,
        workflowID: UUID? = nil
    ) -> (workflowID: UUID, nodeID: UUID)? {
        for workflow in workflows(in: project, matching: workflowID) {
            if let node = workflow.nodes.first(where: { $0.type == .agent && $0.agentID == agentID }) {
                return (workflow.id, node.id)
            }
        }
        return nil
    }

    private func workflows(in project: MAProject, matching workflowID: UUID? = nil) -> [Workflow] {
        guard let workflowID else {
            return project.workflows
        }

        guard let workflow = project.workflows.first(where: { $0.id == workflowID }) else {
            return []
        }

        return [workflow]
    }

    private func applySessionMirrorToDeployment() throws {
        guard let sessionContext else { return }
        try ensureSessionDeploymentBackup()

        switch sessionContext.deployment.deploymentKind {
        case .local:
            guard let openClawRoot = sessionContext.deployment.localRootURL else {
                throw NSError(
                    domain: "OpenClawManager",
                    code: 15,
                    userInfo: [NSLocalizedDescriptionKey: "无法解析本地 OpenClaw 路径"]
                )
            }
            try applyManagedSessionMirrorContents(
                from: sessionContext.mirrorURL,
                deploymentRootPath: openClawRoot.path,
                using: sessionContext.deployment.config
            )
        case .container:
            guard let deploymentRootPath = sessionContext.deployment.deploymentRootPath else {
                throw NSError(
                    domain: "OpenClawManager",
                    code: 15,
                    userInfo: [NSLocalizedDescriptionKey: "无法解析容器内 OpenClaw 路径"]
                )
            }
            try applyManagedSessionMirrorContents(
                from: sessionContext.mirrorURL,
                deploymentRootPath: deploymentRootPath,
                using: sessionContext.deployment.config
            )
        case .remoteServer:
            break
        }

        sessionDeploymentModified = true
        markSessionSynchronized()
    }

    private func ensureSessionDeploymentBackup() throws {
        guard let sessionContext else { return }
        guard !sessionDeploymentBackupPrepared else { return }

        try FileManager.default.createDirectory(at: sessionContext.backupURL, withIntermediateDirectories: true)

        switch sessionContext.deployment.deploymentKind {
        case .local:
            guard let openClawRoot = sessionContext.deployment.localRootURL else {
                throw NSError(
                    domain: "OpenClawManager",
                    code: 16,
                    userInfo: [NSLocalizedDescriptionKey: "无法解析本地 OpenClaw 路径"]
                )
            }
            _ = try replaceDirectoryContents(of: sessionContext.backupURL, withContentsOf: openClawRoot)
        case .container:
            guard let deploymentRootPath = sessionContext.deployment.deploymentRootPath else {
                throw NSError(
                    domain: "OpenClawManager",
                    code: 16,
                    userInfo: [NSLocalizedDescriptionKey: "无法解析容器内 OpenClaw 路径"]
                )
            }
            _ = try copyDeploymentContentsToLocal(
                sessionContext.backupURL,
                deploymentRootPath: deploymentRootPath,
                using: sessionContext.deployment.config
            )
        case .remoteServer:
            break
        }

        sessionDeploymentBackupPrepared = true
    }

    private func ensureSessionPrepared() {
        if sessionLifecycle.preparedAt == nil {
            sessionLifecycle.preparedAt = Date()
        }

        if sessionLifecycle.stage == .inactive {
            sessionLifecycle.stage = .prepared
        }
    }

    private func markSessionPendingSync() {
        if sessionLifecycle.preparedAt == nil {
            sessionLifecycle.preparedAt = Date()
        }
        sessionLifecycle.stage = .pendingSync
        sessionLifecycle.hasPendingMirrorChanges = true
    }

    private func markSessionSynchronized() {
        if sessionLifecycle.preparedAt == nil {
            sessionLifecycle.preparedAt = Date()
        }
        sessionLifecycle.stage = .synced
        sessionLifecycle.hasPendingMirrorChanges = false
        sessionLifecycle.lastAppliedAt = Date()
    }

    @discardableResult
    private func writeTextIfNeeded(_ content: String, to targetURL: URL) throws -> Bool {
        try FileManager.default.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: targetURL.path) {
            let existing = try String(contentsOf: targetURL, encoding: .utf8)
            if existing == content {
                return false
            }
        }

        try content.write(to: targetURL, atomically: true, encoding: .utf8)
        return true
    }

    private func finalizeDetachedSessionLifecycle() {
        switch sessionLifecycle.stage {
        case .synced:
            sessionLifecycle.stage = .prepared
            sessionLifecycle.hasPendingMirrorChanges = false
        case .inactive, .prepared, .pendingSync:
            break
        }
    }

    private func restoredSessionLifecycle(
        from snapshot: OpenClawSessionLifecycleSnapshot
    ) -> OpenClawSessionLifecycleSnapshot {
        var restored = snapshot
        if restored.stage == .synced {
            restored.stage = .prepared
        }
        return restored
    }

    private func markProjectAttached(projectID: UUID) {
        if projectAttachment.attachedAt == nil || projectAttachment.projectID != projectID {
            projectAttachment.attachedAt = Date()
        }
        projectAttachment.state = .attached
        projectAttachment.projectID = projectID
    }

    private func markProjectDetached() {
        if projectAttachment.state == .attached || projectAttachment.projectID != nil {
            projectAttachment.lastDetachedAt = Date()
        }
        projectAttachment.state = .detached
        projectAttachment.projectID = nil
    }

    private func restoredProjectAttachment(
        from snapshot: OpenClawProjectAttachmentSnapshot
    ) -> OpenClawProjectAttachmentSnapshot {
        var restored = snapshot
        if restored.state == .attached || restored.projectID != nil {
            restored.state = .detached
            restored.projectID = nil
            restored.lastDetachedAt = Date()
        }
        return restored
    }

    private func mirrorStageMessage(from result: MirrorStageResult) -> String? {
        var parts: [String] = []
        if result.updatedAgentCount > 0 {
            parts.append("已更新 \(result.updatedAgentCount) 个 agent 的项目镜像")
        } else if result.unresolvedAgentNames.isEmpty {
            parts.append("项目镜像已是最新")
        }
        if !result.cleanedEntryNames.isEmpty {
            parts.append("已清理镜像中的非项目目录：\(result.cleanedEntryNames.joined(separator: ", "))")
        }
        if !result.unresolvedAgentNames.isEmpty {
            let names = result.unresolvedAgentNames.sorted().joined(separator: ", ")
            parts.append("未能定位这些 agent 的 SOUL 路径：\(names)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "；")
    }

    private func stagedMirrorPreparationMessage(from result: MirrorStageResult) -> String? {
        var parts: [String] = []
        if result.updatedAgentCount > 0 {
            parts.append("已准备 \(result.updatedAgentCount) 个 agent 的项目镜像，尚未写回当前 OpenClaw 会话")
        } else if result.unresolvedAgentNames.isEmpty {
            parts.append("项目镜像已是最新，当前无需重新准备会话副本")
        }
        if !result.cleanedEntryNames.isEmpty {
            parts.append("已清理镜像中的非项目目录：\(result.cleanedEntryNames.joined(separator: ", "))")
        }
        if !result.unresolvedAgentNames.isEmpty {
            let names = result.unresolvedAgentNames.sorted().joined(separator: ", ")
            parts.append("未能定位这些 agent 的 SOUL 路径：\(names)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "；")
    }

    private func resolveProjectMirrorSoulURL(
        for agent: Agent,
        in project: MAProject,
        mirrorURL: URL,
        backupURL: URL?
    ) -> URL? {
        let candidateNames = Array(
            Set([
                agent.name,
                agent.openClawDefinition.agentIdentifier,
                normalizedTargetIdentifier(for: agent)
            ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        )

        let currentProjectMirrorURL = ProjectManager.shared.openClawMirrorDirectory(for: project.id)
        if currentProjectMirrorURL.path != mirrorURL.path,
           let existingCurrentMirrorMatch = findMatchingSoulURL(in: currentProjectMirrorURL, matching: candidateNames),
           let translatedExistingMatch = translateRelativeURL(
                existingCurrentMirrorMatch,
                from: currentProjectMirrorURL,
                to: mirrorURL
           ) {
            return translatedExistingMatch
        }

        let sourceCandidates = mirrorSourceCandidates(for: agent, in: project, matching: candidateNames)
        for sourceURL in sourceCandidates {
            if let translated = translateURLToMirror(
                sourceURL,
                mirrorURL: mirrorURL,
                currentBackupURL: backupURL,
                project: project
            ) {
                return translated
            }
        }

        if let existingMirrorMatch = findMatchingSoulURL(in: mirrorURL, matching: candidateNames) {
            return existingMirrorMatch
        }

        if let backupURL,
           let backupMatch = findMatchingSoulURL(in: backupURL, matching: candidateNames),
           let translated = translateRelativeURL(backupMatch, from: backupURL, to: mirrorURL) {
            return translated
        }

        let fallbackName = safePathComponent(normalizedTargetIdentifier(for: agent))
        return mirrorURL
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent(fallbackName, isDirectory: true)
            .appendingPathComponent("SOUL.md", isDirectory: false)
    }

    private func mirrorSourceCandidates(
        for agent: Agent,
        in project: MAProject,
        matching candidateNames: [String]
    ) -> [URL] {
        var sources: [URL] = []

        if let sourcePath = firstNonEmptyPath(agent.openClawDefinition.soulSourcePath) {
            sources.append(URL(fileURLWithPath: sourcePath, isDirectory: false))
        }

        if let localSoulURL = localAgentSoulURL(matching: candidateNames) {
            sources.append(localSoulURL)
        }

        let normalizedNames = Set(candidateNames.map(normalizeAgentKey))
        if let detectedRecord = discoveryResults.first(where: { normalizedNames.contains(normalizeAgentKey($0.name)) }) {
            if let soulPath = firstNonEmptyPath(detectedRecord.soulPath) {
                sources.append(URL(fileURLWithPath: soulPath, isDirectory: false))
            }
            if let directoryPath = firstNonEmptyPath(detectedRecord.directoryPath) {
                sources.append(preferredSoulURL(in: URL(fileURLWithPath: directoryPath, isDirectory: true)))
            }
            if let copiedRootPath = firstNonEmptyPath(detectedRecord.copiedToProjectPath) {
                sources.append(preferredSoulURL(in: URL(fileURLWithPath: copiedRootPath, isDirectory: true)))
            }
        }

        if let memoryBackupPath = firstNonEmptyPath(agent.openClawDefinition.memoryBackupPath) {
            let privateURL = URL(fileURLWithPath: memoryBackupPath, isDirectory: true)
            let rootURL = privateURL.lastPathComponent == "private" ? privateURL.deletingLastPathComponent() : privateURL
            sources.append(preferredSoulURL(in: rootURL))
        }

        var seen = Set<String>()
        return sources.filter { seen.insert($0.path).inserted }
    }

    private func translateURLToMirror(
        _ sourceURL: URL,
        mirrorURL: URL,
        currentBackupURL: URL?,
        project: MAProject
    ) -> URL? {
        if sourceURL.path == mirrorURL.path || sourceURL.path.hasPrefix(mirrorURL.path + "/") {
            return sourceURL
        }

        var sourceRoots: [URL] = []
        if let currentBackupURL {
            sourceRoots.append(currentBackupURL)
        }
        sourceRoots.append(ProjectManager.shared.openClawMirrorDirectory(for: project.id))
        sourceRoots.append(ProjectManager.shared.openClawBackupDirectory(for: project.id))
        if let previousMirrorPath = firstNonEmptyPath(project.openClaw.sessionMirrorPath) {
            sourceRoots.append(URL(fileURLWithPath: previousMirrorPath, isDirectory: true))
        }
        if let previousBackupPath = firstNonEmptyPath(project.openClaw.sessionBackupPath) {
            sourceRoots.append(URL(fileURLWithPath: previousBackupPath, isDirectory: true))
        }
        if let sessionContext,
           sessionContext.projectID == project.id,
           let sessionLocalRootURL = sessionContext.deployment.localRootURL {
            sourceRoots.append(sessionLocalRootURL)
        } else if config.deploymentKind == .local {
            sourceRoots.append(localOpenClawRootURL())
        }

        var seen = Set<String>()
        for sourceRoot in sourceRoots where seen.insert(sourceRoot.path).inserted {
            if let translated = translateRelativeURL(sourceURL, from: sourceRoot, to: mirrorURL) {
                return translated
            }
        }

        return nil
    }

    private func translateURLToBackup(_ sourceURL: URL, backupURL: URL, project: MAProject) -> URL? {
        if sourceURL.path == backupURL.path || sourceURL.path.hasPrefix(backupURL.path + "/") {
            return sourceURL
        }

        var sourceRoots: [URL] = []
        if let sessionContext, sessionContext.projectID == project.id {
            sourceRoots.append(sessionContext.mirrorURL)
            sourceRoots.append(sessionContext.backupURL)
        }
        sourceRoots.append(ProjectManager.shared.openClawMirrorDirectory(for: project.id))
        sourceRoots.append(ProjectManager.shared.openClawBackupDirectory(for: project.id))
        if let previousMirrorPath = firstNonEmptyPath(project.openClaw.sessionMirrorPath) {
            sourceRoots.append(URL(fileURLWithPath: previousMirrorPath, isDirectory: true))
        }
        if let previousBackupPath = firstNonEmptyPath(project.openClaw.sessionBackupPath) {
            sourceRoots.append(URL(fileURLWithPath: previousBackupPath, isDirectory: true))
        }
        if let sessionContext,
           sessionContext.projectID == project.id,
           let sessionLocalRootURL = sessionContext.deployment.localRootURL {
            sourceRoots.append(sessionLocalRootURL)
        } else if config.deploymentKind == .local {
            sourceRoots.append(localOpenClawRootURL())
        }

        var seen = Set<String>()
        for sourceRoot in sourceRoots where seen.insert(sourceRoot.path).inserted {
            if let translated = translateRelativeURL(sourceURL, from: sourceRoot, to: backupURL) {
                return translated
            }
        }

        return nil
    }

    private func currentLocalDeploymentBaselineRoot(for project: MAProject) -> URL? {
        guard let sessionContext,
              sessionContext.projectID == project.id,
              sessionContext.deployment.deploymentKind == .local,
              !sessionDeploymentModified,
              !sessionDeploymentBackupPrepared,
              let localRootURL = sessionContext.deployment.localRootURL else {
            return nil
        }

        return localRootURL
    }

    private func lazilyCacheCurrentLocalSoulBaseline(
        from sourceURL: URL,
        for project: MAProject,
        backupURL: URL
    ) -> URL? {
        guard let localRootURL = currentLocalDeploymentBaselineRoot(for: project),
              let translated = translateRelativeURL(sourceURL, from: localRootURL, to: backupURL) else {
            return nil
        }

        return cacheSessionBackupFileIfNeeded(from: sourceURL, to: translated)
    }

    private func lazilyCacheCurrentLocalSoulBaseline(
        matching candidateNames: [String],
        for project: MAProject,
        backupURL: URL
    ) -> URL? {
        guard let localRootURL = currentLocalDeploymentBaselineRoot(for: project),
              let sourceURL = findMatchingSoulURL(in: localRootURL, matching: candidateNames),
              let translated = translateRelativeURL(sourceURL, from: localRootURL, to: backupURL) else {
            return nil
        }

        return cacheSessionBackupFileIfNeeded(from: sourceURL, to: translated)
    }

    private func cacheSessionBackupFileIfNeeded(from sourceURL: URL, to targetURL: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return nil }

        do {
            try FileManager.default.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if !FileManager.default.fileExists(atPath: targetURL.path) {
                let data = try Data(contentsOf: sourceURL)
                try data.write(to: targetURL, options: .atomic)
            }

            return targetURL
        } catch {
            return nil
        }
    }

    private func backupSoulContent(
        for agent: Agent,
        in project: MAProject,
        mirrorSoulURL: URL,
        mirrorURL: URL,
        backupURL: URL?
    ) -> String? {
        guard let backupURL else { return nil }

        var candidates: [URL] = []
        if let translatedMirrorURL = translateRelativeURL(mirrorSoulURL, from: mirrorURL, to: backupURL) {
            candidates.append(translatedMirrorURL)
        }
        if let resolvedBackupURL = resolveSessionBackupSoulURL(for: agent, in: project, backupURL: backupURL) {
            candidates.append(resolvedBackupURL)
        }

        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate.path).inserted {
            guard FileManager.default.fileExists(atPath: candidate.path),
                  let content = try? String(contentsOf: candidate, encoding: .utf8) else {
                continue
            }
            return content
        }

        return nil
    }

    private func translateRelativeURL(_ sourceURL: URL, from sourceRoot: URL, to targetRoot: URL) -> URL? {
        let normalizedSourceRoot = sourceRoot.standardizedFileURL.path
        let normalizedSourceURL = sourceURL.standardizedFileURL.path
        guard normalizedSourceURL == normalizedSourceRoot || normalizedSourceURL.hasPrefix(normalizedSourceRoot + "/") else {
            return nil
        }

        let relativePath = String(normalizedSourceURL.dropFirst(normalizedSourceRoot.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relativePath.isEmpty else { return targetRoot }
        return targetRoot.appendingPathComponent(relativePath, isDirectory: false)
    }

    private func findMatchingSoulURL(in rootURL: URL, matching candidateNames: [String]) -> URL? {
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return nil }

        let normalizedNames = Set(candidateNames.map(normalizeAgentKey).filter { !$0.isEmpty })
        guard !normalizedNames.isEmpty else { return nil }

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var bestMatch: (score: Int, url: URL)?
        for case let fileURL as URL in enumerator {
            let filename = fileURL.lastPathComponent.lowercased()
            guard filename == "soul.md" else { continue }

            let score = scoreSoulURL(fileURL, matching: normalizedNames)
            guard score > 0 else { continue }

            if let currentBest = bestMatch {
                if score > currentBest.score {
                    bestMatch = (score, fileURL)
                }
            } else {
                bestMatch = (score, fileURL)
            }
        }

        return bestMatch?.url
    }

    private func scoreSoulURL(_ fileURL: URL, matching candidateNames: Set<String>) -> Int {
        var score = 0
        var current = fileURL.deletingLastPathComponent()

        for depth in 0..<6 {
            let normalizedComponent = normalizeAgentKey(current.lastPathComponent)
            if candidateNames.contains(normalizedComponent) {
                score = max(score, 100 - (depth * 10))
            } else {
                let pathComponent = normalizeAgentKey(current.path)
                if candidateNames.contains(where: { !$0.isEmpty && pathComponent.contains($0) }) {
                    score = max(score, 50 - (depth * 5))
                }
            }

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }

        return score
    }
    private func resolveLocalAgentConfigResolution(
        matching candidateNames: [String],
        at configURL: URL? = nil
    ) -> LocalAgentConfigResolution {
        let normalizedNames = Set(candidateNames.map(normalizeAgentKey).filter { !$0.isEmpty })
        guard !normalizedNames.isEmpty else {
            return LocalAgentConfigResolution(status: .missing, entries: [], selectedEntry: nil)
        }

        let resolvedConfigURL = configURL
            ?? resolveLocalOpenClawConfigURL()
            ?? localOpenClawRootURL().appendingPathComponent("openclaw.json")
        let entries = readLocalAgentConfigEntries(at: resolvedConfigURL)
        let matchingEntries = entries.filter { !$0.candidateKeys.isDisjoint(with: normalizedNames) }
        guard !matchingEntries.isEmpty else {
            return LocalAgentConfigResolution(status: .missing, entries: [], selectedEntry: nil)
        }

        let validEntries = matchingEntries.filter { entry in
            guard let workspacePath = entry.workspacePath,
                  let normalizedPath = normalizeWorkspacePath(workspacePath) else {
                return false
            }
            return fileManager.fileExists(atPath: normalizedPath)
        }

        if validEntries.isEmpty {
            return LocalAgentConfigResolution(status: .invalid, entries: matchingEntries, selectedEntry: nil)
        }

        let uniquePaths = Dictionary(grouping: validEntries) { entry in
            normalizeWorkspacePath(entry.workspacePath ?? "") ?? ""
        }.filter { !$0.key.isEmpty }

        let selectedEntry = validEntries.sorted { lhs, rhs in
            localAgentConfigReadPriority(lhs: lhs, rhs: rhs)
        }.first

        guard uniquePaths.count == 1,
              let selectedEntry else {
            return LocalAgentConfigResolution(status: .ambiguous, entries: validEntries, selectedEntry: nil)
        }

        return LocalAgentConfigResolution(status: .uniqueValid, entries: validEntries, selectedEntry: selectedEntry)
    }

    private func localAgentConfigReadPriority(lhs: LocalAgentConfigEntry, rhs: LocalAgentConfigEntry) -> Bool {
        let lhsID = lhs.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rhsID = rhs.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !lhsID.isEmpty && rhsID.isEmpty {
            return true
        }
        if lhsID.isEmpty && !rhsID.isEmpty {
            return false
        }

        let lhsWorkspaceExists = lhs.workspacePath.flatMap(normalizeWorkspacePath).map { fileManager.fileExists(atPath: $0) } ?? false
        let rhsWorkspaceExists = rhs.workspacePath.flatMap(normalizeWorkspacePath).map { fileManager.fileExists(atPath: $0) } ?? false
        if lhsWorkspaceExists != rhsWorkspaceExists {
            return lhsWorkspaceExists
        }

        return lhs.configIndex < rhs.configIndex
    }

    private func unresolvedWorkspaceDiagnosticMessage(
        for agent: Agent,
        in project: MAProject? = nil,
        workflowID: UUID? = nil
    ) -> String? {
        if let bindingDiagnostic = workflowBindingDiagnosticMessage(for: agent, in: project, workflowID: workflowID) {
            return bindingDiagnostic
        }

        let candidateNames = [
            agent.openClawDefinition.agentIdentifier,
            agent.name
        ].map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }

        let localResolution = resolveLocalAgentConfigResolution(matching: candidateNames)
        switch localResolution.status {
        case .ambiguous:
            let paths = Array(
                Set(
                    localResolution.entries.compactMap { entry in
                        if let normalized = normalizeWorkspacePath(entry.workspacePath ?? "") {
                            return normalized
                        }
                        let trimmed = entry.workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return trimmed.isEmpty ? nil : trimmed
                    }
                )
            ).sorted { (lhs: String, rhs: String) in
                lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            if paths.isEmpty {
                return "openclaw.json 中存在多条同名或同标识 agent 记录，但这些记录的 workspace 信息彼此冲突。"
            }
            return "openclaw.json 中存在多条同名或同标识 agent 记录，且 workspace 不一致：\(paths.joined(separator: "；"))。"
        case .invalid:
            let paths = localResolution.entries.compactMap { entry -> String? in
                let trimmed = entry.workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
            if paths.isEmpty {
                return "openclaw.json 中找到了该 agent 的记录，但 workspace 字段缺失。"
            }
            return "openclaw.json 中找到了该 agent 的记录，但 workspace 不存在或当前不可用：\(paths.joined(separator: "；"))。"
        case .missing:
            if project != nil {
                return "当前项目上下文中没有可直接复用的节点 workspace，openclaw.json 中也没有该 agent 的唯一有效记录。"
            }
            return "openclaw.json 中没有该 agent 的唯一有效 workspace 记录。"
        case .uniqueValid:
            return nil
        }
    }

    private func workflowBindingDiagnosticMessage(
        for agent: Agent,
        in project: MAProject? = nil,
        workflowID: UUID? = nil
    ) -> String? {
        guard let project else { return nil }

        let bindings = workflows(in: project, matching: workflowID)
            .flatMap { workflow in
                workflow.nodes
                    .filter { $0.type == .agent && $0.agentID == agent.id }
                    .map { (workflowID: workflow.id, nodeID: $0.id) }
            }

        if workflowID != nil, bindings.isEmpty {
            return "当前 workflow 中没有绑定这个 agent 节点，因此无法推断应使用哪个 workspace。"
        }

        if workflowID == nil, bindings.count > 1 {
            return "该 agent 同时绑定在多个 workflow 节点上，当前执行入口未提供明确的 workflow，因此无法自动判定 workspace。"
        }

        return nil
    }

    private func localAgentWorkspaceMap() -> [String: String] {
        let configURL = resolveLocalOpenClawConfigURL()
            ?? localOpenClawRootURL().appendingPathComponent("openclaw.json")
        let currentModificationDate = (try? fileManager.attributesOfItem(atPath: configURL.path)[.modificationDate] as? Date) ?? nil

        if cachedLocalWorkspaceConfigModificationDate == currentModificationDate,
           !cachedLocalWorkspaceMap.isEmpty {
            return cachedLocalWorkspaceMap
        }

        let entries = readLocalAgentConfigEntries(at: configURL)
        guard !entries.isEmpty else {
            cachedLocalWorkspaceMap = [:]
            cachedLocalWorkspaceConfigModificationDate = currentModificationDate
            return [:]
        }

        var map: [String: String] = [:]
        let keys = Set(entries.flatMap { $0.candidateKeys })
        for key in keys {
            let resolution = resolveLocalAgentConfigResolution(matching: [key], at: configURL)
            guard resolution.status == .uniqueValid,
                  let workspace = resolution.selectedEntry?.workspacePath else {
                continue
            }
            map[key] = workspace
        }
        cachedLocalWorkspaceMap = map
        cachedLocalWorkspaceConfigModificationDate = currentModificationDate
        return map
    }

    private func localLoopbackGatewayConfig(using baseConfig: OpenClawConfig) -> OpenClawConfig? {
        let localRootURL = localOpenClawRootURL(using: baseConfig)
        let configURL = resolveLocalOpenClawConfigURL(using: baseConfig)
            ?? localRootURL.appendingPathComponent("openclaw.json")
        let currentModificationDate = (try? fileManager.attributesOfItem(atPath: configURL.path)[.modificationDate] as? Date) ?? nil
        let fallbackToken = baseConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackKey = [
            String(baseConfig.port),
            fallbackToken,
            String(baseConfig.timeout),
            baseConfig.defaultAgent,
            baseConfig.autoConnect ? "auto" : "manual"
        ].joined(separator: "|")

        if cachedLocalGatewayConfigModificationDate == currentModificationDate,
           cachedLocalGatewayConfigFallbackKey == fallbackKey {
            return cachedLocalGatewayConfig
        }

        func cache(_ gatewayConfig: OpenClawConfig?) -> OpenClawConfig? {
            cachedLocalGatewayConfig = gatewayConfig
            cachedLocalGatewayConfigModificationDate = currentModificationDate
            cachedLocalGatewayConfigFallbackKey = fallbackKey
            return gatewayConfig
        }

        return cache(
            gatewayConfig(
                fromOpenClawRoot: localRootURL,
                using: baseConfig,
                hostFallback: "127.0.0.1",
                useSSLFallback: false,
                fallbackPort: baseConfig.port
            )
        )
    }

    func gatewayConfig(
        fromOpenClawRoot rootURL: URL,
        using baseConfig: OpenClawConfig,
        hostFallback: String,
        useSSLFallback: Bool,
        fallbackPort: Int? = nil
    ) -> OpenClawConfig? {
        let configURL = rootURL.appendingPathComponent("openclaw.json")
        let fallbackToken = baseConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedHost = hostFallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "127.0.0.1"
            : hostFallback.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedFallbackPort = fallbackPort ?? baseConfig.port

        func fallbackGatewayConfig(port: Int? = nil) -> OpenClawConfig? {
            let resolvedPort = port ?? resolvedFallbackPort
            guard resolvedPort > 0 else { return nil }

            return OpenClawConfig(
                deploymentKind: .remoteServer,
                runtimeOwnership: baseConfig.runtimeOwnership,
                host: resolvedHost,
                port: resolvedPort,
                useSSL: useSSLFallback,
                apiKey: fallbackToken,
                defaultAgent: baseConfig.defaultAgent,
                timeout: baseConfig.timeout,
                autoConnect: baseConfig.autoConnect,
                localBinaryPath: baseConfig.localBinaryPath,
                container: baseConfig.container,
                cliQuietMode: baseConfig.cliQuietMode,
                cliLogLevel: baseConfig.cliLogLevel
            )
        }

        guard
            let root = readOpenClawConfigRecord(at: configURL),
            let gateway = root["gateway"] as? [String: Any]
        else {
            return fallbackGatewayConfig()
        }

        let mode = (stringValue(gateway, keys: ["mode"]) ?? "local").lowercased()
        guard mode == "local" else {
            return nil
        }

        let port = intValue(gateway, keys: ["port"]) ?? resolvedFallbackPort
        guard port > 0 else {
            return fallbackGatewayConfig(port: resolvedFallbackPort)
        }

        let auth = gateway["auth"] as? [String: Any] ?? [:]
        let authMode = (stringValue(auth, keys: ["mode"]) ?? "token").lowercased()
        let token = auth["token"] as? String
        let normalizedToken = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let resolvedToken: String
        switch authMode {
        case "none":
            resolvedToken = ""
        case "token":
            resolvedToken = normalizedToken.isEmpty ? fallbackToken : normalizedToken
        default:
            return nil
        }

        return OpenClawConfig(
            deploymentKind: .remoteServer,
            runtimeOwnership: baseConfig.runtimeOwnership,
            host: resolvedHost,
            port: port,
            useSSL: useSSLFallback,
            apiKey: resolvedToken,
            defaultAgent: baseConfig.defaultAgent,
            timeout: baseConfig.timeout,
            autoConnect: baseConfig.autoConnect,
            localBinaryPath: baseConfig.localBinaryPath,
            container: baseConfig.container,
            cliQuietMode: baseConfig.cliQuietMode,
            cliLogLevel: baseConfig.cliLogLevel
        )
    }

    private func containerGatewayConfig(using baseConfig: OpenClawConfig) -> OpenClawConfig? {
        let hostFallback = baseConfig.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "127.0.0.1"
            : baseConfig.host.trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let discoveryContext = try? resolveOpenClawDiscoveryContext(
                using: baseConfig,
                requiresInspectionRoot: true
            ),
            let inspectionRootURL = discoveryContext.inspectionRootURL
        else {
            return OpenClawConfig(
                deploymentKind: .remoteServer,
                runtimeOwnership: baseConfig.runtimeOwnership,
                host: hostFallback,
                port: baseConfig.port,
                useSSL: baseConfig.useSSL,
                apiKey: baseConfig.apiKey,
                defaultAgent: baseConfig.defaultAgent,
                timeout: baseConfig.timeout,
                autoConnect: baseConfig.autoConnect,
                localBinaryPath: baseConfig.localBinaryPath,
                container: baseConfig.container,
                cliQuietMode: baseConfig.cliQuietMode,
                cliLogLevel: baseConfig.cliLogLevel
            )
        }

        return gatewayConfig(
            fromOpenClawRoot: inspectionRootURL,
            using: baseConfig,
            hostFallback: hostFallback,
            useSSLFallback: baseConfig.useSSL,
            fallbackPort: baseConfig.port
        )
    }

    private func existingSoulURL(in rootURL: URL) -> URL? {
        existingOpenClawSoulURL(in: rootURL, maxAncestorDepth: 2)
    }

    private struct DirectoryInspection {
        let name: String
        let path: String
        let workspacePath: String?
        let statePath: String?
        let hasSoulFile: Bool
    }

    private struct ConfigInspection {
        let name: String
        let identifier: String?
        let configPath: String?
        let agentDirPath: String?
        let workspacePath: String?
        let statePath: String?
    }

    private struct LocalAgentBootstrapCandidate {
        let identifier: String
        let authProfilesURL: URL?
        let modelsURL: URL?
        let sourceDescription: String

        var hasAuthProfiles: Bool {
            authProfilesURL != nil
        }

        var hasModels: Bool {
            modelsURL != nil
        }
    }

    private func inspectOpenClawAgents(using config: OpenClawConfig, fallbackAgentNames: [String] = []) -> [ProjectOpenClawDetectedAgentRecord] {
        guard config.deploymentKind != .remoteServer else {
            return []
        }

        if config.deploymentKind == .local {
            clearDiscoverySnapshot()
        }

        guard
            let discoveryContext = try? resolveOpenClawDiscoveryContext(
                using: config,
                requiresInspectionRoot: true
            ),
            let inspectionRootURL = discoveryContext.inspectionRootURL
        else {
            return fallbackAgentNames.map {
                ProjectOpenClawDetectedAgentRecord(
                    id: $0,
                    name: $0,
                    directoryValidated: false,
                    configValidated: false,
                    issues: ["无法读取 \(config.deploymentKind == .container ? "容器" : "本地") 中的 OpenClaw 文件，仅保留 CLI 结果。"]
                )
            }
        }

        let configURL = discoveryContext.configURL
        let configRecord = configURL.flatMap { readOpenClawConfigRecord(at: $0) }

        return inspectOpenClawAgents(
            at: inspectionRootURL,
            configRecord: configRecord,
            configURL: configURL,
            fallbackAgentNames: fallbackAgentNames
        )
    }

    private func inspectOpenClawAgents(
        at rootURL: URL,
        configRecord: [String: Any]? = nil,
        configURL: URL? = nil,
        fallbackAgentNames: [String] = []
    ) -> [ProjectOpenClawDetectedAgentRecord] {
        let agentsDirectory = rootURL.appendingPathComponent("agents", isDirectory: true)
        let resolvedConfigURL = configURL ?? rootURL.appendingPathComponent("openclaw.json")

        let directoryInspections = inspectAgentDirectories(at: agentsDirectory)
        let configInspections: [ConfigInspection]
        if let configRecord {
            configInspections = inspectAgentConfigCandidates(
                in: configRecord,
                configURL: resolvedConfigURL
            )
        } else {
            configInspections = inspectAgentConfigCandidates(at: resolvedConfigURL)
        }

        var unmatchedDirectories = directoryInspections
        var inspectionPairs: [(directory: DirectoryInspection?, config: ConfigInspection?)] = []

        for configCandidate in configInspections {
            let matchedDirectoryIndex = unmatchedDirectories.firstIndex { directory in
                if let configAgentDirPath = canonicalInspectionPath(configCandidate.agentDirPath),
                   canonicalInspectionPath(directory.path) == configAgentDirPath {
                    return true
                }

                if let configWorkspacePath = canonicalInspectionPath(configCandidate.workspacePath),
                   canonicalInspectionPath(directory.workspacePath) == configWorkspacePath {
                    return true
                }

                let normalizedDirectoryName = normalizeAgentKey(directory.name)
                if normalizedDirectoryName == normalizeAgentKey(configCandidate.name) {
                    return true
                }

                if let identifier = configCandidate.identifier,
                   normalizedDirectoryName == normalizeAgentKey(identifier) {
                    return true
                }

                return false
            }

            let matchedDirectory = matchedDirectoryIndex.map { unmatchedDirectories.remove(at: $0) }
            inspectionPairs.append((directory: matchedDirectory, config: configCandidate))
        }

        inspectionPairs.append(contentsOf: unmatchedDirectories.map { (directory: $0, config: nil) })

        let records = inspectionPairs.map { pair in
            let directory = pair.directory
            let configCandidate = pair.config
            var issues: [String] = []
            let workspacePath = configCandidate?.workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines)
            let workspaceURL = (workspacePath?.isEmpty == false)
                ? URL(fileURLWithPath: workspacePath!, isDirectory: true)
                : nil
            let workspaceValidated = workspaceURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            let directoryValidated = directory != nil
            let configValidated = configCandidate != nil
            let soulSearchRoots = [
                directory.map { URL(fileURLWithPath: $0.path, isDirectory: true) },
                workspaceValidated ? workspaceURL : nil
            ].compactMap { $0 }
            let soulURL = soulSearchRoots.compactMap { rootURL in
                existingOpenClawSoulURL(in: rootURL, maxAncestorDepth: rootURL == workspaceURL ? 2 : 0)
            }.first

            if !directoryValidated {
                issues.append("agent 目录未找到")
            }

            if soulURL == nil {
                issues.append("缺少 SOUL.md")
            }

            if !configValidated {
                issues.append("openclaw.json 中未找到匹配项")
            }

            let name = configCandidate?.name
                ?? configCandidate?.identifier
                ?? directory?.name
                ?? "unknown-agent"
            let recordID = [
                name,
                directory?.path ?? "",
                configCandidate?.configPath ?? ""
            ].joined(separator: "|")

            return ProjectOpenClawDetectedAgentRecord(
                id: recordID,
                name: name,
                directoryPath: directory?.path,
                configPath: configCandidate?.configPath,
                soulPath: soulURL?.path,
                workspacePath: configCandidate?.workspacePath ?? directory?.workspacePath,
                statePath: configCandidate?.statePath ?? directory?.statePath,
                directoryValidated: directoryValidated,
                configValidated: configValidated,
                issues: issues
            )
        }
        .sorted(by: { (lhs: ProjectOpenClawDetectedAgentRecord, rhs: ProjectOpenClawDetectedAgentRecord) in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        })

        if !records.isEmpty {
            return records
        }

        guard !fallbackAgentNames.isEmpty else {
            return []
        }

        return fallbackAgentNames.map {
            ProjectOpenClawDetectedAgentRecord(
                id: $0,
                name: $0,
                directoryValidated: false,
                configValidated: false,
                issues: ["未发现可验证的 agent 文件，仅保留 CLI 结果。"]
            )
        }
        .sorted(by: { (lhs: ProjectOpenClawDetectedAgentRecord, rhs: ProjectOpenClawDetectedAgentRecord) in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        })
    }

    private func inspectAgentDirectories(at agentsDirectory: URL) -> [DirectoryInspection] {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: agentsDirectory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }

        return contents.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { return nil }

            let hasSoulFile = existingOpenClawSoulURL(in: url, maxAncestorDepth: 0) != nil

            let workspacePath = firstExistingChildPath(in: url, candidates: ["workspace", "workspaces", "job", "jobs"])
            let statePath = firstExistingChildPath(in: url, candidates: ["state", "status", "runtime", "private"])

            return DirectoryInspection(
                name: url.lastPathComponent,
                path: url.path,
                workspacePath: workspacePath,
                statePath: statePath,
                hasSoulFile: hasSoulFile
            )
        }
    }

    private func inspectAgentConfigCandidates(at configURL: URL) -> [ConfigInspection] {
        guard let json = readOpenClawConfigRecord(at: configURL) else {
            return []
        }
        return inspectAgentConfigCandidates(in: json, configURL: configURL)
    }

    private func inspectAgentConfigCandidates(in json: [String: Any], configURL: URL) -> [ConfigInspection] {
        var candidates: [ConfigInspection] = []

        func walk(_ value: Any, path: [String]) {
            if let dict = value as? [String: Any] {
                let identifier = stringValue(dict, keys: ["id", "agentID", "agentId", "identifier", "agentIdentifier"])
                let name = stringValue(dict, keys: ["name", "agentName"]) ?? identifier
                let configPath = stringValue(dict, keys: ["configPath", "path", "filePath"])
                let agentDirPath = stringValue(dict, keys: ["agentDir", "agentDirPath", "directory", "agentDirectory"])
                let workspacePath = stringValue(dict, keys: ["workspacePath", "workspace", "workPath", "workdir"])
                let statePath = stringValue(dict, keys: ["statePath", "statusPath", "privatePath", "state", "private"])

                if let name, (path.contains("agents") || configPath != nil || workspacePath != nil || statePath != nil) {
                    candidates.append(
                        ConfigInspection(
                            name: name,
                            identifier: identifier,
                            configPath: configPath ?? configURL.path,
                            agentDirPath: agentDirPath,
                            workspacePath: workspacePath,
                            statePath: statePath
                        )
                    )
                }

                for (key, child) in dict {
                    walk(child, path: path + [key])
                }
            } else if let array = value as? [Any] {
                for child in array {
                    walk(child, path: path)
                }
            }
        }

        walk(json, path: [])

        var unique: [String: ConfigInspection] = [:]
        for candidate in candidates {
            unique[normalizeAgentKey(candidate.name)] = candidate
        }
        return Array(unique.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func canonicalInspectionPath(_ path: String?) -> String? {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed, isDirectory: true)
            .standardizedFileURL
            .path
    }

    private func readOpenClawConfigRecord(at configURL: URL) -> [String: Any]? {
        guard
            let data = try? Data(contentsOf: configURL),
            let json = try? JSONSerialization.jsonObject(with: data),
            let record = json as? [String: Any]
        else {
            return nil
        }

        return record
    }

    private func readOpenClawAgentConfigList(at configURL: URL) -> [[String: Any]]? {
        guard
            let root = readOpenClawConfigRecord(at: configURL),
            let agents = root["agents"] as? [String: Any],
            let list = agents["list"] as? [[String: Any]]
        else {
            return nil
        }

        return list
    }

    private func readLocalAgentConfigEntries(at configURL: URL) -> [LocalAgentConfigEntry] {
        guard let list = readOpenClawAgentConfigList(at: configURL) else {
            return []
        }
        return parseLocalAgentConfigEntries(from: list)
    }

    private func firstExistingChildPath(in url: URL, candidates: [String]) -> String? {
        for candidate in candidates {
            let child = url.appendingPathComponent(candidate, isDirectory: true)
            if FileManager.default.fileExists(atPath: child.path) {
                return child.path
            }
        }
        return nil
    }

    private func preferredSoulURL(in rootURL: URL) -> URL {
        preferredOpenClawSoulURL(in: rootURL, maxAncestorDepth: 2)
    }

    private func stringValue(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private func intValue(_ dictionary: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = dictionary[key] as? Int {
                return value
            }
            if let value = dictionary[key] as? NSNumber {
                return value.intValue
            }
            if let value = dictionary[key] as? String,
               let parsed = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return parsed
            }
        }
        return nil
    }

    private func normalizeAgentKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func desiredAllowAgentsMap(for project: MAProject) -> [String: [String]] {
        var identifierByAgentID: [UUID: String] = [:]
        var desiredSetBySourceKey: [String: Set<String>] = [:]

        for agent in project.agents {
            let identifier = normalizedTargetIdentifier(for: agent).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identifier.isEmpty else { continue }
            identifierByAgentID[agent.id] = identifier
            desiredSetBySourceKey[normalizeAgentKey(identifier), default: []] = []
        }

        for permission in project.permissions where permission.permissionType == .allow {
            guard let fromIdentifier = identifierByAgentID[permission.fromAgentID],
                  let toIdentifier = identifierByAgentID[permission.toAgentID] else {
                continue
            }

            let normalizedFrom = normalizeAgentKey(fromIdentifier)
            let normalizedTo = normalizeAgentKey(toIdentifier)
            guard !normalizedFrom.isEmpty, !normalizedTo.isEmpty, normalizedFrom != normalizedTo else { continue }

            desiredSetBySourceKey[normalizedFrom, default: []].insert(toIdentifier)
        }

        return desiredSetBySourceKey.reduce(into: [String: [String]]()) { partial, entry in
            partial[entry.key] = entry.value.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
        }
    }

    private func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let result = String(cleaned)
        return result.isEmpty ? UUID().uuidString : result
    }

    private func ensureLocalRuntimeAgentBootstrapFiles(
        at targetAgentDirectory: URL,
        displayIdentifier identifier: String,
        using config: OpenClawConfig? = nil
    ) -> (success: Bool, message: String, requiresUserProvidedBootstrapPath: Bool) {
        let targetAuthProfilesURL = targetAgentDirectory.appendingPathComponent("auth-profiles.json", isDirectory: false)
        let targetModelsURL = targetAgentDirectory.appendingPathComponent("models.json", isDirectory: false)
        let needsAuthProfiles = !fileManager.fileExists(atPath: targetAuthProfilesURL.path)
        let needsModels = !fileManager.fileExists(atPath: targetModelsURL.path)

        guard needsAuthProfiles || needsModels else {
            return (true, "", false)
        }

        guard let bootstrapCandidate = preferredLocalAgentBootstrapCandidate(excluding: [identifier], using: config) else {
            if needsAuthProfiles {
                return (
                    false,
                    "本地 workflow agent \(identifier) 缺少 auth-profiles.json，且当前未找到可复用的本地 agent 鉴权配置。",
                    true
                )
            }
            return (true, "", false)
        }

        do {
            try fileManager.createDirectory(at: targetAgentDirectory, withIntermediateDirectories: true)
            var copiedItems: [String] = []

            if needsAuthProfiles, let sourceAuthProfilesURL = bootstrapCandidate.authProfilesURL {
                if fileManager.fileExists(atPath: targetAuthProfilesURL.path) {
                    try fileManager.removeItem(at: targetAuthProfilesURL)
                }
                try fileManager.copyItem(at: sourceAuthProfilesURL, to: targetAuthProfilesURL)
                copiedItems.append("auth-profiles.json")
            }

            if needsModels, let sourceModelsURL = bootstrapCandidate.modelsURL {
                if fileManager.fileExists(atPath: targetModelsURL.path) {
                    try fileManager.removeItem(at: targetModelsURL)
                }
                try fileManager.copyItem(at: sourceModelsURL, to: targetModelsURL)
                copiedItems.append("models.json")
            }

            if needsAuthProfiles && !fileManager.fileExists(atPath: targetAuthProfilesURL.path) {
                return (
                    false,
                    "本地 workflow agent \(identifier) 缺少 auth-profiles.json，且未能从其他本地 agent 自动补齐。",
                    true
                )
            }

            guard !copiedItems.isEmpty else {
                return (true, "", false)
            }

            return (
                true,
                "已为本地 workflow agent \(identifier) 自动补齐 \(copiedItems.joined(separator: "、"))，来源于\(bootstrapCandidate.sourceDescription)。",
                false
            )
        } catch {
            return (false, "为本地 workflow agent \(identifier) 自动补齐鉴权配置失败：\(error.localizedDescription)", false)
        }
    }

    private func preferredLocalAgentBootstrapCandidate(
        excluding identifiers: Set<String>,
        using config: OpenClawConfig? = nil
    ) -> LocalAgentBootstrapCandidate? {
        let normalizedExcludedIdentifiers = Set(identifiers.map(normalizeAgentKey))
        let candidates = localAgentBootstrapCandidates(using: config).filter { candidate in
            !normalizedExcludedIdentifiers.contains(normalizeAgentKey(candidate.identifier))
        }

        return candidates.sorted { lhs, rhs in
            let lhsScore = (lhs.hasAuthProfiles ? 2 : 0) + (lhs.hasModels ? 1 : 0)
            let rhsScore = (rhs.hasAuthProfiles ? 2 : 0) + (rhs.hasModels ? 1 : 0)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            return lhs.identifier.localizedCaseInsensitiveCompare(rhs.identifier) == .orderedAscending
        }.first
    }

    private func localAgentBootstrapCandidates(
        using config: OpenClawConfig? = nil
    ) -> [LocalAgentBootstrapCandidate] {
        var candidates: [LocalAgentBootstrapCandidate] = []

        for source in localAgentBootstrapSourceDirectories(using: config) {
            candidates.append(contentsOf: bootstrapCandidates(in: source.directoryURL, sourceDescription: source.description))
        }

        if let directoryURL = userProvidedLocalBootstrapDirectory {
            candidates.append(contentsOf: bootstrapCandidates(in: directoryURL, sourceDescription: "手动指定路径"))
        }

        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = [
                normalizeAgentKey(candidate.identifier),
                candidate.authProfilesURL?.path ?? "",
                candidate.modelsURL?.path ?? ""
            ].joined(separator: "|")
            return seen.insert(key).inserted
        }
    }

    private func localAgentBootstrapSourceDirectories(
        using config: OpenClawConfig? = nil
    ) -> [(directoryURL: URL, description: String)] {
        let resolvedConfig = config ?? self.config
        return [
            (
                localOpenClawRootURL(using: resolvedConfig).appendingPathComponent("agents", isDirectory: true),
                "当前本地 runtime"
            )
        ]
    }

    private func bootstrapCandidates(
        in directoryURL: URL,
        sourceDescription: String
    ) -> [LocalAgentBootstrapCandidate] {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }

        if let directCandidate = directBootstrapCandidate(at: directoryURL, sourceDescription: sourceDescription) {
            return [directCandidate]
        }

        let nestedAgentsURL = directoryURL.appendingPathComponent("agents", isDirectory: true)
        if nestedAgentsURL.path != directoryURL.path,
           fileManager.fileExists(atPath: nestedAgentsURL.path) {
            let nestedCandidates = bootstrapCandidates(in: nestedAgentsURL, sourceDescription: sourceDescription)
            if !nestedCandidates.isEmpty {
                return nestedCandidates
            }
        }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { candidateRootURL in
            guard (try? candidateRootURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }

            return directBootstrapCandidate(at: candidateRootURL, sourceDescription: sourceDescription)
        }
    }

    private func directBootstrapCandidate(
        at directoryURL: URL,
        sourceDescription: String
    ) -> LocalAgentBootstrapCandidate? {
        let directAuthURL = directoryURL.appendingPathComponent("auth-profiles.json", isDirectory: false)
        let directModelsURL = directoryURL.appendingPathComponent("models.json", isDirectory: false)
        let nestedAgentDirectory = directoryURL.appendingPathComponent("agent", isDirectory: true)
        let nestedAuthURL = nestedAgentDirectory.appendingPathComponent("auth-profiles.json", isDirectory: false)
        let nestedModelsURL = nestedAgentDirectory.appendingPathComponent("models.json", isDirectory: false)

        let resolvedAuthURL: URL?
        let resolvedModelsURL: URL?
        if fileManager.fileExists(atPath: directAuthURL.path) || fileManager.fileExists(atPath: directModelsURL.path) {
            resolvedAuthURL = fileManager.fileExists(atPath: directAuthURL.path) ? directAuthURL : nil
            resolvedModelsURL = fileManager.fileExists(atPath: directModelsURL.path) ? directModelsURL : nil
        } else if fileManager.fileExists(atPath: nestedAuthURL.path) || fileManager.fileExists(atPath: nestedModelsURL.path) {
            resolvedAuthURL = fileManager.fileExists(atPath: nestedAuthURL.path) ? nestedAuthURL : nil
            resolvedModelsURL = fileManager.fileExists(atPath: nestedModelsURL.path) ? nestedModelsURL : nil
        } else {
            return nil
        }

        let identifierSourceURL = (directoryURL.lastPathComponent == "agent")
            ? directoryURL.deletingLastPathComponent()
            : directoryURL
        let identifier = identifierSourceURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else { return nil }

        return LocalAgentBootstrapCandidate(
            identifier: identifier,
            authProfilesURL: resolvedAuthURL,
            modelsURL: resolvedModelsURL,
            sourceDescription: "\(sourceDescription) \(directoryURL.path)"
        )
    }

    private func normalizedUserProvidedLocalBootstrapDirectory(_ directoryURL: URL) -> URL? {
        if directBootstrapCandidate(at: directoryURL, sourceDescription: "手动指定路径") != nil {
            return directoryURL
        }

        let agentsDirectory = directoryURL.appendingPathComponent("agents", isDirectory: true)
        if !bootstrapCandidates(in: agentsDirectory, sourceDescription: "手动指定路径").isEmpty {
            return agentsDirectory
        }

        if !bootstrapCandidates(in: directoryURL, sourceDescription: "手动指定路径").isEmpty {
            return directoryURL
        }

        return nil
    }

    private func normalizedUserProvidedLocalWorkspaceDirectory(_ directoryURL: URL) -> URL? {
        let standardizedURL = directoryURL.standardizedFileURL
        let isDirectory = (try? standardizedURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        guard isDirectory else { return nil }
        return standardizedURL
    }

    private func directoryHasContent(_ url: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return false
        }
        return !contents.isEmpty
    }

    private func visibleDirectoryEntryNames(in url: URL) -> Set<String> {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return Set(contents.map(\.lastPathComponent))
    }

    private func relativePath(of url: URL, from root: URL) -> String? {
        let normalizedRoot = root.standardizedFileURL.path
        let normalizedURL = url.standardizedFileURL.path
        guard normalizedURL == normalizedRoot || normalizedURL.hasPrefix(normalizedRoot + "/") else {
            return nil
        }

        let relative = String(normalizedURL.dropFirst(normalizedRoot.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? nil : relative
    }

    private func fileSystemItemsEqual(at lhs: URL, and rhs: URL) -> Bool {
        let fileManager = FileManager.default
        let lhsExists = fileManager.fileExists(atPath: lhs.path)
        let rhsExists = fileManager.fileExists(atPath: rhs.path)
        guard lhsExists == rhsExists else { return false }
        guard lhsExists else { return true }

        let lhsIsDirectory = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let rhsIsDirectory = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        guard lhsIsDirectory == rhsIsDirectory else { return false }

        if lhsIsDirectory {
            guard let lhsContents = try? fileManager.contentsOfDirectory(
                at: lhs,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ), let rhsContents = try? fileManager.contentsOfDirectory(
                at: rhs,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return false
            }

            let lhsByName = Dictionary(uniqueKeysWithValues: lhsContents.map { ($0.lastPathComponent, $0) })
            let rhsByName = Dictionary(uniqueKeysWithValues: rhsContents.map { ($0.lastPathComponent, $0) })
            guard lhsByName.keys == rhsByName.keys else { return false }

            for name in lhsByName.keys.sorted() {
                guard let lhsChild = lhsByName[name], let rhsChild = rhsByName[name] else {
                    return false
                }
                if !fileSystemItemsEqual(at: lhsChild, and: rhsChild) {
                    return false
                }
            }

            return true
        }

        guard let lhsData = try? Data(contentsOf: lhs),
              let rhsData = try? Data(contentsOf: rhs) else {
            return false
        }
        return lhsData == rhsData
    }

    private func removeDirectoryContents(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }

        let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        for item in contents {
            try? fileManager.removeItem(at: item)
        }
    }

    private func mergeDirectoryContents(of destination: URL, withContentsOf source: URL) throws -> Int {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else { return 0 }

        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let contents = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var copiedItemCount = 0

        for item in contents {
            let target = destination.appendingPathComponent(item.lastPathComponent, isDirectory: false)
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true

            if isDirectory {
                var targetIsDirectory = false
                if fileManager.fileExists(atPath: target.path) {
                    targetIsDirectory = (try? target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    if !targetIsDirectory {
                        try fileManager.removeItem(at: target)
                    }
                }

                if !targetIsDirectory {
                    try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                }

                copiedItemCount += try mergeDirectoryContents(of: target, withContentsOf: item)
                copiedItemCount += 1
                continue
            }

            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: item, to: target)
            copiedItemCount += 1
        }

        return copiedItemCount
    }

    private func replaceDirectoryContents(of destination: URL, withContentsOf source: URL) throws -> Int {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        try removeDirectoryContents(at: destination)

        guard fileManager.fileExists(atPath: source.path) else { return 0 }

        let contents = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        var copiedItemCount = 0
        for item in contents {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: item, to: target)
            copiedItemCount += 1
        }
        return copiedItemCount
    }

    private func prepareDiscoverySnapshot(using config: OpenClawConfig) throws -> URL {
        guard config.deploymentKind == .container else {
            throw NSError(domain: "OpenClawManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "仅容器模式需要 discovery snapshot"])
        }

        let discoveryContext = try resolveOpenClawDiscoveryContext(using: config, requiresInspectionRoot: true)
        guard
            let snapshotURL = discoveryContext.inspectionRootURL,
            discoveryContext.usesSnapshot
        else {
            throw NSError(domain: "OpenClawManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法解析容器内 OpenClaw 路径"])
        }

        return snapshotURL
    }

    private func clearDiscoverySnapshot() {
        guard let discoverySnapshotContext else { return }
        try? FileManager.default.removeItem(at: discoverySnapshotContext.snapshotURL)
        self.discoverySnapshotContext = nil
    }

    private func resolveSessionDeploymentDescriptor(
        using config: OpenClawConfig
    ) throws -> SessionDeploymentDescriptor {
        switch config.deploymentKind {
        case .local:
            let rootURL = localOpenClawRootURL(using: config)
            return SessionDeploymentDescriptor(
                config: config,
                scopeKey: openClawDiscoveryScopeKey(for: config),
                localRootURL: rootURL,
                deploymentRootPath: rootURL.path
            )
        case .container:
            guard let deploymentRootPath = containerOpenClawRootPath(for: config) else {
                throw NSError(
                    domain: "OpenClawManager",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "无法解析容器内 OpenClaw 路径"]
                )
            }

            return SessionDeploymentDescriptor(
                config: config,
                scopeKey: openClawDiscoveryScopeKey(for: config),
                localRootURL: nil,
                deploymentRootPath: deploymentRootPath
            )
        case .remoteServer:
            return SessionDeploymentDescriptor(
                config: config,
                scopeKey: openClawDiscoveryScopeKey(for: config),
                localRootURL: nil,
                deploymentRootPath: nil
            )
        }
    }

    private func openClawDiscoveryScopeKey(for config: OpenClawConfig) -> String {
        switch config.deploymentKind {
        case .local:
            return "local|\(localOpenClawRootURL(using: config).path)"
        case .container:
            return [
                "container",
                containerEngine(for: config),
                containerName(for: config) ?? "",
                resolveOpenClawPath(for: config)
            ].joined(separator: "|")
        case .remoteServer:
            return [
                "remote",
                config.host.trimmingCharacters(in: .whitespacesAndNewlines),
                String(config.port),
                config.useSSL ? "ssl" : "plain"
            ].joined(separator: "|")
        }
    }

    private func resolveOpenClawDiscoveryContext(
        using config: OpenClawConfig,
        requiresInspectionRoot: Bool = false
    ) throws -> OpenClawDiscoveryContext {
        switch config.deploymentKind {
        case .local:
            let rootURL = localOpenClawRootURL(using: config)
            return OpenClawDiscoveryContext(
                deploymentKind: .local,
                deploymentRootPath: rootURL.path,
                inspectionRootURL: requiresInspectionRoot ? rootURL : nil,
                configURL: rootURL.appendingPathComponent("openclaw.json"),
                usesSnapshot: false
            )
        case .container:
            guard let deploymentRootPath = containerOpenClawRootPath(for: config) else {
                return OpenClawDiscoveryContext(
                    deploymentKind: .container,
                    deploymentRootPath: nil,
                    inspectionRootURL: nil,
                    configURL: nil,
                    usesSnapshot: false
                )
            }

            let inspectionRootURL: URL?
            if requiresInspectionRoot {
                inspectionRootURL = try containerInspectionRootURL(
                    using: config,
                    deploymentRootPath: deploymentRootPath
                )
            } else {
                inspectionRootURL = nil
            }

            return OpenClawDiscoveryContext(
                deploymentKind: .container,
                deploymentRootPath: deploymentRootPath,
                inspectionRootURL: inspectionRootURL,
                configURL: inspectionRootURL?.appendingPathComponent("openclaw.json"),
                usesSnapshot: inspectionRootURL != nil
            )
        case .remoteServer:
            return OpenClawDiscoveryContext(
                deploymentKind: .remoteServer,
                deploymentRootPath: nil,
                inspectionRootURL: nil,
                configURL: nil,
                usesSnapshot: false
            )
        }
    }

    func resolveOpenClawGovernancePaths(
        using config: OpenClawConfig,
        requiresInspectionRoot: Bool = false
    ) throws -> OpenClawGovernancePaths {
        let discoveryContext = try resolveOpenClawDiscoveryContext(
            using: config,
            requiresInspectionRoot: requiresInspectionRoot
        )

        let rootURL: URL?
        switch discoveryContext.deploymentKind {
        case .local:
            if let inspectionRootURL = discoveryContext.inspectionRootURL {
                rootURL = inspectionRootURL
            } else if let deploymentRootPath = discoveryContext.deploymentRootPath {
                rootURL = URL(fileURLWithPath: deploymentRootPath, isDirectory: true)
            } else {
                rootURL = nil
            }
        case .container:
            rootURL = discoveryContext.inspectionRootURL
        case .remoteServer:
            rootURL = nil
        }

        let configURL = discoveryContext.configURL ?? rootURL?.appendingPathComponent("openclaw.json", isDirectory: false)
        let approvalsURL: URL?
        if let rootURL {
            let candidate = rootURL.appendingPathComponent("exec-approvals.json", isDirectory: false)
            approvalsURL = fileManager.fileExists(atPath: candidate.path) ? candidate : nil
        } else {
            approvalsURL = nil
        }

        return OpenClawGovernancePaths(
            rootURL: rootURL,
            configURL: configURL,
            approvalsURL: approvalsURL
        )
    }

    private func containerInspectionRootURL(
        using config: OpenClawConfig,
        deploymentRootPath: String
    ) throws -> URL {
        let scopeKey = openClawDiscoveryScopeKey(for: config)

        if let discoverySnapshotContext,
           discoverySnapshotContext.scopeKey == scopeKey,
           discoverySnapshotContext.deploymentRootPath == deploymentRootPath,
           fileManager.fileExists(atPath: discoverySnapshotContext.snapshotURL.path) {
            return discoverySnapshotContext.snapshotURL
        }

        clearDiscoverySnapshot()

        let snapshotURL = backupDirectory.appendingPathComponent("discovery-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: snapshotURL, withIntermediateDirectories: true)
        _ = try copyDeploymentContentsToLocal(snapshotURL, deploymentRootPath: deploymentRootPath, using: config)
        discoverySnapshotContext = OpenClawDiscoverySnapshotContext(
            snapshotURL: snapshotURL,
            scopeKey: scopeKey,
            deploymentRootPath: deploymentRootPath
        )
        return snapshotURL
    }

    private func containerEngine(for config: OpenClawConfig) -> String {
        let trimmed = config.container.engine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "docker" : trimmed
    }

    private func containerName(for config: OpenClawConfig) -> String? {
        let trimmed = config.container.containerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func containerOpenClawRootFallbackCandidates(
        for config: OpenClawConfig,
        homeDirectoryOverride: String? = nil
    ) -> [String] {
        guard config.deploymentKind == .container else { return [] }

        var candidates: [String] = []
        func appendCandidate(_ candidate: String?) {
            guard let candidate,
                  !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !candidates.contains(candidate) else { return }
            candidates.append(candidate)
        }

        let homeDirectory = (homeDirectoryOverride ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !homeDirectory.isEmpty {
            appendCandidate(
                URL(fileURLWithPath: homeDirectory, isDirectory: true)
                    .appendingPathComponent(".openclaw", isDirectory: true)
                    .path
            )
            appendCandidate(
                URL(fileURLWithPath: homeDirectory, isDirectory: true)
                    .appendingPathComponent("openclaw", isDirectory: true)
                    .path
            )
        }

        [
            "/root/.openclaw",
            "/home/node/.openclaw",
            "/home/app/.openclaw",
            "/app/.openclaw",
            "/workspace/.openclaw",
            "/workspace/openclaw",
            "/workspaces/.openclaw",
            "/workspaces/openclaw"
        ].forEach { appendCandidate($0) }

        let workspaceMountPath = config.container.workspaceMountPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !workspaceMountPath.isEmpty {
            appendCandidate(
                URL(fileURLWithPath: workspaceMountPath, isDirectory: true)
                    .appendingPathComponent(".openclaw", isDirectory: true)
                    .path
            )
            appendCandidate(
                URL(fileURLWithPath: workspaceMountPath, isDirectory: true)
                    .appendingPathComponent("openclaw", isDirectory: true)
                    .path
            )
            appendCandidate(workspaceMountPath)
        }

        return candidates
    }

    func containerOpenClawRootDiscoveryScript(workspaceMountPath: String) -> String {
        let trimmedWorkspaceMountPath = workspaceMountPath.trimmingCharacters(in: .whitespacesAndNewlines)

        var script = """
        probe_candidate() {
          candidate="$1"
          if [ -n "$candidate" ] && [ -d "$candidate" ]; then
            if [ -f "$candidate/openclaw.json" ] || [ -d "$candidate/agents" ]; then
              printf '%s' "$candidate"
              return 0
            fi
          fi
          return 1
        }

        for candidate in \
          "${OPENCLAW_ROOT:-}" \
          "${OPENCLAW_HOME:-}" \
          "${OPENCLAW_PATH:-}" \
          "${XDG_CONFIG_HOME:-$HOME/.config}/openclaw" \
          "${XDG_CONFIG_HOME:-$HOME/.config}/.openclaw" \
          "${XDG_DATA_HOME:-$HOME/.local/share}/openclaw" \
          "${XDG_DATA_HOME:-$HOME/.local/share}/.openclaw" \
          "$HOME/.openclaw" \
          "$HOME/openclaw" \
          "/root/.openclaw" \
          "/home/node/.openclaw" \
          "/home/app/.openclaw" \
          "/app/.openclaw" \
          "/workspace/.openclaw" \
          "/workspace/openclaw" \
          "/workspaces/.openclaw" \
          "/workspaces/openclaw"; do
          probe_candidate "$candidate" && exit 0
        done
        """

        if !trimmedWorkspaceMountPath.isEmpty {
            let workspaceCandidates = [
                URL(fileURLWithPath: trimmedWorkspaceMountPath, isDirectory: true)
                    .appendingPathComponent(".openclaw", isDirectory: true)
                    .path,
                URL(fileURLWithPath: trimmedWorkspaceMountPath, isDirectory: true)
                    .appendingPathComponent("openclaw", isDirectory: true)
                    .path
            ]

            script += "\n"
            for candidate in workspaceCandidates {
                script += "probe_candidate \(shellQuoted(candidate)) && exit 0\n"
            }
        }

        script += """

        for root in \
          "$HOME" \
          "/root" \
          "/home/node" \
          "/home/app" \
          "/app" \
          "/workspace" \
          "/workspaces" \
          "/tmp" \
          "/opt"; do
          [ -d "$root" ] || continue

          found_json="$(find "$root" -maxdepth 5 -type f -name openclaw.json 2>/dev/null | head -n 1)"
          if [ -n "$found_json" ]; then
            dirname "$found_json"
            exit 0
          fi

          found_agents="$(find "$root" -maxdepth 5 -type d -name agents 2>/dev/null | head -n 1)"
          if [ -n "$found_agents" ]; then
            dirname "$found_agents"
            exit 0
          fi
        done
        """

        return script
    }

    func firstReachableOpenClawRootCandidate(
        from candidates: [String],
        exists: (String) -> Bool
    ) -> String? {
        for candidate in candidates {
            let normalizedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedCandidate.isEmpty else { continue }
            if exists(normalizedCandidate) {
                return normalizedCandidate
            }
        }
        return nil
    }

    private func containerOpenClawRootPath(for config: OpenClawConfig) -> String? {
        if let discoveredRoot = discoverContainerOpenClawRootPath(using: config) {
            return discoveredRoot
        }

        let homeDirectory = queryContainerHomeDirectory(using: config)
        return firstReachableOpenClawRootCandidate(
            from: containerOpenClawRootFallbackCandidates(
                for: config,
                homeDirectoryOverride: homeDirectory
            )
        ) { [weak self] candidate in
            guard let self else { return false }
            return self.containerPathExists(candidate, using: config)
        }
    }

    private func discoverContainerOpenClawRootPath(using config: OpenClawConfig) -> String? {
        guard let containerName = containerName(for: config) else { return nil }

        let script = containerOpenClawRootDiscoveryScript(
            workspaceMountPath: config.container.workspaceMountPath
        )

        let result = try? runDeploymentCommand(
            using: config,
            arguments: ["exec", containerName, "sh", "-lc", script]
        )

        guard let result, result.terminationStatus == 0 else { return nil }

        let output = String(data: result.standardOutput, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !output.isEmpty else { return nil }

        return output
    }

    private func containerPathExists(_ candidatePath: String, using config: OpenClawConfig) -> Bool {
        guard let containerName = containerName(for: config) else { return false }

        let normalizedCandidatePath = candidatePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCandidatePath.isEmpty else { return false }

        let result = try? runDeploymentCommand(
            using: config,
            arguments: ["exec", containerName, "sh", "-lc", "test -e \(shellQuoted(normalizedCandidatePath))"],
            timeoutSeconds: TimeInterval(max(config.timeout, 5))
        )

        return result?.terminationStatus == 0
    }

    private func queryContainerHomeDirectory(using config: OpenClawConfig) -> String? {
        guard let containerName = containerName(for: config) else { return nil }

        let result = try? runDeploymentCommand(
            using: config,
            arguments: ["exec", containerName, "sh", "-lc", "printf %s \"$HOME\""]
        )

        guard let result, result.terminationStatus == 0 else { return nil }

        let output = String(data: result.standardOutput, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return output.isEmpty ? nil : output
    }

    private func runDeploymentCommand(
        using config: OpenClawConfig,
        arguments: [String],
        standardInput: FileHandle? = nil,
        timeoutSeconds: TimeInterval? = nil
    ) throws -> (terminationStatus: Int32, standardOutput: Data, standardError: Data) {
        try host.runDeploymentCommand(
            using: config,
            arguments: arguments,
            standardInput: standardInput,
            timeoutSeconds: timeoutSeconds
        )
    }

    private func copyDeploymentContentsToLocal(
        _ localDestination: URL,
        deploymentRootPath: String,
        using config: OpenClawConfig
    ) throws -> Int {
        switch config.deploymentKind {
        case .local:
            let source = URL(fileURLWithPath: deploymentRootPath, isDirectory: true)
            return try replaceDirectoryContents(of: localDestination, withContentsOf: source)
        case .container:
            try FileManager.default.createDirectory(at: localDestination, withIntermediateDirectories: true)
            try removeDirectoryContents(at: localDestination)

            guard let containerName = containerName(for: config) else { return 0 }

            let command = "cd \(shellQuoted(deploymentRootPath)) && tar -cf - ."
            let result = try runDeploymentCommand(
                using: config,
                arguments: ["exec", containerName, "sh", "-lc", command]
            )

            guard result.terminationStatus == 0, !result.standardOutput.isEmpty else {
                return 0
            }

            let archiveURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("openclaw-snapshot-\(UUID().uuidString).tar", isDirectory: false)
            try result.standardOutput.write(to: archiveURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: archiveURL) }

            let extract = try OpenClawHost.executeProcessAndCaptureOutput(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["tar", "-xf", archiveURL.path, "-C", localDestination.path],
                timeoutSeconds: 60
            )

            guard extract.terminationStatus == 0 else {
                let message = String(data: result.standardError, encoding: .utf8) ?? "容器快照同步失败"
                throw NSError(domain: "OpenClawManager", code: Int(extract.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
            }

            let contents = try? FileManager.default.contentsOfDirectory(at: localDestination, includingPropertiesForKeys: nil)
            return contents?.count ?? 0
        case .remoteServer:
            return 0
        }
    }

    private func copyLocalContentsToDeployment(
        _ localSource: URL,
        deploymentRootPath: String,
        using config: OpenClawConfig
    ) throws {
        try transferLocalContentsToDeployment(
            localSource,
            deploymentPath: deploymentRootPath,
            using: config,
            replaceExistingContents: true
        )
    }

    private func applyManagedSessionMirrorContents(
        from mirrorURL: URL,
        deploymentRootPath: String,
        using config: OpenClawConfig
    ) throws {
        for entryName in Self.managedSessionMirrorTopLevelEntries.sorted() {
            let sourceURL = mirrorURL.appendingPathComponent(entryName, isDirectory: true)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }

            let deploymentPath = URL(fileURLWithPath: deploymentRootPath, isDirectory: true)
                .appendingPathComponent(entryName, isDirectory: true)
                .path
            try transferLocalContentsToDeployment(
                sourceURL,
                deploymentPath: deploymentPath,
                using: config,
                replaceExistingContents: false
            )
        }
    }

    private func transferLocalContentsToDeployment(
        _ localSource: URL,
        deploymentPath: String,
        using config: OpenClawConfig,
        replaceExistingContents: Bool
    ) throws {
        switch config.deploymentKind {
        case .local:
            let destination = URL(fileURLWithPath: deploymentPath, isDirectory: true)
            if replaceExistingContents {
                _ = try replaceDirectoryContents(of: destination, withContentsOf: localSource)
            } else if FileManager.default.fileExists(atPath: localSource.path) {
                _ = try mergeDirectoryContents(of: destination, withContentsOf: localSource)
            }
        case .container:
            guard let containerName = containerName(for: config) else { return }
            guard FileManager.default.fileExists(atPath: localSource.path) else { return }

            let archiveURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("openclaw-upload-\(UUID().uuidString).tar", isDirectory: false)
            let createArchive = try OpenClawHost.executeProcessAndCaptureOutput(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["tar", "-cf", archiveURL.path, "-C", localSource.path, "."],
                timeoutSeconds: 60
            )

            guard createArchive.terminationStatus == 0 else {
                try? FileManager.default.removeItem(at: archiveURL)
                throw NSError(domain: "OpenClawManager", code: Int(createArchive.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "本地快照打包失败"])
            }

            defer { try? FileManager.default.removeItem(at: archiveURL) }

            if replaceExistingContents {
                let clearCommand = "mkdir -p \(shellQuoted(deploymentPath)) && find \(shellQuoted(deploymentPath)) -mindepth 1 -maxdepth 1 -exec rm -rf {} +"
                let clearResult = try runDeploymentCommand(
                    using: config,
                    arguments: ["exec", containerName, "sh", "-lc", clearCommand]
                )
                guard clearResult.terminationStatus == 0 else {
                    let message = String(data: clearResult.standardError, encoding: .utf8) ?? "容器目录清理失败"
                    throw NSError(domain: "OpenClawManager", code: Int(clearResult.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
                }
            }

            let input = try FileHandle(forReadingFrom: archiveURL)
            defer { input.closeFile() }

            let extractCommand = "mkdir -p \(shellQuoted(deploymentPath)) && tar -xf - -C \(shellQuoted(deploymentPath))"
            let extractResult = try runDeploymentCommand(
                using: config,
                arguments: ["exec", "-i", containerName, "sh", "-lc", extractCommand],
                standardInput: input
            )

            guard extractResult.terminationStatus == 0 else {
                let message = String(data: extractResult.standardError, encoding: .utf8) ?? "容器文件同步失败"
                throw NSError(domain: "OpenClawManager", code: Int(extractResult.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
            }
        case .remoteServer:
            return
        }
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    func resolvedLocalBinaryPath(for config: OpenClawConfig) -> String {
        host.resolveLocalBinaryPath(for: config)
    }

    private func resolveOpenClawPath(for config: OpenClawConfig) -> String {
        host.resolveLocalBinaryPath(for: config)
    }

    private static func parseAgentNames(from output: String) -> [String] {
        output
            .components(separatedBy: .newlines)
            .compactMap { line in
                guard line.hasPrefix("- ") else { return nil }
                let raw = String(line.dropFirst(2))
                return raw.components(separatedBy: " (").first?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    private func runLocalConnectionTest(
        config: OpenClawConfig,
        completion: @escaping (Bool, String, [String]) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let binaryPath = self.host.resolveLocalBinaryPath(for: config)
            guard FileManager.default.fileExists(atPath: binaryPath) else {
                DispatchQueue.main.async {
                    completion(false, "未找到 OpenClaw 可执行文件：\(binaryPath)", [])
                }
                return
            }

            do {
                let result = try self.runOpenClawCommand(
                    using: config,
                    arguments: ["agents", "list"],
                    timeoutSeconds: TimeInterval(max(config.timeout, 5))
                )
                let output = String(
                    data: result.standardOutput + result.standardError,
                    encoding: .utf8
                ) ?? ""
                let agentNames = Self.parseAgentNames(from: output)
                let success = result.terminationStatus == 0
                let message: String

                if success {
                    message = "OpenClaw CLI 可用，发现 \(agentNames.count) 个 agents"
                } else {
                    let fallback = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    message = fallback.isEmpty ? "OpenClaw 本地连接失败" : fallback
                }

                guard success else {
                    DispatchQueue.main.async {
                        self.discoveryResults = []
                        self.agents = []
                        completion(false, message, [])
                    }
                    return
                }

                guard let gatewayConfig = self.preferredGatewayConfig(using: config) else {
                    DispatchQueue.main.async {
                        self.discoveryResults = self.inspectOpenClawAgents(using: config, fallbackAgentNames: agentNames)
                        if self.discoveryResults.isEmpty {
                            self.discoveryResults = agentNames.map {
                                ProjectOpenClawDetectedAgentRecord(
                                    id: $0,
                                    name: $0,
                                    directoryValidated: false,
                                    configValidated: false,
                                    issues: ["CLI 可用，但本地 Gateway 配置不可用。"]
                                )
                            }
                        }
                        self.agents = self.discoveryResults.map(\.name)
                        completion(false, "OpenClaw CLI 可用，但本地 Gateway 配置不可用。", agentNames)
                    }
                    return
                }

                _Concurrency.Task {
                    do {
                        let probe = try await self.gatewayClient.probe(using: gatewayConfig)
                        let resolvedAgentNames = probe.agentNames.isEmpty ? agentNames : probe.agentNames

                        DispatchQueue.main.async {
                            self.discoveryResults = self.inspectOpenClawAgents(using: config, fallbackAgentNames: resolvedAgentNames)
                            if self.discoveryResults.isEmpty {
                                self.discoveryResults = resolvedAgentNames.map {
                                    ProjectOpenClawDetectedAgentRecord(
                                        id: $0,
                                        name: $0,
                                        directoryValidated: false,
                                        configValidated: false,
                                        issues: ["未发现可验证的 agent 文件，仅保留 CLI/Gateway 结果。"]
                                    )
                                }
                            }
                            self.agents = self.discoveryResults.map(\.name)
                            completion(
                                true,
                                "本地 OpenClaw CLI 与 Gateway 连接成功：ws://127.0.0.1:\(gatewayConfig.port)",
                                resolvedAgentNames
                            )
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.discoveryResults = self.inspectOpenClawAgents(using: config, fallbackAgentNames: agentNames)
                            self.agents = self.discoveryResults.map(\.name)
                            completion(false, "OpenClaw CLI 可用，但 Gateway 不可用：\(error.localizedDescription)", agentNames)
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription, [])
                }
            }
        }
    }

    private func runContainerConnectionTest(
        config: OpenClawConfig,
        completion: @escaping (Bool, String, [String]) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let containerName = config.container.containerName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !containerName.isEmpty else {
                DispatchQueue.main.async {
                    completion(false, "请先填写容器名称", [])
                }
                return
            }

            do {
                let result = try self.runOpenClawCommand(
                    using: config,
                    arguments: ["agents", "list"],
                    timeoutSeconds: TimeInterval(max(config.timeout, 5))
                )
                let output = String(
                    data: result.standardOutput + result.standardError,
                    encoding: .utf8
                ) ?? ""
                let agentNames = Self.parseAgentNames(from: output)
                let success = result.terminationStatus == 0
                let message: String

                if success {
                    message = "容器连接成功，发现 \(agentNames.count) 个 OpenClaw agents"
                } else {
                    let fallback = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    message = fallback.isEmpty ? "OpenClaw 容器连接失败" : fallback
                }

                guard success else {
                    DispatchQueue.main.async {
                        self.discoveryResults = []
                        self.agents = []
                        completion(false, message, [])
                    }
                    return
                }

                guard let gatewayConfig = self.preferredGatewayConfig(using: config) else {
                    DispatchQueue.main.async {
                        self.discoveryResults = self.inspectOpenClawAgents(using: config, fallbackAgentNames: agentNames)
                        if self.discoveryResults.isEmpty {
                            self.discoveryResults = agentNames.map {
                                ProjectOpenClawDetectedAgentRecord(
                                    id: $0,
                                    name: $0,
                                    directoryValidated: false,
                                    configValidated: false,
                                    issues: ["CLI 可用，但容器 Gateway 配置不可用。"]
                                )
                            }
                        }
                        self.agents = self.discoveryResults.map(\.name)
                        completion(false, "OpenClaw CLI 可用，但容器 Gateway 配置不可用。", agentNames)
                    }
                    return
                }

                _Concurrency.Task {
                    do {
                        let probe = try await self.gatewayClient.probe(using: gatewayConfig)
                        let resolvedAgentNames = probe.agentNames.isEmpty ? agentNames : probe.agentNames

                        DispatchQueue.main.async {
                            self.discoveryResults = self.inspectOpenClawAgents(using: config, fallbackAgentNames: resolvedAgentNames)
                            if self.discoveryResults.isEmpty {
                                self.discoveryResults = resolvedAgentNames.map {
                                    ProjectOpenClawDetectedAgentRecord(
                                        id: $0,
                                        name: $0,
                                        directoryValidated: false,
                                        configValidated: false,
                                        issues: ["未发现可验证的 agent 文件，仅保留 CLI/Gateway 结果。"]
                                    )
                                }
                            }
                            self.agents = self.discoveryResults.map(\.name)
                            completion(
                                true,
                                "容器内 OpenClaw CLI 与 Gateway 连接成功：\((gatewayConfig.useSSL ? "wss" : "ws"))://\(gatewayConfig.host):\(gatewayConfig.port)",
                                resolvedAgentNames
                            )
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.discoveryResults = self.inspectOpenClawAgents(using: config, fallbackAgentNames: agentNames)
                            self.agents = self.discoveryResults.map(\.name)
                            completion(false, "OpenClaw CLI 可用，但容器 Gateway 不可用：\(error.localizedDescription)", agentNames)
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription, [])
                }
            }
        }
    }

    private func runRemoteConnectionTest(
        config: OpenClawConfig,
        completion: @escaping (Bool, String, [String]) -> Void
    ) {
        let host = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            completion(false, "请先填写远程主机地址", [])
            return
        }

        _Concurrency.Task {
            do {
                let probe = try await gatewayClient.probe(using: config)
                DispatchQueue.main.async {
                    self.discoveryResults = probe.agents.map { agent in
                        ProjectOpenClawDetectedAgentRecord(
                            id: agent.id,
                            name: agent.name,
                            directoryValidated: true,
                            configValidated: true
                        )
                    }
                    self.agents = self.discoveryResults.map(\.name)
                    completion(
                        true,
                        "远程网关连接成功：\((config.useSSL ? "wss" : "ws"))://\(host):\(config.port)",
                        probe.agentNames
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    self.discoveryResults = []
                    self.agents = []
                    completion(false, error.localizedDescription, [])
                }
            }
        }
    }
    
    // 备份当前OpenClaw配置
    func backup() -> Bool {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupPath = backupDirectory.appendingPathComponent("backup-\(timestamp)")
        
        do {
            try FileManager.default.createDirectory(at: backupPath, withIntermediateDirectories: true)
            
            let fileManager = FileManager.default
            let openClawRootURL = localOpenClawRootURL()
            
            // 备份agents目录
            let agentsSrc = openClawRootURL.appendingPathComponent("agents", isDirectory: true)
            let agentsDst = backupPath.appendingPathComponent("agents")
            if fileManager.fileExists(atPath: agentsSrc.path) {
                try fileManager.copyItem(at: agentsSrc, to: agentsDst)
            }
            
            // 备份workspaces
            for item in try fileManager.contentsOfDirectory(atPath: openClawRootURL.path) {
                if item.hasPrefix("workspace") {
                    let src = openClawRootURL.appendingPathComponent(item)
                    let dst = backupPath.appendingPathComponent(item)
                    try fileManager.copyItem(at: src, to: dst)
                }
            }
            
            print("Backup created at: \(backupPath)")
            return true
        } catch {
            print("Backup failed: \(error)")
            return false
        }
    }
    
    // 还原到备份
    func restore(backupPath: URL) -> Bool {
        do {
            let fileManager = FileManager.default
            let openClawRootURL = localOpenClawRootURL()
            
            // 恢复agents
            let agentsBackup = backupPath.appendingPathComponent("agents")
            let agentsDst = openClawRootURL.appendingPathComponent("agents", isDirectory: true)
            if fileManager.fileExists(atPath: agentsBackup.path) {
                if fileManager.fileExists(atPath: agentsDst.path) {
                    try fileManager.removeItem(at: agentsDst)
                }
                try fileManager.copyItem(at: agentsBackup, to: agentsDst)
            }
            
            // 恢复workspaces
            for item in try fileManager.contentsOfDirectory(atPath: backupPath.path) {
                if item.hasPrefix("workspace") {
                    let src = backupPath.appendingPathComponent(item)
                    let dst = openClawRootURL.appendingPathComponent(item)
                    if fileManager.fileExists(atPath: dst.path) {
                        try fileManager.removeItem(at: dst)
                    }
                    try fileManager.copyItem(at: src, to: dst)
                }
            }
            
            print("Restore completed from: \(backupPath)")
            return true
        } catch {
            print("Restore failed: \(error)")
            return false
        }
    }
    
    // 获取可用备份列表
    func listBackups() -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        
        return contents
            .filter { $0.hasDirectoryPath }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
    
    // 应用配置到OpenClaw（将架构中的agents同步到OpenClaw）
    func applyConfiguration(agents: [Agent]) -> Bool {
        // 备份当前配置
        guard backup() else { return false }
        
        // 这里可以实现将架构中的agent配置同步到OpenClaw
        // 目前只是占位实现
        print("Applying configuration for \(agents.count) agents")
        return true
    }
}
