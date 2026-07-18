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

enum BuiltInDeskPreset: String, CaseIterable, Identifiable {
    case empty
    case chatGPT
    case gemini

    static let boardWidth = 520.0

    var id: Self { self }

    var label: String {
        switch self {
        case .empty: "Empty"
        case .chatGPT: "ChatGPT"
        case .gemini: "Gemini"
        }
    }

    var boards: [DeskPresetBoard] {
        switch self {
        case .empty:
            []
        case .chatGPT:
            (0..<3).map { _ in
                DeskPresetBoard(
                    label: "ChatGPT",
                    width: Self.boardWidth,
                    initialSheetURL: URL(string: "https://chatgpt.com/")
                )
            }
        case .gemini:
            (0..<3).map { _ in
                DeskPresetBoard(
                    label: "Gemini",
                    width: Self.boardWidth,
                    initialSheetURL: URL(string: "https://gemini.google.com/")
                )
            }
        }
    }

    var focusedBoardIndex: Int? { boards.isEmpty ? nil : 0 }
}

struct PersonalDeskPreset: Codable, Equatable, Identifiable {
    var id: UUID
    var label: String
    var boards: [DeskPresetBoard]
    var focusedBoardIndex: Int?

    init(id: UUID = UUID(), label: String, desk: DeskState) {
        self.id = id
        self.label = label
        boards = desk.boards.map(DeskPresetBoard.init)
        focusedBoardIndex = desk.boards.firstIndex { $0.id == desk.focusedBoardID }
    }
}

struct DeskPresetBoard: Codable, Equatable {
    var label: String
    var width: Double
    var initialSheetURL: URL?

    nonisolated init(label: String, width: Double, initialSheetURL: URL?) {
        self.label = label
        self.width = width
        self.initialSheetURL = initialSheetURL
    }

    nonisolated init(board: BoardState) {
        self.init(label: board.label, width: board.width, initialSheetURL: board.currentSheetURL)
    }

    func makeBoard() -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: initialSheetURL)
    }
}

struct BoardState: Codable, Equatable, Identifiable {
    var id: UUID
    var label: String
    var width: Double
    var currentSheetURL: URL?

    init(id: UUID = UUID(), label: String, width: Double, currentSheetURL: URL?) {
        self.id = id
        self.label = label
        self.width = width
        self.currentSheetURL = currentSheetURL
    }
}
