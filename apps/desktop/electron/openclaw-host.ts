import { execFile } from "node:child_process";
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

function defaultOpenClawHostExecutor(
  plan: OpenClawHostCommandPlan,
  options?: OpenClawHostCommandOptions
): Promise<OpenClawHostExecResult> {
  return execFileAsync(plan.command, plan.args, {
    encoding: "utf8",
    timeout: options?.timeoutMs ?? 15000,
    windowsHide: true,
    maxBuffer: 1024 * 1024
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

  buildDeploymentCommandPlan(config: OpenClawConfig, args: string[]): OpenClawHostCommandPlan {
    switch (config.deploymentKind) {
      case "local":
        return {
          command: this.resolveLocalBinaryPath(config),
          args
        };
      case "container": {
        const engine = config.container.engine.trim() || "docker";
        const containerName = config.container.containerName.trim();
        if (!containerName) {
          throw new Error("Container name is required.");
        }

        return {
          command: engine,
          args: ["exec", containerName, "openclaw", ...args]
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
          args: ["-lc", script]
        };
      case "container": {
        const engine = config.container.engine.trim() || "docker";
        const containerName = config.container.containerName.trim();
        if (!containerName) {
          throw new Error("Container name is required.");
        }

        return {
          command: engine,
          args: ["exec", containerName, "sh", "-lc", script]
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
