import DenDomain
import Foundation

public enum BoardOpening {
    public static let maximumPersistedRecentInputLength = 2_048

    public enum Failure {
        case zmxNotConfigured
        case zellijNotConfigured
        case terminalDirectoryMissing(String)
        case invalidInput
    }

    public enum Decision {
        case createBoard(BoardState, recentItem: RecentItem?)
        case openTutorial
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

    public static func resolve(
        input: String,
        width: Double,
        zmxRootSessionName: String? = nil,
        configuration: Configuration,
        directoryExists: (String) -> Bool
    ) -> Decision {
        if input.trimmingCharacters(in: .whitespacesAndNewlines) == ":tutorial" {
            return .openTutorial
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

        let recentItem = input.count <= maximumPersistedRecentInputLength ? recent : nil
        return .createBoard(board, recentItem: recentItem)
    }
}
