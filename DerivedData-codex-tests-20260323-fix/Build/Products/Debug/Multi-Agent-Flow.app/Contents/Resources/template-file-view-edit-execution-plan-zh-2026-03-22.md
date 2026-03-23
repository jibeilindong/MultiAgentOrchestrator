# 模板文件查看与编辑功能执行计划

最后更新：2026-03-22
状态：Draft for review

## 1. 目标

基于新的模板系统规则，为模板资产建立一套完整的文件查看、原文编辑、结构化编辑、校验、保存与发布能力。

执行目标包括：

1. 将模板编辑从属性面板中的表单草稿，升级为独立的模板资产工作区。
2. 建立“正式资产目录 + 草稿目录”的编辑模型。
3. 让模板查看与编辑围绕标准模板文件系统展开。
4. 在不影响工作流与项目的前提下，补齐模板资产的查看、编辑、校验和版本链路。

## 2. 已确认前提

本执行计划建立在以下已确认结论之上：

1. `SOUL.md` 是 agent 语义主源。
2. 模板编辑采用“正式资产目录 + 草稿目录”模型。
3. `AGENTS.md` 与 `lineage.json` 默认由系统维护，不作为普通可编辑文件。
4. 模板与工作流完全解耦。
5. 模板实例化 agent 时始终复制断联。
6. 不考虑旧模板兼容。

## 3. 总体实施策略

整体上按“先收口数据模型，再建立工作区，再补编辑器，再补发布链路”的顺序推进。

执行原则：

- 尽量复用现有 `TemplateFileSystem`、`AgentTemplateLibraryStore`、`AgentTemplateSoulMarkdownParser`
- 不破坏当前模板导入导出能力
- 每一阶段都形成独立可验收结果
- 先保证数据语义正确，再补 UI 细节

## 4. 分阶段计划

### Phase 0：文档与语义收口

目标：

- 将“模板查看与编辑功能”的设计约束固化为正式文档
- 统一团队对模板资产工作区的理解

实施项：

- 落地设计方案文档
- 落地执行计划文档
- 明确 `SOUL.md`、`template.json`、`AGENTS.md`、`lineage.json` 的职责边界

验收标准：

- 文档已进入项目文档目录
- 方案中明确三项关键确认决策

### Phase 1：建立模板草稿会话与草稿目录

目标：

- 建立模板编辑会话机制
- 让所有模板编辑先进入草稿目录，不直接写正式模板资产目录

实施项：

- 在 `TemplateFileSystem` 中增加模板草稿目录路径规则
- 增加草稿目录创建、复制、回收能力
- 新增 `TemplateDraftSession` 模型
- 在 `AgentTemplateLibraryStore` 中增加打开会话、关闭会话、放弃草稿能力

建议关注文件：

- `Multi-Agent-Flow/Sources/Services/TemplateFileSystem.swift`
- `Multi-Agent-Flow/Sources/Services/AgentTemplateLibraryStore.swift`
- 新增 `Multi-Agent-Flow/Sources/Models/TemplateDraftSession.swift`

验收标准：

- 打开模板时会生成独立草稿目录
- 编辑只发生在草稿目录
- 放弃修改可以清理草稿目录并恢复正式内容

### Phase 2：建立模板文件索引与文件树

目标：

- 让模板工作区能稳定列出标准模板目录中的所有关键文件
- 为缺失文件、只读文件、脏文件建立统一状态模型

实施项：

- 新增 `TemplateFileIndex`
- 定义标准文件顺序与文件元信息
- 标记文件类型、是否必需、是否只读、是否缺失、是否脏
- 在 UI 中建立模板文件树视图

建议关注文件：

- 新增 `Multi-Agent-Flow/Sources/Models/TemplateFileIndex.swift`
- 新增 `Multi-Agent-Flow/Sources/Views/TemplateFileTreeView.swift`
- `Multi-Agent-Flow/Sources/Services/TemplateFileSystem.swift`

验收标准：

- 模板工作区能完整显示标准文件树
- 缺失文件有明确占位
- `AGENTS.md`、`lineage.json`、`revisions/` 能正确标记为只读或系统维护

### Phase 3：建立模板资产工作区 UI 框架

目标：

- 将模板编辑主界面从 `PropertiesPanelView` 中抽离
- 建立独立工作区壳层与页签结构

实施项：

- 新增 `TemplateWorkspaceView`
- 增加 `总览`、`文件`、`校验`、`版本`、`导入导出` 页签
- 保留当前模板库列表与筛选能力
- 将原模板管理页逐步改造成新工作区入口

建议关注文件：

- 新增 `Multi-Agent-Flow/Sources/Views/TemplateWorkspaceView.swift`
- 新增 `Multi-Agent-Flow/Sources/Views/TemplateInspectorView.swift`
- `Multi-Agent-Flow/Sources/Views/PropertiesPanelView.swift`

验收标准：

- 模板可在独立工作区中打开
- 属性面板不再承担完整模板编辑器职责
- 新工作区可以稳定切换模板、页签和文件

### Phase 4：实现 `SOUL.md` 与 `template.json` 双轨编辑

目标：

- 建立模板编辑的核心能力
- 支持结构化编辑与原文编辑并存

实施项：

- 为 `SOUL.md` 增加“结构化视图 / 原文视图”切换
- 为 `template.json` 增加“表单视图 / JSON 视图”切换
- 将原有 `TemplateEditorDraft` 的主要能力迁移到新工作区
- 将 `SOUL.md` 解析失败反馈纳入编辑器状态

建议关注文件：

- 新增 `Multi-Agent-Flow/Sources/Views/TemplateFileEditorView.swift`
- `Multi-Agent-Flow/Sources/Models/AgentTemplates.swift`
- `Multi-Agent-Flow/Sources/Views/PropertiesPanelView.swift`

验收标准：

- `SOUL.md` 可查看、可编辑、可切换视图
- `template.json` 可结构化编辑，也可切换到原始 JSON
- `SOUL.md` 修改后可正确回填 `soulSpec`

### Phase 5：补齐其他标准文件编辑与系统维护文件查看

目标：

- 打通模板目录中的主要文件查看与编辑体验
- 让模板真正成为完整标准资产

实施项：

- 支持编辑 `IDENTITY.md`、`USER.md`、`TOOLS.md`、`BOOTSTRAP.md`、`HEARTBEAT.md`、`MEMORY.md`
- 支持查看 `AGENTS.md`、`lineage.json`、`revisions/*.json`
- 支持扩展目录中的标准文本文件查看与编辑
- 增加“创建缺失文件”“重置为标准 scaffold”动作

建议关注文件：

- `Multi-Agent-Flow/Sources/Services/TemplateFileSystem.swift`
- 新增 `Multi-Agent-Flow/Sources/Views/TemplateFileEditorView.swift`
- 新增 `Multi-Agent-Flow/Sources/Views/TemplateInspectorView.swift`

验收标准：

- 所有标准文本文件都能查看
- 核心可编辑文件都能修改并写回草稿目录
- 缺失文件可一键补齐

### Phase 6：建立校验、保存、发布、revision 流程

目标：

- 让模板工作区具备完整的生命周期管理能力

实施项：

- 新增 `TemplateValidationService`
- 新增 `TemplateSyncService`
- 保存时统一解析 `SOUL.md`、更新 `template.json`
- 发布时重建 `AGENTS.md`、更新 `lineage.json`、写入新 revision
- 实现草稿目录到正式模板资产目录的原子提交

建议关注文件：

- 新增 `Multi-Agent-Flow/Sources/Services/TemplateValidationService.swift`
- 新增 `Multi-Agent-Flow/Sources/Services/TemplateSyncService.swift`
- `Multi-Agent-Flow/Sources/Services/TemplateFileSystem.swift`
- `Multi-Agent-Flow/Sources/Services/AgentTemplateLibraryStore.swift`

验收标准：

- 保存草稿不会污染正式模板资产目录
- 发布后 revision 递增
- `template.json`、`SOUL.md`、`AGENTS.md` 状态一致
- 有阻断性 error 时不可发布

### Phase 7：接入导入预检、冲突提示与工作区操作入口

目标：

- 将现有模板资产目录导入能力与新工作区打通
- 保留目录级预检与冲突提示

实施项：

- 复用现有 `preflightImportTemplateAssets`
- 在模板库或工作区中展示导入预检结果
- 保留模板 ID、名称、identity 冲突说明
- 保留“导入后成为独立模板资产”的提示

建议关注文件：

- `Multi-Agent-Flow/Sources/Services/AgentTemplateLibraryStore.swift`
- `Multi-Agent-Flow/Sources/Views/PropertiesPanelView.swift`
- 新工作区导入导出页

验收标准：

- 用户能在新工作区完成模板资产目录导入
- 冲突提示完整保留
- 导入后模板可立即在工作区中打开查看

### Phase 8：体验打磨与回归测试

目标：

- 提升编辑流畅性与可靠性
- 完成回归验证

实施项：

- 增加未保存提示、未发布提示、脏文件提示
- 优化文件切换与模板切换行为
- 补充单元测试与集成测试
- 清理旧模板表单路径中的重复逻辑

验收标准：

- 用户能清楚知道当前修改、校验和发布状态
- 核心流程具备测试覆盖
- 旧入口不再与新工作区形成双轨冲突

## 5. 建议实现顺序

建议按以下顺序执行：

1. 先做 Phase 1，建立草稿目录和草稿会话，这是所有后续编辑能力的基础。
2. 再做 Phase 2 和 Phase 3，先把文件树和工作区框架搭起来。
3. 然后做 Phase 4 和 Phase 5，完成核心文件与标准文件编辑能力。
4. 再做 Phase 6，补齐保存、校验、发布和 revision。
5. 最后做 Phase 7 和 Phase 8，完成导入接入、体验打磨和回归测试。

## 6. 代码改造重点

### 6.1 文件系统层

重点关注：

- [TemplateFileSystem.swift](/Users/chenrongze/Desktop/MultiAgentOrchestrator/MultiAgentOrchestrator/Multi-Agent-Flow/Sources/Services/TemplateFileSystem.swift)

需要新增：

- 草稿目录路径规则
- 草稿目录复制与删除
- 单文件读取与写入辅助
- 标准文件补齐
- 原子提交正式模板资产目录

### 6.2 模板库状态层

重点关注：

- [AgentTemplateLibraryStore.swift](/Users/chenrongze/Desktop/MultiAgentOrchestrator/MultiAgentOrchestrator/Multi-Agent-Flow/Sources/Services/AgentTemplateLibraryStore.swift)

需要新增：

- 模板会话打开与关闭
- 草稿保存与放弃
- 发布模板
- revision 与状态刷新

### 6.3 模板语义与校验层

重点关注：

- [AgentTemplates.swift](/Users/chenrongze/Desktop/MultiAgentOrchestrator/MultiAgentOrchestrator/Multi-Agent-Flow/Sources/Models/AgentTemplates.swift)
- [TemplateAssets.swift](/Users/chenrongze/Desktop/MultiAgentOrchestrator/MultiAgentOrchestrator/Multi-Agent-Flow/Sources/Models/TemplateAssets.swift)

需要扩展：

- 模板工作区的校验结果模型
- `SOUL.md` 编辑失败时的错误表达
- 文件级校验与模板级校验整合

### 6.4 UI 层

重点关注：

- [PropertiesPanelView.swift](/Users/chenrongze/Desktop/MultiAgentOrchestrator/MultiAgentOrchestrator/Multi-Agent-Flow/Sources/Views/PropertiesPanelView.swift)

需要新增或重构：

- `TemplateWorkspaceView.swift`
- `TemplateFileTreeView.swift`
- `TemplateFileEditorView.swift`
- `TemplateInspectorView.swift`

## 7. 测试计划

### 7.1 草稿会话测试

- 打开模板时生成草稿目录
- 放弃草稿时清理草稿目录
- 模板切换时不污染其他模板草稿

### 7.2 文件索引测试

- 标准文件顺序稳定
- 缺失文件状态正确
- 只读文件标记正确

### 7.3 `SOUL.md` 编辑测试

- 原文编辑后可正确解析为 `soulSpec`
- 非法 `SOUL.md` 能报错但保留草稿
- 结构化视图与原文视图切换后内容一致

### 7.4 保存与发布测试

- 保存草稿不覆盖正式模板资产目录
- 发布时 revision 正确递增
- `template.json`、`SOUL.md`、`AGENTS.md` 一致
- 有 error 时不能发布

### 7.5 导入导出回归测试

- 模板资产目录导入预检仍可用
- 冲突提示仍可用
- 导出后的模板资产目录结构完整

## 8. 风险与注意事项

### 8.1 风险一：原始文件编辑与结构化编辑打架

应对：

- 明确 `SOUL.md` 为语义主源
- 保存时统一以 `SOUL.md` 解析结果回填结构化索引

### 8.2 风险二：正式模板目录被半成品污染

应对：

- 所有编辑先写草稿目录
- 提交正式目录时使用原子替换

### 8.3 风险三：旧模板表单逻辑与新工作区并存过久

应对：

- 旧表单逐步降级为入口
- 尽快将完整编辑职责迁移到新工作区

## 9. 里程碑定义

建议设定四个可见里程碑：

### M1：模板草稿会话可用

- 模板可在草稿目录中打开
- 可放弃修改

### M2：模板文件树与基础查看可用

- 文件树完整显示
- 只读与缺失状态正确

### M3：核心编辑能力可用

- `SOUL.md` 与 `template.json` 双轨编辑可用
- 其他核心 markdown 可编辑

### M4：发布链路可用

- 校验、保存、发布、revision、导入预检接入完整

## 10. 推荐下一步

建议执行从 Phase 1 开始，先落地模板草稿目录与草稿会话模型。

原因是：

- 这是新编辑器成立的基础
- 也是避免正式模板资产被直接污染的关键防线
- 后续文件树、编辑器、发布流程都依赖这一层
