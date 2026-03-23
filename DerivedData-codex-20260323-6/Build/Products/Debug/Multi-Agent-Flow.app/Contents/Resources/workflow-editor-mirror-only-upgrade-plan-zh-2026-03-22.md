# Workflow 编辑器 Mirror-Only 升级方案

Last updated: 2026-03-22
Status: Draft for review

## 1. 文档目的

本文档用于固化 Workflow 编辑器的升级方向，作为后续 README、产品说明、实现拆解与验收标准的统一依据。

本文档只讨论 Workflow 编辑器的设计态能力，不讨论执行、运行、调试或测试控制台能力。

## 2. 核心设计逻辑

Workflow 编辑器的核心目的，是帮助用户设计、搭建流程，并高效、可视化地编辑 workflow 与 agents。

因此，编辑器必须围绕以下原则设计：

- 核心职责是设计，不是执行
- 核心价值是可视化、高效、便捷、稳定地完成流程搭建
- 编辑行为必须尽可能低风险、可理解、可撤销
- 配置编辑必须服务于节点搭建，而不是演变成通用文件同步器

对应地，Workflow 编辑器不再承担以下职责：

- 不负责执行 workflow
- 不负责在编辑器内模拟 runtime
- 不负责把“运行反馈”作为主要交互主线
- 不将外部 OpenClaw 文件系统作为实时双向同步对象

## 3. 关键术语定义

### 3.1 Mirror 内容

本文档中的“mirror 内容”，统一指：

- 节点下那份本地受管
- 仅用于编辑与 apply 的有效副本
- 当前文件系统中实际落于 node-local `openclaw/workspace/` 文档集合

这是一层产品语义，不等于字面上的 `openclaw/mirror/` 目录。

### 3.2 受管编辑面

每个 agent 节点都有一份节点本地受管编辑面，对应：

- `design/workflows/<workflow-id>/nodes/<node-id>/openclaw/workspace/`

该目录中的内容，是 Workflow 编辑器唯一直接编辑的配置面。

### 3.3 Apply

Apply 指将当前 workflow 中所有待生效的结构修改与节点本地 mirror 修改，统一推送到 OpenClaw。

Apply 不是“边改边同步”。
Apply 是一次显式的、批量的、可感知的生效动作。

## 4. 与当前文件系统的适配结论

当前文件系统已经具备承载 mirror-only 编辑模型的基础，不需要推翻重做。

### 4.1 已适配的部分

当前重构文档与实现已经明确：

- node-local managed OpenClaw workspace 是一等存储面
- 读侧优先解析 node-local managed workspace artifacts
- apply 不再把 session mirror 路径反写回 project-owned agent state

当前节点下的 OpenClaw 目录结构已经区分为三层：

- `workspace/` 承载实际文档
- `mirror/` 承载 source-map 与 baseline 等元数据
- `state/` 承载导入记录与内部状态

这意味着，“只编辑 mirror 内容”只要被定义为“只编辑节点本地受管有效副本”，就与当前文件系统兼容。

### 4.2 需要避免的误解

不能把“编辑 mirror 内容”解释成：

- 把所有可编辑 markdown 文件移动到 `openclaw/mirror/`
- 在编辑器中直接把 `mirror/` 目录当作文档目录
- 做成一个源文件与项目文件的双向文件同步器

上述解释会与当前结构、测试、读写路径产生冲突。

## 5. 产品边界

### 5.1 编辑器负责什么

- 可视化搭建 workflow 结构
- 节点增删改查
- 连线与结构关系编辑
- agent 受管配置编辑
- 变更暂存、保存、apply
- 通过清晰反馈降低用户的理解成本和误操作成本

### 5.2 编辑器不负责什么

- 执行 workflow
- 启停 agent
- runtime 日志面板
- 运行态调试台
- 远端状态联机诊断
- 外部源文件实时双向同步

## 6. 升级主线

本轮升级只保留三条主线。

### 主线一：统一 Draft / Save / Apply 语义

目标是让用户清楚区分三件事：

- 我现在改的是编辑态草稿
- 我现在保存的是项目草稿文件
- 我现在 apply 的是待生效配置

设计要求：

- 所有 workflow 结构编辑与 agent 配置编辑都先进入当前 draft
- Save 只负责把当前 draft 保存为 `.maoproj`
- Apply 只负责把当前 draft 中已经落在受管 mirror 的内容统一推送到 OpenClaw
- Save 与 Apply 必须可分离，避免用户误以为“保存就等于生效”
- UI 需要明确显示“未保存”和“未应用”是两种不同状态

### 主线二：统一 workflow 结构编辑管线

目标是让所有节点、边、复制、粘贴、删除、重命名限制等行为都经过同一套结构变更管线，避免局部绕路造成脏状态。

设计要求：

- 所有画布结构修改都走统一 mutation pipeline
- 节点新增、复制、粘贴时统一校验 start 节点唯一性
- 删除节点时统一清理边、绑定关系、派生状态
- 节点标题不可编辑，标题固定等于 agent 名称
- agent 节点与 agent 实体的绑定关系必须单向明确
- List / Grid / Canvas 三种视图应共享同一份编辑语义，而不是各自发明一套操作方式

### 主线三：Mirror-Only 的节点本地 override 配置编辑

目标是把 agent 配置编辑从“编辑某个来源文件”改造成“编辑节点本地受管有效副本”。

这是本轮升级的核心配置模型。

## 7. 主线三详细方案

### 7.1 编辑模型

配置编辑只有一种模式：

- 节点本地 override

不再区分：

- 直接编辑源文件
- 编辑项目副本再反向回写源文件
- 编辑 session mirror

用户在编辑器里看到和操作的，永远是该节点自己的本地受管副本。

### 7.2 可编辑范围

可编辑对象不再只限于 `SOUL.md`，而是该 agent 范围内所有定义型 markdown 文件，包括但不限于：

- `SOUL.md`
- `AGENTS.md`
- `IDENTITY.md`
- `USER.md`
- `TOOLS.md`
- `HEARTBEAT.md`
- `BOOTSTRAP.md`
- `MEMORY.md`

后续如果允许编辑更多内容，也必须遵守同一原则：

- 范围只能在该 agent 对应 node-local managed workspace 内
- 不可越出当前 agent 的受管边界

### 7.3 文件选择与路径选择

如果界面允许用户选择文件或切换配置文件，必须满足：

- 选择范围只限当前 agent 的受管目录
- 用户看到的是“当前节点有哪些可编辑配置文件”
- 不是任意浏览本机文件系统
- 不是跨 agent 访问别的节点配置

推荐交互是“文件标签切换”或“受限文件树”，而不是开放式路径输入。

### 7.4 编辑阶段的行为

编辑阶段所有操作都发生在 mirror 中。

具体来说：

- 打开节点配置时，读取 node-local `openclaw/workspace/` 中的文件
- 新建或缺失文件时，在该 workspace 中创建受管副本
- 用户的修改实时写入当前编辑态和本地受管副本
- 不回写外部源文件
- 不要求保持与外部源文件实时一致
- 不在编辑阶段触发 OpenClaw 同步

因此，配置编辑不是文件同步系统，而是受管副本编辑系统。

### 7.5 Apply 阶段的行为

Apply 时统一处理当前 workflow 中所有待应用修改，包括：

- workflow 结构修改
- 节点本地 markdown 修改
- 权限与通信相关配置修改

Apply 的职责是：

- 以当前 draft 为准
- 以 node-local managed workspace 为内容源
- 批量推送到 OpenClaw
- 成功后刷新 applied revision

Apply 不负责：

- 替用户同步外部源文件
- 把受管副本回写到原始导入路径
- 做文件级双向对账 UI

### 7.6 标题规则

agent 节点标题不能编辑。

规则固定为：

- 节点标题就是 agent 名称

这样做的原因是：

- 避免节点标题与 agent 身份分裂
- 降低画布识别成本
- 降低复制、粘贴、重绑定时的歧义

## 8. 用户体验升级要求

虽然编辑器不执行 workflow，但它仍然必须在体验上做到高效、流畅、低负担。

### 8.1 状态可见

用户必须能一眼分清：

- 哪些改动还没保存
- 哪些改动还没 apply
- 当前改的是哪个节点
- 当前改的是哪个配置文件
- 当前内容是否只存在于本地受管副本中

推荐状态层：

- `Draft changed`
- `Project saved`
- `Apply pending`
- `Apply success`
- `Apply failed`

### 8.2 操作低摩擦

- 打开节点后立即看到核心配置入口
- 文件切换应尽量少跳转
- 常用文件优先展示
- 不要求用户理解底层路径结构也能完成编辑
- 不让用户在“源文件”“副本”“会话镜像”之间做概念判断

### 8.3 流畅性

- 结构编辑与配置编辑都不应频繁阻塞主线程
- 文件切换和节点切换应尽量复用已加载内容
- Apply 前不要做重型同步动作
- 大文件切换要提供清晰 loading 与错误反馈

### 8.4 误操作防护

- 删除节点前展示影响摘要
- 切换节点或文件时自动保留本地编辑态
- Apply 前提示待生效项数量
- 当文件缺失、损坏、越界时，给出明确修复建议

## 9. 数据与交互流

### 9.1 结构编辑流

1. 用户修改节点或连线
2. 统一 mutation pipeline 更新 draft
3. 标记 `workflowConfigurationPending`
4. Save 时写入项目文件
5. Apply 时统一生效

### 9.2 配置编辑流

1. 用户选中 agent 节点
2. 进入该节点的受管配置面
3. 选择当前 agent 范围内某个 markdown 文件
4. 编辑内容并写入 node-local managed workspace
5. 标记 `workflowConfigurationPending`
6. Save 时保存 draft
7. Apply 时统一推送到 OpenClaw

## 10. 对 README 的提炼建议

后续 README 可从本文档中提炼为以下简版口径：

- Workflow 编辑器用于设计和搭建流程，不负责执行
- 每个 agent 节点都有一份本地受管配置副本
- 所有配置编辑都先作用于节点本地副本
- Save 保存项目，Apply 统一使修改生效
- 节点标题固定为 agent 名称
- 编辑器支持在 agent 范围内编辑全部定义型 markdown 文件

## 11. 非目标

本轮不纳入：

- workflow 执行器
- 编辑器内测试运行
- runtime console
- 基于远端状态的联机调试
- 外部源文件回写
- 通用文件同步与冲突解决器

## 12. 实施前置结论

基于当前文件系统结构，本方案建议保持以下落盘解释不变：

- `openclaw/workspace/` 是用户可编辑的受管 mirror 内容
- `openclaw/mirror/` 继续只保存 source-map、baseline 等元数据
- `openclaw/state/` 继续保存导入记录与内部状态

这样可以最大程度复用现有结构、测试和路径解析逻辑，在不推翻底层重构的前提下完成 Workflow 编辑器升级。
