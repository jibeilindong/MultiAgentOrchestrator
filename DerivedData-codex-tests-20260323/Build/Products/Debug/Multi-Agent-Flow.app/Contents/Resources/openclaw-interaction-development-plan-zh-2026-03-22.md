# OpenClaw 交互开发计划

最后更新：2026-03-22
状态：待执行

## 目的

本文档将《OpenClaw 交互方案》拆成可落地的开发计划，覆盖数据模型、状态机、执行路径、用户界面、测试与验收。

## 开发目标

本次开发要完成的不是单点修补，而是 5 个方向的整体收口：

1. 统一连接与能力契约
2. 建立显式 attachment / sync 生命周期
3. 为对话路径提供稳定的高速通信体验
4. 为工作流路径提供稳定的热路径执行能力
5. 让 UI 与可观测性消费同一份事实来源

## 总体执行策略

采用“先收口状态模型，再重构交互路径，最后切 UI”的顺序。

原因：

- 如果先改 UI，底层状态仍然含糊，最终只会把问题换皮保留。
- 如果先做 transport 优化，但 session 和 attachment 语义没稳定，性能和正确性都会反复返工。

## 里程碑

### Milestone 1：能力模型落地

目标：

- 让所有运行入口都改为消费 capability report，而不是消费单一 `isConnected`

交付物：

- 统一 `OpenClawCapabilityReport`
- 统一 `OpenClawConnectionPhase`
- 统一 `canRunConversation` / `canRunWorkflow` / `canAttachProject`

建议修改范围：

- `Multi-Agent-Flow/Sources/Services/OpenClawManager.swift`
- `Multi-Agent-Flow/Sources/Services/AppState.swift`
- `Multi-Agent-Flow/Sources/Services/OpenClawService.swift`
- `apps/desktop/electron/openclaw-connection-state.ts`

验收标准：

- CLI-only 场景不再被表达为整体不可运行
- local/container/remote 的 probe 输出可以收敛成同一 contract
- 执行入口不再只检查 `isConnected`

### Milestone 2：Attachment 生命周期拆分

目标：

- 把 `Connect`、`Attach Project`、`Sync To Runtime` 分成独立生命周期

交付物：

- `OpenClawAttachmentContext`
- `AttachmentState`
- `appliedToMirrorRevision`
- `syncedToRuntimeRevision`

建议修改范围：

- `Multi-Agent-Flow/Sources/Services/OpenClawManager.swift`
- `Multi-Agent-Flow/Sources/Services/AppState.swift`
- `Multi-Agent-Flow/Sources/Models/MAProject.swift`
- `packages/domain/src/openclaw.ts`

验收标准：

- `Connect` 不再创建写入型 session 准备态
- `Apply To Mirror` 不再假装 runtime 已发布
- 可以独立查看 mirror revision 和 runtime synced revision

### Milestone 3：原子 Sync 与 Receipt

目标：

- 将 runtime sync 改造成可审计、可失败解释、可重试的提交动作

交付物：

- `RuntimeSyncReceipt`
- 原子 sync 流程
- 子步骤失败时的 partial failure 语义

建议修改范围：

- `Multi-Agent-Flow/Sources/Services/OpenClawManager.swift`
- `Multi-Agent-Flow/Sources/Services/ProjectFileSystem.swift`
- `Multi-Agent-Flow/Sources/Services/OpenClawService.swift`
- `Multi-Agent-Flow/Sources/OpsCenter/Models/*`

关键任务：

- 去掉整目录替换 live root 的主路径
- 建立 per-agent / per-file patch 提交
- 将 allow list、binding、managed files 纳入同一 receipt

验收标准：

- allow list 失败时不再把状态置为 `synced`
- 每次 sync 都有结构化 receipt
- 用户能看到“成功了什么，失败了什么”

### Milestone 4：类型化 Session 与 Transport Plan

目标：

- 把字符串前缀规则升级成显式 session model

交付物：

- `ConversationSession`
- `WorkflowRunSession`
- `InspectionSession`
- `TransportPlan`
- `TransportReceipt`

建议修改范围：

- `Multi-Agent-Flow/Sources/Services/OpenClawTransportRouting.swift`
- `Multi-Agent-Flow/Sources/Services/OpenClawService.swift`
- `packages/domain/src/openclaw-runtime.ts`
- `docs/openclaw-agent-runtime-protocol.md`

关键任务：

- 抽离 session type 判定
- 区分 `plannedTransport` 与 `actualTransport`
- 将 fallback reason 结构化

验收标准：

- 不再依赖 `workflow-*` / `workbench-*` 这类字符串前缀维持核心业务逻辑
- trace 和 execution result 中能同时看到计划 transport 与实际 transport

### Milestone 5：对话高速通信路径

目标：

- 让 Workbench / 对话路径稳定命中低延迟通道

交付物：

- 预热后的 `gateway_chat` session 管理
- 对话 keepalive / abort / reconnect 机制
- 对话路径降级提示

建议修改范围：

- `Multi-Agent-Flow/Sources/Services/OpenClawService.swift`
- `Multi-Agent-Flow/Sources/Services/OpenClawManager.swift`
- `Multi-Agent-Flow/Sources/Views/MessagesView.swift`
- `Multi-Agent-Flow/Sources/Views/TaskDashboardView.swift`

关键任务：

- websocket 预热
- session key 复用
- 流式 delta 优化
- abort 反馈稳定化

验收标准：

- 对话区默认可显示当前是否命中高速路径
- 发生降级时用户能明显感知
- abort 操作可预测，不出现悬挂状态

### Milestone 6：工作流热路径与恢复能力

目标：

- 让 workflow run 默认稳定命中 `gateway_agent`
- 为失败与重连提供恢复语义

交付物：

- `WorkflowRunResumePoint`
- 节点级 dispatch / attempt receipt
- preflight 与恢复策略

建议修改范围：

- `Multi-Agent-Flow/Sources/Services/OpenClawService.swift`
- `Multi-Agent-Flow/Sources/Services/AppState.swift`
- `Multi-Agent-Flow/Sources/OpsCenter/*`
- `Multi-Agent-FlowTests/OpenClawTransportRoutingTests.swift`

关键任务：

- preflight 检查
- 节点级 fallback 记录
- reconnect 后 resume
- execution UI 展示 synced revision 与 actual transport

验收标准：

- 工作流执行前能明确知道基于哪个 synced revision 运行
- fallback 节点可见
- 常见断线/超时后可以恢复或解释

### Milestone 7：UI 全面收口

目标：

- 让用户界面完全对齐新的交互语义

交付物：

- 新按钮命名
- 新 badge 体系
- 新文案
- 新状态提示

建议修改范围：

- `Multi-Agent-Flow/Sources/Views/WorkflowEditorView.swift`
- `Multi-Agent-Flow/Sources/Views/OpenClawConfigView.swift`
- `Multi-Agent-Flow/Sources/Views/ContentView.swift`
- `Multi-Agent-Flow/Sources/Services/LocalizationManager.swift`

建议 UI 变更：

- `Connect`
- `Attach Project`
- `Apply To Mirror`
- `Sync To Runtime`
- `Run`

Badge 建议：

- `Runtime Ready`
- `Runtime Degraded`
- `Runtime Detached`
- `Mirror Dirty`
- `Pending Sync`
- `Runtime Synced`
- `Conversation Fast Path Ready`
- `Workflow Hot Path Ready`

验收标准：

- 用户能明确分辨连接、附着、同步、运行的不同含义
- 不再出现“看起来已发布，实际上没进 runtime”的错觉

## 推荐实施顺序

建议按以下顺序合并：

1. 能力模型与状态收口
2. attachment 生命周期
3. sync receipt
4. session / transport model
5. 对话高速路径
6. workflow 热路径与恢复
7. UI 收口

不建议先做：

- 大规模 UI 换皮
- 继续叠加新的 transport 特判
- 在旧 `isConnected` 模型上继续补分支

## 测试计划

### 单元测试

重点覆盖：

- capability 判定
- attachment 状态机
- sync 成功 / 部分失败 / 完全失败
- transport plan 生成
- conversation / workflow session type
- fallback 策略

建议新增测试：

- `OpenClawCapabilityStateTests`
- `OpenClawAttachmentStateTests`
- `OpenClawRuntimeSyncReceiptTests`
- `OpenClawSessionTypeTests`
- `OpenClawConversationTransportTests`
- `OpenClawWorkflowExecutionRecoveryTests`

### 集成测试

重点覆盖：

- local CLI-only degraded runnable
- local CLI + Gateway ready
- container CLI + Gateway ready
- remote Gateway ready
- sync allow list failure
- workflow 节点 fallback receipt
- conversation abort / reconnect

### Live 验证

继续保留并扩展：

- `workflow_hot_path`
- `gateway_chat`
- `gateway_agent`
- `cli`

新增验证维度：

- planned vs actual transport 一致性
- synced revision 与 run revision 一致性
- conversation 首 token 延迟

## 风险与对策

### 风险 1：状态模型迁移期间出现双轨逻辑

对策：

- 在 domain 层先引入新字段
- 逐步废弃旧布尔语义
- 对旧字段标注 compatibility only

### 风险 2：旧项目快照兼容性

对策：

- 为 attachment state 和 revision 字段提供 decode fallback
- 恢复旧快照时默认进入 `detached + pending interpretation`

### 风险 3：sync 改造触及 live runtime 写路径

对策：

- 先实现 receipt 和 dry-run diff
- 再切换真正 patch sync
- 整目录替换路径先降为 emergency fallback

### 风险 4：高速对话和工作流热路径互相影响

对策：

- 在 execution layer 中按 session type 做资源隔离
- 不共享含糊的 active session 状态
- 分别记录 conversation / workflow 的 active run

## 完成定义

当满足以下条件时，本次计划视为完成：

1. `Connect` 已经成为只读动作。
2. `Attach Project`、`Apply To Mirror`、`Sync To Runtime`、`Run` 四者语义清晰。
3. CLI-only 场景可运行且 UI 可解释。
4. 对话默认走高速路径，工作流默认走热路径。
5. sync 与 run 都具备结构化 receipt。
6. 用户可以明确知道当前运行使用的是哪个 synced revision。
7. Ops Center 能直接读取 attachment / transport / receipt 事实进行展示。

## 相关文档

- [OpenClaw 交互方案](openclaw-interaction-architecture-zh-2026-03-22.md)
- [OpenClaw 连接层重构方案](openclaw-connection-layer-rearchitecture-plan-zh-2026-03-22.md)
- [OpenClaw 远程执行说明](OpenClaw-Remote-Execution.md)
