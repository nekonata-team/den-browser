public import DenDomain

public struct TutorialProgress {
    private let reader: DenStateReader
    private let writer: DenStateWriter

    public init(reader: DenStateReader, writer: DenStateWriter) {
        self.reader = reader
        self.writer = writer
    }

    public func record(_ step: TutorialBoardStep) {
        for deskIndex in reader.snapshot.den.desks.indices {
            guard let boardIndex = reader.snapshot.den.desks[deskIndex].boards.firstIndex(where: \.isTutorial),
                case .tutorial(var tutorial) = reader.snapshot.den.desks[deskIndex].boards[boardIndex].kind
            else { continue }
            guard tutorial.record(step: step) else { return }
            writer.update { $0.den.desks[deskIndex].boards[boardIndex].kind = .tutorial(tutorial) }
            return
        }
    }
}
