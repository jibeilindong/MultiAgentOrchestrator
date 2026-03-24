import test from "node:test";
import assert from "node:assert/strict";
import type { OpenClawConfig } from "@multi-agent-flow/domain";
import {
  buildManagedLocalOpenClawBinaryCandidates,
  resolveLocalOpenClawBinaryPath
} from "../electron/openclaw-local-runtime";

const baseConfig: OpenClawConfig = {
  deploymentKind: "local",
  runtimeOwnership: "appManaged",
  host: "127.0.0.1",
  port: 18789,
  useSSL: false,
  apiKey: "",
  defaultAgent: "default",
  timeout: 30,
  autoConnect: true,
  localBinaryPath: "",
  container: {
    engine: "docker",
    containerName: "openclaw-dev",
    workspaceMountPath: "/workspace"
  },
  cliQuietMode: true,
  cliLogLevel: "warning"
};

test("managed local runtime candidates prioritize bundled and managed roots", () => {
  const candidates = buildManagedLocalOpenClawBinaryCandidates({
    platform: "darwin",
    homeDirectory: "/Users/tester",
    resourcesPath: "/Applications/Multi-Agent-Flow.app/Contents/Resources",
    appPath: "/Users/tester/dev/MultiAgentOrchestrator/apps/desktop",
    userDataPath: "/Users/tester/Library/Application Support/Multi-Agent-Flow"
  });

  assert.deepEqual(candidates, [
    "/Applications/Multi-Agent-Flow.app/Contents/Resources/openclaw/bin/openclaw",
    "/Applications/Multi-Agent-Flow.app/Contents/Resources/openclaw/openclaw",
    "/Users/tester/dev/MultiAgentOrchestrator/apps/desktop/resources/openclaw/bin/openclaw",
    "/Users/tester/dev/MultiAgentOrchestrator/apps/desktop/resources/openclaw/openclaw",
    "/Users/tester/Library/Application Support/Multi-Agent-Flow/openclaw/runtime/bin/openclaw",
    "/Users/tester/Library/Application Support/Multi-Agent-Flow/openclaw/runtime/openclaw",
    "/Users/tester/dev/MultiAgentOrchestrator/apps/desktop/node_modules/.bin/openclaw"
  ]);
});

test("managed local runtime resolution ignores legacy explicit paths and stays inside app-managed candidates", () => {
  const resolved = resolveLocalOpenClawBinaryPath(
    {
      ...baseConfig,
      localBinaryPath: "/legacy/external/openclaw"
    },
    {
      platform: "darwin",
      homeDirectory: "/Users/tester",
      resourcesPath: "/Applications/Multi-Agent-Flow.app/Contents/Resources",
      appPath: "/Users/tester/dev/MultiAgentOrchestrator/apps/desktop",
      userDataPath: "/Users/tester/Library/Application Support/Multi-Agent-Flow",
      pathExists: () => false
    }
  );

  assert.equal(resolved, "/Applications/Multi-Agent-Flow.app/Contents/Resources/openclaw/bin/openclaw");
});

test("legacy local binary hints no longer escape app-managed candidate resolution", () => {
  const resolved = resolveLocalOpenClawBinaryPath(
    {
      ...baseConfig,
      localBinaryPath: "/custom/openclaw/bin/openclaw"
    },
    {
      platform: "darwin",
      homeDirectory: "/Users/tester",
      resourcesPath: "/Applications/Multi-Agent-Flow.app/Contents/Resources",
      appPath: "/Users/tester/dev/MultiAgentOrchestrator/apps/desktop",
      userDataPath: "/Users/tester/Library/Application Support/Multi-Agent-Flow",
      pathExists: () => true
    }
  );

  assert.equal(resolved, "/Applications/Multi-Agent-Flow.app/Contents/Resources/openclaw/bin/openclaw");
});
