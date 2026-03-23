# Ops Center 运行控制台重构方案

最后更新：2026-03-22
状态：已开始执行

## 目的

本文档用于沉淀 Multi-Agent-Flow 新一代仪表盘方向，后续可作为 README、实现说明和项目介绍材料的基础参考。

这次重构的目标，是把当前偏“长滚动分析页”的仪表盘，重建为一个以工作流运行和调试为核心的运行控制台。

重点优化目标：

- 即时感知运行状态
- 便于工作流调试
- 支持跨来源调查
- 以 session 为主线追踪执行
- 保留长期历史诊断能力

## 产品目标

新的仪表盘系统需要尽可能做到：

- 直观
- 详细
- 全面
- 尽可能即时
- 加载和切换流畅
- 更适合调试，而不是只适合报表展示

## 核心判断

当前项目底层其实已经具备非常好的可观测素材：

- managed project root
- collaboration thread 文件
- runtime session 文件
- execution results 与 logs
- analytics SQLite
- projection JSON
- workflow design 与 derived 文档

问题不在于“缺数据”，而在于当前仪表盘仍然主要按分析页来组织，而不是按调查路径和运行态来组织。

## 新的信息架构

新的 Ops Center 重构为 4 个一级页面：

1. `Live Run`
   回答“现在正在运行什么、卡在哪、哪条链路最需要先看”。

2. `Sessions`
   把 session 提升为一等对象，直接查看 dispatch、event、receipt 以及关联上下文。

3. `Workflow Map`
   把运行状态覆盖到工作流结构上，方便用户直接调试工作流，而不是只读列表。

4. `History`
   保留趋势、异常、协议治理和长期分析能力，但降为辅助层，不再作为主入口。

## 与当前文件系统的对齐

本次重构不会推翻现有 managed project filesystem，而是直接建立在它之上。

当前已经存在的关键内部目录：

```text
Projects/<project-id>/
  design/
  collaboration/
  runtime/
  tasks/
  execution/
  openclaw/
  analytics/
  indexes/
```

尤其重要的调试数据面：

- `collaboration/workbench/threads/<thread-id>/thread.json`
- `collaboration/workbench/threads/<thread-id>/dialog.ndjson`
- `runtime/sessions/<session-id>/session.json`
- `runtime/sessions/<session-id>/dispatches.ndjson`
- `runtime/sessions/<session-id>/events.ndjson`
- `runtime/sessions/<session-id>/receipts.ndjson`
- `execution/results.ndjson`
- `execution/logs.ndjson`
- `analytics/analytics.sqlite`
- `analytics/projections/*.json`
- `indexes/workflows.json`
- `indexes/nodes.json`
- `indexes/threads.json`
- `indexes/sessions.json`

## 新仪表盘的数据分层

新的仪表盘读取链路分为三层：

### 1. 即时内存层

用于实时刷新：

- `AppState`
- `RuntimeState`
- `OpenClawService`
- 内存中的 tasks、messages、execution results、logs

### 2. 索引与投影层

用于快速启动和列表展示：

- `indexes/*.json`
- `analytics/projections/*.json`

### 3. 历史分析层

用于趋势和长期分析：

- `analytics.sqlite`

## 新的一等运行对象

本次重构后，以下对象需要成为仪表盘中的一等公民：

- workflow
- node
- edge
- session
- thread
- dispatch
- runtime event
- receipt
- anomaly
- tool
- cron run

也就是说，用户不应再只能从聚合卡片开始调查。

## 建议新增的 projection

为了支撑新的运行控制台，建议新增：

- `analytics/projections/live-run.json`
- `analytics/projections/workflow-health.json`
- `analytics/projections/sessions.json`
- `analytics/projections/nodes-runtime.json`

建议配套增加：

- `runtime/sessions/<session-id>/artifacts/index.json`
- `collaboration/workbench/threads/<thread-id>/investigation.json`

## 交互原则

1. 默认首页必须优先回答“现在发生了什么”。
2. 所有红色状态都必须能快速跳到具体原因。
3. 工作流运行态必须回到工作流结构图上，而不是只出现在表格里。
4. session 和 thread 必须建立显式关联，不能继续彼此割裂。
5. 历史分析继续保留，但不再主导默认调试体验。
6. 冷启动优先依赖 projections 和 indexes，而不是直接扫描全量 NDJSON。

## 执行策略

这次重构在产品形态上不采用渐进式兼容，而是直接替换旧主路径。

执行原则：

- 旧仪表盘冻结为 legacy
- 新建独立 `OpsCenter` 模块
- 主导航和工作台入口切到新容器
- 旧分析实现只在迁移阶段作为回退参考，不再作为主界面继续迭代

## 执行计划

### Phase 1：新容器与新导航

- 建立 `OpsCenterDashboardView`
- 定义新的页面模型和运行态模型
- 建立 `Live Run`、`Sessions`、`Workflow Map`、`History` 四页
- 把主应用和工作台入口切到新容器

### Phase 2：以 session 为核心的调查链

- 定义统一 investigation handle
- 建立 session 摘要和 timeline
- 打通 session 与 workflow、thread、task、message 的关联

### Phase 3：工作流运行地图

- 将节点和边的运行态覆盖到 workflow 结构
- 支持状态、延迟、失败、路由、审批、文件压力等图层

### Phase 4：扩展 projection

- 生成 live-run 和 workflow-health 投影
- 生成 session 与 node 的运行摘要投影
- 基于 indexes 与 projections 优化启动和跳转速度

### Phase 5：统一 investigation panel

- 替换零散的 trace/anomaly/tool/cron 详情入口
- 所有深钻统一经过一套 investigation 模型和容器

### Phase 6：历史页收敛

- 保留历史指标与趋势
- 增加自动洞察摘要与推荐调查入口
- 历史页定位为辅助决策层，而不是默认落点

## 验收标准

当满足以下条件时，说明重构有效：

1. 打开仪表盘后，用户能立刻理解当前 workflow 的运行态。
2. 用户能直接看出哪些节点堵塞、哪些路径失败。
3. 任意一次失败都能快速回溯到 session、工作流区域和相关上下文。
4. session、thread、anomaly、workflow 的调查链路不再割裂。
5. 工作流调试变成“结构优先”，而不是“列表优先”。
6. 历史分析仍然可用，但不会拖慢实时控制台体验。

## 当前执行状态

本次执行已经启动，首轮包含：

- 双语方案文档入库
- 用新的 Ops Center 容器替换旧入口
- 建立 `Live Run`、`Sessions`、`Workflow Map`、`History` 的第一版骨架

