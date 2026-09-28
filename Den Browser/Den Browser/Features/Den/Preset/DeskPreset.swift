import Foundation

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
        boards = DeskPresetBoard.capture(from: desk.boards)
        focusedBoardIndex = desk.boards.firstIndex { $0.id == desk.focusedBoardID }
    }
}

enum DeskPresetTerminalContent: Codable, Equatable {
    case shell(workingDirectory: String)
    case zellij(sessionName: String?)
    case zmx(sessionName: String)

    private enum CodingKeys: String, CodingKey { case kind, workingDirectory, sessionName }
    private enum Kind: String, Codable { case shell, zellij, zmx }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .shell:
            self = .shell(workingDirectory: try container.decode(String.self, forKey: .workingDirectory))
        case .zellij:
            self = .zellij(sessionName: try container.decodeIfPresent(String.self, forKey: .sessionName))
        case .zmx:
            self = .zmx(sessionName: try container.decode(String.self, forKey: .sessionName))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .shell(let workingDirectory):
            try container.encode(Kind.shell, forKey: .kind)
            try container.encode(workingDirectory, forKey: .workingDirectory)
        case .zellij(let sessionName):
            try container.encode(Kind.zellij, forKey: .kind)
            try container.encodeIfPresent(sessionName, forKey: .sessionName)
        case .zmx(let sessionName):
            try container.encode(Kind.zmx, forKey: .kind)
            try container.encode(sessionName, forKey: .sessionName)
        }
    }
}

enum DeskPresetBoardContent: Codable, Equatable {
    case web(URL?)
    case inspection
    case terminal(DeskPresetTerminalContent)

    private enum CodingKeys: String, CodingKey { case kind, session, initialSheetURL }
    private enum Kind: String, Codable { case web, inspection, terminal }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .web:
            self = .web(try container.decodeIfPresent(URL.self, forKey: .initialSheetURL))
        case .inspection:
            self = .inspection
        case .terminal:
            self = .terminal(try container.decode(DeskPresetTerminalContent.self, forKey: .session))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .web(let url):
            try container.encode(Kind.web, forKey: .kind)
            try container.encodeIfPresent(url, forKey: .initialSheetURL)
        case .inspection:
            try container.encode(Kind.inspection, forKey: .kind)
        case .terminal(let session):
            try container.encode(Kind.terminal, forKey: .kind)
            try container.encode(session, forKey: .session)
        }
    }
}

struct DeskPresetBoard: Codable, Equatable {
    var label: String
    var width: Double
    var content: DeskPresetBoardContent
    var customLabel: String?
    var targetBoardIndex: Int?

    var initialSheetURL: URL? {
        guard case .web(let url) = content else { return nil }
        return url
    }

    var terminalWorkingDirectory: String? {
        guard case .terminal(.shell(let workingDirectory)) = content else { return nil }
        return workingDirectory
    }

    var zellijSessionName: String? {
        guard case .terminal(.zellij(let sessionName)) = content else { return nil }
        return sessionName
    }

    var zmxSessionName: String? {
        guard case .terminal(.zmx(let sessionName)) = content else { return nil }
        return sessionName
    }

    nonisolated init(label: String, width: Double, initialSheetURL: URL?, customLabel: String? = nil) {
        self.init(label: label, width: width, content: .web(initialSheetURL), customLabel: customLabel)
    }

    nonisolated init(label: String, width: Double, workingDirectory: String, customLabel: String? = nil) {
        self.init(
            label: label,
            width: width,
            content: .terminal(.shell(workingDirectory: workingDirectory)),
            customLabel: customLabel)
    }

    nonisolated init(label: String, width: Double, zellijSessionName: String?, customLabel: String? = nil) {
        self.init(
            label: label,
            width: width,
            content: .terminal(.zellij(sessionName: zellijSessionName)),
            customLabel: customLabel)
    }

    nonisolated init(label: String, width: Double, zmxSessionName: String, customLabel: String? = nil) {
        self.init(
            label: label,
            width: width,
            content: .terminal(.zmx(sessionName: zmxSessionName)),
            customLabel: customLabel)
    }

    nonisolated init(
        label: String,
        width: Double,
        content: DeskPresetBoardContent,
        customLabel: String? = nil,
        targetBoardIndex: Int? = nil
    ) {
        self.label = label
        self.width = width
        self.content = content
        self.customLabel = customLabel
        self.targetBoardIndex = targetBoardIndex
    }

    nonisolated init(board: BoardState) {
        self.init(board: board, targetBoardIndex: nil)
    }

    nonisolated init(board: BoardState, targetBoardIndex: Int?) {
        let content: DeskPresetBoardContent
        switch board.content {
        case .web(let web):
            content = .web(web.currentSheetURL)
        case .inspection:
            content = .inspection
        case .terminal(.shell(let workingDirectory)):
            content = .terminal(.shell(workingDirectory: workingDirectory))
        case .terminal(.zellij(let zellij)):
            content = .terminal(.zellij(sessionName: zellij.sessionName))
        case .terminal(.zmx(let zmx)):
            content = .terminal(.zmx(sessionName: zmx.sessionName))
        }
        self.init(
            label: board.label,
            width: board.width,
            content: content,
            customLabel: board.customLabel,
            targetBoardIndex: targetBoardIndex)
    }

    static func capture(from boards: [BoardState]) -> [DeskPresetBoard] {
        return boards.map { board in
            let targetBoardIndex = board.sideBoardTargetBoardID.flatMap { targetBoardID in
                boards.firstIndex { $0.id == targetBoardID }
            }
            return DeskPresetBoard(board: board, targetBoardIndex: targetBoardIndex)
        }
    }

    func makeBoard(id: UUID = UUID()) -> BoardState? {
        switch content {
        case .web(let initialSheetURL):
            return BoardState(
                id: id,
                label: label,
                width: width,
                currentSheetURL: initialSheetURL,
                firstSheetURL: initialSheetURL,
                customLabel: customLabel)
        case .inspection:
            return nil
        case .terminal(.shell(let workingDirectory)):
            return BoardState(
                id: id,
                label: label,
                width: width,
                workingDirectory: workingDirectory,
                customLabel: customLabel)
        case .terminal(.zellij(let sessionName)):
            return BoardState(
                id: id,
                label: label,
                width: width,
                zellijSessionName: sessionName,
                customLabel: customLabel)
        case .terminal(.zmx(let sessionName)):
            return BoardState(
                id: id,
                label: label,
                width: width,
                zmxSessionName: sessionName,
                customLabel: customLabel)
        }
    }

    static func makeBoards(from presetBoards: [DeskPresetBoard]) -> [BoardState]? {
        let boardIDs = presetBoards.map { _ in UUID() }
        var boards: [BoardState] = []
        boards.reserveCapacity(presetBoards.count)

        for (index, presetBoard) in presetBoards.enumerated() {
            if case .inspection = presetBoard.content {
                guard
                    let targetBoardIndex = presetBoard.targetBoardIndex,
                    presetBoards.indices.contains(targetBoardIndex),
                    case .web = presetBoards[targetBoardIndex].content
                else { return nil }
                boards.append(
                    BoardState(
                        id: boardIDs[index],
                        label: presetBoard.label,
                        width: presetBoard.width,
                        targetBoardID: boardIDs[targetBoardIndex]))
            } else {
                guard let board = presetBoard.makeBoard(id: boardIDs[index]) else { return nil }
                boards.append(board)
            }
        }
        return boards
    }

    private enum CodingKeys: String, CodingKey {
        case label, width, content, customLabel, targetBoardIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        width = try container.decode(Double.self, forKey: .width)
        customLabel = try container.decodeIfPresent(String.self, forKey: .customLabel)
        targetBoardIndex = try container.decodeIfPresent(Int.self, forKey: .targetBoardIndex)
        content = try container.decode(DeskPresetBoardContent.self, forKey: .content)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        try container.encode(width, forKey: .width)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(customLabel, forKey: .customLabel)
        try container.encodeIfPresent(targetBoardIndex, forKey: .targetBoardIndex)
    }
}
