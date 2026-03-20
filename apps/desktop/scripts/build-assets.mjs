import { existsSync, statSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const rootDir = resolve(scriptDir, "..");
const buildResourcesDir = resolve(rootDir, "buildResources");
const generatorScript = resolve(scriptDir, "generate-icons.py");
const sourceSvg = resolve(buildResourcesDir, "icon-source.svg");
const requiredAssets = [
  resolve(buildResourcesDir, "icon.png"),
  resolve(buildResourcesDir, "icon.ico"),
  resolve(buildResourcesDir, "icon.icns"),
];

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    stdio: "inherit",
    ...options,
  });

  if (result.status !== 0) {
    const rendered = [command, ...args].join(" ");
    throw new Error(`Command failed: ${rendered}`);
  }
}

function canRun(command, args = []) {
  const result = spawnSync(command, args, {
    stdio: "ignore",
  });
  return !result.error;
}

function hasPythonModule(moduleName) {
  const result = spawnSync("python3", ["-c", `import ${moduleName}`], {
    stdio: "ignore",
  });
  return result.status === 0;
}

function missingAssets() {
  return requiredAssets.filter((assetPath) => !existsSync(assetPath));
}

function outputsAreOlderThanSource() {
  if (!existsSync(sourceSvg)) {
    return false;
  }

  const sourceMtime = statSync(sourceSvg).mtimeMs;
  return requiredAssets.some((assetPath) => {
    if (!existsSync(assetPath)) {
      return true;
    }
    return statSync(assetPath).mtimeMs < sourceMtime;
  });
}

function verifyCheckedInAssets() {
  const missing = missingAssets();
  if (missing.length > 0) {
    throw new Error(
      [
        "Required desktop icon assets are missing:",
        ...missing.map((assetPath) => `- ${assetPath}`),
        "Run `npm run build:assets:refresh --workspace @multi-agent-flow/desktop` on a macOS machine with python3, Pillow, and iconutil.",
      ].join("\n"),
    );
  }

  console.log("Using checked-in desktop icon assets.");
}

function main() {
  const verifyOnly = process.env.MAF_ASSETS_VERIFY_ONLY === "1";
  const canRefreshOnThisMachine =
    !verifyOnly &&
    process.platform === "darwin" &&
    canRun("python3", ["--version"]) &&
    canRun("iconutil") &&
    hasPythonModule("PIL");

  if (canRefreshOnThisMachine) {
    const shouldRefresh = missingAssets().length > 0 || outputsAreOlderThanSource();
    if (shouldRefresh) {
      console.log("Refreshing desktop icons from source artwork.");
      run("python3", [generatorScript], {
        cwd: rootDir,
      });
    } else {
      console.log("Desktop icon assets are already up to date.");
    }
    verifyCheckedInAssets();
    return;
  }

  if (!verifyOnly) {
    console.log("Skipping icon regeneration on this machine; verifying checked-in assets instead.");
  }
  verifyCheckedInAssets();
}

main();
