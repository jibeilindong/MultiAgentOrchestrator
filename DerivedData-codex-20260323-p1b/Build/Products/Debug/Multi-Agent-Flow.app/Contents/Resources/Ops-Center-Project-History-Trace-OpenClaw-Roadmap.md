# Ops Center 下一步计划

## 背景

当前 `branch_exploration` 分支上的 Ops Center 已经完成了从基础运维看板到项目级可观测中心的第一阶段升级，具备以下能力：

- 项目级历史指标页
- 按 Project / Agent / Tool / Cron 的历史聚焦视图
- Trace drill-down
- Cron detail / Tool detail
- Anomaly explorer 与 anomaly cluster
- OpenClaw 外部 session / tool / cron 痕迹接入
- `cron_reliability` 真实数据链路
- 基础回归测试护栏

下一阶段目标不是盲目继续堆功能，而是先稳住底座，再把 Ops Center 从“能看”升级为“更容易判断、定位和扩展”。

## 下一步计划

### 1. 拆分并继续扩展测试基建

当前测试已经覆盖了 SQLite 查询、OpenClaw 痕迹接入、异常聚类、历史洞察 helper 等关键链路，但大部分内容仍集中在一个测试文件中。

建议拆分为几类更清晰的测试文件：

- `OpsAnalyticsSQLiteQueryTests`
- `OpsAnalyticsIngestionTests`
- `OpsHistoryInsightBuilderTests`
- `OpsAnomalyInsightBuilderTests`
- `OpsHistoryScopeMatcherTests`

目标价值：

- 提高失败定位速度
- 降低后续新增功能时的回归成本
- 让测试更贴近模块边界，而不是继续堆在一个超大文件中

### 2. 继续抽离 `TaskDashboardView` 中剩余的业务逻辑

虽然已经抽出了多批 helper，但 `TaskDashboardView` 依然承担了较多业务语义拼装。

下一步建议继续抽离以下逻辑：

- trace 列表摘要与展示决策
- anomaly panel 中的文案与分组决策
- history day drill-down 的摘要拼装
- 详情页中的跨来源映射与展示判断

目标价值：

- 降低视图文件复杂度
- 让后续 UI 调整不容易误伤业务逻辑
- 提高可测试性和复用性

### 3. 增加“项目级洞察摘要”

当前历史页已经能展示图表和明细，但还偏“数据面板”，需要再提升一层解释能力。

建议在历史指标页顶部增加自动洞察摘要，例如：

- 最近 7 天最不稳定的 cron
- 错误预算恶化最快的工具
- 异常簇最集中的 agent
- 最近最值得优先排查的 trace 来源

目标价值：

- 从“图表页”升级成“决策页”
- 降低用户阅读多张图表后的认知负担
- 让 Ops Center 更适合作为日常运营入口

### 4. 做更深的跨来源关联

现在已经有了 runtime、cron、tool、OpenClaw 外部 session 等多来源数据，但关联深度还可以继续增强。

建议重点打通以下链路：

- cron run -> session -> tool result -> anomaly
- tool anomaly -> 对应 trace / parent trace / child trace
- agent 在不同来源中的连续行为链
- anomaly cluster 到具体执行链路的跳转

目标价值：

- 缩短问题排查路径
- 把“多个明细面板”变成“单条调查路径”
- 提升 trace drill-down 的真正实战价值

### 5. 为后续告警与自动化巡检预留统一信号层

现阶段先不直接做复杂通知系统，但可以先把稳定、可复用的运维信号抽出来。

建议优先定义：

- 连续失败的 cron
- 持续重复的 anomaly cluster
- 连续上升的 error budget
- 持续偏低的 memory discipline
- 高频失败工具

目标价值：

- 为后续本地提醒、日报、巡检任务、自动化诊断打基础
- 避免未来每种提醒逻辑各自重复实现一套判断规则

## 建议优先级

### P0

- 拆分测试基建
- 继续抽离 `TaskDashboardView` 的剩余业务逻辑

原因：

这是后续持续演进的基础。如果结构和测试不先整理，继续叠加功能的边际收益会下降，维护成本会快速上升。

### P1

- 增加项目级洞察摘要
- 做更深的跨来源关联

原因：

这两项最直接提升 Ops Center 的产品完成度和排查效率，是“用户感知价值”最高的一层升级。

### P2

- 为后续告警与自动化巡检预留统一信号层

原因：

这项更偏平台化建设，价值很高，但适合在前面的可观测与关联能力更稳定后推进。

## 阶段目标

下一阶段完成后，理想状态应当是：

- `TaskDashboardView` 进一步瘦身
- 测试结构更清晰，回归成本更低
- 历史指标页出现第一版自动洞察摘要
- OpenClaw / cron / trace / tool 之间的关联链更完整
- Ops Center 具备继续向告警、巡检、自动诊断扩展的基础

## 一句话总结

下一步不是简单“继续加页面”，而是围绕结构化测试、视图瘦身、自动洞察、跨来源关联和统一信号层，把 Ops Center 从第一阶段的“可观测面板”继续推进为真正可运营、可排障、可自动化扩展的系统级运维中心。
