import { execFile } from "node:child_process";
import { mkdirSync } from "node:fs";
import path from "node:path";
import { promisify } from "node:util";
import type { OpenClawConfig } from "@multi-agent-flow/domain";
import {
  resolveLocalOpenClawBinaryPath,
  type OpenClawLocalRuntimeEnvironment
} from "./openclaw-local-runtime";

const execFileAsync = promisify(execFile);

export interface OpenClawHostEnvironment extends OpenClawLocalRuntimeEnvironment {
  platform: NodeJS.Platform;
  homeDirectory: string;
}

export interface OpenClawHostCommandPlan {
  command: string;
  args: string[];
  env: Record<string, string>;
}

export interface OpenClawHostCommandOptions {
  timeoutMs?: number;
}

type OpenClawHostExecResult = {
  stdout: string;
  stderr: string;
};
type OpenClawHostExecutor = (
  plan: OpenClawHostCommandPlan,
  options?: OpenClawHostCommandOptions
) => Promise<OpenClawHostExecResult>;

const INHERITED_PROCESS_ENVIRONMENT_KEYS = new Set([
  "HOME",
  "PATH",
  "TMPDIR",
  "TMP",
  "TEMP",
  "USER",
  "LOGNAME",
  "SHELL",
  "LANG",
  "LC_ALL",
  "LC_CTYPE",
  "LC_MESSAGES",
  "TERM",
  "TERM_PROGRAM",
  "TERM_PROGRAM_VERSION",
  "__CF_USER_TEXT_ENCODING",
  "SYSTEMROOT",
  "COMSPEC",
  "PATHEXT",
  "WINDIR",
  "APPDATA",
  "LOCALAPPDATA"
]);

export function buildOpenClawProcessEnvironment(
  planEnv: Record<string, string>,
  baseEnv: NodeJS.ProcessEnv = process.env
): Record<string, string> {
  const sanitized: Record<string, string> = {};
  for (const [key, value] of Object.entries(baseEnv)) {
    if (typeof value !== "string") {
      continue;
    }
    if (!INHERITED_PROCESS_ENVIRONMENT_KEYS.has(key.toUpperCase())) {
      continue;
    }
    sanitized[key] = value;
  }
  for (const key of Object.keys(sanitized)) {
    if (key.toUpperCase().startsWith("OPENCLAW_")) {
      delete sanitized[key];
    }
  }
  return {
    ...sanitized,
    ...planEnv
  };
}

function defaultOpenClawHostExecutor(
  plan: OpenClawHostCommandPlan,
  options?: OpenClawHostCommandOptions
): Promise<OpenClawHostExecResult> {
  if (plan.env.OPENCLAW_STATE_DIR?.trim()) {
    mkdirSync(plan.env.OPENCLAW_STATE_DIR, { recursive: true });
  }
  return execFileAsync(plan.command, plan.args, {
    encoding: "utf8",
    timeout: options?.timeoutMs ?? 15000,
    windowsHide: true,
    maxBuffer: 1024 * 1024,
    env: buildOpenClawProcessEnvironment(plan.env)
  }) as Promise<OpenClawHostExecResult>;
}

export function shellSingleQuote(value: string): string {
  return `'${value.replace(/'/g, `'\"'\"'`)}'`;
}

export class OpenClawHost {
  constructor(
    private readonly resolveEnvironment: () => OpenClawHostEnvironment,
    private readonly executor: OpenClawHostExecutor = defaultOpenClawHostExecutor
  ) {}

  resolveLocalBinaryPath(config: OpenClawConfig): string {
    return resolveLocalOpenClawBinaryPath(config, this.resolveEnvironment());
  }

  private resolveManagedLocalRuntimeEnvironment(config: OpenClawConfig): Record<string, string> {
    if (config.deploymentKind !== "local") {
      return {};
    }

    const environment = this.resolveEnvironment();
    const resolvedBinaryPath = this.resolveLocalBinaryPath(config);
    const binaryDirectory = path.dirname(resolvedBinaryPath);
    const inferredManagedRuntimeRoot =
      path.basename(binaryDirectory).toLowerCase() === "bin" ? path.dirname(binaryDirectory) : binaryDirectory;
    const managedRuntimeRoot = environment.userDataPath
      ? path.join(environment.userDataPath, "openclaw", "runtime")
      : inferredManagedRuntimeRoot;
    const managedStateDir = environment.userDataPath
      ? path.join(environment.userDataPath, "openclaw", "state")
      : path.join(path.dirname(managedRuntimeRoot), "state");

    return {
      OPENCLAW_CONFIG_PATH: path.join(managedRuntimeRoot, "openclaw.json"),
      OPENCLAW_STATE_DIR: managedStateDir
    };
  }

  buildDeploymentCommandPlan(config: OpenClawConfig, args: string[]): OpenClawHostCommandPlan {
    switch (config.deploymentKind) {
      case "local":
        return {
          command: this.resolveLocalBinaryPath(config),
          args,
          env: this.resolveManagedLocalRuntimeEnvironment(config)
        };
      case "container": {
        const engine = config.container.engine.trim() || "docker";
        const containerName = config.container.containerName.trim();
        if (!containerName) {
          throw new Error("Container name is required.");
        }

        return {
          command: engine,
          args: ["exec", containerName, "openclaw", ...args],
          env: {}
        };
      }
      case "remoteServer":
        throw new Error("Remote server mode does not support direct OpenClaw CLI execution yet.");
    }
  }

  buildDeploymentShellPlan(config: OpenClawConfig, script: string): OpenClawHostCommandPlan {
    switch (config.deploymentKind) {
      case "local":
        return {
          command: "/bin/sh",
          args: ["-lc", script],
          env: this.resolveManagedLocalRuntimeEnvironment(config)
        };
      case "container": {
        const engine = config.container.engine.trim() || "docker";
        const containerName = config.container.containerName.trim();
        if (!containerName) {
          throw new Error("Container name is required.");
        }

        return {
          command: engine,
          args: ["exec", containerName, "sh", "-lc", script],
          env: {}
        };
      }
      case "remoteServer":
        throw new Error("Remote server mode does not support shell-based OpenClaw file management yet.");
    }
  }

  runDeploymentCommand(
    config: OpenClawConfig,
    args: string[],
    options?: OpenClawHostCommandOptions
  ): Promise<OpenClawHostExecResult> {
    return this.executor(this.buildDeploymentCommandPlan(config, args), options);
  }

  runDeploymentShell(
    config: OpenClawConfig,
    script: string,
    options?: OpenClawHostCommandOptions
  ): Promise<OpenClawHostExecResult> {
    return this.executor(this.buildDeploymentShellPlan(config, script), options);
  }
}
