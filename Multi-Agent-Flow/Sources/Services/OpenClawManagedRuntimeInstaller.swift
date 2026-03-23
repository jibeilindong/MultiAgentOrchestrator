import Foundation
import CryptoKit

struct OpenClawManagedRuntimePayloadManifest: Codable, Equatable {
    static let currentSchemaVersion = "openclaw.managed-runtime.payload.v1"

    var schemaVersion: String
    var payloadVersion: String
    var runtimeVersion: String
    var binaryRelativePath: String
    var distributionKind: String?
    var platform: String?

    init(
        schemaVersion: String = Self.currentSchemaVersion,
        payloadVersion: String,
        runtimeVersion: String,
        binaryRelativePath: String,
        distributionKind: String? = nil,
        platform: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.payloadVersion = payloadVersion
        self.runtimeVersion = runtimeVersion
        self.binaryRelativePath = binaryRelativePath
        self.distributionKind = distributionKind
        self.platform = platform
    }
}

struct OpenClawManagedRuntimeInstallReceipt: Codable, Equatable {
    static let currentSchemaVersion = "openclaw.managed-runtime.install.v1"

    var schemaVersion: String
    var payloadVersion: String
    var runtimeVersion: String
    var binaryRelativePath: String
    var payloadSHA256: String
    var sourcePath: String
    var installedAt: Date

    init(
        schemaVersion: String = Self.currentSchemaVersion,
        payloadVersion: String,
        runtimeVersion: String,
        binaryRelativePath: String,
        payloadSHA256: String,
        sourcePath: String,
        installedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.payloadVersion = payloadVersion
        self.runtimeVersion = runtimeVersion
        self.binaryRelativePath = binaryRelativePath
        self.payloadSHA256 = payloadSHA256
        self.sourcePath = sourcePath
        self.installedAt = installedAt
    }
}

enum OpenClawManagedRuntimeInstallStatus: Equatable {
    case unavailable
    case alreadyCurrent
    case installed
}

struct OpenClawManagedRuntimeInstallResult: Equatable {
    var status: OpenClawManagedRuntimeInstallStatus
    var message: String
    var payloadVersion: String?
    var runtimeVersion: String?
    var sourcePath: String?
    var destinationPath: String?
}

private struct OpenClawManagedRuntimeBundledPayload {
    var rootURL: URL
    var manifest: OpenClawManagedRuntimePayloadManifest
    var binaryURL: URL
    var payloadSHA256: String
}

final class OpenClawManagedRuntimeInstaller {
    static let shared = OpenClawManagedRuntimeInstaller()

    private let fileManager: FileManager
    private let bundleResourceURL: URL?
    private let appSupportRootDirectory: URL?
    private let payloadDirectoryNames: [String]

    init(
        fileManager: FileManager = .default,
        bundleResourceURL: URL? = Bundle.main.resourceURL,
        appSupportRootDirectory: URL? = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Multi-Agent-Flow", isDirectory: true),
        payloadDirectoryNames: [String] = ["OpenClaw", "openclaw"]
    ) {
        self.fileManager = fileManager
        self.bundleResourceURL = bundleResourceURL
        self.appSupportRootDirectory = appSupportRootDirectory
        self.payloadDirectoryNames = payloadDirectoryNames
    }

    func managedRuntimeRootURL() -> URL? {
        appSupportRootDirectory?
            .appendingPathComponent("openclaw", isDirectory: true)
            .appendingPathComponent("runtime", isDirectory: true)
    }

    func installBundledRuntimeIfNeeded() throws -> OpenClawManagedRuntimeInstallResult {
        guard let payload = try locateBundledPayload() else {
            return OpenClawManagedRuntimeInstallResult(
                status: .unavailable,
                message: "No bundled OpenClaw managed runtime payload was found.",
                payloadVersion: nil,
                runtimeVersion: nil,
                sourcePath: nil,
                destinationPath: managedRuntimeRootURL()?.path
            )
        }

        guard let managedRuntimeRootURL = managedRuntimeRootURL() else {
            return OpenClawManagedRuntimeInstallResult(
                status: .unavailable,
                message: "Application Support root is unavailable; cannot install managed runtime.",
                payloadVersion: payload.manifest.payloadVersion,
                runtimeVersion: payload.manifest.runtimeVersion,
                sourcePath: payload.rootURL.path,
                destinationPath: nil
            )
        }

        let parentDirectory = managedRuntimeRootURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        if let receipt = try loadInstallReceipt(at: managedRuntimeRootURL),
           receipt.payloadVersion == payload.manifest.payloadVersion,
           receipt.runtimeVersion == payload.manifest.runtimeVersion,
           receipt.payloadSHA256 == payload.payloadSHA256,
           fileManager.fileExists(
                atPath: managedRuntimeRootURL
                    .appendingPathComponent(receipt.binaryRelativePath, isDirectory: false)
                    .path
           ) {
            return OpenClawManagedRuntimeInstallResult(
                status: .alreadyCurrent,
                message: "Managed runtime payload \(receipt.payloadVersion) is already installed.",
                payloadVersion: receipt.payloadVersion,
                runtimeVersion: receipt.runtimeVersion,
                sourcePath: payload.rootURL.path,
                destinationPath: managedRuntimeRootURL.path
            )
        }

        let stagingURL = parentDirectory.appendingPathComponent(
            "runtime.staging-\(UUID().uuidString)",
            isDirectory: true
        )
        let backupURL = parentDirectory.appendingPathComponent("runtime.previous", isDirectory: true)

        try? fileManager.removeItem(at: stagingURL)
        try? fileManager.removeItem(at: backupURL)

        do {
            try fileManager.copyItem(at: payload.rootURL, to: stagingURL)

            let stagedBinaryURL = stagingURL.appendingPathComponent(
                payload.manifest.binaryRelativePath,
                isDirectory: false
            )
            guard fileManager.fileExists(atPath: stagedBinaryURL.path) else {
                throw NSError(
                    domain: "OpenClawManagedRuntimeInstaller",
                    code: 2001,
                    userInfo: [NSLocalizedDescriptionKey: "Bundled payload is missing its runtime binary."]
                )
            }

            try ensureExecutablePermissions(at: stagedBinaryURL)
            try writeInstallReceipt(
                OpenClawManagedRuntimeInstallReceipt(
                    payloadVersion: payload.manifest.payloadVersion,
                    runtimeVersion: payload.manifest.runtimeVersion,
                    binaryRelativePath: payload.manifest.binaryRelativePath,
                    payloadSHA256: payload.payloadSHA256,
                    sourcePath: payload.rootURL.path
                ),
                to: stagingURL
            )

            if fileManager.fileExists(atPath: managedRuntimeRootURL.path) {
                try fileManager.moveItem(at: managedRuntimeRootURL, to: backupURL)
            }

            try fileManager.moveItem(at: stagingURL, to: managedRuntimeRootURL)
            try? fileManager.removeItem(at: backupURL)

            return OpenClawManagedRuntimeInstallResult(
                status: .installed,
                message: "Installed managed OpenClaw runtime payload \(payload.manifest.payloadVersion).",
                payloadVersion: payload.manifest.payloadVersion,
                runtimeVersion: payload.manifest.runtimeVersion,
                sourcePath: payload.rootURL.path,
                destinationPath: managedRuntimeRootURL.path
            )
        } catch {
            if fileManager.fileExists(atPath: stagingURL.path) {
                try? fileManager.removeItem(at: stagingURL)
            }
            if fileManager.fileExists(atPath: backupURL.path),
               !fileManager.fileExists(atPath: managedRuntimeRootURL.path) {
                try? fileManager.moveItem(at: backupURL, to: managedRuntimeRootURL)
            }
            throw error
        }
    }

    private func locateBundledPayload() throws -> OpenClawManagedRuntimeBundledPayload? {
        guard let bundleResourceURL else { return nil }

        for directoryName in payloadDirectoryNames {
            let payloadRootURL = bundleResourceURL.appendingPathComponent(directoryName, isDirectory: true)
            let manifestURL = payloadRootURL.appendingPathComponent("managed-runtime.json", isDirectory: false)

            guard fileManager.fileExists(atPath: manifestURL.path) else { continue }

            let manifest = try decode(OpenClawManagedRuntimePayloadManifest.self, from: manifestURL)
            let binaryURL = payloadRootURL.appendingPathComponent(manifest.binaryRelativePath, isDirectory: false)

            guard fileManager.fileExists(atPath: binaryURL.path) else { continue }
            let payloadSHA256 = try computeDirectorySHA256(at: payloadRootURL)

            return OpenClawManagedRuntimeBundledPayload(
                rootURL: payloadRootURL,
                manifest: manifest,
                binaryURL: binaryURL,
                payloadSHA256: payloadSHA256
            )
        }

        return nil
    }

    private func loadInstallReceipt(at runtimeRootURL: URL) throws -> OpenClawManagedRuntimeInstallReceipt? {
        let receiptURL = runtimeRootURL.appendingPathComponent("install-receipt.json", isDirectory: false)
        guard fileManager.fileExists(atPath: receiptURL.path) else { return nil }
        return try decode(OpenClawManagedRuntimeInstallReceipt.self, from: receiptURL)
    }

    private func writeInstallReceipt(
        _ receipt: OpenClawManagedRuntimeInstallReceipt,
        to runtimeRootURL: URL
    ) throws {
        let receiptURL = runtimeRootURL.appendingPathComponent("install-receipt.json", isDirectory: false)
        try encode(receipt, to: receiptURL)
    }

    private func ensureExecutablePermissions(at binaryURL: URL) throws {
        let attributes = try fileManager.attributesOfItem(atPath: binaryURL.path)
        let currentPermissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o755
        let normalizedPermissions = currentPermissions | 0o111
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: normalizedPermissions)],
            ofItemAtPath: binaryURL.path
        )
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }

    private func computeDirectorySHA256(at rootURL: URL) throws -> String {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw NSError(
                domain: "OpenClawManagedRuntimeInstaller",
                code: 2002,
                userInfo: [NSLocalizedDescriptionKey: "Unable to enumerate managed runtime payload."]
            )
        }

        var entries: [URL] = []
        for case let url as URL in enumerator {
            entries.append(url)
        }

        entries.sort { lhs, rhs in
            lhs.path.replacingOccurrences(of: rootURL.path, with: "")
                < rhs.path.replacingOccurrences(of: rootURL.path, with: "")
        }

        var hasher = SHA256()
        for entryURL in entries {
            let relativePath = String(entryURL.path.dropFirst(rootURL.path.count + 1))
            let values = try entryURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])

            hasher.update(data: Data(relativePath.utf8))
            hasher.update(data: Data([0]))

            if values.isDirectory == true {
                hasher.update(data: Data("directory".utf8))
                hasher.update(data: Data([0]))
                continue
            }

            if values.isSymbolicLink == true {
                let destination = try fileManager.destinationOfSymbolicLink(atPath: entryURL.path)
                hasher.update(data: Data("symlink".utf8))
                hasher.update(data: Data(destination.utf8))
                hasher.update(data: Data([0]))
                continue
            }

            if values.isRegularFile == true {
                hasher.update(data: Data("file".utf8))
                hasher.update(data: Data([0]))
                hasher.update(data: try Data(contentsOf: entryURL))
                hasher.update(data: Data([0]))
            }
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
