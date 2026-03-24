import test from "node:test";
import assert from "node:assert/strict";
import type { OpenClawConfig } from "@multi-agent-flow/domain";
import {
  buildContainerOpenClawRootDiscoveryScript,
  buildOpenClawRootFallbackCandidates
} from "../electron/openclaw-discovery";

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

test("local app-managed fallback candidates resolve to the app-managed runtime root", () => {
  const candidates = buildOpenClawRootFallbackCandidates(baseConfig, {
    managedRuntimeRootDirectory: "/Users/tester/Library/Application Support/Multi-Agent-Flow/openclaw/runtime"
  });

  assert.deepEqual(candidates, ["/Users/tester/Library/Application Support/Multi-Agent-Flow/openclaw/runtime"]);
});

test("legacy local binary hints still stay inside the app-managed runtime root", () => {
  const candidates = buildOpenClawRootFallbackCandidates(
    {
      ...baseConfig,
      localBinaryPath: "/custom/openclaw/bin/openclaw"
    },
    {
      managedRuntimeRootDirectory: "/Users/tester/Library/Application Support/Multi-Agent-Flow/openclaw/runtime"
    }
  );

  assert.deepEqual(candidates, ["/Users/tester/Library/Application Support/Multi-Agent-Flow/openclaw/runtime"]);
});

test("container fallback candidates prioritize deployment home before workspace mount guesses", () => {
  const candidates = buildOpenClawRootFallbackCandidates(
    {
      ...baseConfig,
      deploymentKind: "container",
      container: {
        ...baseConfig.container,
        workspaceMountPath: "/workspace/project"
      }
    },
    {
      deploymentHomeDirectory: "/home/app"
    }
  );

  assert.deepEqual(candidates.slice(0, 4), [
    "/home/app/.openclaw",
    "/home/app/openclaw",
    "/root/.openclaw",
    "/home/node/.openclaw"
  ]);
  assert.ok(candidates.includes("/workspace/project/.openclaw"));
  assert.ok(candidates.includes("/workspace/project/openclaw"));
  assert.ok(candidates.includes("/workspace/project"));
});

test("container root discovery script scans runtime roots before custom workspace fallback", () => {
  const script = buildContainerOpenClawRootDiscoveryScript("/srv/app'space");

  assert.match(script, /"\$\{OPENCLAW_ROOT:-\}"/);
  assert.match(script, /"\$HOME\/\.openclaw"/);
  assert.match(script, /find "\$root" -maxdepth 5 -type f -name openclaw\.json/);
  assert.match(script, /probe_candidate '\/srv\/app'"'"'space\/\.openclaw' && exit 0/);
  assert.match(script, /probe_candidate '\/srv\/app'"'"'space\/openclaw' && exit 0/);
});
