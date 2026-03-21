# Agent 模板资产目录规范

最后更新：2026-03-22
状态：Proposed

## 文档目标

本文档用于定义新模板系统下标准 agent 模板资产的目录结构与文件职责。

它是下面两份重设计文档的配套规范：

- [template-filesystem-redesign-2026-03-21.md](/Users/chenrongze/Desktop/MultiAgentOrchestrator/MultiAgentOrchestrator/Multi-Agent-Flow/Documentation/template-filesystem-redesign-2026-03-21.md)
- [template-filesystem-redesign-zh-2026-03-22.md](/Users/chenrongze/Desktop/MultiAgentOrchestrator/MultiAgentOrchestrator/Multi-Agent-Flow/Documentation/template-filesystem-redesign-zh-2026-03-22.md)

本文档只讨论 agent 模板，不讨论工作流模板。

## 设计目标

每个模板资产都必须是一套完整、标准、文件系统原生的 agent 包。

编辑器在复制模板时，应当能够直接得到一个标准 agent：

- 如果用户不修改，应该已经可以直接使用
- 如果用户有自己的想法，也只是对复制出来的 agent 继续调整
- 调整后的 agent 与模板没有任何关联

同样地，当用户将一个 agent 保存为模板时：

- 系统应生成一套新的模板资产文件
- 新模板与原 agent 不保留任何 live relation

模板文件本身绝不进入工作流，也绝不作为运行时参与者存在。

## 模板根目录

每个模板资产都拥有自己的独立根目录：

```text
<template-id>/
  template.json
  SOUL.md
  AGENTS.md
  IDENTITY.md
  USER.md
  TOOLS.md
  BOOTSTRAP.md
  HEARTBEAT.md
  MEMORY.md
  lineage.json
  revisions/
    <revision-id>.json
  extensions/
    README.md
    examples/
    tests/
    assets/
```

## 文件分类

模板目录中的文件建议分为三类。

## 一、核心源文件

- `template.json`
- `lineage.json`

这两类文件是结构化定义和来源记录的主入口。

## 二、标准物化配套文件

- `SOUL.md`
- `AGENTS.md`
- `IDENTITY.md`
- `USER.md`
- `TOOLS.md`
- `BOOTSTRAP.md`
- `HEARTBEAT.md`
- `MEMORY.md`

这些文件组成标准 agent 模板包的主要文档表面。

## 三、扩展开发文件

- `revisions/`
- `extensions/`

这部分主要用于版本化、示例、测试和二次开发。

## 必需文件

对一个非 draft 模板来说，以下文件必须存在：

- `template.json`
- `SOUL.md`
- `AGENTS.md`
- `IDENTITY.md`
- `USER.md`
- `TOOLS.md`
- `BOOTSTRAP.md`
- `HEARTBEAT.md`
- `MEMORY.md`
- `lineage.json`

Draft 例外规则：

- 草稿模板允许内容暂时不完整
- 但必需文件集仍然必须存在
- draft 状态必须在 `template.json` 中被明确标记

## 文件定义

## `template.json`

用途：

- 模板资产的结构化主定义文件

最低职责：

- 模板 ID
- revision
- display name
- family/category 等管理信息
- 结构化 SOUL 源内容
- 校验状态
- draft/published 状态
- 时间戳

建议字段：

```text
id
revision
displayName
meta
soulSpec
renderedSoulHash
validation
status
createdAt
updatedAt
```

规则：

- 它是模板资产的主源文件
- 其余 markdown 配套文件应当可以由它派生
- 不得包含任何 workflow binding 信息

## `lineage.json`

用途：

- 记录模板来源和资产历史

典型内容：

- source scope
- source template ID
- source revision
- import path
- import hash
- created reason

规则：

- 血缘属于模板资产本身，不属于项目
- 不得写入 workflow 状态引用

## `SOUL.md`

用途：

- 模板对应的标准 SOUL 文档

预期内容：

- 角色定位
- 核心使命
- 核心能力
- 输入要求
- 工作职责
- 工作流程
- 输出要求
- 协作边界
- 行为边界
- 成功标准

规则：

- 它必须足够完整，能直接作为标准 agent 的 SOUL 使用
- 不得包含模板管理信息泄漏
- 应与 `template.json` 当前渲染结果一致

## `AGENTS.md`

用途：

- 作为模板包顶层说明和身份索引

建议内容：

- 模板名称
- 模板 ID
- revision
- agent package 类型说明
- 当前目录中包含哪些关键文件

规则：

- 与项目运行态中的 `AGENTS.md` 不同，这里描述的是模板包本身，而不是 workflow 节点绑定
- 不应包含 node ID 或 workflow ID

## `IDENTITY.md`

用途：

- 简洁表达该 agent 的身份定义

预期内容：

- identity label
- 角色摘要
- 稳定人格/职责 framing

规则：

- 应短而稳定
- 应与模板定义中的 identity 含义一致

## `USER.md`

用途：

- 面向使用者解释这个 agent 是干什么的

预期内容：

- 这个 agent 能帮助什么
- 适用场景
- 用户与其互动时的预期方式

规则：

- 用户无需读完整个模板目录，也应能从这个文件理解它是否适合自己

## `TOOLS.md`

用途：

- 描述标准 agent 包预期具备的能力/工具画像

预期内容：

- capability list
- tool profile
- 一般性的环境假设

规则：

- 不得写入项目专属环境密钥
- 描述的是通用能力要求，而不是 workflow 运行时绑定

## `BOOTSTRAP.md`

用途：

- 描述该模板包作为标准 agent 的启动上下文

预期内容：

- 预期模型或 runtime profile
- 初始化假设
- 初次使用前提

规则：

- 应保持模板通用性
- 不得包含机器本地或项目本地绝对路径

## `HEARTBEAT.md`

用途：

- 描述该模板的稳定运行状态与健康预期

预期内容：

- 协议/运行模式摘要
- 更新语义
- 基本健康检查预期

规则：

- 它应描述 steady-state 运行特征
- 不应被当成 runtime log 使用

## `MEMORY.md`

用途：

- 描述该模板的记忆策略和稳定规则

预期内容：

- memory policy 摘要
- 长期稳定原则
- 稳定工作规则

规则：

- 应包含可复用的记忆指导
- 不得混入项目专属历史记忆

## 版本目录

## `revisions/<revision-id>.json`

用途：

- 保存历史模板定义的不可变快照

规则：

- revisions 应 append-only
- 当前发布态仍然由 `template.json` 表达
- revision 文件应 machine-readable 且尽量 deterministic

## 扩展目录

## `extensions/README.md`

用途：

- 说明模板目录中附带的扩展材料是什么

## `extensions/examples/`

用途：

- 存放示例输入、示例输出、示例使用场景

## `extensions/tests/`

用途：

- 存放校验样例、评估样例或质量测试夹具

## `extensions/assets/`

用途：

- 存放除核心文件外，为复用或二次开发所需的补充材料

规则：

- `extensions/` 是可选的
- 模板的核心可用性不应依赖 `extensions/`

## 路径规则

模板资产路径应遵循以下规则：

- 不出现 workflow ID
- 不出现 node ID
- 在模板根目录内部不出现 project ID
- 除非明确是占位符，否则不应在文件内容中写入机器本地绝对路径
- 文件名应稳定、可预测
- 默认优先使用 ASCII 命名

## 内容完整性规则

如果出现以下情况，一个标准模板应被拒绝、报错或标记为 incomplete：

- 必需文件缺失
- `SOUL.md` 只有占位内容
- 配套文档为空或基本无意义
- 内容明显不足以支持“直接复制后使用”

建议的质量下限是：

- 用户复制模板后，应当能立即得到一个可直接使用的标准 agent
- 用户修改应是可选 refinement，而不是强制补救

## 与当前项目文件系统代码的关系

当前 `ProjectFileSystem` 已经会为 node-local OpenClaw workspace 生成：

- `AGENTS.md`
- `IDENTITY.md`
- `USER.md`
- `TOOLS.md`
- `BOOTSTRAP.md`
- `HEARTBEAT.md`
- `MEMORY.md`
- `SOUL.md`

新模板资产规范应尽量对齐这些文档的职责边界，但要去掉项目/节点耦合：

- 不包含 node ID
- 不包含 workflow ID
- 不包含 runtime-only binding 语义

## 校验清单

一个标准模板资产至少应通过如下校验：

- 必需文件集存在
- `template.json` 能正常解析
- `lineage.json` 能正常解析
- `SOUL.md` 与结构化源内容一致
- 配套文档非空
- `SOUL.md` 不含模板管理信息泄漏
- 标准模板文件中不存在项目/工作流耦合信息
- draft/published 状态合法

## 编辑器行为要求

当用户应用模板时：

1. 读取模板根目录。
2. 以 `template.json` 作为结构化主源。
3. 读取或按需重新生成标准配套文件。
4. 将模板复制为标准 agent 草稿。
5. 产出一个独立 agent。

当用户将 agent 保存为模板时：

1. 提取该 agent 的标准状态。
2. 创建新的模板根目录。
3. 写入完整标准文件集。
4. 不保留与原 agent 的 live relation。

## 不在本文范围内

本文档不定义：

- workflow template packaging
- 项目中对模板引用的持久化
- 运行时执行协议
- marketplace 元数据 schema

这些能力后续可以增加，但不能削弱一条原则：

- 模板资产始终独立于工作流和项目
