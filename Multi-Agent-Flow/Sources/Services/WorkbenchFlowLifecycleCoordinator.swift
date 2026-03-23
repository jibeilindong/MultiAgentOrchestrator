import Foundation

enum WorkbenchChatEntryDisposition: Equatable {
    case failed(errorMessage: String?)
    case readyToRun
    case continueInBackground
}

struct WorkbenchWorkflowRunPresentation {
    let taskStatus: TaskStatus
    let terminalTransition: WorkbenchThreadTransition
    let messageType: MessageType
    let outputType: ExecutionOutputType
    let summaryText: String
}

final class WorkbenchFlowLifecycleCoordinator {
    func chatEntryDisposition(
        for entryResult: ExecutionResult,
        hasBackgroundNodes: Bool
    ) -> WorkbenchChatEntryDisposition {
        guard entryResult.status == .completed else {
            return .failed(errorMessage: entryResult.summaryText)
        }

        return hasBackgroundNodes ? .continueInBackground : .readyToRun
    }

    func backgroundWorkflowTerminalTransition(
        for results: [ExecutionResult]
    ) -> WorkbenchThreadTransition {
        terminalTransition(
            for: results,
            successInteractionMode: .run,
            successThreadMode: .conversationToRun
        )
    }

    func workflowRunPresentation(
        for results: [ExecutionResult]
    ) -> WorkbenchWorkflowRunPresentation {
        let failedResults = results.filter { $0.status == .failed }
        let completedCount = results.filter { $0.status == .completed }.count
        let summaryLine = (
            results
                .map(\.summaryText)
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )?.compactSingleLinePreview(limit: 220)
        let failureLine = failedResults.first?.summaryText.compactSingleLinePreview(limit: 180)
        let summaryText = [
            "Run completed: \(completedCount) succeeded, \(failedResults.count) failed.",
            summaryLine,
            failureLine.map { "Failure: \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: "\n")

        return WorkbenchWorkflowRunPresentation(
            taskStatus: failedResults.isEmpty ? .done : .blocked,
            terminalTransition: terminalTransition(
                for: results,
                successInteractionMode: .run,
                successThreadMode: .controlledRun
            ),
            messageType: failedResults.isEmpty ? .notification : .data,
            outputType: failedResults.isEmpty ? .agentFinalResponse : .errorSummary,
            summaryText: summaryText
        )
    }

    private func terminalTransition(
        for results: [ExecutionResult],
        successInteractionMode: WorkbenchInteractionMode,
        successThreadMode: WorkbenchThreadSemanticMode
    ) -> WorkbenchThreadTransition {
        let failureSummary = results.first(where: { $0.status == .failed })?.summaryText
        if results.isEmpty || results.contains(where: { $0.status == .failed }) {
            return .failed(
                errorMessage: failureSummary,
                interactionMode: successInteractionMode,
                threadMode: successThreadMode
            )
        }

        return .completed(
            interactionMode: successInteractionMode,
            threadMode: successThreadMode
        )
    }
}
