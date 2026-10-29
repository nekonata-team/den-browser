import Foundation

public struct DrawerItem: Codable, Equatable, Identifiable {
    public var id: UUID
    public var content: DrawerItemContent
    public var title: String?

    public init(id: UUID = UUID(), url: URL, title: String? = nil) {
        self.id = id
        content = .web(url)
        self.title = title
    }

    public init(id: UUID = UUID(), terminal: TerminalBoardState, title: String? = nil) {
        self.id = id
        content = .terminal(terminal)
        self.title = title
    }

    public var url: URL? {
        guard case .web(let url) = content else { return nil }
        return url
    }

    public var terminal: TerminalBoardState? {
        guard case .terminal(let terminal) = content else { return nil }
        return terminal
    }

    public var detail: String {
        switch content {
        case .web(let url): url.absoluteString
        case .terminal(.shell(let directory)): directory
        case .terminal(.zellij(let session)): session.sessionName ?? "Zellij Welcome"
        case .terminal(.zmx(let session)): session.workingDirectory
        }
    }

    public var displayName: String {
        if let title { return title }
        switch content {
        case .web(let url): return url.host(percentEncoded: false) ?? url.absoluteString
        case .terminal(.shell): return "Terminal"
        case .terminal(.zellij(let session)): return session.sessionName.map { "Zellij · \($0)" } ?? "Zellij"
        case .terminal(.zmx(let session)): return "zmx · \(session.sessionName)"
        }
    }
}
