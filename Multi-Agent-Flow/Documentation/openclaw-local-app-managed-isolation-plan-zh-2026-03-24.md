# OpenClaw 本地连接 App-Managed-Only 强隔离改造方案

最后更新：2026-03-24  
状态：方案定稿，待按本文执行

## 文档目的

本文档用于定义 OpenClaw 本地连接模式的最终隔离方案，目标是在软件内彻底移除 `external binary` 路径之前，先把本地运行时设计成只允许应用私有托管实例存在。

本文关注的问题只有一个：

- 当用户机器上已经安装、甚至已经运行了系统级 `openclaw` 时，应用内置的 OpenClaw 是否还存在任何可能与其相互影响、相互接管、相互混淆的路径。

本文给出的答案不是“尽量避免”，而是“从产品能力、启动路径、状态目录、端口、探测协议和验收标准六个层面，把这种路径从系统里删掉或封死”。

## 核心结论

本地连接模式应收敛为唯一模式：

- `deploymentKind = local`
- `runtimeOwnership = appManaged`

系统不再支持也不再兼容以下行为：

- 用户在本地连接模式下手动指定 `openclaw` 二进制路径
- 通过历史配置自动推断进入 `externalLocal`
- 在托管运行时缺失时回退到系统 `PATH`
- 复用 `~/.openclaw`
- 因端口相同而误连到用户本机另一个 `openclaw`

一句话总结：

`本地连接必须只连接应用自己启动、自己标记、自己管理、自己验明身份的 OpenClaw sidecar。`

## 当前实现现状

当前代码已经具备较好的隔离基础：

- `appManaged` 本地运行时优先解析应用 bundle 与应用私有 managed runtime root 内的 OpenClaw。
- 托管运行时会注入 `OPENCLAW_CONFIG_PATH` 与 `OPENCLAW_STATE_DIR`，把配置和状态写入应用私有目录。
- 托管 sidecar 在首选端口被占用时会自动避让，不会强占已有端口。
- 运行时来源说明已经能够向 UI 暴露“不会复用 `~/.openclaw`，不会接管系统 PATH 中的 openclaw”。

当前代码参考：

- `Sources/Services/OpenClawHost.swift`
- `Sources/Services/OpenClawManagedRuntimeSupervisor.swift`
- `Sources/Services/OpenClawManager.swift`
- `apps/desktop/electron/openclaw-local-runtime.ts`

但从“足以发布”为标准看，仍有 4 个缺口：

- 历史配置和 Electron 侧仍然保留 `externalLocal` 自动推断路径。
- 托管进程启动时仍基于宿主环境变量做合并，理论上可能继承外部 `OPENCLAW_*` 变量。
- 本地 sidecar 仍保留“首选端口”语义，而不是完全应用内动态分配。
- 连接层尚未引入“实例归属校验”，理论上仍可能误连到另一个本地 Gateway。

## 设计目标

本方案必须同时满足以下 6 个目标：

- 应用绝不执行系统已安装的 `openclaw`。
- 应用绝不写入系统 `openclaw` 的配置目录、状态目录和日志目录。
- 应用绝不把系统中正在运行的 `openclaw` 识别为自己托管的 sidecar。
- 系统中已有 `openclaw` 占用默认端口时，应用仍可独立启动。
- 应用的 probe、stop、restart、recovery 只作用于自己启动的实例。
- 用户在 UI 和诊断信息中可以明确判断当前连接的是“应用托管实例”，而不是“系统现有实例”。

## 非目标

以下内容不属于本文目标：

- 解决两个不同 OpenClaw 实例访问同一外部远程服务时的业务层竞争问题
- 改造容器模式与远程服务器模式
- 定义 OpenClaw 本体内部的多实例共享资源策略

本文只处理“应用本地连接模式的宿主边界”。

## 最终架构原则

### 1. 单通道原则

本地连接只有一个合法入口：

- 应用内置或应用私有托管目录中的 OpenClaw binary
- 应用私有 runtime root
- 应用私有 state root
- 应用私有 supervisor root
- 应用动态分配并记录的 loopback Gateway 端口

任何指向用户系统 OpenClaw 的入口都视为设计缺陷。

### 2. 失败即不可用原则

当应用私有 OpenClaw runtime 缺失、损坏或版本不匹配时，系统应直接报告“托管运行时不可用”，而不是尝试：

- 回退到系统 PATH 中的 `openclaw`
- 回退到用户配置的 `localBinaryPath`
- 回退到 `~/.openclaw`

### 3. 明确归属原则

应用只连接和管理“自己能够证明归属”的本地 Gateway。  
不能因为某个端口上正好有一个 OpenClaw Gateway 在运行，就默认认为它属于本应用。

### 4. 外部存在可见但不可接管原则

系统可以探测到“机器上存在外部 OpenClaw”这一事实，并将其作为诊断信息展示。  
但应用不得：

- 接管它
- 停止它
- 复用它
- 将它纳入恢复流程

## 具体改造方案

### 一、删除 external binary 产品能力

产品与配置模型应完成如下收敛：

- 删除本地模式下的 `runtimeOwnership = externalLocal`。
- 删除 `localBinaryPath` 对本地连接的配置入口、展示入口和校验入口。
- 删除“只要 `localBinaryPath` 非空就推断为 `externalLocal`”的历史兼容逻辑。
- 所有历史项目只要 `deploymentKind = local`，在读取配置时统一归一化为 `runtimeOwnership = appManaged`。
- 历史项目中的 `localBinaryPath` 保留为迁移输入，但迁移完成后不再参与运行时决策。

实施重点文件：

- `Multi-Agent-Flow/Sources/Models/OpenClawConfig.swift`
- `apps/desktop/electron/main.ts`
- `Multi-Agent-Flow/Sources/Views/OpenClawConfigView.swift`
- `apps/desktop/src/App.tsx`

### 二、封死二进制解析回退路径

`appManaged` 模式下的二进制解析必须只允许以下候选：

- 应用 bundle 内 OpenClaw payload
- 应用私有 managed runtime root 内的 OpenClaw payload

必须禁止：

- 读取 `localBinaryPath`
- 读取系统 PATH
- 扫描 Home 目录下的用户安装位置
- 借用任何全局 npm 或 Homebrew 安装位置

推荐实现方式：

- 将 `OpenClawHost.resolveLocalBinaryPath` 改为在 `appManaged` 下只返回受控候选集合。
- 若受控候选全部不存在，直接抛出“managed runtime unavailable”错误。
- Electron 侧 `openclaw-local-runtime.ts` 保持同样的受控候选策略，不提供外部候选分支。

### 三、固定使用应用私有运行时目录

托管 sidecar 的全部运行痕迹必须写入应用私有目录，包括：

- `openclaw.json`
- `OPENCLAW_STATE_DIR`
- supervisor metadata
- PID state
- logs
- device identity

同时增加两层保护：

- 启动前校验目标路径不是 `~/.openclaw`
- 启动前校验目标路径不是指向用户目录的 symlink

若校验失败，应直接拒绝启动并报告配置污染，而不是回退到外部目录。

### 四、环境变量改为白名单继承

当前托管进程仍会从宿主环境继承变量并覆盖写入。  
这一点需要收紧为白名单模型。

目标规则：

- 启动前清除所有 `OPENCLAW_*`
- 只保留少量系统级安全变量，例如 `PATH`、`HOME`、`TMPDIR`、语言区域变量
- 再显式注入应用托管所需变量

这样可以避免以下风险：

- 用户 shell 已设置 `OPENCLAW_CONFIG_PATH`
- 用户 shell 已设置 `OPENCLAW_STATE_DIR`
- CI 或启动脚本注入了未知 `OPENCLAW_*`

### 五、本地 Gateway 端口改为应用动态分配

当前“首选端口被占用则避让”的做法是正确方向，但还不够硬。  
最终应改为：

- `appManaged` 启动时总是动态分配一个空闲 loopback 端口
- 该端口只作为当前托管实例的实际监听端口
- UI 可以展示该端口，但不把它当作用户必须维护的长期配置
- 本地 probe 和 runtime descriptor 统一使用实际端口，不依赖用户记忆中的默认端口

这样可以完全消除“用户系统 OpenClaw 占着默认端口导致本应用连错对象”的歧义。

### 六、引入实例归属令牌

这是确保“不会误连到另一个本地 OpenClaw”的关键措施。

建议新增 `managedOwnerToken` 机制：

- 应用首次初始化托管 runtime 时生成一个持久 owner token
- 启动 sidecar 时把该 token 写入应用私有 runtime config 或环境变量
- Gateway 在握手、health 或 probe 响应中返回该 token 或其指纹
- 应用连接本地 Gateway 时必须验证该 token

验收规则：

- token 匹配，视为“应用自有实例”
- token 不匹配，视为“外部实例或错误实例”，必须拒绝连接

这一机制可以彻底阻断以下误判：

- 本地已有另一个 OpenClaw 正在监听同类接口
- 端口被手动改回旧值
- supervisor 重启后误识别到外部进程

### 七、supervisor 只管理自有实例

stop、restart、recovery、crash cleanup 只允许针对以下对象执行：

- 由本应用 supervisor 启动
- 已写入本应用持久化 PID state
- 归属令牌校验通过

supervisor 不得基于如下条件接管外部实例：

- 端口相同
- 进程名相同
- 命令行中带有 `openclaw`

如果发现外部 `openclaw` 已存在，正确行为应是：

- 记录诊断
- 选择其他端口
- 保持隔离

而不是：

- kill 对方
- attach 对方
- stop 对方

### 八、诊断与 UI 表达要显式区分“外部存在”和“当前连接对象”

需要在 runtime descriptor、诊断报告和连接状态页里固定展示：

- 运行模式：`App Managed Only`
- binary 路径：应用私有
- runtime root：应用私有
- state root：应用私有
- supervisor root：应用私有
- requested port 与 actual port
- owner token 校验结果
- 是否检测到外部 `openclaw`
- 外部实例状态：`detected but not attached`

这样可以避免用户把“发现外部 OpenClaw”误解成“应用正在使用外部 OpenClaw”。

## 配置迁移方案

为避免升级后出现历史项目失联，配置迁移需要一次性完成：

### 迁移规则

- 若 `deploymentKind != local`，不处理。
- 若 `deploymentKind = local`，统一写回 `runtimeOwnership = appManaged`。
- 清空 `localBinaryPath`。
- 若旧配置包含 `externalLocal`，写入一次 migration note，供诊断页展示。

### 兼容策略

- 升级后的新版本仍能读取旧字段，但只用于生成迁移诊断，不用于决定运行行为。
- 所有新保存的配置都不得再写出 `externalLocal`。

### 用户可见提示

- 升级后首次打开本地连接项目时，可提示“本地 OpenClaw 已升级为应用托管模式，系统将不再使用外部 binary”。

## 验收标准

以下检查全部通过，才能认为“本地已有 OpenClaw 与应用托管 OpenClaw 不会互相干扰”：

- 机器已安装系统 `openclaw`，应用启动本地连接后，实际执行路径仍然来自应用 bundle 或 managed runtime root。
- `~/.openclaw` 预置配置和状态后，应用完成一次 connect、probe、chat、restart，目录内容无变化。
- 机器上已有系统 `openclaw` 正在运行并占用默认端口，应用仍能在新的 loopback 端口正常启动、连接和执行。
- 用户环境中预置 `OPENCLAW_CONFIG_PATH`、`OPENCLAW_STATE_DIR` 等变量时，应用托管 sidecar 的运行结果不受影响。
- 导入旧项目配置，其中包含 `externalLocal` 或 `localBinaryPath`，应用会自动迁移为 `appManaged`，且不会执行旧路径。
- 应用执行 stop、restart、recover 时，不会误杀系统中原本在跑的 `openclaw`。
- probe 命中了一个不带本应用 owner token 的本地 Gateway 时，应用必须拒绝接入并给出明确错误。
- UI 与诊断面可以同时展示“发现外部实例”和“当前连接的是应用私有实例”。

## 推荐测试拆分

建议新增或补强以下测试组：

- Swift 单元测试：`OpenClawConfig` 历史配置迁移与归一化
- Swift 单元测试：`OpenClawHost` 在 `appManaged` 下的候选路径封闭性
- Swift 单元测试：`OpenClawManagedRuntimeSupervisor` 的白名单环境继承
- Swift 单元测试：动态端口分配与实际端口回写
- Swift 单元测试：owner token 校验失败时的拒连逻辑
- Electron 测试：旧配置导入后不再落入 `externalLocal`
- 端到端共存测试：系统 OpenClaw 已运行时，应用托管实例仍可隔离启动
- 回归测试：stop/restart 不影响外部进程

## 实施顺序建议

为降低改造风险，建议按以下顺序落地：

1. 移除配置与 UI 中的 `externalLocal` 能力，完成历史配置迁移。
2. 收紧 `OpenClawHost` 与 Electron 侧 binary 解析策略，彻底封死外部路径。
3. 改造 supervisor 启动环境为白名单继承。
4. 将 app-managed 本地端口切换为动态分配。
5. 引入 owner token 并接入 probe、runtime descriptor 与诊断面。
6. 补齐共存与误连拒绝的自动化测试。

## 发布门槛

在以下条件未全部满足前，不建议正式删除 `external binary` 的代码路径：

- 旧配置迁移已经上线并稳定
- `appManaged` 本地运行时已不依赖任何外部 binary 回退
- owner token 校验已生效
- 共存测试已纳入 CI
- 诊断页已经能明确解释“外部实例已检测到但未接管”

当以上门槛全部满足后，可以进入下一阶段：

- 删除 `externalLocal` 枚举值
- 删除 `localBinaryPath` 本地连接语义
- 删除与 external binary 相关的 UI、测试和兼容代码

## 最终判断

如果按本文方案完成改造，则可以把本地连接模式定义为：

- 只使用应用私有 OpenClaw runtime
- 只连接应用私有 OpenClaw Gateway
- 只管理应用私有 OpenClaw sidecar

在这个前提下，用户机器上是否已经安装 OpenClaw、是否已经有另一个 OpenClaw 正在运行，都不会影响应用内本地连接的正确性，也不会被本应用接管或破坏。
