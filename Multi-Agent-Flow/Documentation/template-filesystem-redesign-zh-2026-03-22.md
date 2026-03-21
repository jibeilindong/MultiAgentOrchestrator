# 面向文件系统架构的 Agent 模板系统重设计方案

最后更新：2026-03-22
状态：Proposed

## 方案目标

本次重设计要让模板系统与本软件的文件系统架构保持一致，并严格遵守以下产品原则：

1. 模板与项目完全解耦，项目中不包含模板元数据、模板绑定、模板修订或模板快照。
2. 模板是一种标准化资产，可以流通、复用、fork、扩展、二次开发，也可以从零创建。
3. 模板系统必须遵从本软件的文件系统设计，不能继续停留在单一全局 JSON 快照的形态。
4. 本方案中的模板特指 agent 模板，不包括工作流模板。
5. 作为标准化 agent 模板，要求相关文件、路径和内容都必须具备，并且尽可能完整、充实、标准。
6. 模板文件绝对不能参与工作流。只有从模板复制并物化出来的 agent，才能进入工作流。

这意味着，本方案不再走任何“项目内模板库”或“项目持有模板绑定”的路线，而是转为“独立模板资产库”路线。

## 当前问题

现在模板系统虽然可用，但存储模型和整个应用正在推进的文件系统架构并不一致。

当前实际上存在两套不同的存储世界：

- 项目的设计态和运行态，正在迁移到 `Application Support/Multi-Agent-Flow/Projects/<project-id>/...` 下面的 managed project root。
- 模板内容仍然集中放在单个全局文件里：
  - `Application Support/Multi-Agent-Flow/TemplateLibrary/agent-template-library.json`

这会带来几个问题：

1. 模板不是一等文件系统资产。
2. 模板正文、用户偏好、导入辅助状态混在一起。
3. 模板很难被稳定地打包、流通、版本化、扩展。
4. 模板存储方式与当前 managed-storage 方向不统一。
5. 项目容易看起来依赖本机当前的全局模板状态。
6. 当前模型没有严格保证“模板本身应该是完整标准 agent 包”的要求。

## 必须保留的约束

本次重设计仍然必须保留以下约束：

- `.maoproj` 兼容性
- `MAProject` 继续作为共享装配模型
- `node = agent = 1:1 execution unit`
- 当前 node-local agent 物化逻辑
- `SOUL.md` 继续作为执行侧物化产物

换句话说：

- 模板可以参与 agent 创建
- 但模板不能变成运行时共享 live object
- 项目继续只保存物化后的 agent 状态，而不是模板状态

## 核心原则

## 1. 项目与模板完全解耦

项目必须与模板资产完全解耦。

项目应保存：

- node-owned agent 状态
- workflow 状态
- runtime 状态
- OpenClaw 状态

项目不应保存：

- template ID
- template revision
- template binding
- 模板库
- 模板资产快照
- 模板文件在工作流中的任何参与信息

因此，模板应用必须被视为一次严格的单向物化动作：

- 用户选择模板
- 编辑器复制模板内容到 agent 草稿
- 项目中只保存最终物化出来的 node-owned agent 状态

## 2. 模板是标准化的 agent 资产

模板不应只是“编辑器里的一个选项”或“局部提示词片段”，而应是一类真正可管理、可流通的软件资产。

模板资产必须支持：

- 从零创建
- 从 `SOUL.md` 导入
- 从 OpenClaw 产物导入
- 导出为可移植 package
- fork 与二次开发
- 版本与修订
- 校验与测试

## 3. 模板遵从文件系统设计

模板系统应遵从本软件现有的文件系统设计哲学：

- 明确的根目录
- 清晰的 manifest
- 拆分后的文档结构
- 稳定 ID
- 源文档与生成产物分离
- 可预测的路径结构

因此，模板不能继续只是一个大 JSON 文件，而应演进为一个正式的 managed asset library。

## 4. 模板必须是完整标准文件集

每个模板都应代表一个完整的标准 agent 包，而不是只有 `template.json` 加一段 prompt。

这意味着：

- 必需文件要齐全
- 必需路径要稳定
- 配套文档要存在
- 内容要尽可能完整、标准、充实

目标是：编辑器复制模板后，如果用户不做任何修改，就已经得到一个可直接使用的标准 agent。

## 5. 复制后立即彻底断联

模板使用必须遵循“复制，然后完全断联”的模型。

当用户应用模板时：

- 编辑器复制模板内容到新的或已有的 agent 草稿
- 复制结果变成普通 node-owned agent
- 用户后续对该 agent 的修改，只属于该 agent
- 这个 agent 与源模板不再有任何关系

当用户将一个 agent 保存为模板时：

- 系统创建一套新的模板资产文件
- 新模板与原 agent 不保留 live relation
- 原 agent 仍然只是 agent

这条规则必须绝对成立：

- 模板不追踪 agent
- agent 不追踪模板

## 6. 模板绝不参与工作流

模板与工作流完全独立。

模板可以被编辑器拿来作为“创建 agent 的源材料”，但：

- 模板文件不是 workflow node
- 模板文件不是 workflow resource
- 模板文件不是 runtime participant
- 模板文件不会作为 workflow state 的一部分保存

只有从模板复制并物化出来的 agent 才能参与工作流。

## 总体架构

新的模板系统建议拆成三层：

- System catalog
  - 应用内置模板，只读
- User library
  - 用户拥有的模板资产和用户偏好
- Exchange package
  - 用于流通、导入导出、二次开发的模板包

这里特别强调：

- 不再引入 project template scope

项目只消费模板生成的结果，不持有模板本体。

## 作用域模型

## 一、System scope

System scope 用于保存应用内置模板。

特征：

- 只读
- 跟随应用版本
- 不允许原地修改
- 允许 fork 到用户模板库

## 二、User scope

User scope 用于保存用户自己的模板资产。

特征：

- 可编辑
- 可版本化
- 可导入导出
- 可从内置模板或其他用户模板 fork
- 可作为 agent 物化的来源

## 三、Exchange scope

Exchange scope 不是运行时 store，而是一种打包形态。

它用于：

- 模板流通
- 跨机器迁移
- 审阅与共享
- 二次开发
- 将来的模板仓库或 marketplace 能力

## 文件系统布局

## 一、内置模板目录

内置模板应以只读资产形式存在于应用 bundle 或其生成缓存中。

概念结构建议如下：

```text
System Templates/
  manifest.json
  templates/
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
```

具体物理位置可以根据实现决定，但结构上应遵循 managed asset 的形式。

## 二、用户模板库

用户模板库应成为唯一可变、可持续演化的模板主库。

建议位置：

```text
Application Support/Multi-Agent-Flow/
  Libraries/
    Templates/
      manifest.json
      preferences.json
      indexes/
        tags.json
        capabilities.json
        search.json
      templates/
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

### 为什么采用这种结构

因为这样每个模板都会拥有自己的独立目录，而不是作为某个大 JSON 文件里的一行数据存在。

这样做的好处是：

- 每个模板有稳定的 asset root
- 修订历史可以自然追加
- 扩展材料有自己的归宿
- 导入导出更简单
- 后续可以做基于资产的 tooling
- 每个模板都可以成为一套完整标准 agent 包

## 三、可移植模板包

模板应支持可移植的 package 格式，便于打包、复制、审阅、共享和导入。

建议解包后结构如下：

```text
template-package/
  package.json
  templates/
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
      extensions/
```

这样模板就可以独立流通，而不依赖某个具体项目。

## 重设计后项目保存什么

重设计后，项目仍然只保存物化后的设计态和运行态内容。

项目保留：

- `agent.json`
- node-local OpenClaw workspace 文件
- 物化后的 `SOUL.md`
- workflow 状态
- runtime 状态

项目不保留：

- template-binding 文件
- template revision 信息
- template lineage 信息
- 项目级模板目录
- 回指模板资产的 live link

这就是“项目与模板完全解耦”的严格落地方式。

## 模板应用模型

## 一、单向物化

模板应用到节点时建议按下面的方式工作：

1. 从 system 或 user scope 中解析出选中的模板。
2. 编辑器先把模板复制为一个标准 agent 草稿。
3. 将模板文件和字段物化到 node-owned agent：
   - identity
   - description
   - capabilities
   - color
   - 渲染后的 `SOUL.md`
   - 编辑器/运行时表面需要的标准配套文档
4. 项目中只保存这个物化后的 agent 状态。
5. 再基于该 agent 继续生成 node-local OpenClaw workspace 文件。

项目里不保存模板引用。

## 二、应用后的节点状态

节点一旦创建完成：

- 它就是独立的
- 后续编辑不会影响源模板
- 若要再次使用模板，必须由用户显式触发“重新应用”
- 如果用户不做修改，这个结果本身就应该已经是可直接使用的标准 agent

这与当前“模板是源资产，不是 live dependency”的方向一致。

## 在不耦合项目的前提下处理血缘

由于项目中不应保存模板信息，所以模板血缘不应写入项目。

推荐做法是：

- 模板血缘保存在模板资产内部
- 编辑器如果需要记录最近应用历史，可放在用户侧辅助状态里
- 项目里只保存物化后的结果

如果将来产品确实需要审计或追溯，也应优先作为用户侧 editor state，而不是项目持久化的一部分。

## 模板文档模型

每个模板资产建议使用类似下面的文档结构：

```text
TemplateAssetDocument
- id
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

- `meta` 负责管理字段
- `soulSpec` 负责结构化 SOUL 源内容
- `renderedSoulHash` 记录当前渲染出的 `SOUL.md` 指纹
- `lineage` 记录模板来源和 fork 历史

这个文档只是结构化索引和规格入口，不替代其余标准模板文件集。

## 标准模板文件集

每个模板资产都应带有一套完整的标准 agent 模板文件集。

最低建议文件集：

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
```

规则：

- 必需文件必须齐全
- 路径必须稳定、可预测
- 内容应尽可能完整、充实、标准
- 除非明确标记为 draft，否则应避免只包含占位内容的模板

## 模板血缘模型

建议模板资产使用类似以下的 lineage 结构：

```text
TemplateLineage
- sourceScope: system | user | imported-soul | imported-openclaw | imported-package
- sourceTemplateID
- sourceRevision
- importedFromPath
- importedFromSoulHash
- createdReason: built-in-fork | new-from-scratch | soul-import | package-import | migrated-legacy
```

这样就能支持：

- 从内置模板 fork
- 从已有模板 fork
- 从 SOUL 导入
- 从 OpenClaw 导入
- 从旧版全局快照迁移

同时不需要把任何模板信息写入项目。

## 内置模板行为调整

## 一、内置模板必须真正只读

内置模板只允许：

- 查看
- 应用
- fork 到用户模板库

内置模板不应再支持：

- 原地编辑
- 在可变 store 里以相同 ID 做 override

## 二、旧版 built-in override 的迁移方式

旧版全局快照中的 built-in override，不再保留“原 ID 覆盖”语义，而应在迁移时转成：

- 用户模板库中的 forked asset

并在 lineage 中记录它来自哪个 built-in。

## 模板创建模型

模板应支持四种主要创建路径。

## 一、从零创建

用户可以直接在用户模板库里创建空白模板资产。

即使从零创建，结果也应该被扩展成完整的标准模板文件集，而不是停留在一个零散 prompt stub 上。

## 二、从 `SOUL.md` 创建

将独立的 `SOUL.md` 导入并生成模板资产。

推荐输出：

- 结构化 `template.json`
- 渲染后的 `SOUL.md`
- 标准配套文档
- `lineage = imported-soul`

## 三、从已有模板 fork

把内置模板或用户模板 fork 成新的用户模板资产。

推荐输出：

- 新 asset ID
- 新 revision
- 完整标准文件集
- lineage 指向来源模板和来源 revision

## 四、从现有 agent 另存为模板

编辑器还应支持将一个现有 agent 保存成新的模板资产。

规则：

- 系统创建一套新的模板资产文件
- 新模板与原 agent 完全独立
- 原 agent 仍然只是 agent
- 不保留反向关联

## 模板二次开发模型

为了支持模板资产的持续演化和二次开发，建议每个模板目录允许携带扩展材料：

- `README.md`
- examples
- tests
- assets

这样模板就不只是一个“提示词/规范对象”，而可以成长为一组可复用的标准化能力资产。

二次开发也必须继续遵守一个前提：

- 模板资产始终不进入工作流

## 校验体系调整

重设计后，校验的对象应是模板资产本身，而不是项目内的模板副本。

校验项建议包括：

- SOUL 必填章节
- 必需标准文件是否存在
- 必需路径是否合法
- 配套文档是否缺失
- 管理信息泄漏词
- 列表项数量提醒
- ID / revision 合法性
- lineage 一致性
- 可选扩展材料完整性

校验不应再默认模板和项目耦合。

## 导入导出流程调整

## 一、导入 `SOUL.md`

导入目标应改成：

- 用户模板库

而不是：

- 当前项目

项目后续当然仍然可以使用该模板去创建 agent，但这个模板本身属于模板库，而不是项目。

## 二、导入 OpenClaw 产物

当导入一个 OpenClaw agent 后，如果其 `SOUL.md` 有价值，可以让用户选择：

- 只把它物化成项目里的 agent
- 或同时保存为用户模板库中的新模板资产

如果保存为模板，系统应把它规范化成完整标准模板文件集，而不是只保存一个孤立的 `SOUL.md`。

## 三、模板包导出

导出应从用户模板资产生成一个可移植 package。

这个 package 适用于：

- 模板流通
- 备份
- 审阅
- 二次开发
- 将来接入模板仓库

## 服务拆分建议

当前 `AgentTemplateLibraryStore` 承担的责任过多，建议拆分为下面几类服务。

## 一、`SystemTemplateCatalog`

职责：

- 暴露只读 built-in templates
- 不做可变持久化

## 二、`UserTemplateLibraryStore`

职责：

- 读写用户模板资产
- 读写用户偏好
- 管理 favorites / recents / picker order
- 管理模板包导入导出

## 三、`TemplateAssetService`

职责：

- 从零创建模板
- fork 模板
- 将 agent 保存为模板
- 解析与生成 `SOUL.md`
- 生成完整标准文件集
- 维护 revision 和 lineage
- 执行模板校验

## 四、`TemplateMaterializationService`

职责：

- 将模板应用到 agent 草稿
- 渲染物化后的 `SOUL.md`
- 生成编辑器/运行时表面所需的标准配套文档
- 返回纯净的 agent 状态
- 不向项目注入模板元数据

## 五、`TemplateMigrationService`

职责：

- 迁移旧版大 JSON 快照
- 拆分模板正文与偏好状态
- 将旧 built-in override 转为用户 fork 模板

## 文件系统能力补充建议

由于模板现在不应属于项目，所以路径能力不应继续塞进 `ProjectFileSystem`。

更合理的做法是新增一个专门的 `TemplateFileSystem`。

建议 helper 如下：

```text
templateLibraryRootDirectory()
templateManifestURL()
templatePreferencesURL()
templateIndexesRootDirectory()
templateRootDirectory(for templateID:)
templateDocumentURL(for templateID:)
templateSoulURL(for templateID:)
templateAgentsURL(for templateID:)
templateIdentityURL(for templateID:)
templateUserURL(for templateID:)
templateToolsURL(for templateID:)
templateBootstrapURL(for templateID:)
templateHeartbeatURL(for templateID:)
templateMemoryURL(for templateID:)
templateLineageURL(for templateID:)
templateRevisionDirectory(for templateID:)
```

这能让模板资产遵从本软件文件系统设计，同时又不污染项目存储。

## 迁移计划

## Phase 0：兼容读取旧库

继续兼容读取旧版文件：

- `Application Support/Multi-Agent-Flow/TemplateLibrary/agent-template-library.json`

## Phase 1：存储拆分

将旧数据迁移到新的模板库结构：

```text
Application Support/Multi-Agent-Flow/Libraries/Templates/
  manifest.json
  preferences.json
  templates/<template-id>/...
```

迁移规则：

- built-in override -> user-owned fork asset
- custom template -> user-owned asset
- favorites / recents / order -> `preferences.json`
- 零散旧模板统一规范化为标准文件集

## Phase 2：替换服务层

用下面这些新服务替换 `AgentTemplateLibraryStore`：

- `SystemTemplateCatalog`
- `UserTemplateLibraryStore`
- `TemplateAssetService`
- `TemplateMaterializationService`

## Phase 3：模板包导入导出

引入标准化模板 package，支持资产级 import/export。

## Phase 4：支持二次开发材料

允许模板目录中携带：

- `extensions/`
- `examples/`
- `tests/`

## UI 影响

## 一、模板选择器

选择器中应展示：

- built-in templates
- user templates
- favorites
- recents
- recommendations

但不应暗示“模板属于当前项目”。

## 二、模板管理器

模板管理器应转型为“用户模板库管理器”。

主操作：

- 从零创建
- 从内置模板或已有模板 fork
- 导入 `SOUL.md`
- 导入 package
- 将 agent 保存为模板
- 导出 package
- 校验模板资产

## 三、Agent 检视区

Agent 检视区仍然可以支持：

- 选择模板
- 应用模板
- 手动重新应用模板

但这些动作不应在项目持久化层中留下模板绑定信息。

一旦应用完成，检视区里显示的就只是普通 agent，而不再是“模板实例”。

## 对本仓库的推荐落地决策

结合当前仓库方向，建议采用以下具体决策：

1. 从方案中移除 project-owned template storage。
2. 项目中不保存任何模板元数据。
3. 模板统一视为系统/用户侧的标准化资产。
4. 新增独立的 `TemplateFileSystem`，而不是扩展 `ProjectFileSystem`。
5. 内置模板只读，只允许 fork。
6. 每个 agent 模板资产都必须带有完整标准文件集，而不只是 `template.json + SOUL.md`。
7. 模板应用必须是“复制后立即断联”的单向物化动作。
8. 模板绝不参与工作流持久化或运行时参与。
9. 第一阶段不修改 `.maoproj`。

## 方案收益

采用此方案后：

- 模板与项目彻底解耦
- 模板成为可流通、可扩展的标准化资产
- 文件系统模型更统一、更清晰
- 项目仍然专注于物化后的设计态和运行态
- 模板流通与二次开发成为可能
- 编辑器复制模板即可直接得到一个标准可用的 agent

## 主要取舍

这套方案最大的代价，是项目侧模板血缘信息会减少。

因为项目不保存模板信息，所以：

- 重新打开项目时，系统无法仅靠项目文件精确知道某个节点最初来自哪个模板，除非再从 agent 内容反推

这是“严格解耦”带来的必然结果。在新的原则下，模板资产的标准化、完整性、可流通性和与工作流的绝对隔离，优先级高于项目内模板血缘记录。
