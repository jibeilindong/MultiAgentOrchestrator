# Multi-Agent-Flow 画布编辑器介绍

Multi-Agent-Flow 的画布编辑器用于搭建多智能体工作流，并把“能看懂”作为连线布局的第一原则。

当前版本的连线策略重点解决两件事：

- 连接线尽量减少交叉
- 如果交叉不可避免，则在连线上显示弧桥，明确表示只是跨越，不是实际连接

这些文档图片来自实际前端组件页面截图，使用的就是当前软件里的 `WorkflowCanvasPreview` 与现有样式，因此文档展示与实际编辑器行为保持一致。

## 总览

![画布编辑器总览](assets/workflow-canvas-editor-overview-2026-03-21.png)

画布编辑器当前覆盖的体验重点：

- 节点之间使用正交折线连接，路径更规整
- 同源多分支优先做 `fan-out` 主干收束，减少“从一个节点炸开”的杂乱感
- 同目标多输入优先做 `fan-in` 汇流，方便阅读执行汇聚关系
- 不可避免的跨线使用弧桥显示，避免用户误读为存在真实连接
- 连线标签、终点圆点、选中态在预览和正式画布中保持同类表达

## 连线规则

### 1. 尽量减少交叉

编辑器会优先比较多组候选正交路径，优先选择：

1. 不穿过节点障碍物
2. 与已有连线交叉更少
3. 折点更少
4. 总长度更短

### 2. 同源多分支优先共用主干

![同源多分支 fan-out](assets/workflow-canvas-routing-fanout-2026-03-21.png)

从同一节点发出的多条连接线会优先共享一段主干，再分别进入目标节点。这样做的好处是：

- 线条密度更低
- 更容易看出“同一个节点在分发任务”
- 在上下或左右发散场景中都更稳定

### 3. 同目标多输入优先做汇流

![同目标多输入 fan-in](assets/workflow-canvas-routing-fanin-2026-03-21.png)

多个上游节点汇入同一个目标时，编辑器会优先把路径整理到同一段汇流线上，再进入目标节点。这样更容易看出：

- 哪些节点在共同产出一个结果
- 哪个节点是当前汇总或审核入口

### 4. 不可避免交叉时显示弧桥

![弧桥跨线示意](assets/workflow-canvas-routing-bridge-2026-03-21.png)

当布局约束导致交叉无法完全消除时，画布不会把两条线简单画穿过去，而是给水平连线增加跳线弧桥，明确表达：

- 这里只是视觉跨越
- 两条线之间不存在真实连接关系

这能显著降低用户把“交叉”误读成“接入”的风险。

## 验收方式

当前连线相关的最小验收已经落地为可复用命令：

```bash
npm run validate:desktop-routing
```

它会覆盖以下典型场景：

- 纵向 fan-out
- 横向 fan-out
- 纵向 fan-in
- 交叉场景的 bridge overlay

如果要重新生成本文档使用的真实截图，可以运行：

```bash
npm run capture:canvas-doc-screenshots
```

生成产物位于：

- `Multi-Agent-Flow/Documentation/assets/workflow-canvas-editor-overview-2026-03-21.png`
- `Multi-Agent-Flow/Documentation/assets/workflow-canvas-routing-fanout-2026-03-21.png`
- `Multi-Agent-Flow/Documentation/assets/workflow-canvas-routing-fanin-2026-03-21.png`
- `Multi-Agent-Flow/Documentation/assets/workflow-canvas-routing-bridge-2026-03-21.png`

## 相关实现

- Routing 核心：`apps/desktop/src/components/workflowCanvasRouting.ts`
- 预览组件：`apps/desktop/src/components/WorkflowCanvasPreview.tsx`
- 视觉验收脚本：`apps/desktop/scripts/validate-routing.ts`
- 文档截图页面：`apps/desktop/canvas-doc.html`
- 文档截图脚本：`apps/desktop/scripts/capture-canvas-doc-screenshots.mjs`
