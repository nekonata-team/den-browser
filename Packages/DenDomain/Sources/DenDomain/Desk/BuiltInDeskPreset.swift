import Foundation

public enum BuiltInDeskPreset: String, CaseIterable, Identifiable {
    case empty
    case chatGPT
    case gemini

    public static let boardWidth = 520.0

    public var id: Self { self }

    public var label: String {
        switch self {
        case .empty: "Empty"
        case .chatGPT: "ChatGPT"
        case .gemini: "Gemini"
        }
    }

    public var boards: [DeskPresetBoard] {
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

    public var focusedBoardIndex: Int? { boards.isEmpty ? nil : 0 }
}
