import { WorkflowCanvasPreview } from "./components/WorkflowCanvasPreview";
import { resolveCanvasDocScene } from "./canvas-doc-scenes";

export function CanvasDocumentationPage() {
  const params = new URLSearchParams(window.location.search);
  const scene = resolveCanvasDocScene(params.get("scene"));
  const capture = params.get("capture") === "1";

  return (
    <main className={`canvasDocShell${capture ? " canvasDocShellCapture" : ""}`} data-scene={scene.id}>
      <section className="canvasDocHero">
        <div className="canvasDocHeroCopy">
          <p className="eyebrow">Workflow Canvas</p>
          <h1>{scene.title}</h1>
          <p className="lede">{scene.subtitle}</p>
          <div className="canvasDocEmphasis">{scene.emphasis}</div>
          <div className="canvasDocBullets">
            {scene.bullets.map((bullet) => (
              <div key={bullet} className="canvasDocBullet">
                {bullet}
              </div>
            ))}
          </div>
        </div>
        <aside className="canvasDocAside">
          <div className="canvasDocAsideCard">
            <span className="sectionLabel">Screenshot Notes</span>
            <h2>真实软件渲染</h2>
            <p>下面的画布直接使用实际的 `WorkflowCanvasPreview` 组件与现有样式，不是后期拼接示意图。</p>
          </div>
          <div className="canvasDocAsideCard">
            <span className="sectionLabel">Read This</span>
            <p>当前截图专门用于说明连线避让、汇流、发散和弧桥跨线这几类关键视觉规则。</p>
          </div>
        </aside>
      </section>

      <section className="canvasDocWorkbench">
        <div className="workflowHeader">
          <div className="compactField">
            <span className="sectionLabel">Mode</span>
            <button type="button">Canvas</button>
          </div>
          <div className="compactField">
            <span className="sectionLabel">Policy</span>
            <button type="button">Minimize Crossings</button>
          </div>
          <div className="compactField">
            <span className="sectionLabel">Scene</span>
            <button type="button">{scene.id}</button>
          </div>
        </div>

        <div className="canvasDocStage">
          <div className="canvasDocPreviewCard canvasDocCanvasWrap">
            <WorkflowCanvasPreview
              workflow={scene.workflow}
              agents={[]}
              zoom={scene.zoom ?? 1}
              selectedEdgeId={scene.selectedEdgeId}
              selectedNodeIds={scene.selectedNodeIds}
            />
            {scene.focusBox ? (
              <div
                className="canvasDocFocusBox"
                style={{
                  left: scene.focusBox.left,
                  top: scene.focusBox.top,
                  width: scene.focusBox.width,
                  height: scene.focusBox.height
                }}
              >
                <span>{scene.focusBox.label}</span>
              </div>
            ) : null}
          </div>

          <div className="inspectorCard canvasDocInspector">
            <span className="sectionLabel">What To Notice</span>
            <div className="canvasDocInspectorList">
              {scene.bullets.map((bullet) => (
                <div key={bullet} className="canvasDocInspectorItem">
                  <strong>{bullet}</strong>
                </div>
              ))}
            </div>
            <div className="canvasDocCallout">
              <strong>画布规则</strong>
              <span>{scene.emphasis}</span>
            </div>
          </div>
        </div>
      </section>
    </main>
  );
}
