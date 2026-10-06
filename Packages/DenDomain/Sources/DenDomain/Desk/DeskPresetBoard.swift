import Foundation

public struct DeskPresetBoard: Codable, Equatable {
    public var label: String
    public var width: Double
    public var kind: DeskPresetBoardKind
    public var customLabel: String?
    public var targetBoardIndex: Int?

    public var initialSheetURL: URL? {
        guard case .web(let url) = kind else { return nil }
        return url
    }

    public var terminalWorkingDirectory: String? {
        guard case .terminal(.shell(let workingDirectory)) = kind else { return nil }
        return workingDirectory
    }

    public var zellijSessionName: String? {
        guard case .terminal(.zellij(let sessionName)) = kind else { return nil }
        return sessionName
    }

    public var zmxSessionName: String? {
        guard case .terminal(.zmx(let sessionName, _)) = kind else { return nil }
        return sessionName
    }

    public nonisolated init(label: String, width: Double, initialSheetURL: URL?, customLabel: String? = nil) {
        self.init(label: label, width: width, kind: .web(initialSheetURL), customLabel: customLabel)
    }

    public nonisolated init(label: String, width: Double, workingDirectory: String, customLabel: String? = nil) {
        self.init(
            label: label,
            width: width,
            kind: .terminal(.shell(workingDirectory: workingDirectory)),
            customLabel: customLabel)
    }

    public nonisolated init(label: String, width: Double, zellijSessionName: String?, customLabel: String? = nil) {
        self.init(
            label: label,
            width: width,
            kind: .terminal(.zellij(sessionName: zellijSessionName)),
            customLabel: customLabel)
    }

    public nonisolated init(label: String, width: Double, zmxSessionName: String, customLabel: String? = nil) {
        self.init(
            label: label,
            width: width,
            kind: .terminal(.zmx(sessionName: zmxSessionName, rootSessionName: nil)),
            customLabel: customLabel)
    }

    public nonisolated init(
        label: String,
        width: Double,
        kind: DeskPresetBoardKind,
        customLabel: String? = nil,
        targetBoardIndex: Int? = nil
    ) {
        self.label = label
        self.width = width
        self.kind = kind
        self.customLabel = customLabel
        self.targetBoardIndex = targetBoardIndex
    }

    public nonisolated init?(board: BoardState, targetBoardIndex: Int? = nil) {
        let kind: DeskPresetBoardKind
        switch board.kind {
        case .web(let web):
            kind = .web(web.currentSheetURL)
        case .inspection:
            kind = .inspection
        case .terminal(.shell(let workingDirectory)):
            kind = .terminal(.shell(workingDirectory: workingDirectory))
        case .terminal(.zellij(let zellij)):
            kind = .terminal(.zellij(sessionName: zellij.sessionName))
        case .terminal(.zmx(let zmx)):
            kind = .terminal(.zmx(sessionName: zmx.sessionName, rootSessionName: zmx.rootSessionName))
        case .tutorial:
            return nil
        }
        self.init(
            label: board.label,
            width: board.width,
            kind: kind,
            customLabel: board.customLabel,
            targetBoardIndex: targetBoardIndex)
    }

    public static func capture(from boards: [BoardState]) -> [DeskPresetBoard] {
        let presetBoards = boards.filter { !$0.isTutorial }
        return presetBoards.compactMap { board in
            let targetBoardIndex = board.sideBoardTargetBoardID.flatMap { targetBoardID in
                presetBoards.firstIndex { $0.id == targetBoardID }
            }
            return DeskPresetBoard(board: board, targetBoardIndex: targetBoardIndex)
        }
    }

    public func makeBoard(id: UUID = UUID()) -> BoardState? {
        switch kind {
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
        case .terminal(.zmx(let sessionName, let rootSessionName)):
            return BoardState(
                id: id,
                label: label,
                width: width,
                zmxSessionName: sessionName,
                rootSessionName: rootSessionName,
                customLabel: customLabel)
        }
    }

    public static func makeBoards(from presetBoards: [DeskPresetBoard]) -> [BoardState]? {
        let boardIDs = presetBoards.map { _ in UUID() }
        var boards: [BoardState] = []
        boards.reserveCapacity(presetBoards.count)

        for (index, presetBoard) in presetBoards.enumerated() {
            if case .inspection = presetBoard.kind {
                guard
                    let targetBoardIndex = presetBoard.targetBoardIndex,
                    presetBoards.indices.contains(targetBoardIndex),
                    case .web = presetBoards[targetBoardIndex].kind
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
        case label, width, customLabel, targetBoardIndex
        case kind = "content"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        width = try container.decode(Double.self, forKey: .width)
        customLabel = try container.decodeIfPresent(String.self, forKey: .customLabel)
        targetBoardIndex = try container.decodeIfPresent(Int.self, forKey: .targetBoardIndex)
        kind = try container.decode(DeskPresetBoardKind.self, forKey: .kind)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        try container.encode(width, forKey: .width)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(customLabel, forKey: .customLabel)
        try container.encodeIfPresent(targetBoardIndex, forKey: .targetBoardIndex)
    }
}
