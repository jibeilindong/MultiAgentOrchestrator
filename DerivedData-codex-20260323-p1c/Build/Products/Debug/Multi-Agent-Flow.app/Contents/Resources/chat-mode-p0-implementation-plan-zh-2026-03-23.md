# 聊天模式 P0 实施拆解

日期：2026-03-23

## 0. 当前实施状态

截至 2026-03-23，P0 主体开发已基本完成，状态如下：

- 已完成：thread identity 建模
- 已完成：Workbench 消息按 thread 过滤
- 已完成：task/message metadata 统一写入 thread 信息
- 已完成：transcript merge 改为非破坏式 append-first
- 已完成：OpenClawService thread-aware active run registry
- 已完成：Stop 行为改为 thread-aware
- 已完成：MessagesView 线程可见性，支持 thread 切换与新开 thread
- 已完成：`RuntimeState.activeWorkbenchRuns` 持久化与恢复链路
- 已完成：线程运行状态在 UI 中的基础可视化

当前剩余工作：

- 补齐 P0 文档收尾
- 补齐回归测试与测试环境验证
- 处理测试阶段的资源复制 sandbox 阻塞

当前验证结论：

- `xcodebuild ... build` 已通过
- `xcodebuild ... test` 目前仍被构建阶段资源复制阻塞，不是新增 Swift 编译错误
- 当前测试阻塞点已从先前的 `rm/unlink` 变为 `ditto` 复制 `managed-runtime/openclaw`

## 1. P0 目标

P0 不解决“聊天模式自治化”全部问题，只做止血，目标是 4 件事：

- 把 `chat`、`run`、`chat->run` 从同一条混乱线程里拆开
- 让历史回放不再破坏本地消息
- 让停止能力覆盖整个 thread 的活跃执行单元
- 为后续 P1 聊天控制器拆分准备稳定的身份模型

一句话定义：

**先把 thread 变成一等对象，再去谈 autonomous conversation。**

## 2. P0 范围

### 2.1 包含

- thread identity 建模
- Workbench 消息过滤改造
- task/message metadata 统一
- transcript merge 改为非破坏式
- thread 级 active run registry
- Stop 行为改为 thread-aware
- 基础迁移与兼容读取

### 2.2 不包含

- 去掉 routing JSON
- 新的 conversation controller
- delegation/span/artifact 新文件格式
- Ops Center 全量重构
- 多线程并发 UI 完整交互设计

## 3. 当前模型问题与 P0 对应修复

### 3.1 当前模型

当前真正被复用的键主要有 3 个：

- `project.runtimeState.sessionID`
- `workbenchSessionID`
- `workflowID`

但它们分别承担了 5 类语义：

- runtime project session
- workbench 会话
- thread 展示过滤
- gateway session 推导
- 历史回放目标定位

这就是混线根源。

### 3.2 P0 新模型

P0 需要把这 5 类语义拆开成至少 4 个显式字段：

- `projectSessionID`
- `threadID`
- `threadType`
- `threadMode`

补充建议字段：

- `threadEntryAgentID`
- `threadOrigin`，取值建议：`workbench_chat` / `workbench_run` / `chat_to_run`
- `threadGatewaySessionKey`

## 4. 数据模型改造

### 4.1 新增统一 metadata key

建议统一引入以下 metadata 键，供 `Message` 和 `Task` 共用：

- `workbenchThreadID`
- `workbenchThreadType`
- `workbenchThreadMode`
- `workbenchThreadOrigin`
- `workbenchEntryAgentID`
- `workbenchProjectSessionID`
- `workbenchGatewaySessionKey`

保留但降级旧字段：

- `workbenchSessionID`

P0 期间兼容策略：

- 新写入时同时写新字段和旧字段
- 读取时优先读 `workbenchThreadID`
- 如果没有 `workbenchThreadID`，再从旧 `workbenchSessionID` 推导

### 4.2 新增 thread 上下文类型

建议在 `AppState` 或单独模型文件中新增：

```swift
struct WorkbenchThreadContext: Hashable, Codable, Sendable {
    let threadID: String
    let workflowID: UUID
    let projectSessionID: String
    let threadType: RuntimeSessionSemanticType
    let threadMode: WorkbenchThreadSemanticMode
    let interactionMode: WorkbenchInteractionMode
    let entryAgentID: UUID
    let entryAgentName: String
    let gatewaySessionKey: String?
}
```

说明：

- `threadID` 是 Workbench 展示与历史回放的主键。
- `gatewaySessionKey` 是远端 transcript/abort 的目标键，不再由 UI 临时推导。
- `workbenchSessionID` 可以暂时保留，但只作为兼容字段，不再承担 thread key 职责。

### 4.3 RuntimeState 补充 thread 级 registry

当前 `RuntimeState` 里只有 dispatch 队列和 runtime events，没有 thread registry。

P0 建议新增：

```swift
struct WorkbenchActiveRunRecord: Codable, Hashable, Identifiable {
    let id: String
    var threadID: String
    var workflowID: String
    var runID: String
    var sessionKey: String
    var transportKind: String
    var executionIntent: String
    var startedAt: Date
    var updatedAt: Date
    var status: String
}
```

在 `RuntimeState` 中新增：

- `activeWorkbenchRuns: [WorkbenchActiveRunRecord]`

用途：

- 让 Stop 按钮不再依赖 `OpenClawService` 的单一全局 active run。
- 让 thread 与远端 run 建立稳定映射。

## 5. 服务层实施任务

### 5.1 AppState：集中生成 thread context

目标：

- 所有 Workbench 提交都必须先生成 `WorkbenchThreadContext`
- 后续 task/message/history/stop 都只围绕该对象工作

建议新增方法：

```swift
private func makeWorkbenchThreadContext(
    workflow: Workflow,
    leadAgent: Agent,
    mode: WorkbenchInteractionMode,
    reuseExistingThreadID: String? = nil
) -> WorkbenchThreadContext
```

生成规则建议：

- `threadID` 不能再只由 `workflowID + agentID` 构成
- 必须至少包含：
  - `projectSessionID`
  - `workflowID`
  - `mode/threadType`
  - 新生成的稳定 thread token

建议格式：

`thread-<projectSessionID>-<workflowID>-<mode>-<uuid>`

这样可以保证：

- 同一 workflow 可以有多个聊天线程
- chat 与 run 天然分离
- chat->run 可以新开 thread，而不是污染旧 thread

### 5.2 AppState：统一 metadata 写入入口

当前 `applyWorkbenchSemanticMetadata` 只写 type/mode，不写 thread identity。

建议改为：

```swift
private func applyWorkbenchThreadMetadata(
    _ metadata: inout [String: String],
    context: WorkbenchThreadContext
)
```

职责：

- 一次性写入全部 thread 相关字段
- 保证 `Task` 与 `Message` 的 metadata 一致
- 兼容期内顺手写旧 `workbenchSessionID`

### 5.3 MessageManager：按 thread 过滤，而不是按 workflow 过滤

当前：

- `workbenchMessages(for workflowID: UUID?)`

P0 建议替换为：

```swift
func workbenchMessages(threadID: String?) -> [Message]
func workbenchMessages(workflowID: UUID?, threadID: String?) -> [Message]
```

最低要求：

- 主消息流必须优先按 `threadID` 过滤
- `workflowID` 只能作为补充约束

兼容读取策略：

- 如果 message 没有 `workbenchThreadID`
- 且 threadID 为空
- 才允许按旧逻辑回退

### 5.4 AppState：历史回放改为 thread-scoped

当前的 `latestWorkbenchRemoteSessionContext` 有 3 个问题：

- 它返回“最新 session”，不是“当前 thread”
- 它没有显式 threadID
- 它会跨模式误选最近 task/message

P0 需要改为：

```swift
private func workbenchRemoteSessionContext(
    for threadID: String,
    workflow: Workflow,
    project: MAProject
) -> WorkbenchRemoteSessionContext?
```

关键原则：

- 只能根据当前选中的 thread 去拉 transcript
- 不能再从整个 workflow 里猜“最近一个”
- 不能再从 run 线程回放成 chat 线程

### 5.5 AppState：mergeWorkbenchTranscript 改为非破坏式 append-first

P0 建议放弃当前“按 role 顺序覆盖”的 merge 策略，改为三段式：

1. 尝试用稳定 identity 命中
2. 命不中时按内容 hash + 时间窗口弱匹配
3. 仍命不中则 append，不覆盖

建议新增 metadata：

- `remoteTranscriptRole`
- `remoteTranscriptTimestamp`
- `remoteTranscriptDigest`

P0 阶段即使拿不到远端 message id，也至少做 digest：

`sha256(role + normalizedText + roundedTimestampBucket)`

P0 的底线规则：

- 不确定时只追加，不覆盖
- merge 时不得改写已有 message 的 `threadType/threadMode`
- merge 时不得把 run 线程强制转成 chat

### 5.6 OpenClawService：引入 thread 级 active run 跟踪

当前只有：

- `activeGatewayRunID`
- `activeGatewaySessionKey`

它们是单值，无法表示多个 thread/runs。

P0 建议：

- 保留旧字段做兼容 UI
- 新增：

```swift
@Published var activeWorkbenchRunsByThreadID: [String: [WorkbenchActiveRunHandle]]
```

或直接通过 `RuntimeState.activeWorkbenchRuns` 统一读写。

建议运行时句柄：

```swift
struct WorkbenchActiveRunHandle: Identifiable, Hashable {
    let id: String
    let threadID: String
    let runID: String
    let sessionKey: String
    let executionIntent: String
    let transportKind: String
}
```

登记时机：

- gateway chat run started
- gateway agent run started
- 后台 workflow node 如有远端 run 也要登记

清理时机：

- run 完成
- abort accepted
- disconnect
- thread reset

### 5.7 OpenClawService：Stop 改为 thread-aware

新增接口建议：

```swift
func abortWorkbenchThread(threadID: String)
```

行为：

- 找到 thread 下所有 active run
- 逐个发 abort
- 更新本地 active registry
- 写入 thread 级系统消息或日志

UI 不再通过“有没有单个 activeGatewayRunID”来决定按钮显隐，而是：

- 当前 thread 是否存在 active runs

## 6. UI 层实施任务

### 6.1 MessagesView：增加当前 thread 状态

当前只有：

- `selectedWorkflowID`
- `submitMode`

P0 需要至少新增：

- `selectedThreadID`

推荐行为：

- 每次发送新 prompt，创建或切换到对应 thread
- 当前消息面板只展示该 thread 的消息

### 6.2 MessagesView：Stop 按钮基于当前 thread

当前：

- `canStopActiveRemoteConversation` 只看全局单值 run/session

改造后：

- `canStopCurrentThread`
- `isStoppingCurrentThread`

数据来源：

- `AppState` 提供当前 thread 的 active run 数量

### 6.3 MessagesView：为后续 thread list 预留状态位

P0 不一定要完整做 thread list UI，但建议先预留：

- `availableWorkbenchThreads(for workflowID)`
- `preferredThreadID`

这样 Iteration 2 不需要再二次重构状态树。

## 7. 迁移策略

### 7.1 兼容读取

老数据没有 `workbenchThreadID` 时：

- 从 `workbenchSessionID + workbenchThreadType + workbenchMode + workflowID` 推导一个兼容 thread key
- 只用于本地显示，不回写覆盖原记录

### 7.2 渐进写入

P0 上线后：

- 新 task/message 全部写入新 thread 字段
- 同时继续写旧 `workbenchSessionID`
- 等 P1/P2 稳定后再考虑清理旧字段依赖

### 7.3 安全边界

P0 不建议做全量历史迁移脚本，原因：

- 当前老消息没有稳定远端 id
- 批量重写 thread 可能放大错配风险

推荐：

- 运行时 lazy migration
- 读到旧记录时推导 thread identity
- 新记录按新 schema 落地

## 8. 实施顺序

建议按下面顺序落地，避免反复返工：

### Step 1

- 新增 `WorkbenchThreadContext`
- 新增 metadata key 常量
- 新增 threadID 生成方法

### Step 2

- `submitWorkbenchPrompt`
- `submitWorkbenchRunPrompt`
- `applyWorkbenchSemanticMetadata`

统一切换到 thread context 写入

### Step 3

- `MessageManager.workbenchMessages`
- `MessagesView.workbenchMessages`

改为按 thread 过滤

### Step 4

- `refreshWorkbenchHistory`
- `latestWorkbenchRemoteSessionContext`
- `mergeWorkbenchTranscript`

改为 thread-scoped + 非破坏式 merge

### Step 5

- `OpenClawService` active run registry
- thread-aware stop
- `MessagesView` Stop 按钮状态改造

### Step 6

- 兼容读取
- 回归测试
- 手工验证

## 9. 文件级改造地图

### 必改

- `Multi-Agent-Flow/Sources/Services/AppState.swift`
- `Multi-Agent-Flow/Sources/Services/MessageManager.swift`
- `Multi-Agent-Flow/Sources/Services/OpenClawService.swift`
- `Multi-Agent-Flow/Sources/Views/MessagesView.swift`
- `Multi-Agent-Flow/Sources/Models/MAProject.swift`

### 可选但推荐

- `Multi-Agent-Flow/Sources/Models/Message.swift`
- `Multi-Agent-Flow/Sources/Models/Task.swift`

建议原因：

- 可以增加 thread 相关推导属性，减少 metadata 字符串散落在业务层。

## 10. 验收用例

### Case 1. chat 与 run 分离

步骤：

1. 在同一 workflow 先发一次 chat
2. 再发一次 run
3. 切换不同 thread

验收：

- 两组消息不混在同一消息流
- Stop 状态只作用于当前 thread

### Case 2. 同一 workflow 两次 chat 不串线

步骤：

1. 发一轮 chat A
2. 再开启 chat B
3. 刷新历史

验收：

- A/B 拥有不同 threadID
- transcript refresh 只更新当前 thread

### Case 3. 历史回放不覆盖本地占位消息到错误 thread

步骤：

1. 发起 chat，保留本地 placeholder
2. 拉取 transcript
3. 检查 merge 结果

验收：

- 命中不确定时新增消息，而不是覆盖错误消息
- metadata 中 thread 字段保持不变

### Case 4. 后台续跑可停止

步骤：

1. 发起 chat
2. 首条回复返回后让后台继续跑
3. 点击 Stop

验收：

- 当前 thread 下的活跃 run 被终止
- UI 状态从 stopping 变回 idle
- 不影响其他 thread

### Case 5. 老数据兼容

步骤：

1. 打开不含 `workbenchThreadID` 的老项目
2. 进入 Workbench

验收：

- 旧消息仍可显示
- 不崩溃
- 新发送消息按新 schema 写入

## 11. 风险提示

P0 最大风险不是“实现难”，而是“半改状态”：

- 一部分逻辑按新 thread key
- 一部分逻辑还按旧 workbenchSessionID

这会造成更隐蔽的混线。

因此 P0 最重要的实施纪律是：

**一旦引入 `WorkbenchThreadContext`，所有 Workbench 主链路必须统一从它读写，不允许新旧键混用做核心判断。**

## 12. 完成定义

P0 完成意味着：

- Workbench 已具备 thread 级身份
- 历史回放不会再破坏本地线程
- Stop 已经不是全局单 run 模式
- 后续可以在同一 thread 上继续推进真正的聊天控制器重构

但它不意味着聊天模式已经完成产品目标。

P0 完成后，下一阶段才适合开始做：

- 去 routing JSON
- conversation controller
- delegation/span/artifact 落盘
- chat->run 显式跃迁
