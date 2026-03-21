import { spawn } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const appDir = path.resolve(__dirname, "..");
const repoRoot = path.resolve(appDir, "..", "..");
const outputDir = path.resolve(repoRoot, "Multi-Agent-Flow/Documentation/assets");
const host = "127.0.0.1";
const port = 4174;
const baseUrl = `http://${host}:${port}/canvas-doc.html`;

const screenshots = [
  {
    scene: "overview",
    fileName: "workflow-canvas-editor-overview-2026-03-21.png"
  },
  {
    scene: "fanout",
    fileName: "workflow-canvas-routing-fanout-2026-03-21.png"
  },
  {
    scene: "fanin",
    fileName: "workflow-canvas-routing-fanin-2026-03-21.png"
  },
  {
    scene: "bridge",
    fileName: "workflow-canvas-routing-bridge-2026-03-21.png"
  }
];

function run(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: appDir,
      stdio: ["ignore", "pipe", "pipe"],
      shell: false,
      ...options
    });

    let stdout = "";
    let stderr = "";
    child.stdout?.on("data", (chunk) => {
      stdout += String(chunk);
    });
    child.stderr?.on("data", (chunk) => {
      stderr += String(chunk);
    });

    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) {
        resolve({ stdout, stderr });
        return;
      }
      reject(new Error(`Command failed (${command} ${args.join(" ")}):\n${stdout}\n${stderr}`));
    });
  });
}

function waitForServer(timeoutMs = 15000) {
  const startedAt = Date.now();

  return new Promise((resolve, reject) => {
    const attempt = () => {
      const request = http.get(`${baseUrl}?scene=overview&capture=1`, (response) => {
        response.resume();
        if ((response.statusCode ?? 500) < 500) {
          resolve();
          return;
        }
        retry();
      });

      request.on("error", retry);
    };

    const retry = () => {
      if (Date.now() - startedAt > timeoutMs) {
        reject(new Error("Timed out waiting for Vite server"));
        return;
      }
      setTimeout(attempt, 250);
    };

    attempt();
  });
}

async function main() {
  fs.mkdirSync(outputDir, { recursive: true });

  const vite = spawn("npx", ["vite", "--host", host, "--port", String(port)], {
    cwd: appDir,
    stdio: ["ignore", "pipe", "pipe"],
    shell: false
  });

  vite.stdout?.on("data", (chunk) => process.stdout.write(String(chunk)));
  vite.stderr?.on("data", (chunk) => process.stderr.write(String(chunk)));

  try {
    await waitForServer();

    for (const item of screenshots) {
      const destination = path.join(outputDir, item.fileName);
      const url = `${baseUrl}?scene=${item.scene}&capture=1`;
      await run("npx", [
        "playwright",
        "screenshot",
        "--browser",
        "chromium",
        "--viewport-size",
        "1440,980",
        "--wait-for-timeout",
        "1200",
        url,
        destination
      ]);
      console.log(`captured ${destination}`);
    }
  } finally {
    vite.kill("SIGTERM");
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
