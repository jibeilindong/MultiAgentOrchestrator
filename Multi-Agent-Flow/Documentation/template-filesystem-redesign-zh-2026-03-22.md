# 面向项目文件系统的模板系统重设计方案

最后更新：2026-03-22
状态：Proposed

## 背景与问题

当前模板系统功能已经比较完整，但它的存储方式和项目文件系统重构后的方向并不一致。

现在实际上存在两套不同的世界：

- 项目的运行态和设计态，已经逐步迁移到 `Application Support/Multi-Agent-Flow/Projects/<project-id>/...` 下面的 managed project root。
- 模板内容仍然集中存放在全局文件 `Application Support/Multi-Agent-Flow/TemplateLibrary/agent-template-library.json` 中。

这会带来几个明显问题：

1. 模板资产不属于项目。
2. 项目无法携带自己的模板历史、模板修订和项目局部 preset。
3. 节点应用模板之后，node-local 设计文件里几乎没有模板血缘信息。
4. 全局的内置模板覆盖会影响未来行为，但这种变化并不会进入项目存储。
5. 模板正文、用户偏好、导入辅助状态都混在一个 store 里。
6. 这和当前文件系统设计里的原则不一致：未来模板复用应该通过 preset，而不是共享 live agent。

因此，需要把模板系统重构成 managed project filesystem 的一等公民，同时继续保持当前的 `node = agent = 1:1` 执行模型不变。

## 必须保持的约束

结合当前代码和文件系统重构计划，下面这些约束不能破坏：

- `.maoproj` 兼容性必须保留。
- `MAProject` 仍然是共享装配模型。
- `node = agent = 1:1 execution unit` 不能变化。
- 模板复用必须通过 preset，而不是共享活体 agent。
- node-local `agent.json`、`binding.json`、OpenClaw workspace 文件仍然是执行侧主表面。
- `SOUL.md` 仍然是 agent 的物化运行产物。

这意味着模板系统不能被设计成“节点直接挂到一个可变模板对象上”，否则会和现在的设计方向冲突。

## 重设计目标

本次重设计的目标不是做一个更复杂的 prompt 模板引擎，而是把模板系统变成：

- 可分层管理
- 可进入项目存储
- 可追踪来源和修订
- 可与 node-local agent 物化状态协同
- 可兼容现有 `.maoproj` 和 UI 语义

## 核心设计原则

### 1. 模板内容与偏好状态分离

模板正文和用户偏好不是同一种资产，不应该继续存放在同一个快照文件里。

模板内容包括：

- 内置模板
- 用户自定义模板
- 项目模板
- 从 SOUL 导入得到的模板

偏好状态包括：

- 收藏
- 最近使用
- 选择器排序
- 自定义功能描述候选

### 2. 引入 system / user / project 三层作用域

新的模板体系分成三层：

- System scope
  - 应用内置模板目录，只读
- User scope
  - 用户个人可复用 preset 和模板选择偏好
- Project scope
  - 当前项目拥有的模板资产，存放在项目自己的 managed root 下

### 3. 保持“模板应用后物化”的语义

模板应用到节点时，仍然应该把内容物化到 node-owned agent 上。

也就是说：

- 节点不共享 live template
- 节点只记录它来自哪个模板修订
- 节点上的 agent 之后仍然可以独立编辑

模板在这里是“带血缘信息的 preset”，不是“运行时继承链”。

### 4. 血缘信息必须显式可见

无论是项目模板本身，还是由模板创建出来的节点，都应该能回答几个问题：

- 这个模板从哪里来
- 当前节点应用的是哪个模板修订
- 节点内容是否已经偏离模板

### 5. 项目需要可自洽、可迁移

managed project 在另一个机器上重新打开时，应该尽量仅依赖项目自身文件就能重建设计上下文。

具体来说：

- 如果一个节点是从模板创建的，那么项目里应该保存它当时使用的模板修订。
- 不能要求目标机器上恰好存在同一个全局模板库，才能理解这个项目的设计来源。

## 新的存储分层

## 一、用户级模板库

用户级模板库仍然放在 Application Support 下，但只负责“个人模板资产 + 个人偏好”。

建议目录：

```text
Application Support/Multi-Agent-Flow/
  Libraries/
    Templates/
      preferences.json
      library.json
      templates/
        <template-id>/
          template.json
          SOUL.md
```

### `preferences.json`

只放用户偏好，不放模板正文：

- favorite template IDs
- recent template IDs
- ordered template IDs
- custom function-description suggestions

### `library.json`

只放轻量索引信息：

- schema version
- template IDs
- last updated at

### `templates/<template-id>/template.json`

这里只保存用户拥有的模板文档：

- 模板正文
- lineage
- revision
- validation 摘要

注意：

- 内置模板不应该复制到这里
- 这里主要用于用户 fork、导入、迁移而来的 preset

## 二、项目级模板库

项目模板库应该成为 `design/` 下的一类正式设计资产。

建议目录：

```text
Application Support/Multi-Agent-Flow/Projects/<project-id>/
  design/
    project.json
    templates/
      library.json
      templates/
        <project-template-id>/
          template.json
          SOUL.md
          lineage.json
    workflows/
      <workflow-id>/
        workflow.json
        nodes/
          <node-id>/
            node.json
            agent.json
            template-binding.json
            openclaw/
              binding.json
              workspace/
                SOUL.md
                AGENTS.md
                USER.md
                IDENTITY.md
                TOOLS.md
                HEARTBEAT.md
                BOOTSTRAP.md
                MEMORY.md
                memory/
                skills/
```

### 为什么要放在 `design/templates/`

因为模板是设计态资产，不是运行态状态。

它：

- 应该和 `project.json`、`workflow.json`、`node.json`、`agent.json` 放在同一层级语义中
- 是项目设计的一部分，而不只是 UI 辅助功能
- 符合当前内部存储把 design asset 逐步拆分到 `design/` 下的方向

## 新的领域模型

## 一、模板文档模型

建议引入显式带修订和血缘信息的模板文档：

```text
ProjectTemplateDocument
- id
- scope: system | user | project
- revision
- displayName
- meta
- soulSpec
- renderedSoulHash
- validation
- lineage
- createdAt
- updatedAt
```

其中：

- `meta` 继续承担分类、摘要、能力标签、颜色等管理信息
- `soulSpec` 继续承担 role / mission / workflow / guardrails 等 SOUL 结构化内容
- `renderedSoulHash` 用来标记当前渲染后的 `SOUL.md` 指纹

## 二、模板血缘模型

建议显式建模模板来源：

```text
TemplateLineage
- sourceScope: system | user | project | imported-soul | imported-openclaw
- sourceTemplateID
- sourceRevision
- sourceProjectID
- importedFromPath
- importedFromSoulHash
- createdReason: built-in-snapshot | fork | import | project-local | migrated-override
```

这样无论是：

- 从内置模板 fork
- 从 SOUL 导入
- 从 OpenClaw 导入
- 从旧全局库迁移

都能追溯来源。

## 三、节点模板绑定模型

节点不应该只保存“当前 agent 长什么样”，还应该保存“它最初是由哪个模板修订物化而来”。

建议新增 node-local 文件：

```text
NodeTemplateBindingDocument
- nodeID
- agentID
- projectTemplateID
- projectTemplateRevision
- sourceScope
- sourceTemplateID
- appliedAt
- materializedSoulHash
- driftStatus: clean | modified | detached | missing-template
- lastCheckedAt
```

### 为什么要单独做 `template-binding.json`

这和当前文件系统分工是统一的：

- `agent.json` 保存节点自有 agent 定义
- `openclaw/binding.json` 保存 OpenClaw 绑定关系
- `template-binding.json` 保存模板绑定和血缘关系

这样比把模板来源偷偷塞进 `agent.json` 更清晰，也更便于后续校验和 UI 展示。

## 四、`agent.json` 的边界

`NodeAgentDesignDocument` 应继续只负责 node-owned agent 的现实状态：

- name
- identity
- description
- capabilities
- color
- timestamps
- OpenClaw definition

它不应该成为模板目录的主存储位置。

如果未来需要附加一些轻量元数据，可以考虑增加：

- `lastTemplateApplicationAt`
- `lastTemplateMaterializedHash`

但这类字段只是补充，真正的模板血缘仍然应由 `template-binding.json` 负责。

## 内置模板行为调整

## 一、当前问题

当前实现允许对内置模板做覆盖，并继续沿用原始模板 ID。这样会导致语义不清：

- 这是应用自带的 built-in 吗
- 这是用户覆盖后的 built-in 吗
- 这是 fork 出来的自定义模板吗

从项目文件系统角度看，这种状态不利于稳定复原。

## 二、新建议

内置模板改成真正只读。

当用户要修改内置模板时，不再做“同 ID 覆盖”，而是明确 fork：

1. fork 到 user scope
2. 或 fork 到 project scope

兼容迁移时，可以把旧版 built-in override 自动转成 user-owned template，并用 lineage 指回原 built-in 模板。

## 模板应用模型

## 一、节点创建或应用模板时的流程

当用户选择一个模板来创建节点，或者将模板应用到一个已有节点时，建议流程如下：

1. 从 system / user / project 三个作用域中解析出选中的模板。
2. 如果当前项目里还没有这个精确修订的模板快照，则先把它快照进 project template library。
3. 把模板内容物化到 node-owned agent：
   - identity
   - description
   - capabilities
   - color
   - 渲染后的 `SOUL.md`
4. 写入 `template-binding.json`。
5. 用当前物化后的 agent 继续生成 node-local OpenClaw workspace 文件。

这样就同时满足：

- 项目内可复原
- 节点执行态独立

## 二、节点后续编辑行为

节点创建后，用户仍然可以继续编辑 agent：

- identity
- description
- capabilities
- `SOUL.md`

这些编辑不应该反向修改源模板，也不应该隐式同步回模板库。

正确行为应是：

- 节点保持为独立物化态
- `template-binding.json` 中的 `driftStatus` 变成 `modified`
- UI 提供明确动作：
  - 重新应用模板
  - 另存为项目模板
  - fork 成用户模板

这样比双向同步安全得多。

## 三、建议的漂移判断逻辑

将节点当前物化内容与绑定模板修订进行比较：

- 如果一致：
  - `clean`
- 如果只是格式变化，语义等价：
  - 仍然算 `clean`
- 如果核心字段发生变化：
  - `modified`
- 如果绑定的项目模板已不存在：
  - `missing-template`
- 如果用户主动断开绑定：
  - `detached`

## 与项目装配流程的关系

## 一、内部装配

`ProjectFileSystem.loadAssembledProject(...)` 仍然可以继续装配成普通 `MAProject`，不需要一上来就改变整个共享模型。

模板相关责任可以拆成：

- `project.json`
  - 继续记录 project 的总体设计信息
- `design/templates/...`
  - 记录项目拥有的模板资产
- `nodes/<node-id>/agent.json`
  - 记录节点物化后的 agent 状态
- `nodes/<node-id>/template-binding.json`
  - 记录模板来源、修订、漂移状态

也就是说，模板可以先作为“managed storage 内部设计资产”存在，而不必在第一阶段就变成 `MAProject` 的核心字段。

## 二、`.maoproj` 兼容策略

这里建议分两级推进。

### Level 1：不改共享模型

先保持 `.maoproj` 结构不变：

- 节点上的 agent 仍然带有完整物化后的 `identity`、`description`、`capabilities`、`soulMD`
- 项目模板库仅存在于 managed project root 中
- 即使导出再导入 `.maoproj`，模板血缘也可以暂时不是一等兼容字段

这是最稳妥的第一阶段。

### Level 2：可选地做加法扩展

后续如果确实需要跨机器携带项目模板资产，再给共享模型增加可选字段，例如：

- `projectTemplateData`
- `nodeTemplateBindings`

但这些字段必须保持 optional，保证旧 `.maoproj` 仍能正常读取。

建议顺序：

1. 先做 Level 1
2. 只有当“项目模板资产也必须进入 `.maoproj`”成为明确需求时，再做 Level 2

## 用户模板库的新定位

重设计后，用户模板库不再是所有模板内容的唯一真相源。

它更适合作为：

- 用户个人 preset 库
- 项目模板的来源之一
- 模板选择器偏好的存放地

而项目不应该依赖某个 user template 在未来是否还保持不变。

## 导入导出流程调整

## 一、从 `SOUL.md` 导入模板

当前“导入 SOUL 生成模板”的能力应拆成两个目标位置：

- 导入到用户模板库
- 导入到当前项目模板库

推荐默认：

- 如果用户在项目内的模板管理器里操作，默认导入到当前项目
- 如果是在全局模板库里操作，默认导入到用户库

## 二、导入 OpenClaw agent

导入 OpenClaw agent 时建议这样处理：

1. 保留现有物化导入行为。
2. 解析导入的 `SOUL.md`。
3. 尝试做模板推荐。
4. 如果用户接受推荐结果：
   - 把对应模板修订快照进项目模板库
   - 写入 `template-binding.json`
5. 如果没有合适模板：
   - 提供“将该 SOUL 保存为项目模板”的入口

这和当前 OpenClaw import 已经把文件镜像进项目 managed copy 的方向是完全一致的。

## 三、模板 JSON 导入导出

JSON 导出也应按 scope 划分：

- user template export
  - 导出用户 preset
- project template export
  - 导出当前项目下的模板资产

项目模板导出应来自 `design/templates/`，而不是全局用户模板库。

## 校验体系重构

模板校验也应该分层。

## 一、模板文档校验

校验模板自身是否合法：

- SOUL 必填章节是否缺失
- 是否含有管理信息泄漏词
- 列表长度是否超标
- lineage 是否非法
- ID / revision 是否冲突

## 二、模板绑定校验

校验项目节点与模板之间的关系是否合法：

- 绑定的项目模板是否存在
- 绑定修订是否存在
- 节点是否已经漂移
- source lineage 是否断裂

## 三、物化结果校验

校验执行侧文件是否和当前节点状态一致：

- `openclaw/workspace/SOUL.md` 是否和 node-owned agent 的物化结果一致
- 渲染后的 SOUL hash 是否匹配 binding 元数据

## 服务拆分建议

当前 `AgentTemplateLibraryStore` 责任过重，建议拆分。

## 一、`SystemTemplateCatalog`

职责：

- 只暴露内置模板
- 不做持久化

## 二、`UserTemplateLibraryStore`

职责：

- 读写用户模板
- 读写模板选择偏好
- 管理 favorites / recents / 自定义功能描述

## 三、`ProjectTemplateStore`

职责：

- 读写 `design/templates/`
- 管理项目模板 revision
- 在模板应用到节点时生成项目快照
- 提供节点模板血缘查询

## 四、`TemplateMaterializationService`

职责：

- 从模板文档渲染 `SOUL.md`
- 将模板应用到 node-owned agent
- 计算 hash 和 drift 状态

## 五、`TemplateMigrationService`

职责：

- 迁移旧版全局模板快照
- 拆分模板内容与偏好数据
- 将 built-in override 转换为 user-owned fork

## `ProjectFileSystem` 需要新增的路径能力

建议在 `ProjectFileSystem` 中补充与模板相关的路径 helper：

```text
designTemplatesRootDirectory(for projectID:)
projectTemplateLibraryURL(for projectID:)
projectTemplateRootDirectory(for templateID:, projectID:)
projectTemplateDocumentURL(for templateID:, projectID:)
projectTemplateSoulURL(for templateID:, projectID:)
nodeTemplateBindingURL(for nodeID:, workflowID:, projectID:)
```

建议的权威路径如下：

```text
Projects/<project-id>/design/templates/library.json
Projects/<project-id>/design/templates/templates/<template-id>/template.json
Projects/<project-id>/design/templates/templates/<template-id>/SOUL.md
Projects/<project-id>/design/workflows/<workflow-id>/nodes/<node-id>/template-binding.json
```

## 迁移计划

## Phase 0：兼容读取旧库

继续兼容读取旧文件：

- `Application Support/Multi-Agent-Flow/TemplateLibrary/agent-template-library.json`

第一次启动迁移时，将其拆分迁移到：

- `Libraries/Templates/preferences.json`
- `Libraries/Templates/library.json`
- `Libraries/Templates/templates/<template-id>/...`

## Phase 1：先做用户侧 service 拆分

将当前 `AgentTemplateLibraryStore` 拆成：

- `SystemTemplateCatalog`
- `UserTemplateLibraryStore`

此阶段先不引入项目模板存储。

## Phase 2：引入项目模板存储

新增：

- `design/templates/`
- `template-binding.json`
- apply template 时自动 snapshot into project

## Phase 3：做漂移感知 UI

在编辑器中显示节点与模板关系：

- 来自 system / user / project 的哪个模板
- 当前是 clean 还是 modified
- 支持 reapply
- 支持 fork 为项目模板
- 支持保存当前节点为模板

## Phase 4：按需扩展 `.maoproj`

只有在“项目模板资产也必须随 `.maoproj` 一起便携”成为真实需求时，再考虑做共享模型加法扩展。

## UI 层面的改造建议

## 一、模板选择器

模板选择器应该显式展示模板来源作用域：

- System
- User
- Project

推荐分组：

- 推荐
- 最近
- 收藏
- 当前项目模板
- 用户 preset
- 内置模板

## 二、模板管理器

建议把当前模板管理器拆成两个入口：

- User Template Library
- Project Template Library

支持操作：

- fork 内置模板到 user
- fork 内置模板到 project
- 导入 SOUL 到 user / project
- 把当前节点提升为项目模板
- 导出项目模板包

## 三、Agent 检视区

在 SOUL 编辑区域旁边显示模板血缘信息：

- 当前来自哪个模板
- 哪个 revision
- 当前 drift 状态

并提供动作：

- 重新应用模板
- 断开模板绑定
- 将当前节点另存为模板

## 本仓库建议采用的最终方案

结合当前代码和文件系统方向，建议采用以下具体决策：

1. 内置模板改为只读，不再允许同 ID override。
2. 用户偏好从模板正文快照中拆出。
3. 项目模板统一落在 `design/templates/`。
4. 模板应用到节点时，先快照到项目，再物化到 node-owned agent。
5. 节点模板来源记录在 `template-binding.json`。
6. 节点在模板应用后仍然允许独立编辑。
7. 第一阶段不修改 `.maoproj` 共享模型。

## 这个方案的收益

采用该方案后：

- 模板系统和 managed project filesystem 的方向完全对齐
- 项目不再依赖一个可变的全局模板库才能理解设计来源
- 节点可以明确知道自己来自哪个模板修订
- 内置、用户、项目三类模板不会再混在一起
- OpenClaw 导入和 SOUL 导入都能自然沉淀为项目资产
- 也更利于未来 Electron 迁移

## 主要代价与取舍

这套方案的主要代价是“会有重复”。

同一个模板可能同时存在于：

- system scope
- user scope
- project scope

但这种重复是刻意保留的，换来的好处是：

- 可复原
- 可追踪
- 项目隔离
- 不会出现跨项目隐式共享带来的污染

对当前这个仓库来说，这个取舍是值得的，因为整个文件系统重构本来就在朝“显式 managed copy 优于隐式外部引用”这个方向演进。
