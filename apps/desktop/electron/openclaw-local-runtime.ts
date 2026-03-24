import os from "node:os";
import path from "node:path";
import { existsSync } from "node:fs";
import { type OpenClawConfig } from "@multi-agent-flow/domain";

export interface OpenClawLocalRuntimeEnvironment {
  platform?: NodeJS.Platform;
  homeDirectory?: string;
  resourcesPath?: string | null;
  appPath?: string | null;
  userDataPath?: string | null;
  pathExists?: (candidate: string) => boolean;
}

function dedupeCandidates(candidates: Array<string | null | undefined>): string[] {
  const result: string[] = [];
  const seen = new Set<string>();
  for (const candidate of candidates) {
    const normalized = (candidate ?? "").trim();
    if (!normalized || seen.has(normalized)) {
      continue;
    }
    seen.add(normalized);
    result.push(normalized);
  }
  return result;
}

export function buildSystemLocalOpenClawBinaryCandidates(
  environment: Pick<OpenClawLocalRuntimeEnvironment, "platform" | "homeDirectory"> = {}
): string[] {
  const platform = environment.platform ?? process.platform;
  const homeDirectory = environment.homeDirectory ?? os.homedir();

  if (platform === "win32") {
    return dedupeCandidates([
      path.join(homeDirectory, ".local", "bin", "openclaw.exe"),
      path.join(homeDirectory, "AppData", "Local", "Programs", "OpenClaw", "openclaw.exe"),
      "openclaw.exe"
    ]);
  }

  return dedupeCandidates([
    path.join(homeDirectory, ".local", "bin", "openclaw"),
    "/usr/local/bin/openclaw",
    "/opt/homebrew/bin/openclaw",
    "/usr/bin/openclaw",
    "openclaw"
  ]);
}

export function buildManagedLocalOpenClawBinaryCandidates(
  environment: Omit<OpenClawLocalRuntimeEnvironment, "pathExists"> = {}
): string[] {
  const platform = environment.platform ?? process.platform;
  const binaryNames = platform === "win32" ? ["openclaw.exe", "openclaw.cmd"] : ["openclaw"];
  const managedRuntimeRoots = dedupeCandidates([
    environment.resourcesPath ? path.join(environment.resourcesPath, "openclaw") : null,
    environment.appPath ? path.join(environment.appPath, "resources", "openclaw") : null,
    environment.userDataPath ? path.join(environment.userDataPath, "openclaw", "runtime") : null
  ]);

  const managedCandidates = managedRuntimeRoots.flatMap((rootPath) =>
    binaryNames.flatMap((binaryName) => [
      path.join(rootPath, "bin", binaryName),
      path.join(rootPath, binaryName)
    ])
  );
  const developmentCandidates =
    environment.appPath == null
      ? []
      : binaryNames.map((binaryName) => path.join(environment.appPath!, "node_modules", ".bin", binaryName));

  return dedupeCandidates([
    ...managedCandidates,
    ...developmentCandidates
  ]);
}

export function resolveLocalOpenClawBinaryPath(
  config: OpenClawConfig,
  environment: OpenClawLocalRuntimeEnvironment = {}
): string {
  if (config.deploymentKind !== "local") {
    return config.localBinaryPath.trim();
  }

  const candidates = buildManagedLocalOpenClawBinaryCandidates(environment);
  const pathExists = environment.pathExists ?? existsSync;
  return candidates.find((candidate) => pathExists(candidate)) ?? candidates[0] ?? "";
}
