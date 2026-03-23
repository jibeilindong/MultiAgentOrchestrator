import SwiftUI

struct WorkflowPackageImportPreviewSheet: View {
    @EnvironmentObject var appState: AppState
    let preview: WorkflowPackagePreview

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("导入工作流设计包")
                    .font(.title2.weight(.semibold))
                Text(preview.archiveURL.lastPathComponent)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    infoRow("来源项目", preview.manifest.source.projectName)
                    infoRow("入口工作流", preview.rootWorkflowName)
                    infoRow("工作流数量", "\(preview.workflowCount)")
                    infoRow("节点数量", "\(preview.nodeCount)")
                    infoRow("连线数量", "\(preview.edgeCount)")
                    infoRow("边界数量", "\(preview.boundaryCount)")
                    infoRow("节点 Agent 快照", "\(preview.nodeAgentCount)")
                    infoRow("Workspace 文件数", "\(preview.workspaceFileCount)")
                    infoRow("Workspace 大小", ByteCountFormatter.string(fromByteCount: preview.workspaceTotalBytes, countStyle: .file))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("包摘要")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("导入设置")
                    .font(.headline)

                TextField("导入后根工作流名称", text: $appState.workflowPackageImportRootName)
                    .textFieldStyle(.roundedBorder)

                Toggle("导入完成后切换到该工作流", isOn: $appState.switchToImportedWorkflowAfterPackageImport)

                Text("该设计包只导入 workflow、节点绑定的 agent 快照，以及完整 workspace 树；不会导入任务、消息、执行结果等运行时数据。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()

                Button("取消") {
                    appState.cleanupWorkflowPackageImportPreview()
                }

                Button("导入") {
                    appState.confirmWorkflowPackageImport()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}
