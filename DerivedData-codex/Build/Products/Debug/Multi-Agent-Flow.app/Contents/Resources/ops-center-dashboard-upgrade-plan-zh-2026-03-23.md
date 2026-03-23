# Ops Center 仪表盘升级迭代方案

最后更新：2026-03-23
状态：Proposed

## 目标

基于当前 Multi-Agent-Flow 已有的 `OpsCenter`、`OpsAnalyticsService`、`ProjectFileSystem`、runtime session 落盘与 projection 体系，输出一版面向运行掌控、调试效率和用户体验的仪表盘升级方案。

这版升级的核心不是“再多做几张统计卡片”，而是把仪表盘从“能看到一些运行摘要”升级成“能快速定位问题、直接查看证据、按关键对象做管理”的运行控制台。

本次方案聚焦三个一等对象：

1. `Agent`
   谁表现好，谁表现差，谁需要帮助，谁在烧钱。
2. `Connection`
   是否稳定、速度如何、准确与否、出错概率、错误索引。
3. `Files / Memory`
   多少文件、大小如何、权限如何、来自谁、生成频率、是否需要压缩、趋势如何。

## 基于现状的判断

当前系统并不缺数据，缺的是正确的信息组织方式和调查路径。

已经具备的基础：

- `OpsCenterDashboardView` 已经有 `threads / signals / liveRun / sessions / workflowMap / history` 六个一级页。
- `OpsCenterSnapshotBuilder` 已经能构建 `session / node / route / thread investigation`。
- `ProjectFileSystem` 已经会写入 `analytics/projections/*.json`、`indexes/*.json`、`execution/results.ndjson`、`execution/logs.ndjson`、`runtime/sessions/*`。
- `OpsAnalyticsService` 已经具备 agent health、goal card、trace summary、cron/tool/anomaly 的基础能力。
- OpenClaw 连接层已经有结构化 `connectionState`、capability snapshot、probe report。
- 项目级别已经有 `workspaceIndex` 和 `memoryData`，文件和记忆并不是完全没有数据基础。

当前主要问题：

### 1. 仪表盘默认对象不对

现在的一级导航更偏：

- thread
- signal
- session
- workflow map
- history

但用户真正想管理的是：

- agent
- connection
- file / memory

这导致系统虽然“有页面”，但不是按用户脑内对象组织。

### 2. 日志存在，但不在主调查路径里

当前实时日志主要存在于：

- `ExecutionView`
- `TaskDashboardView`
- `RealtimeInfoPanel`

而新的 `OpsCenter` 里更多是 digest、summary、top 10 investigation list。结果是：

- 想直接看日志时，要切到别的区域。
- session / thread / node 调查和原始日志证据没有统一。
- 仪表盘更像“摘要系统”，不是“调试系统”。

### 3. Agent 视角太浅

目前 agent 维度更多只有：

- completed count
- failed count
- average duration
- last activity
- has tracked memory

这不足以回答：

- 哪个 agent 返工最多
- 哪个 agent 最贵
- 哪个 agent 质量差但速度快
- 哪个 agent 经常拖垮下游
- 哪个 agent 需要帮助或替换

### 4. Connection 体系有模型，但没有变成一等看板

连接层已经有能力型状态和 probe 结果，但仪表盘里还没有形成专门的连接中心，导致用户看不到：

- CLI / gateway / chat / agent 通道谁在掉线
- probe 延迟趋势
- transport fallback 频率
- requested transport 与 actual transport 是否一致
- 哪类错误集中发生在什么连接层级

### 5. Files / Memory 几乎还没进入运行地图

虽然系统已经有：

- workspace index
- task workspace
- memory backup
- runtime artifacts

但现在在 `Workflow Map` 中，`files` layer 仍基本是占位语义，不能回答：

- 哪些文件增长最快
- 谁生成的
- 权限是否异常
- 哪些 memory 已过时
- 哪些应该压缩或归档
- 哪个 workflow 节点正在制造文件压力

### 6. 证据展示仍偏 modal、偏摘要

当前 investigation 主要通过 sheet 打开，适合“查看”，不适合“持续调试”。这会带来三个体验问题：

- 页面切换成本高
- 多对象横向对比困难
- 原始证据和地图、列表无法并排工作

## 这次升级的产品目标

升级后的仪表盘应优先做到：

1. 打开后 5 秒内知道当前最需要处理什么。
2. 任意异常最多 2 次点击进入原始日志或原始证据。
3. `Agent / Connection / Files-Memory` 成为一等对象，而不是散落在 session 和 summary 中。
4. 地图、列表、日志、证据可以联动，而不是分裂在不同页面。
5. 默认体验偏“调试”和“掌控”，历史分析退到辅助层。

## 新的信息架构

建议将当前 `OpsCenter` 升级为 7 个一级页，并把当前 `Threads` 与 `Signals` 吸收重构，而不是继续作为长期主导航。

### 1. `War Room`

默认首页，回答：

- 现在正在发生什么
- 哪三个问题最值得先看
- 哪些 agent / connection / asset 正在冒烟

### 2. `Agents`

围绕 agent 做表现、质量、效率、成本和协作压力的集中管理。

### 3. `Connections`

围绕连接与 transport 做稳定性、速度、准确性、退化、错误索引的集中管理。

### 4. `Assets`

围绕文件、workspace、memory、artifact 做体量、权限、来源、频率、压缩和趋势管理。

### 5. `Workflow Map`

保留并升级当前工作流地图，将 agent、connection、asset 三种视角叠加到结构图上。

### 6. `Sessions & Logs`

把当前 `sessions`、`threads` 和日志主路径合并，强化 session 调查、原始日志、事件流、artifact 证据。

### 7. `History`

保留长期趋势、异常、工具/cron、治理分析，但降为辅助层。

说明：

- 如果希望控制导航复杂度，可以先不单独新增 `History` 页，而是把 `History` 保留为 `Agents / Connections / Assets` 的趋势模式。
- 但 `Sessions & Logs` 必须升级为主路径，不能继续把日志留在外围面板。

## 核心交互模型

### 一、从“卡片跳页面”改成“三栏联动”

建议统一为三栏或上下联动结构：

- 左侧：范围与筛选
- 中间：主列表 / 地图 / 排行
- 右侧：调查抽屉
- 底部：常驻日志控制台

核心原则：

- 右侧调查抽屉替代当前大量 modal sheet。
- 底部日志控制台全局常驻，可折叠、可固定、可筛选。
- 切换对象时，日志、证据、地图联动更新。

### 二、把日志提升为全局一级交互能力

新增全局 `Log Console`，而不是只在 ExecutionView 出现。

日志控制台至少提供三种模式：

1. `Tail`
   实时滚动日志。
2. `Structured`
   按 session / node / agent / connection / file / error code 结构化过滤。
3. `Evidence`
   展示 refs、artifact、runtime event、dispatch、receipt 的关联证据。

必须支持：

- 跟随最新
- 暂停滚动
- 搜索
- 多维过滤
- 复制 sessionID / nodeID / agentID
- 一键固定到当前调查对象

### 三、所有红色状态必须能直达原因

任何红色或黄色状态卡片都要带：

- 为什么红
- 最近一次发生时间
- 影响对象
- 一键跳日志
- 一键跳调查

不允许再出现“显示失败数量，但没有证据入口”的卡片。

### 四、明确区分数据来源

当前系统已有 live memory、projection、archive 三层。升级后必须在 UI 上明确标注：

- `Live`
- `Projection`
- `Archive`

避免用户误判“现在系统真的在运行”还是“我看到的是一份旧投影”。

## 三个一等对象的设计

## Agent Center

### 核心问题

这个页面要回答：

- 谁最稳
- 谁最慢
- 谁最贵
- 谁经常返工
- 谁最容易把问题传给下游
- 谁长期没活跃
- 谁需要补 memory / skill / routing 支持

### 建议指标

基础指标：

- run count
- completed rate
- failed rate
- average duration
- p95 duration
- last active at

质量指标：

- rework rate
- downstream failure contribution
- approval rejection rate
- safe degrade / repair 触发率

效率指标：

- token burn
- estimated cost
- cost per successful run
- first response latency
- completion latency

协作指标：

- handoff count
- blocked downstream count
- help-needed count
- waiting approval caused count

上下文指标：

- memory coverage
- memory freshness
- workspace output count
- recent artifact volume

### 建议视图

1. `Agent Leaderboard`
   默认按 attention score 排序。
2. `Performance Matrix`
   横轴质量，纵轴速度，气泡大小表示成本。
3. `Agent Detail`
   右侧抽屉查看 timeline、最近 session、最近日志、文件输出、memory 使用、下游影响。
4. `Compare Mode`
   支持选择 2 到 4 个 agent 横向比较。

### 建议评分

新增 `agent_attention_score`，用于首页和排序：

- failure pressure
- rework pressure
- cost pressure
- inactivity risk
- downstream impact

这个分数不是为了代替明细，而是为了帮助用户快速排序。

## Connection Center

### 核心问题

这个页面要回答：

- 当前连接总体是 ready、degraded 还是 blocked
- gateway、cli、chat、agent 哪条链路最不稳定
- 哪条链路慢
- transport fallback 是否在变多
- 路由请求和实际执行是否一致
- 错误集中在哪一层

### 建议对象模型

建议把连接对象标准化为：

- deployment
- probe layer
- transport channel
- execution lane

至少覆盖：

- local / container / remoteServer
- CLI
- gateway
- gateway_agent
- gateway_chat
- runtime_channel

### 建议指标

稳定性：

- success rate
- disconnect count
- reconnect count
- retry count
- fallback rate
- health phase dwell time

速度：

- probe latency
- handshake latency
- first response latency
- completion latency

准确性：

- requested vs actual transport match rate
- route target hit rate
- protocol conformance rate
- repair rate
- safe degrade rate

错误：

- error rate
- top error code
- affected session count
- last failure time

### 建议视图

1. `Connection Board`
   每条链路一张卡，展示 phase、能力、最近错误、延迟。
2. `Capability Matrix`
   显示 CLI / gateway / auth / listing / session history / attachment / agent / chat 能力。
3. `Error Index`
   按错误码、错误文案、影响对象聚合。
4. `Fallback Timeline`
   观察从 gateway 到 CLI 的退化频率是否异常。

### 特别建议

把当前连接层已有的 capability state 和 probe report 直接接入 Ops Center，不再只在设置或状态栏中隐含存在。

## Assets Center

### 核心问题

这个页面要回答：

- 文件和记忆在长成什么样
- 哪些节点在制造存储压力
- 哪些 memory 过大、过旧、过碎
- 谁在生成这些文件
- 权限是否健康
- 哪些内容值得压缩、归档或清理

### 建议对象范围

资产对象至少包括：

- task workspace
- agent workspace
- runtime session artifacts
- state files
- execution outputs
- memory workspace
- memory backup
- derived indexes

### 建议指标

体量：

- file count
- directory count
- total size
- average file size
- growth rate

来源：

- source agent
- source node
- source workflow
- source session
- created by transport / service

频率：

- files per hour / day
- update frequency
- hottest directories

治理：

- permission risk
- duplicated files
- stale memory
- archive candidate count
- compression candidate size

趋势：

- 7d / 30d growth
- top growing agent
- top growing workflow
- storage churn

### 建议视图

1. `Asset Overview`
   文件数、体积、增长率、压缩候选。
2. `Ownership View`
   按 agent / workflow / session 看资产来源。
3. `Hot Directories`
   哪些目录增长最快。
4. `Memory Health`
   freshness、size、duplication、backup coverage。
5. `Permission View`
   识别 public、shared、backup-only、unknown 的风险。

### Workflow Map 的资产叠加

当前 `files` layer 需要从占位符升级为真实图层：

- 节点文件产出量
- 节点 memory 体积
- 节点最近增长
- 节点权限风险
- 节点压缩建议

## War Room 首页设计

首页不再展示均匀铺开的统计卡，而是做成“总控台”。

建议布局：

### 顶部状态条

- 当前 workflow / project
- 连接总状态
- live / projection freshness
- active session
- approval pressure
- total spend today

### 左列：要立刻处理的 3 件事

- 最危险的 agent
- 最不稳定的 connection
- 最大的 asset hotspot

### 中列：运行主画面

- 当前 active workflow timeline
- 热 session
- 热 node
- 关键路径状态

### 右列：调查入口

- latest failure
- latest fallback
- latest file burst
- latest approval queue

### 底部：常驻日志

- 默认只显示当前 workflow 范围
- 可一键切到全局
- 可一键 pin 到选中的 session / agent / connection / asset

## Sessions & Logs 页设计

这是本次升级里最关键的体验修复。

### 目标

让用户在一个页面内同时完成：

- 找 session
- 看事件
- 看 dispatch / receipt
- 看原始日志
- 看 refs / artifacts
- 看关联 thread、node、agent、file

### 页面结构

上方：

- session 列表
- 热点排序
- 失败、卡住、等待审批过滤

中间：

- session timeline
- dispatch / receipt / event 混合时间轴

右侧：

- session investigation drawer

底部：

- raw log console

### 建议增强

1. 时间轴支持混合显示：
   dispatch、receipt、runtime event、message、task、file output。
2. 支持从 timeline 直接跳 raw log。
3. refs 如果指向文件，应直接展示路径、大小、类型、来源和打开动作。
4. 如果 session 发生 fallback、repair、safe degrade，要在时间轴上显式打点。

## Workflow Map 升级方向

当前地图基础很好，建议继续保留，并重点增强图层。

### 建议图层

1. `State`
   当前状态。
2. `Latency`
   平均耗时与 p95。
3. `Failures`
   失败热度。
4. `Routing`
   路由与边活跃度。
5. `Approvals`
   审批压力。
6. `Agents`
   节点绑定 agent 的综合健康度。
7. `Connections`
   节点运行主要依赖的 transport / channel 健康度。
8. `Assets`
   文件体积、增长、memory 压力、权限风险。
9. `Cost`
   节点累计 token 与成本热度。

### 交互要求

- 点 node：右侧显示 agent + session + logs + files + memory。
- 点 edge：右侧显示 route pressure、fallback、error index、shared sessions。
- hover：预览最近一次运行摘要。
- layer 切换时，颜色和图例必须明显变化。

## 数据模型升级建议

## 1. `ExecutionLogEntry` 升级为可关联日志

当前日志结构过轻，不足以支撑 dashboard 主路径。

建议新增 `ExecutionLogEntryV2` 字段：

- `sessionID`
- `threadID`
- `workflowID`
- `nodeID`
- `agentID`
- `edgeID`
- `connectionID`
- `transportKind`
- `deploymentKind`
- `eventType`
- `errorCode`
- `errorGroup`
- `tokenInput`
- `tokenOutput`
- `estimatedCost`
- `artifactRefs`
- `traceID`
- `spanID`
- `tags`
- `sourceLayer`
- `message`
- `rawPayload`

原则：

- 兼容旧日志写法
- 新日志优先结构化
- 原始 message 保留

## 2. 新增三类 projection

在现有 `overview / traces / anomalies / live-run / sessions / nodes-runtime / threads / cron / tools / workflow-health` 基础上，新增：

- `agent-health.json`
- `connections.json`
- `assets.json`
- `cost-burn.json`
- `log-head.json`

推荐内容：

### `agent-health.json`

- success / fail / rework / cost / avg latency / p95 / downstream impact / memory coverage

### `connections.json`

- phase / capability / probe latency / retry / fallback / mismatch / error buckets

### `assets.json`

- file count / size / delta / source / permission / compression score / memory freshness

### `log-head.json`

- 最近 N 条结构化日志头索引，用于冷启动快速展示

## 3. 新增 SQLite 表

建议在 `analytics.sqlite` 中增加：

- `agent_daily_metrics`
- `connection_daily_metrics`
- `asset_daily_metrics`
- `cost_usage`
- `error_catalog`
- `session_log_index`

## 4. 扩展 indexes

建议在 `indexes` 目录增加：

- `agents.json`
- `connections.json`
- `assets.json`

## 5. 扩展 session artifacts 索引

建议补齐：

- `runtime/sessions/<session-id>/artifacts/index.json`

每条 artifact 至少包含：

- source object
- file path
- size
- content type
- created at
- owner agent
- source session
- compression candidate

## 用户体验要求

### 必须有的体验

1. 日志可直接看，不需要绕路。
2. 所有对象都能被搜索。
3. 所有对象都能被复制 ID。
4. 所有异常都能看到最近原始证据。
5. 所有列表都支持排序和保存视图。
6. 所有页面都要明确显示数据来源和刷新时间。

### 建议加入的体验

- 快捷键打开日志控制台
- 快捷键聚焦搜索
- 支持保存 filter preset
- 支持 compare mode
- 支持 bookmark investigation
- 支持“继续上次调查”

### 视觉原则

- 首页不是“平均用力”的卡片墙，而是有明确优先级的战情台。
- 红、黄、绿不只是装饰，要与行动相关。
- 列表密度要支持调试，不要只追求大卡片。
- investigation drawer 的信息层级要清晰，避免摘要淹没证据。

## 分阶段实施建议

## Phase 1：证据优先

目标：

- 先修复“想看日志却看不到”的最大痛点。

范围：

- 新增全局 `Log Console`
- `Sessions` 升级为 `Sessions & Logs`
- investigation 从 modal sheet 改为右侧 drawer
- `ExecutionLogEntry` 开始补 session / agent / transport 等字段
- 所有失败卡片一键跳日志

验收：

- 用户能在 Ops Center 内直接持续查看日志
- session / node / thread / route 都能联动日志

## Phase 2：Agent / Connection / Asset 三中心

目标：

- 让用户真正围绕三类对象做管理。

范围：

- `Agents` 页
- `Connections` 页
- `Assets` 页
- 新 projection 与 analytics 表

验收：

- 能找出最差 agent、最不稳 connection、最大文件热点

## Phase 3：Workflow Map 叠层升级

目标：

- 让地图成为真正的运行调试主画面。

范围：

- agent / connection / asset / cost layer
- node / edge investigation 丰富化
- 地图与日志联动

验收：

- 用户能从结构图直接定位异常对象和证据

## Phase 4：历史与智能洞察

目标：

- 在不牺牲即时感的前提下，补强长期诊断。

范围：

- 趋势页
- error index
- 回归检测
- agent / connection / asset 的自动洞察摘要

验收：

- 用户能看到“最近变差的是谁、哪条链路、哪个目录”

## 研发拆分建议

### UI 层

- 新的导航与容器布局
- drawer 替代 sheet
- 全局日志控制台
- 三个对象中心页面

### Domain / ViewModel 层

- agent health 聚合
- connection health 聚合
- asset health 聚合
- unified investigation context

### Persistence 层

- log schema v2
- projection 扩展
- analytics SQLite 扩展
- artifacts index 扩展

### Observability 层

- 连接错误码归类
- requested / actual transport 对齐
- file / memory 变化采样
- cost / token usage 采样

## 不建议这轮先做的事情

为了避免范围失控，这轮不建议优先做：

- 完整引入重量级外部 observability stack
- 先上复杂 3D 地图或过度视觉化
- 先做大量 AI 自动诊断而不补证据链
- 先做全自动清理 / 压缩，而没有先把可见性建立起来

这轮最重要的是：

- 对象对齐
- 日志回归主路径
- 证据链完整
- 调查成本明显下降

## 最终口径

这次升级不应再把 Ops Center 理解为“运行摘要页集合”，而应理解为：

一个围绕 `Agent / Connection / Files-Memory` 三类对象构建的运行控制台。

它的核心成功标准不是“图表更多”，而是：

- 用户更快知道问题在哪
- 用户更快拿到证据
- 用户更快判断应该处理谁、哪条连接、哪些文件或记忆
- 用户不再因为看不到日志而嫌弃仪表盘
