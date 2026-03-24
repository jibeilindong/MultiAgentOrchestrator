# OpenClaw Managed Runtime 本地开发、CI 与发版指南

## 1. 文档目标

本文档说明当前仓库中 `OpenClaw Managed Runtime` 的推荐使用方式，覆盖三类场景：

- 本地开发如何准备可运行的托管 OpenClaw Runtime
- CI 如何在打包前自动生成并校验 Runtime
- 正式发版时应该如何执行、核对和留痕

本文档对应当前采用的方案：

- 应用内置
- 应用托管
- 进程隔离
- 构建时生成 Runtime payload
- 不把 700MB+ 运行时制品直接提交到 Git

## 2. 当前方案结论

当前仓库已经确定采用以下策略：

- Git 只提交稳定的小体积内容：
  - `managed-runtime.json`
  - `bin/openclaw`
  - 构建脚本
  - 同步/校验脚本
  - 文档
- 真正的 OpenClaw Runtime payload 在构建阶段生成：
  - `libexec/openclaw`
  - `openclaw.mjs`
  - `dist/`
  - `node_modules/`
  - `runtime/node/`
  - `skills/` / `docs/` / `assets/`
- 生成后的 payload 会被 hydrate 到：
  - `managed-runtime/openclaw`
  - `apps/desktop/resources/openclaw`
- 这些大体积目录默认被 `.gitignore` 忽略，不直接入库
- 应用内默认采用：
  - `App Managed`
  - `Foreground Gateway Sidecar`
  - `应用退出即停止托管 Runtime`
  - `Runtime 崩溃后自动拉起`
- 如果业务需要，也可以在应用配置里切换为：
  - `应用退出后保持 Runtime 运行`
  - `关闭崩溃自动恢复，改为手动恢复`

这样做的原因：

- 保证最终 App 仍然是“内置 OpenClaw”
- 避免仓库长期膨胀
- 减少 clone / pull / branch 切换 / CI checkout 成本
- 保留对 upstream 版本的可追溯性和可复现性

默认选择“应用退出即停止托管 Runtime”的原因：

- 更符合“应用内置、应用托管”的安全边界
- 可以避免 App 已退出但 Runtime 仍长期占用端口、日志和工作目录
- 让本地开发、CI 冒烟和发版验证具备更稳定的生命周期预期

## 3. 关键脚本

当前链路依赖以下脚本：

- `scripts/prepare-openclaw-managed-runtime.sh`
  - 一键入口
  - 负责获取或使用固定 upstream 源码、构建、生成 payload、hydrate、sync、validate
- `scripts/build-openclaw-managed-runtime-native-payload.sh`
  - 从 upstream OpenClaw 源码目录生成 native launcher payload
- `scripts/hydrate-openclaw-managed-runtime.sh`
  - 将生成好的 payload 导入到仓库托管目录
- `scripts/sync-openclaw-managed-runtime.sh`
  - 将 Swift 侧托管目录镜像同步到 Electron 资源目录
- `scripts/validate-openclaw-managed-runtime.sh`
  - 校验 payload 是否完整、Swift/Electron 目录是否一致

## 4. 固定的 Upstream 版本

当前固定的 OpenClaw upstream 来源：

- 仓库：`https://github.com/openclaw/openclaw.git`
- 固定 ref：`afb4b1173be157997d3cea9247b598c3d1d9a18a`

这个固定 ref 已经写入：

- `managed-runtime/openclaw/managed-runtime.json`
- `apps/desktop/resources/openclaw/managed-runtime.json`
- `scripts/prepare-openclaw-managed-runtime.sh`

如果未来要升级 OpenClaw 版本，必须同时更新这三处。

## 5. 本地开发

### 5.1 前置条件

本地准备托管 Runtime 需要：

- macOS
- `git`
- `pnpm`
- `node`
- `swiftc`
- `install_name_tool`
- `otool`
- `codesign`

说明：

- 当前 native payload builder 会生成 macOS Darwin payload
- 它依赖 `swiftc` 构建原生 launcher
- 它会对私有 Node runtime 做依赖收集、路径重写和 ad-hoc 签名

### 5.2 最推荐的本地命令

如果你希望从固定 upstream ref 自动准备 Runtime，直接运行：

```bash
npm run prepare:openclaw-managed-runtime
```

等价命令：

```bash
bash ./scripts/prepare-openclaw-managed-runtime.sh
```

这个命令会自动完成：

1. 拉取固定 upstream ref
2. 检查是否已有 `openclaw.mjs` / `dist/entry.js` / `node_modules`
3. 缺失时执行：
   - `pnpm install`
   - `pnpm ui:build`
   - `pnpm build`
4. 生成 native launcher payload
5. hydrate 到 `managed-runtime/openclaw`
6. sync 到 `apps/desktop/resources/openclaw`
7. validate

### 5.3 使用已有本地 OpenClaw 源码目录

如果你已经自己拉好了 OpenClaw 源码，可以直接指定：

```bash
bash ./scripts/prepare-openclaw-managed-runtime.sh \
  --source /path/to/openclaw-source
```

适合场景：

- 你正在调试 OpenClaw upstream
- 你不想每次都重新 clone
- 你想验证某个本地改动是否可被托管打包

### 5.4 本地开发后的验证命令

建议最少执行以下检查：

```bash
bash ./scripts/validate-openclaw-managed-runtime.sh
```

```bash
cd managed-runtime/openclaw && ./bin/openclaw --version
```

```bash
cd apps/desktop/resources/openclaw && ./bin/openclaw --version
```

如果要进一步验证 Swift App 打包：

```bash
xcodebuild \
  -project ./Multi-Agent-Flow.xcodeproj \
  -scheme Multi-Agent-Flow \
  -destination 'platform=macOS' \
  -derivedDataPath ./DerivedData-codex/openclaw-native-payload \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### 5.5 本地开发的注意事项

- 不要把生成出来的 `dist/`、`node_modules/`、`runtime/`、`libexec/` 直接提交到 Git
- 本地运行 `prepare` 后，工作区里出现这些目录是正常的
- 这些目录默认已被 `.gitignore` 忽略
- 如果你只是改应用业务代码，不必每次都重新 prepare
- 只有以下情况建议重新 prepare：
  - 更新 OpenClaw upstream ref
  - 修改 builder / hydrate / sync / validate 脚本
  - 修改 launcher shim
  - 清空了 `.build/` 或托管目录

### 5.6 运行时观测与排障

当前 App 内的 `Managed Runtime` 面板已经补充了托管 sidecar 的关键观测字段，开发和联调时建议重点看这些信息：

- `Supervisor`
  - 当前托管状态，区分 `未运行`、`启动中`、`运行中`、`失败`
- `退出策略`
  - 当前是 `应用退出即停止` 还是 `应用退出后保持运行`
- `崩溃恢复`
  - 当前是 `自动恢复已启用` 还是 `需要手动恢复`
- `重启统计`
  - 显示 `总计 / 手动 / 自动恢复` 三类次数，避免把人工重启和崩溃恢复混为一谈
- `崩溃状态`
  - 显示当前连续异常退出次数，便于判断是否进入不稳定期
- `最近异常退出 / 最近恢复尝试 / 最近恢复成功`
  - 用于确认最近一次 crash-recovery 链路是否真正跑完

推荐排障顺序：

1. 先看 `Supervisor` 和 `最后一条状态消息`
2. 再看 `重启统计` 与 `崩溃状态`，判断是手动操作还是自动恢复
3. 如果是自动恢复问题，再看 `最近异常退出 / 最近恢复尝试 / 最近恢复成功`
4. 最后再去看 `日志路径` 对应的 gateway log

如果看到以下模式，通常可以快速判断问题类型：

- `自动恢复次数增加，但最近恢复成功为空`
  - 说明恢复流程被触发了，但没有成功拉起到可用状态
- `连续异常退出次数持续增加`
  - 说明 sidecar 仍处在 crash loop，需要优先检查 payload、端口占用或 runtime 依赖
- `手动重启次数增加，自动恢复次数不变`
  - 说明当前看到的是人工维护动作，不是 supervisor 后台恢复

## 6. CI 使用方式

### 6.1 当前 CI 行为

当前工作流文件：

- `.github/workflows/desktop-packaging.yml`

当前策略：

- 监听以下变更后触发打包：
  - `apps/desktop/**`
  - `managed-runtime/**`
  - `packages/**`
  - `package.json`
  - `package-lock.json`
  - `scripts/**`
  - `.github/workflows/desktop-packaging.yml`
- 在 `macOS` runner 上：
  - 安装 `pnpm`
  - 执行 `npm run prepare:openclaw-managed-runtime`
  - 再执行后续 typecheck / build / dist
- 在 `Windows` runner 上：
  - 当前不会执行 prepare
  - 现阶段的 managed runtime 打包链路仍以 macOS 为主

### 6.2 为什么 CI 只在 macOS 上 prepare

因为当前生成的是 Darwin payload，依赖：

- `swiftc`
- `install_name_tool`
- `otool`
- `codesign`

这是一条明确的 macOS 原生打包链路，不适合直接在 Windows runner 上复用。

因此当前设计是：

- macOS 包：构建时生成并打入托管 OpenClaw runtime
- Windows 包：暂不复用这条 Darwin-native payload builder

如果未来要支持 Windows 版应用内置 OpenClaw，需要单独补：

- Windows 私有 Node runtime 打包
- Windows launcher
- Windows 依赖重写和签名策略
- Windows 平台的 validate 规则

### 6.3 CI 成功的判断标准

CI 中最重要的三个成功信号：

1. `npm run prepare:openclaw-managed-runtime` 成功
2. `bash ./scripts/validate-openclaw-managed-runtime.sh` 成功
3. 后续 `dist:mac` 打包成功

如果 CI 在 prepare 阶段失败，优先排查：

- upstream ref 是否可拉取
- `pnpm install` / `pnpm build` 是否成功
- Node runtime 是否被正确收集和签名
- `managed-runtime/openclaw` 与 `apps/desktop/resources/openclaw` 是否同步一致

## 7. 正式发版流程

### 7.1 推荐发版顺序

正式发版时，建议按下面顺序执行：

1. 确认当前仓库已经在目标发布分支/提交点
2. 执行 Runtime 准备：

```bash
npm run prepare:openclaw-managed-runtime
```

3. 验证 Runtime：

```bash
bash ./scripts/validate-openclaw-managed-runtime.sh
```

4. 本地验证 OpenClaw launcher：

```bash
cd managed-runtime/openclaw && ./bin/openclaw --version
```

5. 构建 macOS App：

```bash
xcodebuild \
  -project ./Multi-Agent-Flow.xcodeproj \
  -scheme Multi-Agent-Flow \
  -destination 'platform=macOS' \
  -derivedDataPath ./DerivedData-codex/openclaw-release \
  CODE_SIGNING_ALLOWED=NO \
  build
```

6. 若需要 Electron 包，再执行：

```bash
npm run dist:mac --workspace @multi-agent-flow/desktop
```

### 7.2 发版前需要核对的内容

发版前必须核对：

- `managed-runtime.json` 中的 pinned upstream ref 是否正确
- 本地 prepare 使用的 upstream 是否与计划版本一致
- `./bin/openclaw --version` 输出是否符合预期
- `validate-openclaw-managed-runtime.sh` 是否通过
- App 打包是否成功
- 没有把生成出来的大 payload 制品误加入 Git 提交

### 7.3 发版留痕建议

建议在发版说明或 changelog 中记录：

- OpenClaw upstream repository
- OpenClaw upstream ref
- 实际运行时版本号
- 本次使用的 Node 主版本
- 是否重新生成了 managed runtime payload

建议最少留下面几项：

- upstream ref：`afb4b1173be157997d3cea9247b598c3d1d9a18a`
- runtime version：以 `./bin/openclaw --version` 实际输出为准
- payload strategy：`managed-native-launcher`

## 8. 升级 OpenClaw 版本时怎么做

如果未来要升级 OpenClaw upstream 版本，推荐步骤：

1. 修改固定 ref
   - `scripts/prepare-openclaw-managed-runtime.sh`
   - `managed-runtime/openclaw/managed-runtime.json`
   - `apps/desktop/resources/openclaw/managed-runtime.json`

2. 重新准备 Runtime

```bash
npm run prepare:openclaw-managed-runtime
```

3. 验证：

```bash
bash ./scripts/validate-openclaw-managed-runtime.sh
cd managed-runtime/openclaw && ./bin/openclaw --version
```

4. 本地重新打包 App

5. 确认没有把大 payload 目录误提交，只提交：
   - pinned ref 更新
   - 脚本改动
   - manifest 改动
   - 文档改动

## 9. 故障排查

### 9.1 `pnpm` 不存在

表现：

- `prepare-openclaw-managed-runtime.sh` 直接失败

解决：

```bash
npm install -g pnpm
```

### 9.2 `validate-openclaw-managed-runtime.sh` 失败

优先检查：

- 是否只 hydrate 了一个目录，没 sync
- `managed-runtime/openclaw` 与 `apps/desktop/resources/openclaw` 是否一致
- 是否残留 `.DS_Store`
- 是否缺少 `node_modules/`
- 是否缺少 `runtime/node/bin/node`

### 9.3 `./bin/openclaw --version` 无法运行

优先检查：

- `libexec/openclaw` 是否存在
- 私有 Node runtime 是否完整
- Node `.dylib` 是否已重写装载路径并重新签名
- `openclaw.mjs`、`dist/`、`node_modules/` 是否完整

### 9.4 Xcode build 失败

优先检查：

- Build phase 是否仍能复制 `managed-runtime/openclaw`
- Runtime payload 是否已成功 hydrate
- 是否误清空了托管目录
- 是否在未 prepare 的情况下直接打包

## 10. 当前边界

当前文档对应的是：

- macOS 托管 Runtime 构建链路
- Darwin native launcher payload
- Swift App / Electron macOS 打包联动

当前尚未覆盖：

- Windows 原生 OpenClaw managed runtime payload
- Linux 原生 OpenClaw managed runtime payload
- 多平台统一 payload builder

因此目前对外口径应保持一致：

- `OpenClaw Managed Runtime` 当前是构建时生成、应用内置、应用托管的 macOS 主链路
- 仓库不直接托管完整大制品
- CI 和发版流程围绕固定 upstream ref 做可复现构建
