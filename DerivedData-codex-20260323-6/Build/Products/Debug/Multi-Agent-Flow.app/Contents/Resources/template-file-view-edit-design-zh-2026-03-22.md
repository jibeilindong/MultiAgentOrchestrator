# 模板文件查看与编辑功能设计方案

最后更新：2026-03-22
状态：Proposed

## 1. 文档目标

本文档用于定义新模板系统下“模板文件查看与编辑功能”的产品与实现方案。

本文档建立在当前已确认的模板系统原则之上：

1. 模板与项目完全解耦，项目中不包含模板信息。
2. 模板是一种标准化资产，可流通、可导入导出、可二次开发、可从零创建。
3. 模板遵从本软件的文件系统设计。
4. 模板特指 agent 模板，不包括工作流模板。
5. 标准化模板要求文件、路径和内容尽可能完整、标准、充实。
6. 模板使用时，本质上是复制并实例化为独立 agent，实例化后与模板完全断联。
7. 模板文件绝不参与工作流，工作流只消费实例化后的 agent。
8. 旧模板兼容不是目标，新系统以新标准模板为准。

本文档重点回答两个问题：

- 用户如何查看一个模板资产中的所有标准文件
- 用户如何以文件系统原生方式编辑模板，并安全地保存、校验、发布

## 2. 当前现状

基于当前代码，模板系统已经具备较强的文件系统基础，但查看和编辑能力仍偏向“表单草稿”，尚未真正形成“模板资产工作区”。

当前已有基础：

- [TemplateFileSystem.swift](/Users/chenrongze/Desktop/MultiAgentOrchestrator/MultiAgentOrchestrator/Multi-Agent-Flow/Sources/Services/TemplateFileSystem.swift) 已支持标准模板资产目录的路径定义、脚手架创建、文件写入、目录导入导出。
- [TemplateAssets.swift](/Users/chenrongze/Desktop/MultiAgentOrchestrator/MultiAgentOrchestrator/Multi-Agent-Flow/Sources/Models/TemplateAssets.swift) 已定义 `TemplateAssetDocument`、`TemplateLineage`、`TemplateValidationState`、`TemplateAssetStatus`。
- [AgentTemplateLibraryStore.swift](/Users/chenrongze/Desktop/MultiAgentOrchestrator/MultiAgentOrchestrator/Multi-Agent-Flow/Sources/Services/AgentTemplateLibraryStore.swift) 已支持模板库、导入预检、冲突避让、模板资产导出、模板复制和 agent 保存为模板。
- [AgentTemplates.swift](/Users/chenrongze/Desktop/MultiAgentOrchestrator/MultiAgentOrchestrator/Multi-Agent-Flow/Sources/Models/AgentTemplates.swift) 已支持 `SOUL.md` 渲染、解析与校验。
- [PropertiesPanelView.swift](/Users/chenrongze/Desktop/MultiAgentOrchestrator/MultiAgentOrchestrator/Multi-Agent-Flow/Sources/Views/PropertiesPanelView.swift) 已提供模板库管理页、模板草稿表单、`SOUL.md` 预览、导入导出入口。

当前主要问题：

1. 当前编辑对象是 `TemplateEditorDraft`，不是模板资产目录里的真实文件。
2. `SOUL.md` 目前主要是预览结果，不是完整的一等编辑对象。
3. 其他标准文件几乎没有稳定的查看与编辑入口。
4. 模板编辑 UI 深度耦合在属性面板中，与“模板是独立资产”这一原则不一致。
5. 保存流程直接写正式模板资产，缺少独立草稿工作区与原子提交机制。
6. `template.json`、`SOUL.md`、其他标准文件之间的同步关系还不够清晰。

## 3. 设计目标

新的模板文件查看与编辑功能应达成以下目标：

1. 让模板真正以“文件系统原生资产”的方式被查看和编辑。
2. 让用户能完整看到一个模板目录中的标准文件，而不只是表单字段。
3. 兼顾结构化编辑与原始文件编辑两种模式。
4. 保证模板编辑过程不影响工作流与项目数据。
5. 提供清晰的草稿、保存、校验、发布语义。
6. 保证模板目录始终可补齐为标准、完整、可流通的模板资产。

## 4. 关键确认决策

以下三项已确认，作为本方案的硬约束：

### 4.1 `SOUL.md` 作为 agent 语义主源

在模板语义层，`SOUL.md` 是核心主源文件。

含义是：

- agent 的角色、使命、能力、边界等语义以 `SOUL.md` 为准
- 系统应支持从 `SOUL.md` 解析出 `soulSpec`
- 结构化编辑与原始 markdown 编辑都应围绕 `SOUL.md` 建立

### 4.2 采用“正式资产目录 + 草稿目录”的编辑模型

模板编辑不应直接在正式模板资产目录上进行。

正确模型是：

- 正式模板资产目录：模板库中当前正式内容
- 草稿目录：用户本次编辑会话的工作副本

所有改动先写草稿目录，再统一保存或发布。

### 4.3 `AGENTS.md` 与 `lineage.json` 默认由系统维护

这两个文件是系统索引和血缘文件，不作为普通可自由编辑文件。

建议规则：

- `AGENTS.md`：默认只读，由系统根据模板当前状态生成
- `lineage.json`：默认只读，由系统维护来源、导入、分叉、更新时间等信息
- 如需高级维护，可后续补管理员模式，但本阶段不作为普通编辑能力开放

## 5. 信息架构

建议将模板查看与编辑功能升级为一个独立的“模板资产工作区”。

主界面采用三栏结构：

- 左栏：模板库列表
- 中栏：当前模板工作区
- 右栏：检查器与状态面板

中栏顶部建议包含五个页签：

1. `总览`
2. `文件`
3. `校验`
4. `版本`
5. `导入导出`

各页职责如下：

### 5.1 总览

用于展示模板资产的概况：

- 模板名称、ID、分类、状态
- 来源范围与 lineage 摘要
- 当前 revision
- 模板实例化说明
- 标准完整性概览

### 5.2 文件

这是核心页，提供模板目录级的查看与编辑能力：

- 文件树浏览
- 标准文件状态
- 文件内容查看
- 文件内容编辑
- 缺失文件补齐
- 文件级错误与脏状态提示

### 5.3 校验

用于展示模板完整性与一致性问题：

- 必需文件缺失
- `SOUL.md` 结构问题
- `template.json` 与 `SOUL.md` 不一致
- 标准文件内容空缺
- 发布门禁问题

### 5.4 版本

用于展示 revision 历史与版本操作：

- 当前 revision
- 历史快照列表
- 每次保存或发布的时间
- 变更摘要

### 5.5 导入导出

用于模板资产目录级的流通：

- 导入模板资产目录
- 导出当前模板资产
- 导出筛选结果
- 展示导入预检与冲突提示

说明：

- 不增加 `extensions/examples/tests/assets` 的专门可视化浏览入口
- 保留模板资产目录导入预检和冲突提示

## 6. 文件模型设计

模板资产目录延续当前标准结构：

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
    r0001.json
    r0002.json
  extensions/
    README.md
    examples/
      README.md
      default-prompt.md
    tests/
      README.md
      acceptance-checklist.md
    assets/
      README.md
      asset-manifest.md
```

为支持查看与编辑，建议把文件划分为三类。

### 6.1 核心可编辑文件

- `SOUL.md`
- `IDENTITY.md`
- `USER.md`
- `TOOLS.md`
- `BOOTSTRAP.md`
- `HEARTBEAT.md`
- `MEMORY.md`
- `extensions/README.md`
- `extensions/examples/README.md`
- `extensions/examples/default-prompt.md`
- `extensions/tests/README.md`
- `extensions/tests/acceptance-checklist.md`
- `extensions/assets/README.md`
- `extensions/assets/asset-manifest.md`

这些文件应支持：

- 文件树展示
- 原文查看
- 原文编辑
- 缺失文件补齐
- 文件级校验

### 6.2 结构化主文件

- `template.json`

该文件应支持双视图：

- 结构化编辑视图
- 原始 JSON 视图

结构化编辑视图用于降低编辑门槛，原始 JSON 视图用于高级维护与调试。

### 6.3 系统维护文件

- `AGENTS.md`
- `lineage.json`
- `revisions/*.json`

这些文件默认只读展示，不开放普通手改。

## 7. Source of Truth 与同步规则

### 7.1 语义主源

`SOUL.md` 是 agent 语义主源。

系统保存模板时，需要：

- 解析 `SOUL.md`
- 更新 `template.json.soulSpec`
- 更新 `renderedSoulHash`
- 执行语义与结构校验

### 7.2 索引主源

`template.json` 是模板资产索引主源。

系统保存模板时，需要确保它准确记录：

- 模板基础信息
- 当前 `soulSpec`
- 校验结果
- 状态
- revision
- 时间戳

### 7.3 派生文件

以下文件建议由系统生成或半生成：

- `AGENTS.md`
- `lineage.json`

其他标准 markdown 文件可由模板标准 scaffold 生成初始内容，但之后允许用户编辑其正文。

### 7.4 冲突策略

当结构化编辑和原文编辑同时存在时，遵循以下原则：

1. `SOUL.md` 原文修改优先
2. `template.json` 结构化字段由保存流程统一回填
3. 若解析失败，则提示用户修复 `SOUL.md`，但保留草稿
4. 不允许静默覆盖用户已编辑的正文文件

## 8. 模板草稿会话模型

建议引入 `TemplateDraftSession` 作为模板编辑的核心运行时对象。

建议会话包含：

- `templateID`
- `sourceAssetURL`
- `draftRootURL`
- `openedAt`
- `hasUnsavedChanges`
- `hasValidationErrors`
- `dirtyFilePaths`
- `selectedFilePath`
- `lastValidationState`

工作方式：

1. 用户打开模板
2. 系统复制正式模板资产目录到草稿目录
3. 用户所有修改都发生在草稿目录
4. 切换文件、切换页签、关闭窗口时会话状态保留
5. 用户选择保存或发布时，再将草稿提交回正式模板资产目录

## 9. 文件查看与编辑交互

建议“文件”页采用三栏布局。

### 9.1 左侧文件树

显示模板标准目录结构，顺序固定：

1. `template.json`
2. `SOUL.md`
3. `AGENTS.md`
4. `IDENTITY.md`
5. `USER.md`
6. `TOOLS.md`
7. `BOOTSTRAP.md`
8. `HEARTBEAT.md`
9. `MEMORY.md`
10. `lineage.json`
11. `revisions/`
12. `extensions/`

文件树状态提示：

- 缺失文件：灰色占位，可“一键创建”
- 已修改文件：蓝点
- 有错误文件：红点
- 系统维护文件：锁图标

### 9.2 中央编辑区

根据文件类型提供不同编辑方式：

- `SOUL.md`：支持“结构化视图 / 原文视图”切换
- `template.json`：支持“表单视图 / JSON 视图”切换
- 其他 markdown：统一文本编辑器
- 只读文件：统一查看器

### 9.3 右侧检查器

用于显示当前文件的上下文信息：

- 文件职责说明
- 是否必需
- 是否允许编辑
- 最近修改时间
- 是否缺失
- 当前校验问题
- 可执行动作

可执行动作建议：

- 创建缺失文件
- 重置为标准 scaffold
- 打开模板目录
- 显示与当前 revision 的差异

## 10. 保存、校验、发布流程

建议模板工作区引入以下操作语义：

- `保存草稿`
- `执行校验`
- `发布模板`
- `放弃修改`

### 10.1 保存草稿

含义：

- 保留当前草稿修改
- 更新草稿级校验状态
- 可存在 warning 或 error
- 正式模板状态仍可保持 `draft`

### 10.2 执行校验

执行完整模板校验，并在校验页中呈现问题。

### 10.3 发布模板

发布前要求：

- 必需文件集齐全
- `SOUL.md` 可被解析
- 关键结构校验通过
- 不存在阻断性 error

发布时系统执行：

1. 解析草稿中的 `SOUL.md`
2. 更新 `template.json`
3. 重建 `AGENTS.md`
4. 更新 `lineage.json.updatedAt`
5. 写入新的 `revisions/rXXXX.json`
6. 原子替换正式模板资产目录
7. 更新模板库索引与 manifest

### 10.4 放弃修改

删除当前草稿目录，恢复到正式模板资产内容。

## 11. 校验体系

建议校验拆为四层。

### 11.1 结构完整性校验

- 必需文件是否存在
- 必需目录是否存在
- 标准 scaffold 是否完整

### 11.2 内容完整性校验

- `SOUL.md` 必需章节是否完整
- 核心 markdown 文件是否为空
- 标准示例与测试说明是否存在

### 11.3 一致性校验

- `SOUL.md` 与 `template.json.soulSpec` 是否一致
- 模板名称、identity、分类是否一致
- `AGENTS.md` 是否反映当前模板状态

### 11.4 发布门禁校验

- 有 error 不允许发布
- 有 warning 允许保存但需提示
- 缺失标准文件时支持一键补齐

## 12. 与当前代码结构的映射

本方案建议在现有代码上做分层收口，而不是继续把能力堆叠在 [PropertiesPanelView.swift](/Users/chenrongze/Desktop/MultiAgentOrchestrator/MultiAgentOrchestrator/Multi-Agent-Flow/Sources/Views/PropertiesPanelView.swift) 中。

建议新增：

- `TemplateWorkspaceView.swift`
- `TemplateFileTreeView.swift`
- `TemplateFileEditorView.swift`
- `TemplateInspectorView.swift`
- `TemplateDraftSession.swift`
- `TemplateFileIndex.swift`
- `TemplateValidationService.swift`
- `TemplateSyncService.swift`

建议职责调整：

### 12.1 `TemplateFileSystem`

继续负责：

- 标准模板目录路径
- 草稿目录创建与回收
- 模板目录复制
- 文件补齐
- 原子提交

建议新增能力：

- 草稿目录路径规则
- 标准文件索引
- 单文件创建与重置
- revision 快照辅助

### 12.2 `AgentTemplateLibraryStore`

继续负责：

- 模板库列表
- 导入导出
- 模板保存
- 模板发布

建议新增能力：

- 打开模板草稿会话
- 关闭模板草稿会话
- 提交草稿
- 放弃草稿
- 读取模板文件工作区状态

### 12.3 `AgentTemplates`

继续负责：

- `SOUL.md` 渲染
- `SOUL.md` 解析
- 模板语义校验

### 12.4 `PropertiesPanelView`

调整为：

- 只保留模板库入口
- 不再承担完整模板文件编辑器

## 13. UI 细节建议

### 13.1 模板列表项

除现有信息外，建议补充：

- `Draft` / `Published` 状态
- 文件完整度
- 最近编辑时间
- 是否存在未发布草稿

### 13.2 工作区顶部操作

建议统一放置：

- `保存草稿`
- `校验`
- `发布模板`
- `放弃修改`
- `打开目录`
- `导出模板资产`

### 13.3 文件缺失提示

如果缺失标准文件：

- 文件树中显示占位项
- 中间区域显示该文件用途说明
- 提供“一键创建标准文件”

### 13.4 导入预检与冲突提示

继续保留当前已实现的模板资产目录导入预检能力，并将其统一纳入模板工作区或模板库入口中：

- 检测目录是否是有效模板资产目录
- 预览将导入哪些模板
- 展示 ID、名称、identity 冲突
- 提示导入后会成为独立模板资产

## 14. 非目标

本阶段不纳入以下内容：

- 旧模板兼容迁移层
- 模板与工作流之间的任何绑定关系
- 模板资产中 `extensions/examples/tests/assets` 的复杂可视化浏览器
- 模板直接参与运行时
- 多人协同编辑同一模板的实时协作

## 15. 推荐结论

本方案建议将模板文件查看与编辑正式升级为“模板资产工作区”能力，明确采用：

1. `SOUL.md` 作为 agent 语义主源
2. 正式资产目录加草稿目录的双目录编辑模型
3. `AGENTS.md` 与 `lineage.json` 默认系统维护
4. 文件树浏览、原文编辑、结构化编辑、校验发布一体化

这样可以把当前已经存在的模板文件系统基础，真正提升为一套完整、稳定、可扩展的模板资产编辑体验。
