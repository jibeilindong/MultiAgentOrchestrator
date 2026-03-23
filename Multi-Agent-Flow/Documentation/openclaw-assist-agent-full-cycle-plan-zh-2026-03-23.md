# OpenClaw 内置 Assist 全责 Agent 全周期执行计划

日期：2026-03-23
状态：Draft for review

## 1. 文档目的

本文档将《OpenClaw 内置 Assist 全责 Agent 方案》拆成完整可执行的开发计划，覆盖产品收口、模型设计、服务改造、界面接入、测试验收与灰度发布。

本文档关注的是“怎么落地”，不重复展开完整产品设计结论。

Assist Store 的数据结构细化见：

- [openclaw-assist-store-design-zh-2026-03-23.md](/Users/chenrongze/Desktop/MultiAgentOrchestrator/MultiAgentOrchestrator/Multi-Agent-Flow/Documentation/openclaw-assist-store-design-zh-2026-03-23.md)

## 2. 执行目标

本次执行的目标不是简单增加一个按钮，而是完成 7 个方向的整体落地：

1. 建立统一的 Assist 产品入口
2. 建立 Assist 的低损耗系统调用路径
3. 建立 Assist 的上下文、proposal、receipt、undo、grant 数据结构
4. 将 Assist 安全接入现有设计态编辑系统
5. 优先落地模板 / 文案 / 配置检查等高价值场景
6. 再逐步扩展到 workflow 节点调用、布局优化与性能诊断
7. 让 Assist 的全过程可观测、可回退、可验收

## 3. 总体执行策略

建议采用以下顺序推进：

1. 先收口产品语义与数据对象
2. 先打通低损耗系统通道
3. 再搭建统一 Assist 基座
4. 再接入文本与模板场景
5. 再接入 workflow 适配通道、布局和诊断场景
6. 最后补齐可观测性、回退、测试与灰度发布

原因：

- 如果先切 UI，没有稳定的 proposal / receipt / scope 模型，后续很容易返工。
- 如果没有独立的低损耗系统通道，Assist 很容易退化成普通源 agent 套壳。
- 如果先做复杂场景，如布局或性能诊断，产品体验和验收标准会先失控。
- 模板和文案场景最贴近当前已有能力，适合作为第一批真实落地入口。

本计划执行期间必须持续遵守一个额外约束：

- Assist 必须始终被实现为“戴着手套、受限权限、每一步可回退的手”，而不是默认直接替用户操作软件的自动执行器。

## 4. 全周期阶段拆分

全周期建议拆成 8 个阶段。

### Phase 0：方案冻结与术语收口

目标：

- 冻结 Assist 的产品定位、边界、原则和命名
- 明确 Assist 与 Chat / Run / Apply 的关系

交付物：

- 方案评审结论
- 统一术语表
- 作用域清单
- V1 范围清单

关键问题：

- 是否统一使用 `Assist`
- V1 是否只做一个全责 agent 入口
- 是否将 Assist 明确放入模板体系但设为系统模板
- 是否同时建立“系统通道”和“workflow 适配通道”
- 是否明确建立系统级 Assist Store，并禁止默认写入项目数据
- 哪些场景必须进入 V1，哪些延后

验收标准：

- 设计文档完成评审
- 不再对“单独聊天窗口 / 多专职 agent 对外暴露 / 直接自动改 runtime”反复摇摆

### Phase 1：Assist 领域模型与状态机

目标：

- 建立 Assist 的一等对象与状态机
- 让 Assist 与普通聊天、运行态执行彻底区分

交付物：

- `AssistRequest`
- `AssistContextPack`
- `AssistProposal`
- `AssistExecutionReceipt`
- `AssistCapabilityGrant`
- `AssistUndoCheckpoint`
- `AssistMutationGateway`
- `AssistStore`
- `AssistState`

建议修改范围：

- `Multi-Agent-Flow/Sources/Models/`
- `Multi-Agent-Flow/Sources/Services/AppState.swift`
- `Multi-Agent-Flow/Sources/Models/SessionSemantics.swift`
- `packages/domain/src/`

关键任务：

- 定义 Assist 请求类型与作用域类型
- 定义 proposal 结构与 change item 结构
- 定义写入回执与撤销快照
- 定义 capability grant 与 mutation gateway contract
- 定义 Assist Store 与系统级索引模型
- 明确 `conversation.assisted` 与 `inspection.readonly` 的使用边界
- 明确 workflow 中的 Assist 节点如何发起 scoped mutation request

验收标准：

- Assist 可以独立表示“生成建议”和“应用建议”
- `applied` 不会被误解为 `saved` 或 `applied_to_runtime`
- 诊断型请求默认只读
- 系统级写入具备独立的 gateway 契约，不依赖普通聊天输出反推
- request / proposal / receipt / undo 默认落在系统层，而不是项目数据

### Phase 2：统一 Assist 编排基座

目标：

- 形成一个统一的 Assist 入口和编排服务
- 保持对外一个全责 agent，内部以模块化方式组织能力

交付物：

- `AssistOrchestrator`
- `AssistContextResolver`
- `AssistProposalBuilder`
- `AssistApplyService`
- `AssistUndoService`
- `AssistWorkflowAdapter`
- `AssistStoreIndex`

建议修改范围：

- `Multi-Agent-Flow/Sources/Services/`
- `Multi-Agent-Flow/Sources/Views/MessagesView.swift`
- `Multi-Agent-Flow/Sources/Views/ContentView.swift`

关键任务：

- 从当前页面解析上下文
- 按请求类型选择处理模块
- 生成统一 proposal
- 统一提交到 mutation gateway，再写入 draft / managed workspace / mirror
- 记录 receipt 与 undo checkpoint
- 强制保留关键动作的确认与回退链路
- 明确 workflow 节点调用与系统调用的分流逻辑
- 将所有 Assist 运行记录统一写入系统级 Assist Store

验收标准：

- 产品表面只有一个 Assist 入口
- 文本类、模板类、诊断类请求都能走同一条 Assist 管线
- 不需要为每种功能单独造一个新的交互框架
- 不会出现“生成建议后未经确认直接改动关键对象”的默认行为
- 系统通道与 workflow 适配通道都能挂接到同一 proposal / receipt 模型
- 项目保存与导出不包含完整 Assist 历史

### Phase 3：Workbench Assist 模式与结果面板

目标：

- 在现有 Workbench 中增加 `Assist`
- 建立聊天区与结构化结果区的协作关系

交付物：

- Workbench `Chat / Assist / Run` 三态切换
- Assist 对话输入区
- Assist 结果面板
- Proposal 确认与应用按钮

建议修改范围：

- `Multi-Agent-Flow/Sources/Views/MessagesView.swift`
- `Multi-Agent-Flow/Sources/Services/LocalizationManager.swift`
- 相关 Workbench 状态与消息写入逻辑

关键任务：

- 新增 `Assist` 模式
- 区分 Assist 线程与普通聊天线程
- 在结果面板中展示 `diff / preview / warnings`
- 支持“继续追问”和“应用到草稿”
- 明确区分“建议已生成”和“改动已写入”
- 禁止普通聊天 agent 通道直接触发系统级写入

验收标准：

- 用户可以在 Workbench 内完整发起一次 Assist 请求
- 用户能看懂当前结果是建议还是已应用
- Assist 交互不会污染 Run 模式执行语义

### Phase 4：编辑器就近入口接入

目标：

- 让高频场景在当前界面直接触发 Assist

交付物：

- 模板工作区就近 Assist 入口
- 受管配置编辑器就近 Assist 入口
- 节点属性面板就近 Assist 入口
- Workflow Editor 工具栏 Assist 入口

建议修改范围：

- `Multi-Agent-Flow/Sources/Views/TemplateWorkspaceView.swift`
- `Multi-Agent-Flow/Sources/Views/ManagedConfigEditorPane.swift`
- `Multi-Agent-Flow/Sources/Views/PropertiesPanelView.swift`
- `Multi-Agent-Flow/Sources/Views/WorkflowEditorView.swift`

关键任务：

- 根据入口自动推断最小作用域
- 将当前选中文本 / 当前文件 / 当前节点打包为上下文
- 支持“从当前页面发起后，在结果面板确认”
- 避免就近入口绕过确认与回退机制
- 为 Assist 系统模板预留只读展示与权限控制位

验收标准：

- 常见高频任务不需要先进入独立页面
- 就近入口不会绕开统一的 proposal / receipt 流程
- 不会直接落写 runtime
- 就近入口只消费 Assist 结果，不把 Assist 历史写回项目

### Phase 5：V1 能力落地

目标：

- 优先交付最稳、最常用、最容易建立用户信任的能力

V1 建议只包含：

- 当前选中文本改写
- 当前文件章节补全
- SOUL / 模板结构补全
- 当前节点职责描述优化
- 当前配置缺失项检查

建议修改范围：

- 模板与受管文档服务
- Assist proposal builder
- Localization 与提示文案

关键任务：

- 统一文本改写结果结构
- 统一章节补全结果结构
- 统一检查报告结构
- 将结果安全写回当前 draft

验收标准：

- 文本类结果可稳定生成 diff
- 文件类结果可稳定生成预览
- 检查类结果默认只读
- 用户可以应用并撤销一次典型改动

### Phase 6：V2 扩展到布局与结构优化

目标：

- 将 Assist 扩展到 workflow 布局与结构整理

交付物：

- 布局预览 proposal
- 分组与边界建议 proposal
- 节点命名与职责重整建议

建议修改范围：

- `Multi-Agent-Flow/Sources/Views/WorkflowEditorView.swift`
- 画布布局与节点数据服务
- 相关 preview 数据模型

关键任务：

- 定义布局类 proposal 数据结构
- 支持“仅预览，不立即写入”
- 支持用户接受某个布局方案后回写 workflow draft

验收标准：

- 布局调整先有预览
- 用户确认后才写入 workflow 结构
- 布局 proposal 与普通文本 proposal 使用同一 Assist 管线

### Phase 6.5：Workflow 节点调用落地

目标：

- 让 Assist 可以作为普通 workflow 节点被调用，同时不丢失系统级权限边界

交付物：

- Assist workflow node adapter
- scoped mutation request
- workflow-to-gateway handoff

关键任务：

- 允许 workflow 中插入 Assist 节点
- 允许 Assist 节点输出建议与诊断工件
- 需要系统级写入时，转交 mutation gateway 做二次确认

验收标准：

- Assist 节点可被 workflow 调用
- 普通 workflow 调用不会天然获得系统级写入权限
- 系统级改动仍可追踪到 grant / receipt / undo

### Phase 7：V3 扩展到性能与效率诊断

目标：

- 将 Assist 扩展到解释型和诊断型场景

交付物：

- 只读性能诊断报告
- 效率优化建议报告
- 与 benchmark / trace / runtime state 的上下文接入

建议修改范围：

- `Multi-Agent-Flow/Sources/Services/OpenClawService.swift`
- `Multi-Agent-Flow/Sources/Services/AppState.swift`
- `Multi-Agent-Flow/Sources/OpsCenter/`
- 相关 benchmark / diagnostics 读取逻辑

关键任务：

- 将运行指标整理为 Assist 上下文快照
- 定义性能诊断类 proposal
- 明确只读与修复建议之间的边界

验收标准：

- 诊断请求默认不产生写入
- 能解释当前问题、可能原因、建议动作
- 与真实 runtime 数据绑定，而不是生成泛泛建议

### Phase 8：可观测性、回退、测试、灰度发布

目标：

- 完成上线前的工程收口

交付物：

- Assist 事件日志
- proposal / receipt / undo 持久化方案
- 单元测试、集成测试、回归用例
- 灰度启用与 fallback 方案
- 系统级数据清理与保留策略

建议修改范围：

- `Multi-Agent-Flow/Sources/Services/ProjectFileSystem.swift`
- `Multi-Agent-Flow/Sources/OpsCenter/`
- 测试 target
- 桌面壳相关开关与配置

关键任务：

- 记录每次 Assist 请求、应用、撤销
- 设计历史恢复与异常恢复
- 增加 feature flag
- 定义禁用 Assist 时的系统退化行为
- 增加系统级数据索引、清理、压缩与导出策略

验收标准：

- Assist 可以被单独开关控制
- 关键链路有测试覆盖
- 线上问题能追溯到 request / proposal / receipt

## 5. V1 / V2 / V3 范围建议

### 5.1 V1

目标：

- 先建立信任，优先交付高频、低风险、强感知价值

包含：

- Workbench Assist 模式
- 就近入口
- 文本改写
- 模板 / SOUL 补全
- 配置检查
- proposal / receipt / undo

不包含：

- 自动布局写回
- 跨 workflow 批量重构
- 运行时自动修复
- 性能优化自动执行

### 5.2 V2

目标：

- 扩展到结构型场景

包含：

- workflow 布局预览
- 节点分组建议
- 命名与职责收口建议

### 5.3 V3

目标：

- 扩展到诊断型场景

包含：

- 性能诊断
- 效率优化建议
- benchmark / trace 解释

## 6. 推荐实现顺序

建议按以下顺序推进：

1. 冻结术语与 V1 范围
2. 定义 Assist 模型与状态机
3. 落 Assist 编排基座
4. 接 Workbench Assist 模式
5. 接模板与文案能力
6. 接编辑器就近入口
7. 补 receipt / undo / 持久化
8. 做 V1 测试与灰度
9. 再进入布局能力
10. 最后进入性能诊断能力

## 7. 关键依赖

Assist 的实施依赖以下已有能力保持稳定：

- Draft / Save / Apply 语义
- node-local managed workspace
- Workbench thread / session semantic
- OpenClaw attachment / sync / run 分层
- 现有模板与受管文件系统读写能力

如果这些基础链路仍在大幅摇摆，Assist 实施会反复返工。

## 8. 主要风险

### R1. 作用域失控

表现：

- 用户以为只改当前段落，实际改了整份文件

应对：

- 强制显示 scope
- 默认使用最小作用域
- 提交前展示影响对象

### R2. 提案与执行混淆

表现：

- 用户分不清“建议生成了”还是“已经写入了”

应对：

- proposal 和 receipt 分开展示
- 明确状态文案

### R3. 结果面板沦为普通聊天

表现：

- 只有自然语言，没有结构化 diff 和预览

应对：

- 先定义 proposal schema，再接 UI

### R4. 直接侵入 runtime

表现：

- Assist 越过设计态直接影响 live runtime

应对：

- 服务层写入必须只落 draft / mirror
- 禁止 Assist 直接触发 Apply

### R5. Assist 退化成普通源 agent 套壳

表现：

- 仍然依赖 prompt 拼装上下文
- 仍然依赖自然语言回推结构化改动
- 低损耗优势无法体现

应对：

- 先建设 context resolver 与 mutation gateway
- 将系统通道明确设计为 typed path
- 将 workflow 适配通道与系统通道分离

### R6. Assist 数据被错误写入项目数据

表现：

- `.maoproj` 或项目托管目录混入大量 request / proposal / receipt / undo
- 项目导入导出携带大量无关 Assist 历史
- Assist 无法形成跨项目统一视图

应对：

- 默认建立系统级 Assist Store
- 项目仅保留最终结果，不保留 Assist 运行全过程
- 使用项目引用索引，而不是项目内存储

### R7. 默认自动执行带来的信任失控

表现：

- 用户以为在看建议，系统却已经替用户改了内容或结构
- 用户无法区分“Assist 帮我操作”与“Assist 已替我做决定”

应对：

- 所有高风险动作默认需要确认
- 结果面板必须先展示 proposal，再允许写入
- 每次写入都生成 receipt 和 undo checkpoint

### R8. 信任感建立失败

表现：

- 初版能力不稳，用户不敢继续用

应对：

- V1 只做最稳场景
- 所有写入都可撤销

## 9. 测试策略

### 9.1 单元测试

覆盖：

- scope 解析
- context pack 构造
- proposal 生成
- proposal 应用
- undo checkpoint 恢复

### 9.2 集成测试

覆盖：

- Workbench Assist 完整链路
- 模板编辑中发起 Assist
- 配置编辑中发起 Assist
- proposal 应用后 Save / Apply 状态变化

### 9.3 回归测试

重点关注：

- Assist 不破坏现有 Chat / Run
- Assist 不绕开 Draft / Save / Apply
- Assist 不破坏 node-local managed workspace
- Assist 不在默认路径下越过确认直接执行关键操作
- Assist 的系统通道明显优于普通源 agent 路径，而不是只是另一层聊天壳
- Assist 的运行历史默认不进入项目导出物

### 9.4 手工验收场景

至少包含：

1. 改写一段 SOUL 文本
2. 补全模板缺失章节
3. 检查当前节点配置并生成只读报告
4. 应用一次建议并成功撤销
5. 在不 Apply 的情况下退出并重新打开项目，确认 Draft 状态可解释

## 10. 发布与灰度建议

建议采用渐进式发布：

### Stage 1

- 仅内部 feature flag 开启
- 只开放 V1 文本 / 模板能力

### Stage 2

- 向有限用户开放
- 收集 proposal 命中率、应用率、撤销率

### Stage 3

- 开启布局类能力
- 继续观察误改与撤销比例

### Stage 4

- 开启性能诊断类能力

## 11. 成功指标建议

建议至少跟踪以下指标：

- Assist 请求发起率
- proposal 生成成功率
- proposal 应用率
- proposal 撤销率
- 文本类任务平均完成耗时
- 模板补全任务平均完成耗时
- 就近入口使用占比
- 因 Assist 导致的误改反馈数

其中：

- 应用率过低，说明 proposal 质量不足
- 撤销率过高，说明作用域或预览设计不足

## 12. 阶段性里程碑建议

### Milestone A：模型与基座完成

完成标志：

- Assist 对象模型稳定
- Workbench 可进入 Assist 模式
- proposal / receipt / undo 主链路可跑通

### Milestone B：V1 可用

完成标志：

- 文本改写、模板补全、配置检查稳定可用
- 编辑器就近入口完成接入
- Draft 写入与撤销可用

### Milestone C：V2 可用

完成标志：

- workflow 布局预览与确认写入可用

### Milestone D：V3 可用

完成标志：

- 诊断型 Assist 可读取真实运行数据并输出只读报告

## 13. 结论

Assist 的落地不应被理解为一次孤立功能开发，而应被视为对现有设计态系统的一次受控升级。

最合理的推进方式是：

- 先稳住语义和模型
- 再搭统一基座
- 先做高价值低风险场景
- 最后扩展到布局和诊断

只要始终坚持“统一入口、设计态优先、先预览后提交、全过程可回退”这几条原则，Assist 就能逐步成为 Multi-Agent-Flow 中稳定、可信、可扩展的内置能力。
