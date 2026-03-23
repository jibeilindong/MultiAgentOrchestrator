import Foundation

final class WorkbenchRuntimeMutationCoordinator {
    typealias AppendRuntimeEvents = (_ events: [OpenClawRuntimeEvent], _ runtimeState: inout RuntimeState) -> Void
    typealias EnqueueRuntimeDispatch = (_ event: OpenClawRuntimeEvent, _ runtimeState: inout RuntimeState) -> Void
    typealias PromoteRuntimeDispatchToInflight = (_ event: OpenClawRuntimeEvent, _ runtimeState: inout RuntimeState) -> Void
    typealias PromoteRuntimeDispatchToRunning = (_ event: OpenClawRuntimeEvent, _ runtimeState: inout RuntimeState) -> Void
    typealias MakeRuntimeDispatchRecord = (
        _ event: OpenClawRuntimeEvent,
        _ status: RuntimeDispatchStatus,
        _ completedAt: Date?,
        _ errorMessage: String?
    ) -> RuntimeDispatchRecord
    typealias RemoveSupersededFailedDispatches = (_ records: [RuntimeDispatchRecord], _ runtimeState: inout RuntimeState) -> Void
    typealias RecordProtocolOutcome = (_ result: ExecutionResult, _ project: inout MAProject) -> Void

    private let appendRuntimeEvents: AppendRuntimeEvents
    private let enqueueRuntimeDispatch: EnqueueRuntimeDispatch
    private let promoteRuntimeDispatchToInflight: PromoteRuntimeDispatchToInflight
    private let promoteRuntimeDispatchToRunning: PromoteRuntimeDispatchToRunning
    private let makeRuntimeDispatchRecord: MakeRuntimeDispatchRecord
    private let removeSupersededFailedDispatches: RemoveSupersededFailedDispatches
    private let recordProtocolOutcome: RecordProtocolOutcome

    init(
        appendRuntimeEvents: @escaping AppendRuntimeEvents,
        enqueueRuntimeDispatch: @escaping EnqueueRuntimeDispatch,
        promoteRuntimeDispatchToInflight: @escaping PromoteRuntimeDispatchToInflight,
        promoteRuntimeDispatchToRunning: @escaping PromoteRuntimeDispatchToRunning,
        makeRuntimeDispatchRecord: @escaping MakeRuntimeDispatchRecord,
        removeSupersededFailedDispatches: @escaping RemoveSupersededFailedDispatches,
        recordProtocolOutcome: @escaping RecordProtocolOutcome
    ) {
        self.appendRuntimeEvents = appendRuntimeEvents
        self.enqueueRuntimeDispatch = enqueueRuntimeDispatch
        self.promoteRuntimeDispatchToInflight = promoteRuntimeDispatchToInflight
        self.promoteRuntimeDispatchToRunning = promoteRuntimeDispatchToRunning
        self.makeRuntimeDispatchRecord = makeRuntimeDispatchRecord
        self.removeSupersededFailedDispatches = removeSupersededFailedDispatches
        self.recordProtocolOutcome = recordProtocolOutcome
    }

    func recordSubmission(
        project: inout MAProject,
        prompt: String,
        userRuntimeEvent: OpenClawRuntimeEvent?,
        leadAgentID: UUID
    ) {
        project.runtimeState.messageQueue.append(prompt)
        if let userRuntimeEvent {
            appendRuntimeEvents([userRuntimeEvent], &project.runtimeState)
        }
        project.runtimeState.agentStates[leadAgentID.uuidString] = "queued"
    }

    func handleDispatchEvent(
        project: inout MAProject,
        dispatchEvent: OpenClawRuntimeEvent
    ) {
        enqueueRuntimeDispatch(dispatchEvent, &project.runtimeState)
    }

    func handleAcceptedEvent(
        project: inout MAProject,
        acceptedEvent: OpenClawRuntimeEvent
    ) {
        promoteRuntimeDispatchToInflight(acceptedEvent, &project.runtimeState)
    }

    func handleProgressEvent(
        project: inout MAProject,
        progressEvent: OpenClawRuntimeEvent
    ) {
        promoteRuntimeDispatchToRunning(progressEvent, &project.runtimeState)
    }

    func recordExecutionResults(
        project: inout MAProject,
        results: [ExecutionResult],
        removingQueuedPrompt prompt: String,
        removingDispatchEventID dispatchEventID: String? = nil,
        at completedAt: Date
    ) {
        if let queueIndex = project.runtimeState.messageQueue.firstIndex(of: prompt) {
            project.runtimeState.messageQueue.remove(at: queueIndex)
        }
        if let dispatchEventID {
            project.runtimeState.dispatchQueue.removeAll { $0.id == dispatchEventID }
            project.runtimeState.inflightDispatches.removeAll { inflight in
                inflight.id == dispatchEventID || inflight.parentEventID == dispatchEventID
            }
        }

        for result in results {
            project.runtimeState.agentStates[result.agentID.uuidString] = result.status.rawValue.lowercased()
            recordProtocolOutcome(result, &project)
        }

        let terminalDispatches = results
            .flatMap(\.runtimeEvents)
            .filter { event in
                event.eventType == .taskResult || event.eventType == .taskError
            }
            .map { event in
                makeRuntimeDispatchRecord(
                    event,
                    event.eventType == .taskError ? .failed : .completed,
                    completedAt,
                    event.eventType == .taskError ? event.payload["message"] : nil
                )
            }
        let failedIDs = Set(
            terminalDispatches
                .filter { $0.status == .failed || $0.status == .aborted || $0.status == .expired }
                .map(\.id)
        )
        let completedDispatches = terminalDispatches.filter { !failedIDs.contains($0.id) }
        let failedDispatches = terminalDispatches.filter { failedIDs.contains($0.id) }
        let terminalParentIDs = Set(terminalDispatches.compactMap(\.parentEventID))
        if !terminalParentIDs.isEmpty {
            project.runtimeState.inflightDispatches.removeAll { terminalParentIDs.contains($0.id) }
        }
        if !completedDispatches.isEmpty {
            removeSupersededFailedDispatches(completedDispatches, &project.runtimeState)
            let completedIDs = Set(completedDispatches.map(\.id))
            project.runtimeState.completedDispatches.removeAll { completedIDs.contains($0.id) }
            project.runtimeState.completedDispatches.append(contentsOf: completedDispatches)
        }
        if !failedDispatches.isEmpty {
            let failedRecordIDs = Set(failedDispatches.map(\.id))
            project.runtimeState.failedDispatches.removeAll { failedRecordIDs.contains($0.id) }
            project.runtimeState.failedDispatches.append(contentsOf: failedDispatches)
        }
        appendRuntimeEvents(results.flatMap(\.runtimeEvents), &project.runtimeState)
    }
}
