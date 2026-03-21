# Multi-Agent-Flow OpenClaw 远程执行说明

## 文档目的

本文档说明 Multi-Agent-Flow 中 OpenClaw 远程执行相关能力的边界，以及它与 Workflow Editor 的关系。

本文档讨论的是运行态能力，不讨论 workflow 的设计态编辑细节。

## 核心边界

当前产品边界已经明确分成两层：

- Workflow Editor
  负责设计 workflow、编辑节点关系、编辑节点本地受管配置、保存 draft、执行 Apply。
- OpenClaw 远程执行
  负责运行 workflow、处理运行态会话、记录日志、产出执行结果与 runtime trace。

因此：

- Workflow Editor 不再承担“在编辑器内执行 workflow”的职责
- Save 不是执行
- Apply 也不是执行
- Apply 的职责只是把当前待生效配置统一推送到 OpenClaw

## 执行前提

远程执行依赖 OpenClaw 运行时可用。

当前系统会围绕以下能力判断运行时是否可执行：

- 连接状态是否可用
- 运行时 transport 是否可用
- 当前 workflow 是否具备可执行上下文
- 相关 agent 是否已导入并可被运行时识别

即使运行时暂不可用，workflow 设计仍然可以继续进行。

## 运行态能力范围

OpenClaw 远程执行当前覆盖的核心能力包括：

- workflow 运行与调度
- 运行态会话管理
- 执行日志记录
- 执行结果查看
- runtime protocol 事件落盘
- trace、分析与历史回看
- 运行态降级与恢复

当前热路径的 transport 策略是：

- `gateway_agent`
  作为 workflow 热路径的优先执行 transport
- `gateway_chat`
  作为对话型运行路径
- `cli`
  作为 fallback 路径

## 运行态信息查看

运行期间，用户应在运行态相关界面查看执行信息，而不是回到 Workflow Editor 寻找执行入口。

当前运行态信息主要体现在这些方向：

- 执行结果视图
- Workbench / 消息面板中的远程会话
- Ops Center / Runtime 分析与追踪视图
- runtime protocol 持久化结果

这些界面消费的是运行态事实，不会改变 Workflow Editor 的设计态职责。

## 与 Workflow Editor 的衔接方式

Workflow Editor 与 OpenClaw 远程执行之间的正确衔接顺序是：

1. 在 Workflow Editor 中完成结构设计。
2. 在节点配置面中编辑节点本地受管配置文件。
3. 通过 `Save` 保存当前项目草稿。
4. 通过 `Apply` 将当前待生效配置统一推送到 OpenClaw。
5. 在运行态相关界面中发起执行、观察日志、查看结果。

这条顺序的重点是：

- 设计态先稳定
- 生效动作显式可控
- 执行入口与设计入口分离

## 常见问题

### 为什么在 Workflow Editor 里找不到执行按钮

因为 Workflow Editor 的职责已经收口为设计态编辑，不再直接承担执行入口。

### Save 之后为什么还不能直接执行最新配置

因为 `Save` 保存的是 `.maoproj` 草稿文件。

只有在 `Apply` 之后，当前 workflow 的结构与节点本地受管配置才会统一推送到 OpenClaw。

### Apply 和执行是什么关系

`Apply` 是配置生效动作，执行是运行态动作。

`Apply` 的结果是让 OpenClaw 拿到最新待生效配置；它本身不会替你自动启动一次 workflow 运行。

### 运行时不可用时怎么办

可以先继续做 workflow 设计。

当前系统设计允许“离线可用的工作流设计”和“运行态执行”分离存在。

## 相关文档

- [OpenClaw 交互方案](openclaw-interaction-architecture-zh-2026-03-22.md)
- [OpenClaw 交互开发计划](openclaw-interaction-development-plan-zh-2026-03-22.md)
- [Workflow Editor Guide](Workflow-Editor-Guide.md)
- [OpenClaw 连接层重构方案](openclaw-connection-layer-rearchitecture-plan-zh-2026-03-22.md)
- [OpenClaw Agent Runtime 协议](/Users/chenrongze/Desktop/MultiAgentOrchestrator/MultiAgentOrchestrator/docs/openclaw-agent-runtime-protocol.md)
