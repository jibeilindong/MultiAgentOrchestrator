# OpenClaw 连接层重构方案

最后更新：2026-03-22
状态：已开始执行

## 目的

本文档定义 Multi-Agent-Flow 下一代 OpenClaw 连接层方案。

这次重构的目标，不只是修复当前连接问题，而是把 OpenClaw 正式提升为系统运行时后端，能够稳定支撑：

- 可靠的连接语义
- 高速工作流执行
- 工作台对话流
- 离线可用的工作流设计
- 本地、容器、远程三种部署的一致行为
- 可观测的降级与恢复

## 为什么需要这次重构

当前实现把太多职责混进了“连接 OpenClaw”这个动作里：

- 发现部署
- 探测连通性
- 鉴权
- 加载 agent 清单
- 处理项目 mirror
- 绑定运行时 session
- 决定执行 transport
- 向 UI 发布状态

这导致当前代码里已经暴露出 5 类结构性问题：

1. 连接前置动作会修改真实 OpenClaw 状态
2. Swift 与 Electron 对“已连接”的定义不一致
3. 容器模式的发现链路并不总是读取真实容器状态
4. CLI 探测可能阻塞或卡死
5. Gateway 断线没有稳定回推到公开应用状态

## 产品目标

重构后的连接层需要确保：

1. 连接默认是只读动作
2. 项目 attach 与 runtime sync 是显式生命周期步骤
3. 工作流热路径继续优先走 `gateway_agent`
4. 工作台对话继续优先走 `gateway_chat`
5. CLI 成为可控 fallback，而不是隐式默认路径
6. 即使运行时不可用，工作流设计依然可进行
7. 用户可以明确分辨 `ready`、`degraded`、`blocked`、`detached`

## 架构原则

### 1. 只有一套连接契约

所有界面和执行入口都必须使用同一套 probe 语义和同一份事实来源。

### 2. 基于能力的运行时状态

系统不能再依赖单个 `isConnected` 布尔值，而应暴露能力型状态：

- CLI 是否可用
- Gateway 是否可达
- Gateway 是否通过鉴权
- agent.list 是否可读
- `gateway_agent` 是否可用
- `gateway_chat` 是否可用
- project attach 是否支持

### 3. 结构化 transport 策略

transport 选择必须由运行时能力和任务类型决定，而不是由零散 UI 分支决定。

### 4. 连接只读，写回显式提交

连接 OpenClaw 时不能写入真实运行时。任何对 live runtime 的修改，都应通过显式 attach/sync 动作触发。

### 5. 设计期与运行期分离

工作流构建必须允许离线进行。运行时验证是增强，而不是阻断设计体验。

## 目标架构

新的连接层拆成 4 层。

### 1. Discovery Layer

职责：

- 定位 OpenClaw 部署
- 识别部署类型
- 定位 runtime root 与 config path
- 收集原始 inventory 候选

这一层只读。

### 2. Probe Layer

职责：

- 验证 CLI 可用性
- 验证 Gateway 握手
- 验证鉴权
- 验证 agent 列表能力
- 验证 session/history 能力
- 发布统一 capability report

输出：

- `OpenClawProbeReport`

### 3. Runtime Attachment Layer

职责：

- 为 project 建立 attachment context
- 加载 baseline snapshot
- 准备 mirror workspace
- 计算安全 diff
- 控制是否允许 commit 到 live runtime

这一层负责：

- attach
- sync
- detach
- restore

### 4. Execution Layer

职责：

- 路由工作台执行
- 路由工作流热路径
- 复用 gateway session
- 管理 CLI fallback
- 输出 transport 指标

这一层消费的是 capability state，而不是直接猜 config。

## 统一连接状态模型

系统应从布尔连接模型升级为结构化运行时状态：

```text
OpenClawConnectionState
  phase:
    idle | discovering | probed | ready | degraded | detached | failed
  deploymentKind:
    local | container | remoteServer
  capabilities:
    cliAvailable
    gatewayReachable
    gatewayAuthenticated
    agentListingAvailable
    sessionHistoryAvailable
    gatewayAgentAvailable
    gatewayChatAvailable
    projectAttachmentSupported
  health:
    lastProbeAt
    lastHeartbeatAt
    latencyMs
    degradationReason
  inventory:
    agents
    sourceOfTruth
```

## 统一 Probe 结果

无论 local、container 还是 remote，都应该收敛成同一个报告结构：

```text
OpenClawProbeReport
  success
  deploymentKind
  endpoint
  authMode
  capabilities
  health
  agents
  warnings
  errors
  sourceOfTruth
  observedDefaultTransports
```

这份报告将成为以下模块的唯一事实来源：

- AppState
- 工作台可发布性判断
- 工作流执行可发布性判断
- benchmark transport 可用性判断
- UI 连接状态徽标
- Ops Center 运行诊断

## Transport 策略

transport 策略必须显式化，并由 capability 驱动。

### 首选路径

- `workflow-*` session 优先 `gateway_agent`
- `workbench-*` session 优先 `gateway_chat`
- transcript/session 型任务优先 `gateway_chat`
- CLI 只作为 local/container 下的 fallback

### 路由规则

1. 如果存在 `gateway_agent` 能力，且任务属于 workflow hot path，则使用 `gateway_agent`。
2. 如果存在 `gateway_chat` 能力，且任务属于对话/session 型，则使用 `gateway_chat`。
3. 如果 gateway 在 local/container 模式下失败，且策略允许 fallback，则退化到 CLI。
4. 如果 gateway 在 remote 模式下失败，不允许静默改写成另一套执行契约。

## 工作流设计可行性

工作流设计不能依赖实时 OpenClaw runtime。

系统需要区分：

- 结构是否有效
- 运行时是否就绪
- 当前部署是否兼容

建议的 workflow 状态：

- `draft`
- `structurally_valid`
- `runtime_ready`
- `runtime_degraded`
- `runtime_blocked`

也就是说，编辑器在离线状态下仍然应可用；当 probe report 和 inventory snapshot 存在时，再叠加 runtime 校验信息。

## 容器与远程模式的一致性

建议把部署行为统一收敛到 adapter：

```text
OpenClawDeploymentAdapter
  discover()
  probe()
  fetchInventory()
  fetchRuntimeSnapshot()
  attachProject()
  commitMirror()
  executeGatewayAgent()
  executeGatewayChat()
  executeCLI()
```

具体实现：

- `LocalOpenClawAdapter`
- `ContainerOpenClawAdapter`
- `RemoteGatewayAdapter`

这样可以去掉 Swift 和 Electron 之间重复且冲突的连接逻辑。

## 可观测性模型

连接状态不能只靠日志，而应输出结构化连接事件。

建议事件类型：

- `connection.discovery_started`
- `connection.discovery_completed`
- `connection.probe_started`
- `connection.probe_succeeded`
- `connection.probe_failed`
- `connection.degraded`
- `connection.recovered`
- `connection.attached`
- `connection.sync_started`
- `connection.sync_completed`
- `connection.sync_rejected`
- `connection.detached`

这些事件应进入：

- runtime state
- Ops Center
- transport benchmark 报告
- 支持诊断链路

## 执行计划

### Phase 1：先稳定连接事实

- 引入统一连接状态模型
- 把 Gateway 断线回推到公开应用状态
- 统一不同界面的 probe 语义
- 去掉阻塞式 CLI 探测，统一超时控制
- 停止在普通连接检查时改写 live runtime

### Phase 2：统一 transport policy

- 将 transport 路由收敛到 capability 驱动策略
- 让 benchmark、workbench、workflow 执行共用同一套规则
- 让 fallback 策略显式且可观测

### Phase 3：拆开设计期与运行期

- 为 workflow 增加 runtime readiness 状态
- 引入带新鲜度元数据的 inventory snapshot
- 保持编辑器离线可用

### Phase 4：引入 deployment adapter

- 定义 local/container/remote adapter
- 删除重复的连接逻辑
- 统一 inventory 与 runtime snapshot 的读取链路

### Phase 5：正式建立 runtime attachment 生命周期

- 把 probe、attach、sync、detach 拆成显式动作
- 让 baseline snapshot 与 mirror commit 成为显式步骤
- 在 sync 前增加 safe diff 与冲突处理

## 验收标准

当满足以下条件时，说明重构成功：

1. Gateway 掉线后，应用不会继续显示假在线
2. connect 默认不再改写真实 OpenClaw runtime
3. 本地、容器、远程部署输出同一套 probe 契约
4. 当能力可用时，workflow hot path 仍然命中 `gateway_agent`
5. workbench 保持 session 友好，不被强制退化成 CLI 语义
6. workflow 编辑在离线状态下依然可进行
7. 用户能明确分辨 runtime 是 ready、degraded 还是 blocked

## 实施状态

已经开始执行。

当前第一批落地动作：

- 补齐目标架构文档
- 从 Phase 1 开始，先把 Gateway 断线信号回推到公开应用状态
- 将 `connect` / `beginSession` 改为只读 attach 流程，默认不再把项目镜像写入 live OpenClaw runtime
- 增加持久化的 `ConnectionState` / `ProbeReport` 初始骨架，让 probe 结果、能力状态和降级状态先具备正式兼容层
- 开始把桌面端 `connect` / `detect` 收敛到统一的 `probe` 契约，并把 `ConnectionState` / `ProbeReport` 从 Electron 主进程贯通到项目快照持久化链路
- 容器模式的 agent 发现优先改为读取容器内 `openclaw config file` 指向的真实配置，减少宿主机挂载路径猜测带来的偏差
- Swift 侧 probe / CLI 与容器快照打包解包主链路切换到带双管道并发读取与超时终止的安全执行器，避免连接测试或归档过程因 Pipe 缓冲区写满而挂死
- 桌面端 Gateway probe 从 HTTP `fetch()` 提升为 WebSocket upgrade + `connect.challenge` + `connect` RPC 校验，并补上持久化 device identity 签名载荷，远程/本地模式继续向 Swift Gateway 语义对齐
- 桌面端已抽出纯 `connection-state` 判定 helper，并补齐 `ready / degraded / detached / failed` 回归测试，开始把连接状态机从实现细节升级为可验证契约
- 桌面端 `connection-state` helper 已继续细化为 `transport / authentication / session / inventory` 四层状态判断，并覆盖本地、容器、远程、彻底失败四类回归场景
- `transport / authentication / session / inventory` 四层状态已正式进入 `ProbeReport` 结构化字段，Electron `connect` / `detect` 开始复用共享结果构造器；Swift 项目快照也补上兼容旧存档的 `layers` 解码路径
- 桌面端已新增运行时 readiness helper，把四层状态接入 OpenClaw 配置面板、Operations dashboard 与 live workflow preflight；其中 `transport / authentication / session` 降级现在会阻断高速实时执行，`inventory` 降级则保留为可恢复告警
- launch verification 与审批后的下游 live continuation 现已复用同一套 readiness gating：runtime 被阻断时不再静默退回 synthetic 路径，而是将阻断原因写回 verification / workbench 状态
- readiness helper 已进一步映射出结构化 recovery actions，诊断面板可直接触发 `Connect` / `Detect agents`，并对需要人工修正的 host、container、credential 配置给出明确修复建议
- 桌面端已支持半自动 recovery plan 编排：当恢复链路安全时可按顺序执行 `Connect -> Detect agents`，并在需要人工修正配置时中途暂停并输出明确的接力提示
- 桌面端恢复流程现已记录 before / after 差异报告，明确展示 readiness、layer 状态和恢复步骤是否真正改善了 runtime，避免“执行过恢复”但实际仍停留在旧退化状态的误判
- 恢复报告现已持久化到 `ProjectOpenClawSnapshot`，项目重开后仍可查看最近恢复记录；桌面端也开始展示 recent recovery 列表，为后续跨会话恢复审计和自动重试策略提供基座
- 桌面端现已将恢复历史升级为 recovery audit 视图，汇总 completed / partial / manual / failed / improved / reached ready 等指标，并在时间线中展开 steps、manual follow-up 与关键 findings，开始形成可读的恢复审计面
- 桌面端已开始基于当前 readiness 与 recovery audit 生成 retry guidance，能明确区分 `auto_retry / manual_first / observe / not_needed`，开始把连接层从“可恢复”推进到“可决策”
