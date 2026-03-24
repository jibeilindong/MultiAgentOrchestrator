import test from "node:test";
import assert from "node:assert/strict";
import type { OpenClawConfig } from "@multi-agent-flow/domain";
import { buildOpenClawProcessEnvironment, OpenClawHost, shellSingleQuote } from "../electron/openclaw-host";

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

test("openclaw host resolves app-managed local command plans through bundled runtime candidates", () => {
  const host = new OpenClawHost(() => ({
    platform: "darwin",
    homeDirectory: "/Users/tester",
    resourcesPath: "/Applications/Multi-Agent-Flow.app/Contents/Resources",
    appPath: "/Users/tester/dev/MultiAgentOrchestrator/apps/desktop",
    userDataPath: "/Users/tester/Library/Application Support/Multi-Agent-Flow",
    pathExists: (candidate) => candidate === "/Applications/Multi-Agent-Flow.app/Contents/Resources/openclaw/bin/openclaw"
  }));

  const plan = host.buildDeploymentCommandPlan(baseConfig, ["agents", "list"]);

  assert.deepEqual(plan, {
    command: "/Applications/Multi-Agent-Flow.app/Contents/Resources/openclaw/bin/openclaw",
    args: ["agents", "list"],
    env: {
      OPENCLAW_CONFIG_PATH:
        "/Users/tester/Library/Application Support/Multi-Agent-Flow/openclaw/runtime/openclaw.json",
      OPENCLAW_STATE_DIR: "/Users/tester/Library/Application Support/Multi-Agent-Flow/openclaw/state"
    }
  });
});

test("openclaw host ignores legacy local binary hints for local command plans", () => {
  const host = new OpenClawHost(() => ({
    platform: "darwin",
    homeDirectory: "/Users/tester",
    resourcesPath: "/Applications/Multi-Agent-Flow.app/Contents/Resources",
    appPath: "/Users/tester/dev/MultiAgentOrchestrator/apps/desktop",
    userDataPath: "/Users/tester/Library/Application Support/Multi-Agent-Flow",
    pathExists: (candidate) => candidate === "/Applications/Multi-Agent-Flow.app/Contents/Resources/openclaw/bin/openclaw"
  }));

  const plan = host.buildDeploymentCommandPlan(
    {
      ...baseConfig,
      localBinaryPath: "/custom/openclaw/bin/openclaw"
    },
    ["agents", "list"]
  );

  assert.deepEqual(plan, {
    command: "/Applications/Multi-Agent-Flow.app/Contents/Resources/openclaw/bin/openclaw",
    args: ["agents", "list"],
    env: {
      OPENCLAW_CONFIG_PATH:
        "/Users/tester/Library/Application Support/Multi-Agent-Flow/openclaw/runtime/openclaw.json",
      OPENCLAW_STATE_DIR: "/Users/tester/Library/Application Support/Multi-Agent-Flow/openclaw/state"
    }
  });
});

test("openclaw host builds container shell plans through the container engine", () => {
  const host = new OpenClawHost(() => ({
    platform: "darwin",
    homeDirectory: "/Users/tester",
    resourcesPath: null,
    appPath: null,
    userDataPath: null
  }));

  const plan = host.buildDeploymentShellPlan(
    {
      ...baseConfig,
      deploymentKind: "container",
      container: {
        ...baseConfig.container,
        engine: "podman",
        containerName: "openclaw-runtime"
      }
    },
    "printf %s \"$HOME\""
  );

  assert.deepEqual(plan, {
    command: "podman",
    args: ["exec", "openclaw-runtime", "sh", "-lc", "printf %s \"$HOME\""],
    env: {}
  });
});

test("shell quoting keeps single-quoted shell scripts safe", () => {
  assert.equal(shellSingleQuote("/srv/app'space"), "'/srv/app'\"'\"'space'");
});

test("openclaw host process environment keeps only whitelisted keys and injected managed overrides", () => {
  const environment = buildOpenClawProcessEnvironment(
    {
      OPENCLAW_CONFIG_PATH: "/managed/runtime/openclaw.json",
      OPENCLAW_STATE_DIR: "/managed/state"
    },
    {
      PATH: "/usr/bin:/bin",
      HOME: "/Users/tester",
      LANG: "en_US.UTF-8",
      OPENCLAW_CONFIG_PATH: "/tmp/external-openclaw.json",
      OPENCLAW_STATE_DIR: "/tmp/external-state",
      CUSTOM_SECRET: "ignore-me"
    }
  );

  assert.deepEqual(environment, {
    PATH: "/usr/bin:/bin",
    HOME: "/Users/tester",
    LANG: "en_US.UTF-8",
    OPENCLAW_CONFIG_PATH: "/managed/runtime/openclaw.json",
    OPENCLAW_STATE_DIR: "/managed/state"
  });
});
