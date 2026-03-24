# Quick Chat 系统总结与 Chat / Run 升级技术支持文档

最后更新：2026-03-24  
状态：基于当前代码实现的系统性总结，可作为 `chat` / `run` 后续设计、抽象与升级输入

## 文档目的

本文档不再讨论 Quick Chat 是否值得保留，而是把它视为已经进入产品体系的一个轻量对话子系统，系统性总结其当前能力、结构边界、可复用资产与现存缺口，为软件中另外两种对话形态 `chat` 与 `run` 的设计或升级提供技术支持。

本文关注 4 个问题：

- Quick Chat 现在到底已经实现了什么。
- 它和 Workbench 内的 `chat` / `run` 在根本设计上应该如何区分。
- 哪些能力应该抽成共享内核，供 `chat` / `run` 复用。
- 后续如果把这些能力推广到 `chat` / `run`，完成性测试应如何定义。

## 核心结论

当前 Quick Chat 已经不再是“一个简单弹窗”，而是一个具备独立窗口、独立会话、独立上下文解析、独立附件流水线、独立消息渲染和独立发送状态管理的轻量对话子系统。

它的产品定位已经比较清晰：

- Quick Chat 是轻量、直达、低观测、低控制、优先速度的快聊通道。
- `chat` 是 Workbench 内的正式对话模式，应承担持续上下文、线程语义、升级到 `run` 的衔接责任。
- `run` 是 Workbench 内的受控执行模式，应承担更高观测、更强控制、更明确状态机和更低误操作风险。

因此，后续正确方向不是把三者做成同一个壳，而是：

- 保持 Quick Chat 与 `chat` / `run` 的产品壳层明确差异。
- 抽取它们底层真正通用的对话基础设施。
- 让用户自己选择观测与控制档位，而不是把速度、透明度和风险绑死在单一路径里。

## 当前实现现状

### 一、Quick Chat 的产品定位已经落地

当前实现明确把 Quick Chat 放在 Workbench 主链路之外：

- 入口在主界面工具栏，帮助文案明确说明“不进入 Workbench 主控制台”。
- 承载形式为独立 `NSWindow`，不是主界面页签，也不是 Workbench 内嵌面板。
- 会话目标默认解析为当前项目、当前工作流、当前入口 Agent。
- 消息发送直连 Gateway chat，不进入 Workbench 的正式线程编排与控制链路。

对应文件：

- `Multi-Agent-Flow/Sources/Views/ContentView.swift`
- `Multi-Agent-Flow/Sources/Views/QuickChatWindowBridge.swift`

### 二、Quick Chat 已具备独立会话系统

当前会话模型已具备以下特征：

- 会话按 `projectID + workflowID + agentID` 形成上下文隔离。
- 每个上下文下可保留多个会话。
- 每个会话拥有独立 `sessionKey`、消息列表、附件列表、草稿和更新时间。
- 支持新建会话、切换会话、重命名会话、删除会话。
- 切换 Agent 时会自动切换到该 Agent 对应的独立会话集合。

这说明 Quick Chat 已经具备最小可用的“多会话对话系统”特征，而不是一次性临时输入框。

对应文件：

- `Multi-Agent-Flow/Sources/Services/QuickChatStore.swift`
- `Multi-Agent-Flow/Sources/Services/AppState+QuickChat.swift`
- `Multi-Agent-FlowTests/QuickChatContextResolutionTests.swift`

### 三、Quick Chat 已具备独立输入与附件流水线

输入能力已覆盖：

- 多行文本输入。
- 自动高度增长。
- `Enter` 发送。
- `Shift+Enter` 换行。
- 原生复制、剪切、粘贴、撤销等基础编辑行为。
- 文件对话框导入。
- 拖拽文件导入。
- 剪贴板导入文件或图片。

附件流水线已覆盖：

- 导入后进入本地 `stage` 状态。
- 校验文件大小与 MIME。
- 生成图片预览。
- 生成 base64 内容供 Gateway chat 发送。
- 区分 `staging / ready / failed` 状态。
- 失败后可移除重试。

需要明确的是，当前实现是“本地 stage + 随消息发送附件内容”，并不是严格意义上的 Gateway `stage-paths` 远端预上传协议。

对应文件：

- `Multi-Agent-Flow/Sources/Views/QuickChatComponents.swift`
- `Multi-Agent-Flow/Sources/Services/QuickChatStore.swift`

### 四、Quick Chat 已具备结构化消息渲染系统

消息角色已区分：

- `user`
- `assistant`
- `tool_result`
- `system`

消息内容块已区分：

- `text`
- `thinking`
- `image`
- `tool_use`
- `tool_result`

当前渲染系统已支持：

- Markdown 文本分段渲染。
- 代码块识别与高亮。
- 超长代码折叠。
- 图片预览与灯箱。
- 工具调用卡片。
- 思考过程折叠卡片。
- Hover 复制。
- 表格与分段 prose 优化。

需要明确的是，当前桌面端实现并不是 `react-markdown + remark-gfm` 体系，而是 SwiftUI / AppKit 原生渲染方案。这一点对后续 `chat` / `run` 复用非常关键：如果要统一视觉与解析规则，应统一在“消息块协议”层，而不是强行统一到某一种前端库。

对应文件：

- `Multi-Agent-Flow/Sources/Views/QuickChatComponents.swift`

### 五、Quick Chat 已具备轻量发送与停止控制

发送链路当前具有如下特征：

- 使用独立 `sessionKey` 调用 Gateway chat。
- 默认 `thinkingLevel = off`，优先速度。
- 发送时先插入用户消息，再插入流式占位 assistant 消息。
- 流式文本更新直接落到当前 assistant 占位消息。
- 结束后会拉取结构化历史并替换最新响应簇。
- 支持基于 `runID + sessionKey` 发起 stop。

这套链路证明 Quick Chat 已经形成一条“轻控制、低中断成本、面向快聊”的对话执行路径。

对应文件：

- `Multi-Agent-Flow/Sources/Services/QuickChatStore.swift`
- `Multi-Agent-Flow/Sources/Services/OpenClawManager.swift`

## 当前架构分层

### 1. 上下文解析层

职责：

- 从当前项目和工作流中解析可用 Agent。
- 优先选择入口节点连接到的 Agent 作为默认快聊目标。
- 为 Quick Chat 提供 `project / workflow / agent` 三元上下文。

当前结论：

- 这层已经具备被 `chat` / `run` 复用的价值。
- 它实际上是“对话入口上下文解析器”，不应只服务于 Quick Chat。

核心文件：

- `Multi-Agent-Flow/Sources/Services/AppState+QuickChat.swift`

### 2. 会话与状态存储层

职责：

- 管理当前上下文、当前 Agent、当前会话。
- 管理会话列表、消息、附件、草稿、发送状态、错误状态。
- 管理会话切换和会话快照保存。

当前结论：

- 这层已经是一个轻量版 `DialogSessionStore`。
- 其核心模型未来应抽象为共享对话存储基类或协议。

核心文件：

- `Multi-Agent-Flow/Sources/Services/QuickChatStore.swift`

### 3. 窗口承载层

职责：

- 把 Quick Chat 从主界面流程中剥离出来。
- 以独立 `NSWindow` 管理展示、关闭、聚焦和尺寸。

当前结论：

- 这是 Quick Chat 与 `chat` / `run` 必须保持差异的重要产品壳层。
- 不建议把 `chat` / `run` 也简单做成同样窗口；它们应保留 Workbench 内嵌语义。

核心文件：

- `Multi-Agent-Flow/Sources/Views/QuickChatWindowBridge.swift`

### 4. 页面编排层

职责：

- 会话侧栏。
- 顶部上下文与 Gateway 状态。
- 消息区。
- 搜索条。
- Composer 输入区。

当前结论：

- 这层可以拆出通用部件，但页面编排本身不宜直接复用到 `run`。
- `chat` 可继承较多。
- `run` 只应复用其中的消息区、部分 composer 和状态条样式资产。

核心文件：

- `Multi-Agent-Flow/Sources/Views/QuickChatModalView.swift`

### 5. 渲染组件层

职责：

- 消息气泡。
- 附件卡片。
- Markdown / 代码 / 表格 / 图片 / 工具卡片。
- 输入框桥接。

当前结论：

- 这是最值得共享的 UI 能力层。
- `chat` / `run` 后续升级时应尽量复用消息块渲染器，而不是各做一套。

核心文件：

- `Multi-Agent-Flow/Sources/Views/QuickChatComponents.swift`

## Quick Chat 与 Chat / Run 的根本差异

### 一、Quick Chat 不应被误认为 Workbench Chat

Quick Chat 的根本目标是“立即对话”，不是“正式线程管理”。

它的天然特征应当保持：

- 独立窗口。
- 轻量上下文。
- 最小观测。
- 最小控制。
- 快速往返。
- 低切换成本。

### 二、Workbench Chat 不应被误认为 Quick Chat

Workbench `chat` 的根本目标是“正式对话线程”，不是“最快入口”。

它应该天然承担：

- 主线程归档。
- 与工作流、线程、运行态的关联。
- 与 `run` 的可升级衔接。
- 更完整的上下文注入。
- 可被调查、可被追踪、可被复盘。

现有代码中这类语义已经存在基础模型：

- `WorkbenchInteractionMode.chat`
- `WorkbenchThreadSemanticMode.autonomousConversation`
- `WorkbenchConversationState`

对应文件：

- `Multi-Agent-Flow/Sources/Views/MessagesView.swift`
- `Multi-Agent-Flow/Sources/Models/SessionSemantics.swift`

### 三、Run 必须比 Chat 更受控

`run` 的根本目标不是对话，而是“执行”。

因此它必须天然具备：

- 更高观测度。
- 更强控制度。
- 更明确状态机。
- 更清晰的失败和停止语义。
- 与 runtime dispatch、receipt、approval、thread state 的直接关联。

现有代码里，`run` 相关语义和状态也已经有基础模型：

- `WorkbenchInteractionMode.run`
- `WorkbenchThreadSemanticMode.controlledRun`
- `RuntimeState.activeWorkbenchRuns`
- `RuntimeState.workbenchThreadStates`

对应文件：

- `Multi-Agent-Flow/Sources/Views/MessagesView.swift`
- `Multi-Agent-Flow/Sources/Models/MAProject.swift`
- `Multi-Agent-Flow/Sources/Models/SessionSemantics.swift`

## 对 Chat / Run 可直接复用的技术资产

### 1. 对话上下文解析器

Quick Chat 已经证明，对话入口必须先解析清楚：

- 当前项目是谁。
- 当前工作流是谁。
- 当前默认入口 Agent 是谁。
- 用户是否允许切换到其他 Agent。

建议抽象为共享服务：

- `DialogContextResolver`

建议服务输出：

- `DialogContext`
- `DialogAgentOption`
- `defaultEntryAgent`
- `contextScopeKey`

### 2. 会话隔离模型

Quick Chat 当前的 `(projectID, workflowID, agentID)` 上下文隔离非常实用，建议推广到 `chat` / `run`。

但推广时要加入模式维度：

- `mode = quickChat / chat / run`

建议统一键模型：

- `DialogContextKey = projectID + workflowID + agentID + mode`

这样才能保证：

- Quick Chat 的轻量历史不会污染正式 Workbench 线程。
- `chat` 与 `run` 的线程记录可以在共享基础设施上共存，但仍然语义分离。

### 3. 消息块协议

Quick Chat 已经用 `MessageContentBlock` 证明“消息块”比“纯字符串消息”更适合未来扩展。

建议抽象为共享协议：

- `DialogMessage`
- `DialogMessageBlock`
- `DialogAttachment`

最小共享块类型建议：

- `text`
- `thinking`
- `image`
- `tool_use`
- `tool_result`
- `status`
- `approval`
- `runtime_event`

其中前 5 类已经在 Quick Chat 中落地，后 3 类是 `run` 升级时的必要扩展。

### 4. 附件流水线

Quick Chat 已经形成附件导入与 staging 逻辑，这部分不应再在 `chat` / `run` 中重复造轮子。

建议抽象为共享服务：

- `DialogAttachmentPipeline`

它至少应负责：

- 本地导入。
- 去重。
- 大小校验。
- MIME 解析。
- 图片预览。
- 本地缓存。
- Gateway 发送前准备。
- 将来接入真正的 Gateway `stage-paths`。

### 5. 结构化转录归一化

Quick Chat 在发送完成后会拉取 Gateway chat history，并把转录归一化为本地消息块，这已经具备共享价值。

建议抽象为共享服务：

- `DialogTranscriptNormalizer`

它应负责：

- 把 Gateway transcript 转为统一 `DialogMessage`。
- 合并流式占位与最终结构化响应。
- 处理 tool/result/thinking/image。
- 为 `chat` / `run` 提供一致的消息渲染输入。

### 6. 渲染资产层

当前 Quick Chat 已具备一组可复用 UI 资产：

- Message bubble
- Markdown prose renderer
- Code block renderer
- Image lightbox
- Tool disclosure card
- Thinking disclosure card
- Attachment cards
- Hover copy
- Search toolbar

建议抽象为共享渲染层：

- `DialogRenderKit`

其目标不是让三种模式长得一样，而是让三种模式能共享“消息内容表现规则”。

## 建议建立统一对话底座

### 一、统一领域模型

建议在 Quick Chat、`chat`、`run` 之下定义统一领域模型：

- `DialogMode`
- `DialogContext`
- `DialogContextKey`
- `DialogSession`
- `DialogSessionSummary`
- `DialogMessage`
- `DialogMessageBlock`
- `DialogAttachment`
- `DialogSendState`
- `DialogTransportStatus`

建议模式定义如下：

- `quickChat`: 快速、低观测、低控制、独立窗口。
- `chat`: 正式对话、线程化、可升级到 `run`。
- `run`: 受控执行、强状态机、高观测、高控制。

### 二、统一服务边界

建议建立如下共享服务：

- `DialogContextResolver`
- `DialogSessionRepository`
- `DialogAttachmentPipeline`
- `DialogTransportAdapter`
- `DialogTranscriptNormalizer`
- `DialogRenderKit`
- `DialogWindowOrPanelCoordinator`

对应关系建议如下：

- Quick Chat 复用全部共享服务，但使用自己的窗口壳层。
- `chat` 复用全部共享服务，但使用 Workbench 对话壳层。
- `run` 复用上下文、会话、附件、转录、渲染层，但使用独立的执行控制壳层。

### 三、统一“观测 / 控制档位”模型

为避免把速度和安全性写死在某个模式里，建议统一引入“档位”概念，让用户选择。

建议最小档位如下：

| 档位 | 观察行为 | 控制行为 | 适用模式 | 速度影响 | 风险特征 |
| --- | --- | --- | --- | --- | --- |
| L0 迅捷 | 只显示最终消息与必要状态 | 仅发送与停止 | Quick Chat | 最快 | 透明度最低，适合低风险快问快答 |
| L1 平衡 | 显示消息块、工具结果、基础状态 | 发送、停止、切换会话 | Quick Chat / Chat | 较快 | 默认推荐档，兼顾速度与可理解性 |
| L2 透明 | 显示思考、工具调用、搜索、更多上下文状态 | 可选择目标 Agent、可恢复线程、可查看更多历史 | Chat | 中等 | 更透明，但渲染和状态刷新开销更高 |
| L3 受控 | 显示运行态、线程态、审批态、失败诊断、执行队列 | 可审批、可重试、可升级/降级、可停止运行 | Run | 最慢 | 速度最慢，但最适合复杂任务和可审计场景 |

这里的关键不是做四套系统，而是：

- 用一个共享底座。
- 用不同模式壳层。
- 用不同档位控制观测和控制密度。

## 对 Chat 升级的直接建议

### 建议保留的特性

- 保持 Workbench 内嵌，而不是改成浮窗。
- 保持线程化和归档能力。
- 保持与工作流和 thread state 的强关联。

### 建议吸收 Quick Chat 的能力

- 多会话侧栏机制。
- 会话重命名与删除。
- 更稳定的输入框与复制粘贴体验。
- 附件导入、拖拽、剪贴板流水线。
- 结构化消息块渲染。
- 图片灯箱与代码块复制。
- 会话内搜索。

### 不建议直接照搬的特性

- 独立 `NSWindow` 壳层。
- 默认 `thinking = off` 的极简执行策略。
- 仅以“快”为目标的轻量状态表达。

## 对 Run 升级的直接建议

### 建议保留的特性

- 强状态机。
- 强 runtime 关联。
- 强可观测性。
- 强控制能力。

### 建议吸收 Quick Chat 的能力

- 统一消息块渲染器。
- 统一附件流水线。
- 统一会话搜索与复制能力。
- 统一 tool/result 卡片体系。
- 统一图片与代码表现规则。

### 必须比 Quick Chat 额外增加的能力

- 审批与权限可见性。
- 线程状态与运行状态联动。
- 更明确的停止、重试、恢复语义。
- 队列、inflight、completed、failed 的运行态呈现。
- 失败诊断和行动建议。

## 当前明确缺口与设计缺陷

这些问题不会否定 Quick Chat 的价值，但如果要把它作为 `chat` / `run` 升级参考，必须正视。

### 1. 会话当前只在内存中保存

当前 `QuickChatStore` 主要是进程内存态，并未看到完整的磁盘持久化仓储层。

这意味着：

- 应用重启后会话可能无法恢复。
- Quick Chat 暂时还不是完整历史系统。
- 若 `chat` / `run` 要复用其会话模型，必须补上持久化仓储。

### 2. 附件还不是真正的 Gateway `stage-paths`

当前实现是本地 staging 后再随请求发送附件内容。

这意味着：

- “预上传到 Gateway”的能力在产品语义上仍未完全闭环。
- 后续若 `chat` / `run` 要支持更大文件和更稳定断点续传，必须接入真正的远端 staging 协议。

### 3. 还没有统一对话内核

当前 Quick Chat、Workbench `chat`、Workbench `run` 在语义模型上有关联，但在实现层并未形成统一对话底座。

这意味着：

- 同类能力容易在不同模式里重复建设。
- 渲染、会话、附件和转录逻辑难以统一演进。

### 4. Quick Chat 搜索高亮存在未闭环风险

当前 `QuickChatModalView` 已向 `QuickChatMessageBubbleView` 传入 `isSearchMatch` 与 `isFocusedSearchMatch`，但 `QuickChatMessageBubbleView` 现有定义尚未体现这两个输入。

这说明：

- 搜索结果滚动逻辑已开始建设。
- 搜索高亮表现层仍可能未完成闭环。

对应文件：

- `Multi-Agent-Flow/Sources/Views/QuickChatModalView.swift`
- `Multi-Agent-Flow/Sources/Views/QuickChatComponents.swift`

### 5. Quick Chat 与正式 Workbench 线程仍缺乏统一桥接协议

当前 Quick Chat 明确不进入 Workbench 主控制链路，这是正确边界。  
但如果未来用户希望“把这次快聊升级成正式 chat 线程”或“从 chat 提升为 run”，仍需一个明确桥接协议。

建议未来补充：

- `QuickChat -> Chat` 升级动作。
- `Chat -> Run` 升级动作。
- 统一的线程语义迁移规则。

## 完成性测试

以下测试是把 Quick Chat 经验推广到 `chat` / `run` 时必须满足的完成性测试。

### 一、上下文与会话测试

- 在同一项目中切换工作流时，会话上下文必须正确隔离。
- 在同一工作流中切换 Agent 时，会话历史必须正确恢复。
- 新建会话后，旧会话草稿、附件、消息不得丢失。
- 删除当前会话后，系统必须正确回退到下一个有效会话。
- 加入 `mode` 维度后，Quick Chat、`chat`、`run` 的会话不得相互污染。

### 二、输入与附件测试

- `Enter` 发送，`Shift+Enter` 换行必须稳定。
- 复制、剪切、粘贴、撤销、重做必须正常。
- 文件对话框、拖拽、剪贴板导入都必须成功。
- 大文件必须被明确拒绝并给出错误提示。
- 图片附件必须能预览，非图片附件必须能显示类型和大小。
- 附件失败后，移除和重新导入必须稳定。
- 如果接入真正 Gateway staging，断网、取消、重复导入、会话切换都必须可恢复。

### 三、发送与停止测试

- 发送时必须先出现用户消息和 assistant 占位消息。
- 流式输出必须逐步更新，不得卡死在空白态。
- stop 时必须正确处理 runID 尚未返回和 runID 已返回两种情况。
- 发送失败时必须保留错误信息，不得吞错。
- 拉取结构化 transcript 后，消息块必须正确替换占位消息。

### 四、渲染测试

- `text / thinking / image / tool_use / tool_result` 五类块都必须正确渲染。
- Markdown 标题、列表、引用、表格、代码块必须可读。
- 长代码块必须支持折叠与复制。
- 图片必须支持灯箱放大。
- Hover 复制在不同角色消息上都必须工作。
- 搜索命中、焦点命中和滚动定位必须完整闭环。

### 五、模式差异测试

- 用户在打开 Quick Chat 的第一眼就能明确感知它不是 Workbench `chat`。
- 用户在 Workbench `chat` 中第一眼就能明确感知它不是 Quick Chat，也不是 `run`。
- 用户在 `run` 中第一眼就能明确感知它是执行模式，而不是普通聊天。
- 三种模式的视觉、文案、状态、按钮语义必须明确分化，不能靠用户猜。

### 六、观测 / 控制档位测试

- 在 L0 / L1 / L2 / L3 档位间切换时，系统必须能稳定启用或关闭对应观测能力。
- 档位变化必须影响速度和透明度，但不能破坏消息正确性。
- 默认档位必须明确，且用户可理解地知道自己换来了什么、牺牲了什么。

### 七、持久化与恢复测试

- 应用重启后，会话列表和最近会话恢复必须符合产品预期。
- 如果只对 `chat` / `run` 做持久化，而 Quick Chat 不做，也必须在产品层明确告知。
- 若未来 Quick Chat 也持久化，则必须支持会话索引恢复、草稿恢复和附件缓存清理策略。

## 建议的下一步实施顺序

### 第一步：先抽共享内核，不动产品壳层

建议先抽出：

- `DialogContextResolver`
- `DialogMessageBlock`
- `DialogAttachmentPipeline`
- `DialogTranscriptNormalizer`
- `DialogRenderKit`

这样做风险最低，也最能为 `chat` / `run` 提供直接支持。

### 第二步：让 Workbench Chat 吸收 Quick Chat 的输入与渲染能力

优先建议升级：

- 输入框。
- 附件导入。
- 结构化消息渲染。
- 搜索与复制。

这是收益最高、风险相对最低的一步。

### 第三步：让 Run 复用共享渲染与附件底座

优先建议复用：

- 消息块协议。
- 工具调用卡片。
- 代码和图片渲染。
- 会话搜索。

但不要把 `run` 产品壳层做成 Quick Chat 风格。

### 第四步：再建设模式桥接

最后再建设：

- Quick Chat 升级为正式 `chat`
- `chat` 升级为 `run`
- `run` 回看 `chat` 历史

这是高价值但也最容易引入语义混乱的一步，必须排在共享底座稳定之后。

## 结论

Quick Chat 的真正价值，不只是给软件补了一个快聊入口，而是先行实现了一套更现代、更轻、更顺滑的对话子系统原型。

对软件整体来说，最值得复用的不是它的浮窗形态，而是它已经验证过的这些底层能力：

- 上下文解析
- 多会话隔离
- 附件流水线
- 结构化消息块
- 统一渲染资产
- 轻量发送与停止链路

对 `chat` / `run` 的后续设计来说，正确方向不是“把 Quick Chat 复制过去”，而是：

- 保留三种模式的根本差异。
- 共享真正通用的对话底座。
- 用观测 / 控制档位把速度、透明度和风险选择权交还给用户。

