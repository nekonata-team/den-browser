import DenDomain
import Foundation

public enum BoardOpening {
    public static let maximumPersistedRecentInputLength = 2_048

    public enum Failure {
        case zmxNotConfigured
        case zellijNotConfigured
        case terminalDirectoryMissing(String)
        case invalidInput
        case creationFailed
    }

    public enum Outcome {
        case openedBoard
        case openedTutorial
        case selectZmxSession
        case rejected(Failure)
    }

    public struct Configuration {
        public let searchEngine: SearchEngine
        public let zmxConfigured: Bool
        public let zellijConfigured: Bool
        public let homeDirectory: URL

        public init(searchEngine: SearchEngine, zmxConfigured: Bool, zellijConfigured: Bool, homeDirectory: URL) {
            self.searchEngine = searchEngine
            self.zmxConfigured = zmxConfigured
            self.zellijConfigured = zellijConfigured
            self.homeDirectory = homeDirectory
        }
    }

    public struct Actions {
        public let openTutorial: (Double, BoardID?) -> Bool
        /// Persist the insertion immediately only when no Recent write will follow.
        public let insertBoard: (BoardState, BoardID?, Bool) -> Bool
        public let recordRecent: (RecentItem) -> Void

        public init(
            openTutorial: @escaping (Double, BoardID?) -> Bool,
            insertBoard: @escaping (BoardState, BoardID?, Bool) -> Bool,
            recordRecent: @escaping (RecentItem) -> Void
        ) {
            self.openTutorial = openTutorial
            self.insertBoard = insertBoard
            self.recordRecent = recordRecent
        }
    }

    public static func open(
        input: String,
        width: Double,
        afterBoardID: BoardID? = nil,
        zmxRootSessionName: String? = nil,
        configuration: Configuration,
        directoryExists: (String) -> Bool,
        actions: Actions
    ) -> Outcome {
        if input.trimmingCharacters(in: .whitespacesAndNewlines) == ":tutorial" {
            return actions.openTutorial(width, afterBoardID) ? .openedTutorial : .rejected(.creationFailed)
        }

        let board: BoardState
        let recent: RecentItem
        if let zmx = BoardInputResolver.resolveZmxInput(input) {
            guard configuration.zmxConfigured else { return .rejected(.zmxNotConfigured) }
            guard case .session(let name) = zmx else { return .selectZmxSession }
            board = BoardState(
                width: width,
                zmxSessionName: name,
                workingDirectory: configuration.homeDirectory.path,
                rootSessionName: zmxRootSessionName)
            recent = .zmx(sessionName: name)
        } else if let zellij = BoardInputResolver.resolveZellijInput(input) {
            guard configuration.zellijConfigured else { return .rejected(.zellijNotConfigured) }
            let name: String?
            switch zellij {
            case .welcome: name = nil
            case .session(let sessionName): name = sessionName
            }
            board = BoardState(width: width, zellijSessionName: name)
            recent = .zellij(sessionName: name)
        } else if let terminal = BoardInputResolver.resolveTerminalInput(
            input, homeDirectory: configuration.homeDirectory, directoryExists: directoryExists)
        {
            switch terminal {
            case .success(let directory):
                board = BoardState(width: width, workingDirectory: directory)
                recent = .terminal(workingDirectory: directory)
            case .failure(.missingDirectory(let path)):
                return .rejected(.terminalDirectoryMissing(path))
            }
        } else {
            guard
                let resolution = BoardInputResolver.resolveOpenBoardInput(
                    input, searchEngine: configuration.searchEngine)
            else {
                return .rejected(.invalidInput)
            }
            let url = WebURLPolicy.canonicalSheetURL(resolution.url)
            board = BoardState(
                label: url.host(percentEncoded: false) ?? url.absoluteString,
                width: width,
                currentSheetURL: url)
            recent = resolution.item
        }

        let recordsRecent = input.count <= maximumPersistedRecentInputLength
        guard actions.insertBoard(board, afterBoardID, !recordsRecent) else {
            return .rejected(.creationFailed)
        }
        if recordsRecent { actions.recordRecent(recent) }
        return .openedBoard
    }
}
