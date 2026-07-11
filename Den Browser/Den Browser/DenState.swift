import Foundation

struct DenState: Codable, Equatable {
    var desks: [DeskState]
    var focusedDeskID: UUID

    static let sample = DenState(
        desks: [
            DeskState(
                label: "Main",
                boards: []
            )
        ],
        focusedDeskID: UUID()
    ).withFirstDeskFocused()

    private func withFirstDeskFocused() -> DenState {
        var copy = self
        if let firstDeskID = copy.desks.first?.id {
            copy.focusedDeskID = firstDeskID
        }
        return copy
    }
}

struct DeskState: Codable, Equatable, Identifiable {
    var id: UUID
    var label: String
    var boards: [BoardState]
    var focusedBoardID: UUID?

    init(id: UUID = UUID(), label: String, boards: [BoardState], focusedBoardID: UUID? = nil) {
        self.id = id
        self.label = label
        self.boards = boards
        self.focusedBoardID = focusedBoardID ?? boards.first?.id
    }
}

enum DeskTemplate: String, CaseIterable, Identifiable {
    case empty
    case chatGPTThree

    var id: Self { self }

    var label: String {
        switch self {
        case .empty: "Empty"
        case .chatGPTThree: "ChatGPT ×3"
        }
    }

    func makeBoards() -> [BoardState] {
        switch self {
        case .empty:
            []
        case .chatGPTThree:
            (0..<3).map { _ in
                BoardState(
                    label: "ChatGPT",
                    width: 520,
                    currentURLString: "https://chatgpt.com/"
                )
            }
        }
    }
}

struct BoardState: Codable, Equatable, Identifiable {
    var id: UUID
    var label: String
    var width: Double
    var currentURLString: String

    init(id: UUID = UUID(), label: String, width: Double, currentURLString: String) {
        self.id = id
        self.label = label
        self.width = width
        self.currentURLString = currentURLString
    }
}
