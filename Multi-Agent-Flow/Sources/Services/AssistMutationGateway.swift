import Foundation

enum AssistMutationGatewayError: LocalizedError {
    case confirmationRequired
    case outOfScope
    case denied
    case liveRuntimeMutationForbidden
    case unsupported

    var errorDescription: String? {
        switch self {
        case .confirmationRequired:
            return "Assist mutation requires explicit confirmation."
        case .outOfScope:
            return "Assist mutation attempted to write outside the approved scope."
        case .denied:
            return "Assist mutation was denied by the active grant policy."
        case .liveRuntimeMutationForbidden:
            return "Assist mutation cannot write directly to the live runtime."
        case .unsupported:
            return "Assist mutation gateway is not implemented yet."
        }
    }
}

protocol AssistMutationGateway {
    func apply(
        proposal: AssistProposal,
        request: AssistRequest,
        contextPack: AssistContextPack
    ) throws -> AssistExecutionReceipt

    func revert(
        undoCheckpoint: AssistUndoCheckpoint
    ) throws -> AssistExecutionReceipt
}

struct NoopAssistMutationGateway: AssistMutationGateway {
    func apply(
        proposal: AssistProposal,
        request: AssistRequest,
        contextPack: AssistContextPack
    ) throws -> AssistExecutionReceipt {
        throw AssistMutationGatewayError.unsupported
    }

    func revert(
        undoCheckpoint: AssistUndoCheckpoint
    ) throws -> AssistExecutionReceipt {
        throw AssistMutationGatewayError.unsupported
    }
}
