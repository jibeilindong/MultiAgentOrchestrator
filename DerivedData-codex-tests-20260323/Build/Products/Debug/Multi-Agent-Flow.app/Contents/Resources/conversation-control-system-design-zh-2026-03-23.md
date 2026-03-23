# 对话控制系统设计方案

最后更新：2026-03-23
状态：方案拟定

## 目标

基于“首 agent 自主协作 + 正式执行受控编排”的新方案，设计一套统一的：

- 对话控制系统
- 执行控制系统
- 文件系统
- 仪表盘系统

该方案的核心目标是同时满足两类诉求：

1. 在聊天场景下，让用户获得更快、更自然、更连续的体验。
2. 在正式执行场景下，让系统具备可控、可审计、可恢复的能力。

## 核心判断

新的系统不应继续把“聊天”和“正式执行”混成同一种运行方式。

应当明确拆分为两种模式：

1. `Autonomous Conversation`
   入口 agent 直接面向用户，内部可自主调用 subagent 协作。
2. `Controlled Workflow Run`
   软件作为外部调度器，按 workflow 结构受控执行。

这两种模式共享底层的项目文件系统、权限系统、会话目录、审批系统、产物系统与仪表盘系统。

## 总体产品模型

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

这些对象之间的关系如下：

- 用户在 `Thread` 中发起聊天或执行请求
- 每次来回形成一个或多个 `Turn`
- `Thread` 绑定一个或多个 `Session`
- `Session` 中产生 `Dispatch / Event / Receipt`
- `Workflow / Node / Agent` 提供执行结构
- `Artifact` 记录产物
- `Projection` 为仪表盘提供快速读取的聚合结果

## 双模式运行设计

## 1. 聊天模式：`Autonomous Conversation`

### 定义

用户对工作流中的入口 agent 发起聊天，但软件不再逐节点调度后续 agent，而是允许入口 agent 在边界内自主调用 subagent 协作。

### 用户视角下的行为

- 用户选择一个 workflow
- 软件确定入口 agent
- 用户输入消息
- 软件将消息直接交给入口 agent
- 入口 agent 自主决定是否调用其他 agent 或工具
- 最终由入口 agent 直接返回统一回复

### 软件在此模式中的职责

软件不再承担逐节点调度，而是负责：

- 入口 agent 选择
- workflow 上下文打包
- agent allowlist 下发
- file scope 和 tool scope 下发
- 审批拦截
- 对话线程记录
- 会话与产物记录
- 指标统计与仪表盘投影

### 此模式的目标

- 降低首回复延迟
- 保持上下文连续
- 提供更自然的交互体验
- 让用户感觉自己在和“负责协调团队的主 agent”沟通

## 2. 执行模式：`Controlled Workflow Run`

### 定义

软件作为外部 orchestrator，按 workflow 结构和策略对各 node 进行逐步调度。

### 用户视角下的行为

- 用户点击执行 workflow
- 软件根据 workflow 结构创建运行 session
- 每个节点依次或按 routing 策略执行
- 软件记录 dispatch、event、receipt、approval、artifact
- 遇到失败、重试、超时、审批时由软件接管
- 最终产生正式运行结果

### 软件在此模式中的职责

- 生成 transport plan
- 管理 dispatch queue
- 做 route sanitization
- 做审批 gating
- 做 timeout / retry / pause / resume
- 记录完整 runtime trace

### 此模式的目标

- 完整可审计
- 完整可恢复
- 节点级问题可定位
- 历史运行可回放

## 3. 两种模式的定位

### 聊天模式

- 速度优先
- 自然交互优先
- 入口 agent 自治协作
- 软件做边界治理

### 执行模式

- 可控优先
- 可解释优先
- 软件显式编排
- agent 接受明确调度

## 统一对话控制系统

建议将控制系统拆为 8 个子系统。

## 1. Capability Controller

### 职责

- 探测当前 OpenClaw runtime 能力
- 判断是否可聊天
- 判断是否可正式执行
- 判断是否支持 transcript/history
- 判断是否支持 subagent 协作

### 标准输出

```text
CapabilityReport
  canChat
  canRunWorkflow
  canReadSessionHistory
  canUseSubagentCollaboration
  preferredConversationTransport
  preferredWorkflowTransport
  degradationReason
```

## 2. Session Controller

### 职责

- 创建和恢复 session
- 显式管理 session type
- 管理 thread 与 session 的绑定关系
- 提供 session 生命周期状态

### 建议的 session type

- `conversation.autonomous`
- `conversation.assisted`
- `run.controlled`
- `inspection.readonly`

### 建议字段

- `sessionID`
- `sessionType`
- `threadID`
- `workflowID`
- `entryAgentID`
- `transportPlan`
- `startedAt`
- `endedAt`
- `status`

## 3. Policy Controller

### 职责

- 决定用户这次请求属于聊天还是执行
- 生成允许协作的 agent allowlist
- 生成 file scope / tool scope
- 判断哪些行为需要审批

### 基本策略

- 用户在 Workbench 发送消息，默认进入 `conversation.autonomous`
- 用户点击 Run，默认进入 `run.controlled`
- 用户可从聊天升级为正式执行
- 聊天模式内部协作只能在 workflow 允许范围内发生
- 超出 file/tool/approval 边界必须阻断或审批

## 4. Conversation Controller

### 职责

- 管理 thread
- 管理 turn
- 管理消息 streaming
- 管理 thread summary
- 管理“聊天升级为执行”

### thread 状态建议

- `draft`
- `queued`
- `running`
- `waiting_approval`
- `responded`
- `follow_up_ready`
- `escalated_to_run`
- `failed`
- `closed`

### turn 状态建议

- `submitted`
- `accepted`
- `streaming`
- `completed`
- `failed`
- `aborted`

## 5. Workflow Run Controller

### 职责

- 管理正式执行的调度状态
- 管理 dispatch queue
- 做 timeout / retry / pause / resume
- 管理 node 级 receipt

### run 状态建议

- `planned`
- `dispatched`
- `accepted`
- `running`
- `waiting_approval`
- `paused`
- `completed`
- `failed`
- `expired`
- `aborted`

## 6. Approval Controller

### 职责

- 管理聊天模式中的高风险内部协作审批
- 管理执行模式中的 edge/agent/tool/artifact 审批
- 统一审批状态流转

### 审批对象字段

- `approvalID`
- `scope`
- `threadID`
- `sessionID`
- `sourceAgentID`
- `targetAgentID`
- `requestedAction`
- `reason`
- `status`
- `requestedAt`
- `resolvedAt`
- `resolvedBy`

### approval scope

- `edge`
- `agent`
- `tool`
- `artifact`
- `workflow`

## 7. Receipt Controller

### 职责

- 为所有关键动作生成可审计 receipt
- 支持对话排查、运行排查与仪表盘渲染

### receipt type

- `conversation.turn`
- `conversation.delegation`
- `workflow.dispatch`
- `workflow.node_result`
- `approval.decision`
- `artifact.write`
- `session.close`

## 8. Projection Controller

### 职责

- 从实时内存与明细 ndjson 中汇总投影
- 让仪表盘冷启动优先读取 projection
- 支持历史趋势分析和实时控制台

## 模式切换规则

## 1. 默认入口

- Workbench 输入消息：进入 `Autonomous Conversation`
- Run 按钮：进入 `Controlled Workflow Run`

## 2. 聊天升级为执行

满足以下情况时，允许或建议升级：

- 用户明确要求“正式执行”
- agent 建议进入正式执行
- 任务涉及长链路、多产物、强审计
- 当前请求涉及高风险写入

升级动作：

- 保留原 thread
- 创建新的 controlled run session
- 将 thread summary 和关键上下文转移到 run 启动参数
- thread 状态变为 `escalated_to_run`

## 3. 执行退回聊天

适用于：

- run 失败，需要解释
- run 被审批阻塞，需要人工判断
- 用户希望继续讨论方案

退回动作：

- 从 session 生成解释线程
- 由入口 agent 面向用户解释当前状态

## 聊天模式详细设计

## 1. 协作边界包

聊天模式中，软件给入口 agent 的核心输入不再是“逐节点执行命令”，而是“协作边界包”。

### 边界包内容

- 用户消息
- workflow 摘要
- 入口 agent 身份
- 可协作 agent 列表
- 每个 agent 的角色摘要
- file scope
- tool scope
- approval-required targets
- 当前 thread summary
- 最近几轮 turn 摘要

### 聊天模式中不再强制的东西

- 最后一行 routing JSON
- 软件逐节点决定是否继续
- 每次内部协作都必须回到外部 orchestrator 重新排程

## 2. 聊天模式下的入口 agent 能力

入口 agent 可以：

- 自己直接回答
- 自主调用 subagent
- 请求审批后调用高风险 subagent
- 使用允许范围内的工具
- 产出草稿、建议、文件或分析结果
- 向用户提出“建议转正式执行”

## 3. 聊天模式的可观测性分层

由于 runtime 不一定能完整暴露内部 subagent 过程，因此建议支持三档可观测性：

- `blackbox`
- `summarized`
- `span_level`

### blackbox

- 只知道最终回复和总耗时

### summarized

- 能知道“是否发生过内部协作”和协作摘要

### span_level

- 能记录内部 delegation span、工具调用 span、阶段耗时

## 4. 聊天模式的 assistant turn 输出结构

建议标准化为：

- `visibleReply`
- `collaborationSummary`
- `suggestedNextActions`
- `artifacts`
- `riskFlags`
- `delegationStats`

其中只有 `visibleReply` 是强用户可见，其他内容可折叠展示。

## 执行模式详细设计

执行模式延续现有受控编排模型，但要与聊天模式共享统一的数据目录和投影系统。

## 1. 保留的核心能力

- dispatch queue
- inflight dispatches
- route sanitization
- node-level receipts
- retry
- timeout
- pause / resume
- approval gating
- runtime trace

## 2. 与聊天模式共享的能力

- 同一 project root
- 同一 session catalog
- 同一 approval store
- 同一 artifact store
- 同一 projections
- 同一 Ops Center

## 文件系统设计

新的方案不重写现有 managed project root，而是在现有目录结构上增强控制面与对话面。

## 建议的 managed project root

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

建议新增 `control/`，将能力探测、策略、审批、会话目录等控制状态独立出来。

## 推荐目录结构

```text
Projects/<project-id>/
  manifest.json

  snapshot/
    current.maoproj
    autosave.maoproj

  design/
    project.json
    workflows/
      <workflow-id>/
        workflow.json
        nodes/
        edges/
        boundaries/
        derived/

  collaboration/
    workbench/
      threads/
        <thread-id>/
          thread.json
          context.json
          summary.json
          dialog.ndjson
          turns.ndjson
          delegation.ndjson
          approvals.ndjson
          artifacts/
          investigation.json

    communications/
      messages.ndjson
      approvals.ndjson
      escalations.ndjson

  runtime/
    sessions/
      <session-id>/
        session.json
        transport-plan.json
        dispatches.ndjson
        events.ndjson
        receipts.ndjson
        spans.ndjson
        artifacts/
          index.json
        checkpoints/
          latest.json
    state/
      runtime-state.json
      queue.json

  control/
    capability-report.json
    policy/
      effective-policy.json
      agent-allowlist.json
      tool-allowlist.json
      file-scope-map.json
    approvals/
      pending.json
      resolved.ndjson
    session-catalog.json
    thread-catalog.json
    escalation-rules.json

  tasks/
    tasks.json
    workspace-index.json

  execution/
    results.ndjson
    logs.ndjson

  openclaw/
    session/
      backup/
      mirror/
      agents/

  analytics/
    analytics.sqlite
    projections/
      overview.json
      live-run.json
      sessions.json
      threads.json
      workflow-health.json
      nodes-runtime.json
      conversation-health.json
      approvals.json
      artifacts.json

  indexes/
    workflows.json
    nodes.json
    threads.json
    sessions.json
    approvals.json
    artifacts.json
```

## 关键文件定义

## 1. `thread.json`

用于记录线程头信息。

### 字段建议

- `threadID`
- `threadType`
- `mode`
- `status`
- `workflowID`
- `workflowName`
- `entryAgentID`
- `entryAgentName`
- `linkedSessionIDs`
- `startedAt`
- `lastUpdatedAt`
- `messageCount`
- `turnCount`
- `approvalCount`
- `artifactCount`
- `latestTurnID`

### mode

- `autonomous_conversation`
- `controlled_run`
- `conversation_to_run`

## 2. `context.json`

用于记录 thread 的稳定上下文。

### 字段建议

- `projectSummary`
- `workflowSummary`
- `entryAgentSummary`
- `participantAgents`
- `fileScopes`
- `toolScopes`
- `approvalTargets`
- `activeObjectives`
- `pinnedArtifacts`
- `threadSummary`

## 3. `turns.ndjson`

一轮交互一条记录。

### 字段建议

- `turnID`
- `threadID`
- `role`
- `submittedAt`
- `acceptedAt`
- `firstChunkAt`
- `completedAt`
- `status`
- `visibleReply`
- `summary`
- `tokenEstimate`
- `sessionID`
- `receiptID`
- `riskFlags`

## 4. `delegation.ndjson`

这是聊天模式新增的关键文件，用于记录入口 agent 的内部协作摘要或 span。

### 字段建议

- `delegationID`
- `threadID`
- `turnID`
- `sessionID`
- `sourceAgentID`
- `targetAgentID`
- `kind`
- `visibilityLevel`
- `summary`
- `startedAt`
- `completedAt`
- `status`
- `approvalRequired`
- `artifactIDs`

### kind

- `internal_subagent`
- `tool_proxy`
- `external_handoff`

## 5. `session.json`

统一描述一次运行会话。

### 字段建议

- `sessionID`
- `sessionType`
- `threadID`
- `workflowID`
- `entryAgentID`
- `transportKind`
- `status`
- `startedAt`
- `endedAt`
- `lastUpdatedAt`
- `visibilityLevel`
- `queuedDispatchCount`
- `inflightDispatchCount`
- `completedDispatchCount`
- `failedDispatchCount`
- `isPrimaryRuntimeSession`

## 6. `transport-plan.json`

解释本次执行为什么走某条 transport 路径。

### 字段建议

- `sessionID`
- `requestedMode`
- `resolvedMode`
- `preferredTransport`
- `actualTransport`
- `capabilitySnapshot`
- `fallbackReason`
- `degradationReason`

## 7. `spans.ndjson`

若 runtime 能提供内部 span，则写入此文件。

### 字段建议

- `spanID`
- `sessionID`
- `parentSpanID`
- `spanType`
- `actor`
- `summary`
- `status`
- `startedAt`
- `completedAt`
- `toolName`
- `artifactRefs`

## 8. `investigation.json`

用于仪表盘快速打开 thread 调查摘要。

### 字段建议

- `threadID`
- `sessionIDs`
- `workflowID`
- `entryAgentID`
- `relatedNodeIDs`
- `status`
- `turnCount`
- `delegationCount`
- `approvalCount`
- `artifactCount`
- `latestFailureText`
- `latencySummary`
- `riskSummary`

## 控制状态机设计

## 1. 线程状态机

```text
draft
-> queued
-> running
-> waiting_approval
-> responded
-> follow_up_ready
-> escalated_to_run
-> closed

异常分支:
queued/running -> failed
running -> aborted
```

### 状态语义

- `responded`：当前轮已回复用户
- `follow_up_ready`：线程仍可继续追问
- `escalated_to_run`：已从聊天升级为正式执行
- `closed`：线程结束

## 2. 运行状态机

```text
planned
-> dispatched
-> accepted
-> running
-> waiting_approval
-> paused
-> completed

异常分支:
running -> failed
running -> expired
running -> aborted
```

## 3. 审批状态机

```text
requested
-> pending
-> approved
-> rejected
-> expired
-> superseded
```

## 权限与边界控制

系统必须在“快”和“可控”之间保持平衡。

## 1. 聊天模式中的硬边界

即使入口 agent 可自主协作，也必须保留以下硬边界：

- agent allowlist
- tool allowlist
- file write scope
- approval-required targets
- artifact write policy

## 2. 聊天模式中的治理原则

- 可自由协作，但只能在 workflow 允许的 agent 范围内
- 可思考和计划，但不可越过项目文件边界
- 可建议高风险动作，但必须先审批
- 可生成草稿，但正式写回设计镜像需生成 receipt

## 3. 执行模式中的治理原则

- 每次 dispatch 都有状态
- 每次 route 都可审计
- 每次 artifact 写入都要 receipt
- 审批阻塞是强阻塞

## 仪表盘系统设计

新方案下，仪表盘不能只看 workflow，还必须把 thread、session、approval、artifact 一起提升为一等对象。

建议构建 6 个主页面。

## 1. Command Center

### 目标

回答一句话：

“现在正在发生什么，哪里卡住了，最该先看什么？”

### 展示内容

- 当前活跃 threads
- 当前活跃 sessions
- 待审批项
- 首回复延迟异常
- 失败 run
- 高风险 artifact 写入
- 最近从聊天升级为执行的 threads

### 核心指标

- `activeThreads`
- `activeSessions`
- `waitingApprovals`
- `firstReplyP95`
- `failedRuns24h`
- `escalationsToday`

## 2. Threads

### 定位

聊天模式主页面。

### thread 卡片内容

- 用户最后一句摘要
- 入口 agent
- 当前状态
- 首回复耗时
- 总耗时
- 内部协作次数
- 是否升级成 run
- 是否有待审批

### 打开 thread 后展示

- 对话时间线
- 每轮 turn
- 协作摘要或 span
- 产物
- 风险标记
- linked sessions

## 3. Sessions

### 定位

runtime 主页面。

### session 摘要内容

- session 类型
- transport
- dispatch 计数
- event 计数
- receipt 计数
- 失败数
- 是否为 primary session
- 最近错误

### 打开 session 后展示

- dispatch timeline
- events
- receipts
- spans
- artifacts
- linked thread
- linked workflow

## 4. Workflow Map

### 定位

正式执行结构可视化页面。

### 节点叠加信息

- 当前状态
- 平均耗时
- 最近错误
- 最近 24 小时命中次数
- 审批等待频率
- file pressure

### 边叠加信息

- route 频率
- approval 频率
- 失败率

### 聊天模式的弱叠加

- 哪个 thread 最近使用了哪些 node/agent
- 哪个入口 agent 最常触发内部协作

## 5. Approvals

### 定位

审批独立页面。

### 展示内容

- 当前待审批
- 最近已审批
- 按 scope 分类
- 按 thread/session 分类
- 审批平均等待时长
- 高频被拦截 agent

## 6. History

### 定位

长期趋势与治理分析页面。

### 展示内容

- first reply latency
- full completion latency
- escalation ratio
- conversation success rate
- controlled run success rate
- approval burden
- artifact write volume
- top failing workflows
- top overloaded agents

## 核心仪表盘指标

## 1. 聊天模式指标

- `firstChunkMs`
- `firstReplyMs`
- `conversationCompletionMs`
- `delegationCount`
- `delegationDepth`
- `approvalCount`
- `escalationRate`
- `artifactCount`
- `followUpRate`

## 2. 执行模式指标

- `dispatchLatencyMs`
- `nodeCompletionMs`
- `workflowCompletionMs`
- `retryCount`
- `approvalWaitMs`
- `routeRepairCount`
- `failureRate`
- `resumeCount`

## 3. 跨模式指标

- `stuckThreadCount`
- `stuckSessionCount`
- `policyViolationCount`
- `transportMismatchCount`
- `degradationCount`

## 投影文件设计

建议补齐以下 projection：

- `analytics/projections/live-run.json`
- `analytics/projections/sessions.json`
- `analytics/projections/threads.json`
- `analytics/projections/nodes-runtime.json`
- `analytics/projections/workflow-health.json`
- `analytics/projections/conversation-health.json`
- `analytics/projections/approvals.json`
- `analytics/projections/artifacts.json`

## 推荐的 `conversation-health.json`

```text
conversation-health.json
  generatedAt
  totalThreads
  activeThreads
  respondedThreads
  failedThreads
  escalatedThreads
  p50FirstReplyMs
  p95FirstReplyMs
  averageDelegationCount
  approvalPendingCount
  topSlowEntryAgents[]
  topEscalatedWorkflows[]
```

## 推荐的 `threads.json`

每个 thread 一条摘要：

- `threadID`
- `workflowID`
- `entryAgentID`
- `status`
- `mode`
- `startedAt`
- `lastUpdatedAt`
- `turnCount`
- `delegationCount`
- `artifactCount`
- `approvalCount`
- `firstReplyMs`
- `completionMs`
- `latestSummary`
- `linkedRunID`

## 推荐的 `sessions.json`

每个 session 一条摘要：

- `sessionID`
- `sessionType`
- `threadID`
- `workflowID`
- `entryAgentID`
- `transportKind`
- `status`
- `dispatchCount`
- `eventCount`
- `receiptCount`
- `failedDispatchCount`
- `lastUpdatedAt`
- `latestFailureText`

## 交互设计建议

最重要的是让用户明确知道“当前是在快速对话”还是“在正式执行”。

建议在 Workbench 输入框旁提供显式模式开关：

- `快速对话`
- `正式执行`

### 用户提示文案建议

- `快速对话`：由入口 agent 自主协作，优先追求更快、更自然的响应
- `正式执行`：按 workflow 受控执行，提供完整追踪与可审计能力

### 自动提示规则

若用户在 `快速对话` 中提出明显适合受控执行的请求，系统可提示：

“建议切换为正式执行，以获得完整追踪与恢复能力。”

## 迁移策略

建议分四期落地。

## Phase 1：显式 session type 和 thread type

目标：

- 补齐 `sessionType`
- 补齐 `threadType`
- 补齐 `transport-plan`
- 不大改现有产品行为

## Phase 2：Workbench 切换为真正的 autonomous conversation

目标：

- 去掉聊天模式中强制 routing JSON 的要求
- 将入口 agent 升级为自治协作入口
- 软件仅下发边界包和可协作名单

## Phase 3：补齐 delegation / span / approval / artifact 明细落盘

目标：

- 新增 `turns.ndjson`
- 新增 `delegation.ndjson`
- 新增 `spans.ndjson`
- 新增 conversation projections

## Phase 4：升级 Ops Center

目标：

- 真正打通 Threads / Sessions / Workflow Map / Approvals / History
- 将 thread、session、approval、artifact 全部作为一等调查入口

## 最终产品结论

新系统的核心原则应当是：

- 让“聊天”像和一个会主动协调团队的负责人对话
- 让“执行”像一条每一步都能回放和审计的正式生产流水线

一句话总结：

`聊天走自治协作，执行走受控编排，二者共享统一存储、统一控制、统一观测。`
