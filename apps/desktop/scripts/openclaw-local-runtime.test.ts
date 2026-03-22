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

test("managed local runtime candidates prioritize bundled and managed roots before system paths", () => {
  const candidates = buildManagedLocalOpenClawBinaryCandidates({
    platform: "darwin",
    homeDirectory: "/Users/tester",
    resourcesPath: "/Applications/Multi-Agent-Flow.app/Contents/Resources",
    appPath: "/Users/tester/dev/MultiAgentOrchestrator/apps/desktop",
    userDataPath: "/Users/tester/Library/Application Support/Multi-Agent-Flow"
  });

  assert.deepEqual(candidates.slice(0, 7), [
    "/Applications/Multi-Agent-Flow.app/Contents/Resources/openclaw/bin/openclaw",
    "/Applications/Multi-Agent-Flow.app/Contents/Resources/openclaw/openclaw",
    "/Users/tester/dev/MultiAgentOrchestrator/apps/desktop/resources/openclaw/bin/openclaw",
    "/Users/tester/dev/MultiAgentOrchestrator/apps/desktop/resources/openclaw/openclaw",
    "/Users/tester/Library/Application Support/Multi-Agent-Flow/openclaw/runtime/bin/openclaw",
    "/Users/tester/Library/Application Support/Multi-Agent-Flow/openclaw/runtime/openclaw",
    "/Users/tester/dev/MultiAgentOrchestrator/apps/desktop/node_modules/.bin/openclaw"
  ]);
  assert.equal(candidates.at(-1), "openclaw");
});

test("managed local runtime resolution ignores legacy explicit paths and prefers discovered managed/system binaries", () => {
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
      pathExists: (candidate) => candidate === "/usr/local/bin/openclaw"
    }
  );

  assert.equal(resolved, "/usr/local/bin/openclaw");
});

test("externally managed local runtime stays pinned to the user-provided binary path", () => {
  const resolved = resolveLocalOpenClawBinaryPath(
    {
      ...baseConfig,
      runtimeOwnership: "externalLocal",
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

  assert.equal(resolved, "/custom/openclaw/bin/openclaw");
});
