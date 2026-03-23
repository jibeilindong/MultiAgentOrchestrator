# Workflow 编辑器 Mirror-Only 升级执行计划

Last updated: 2026-03-22
Status: Draft for review

## 1. 目标

将 Workflow 编辑器升级为一个以设计态为核心、以 node-local managed workspace 为唯一配置编辑面的可视化编辑器。

本计划围绕三条主线展开：

- Draft / Save / Apply 语义重整
- 统一 workflow 结构编辑管线
- Mirror-only 的节点本地 override 配置编辑

## 2. 实施原则

- 尽量复用当前受管文件系统结构
- 不引入“编辑源文件”和“同步源文件”的新复杂度
- 不把 runtime 能力重新耦合回编辑器
- 先收口语义，再补交互，再补全覆盖面
- 每一阶段都要有独立可验收结果

## 3. 分阶段计划

### Phase 0：语义收口与文档对齐

目标：

- 统一产品、研发、README 的口径
- 明确 mirror 的产品定义
- 明确 workflow 编辑器不负责执行

实施项：

- 更新 workflow 编辑器相关文档
- 更新 `openclaw-soul-sync` 相关说明，避免继续使用“源文件同步器”口径
- 梳理界面文案，替换容易混淆的 mirror / workspace / source 表述

验收标准：

- 文档中不再把 `openclaw/mirror/` 误写为用户编辑目录
- 文档中明确 `openclaw/workspace/` 是节点本地受管有效副本
- 文档中明确 Save 与 Apply 的职责边界

### Phase 1：统一 Draft / Save / Apply 状态模型

目标：

- 修正“保存草稿”和“应用配置”混杂的问题
- 确保保存 `.maoproj` 时不会漏掉当前 draft 中的 workflow 设计修改

实施项：

- 清理 current draft、saved snapshot、applied snapshot 的职责
- 统一 pending / applied revision 的更新时机
- 保存时始终以当前 draft 为准
- Apply 时始终以当前 draft 与 node-local managed workspace 为准
- UI 增加未保存与未应用的状态提示

验收标准：

- 结构修改后直接 Save，不会丢失设计变更
- 配置修改后 Save 与 Apply 可分别进行
- UI 能清楚显示 `Unsaved` 与 `Apply pending`

### Phase 2：统一 workflow 结构编辑管线

目标：

- 所有结构编辑行为走同一条 mutation pipeline
- 消除复制、粘贴、删除、跨视图编辑的不一致

实施项：

- 统一节点新增、复制、粘贴、删除入口
- 统一边清理与绑定清理
- 统一 start 节点唯一性校验
- 删除旁路逻辑，避免绕开标准清理流程
- List / Grid / Canvas 共用同一套结构修改语义

验收标准：

- Paste 不会产生重复 start 节点
- 任意视图下删除节点都不会残留脏边
- 节点与 agent 绑定关系保持一致

### Phase 3：建立节点本地配置文件索引

目标：

- 将配置编辑范围从单一 `SOUL.md` 扩展到当前 agent 范围内所有定义型 markdown 文件

实施项：

- 基于 node-local `openclaw/workspace/` 生成受管文件索引
- 定义允许展示和编辑的文件白名单
- 明确文件展示顺序与默认打开文件
- 为缺失文件建立受管创建策略

建议首批支持：

- `SOUL.md`
- `AGENTS.md`
- `IDENTITY.md`
- `USER.md`
- `TOOLS.md`
- `HEARTBEAT.md`
- `BOOTSTRAP.md`
- `MEMORY.md`

验收标准：

- 进入节点配置时能稳定列出当前 agent 的受管 markdown 文件
- 不会越权访问其他 agent 或任意本机路径
- 缺失文件可在当前 agent 范围内受管创建

### Phase 4：Mirror-only 配置编辑器落地

目标：

- 把配置编辑收口到节点本地 override 模式

实施项：

- 配置面板读取 node-local managed workspace 文件
- 编辑时直接更新本地受管副本
- 节点切换和文件切换时保留编辑态
- 将“编辑源文件”“刷新源文件”“同步源文件”等旧入口逐步移除或降级
- Apply 前汇总待生效文件变更

验收标准：

- 编辑器中所有配置编辑都只写入 node-local managed workspace
- 编辑阶段不再依赖外部源文件存在
- Apply 时能把所有已编辑文件统一推送

### Phase 5：节点标题与身份规则收口

目标：

- 让节点身份表达稳定且无歧义

实施项：

- 取消 agent 节点标题编辑
- 节点标题统一绑定为 agent 名称
- agent 改名时统一刷新节点展示标题
- 复制、导入、重绑定时复用同一规则

验收标准：

- 节点标题不能单独编辑
- 节点标题始终与 agent 名称一致

### Phase 6：用户体验与便捷性打磨

目标：

- 降低理解成本，提高编辑效率与流畅性

实施项：

- 增加节点级配置入口与常用文件快捷入口
- 优化文件切换与节点切换反馈
- 增加待 Apply 变更计数
- 增加错误态与恢复态提示
- 优化大文件或缺失文件时的状态反馈

验收标准：

- 用户能快速理解“当前改了什么、还差什么、何时生效”
- 高频编辑路径的操作步数明显降低
- 常见错误有明确反馈与恢复路径

## 4. 建议实现顺序

建议按以下顺序执行：

1. 先做 Phase 1，修正 Save / Apply 数据语义，避免后续编辑能力建立在错误状态模型上
2. 再做 Phase 2，统一结构编辑入口，先稳住 workflow 结构层
3. 然后做 Phase 3 和 Phase 4，扩展并收口配置编辑模型
4. 最后做 Phase 5 和 Phase 6，完成身份规则与体验打磨

## 5. 代码改造关注点

### 5.1 状态与应用层

重点关注：

- `AppState.swift`
- workflow draft / snapshot / apply revision 相关逻辑
- pending workflow configuration 相关逻辑

### 5.2 文件系统与路径解析层

重点关注：

- `ProjectFileSystem.swift`
- node-local `openclaw/workspace/` 路径工具
- 受管文件列表与默认文件规则

### 5.3 OpenClaw 同步层

重点关注：

- `OpenClawManager.swift`
- Apply 时如何批量读取 node-local managed workspace 并推送
- 清理“源文件同步器”思维残留

### 5.4 Workflow 编辑器 UI 层

重点关注：

- `WorkflowEditorView.swift`
- 节点详情面板 / 配置面板
- 视图切换下的一致编辑语义

## 6. 测试计划

### 6.1 状态语义测试

- 结构改动后 Save，不丢 workflow 设计
- 配置改动后 Save，不自动 Apply
- Apply 成功后 applied revision 正确刷新

### 6.2 文件系统测试

- 所有定义型 markdown 文件都落在 node-local `openclaw/workspace/`
- `openclaw/mirror/` 继续只保存元数据
- 越界路径选择被拦截

### 6.3 结构编辑回归测试

- 复制粘贴不会生成重复 start 节点
- 删除节点时边与绑定同步清理
- 多视图下编辑结果一致

### 6.4 配置编辑测试

- 当前 agent 范围内文件可列出、可切换、可编辑
- 缺失文件可受管创建
- 编辑内容保存后可重新打开读取
- Apply 时全部已编辑文件一并生效

## 7. 风险与应对

### 风险一：mirror 术语继续混淆

应对：

- 在代码注释、文档、UI 文案里统一写成 node-local managed workspace
- 只在产品说明中保留“mirror 内容”这个抽象词，并加明确定义

### 风险二：旧逻辑继续从外部源文件回读

应对：

- 配置编辑入口统一先查 node-local managed workspace
- 将外部源文件读取降级为导入或初始化路径，而不是编辑主路径

### 风险三：Apply 与 Save 仍有交叉副作用

应对：

- 分离状态更新时机
- 为 Save / Apply 分别增加回归测试

## 8. 完成定义

当以下条件全部满足时，本轮升级视为完成：

- Workflow 编辑器文档和 UI 均明确其职责是设计而非执行
- Save 与 Apply 语义完全分离
- 所有结构编辑走统一 mutation pipeline
- 节点标题固定为 agent 名称
- 配置编辑只作用于 node-local managed workspace
- 当前 agent 范围内全部定义型 markdown 文件可编辑
- Apply 统一推送所有已编辑 mirror 内容到 OpenClaw
