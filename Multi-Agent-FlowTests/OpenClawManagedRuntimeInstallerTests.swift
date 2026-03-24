import XCTest
@testable import Multi_Agent_Flow

final class OpenClawManagedRuntimeInstallerTests: XCTestCase {
    func testInstallerCopiesBundledPayloadIntoManagedRuntimeRoot() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenClawManagedRuntimeInstallerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let bundleRoot = tempRoot.appendingPathComponent("bundle", isDirectory: true)
        let payloadRoot = bundleRoot.appendingPathComponent("OpenClaw", isDirectory: true)
        let managedRoot = tempRoot.appendingPathComponent("ApplicationSupport", isDirectory: true)

        try FileManager.default.createDirectory(
            at: payloadRoot.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true
        )

        let binaryURL = payloadRoot.appendingPathComponent("bin/openclaw", isDirectory: false)
        try "#!/bin/sh\necho managed-runtime\n".write(to: binaryURL, atomically: true, encoding: .utf8)
        try JSONEncoder().encode(
            OpenClawManagedRuntimePayloadManifest(
                payloadVersion: "payload-1",
                runtimeVersion: "runtime-1",
                binaryRelativePath: "bin/openclaw"
            )
        ).write(
            to: payloadRoot.appendingPathComponent("managed-runtime.json", isDirectory: false),
            options: .atomic
        )

        let installer = OpenClawManagedRuntimeInstaller(
            fileManager: .default,
            bundleResourceURL: bundleRoot,
            appSupportRootDirectory: managedRoot,
            payloadDirectoryNames: ["OpenClaw"]
        )

        let result = try installer.installBundledRuntimeIfNeeded()
        let installedBinaryURL = try XCTUnwrap(installer.managedRuntimeRootURL())
            .appendingPathComponent("bin/openclaw", isDirectory: false)
        let receiptURL = try XCTUnwrap(installer.managedRuntimeRootURL())
            .appendingPathComponent("install-receipt.json", isDirectory: false)
        let configURL = try XCTUnwrap(installer.managedRuntimeRootURL())
            .appendingPathComponent("openclaw.json", isDirectory: false)

        XCTAssertEqual(result.status, .installed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedBinaryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: receiptURL.path))
        let configData = try Data(contentsOf: configURL)
        let configObject = try XCTUnwrap(JSONSerialization.jsonObject(with: configData) as? [String: Any])
        let gateway = try XCTUnwrap(configObject["gateway"] as? [String: Any])
        let auth = try XCTUnwrap(gateway["auth"] as? [String: Any])
        let controlUI = try XCTUnwrap(gateway["controlUi"] as? [String: Any])
        XCTAssertEqual(gateway["mode"] as? String, "local")
        XCTAssertEqual(auth["mode"] as? String, "token")
        XCTAssertFalse((auth["token"] as? String ?? "").isEmpty)
        XCTAssertEqual(controlUI["allowedOrigins"] as? [String], ["file://"])
    }

    func testInstallerSkipsWhenInstalledPayloadMatchesReceipt() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenClawManagedRuntimeInstallerSkipTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let bundleRoot = tempRoot.appendingPathComponent("bundle", isDirectory: true)
        let payloadRoot = bundleRoot.appendingPathComponent("openclaw", isDirectory: true)
        let managedRoot = tempRoot.appendingPathComponent("ApplicationSupport", isDirectory: true)

        try FileManager.default.createDirectory(
            at: payloadRoot.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true
        )

        let binaryURL = payloadRoot.appendingPathComponent("bin/openclaw", isDirectory: false)
        try "#!/bin/sh\necho managed-runtime\n".write(to: binaryURL, atomically: true, encoding: .utf8)
        try JSONEncoder().encode(
            OpenClawManagedRuntimePayloadManifest(
                payloadVersion: "payload-2",
                runtimeVersion: "runtime-2",
                binaryRelativePath: "bin/openclaw"
            )
        ).write(
            to: payloadRoot.appendingPathComponent("managed-runtime.json", isDirectory: false),
            options: .atomic
        )

        let installer = OpenClawManagedRuntimeInstaller(
            fileManager: .default,
            bundleResourceURL: bundleRoot,
            appSupportRootDirectory: managedRoot,
            payloadDirectoryNames: ["openclaw"]
        )

        _ = try installer.installBundledRuntimeIfNeeded()
        let result = try installer.installBundledRuntimeIfNeeded()

        XCTAssertEqual(result.status, .alreadyCurrent)
        XCTAssertEqual(result.payloadVersion, "payload-2")
    }

    func testInstallerRepairsManagedConfigWhenCurrentPayloadIsMissingGatewayBootstrap() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenClawManagedRuntimeInstallerRepairTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let bundleRoot = tempRoot.appendingPathComponent("bundle", isDirectory: true)
        let payloadRoot = bundleRoot.appendingPathComponent("openclaw", isDirectory: true)
        let managedRoot = tempRoot.appendingPathComponent("ApplicationSupport", isDirectory: true)

        try FileManager.default.createDirectory(
            at: payloadRoot.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true
        )

        let binaryURL = payloadRoot.appendingPathComponent("bin/openclaw", isDirectory: false)
        try "#!/bin/sh\necho managed-runtime\n".write(to: binaryURL, atomically: true, encoding: .utf8)
        try "{}".write(
            to: payloadRoot.appendingPathComponent("openclaw.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try JSONEncoder().encode(
            OpenClawManagedRuntimePayloadManifest(
                payloadVersion: "payload-3",
                runtimeVersion: "runtime-3",
                binaryRelativePath: "bin/openclaw"
            )
        ).write(
            to: payloadRoot.appendingPathComponent("managed-runtime.json", isDirectory: false),
            options: .atomic
        )

        let installer = OpenClawManagedRuntimeInstaller(
            fileManager: .default,
            bundleResourceURL: bundleRoot,
            appSupportRootDirectory: managedRoot,
            payloadDirectoryNames: ["openclaw"]
        )

        _ = try installer.installBundledRuntimeIfNeeded()

        let installedConfigURL = try XCTUnwrap(installer.managedRuntimeRootURL())
            .appendingPathComponent("openclaw.json", isDirectory: false)
        try "{}".write(to: installedConfigURL, atomically: true, encoding: .utf8)

        let result = try installer.installBundledRuntimeIfNeeded()
        XCTAssertEqual(result.status, .alreadyCurrent)

        let configData = try Data(contentsOf: installedConfigURL)
        let configObject = try XCTUnwrap(JSONSerialization.jsonObject(with: configData) as? [String: Any])
        let gateway = try XCTUnwrap(configObject["gateway"] as? [String: Any])
        let auth = try XCTUnwrap(gateway["auth"] as? [String: Any])
        XCTAssertEqual(gateway["mode"] as? String, "local")
        XCTAssertEqual(auth["mode"] as? String, "token")
        XCTAssertFalse((auth["token"] as? String ?? "").isEmpty)
    }

    func testInstallerReinstallsWhenPayloadContentsChangeWithoutVersionBump() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenClawManagedRuntimeInstallerReinstallTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let bundleRoot = tempRoot.appendingPathComponent("bundle", isDirectory: true)
        let payloadRoot = bundleRoot.appendingPathComponent("OpenClaw", isDirectory: true)
        let managedRoot = tempRoot.appendingPathComponent("ApplicationSupport", isDirectory: true)

        try FileManager.default.createDirectory(
            at: payloadRoot.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true
        )

        let binaryURL = payloadRoot.appendingPathComponent("bin/openclaw", isDirectory: false)
        let manifestURL = payloadRoot.appendingPathComponent("managed-runtime.json", isDirectory: false)

        try "#!/bin/sh\necho first\n".write(to: binaryURL, atomically: true, encoding: .utf8)
        try JSONEncoder().encode(
            OpenClawManagedRuntimePayloadManifest(
                payloadVersion: "payload-stable",
                runtimeVersion: "runtime-stable",
                binaryRelativePath: "bin/openclaw"
            )
        ).write(to: manifestURL, options: .atomic)

        let installer = OpenClawManagedRuntimeInstaller(
            fileManager: .default,
            bundleResourceURL: bundleRoot,
            appSupportRootDirectory: managedRoot,
            payloadDirectoryNames: ["OpenClaw"]
        )

        _ = try installer.installBundledRuntimeIfNeeded()

        try "#!/bin/sh\necho second\n".write(to: binaryURL, atomically: true, encoding: .utf8)
        try JSONEncoder().encode(
            OpenClawManagedRuntimePayloadManifest(
                payloadVersion: "payload-stable",
                runtimeVersion: "runtime-stable",
                binaryRelativePath: "bin/openclaw"
            )
        ).write(to: manifestURL, options: .atomic)

        let result = try installer.installBundledRuntimeIfNeeded()
        let installedBinaryURL = try XCTUnwrap(installer.managedRuntimeRootURL())
            .appendingPathComponent("bin/openclaw", isDirectory: false)

        XCTAssertEqual(result.status, .installed)
        XCTAssertEqual(
            try String(contentsOf: installedBinaryURL, encoding: .utf8),
            "#!/bin/sh\necho second\n"
        )
    }

    func testInstallerReportsUnavailableWhenPayloadBinaryIsMissing() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenClawManagedRuntimeInstallerMissingBinaryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let bundleRoot = tempRoot.appendingPathComponent("bundle", isDirectory: true)
        let payloadRoot = bundleRoot.appendingPathComponent("OpenClaw", isDirectory: true)

        try FileManager.default.createDirectory(at: payloadRoot, withIntermediateDirectories: true)
        try JSONEncoder().encode(
            OpenClawManagedRuntimePayloadManifest(
                payloadVersion: "payload-missing",
                runtimeVersion: "runtime-missing",
                binaryRelativePath: "bin/openclaw"
            )
        ).write(
            to: payloadRoot.appendingPathComponent("managed-runtime.json", isDirectory: false),
            options: .atomic
        )

        let installer = OpenClawManagedRuntimeInstaller(
            fileManager: .default,
            bundleResourceURL: bundleRoot,
            appSupportRootDirectory: tempRoot.appendingPathComponent("ApplicationSupport", isDirectory: true),
            payloadDirectoryNames: ["OpenClaw"]
        )

        let result = try installer.installBundledRuntimeIfNeeded()

        XCTAssertEqual(result.status, .unavailable)
    }
}
