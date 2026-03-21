# Multi-Agent-Flow Workflow Editor Guide

Workflow Editor 是 Multi-Agent-Flow 的设计态核心界面，用于可视化搭建 workflow、组织 agent 关系，并编辑节点下的受管配置文件。

本文档描述的是当前生效的产品语义，可作为后续 README 扩写的基础说明。

## 核心定位

Workflow Editor 负责的是设计，不是执行。

它的核心职责是：

- 可视化搭建 workflow 结构
- 编辑节点、边界、连线与 agent 绑定关系
- 编辑当前节点下的受管配置文件
- 让用户清楚知道哪些改动还没保存、哪些改动还没 Apply

它不负责：

- 在编辑器内执行 workflow
- 在编辑器内运行测试流程
- 把外部 OpenClaw 文件系统作为实时双向同步对象

## 三种视图

Workflow Editor 当前提供三种视图，它们共享同一份 workflow 设计状态：

- List View
  以列表方式查看当前项目中的 agent、连接数量、配置文件状态与常用操作入口。
- Grid View
  以卡片方式浏览 agent，适合批量查看、筛选与进入节点配置。
- Architecture View
  以画布方式搭建 workflow，适合完成节点布局、连线、分组和整体结构设计。

三种视图共用同一套结构编辑语义，不存在 “某个视图改的是另一套状态”。

## Draft、Save、Apply

Workflow Editor 将设计流程拆成三层：

- Draft
  当前正在编辑的 workflow 设计态，包括结构变更和节点下的配置文件修改。
- Save
  将当前 draft 保存到 `.maoproj` 项目文件。
- Apply
  将当前 workflow 中待生效的结构配置和节点本地受管配置统一推送到 OpenClaw。

这三者的关系是：

- 编辑先进入 draft
- Save 只保存项目草稿
- Apply 才让当前配置对 OpenClaw 生效

因此，Save 不等于生效，Apply 也不等于替你同步外部源文件。

## 节点本地受管配置

Workflow Editor 的配置编辑采用 mirror-only 模型，但这里的 “mirror 内容” 指的是节点下的本地受管有效副本，不是字面意义上的 `openclaw/mirror/` 文档目录。

当前唯一直接编辑的配置面是：

```text
design/workflows/<workflow-id>/nodes/<node-id>/openclaw/workspace/
```

编辑器中的配置编辑遵循以下规则：

- 所有改动都发生在当前节点的受管 workspace 中
- 编辑器不直接回写外部源文件
- 编辑阶段不触发 OpenClaw 同步
- Apply 时统一读取这些受管文件并推送

## 可编辑文件范围

配置编辑不再只限于 `SOUL.md`。

当前编辑器面向的是当前 agent 范围内的受管 markdown 文件集合，首批包括：

- `SOUL.md`
- `AGENTS.md`
- `IDENTITY.md`
- `USER.md`
- `TOOLS.md`
- `HEARTBEAT.md`
- `BOOTSTRAP.md`
- `MEMORY.md`

文件选择范围严格限制在当前 agent 对应的 node-local managed workspace 中，不支持任意浏览本机路径，也不会跨 agent 编辑其他节点的文件。

## 节点与 Agent 规则

为避免节点身份和 agent 身份分裂，当前规则固定为：

- agent 节点标题不可单独编辑
- agent 节点标题始终等于 agent 名称
- 当 agent 改名时，绑定节点标题会同步刷新

非 agent 节点仍然保留自己的结构编辑语义，但标题会经过统一规范化。

## 常用编辑入口

Workflow Editor 当前的高频入口包括：

- 工具栏新增节点、对齐、分布、连线、批量连线、边界、撤销重做、删除、生成任务、保存 Draft、Apply
- List/Grid 中的编辑配置文件入口
- Reveal Config File，用于在 Finder 中定位当前节点的受管配置文件
- Open Workspace，用于打开当前 agent 的受管工作区
- Manage Skills、Configure Permissions、Duplicate、Export、Reset、Delete 等节点级操作

从 List 或 Grid 进入编辑时，系统会先确保当前 agent 已经拥有对应的 workflow 节点，再打开配置编辑面，以保证编辑上下文始终落在节点本地受管目录上。

## 推荐使用流程

典型工作流设计过程建议如下：

1. 在 List、Grid 或 Canvas 中创建或组织 agent 节点。
2. 调整连线、边界与布局，完成 workflow 结构搭建。
3. 进入节点配置面，编辑当前节点下的受管 markdown 文件。
4. 需要保留项目草稿时执行 Save。
5. 确认本轮设计完成后执行 Apply，将当前 workflow 配置统一推送到 OpenClaw。

## 故障排查

### 看不到配置文件

- 先确认当前 agent 已经绑定到 workflow 节点。
- 再确认节点下的受管 workspace 已完成创建。
- 如果某个文件缺失，编辑器会在当前 agent 的受管目录中创建它，而不是去查找外部任意路径。

### Save 之后为什么还要 Apply

因为 Save 保存的是项目草稿，Apply 才是把当前待生效配置推送到 OpenClaw。

### 为什么不能直接编辑外部源文件

这是为了让 workflow editor 专注于设计态编辑，降低同步歧义、越权修改和外部文件漂移带来的风险。

## 相关文档

- [Workflow 编辑器 Mirror-Only 升级方案](workflow-editor-mirror-only-upgrade-plan-zh-2026-03-22.md)
- [Workflow 编辑器 Mirror-Only 执行计划](workflow-editor-mirror-only-execution-plan-zh-2026-03-22.md)
- [画布编辑器介绍](Workflow-Canvas-Editor-Overview.md)
