import os from "node:os";
import path from "node:path";
import type { OpenClawConfig } from "@multi-agent-flow/domain";

function trimmedNonEmpty(value: string | null | undefined): string | null {
  const trimmed = value?.trim() ?? "";
  return trimmed ? trimmed : null;
}

function appendCandidate(result: string[], candidate: string | null) {
  const normalized = trimmedNonEmpty(candidate);
  if (!normalized || result.includes(normalized)) {
    return;
  }
  result.push(normalized);
}

export function buildContainerOpenClawRootDiscoveryScript(workspaceMountPath: string): string {
  const normalizedWorkspaceMountPath = trimmedNonEmpty(workspaceMountPath);

  let script = `probe_candidate() {
  candidate="$1"
  if [ -n "$candidate" ] && [ -d "$candidate" ]; then
    if [ -f "$candidate/openclaw.json" ] || [ -d "$candidate/agents" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  fi
  return 1
}

for candidate in \\
  "\${OPENCLAW_ROOT:-}" \\
  "\${OPENCLAW_HOME:-}" \\
  "\${OPENCLAW_PATH:-}" \\
  "\${XDG_CONFIG_HOME:-$HOME/.config}/openclaw" \\
  "\${XDG_CONFIG_HOME:-$HOME/.config}/.openclaw" \\
  "\${XDG_DATA_HOME:-$HOME/.local/share}/openclaw" \\
  "\${XDG_DATA_HOME:-$HOME/.local/share}/.openclaw" \\
  "$HOME/.openclaw" \\
  "$HOME/openclaw" \\
  "/root/.openclaw" \\
  "/home/node/.openclaw" \\
  "/home/app/.openclaw" \\
  "/app/.openclaw" \\
  "/workspace/.openclaw" \\
  "/workspace/openclaw" \\
  "/workspaces/.openclaw" \\
  "/workspaces/openclaw"; do
  probe_candidate "$candidate" && exit 0
done
`;

  if (normalizedWorkspaceMountPath) {
    const workspaceCandidates = [
      path.join(normalizedWorkspaceMountPath, ".openclaw"),
      path.join(normalizedWorkspaceMountPath, "openclaw")
    ];
    script += "\n";
    for (const candidate of workspaceCandidates) {
      const escaped = candidate.replace(/'/g, `'\"'\"'`);
      script += `probe_candidate '${escaped}' && exit 0\n`;
    }
  }

  script += `

for root in \\
  "$HOME" \\
  "/root" \\
  "/home/node" \\
  "/home/app" \\
  "/app" \\
  "/workspace" \\
  "/workspaces" \\
  "/tmp" \\
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
`;

  return script;
}

export function buildOpenClawRootFallbackCandidates(
  config: OpenClawConfig,
  options: {
    deploymentHomeDirectory?: string | null;
    managedRuntimeRootDirectory?: string | null;
    localHomeDirectory?: string;
  } = {}
): string[] {
  switch (config.deploymentKind) {
    case "local": {
      if (config.runtimeOwnership === "appManaged") {
        const managedRuntimeRootDirectory = trimmedNonEmpty(options.managedRuntimeRootDirectory);
        return managedRuntimeRootDirectory ? [managedRuntimeRootDirectory] : [];
      }

      const homeDirectory = trimmedNonEmpty(options.localHomeDirectory) ?? os.homedir();
      return [path.join(homeDirectory, ".openclaw")];
    }
    case "container": {
      const result: string[] = [];
      const deploymentHomeDirectory = trimmedNonEmpty(options.deploymentHomeDirectory);
      const workspaceMountPath = trimmedNonEmpty(config.container.workspaceMountPath);

      if (deploymentHomeDirectory) {
        appendCandidate(result, path.join(deploymentHomeDirectory, ".openclaw"));
        appendCandidate(result, path.join(deploymentHomeDirectory, "openclaw"));
      }

      for (const candidate of [
        "/root/.openclaw",
        "/home/node/.openclaw",
        "/home/app/.openclaw",
        "/app/.openclaw",
        "/workspace/.openclaw",
        "/workspace/openclaw",
        "/workspaces/.openclaw",
        "/workspaces/openclaw"
      ]) {
        appendCandidate(result, candidate);
      }

      if (workspaceMountPath) {
        appendCandidate(result, path.join(workspaceMountPath, ".openclaw"));
        appendCandidate(result, path.join(workspaceMountPath, "openclaw"));
        appendCandidate(result, workspaceMountPath);
      }

      return result;
    }
    case "remoteServer":
      return [];
  }
}
