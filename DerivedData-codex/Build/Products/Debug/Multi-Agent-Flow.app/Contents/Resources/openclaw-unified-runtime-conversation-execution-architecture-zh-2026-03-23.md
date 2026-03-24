# OpenClaw 受管运行时与聊天/执行双模式统一架构方案

最后更新：2026-03-23  
状态：总体方案定稿

## 文档目的

本文档用于统一以下三条设计线：

- OpenClaw 与本软件的深度融合方案
- 聊天模式与执行模式共存的产品架构
- 运行时控制面从固定四步流程升级为“门槛式状态模型”的设计

本文档是以下方案的统一收束版本：

- `openclaw-interaction-architecture-zh-2026-03-22.md`
- `openclaw-connection-layer-rearchitecture-plan-zh-2026-03-22.md`
- `conversation-control-system-design-zh-2026-03-23.md`

## 核心结论

系统应采用以下统一判断：

1. OpenClaw 不应继续作为“用户外部安装并由软件临时调用的 CLI”存在。
2. OpenClaw 应成为“由应用随包分发、受应用托管、受应用治理”的运行时底座。
3. 聊天模式与执行模式应明确区分，但共享同一套控制面、存储面、审批面和观测面。
4. `Connect -> Attach -> Sync -> Run/Chat` 不应再被理解为每次都必须按顺序执行的固定流程。
5. 更合理的模型是：

```text
Runtime / Control Plane
  Probe(Runtime)
  -> Bind(Project)
  -> Publish(Revision)

Execution Plane
  Execute(mode = chat | run | inspect)
```

一句话总结：

`OpenClaw 负责“跑起来”，本软件负责“为什么跑、以什么边界跑、如何记录、如何治理、如何恢复”。`

## 当前已落地进展

截至 2026-03-23，以下关键骨架已进入代码实现：

- 本地运行时已从“默认依赖外部 CLI”升级为“`deploymentKind = local` + `runtimeOwnership`”双因子模型。
- `runtimeOwnership = appManaged` 时，系统会优先解析应用包内、应用托管目录中的 OpenClaw，再回退到系统路径。
- Electron 侧已新增 `openclaw-host.ts`，统一处理本地二进制解析、容器命令规划与执行入口。
- Swift 侧已新增 `OpenClawHost.swift`，开始接管本地/容器命令规划、OpenClaw CLI 调用、ClawHub 调用与本地配置文件解析。
- `OpenClawManager` 已不再承担全部路径解析和命令规划职责，而是通过 `OpenClawHost` 进入受控执行面。
- UI 与 AppState 已从固定的 `Connect -> Attach -> Sync -> Run/Chat` 语义，升级为 `Probe / Bind / Publish / Execute` 控制面展示。
- 项目快照 `ProjectOpenClawSnapshot` 已新增控制面快照投影，并开始持久化 `summary / secondarySummary` 诊断，可作为聊天态与执行态共存时的统一恢复锚点。
- `OpenClawService` 已新增显式 `OpenClawRuntimeExecutionIntent`，当前至少区分：
  - `conversationAutonomous`
  - `workflowControlled`
  - `inspectionReadonly`
  - `benchmark`
- runtime dispatch / receipt / transcript event 已开始补写 `executionIntent`，归档层不再只能依赖 session 字符串前缀猜测聊天态或执行态。
- 正式执行入口与聊天入口已开始使用不同准入策略：
  - Workbench/后台续跑默认走 `conversationAutonomous`
  - Launch Verification 走 `inspectionReadonly`
  - ExecutionView 点击 Run 走 `workflowControlled`
- 当前代码已经开始强制执行“聊天可临时发布、正式执行需持久发布”的门槛：
  - `workflowControlled` 在 `local/container` 下要求已 `Bind` 当前项目、项目镜像已准备完成、runtime 已同步到最新 revision
  - `conversationAutonomous` 与 `inspectionReadonly` 在本地模式下允许以 `ephemeral publish` 继续
  - `remoteServer` 暂不强制本地 `persistent publish` 门槛
- `ProjectFileSystem` 已开始把 `threadType / sessionType / linkedSessionIDs / transport-plan.json` 写入归档目录。
- runtime session 归档已开始区分：
  - 产品线程 session
  - 网关传输 session
  - planned transport 与 actual transport
- 协作与运行时审计面已开始补齐：
  - `collaboration/workbench/threads/<thread>/turns.ndjson`
  - `collaboration/workbench/threads/<thread>/delegation.ndjson`
  - `runtime/sessions/<session>/spans.ndjson`
- `control/recovery.json` 已开始生成轻量恢复游标，汇总最近 thread/session、水位时间戳、approval/blocked/inflight/failed 风险与恢复建议。
- 项目恢复流程已开始消费 `control/recovery.json`，并转写为 `ProjectOpenClawSnapshot.recoveryReports` 的恢复摘要。
- Ops Center 的 session/thread investigation 已开始读取并展示 turn / delegation / span 审计证据。

这意味着当前系统已经从“方案设计阶段”进入“运行时宿主抽象与控制面下沉阶段”。

## 一、总体架构

系统整体分为 6 层。

### 1. Runtime Payload Layer

由应用随包分发并维护：

- Node Runtime
- OpenClaw `dist`
- 受控启动脚本
- 版本元数据
- 升级与回滚元数据

运行时不依赖用户 PATH，不依赖用户全局 npm 安装。

### 2. OpenClawHost Layer

这是系统内唯一允许直接管理 OpenClaw 生命周期的宿主抽象。

职责：

- 校验运行时版本
- 启动 / 停止 / 重启 Gateway
- 健康探测与握手
- 托管运行时目录与状态目录
- 执行 doctor / recovery / rollback
- 暴露统一宿主 RPC

所有 Swift、Electron、前端界面都不得直接：

- 查找 `openclaw` 路径
- 调 `Process()` 执行 OpenClaw 子命令
- 根据 deployment kind 手写 transport 分支

它们必须统一调用 `OpenClawHost`。

### 3. Control Kernel Layer

这是本产品自己的控制内核，不属于 OpenClaw 本身。

建议固定包含以下控制器：

- `Capability Controller`
- `Session Controller`
- `Policy Controller`
- `Conversation Controller`
- `Workflow Run Controller`
- `Approval Controller`
- `Receipt Controller`
- `Projection Controller`

### 4. Conversation Execution Layer

负责 `conversation.autonomous`、`conversation.assisted` 两类会话。

基本原则：

- 入口 agent 主导协作
- 软件只做边界治理
- 优先走 `gateway_chat`
- 不再要求外部 orchestrator 逐节点重排程

### 5. Controlled Run Execution Layer

负责 `run.controlled`、`inspection.readonly` 等正式执行与检查类会话。

基本原则：

- 软件主导编排
- OpenClaw 提供执行承载与 Gateway 控制面
- 优先走 `gateway_agent`
- 维持完整 dispatch / event / receipt / checkpoint 语义

### 6. Observability and Storage Layer

负责统一落盘、统一投影、统一运维入口。

共享事实来源包括：

- Thread
- Session
- Dispatch
- Event
- Receipt
- Approval
- Artifact
- Projection

## 二、OpenClaw 深度融合的推荐方式

### 推荐方案

最佳方案不是“继续适配外部 CLI”，而是：

`应用托管的 OpenClaw Managed Runtime Sidecar + Gateway 协议深度融合`

这意味着：

- OpenClaw 作为应用自带运行时存在
- 它由应用 supervision 层托管
- 应用业务层通过 Gateway 协议、OpenClawKit、协议模型与其交互
- 应用反向作为 node host 暴露原生能力给 OpenClaw

### 不推荐方案

- 默认依赖用户全局安装 `openclaw`
- UI / Swift / Electron 分别直接调用 OpenClaw CLI
- 把整个 OpenClaw Node 运行时嵌进主进程
- 继续把 CLI 文本输出当作产品级接口

### 深度融合边界

当前最稳定的融合边界应放在：

- Gateway WebSocket protocol
- Typed protocol models
- `health`
- `tools.catalog`
- `sessions.patch`
- `node.invoke`
- `connect.challenge` / `connect`

而不是放在 CLI 文本格式或路径约定上。

## 三、聊天模式与执行模式的统一产品模型

系统的一等对象固定为：

- `Project`
- `Workflow`
- `Node`
- `Agent`
- `Thread`
- `Turn`
- `Session`
- `Dispatch`
- `Event`
- `Receipt`
- `Approval`
- `Artifact`
- `Projection`

最重要的关系约束：

- `Thread` 是用户叙事对象
- `Session` 是运行时对象
- 一个 `Thread` 可以绑定多个 `Session`
- 聊天升级为执行时，保留原 `Thread`，新建 `run.controlled` `Session`
- 执行失败后回到解释线程时，应由 `Session` 派生解释性 `Thread`

## 四、运行时模型不再使用固定四步流程

## 1. 为什么不能继续固定为 `Connect -> Attach -> Sync -> Run/Chat`

因为这会把三种不同语义混在一起：

- 探测能力
- 建立项目绑定
- 发布运行时修订
- 执行任务

它们不应该被强制合并成一个线性用户流程。

## 2. 新的运行时语义模型

建议将运行时控制面改为四种语义门槛：

```text
Probe(Runtime)
Bind(Project)
Publish(Revision)
Execute(mode)
```

### `Probe`

语义：

- 发现 runtime
- 做 Gateway reachability / auth / capabilities 检查

特点：

- 只读
- 可自动触发
- 可缓存
- 不要求用户显式点击

### `Bind`

语义：

- 让某个 Project / Workflow / Thread 与当前 OpenClaw runtime 建立绑定关系

建议拆成两级：

- `lightBind`
- `strongBind`

`lightBind` 适合：

- 快速聊天
- 项目上下文绑定
- 会话目录绑定
- policy 和 scope 绑定

`strongBind` 适合：

- 正式执行
- runtime overlay 建立
- baseline 恢复
- 可写运行时上下文建立

### `Publish`

语义：

- 把某个 revision 或边界包真正下发给 runtime

建议拆成两级：

- `ephemeralPublish`
- `persistentSync`

`ephemeralPublish`：

- 面向单次聊天或预览执行
- 只临时下发上下文
- 不把 runtime 标记为“正式已同步”
- 不污染正式发布态

`persistentSync`：

- 面向正式运行态提交
- 会更新 runtime revision
- 生成正式 `RuntimeSyncReceipt`
- 对应“发布到运行时”

### `Execute`

语义：

- 消费当前运行时状态去执行任务

执行模式包括：

- `chat`
- `run`
- `inspect`

## 3. 内部关键状态

建议内核只维护以下四个关键状态，而不是暴露固定操作流：

```text
runtimeProbed
projectBound
revisionPublished
executionActive
```

## 4. 各场景的准入条件

```text
canQuickChat
  = runtimeProbed && gatewayChatAvailable

canProjectChat
  = runtimeProbed && projectBound

canControlledRun
  = runtimeProbed
    && projectBound
    && (
      revisionPublished
      || runPolicy.allowsEphemeralPublish
    )
```

### 4.1 当前代码中的实际准入规则

截至 2026-03-23，代码中的准入逻辑已经比上面的抽象模型更具体：

- `conversationAutonomous`
  - 允许轻绑定继续运行
  - 如果当前项目未强绑定、镜像仍有待准备变更、或 runtime published revision 落后于镜像 revision，会记录提示日志并按 `ephemeral publish` 语义继续
- `inspectionReadonly`
  - 与聊天类似，允许在不污染正式 published revision 的前提下发起只读检查
- `workflowControlled`
  - 在 `local/container` 模式下，必须满足以下条件才允许运行：
  - 当前项目已附着到 OpenClaw 会话
  - `workflowConfigurationRevision <= appliedToMirrorConfigurationRevision`
  - `syncedToRuntimeConfigurationRevision >= appliedToMirrorConfigurationRevision`
  - `sessionLifecycle.stage == synced`
  - `hasPendingMirrorChanges == false`
  - 任何一条不满足，都会直接阻止正式 Run，并给出针对 `Bind` / `Publish` / `Sync` 的明确提示
- `benchmark`
  - 作为独立意图保留，不再复用聊天态的提示逻辑
- `remoteServer`
  - 当前版本下暂不强制本地项目级 `persistent publish` 门槛，后续由远端控制面与回执体系接管

## 5. 各场景是否需要四个门槛

| 场景 | Probe | Bind | Publish | Execute |
| --- | --- | --- | --- | --- |
| 快速聊天 | 需要 | 可选，通常 `lightBind` | 否或 `ephemeralPublish` | `chat` |
| 项目内自治聊天 | 需要 | 是，通常 `lightBind` | 通常 `ephemeralPublish` | `chat` |
| 只读检查 | 需要 | 可选 | 否 | `inspect` |
| 正式执行，runtime 已同步 | 需要 | 是，`strongBind` | 否 | `run` |
| 正式执行，mirror/policy 有变更 | 需要 | 是，`strongBind` | 是，`persistentSync` | `run` |

当前落地实现可进一步归纳为：

- 聊天与检查默认“可继续，但会提示当前是临时发布语义”
- 正式执行默认“不可跳过 persistent publish”
- 这意味着 `Connect -> Attach -> Sync -> Run/Chat` 已不再是固定顺序流程，而是“按 execution intent 触发不同门槛”

## 五、双模式运行定义

## 1. 聊天模式：`conversation.autonomous`

定义：

- 用户面向入口 agent 对话
- 入口 agent 可在边界内自主协作
- 软件不做逐节点排程

软件职责：

- 确定入口 agent
- 下发协作边界包
- 下发 agent allowlist / tool scope / file scope
- 审批拦截
- 记录 thread / turn / delegation / artifacts / receipts

聊天模式的目标：

- 降低首回复延迟
- 提高连续交互体验
- 保持“像在和负责协调团队的主 agent 对话”的感觉

## 2. 执行模式：`run.controlled`

定义：

- 软件作为外部 orchestrator
- 按 workflow 结构与策略显式调度

软件职责：

- 生成 transport plan
- 管理 dispatch queue
- 做 timeout / retry / pause / resume
- 做 route sanitization
- 做审批 gating
- 记录完整 trace

执行模式的目标：

- 可控
- 可审计
- 可恢复
- 可回放

## 3. 二者的正确关系

二者不是：

- 两套完全独立系统
- 一个快一个慢的同构运行模式
- 一个只是另一个的 UI 壳

二者应当是：

- 不同的执行治理模型
- 共享相同控制面与数据面
- 共享相同运行时底座

## 六、统一的模式切换与升级策略

## 1. 默认入口

- Workbench 输入消息：默认 `conversation.autonomous`
- 点击 Run：默认 `run.controlled`

## 2. 聊天升级为执行

触发条件：

- 用户明确要求正式执行
- agent 建议升级
- 任务涉及长链路、多产物、强审计
- 请求涉及高风险写入

升级动作：

- 保留原 `Thread`
- 新建 `run.controlled` `Session`
- 将 `thread summary`、风险标记、边界包摘要转换为 `run` 启动参数
- 将原 `Thread` 标记为 `escalated_to_run`

## 3. 执行退回聊天

适用场景：

- run 失败需要解释
- run 被审批阻塞
- 用户希望继续讨论方案

退回动作：

- 从 `Session` 生成解释性 `Thread`
- 由入口 agent 面向用户解释现状
- 默认退回 `conversation.assisted` 或 `inspection.readonly`

## 七、写入分级模型

这是统一聊天与执行的关键。

建议把“写”分成四级：

### 1. `draftArtifact`

- 聊天模式产生的草稿、建议、候选文件
- 先落到协作目录
- 不进入正式设计态
- 不进入 runtime 正式态

### 2. `mirrorWrite`

- 进入 Project Mirror
- 属于设计态写入
- 必须生成 `artifact.write` receipt

### 3. `runtimePublish`

- 进入 runtime overlay 或 live runtime
- 属于运行态提交
- 必须生成 `RuntimeSyncReceipt`

### 4. `externalPublish`

- 真正向外部系统发布、导出、提交
- 属于高风险动作
- 必须走更高等级审批

这样可以同时保证：

- 聊天模式足够灵活
- 执行模式足够严格
- 不会出现“聊天直接改坏正式运行态”

## 八、统一文件系统方案

## 1. 全局运行时根

```text
Application Support/Multi-Agent-Flow/OpenClaw/
  runtimes/
    <runtime-version>/
  current/
  state/
  logs/
  tmp/
  backups/
  doctor/
  rollback/
```

说明：

- `state/` 对应应用私有 `OPENCLAW_STATE_DIR`
- 不复用用户 `~/.openclaw`
- 不放在 iCloud 等同步目录

## 2. 每项目控制根

```text
Application Support/Multi-Agent-Flow/Projects/<project-id>/
  manifest.json
  snapshot/
  design/
  collaboration/
  runtime/
  control/
  tasks/
  execution/
  openclaw/
  analytics/
  indexes/
```

其中：

- `design/` 是设计态真相源
- `collaboration/` 是聊天与自治协作证据面
- `runtime/` 是正式执行和运行态会话目录
- `control/` 是能力、策略、审批、恢复游标、目录索引控制面
- `analytics/` 是 projection 输出

当前 `control/` 的首个落地点：

- `control/recovery.json`
- 用于记录最近活跃 thread、最近可恢复 session、最近 audit watermark
- 同时汇总 `approval_pending / blocked / inflight / failed` 风险信号
- 恢复时先读该游标，再决定是直接恢复上下文、进入人工补偿，还是继续做 replay / rollback

## 九、统一状态与观测模型

建议统一以下对象：

- `CapabilityReport`
- `AttachmentContext`
- `TransportPlan`
- `TransportReceipt`
- `ConversationTurnReceipt`
- `WorkflowDispatchReceipt`
- `ApprovalDecisionReceipt`
- `ArtifactWriteReceipt`

最关键的观测规则：

- 必须同时记录 `plannedTransport`
- 必须同时记录 `actualTransport`
- 必须能解释 fallback 原因
- 必须区分聊天模式 delegation 与执行模式 dispatch

聊天模式支持三档观测：

- `blackbox`
- `summarized`
- `span_level`

执行模式默认要求：

- node-level receipt
- dispatch trace
- approval trace
- artifact trace

## 十、UI 与产品交互原则

## 1. 不再把四个语义点暴露成固定用户步骤

用户界面不应要求用户每次都显式执行：

- Connect
- Attach
- Sync
- Run

更合理的展示方式是状态徽标加按需动作：

- `Runtime Ready`
- `Project Bound`
- `Mirror Dirty`
- `Runtime Synced`

按需出现的动作：

- `快速对话`
- `正式执行`
- `同步到运行时`
- `恢复运行时`

## 2. Workbench 模式开关

Workbench 输入框旁建议固定显示：

- `快速对话`
- `正式执行`

说明文案：

- `快速对话`：由入口 agent 自主协作，优先追求更快、更自然的响应
- `正式执行`：按 workflow 受控执行，提供完整追踪与可审计能力

## 3. 自动提示规则

当用户在快速对话中提出：

- 强写入
- 长链路
- 多产物
- 多审批
- 高风险操作

系统可提示：

`建议切换为正式执行，以获得完整追踪与恢复能力。`

## 十一、与当前仓库结构的映射

## 1. 运行时配置模型

当前仍主要围绕：

- `local`
- `remoteServer`
- `container`
- `localBinaryPath`

后续应升级为：

- `appManaged`
- `externalLocal`
- `remoteServer`
- `container`

其中：

- `appManaged` 为默认生产模式
- `externalLocal` 仅保留给开发和诊断

## 2. 当前代码中的主要收口点

建议将以下现有模块作为改造锚点：

- `Sources/Models/OpenClawConfig.swift`
- `Sources/Services/OpenClawManager.swift`
- `Sources/Services/OpenClawTransportRouting.swift`
- `Sources/Services/OpenClawService.swift`
- `Sources/Services/AppState.swift`
- `Sources/Views/MessagesView.swift`
- `apps/desktop/electron/main.ts`
- `apps/desktop/src/App.tsx`
- `packages/domain/src/openclaw.ts`
- `packages/core/src/workbench.ts`

## 3. 关键改造方向

### `OpenClawConfig`

从“路径配置”升级为“宿主运行时配置”。

### `OpenClawManager`

从“CLI 与 Gateway 混合管理器”升级为：

- probe / bind / publish 管理器
- 不再直接承担大量 CLI 文本交互

### `OpenClawTransportRouting`

从“基于 session 字符串前缀猜 transport”升级为：

- 基于 `sessionType`
- 基于 `mode`
- 基于 capability report
- 基于 publish state

### `OpenClawService`

从“执行服务”升级为：

- chat execution service
- controlled run execution service
- transport receipt producer

### `AppState`

需要补齐：

- thread catalog
- session catalog
- mode switching
- escalation / de-escalation

### `MessagesView`

应从“发布 workbench prompt”升级为：

- 模式感知 Workbench
- 支持快速对话与正式执行双入口
- 展示 runtime badge / bind badge / sync badge

### `packages/core/src/workbench.ts`

需要从“workbench prompt 发布器”升级为：

- thread / turn / session 编排辅助库
- conversation boundary package 构造器
- execution publish 辅助器

## 十二、分阶段落地执行方案

## Phase 0：OpenClaw 宿主化

目标：

- 把 OpenClaw 从“外部 CLI 依赖”变成“应用托管运行时”

工作项：

- 引入 `appManaged` deployment kind
- 设计 `OpenClawHost`
- 固定应用私有 runtime root 和 `OPENCLAW_STATE_DIR`
- 建立运行时版本检查、升级、回滚与 doctor 机制
- 收口 Swift / Electron 对 CLI 路径的直接依赖

完成标准：

- 普通用户无需安装外部 `openclaw`
- 软件可独立启动、探测、停止 OpenClaw

## Phase 1：运行时模型重构

目标：

- 用 `Probe / Bind / Publish / Execute` 替代固定四步流程

工作项：

- 补齐 `runtimeProbed`、`projectBound`、`revisionPublished`、`executionActive`
- 定义 `lightBind`、`strongBind`
- 定义 `ephemeralPublish`、`persistentSync`
- 将现有 `Connect`、`Attach`、`Sync` UI 改造成状态徽标加按需动作

完成标准：

- 聊天不再被强制要求先做重型 sync
- 正式执行只在必要时要求 persistent sync

当前状态：

- 已部分落地
- `Probe / Bind / Publish / Execute` 已进入 UI、AppState、Project Snapshot
- 正式 Run 已开始执行 persistent publish 准入校验
- 聊天与检查已允许沿 `ephemeral publish` 继续

## Phase 2：显式会话类型与传输契约

目标：

- 去掉字符串前缀推断语义

工作项：

- 引入 `conversation.autonomous`
- 引入 `conversation.assisted`
- 引入 `run.controlled`
- 引入 `inspection.readonly`
- 补齐 `TransportPlan`
- 补齐 `plannedTransport` / `actualTransport`

完成标准：

- transport 由 capability + mode + sessionType 统一决策

当前状态：

- 已部分落地
- 当前代码先以 `executionIntent` 显式区分聊天、正式执行、只读检查与 benchmark
- transport routing 已开始把 `executionIntent` 纳入决策，而不再只依赖 `sessionID` 前缀和输出模式
- `sessionType` / `threadType` / `TransportPlan` 的共享语义与落盘链路已接通
- `turns.ndjson` / `delegation.ndjson` / `spans.ndjson` 已开始写盘
- `control/recovery.json` 已开始基于这些审计面和运行态摘要生成恢复游标
- 恢复链路已开始把 recovery cursor 转成 `recoveryReports`
- 后续仍需把这些审计文件继续接入增量 replay、resume policy 与更细粒度 projection

## Phase 3：Workbench 双模式化

目标：

- Workbench 真正支持“快速对话 / 正式执行”双入口

工作项：

- Workbench 输入框加入模式开关
- 聊天模式改为边界包下发
- 执行模式改为正式 run 启动
- 支持聊天升级为执行
- 支持执行退回解释线程

完成标准：

- 同一个 workflow 既能快速对话，也能正式执行
- 二者共享 thread/session/approval/artifact 目录

## Phase 4：控制面与审计面落盘

目标：

- 打通 thread / turn / delegation / receipt / approval / artifact 明细

工作项：

- 落 `thread.json`
- 落 `context.json`
- 落 `turns.ndjson`
- 落 `delegation.ndjson`
- 落 `session.json`
- 落 `transport-plan.json`
- 落 `receipts.ndjson`
- 落 `spans.ndjson`

完成标准：

- 聊天与执行都能被追查
- 线程与会话可单独调查

当前状态：

- 已部分落地
- `thread.json` / `context.json` / `session.json` / `transport-plan.json` / `dispatches.ndjson` / `events.ndjson` / `receipts.ndjson` 已存在
- 本轮已新增 `turns.ndjson` / `delegation.ndjson` / `spans.ndjson`
- 本轮已新增 `control/recovery.json`
- session/thread investigation 已能直接消费这些新增审计文件
- 恢复入口已开始先消费 recovery cursor，再把结果注入 `recoveryReports`
- 下一阶段重点应放在基于 recovery cursor 继续做增量回放、resume policy 和 Ops Center 深层调查入口

## Phase 5：Projection 与 Ops Center 升级

目标：

- 统一冷启动视图与运维视图

工作项：

- 补齐 `threads.json`
- 补齐 `sessions.json`
- 补齐 `conversation-health.json`
- 补齐 `workflow-health.json`
- 补齐 `approvals.json`
- 补齐 `artifacts.json`

完成标准：

- Ops Center 以 thread/session/approval/artifact 为一等入口

## 十三、近期建议的实际执行顺序

如果要按“风险最小、收益最快”的顺序推进，建议采用：

1. 先做 `OpenClawHost` 与 `appManaged`
2. 再做 `sessionType` / `threadType` / `TransportPlan`
3. 再做 Workbench 模式开关与 `conversation.autonomous`
4. 再做 `ephemeralPublish` / `persistentSync`
5. 最后补 delegation/span/projection/Ops Center

原因：

- 运行时归属不统一，后面所有模式设计都会漂
- session type 不显式，transport 与观测会继续混乱
- Workbench 模式不显式，用户认知会始终混成一团

## 十四、最终产品判断

最终系统应满足：

- 聊天像和一个会协调团队的负责人对话
- 执行像一条可回放、可审计、可恢复的正式流水线
- OpenClaw 是应用托管的运行时底座，不再是外部环境依赖
- 运行时前置条件按场景选择，不再机械要求每次走完整四步

最终总原则：

`聊天走自治协作，执行走受控编排，运行时走门槛式控制面，三者共享统一宿主、统一存储、统一治理、统一观测。`
