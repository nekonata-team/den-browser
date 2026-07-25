import Foundation

struct DenState: Codable, Equatable {
    var desks: [DeskState]
    var focusedDeskID: UUID
    var drawerItems: [DrawerItem]
    var expandedDrawerItemID: UUID?

    init(
        desks: [DeskState],
        focusedDeskID: UUID,
        drawerItems: [DrawerItem] = [],
        expandedDrawerItemID: UUID? = nil
    ) {
        self.desks = desks
        self.focusedDeskID = focusedDeskID
        self.drawerItems = drawerItems
        self.expandedDrawerItemID = expandedDrawerItemID
    }

    private enum CodingKeys: String, CodingKey {
        case desks, focusedDeskID, drawerItems, expandedDrawerItemID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        desks = try container.decode([DeskState].self, forKey: .desks)
        focusedDeskID = try container.decode(UUID.self, forKey: .focusedDeskID)
        drawerItems = try container.decodeIfPresent([DrawerItem].self, forKey: .drawerItems) ?? []
        expandedDrawerItemID = try container.decodeIfPresent(
            UUID.self,
            forKey: .expandedDrawerItemID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(desks, forKey: .desks)
        try container.encode(focusedDeskID, forKey: .focusedDeskID)
        if !drawerItems.isEmpty {
            try container.encode(drawerItems, forKey: .drawerItems)
        }
        try container.encodeIfPresent(expandedDrawerItemID, forKey: .expandedDrawerItemID)
    }

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

struct DrawerItem: Codable, Equatable, Identifiable {
    var id: UUID
    var url: URL
    var title: String?

    init(id: UUID = UUID(), url: URL, title: String? = nil) {
        self.id = id
        self.url = url
        self.title = title
    }

    var displayName: String {
        title ?? url.host(percentEncoded: false) ?? url.absoluteString
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
    var customLabel: String?

    nonisolated init(label: String, width: Double, initialSheetURL: URL?, customLabel: String? = nil) {
        self.label = label
        self.width = width
        self.initialSheetURL = initialSheetURL
        self.customLabel = customLabel
    }

    nonisolated init(board: BoardState) {
        self.init(
            label: board.label,
            width: board.width,
            initialSheetURL: board.currentSheetURL,
            customLabel: board.customLabel
        )
    }

    func makeBoard() -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: initialSheetURL, customLabel: customLabel)
    }
}

struct BoardState: Codable, Equatable, Identifiable {
    var id: UUID
    var label: String
    var width: Double
    var currentSheetURL: URL?
    var customLabel: String?

    var displayName: String {
        customLabel ?? label
    }

    init(id: UUID = UUID(), label: String, width: Double, currentSheetURL: URL?, customLabel: String? = nil) {
        self.id = id
        self.label = label
        self.width = width
        self.currentSheetURL = currentSheetURL
        self.customLabel = customLabel
    }
}
