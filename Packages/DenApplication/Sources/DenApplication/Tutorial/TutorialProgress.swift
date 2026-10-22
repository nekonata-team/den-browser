import DenDomain

@MainActor
public struct TutorialProgress {
    private let store: DenStateStore
    private let writer: DenStateWriter

    public init(store: DenStateStore, writer: DenStateWriter) {
        self.store = store
        self.writer = writer
    }

    public func record(_ step: TutorialBoardStep) {
        for deskIndex in store.snapshot.den.desks.indices {
            guard let boardIndex = store.snapshot.den.desks[deskIndex].boards.firstIndex(where: \.isTutorial),
                case .tutorial(var tutorial) = store.snapshot.den.desks[deskIndex].boards[boardIndex].kind
            else { continue }
            guard tutorial.record(step: step) else { return }
            writer.update { $0.den.desks[deskIndex].boards[boardIndex].kind = .tutorial(tutorial) }
            return
        }
    }
}
