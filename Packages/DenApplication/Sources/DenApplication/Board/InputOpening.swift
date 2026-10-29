public import DenDomain
import Foundation

public struct InputOpening {
    public struct Context {
        public let width: Double
        public let target: BoardCreation.Target
        public let configuration: BoardOpening.Configuration

        public init(width: Double, target: BoardCreation.Target, configuration: BoardOpening.Configuration) {
            self.width = width
            self.target = target
            self.configuration = configuration
        }
    }

    public enum Notice {
        case willOpenBoard
        case board(BoardCreation.Notice)
        case drawer(DrawerItems.Notice)
        case keptInDrawer
    }

    private let creation: BoardCreation
    private let drawer: DrawerItems

    public init(creation: BoardCreation, drawer: DrawerItems) {
        self.creation = creation
        self.drawer = drawer
    }

    public func open(_ input: String, context: Context, inDrawer: Bool, notify: (Notice) -> Void) -> BoardOpenResult {
        if inDrawer {
            let request = BoardCreation.OpenRequest(
                input: input, width: context.width, target: context.target, configuration: context.configuration)
            switch creation.resolve(request) {
            case .createBoard(let board, _):
                switch board.kind {
                case .web(let web):
                    guard let url = web.currentSheetURL, drawer.keep(url, notify: { notify(.drawer($0)) }) != nil
                    else { return .rejected("Could not open in Drawer.") }
                case .terminal(let session):
                    drawer.keep(terminal: session, notify: { notify(.drawer($0)) })
                case .inspection, .tutorial:
                    return .rejected("This content requires a Board.")
                }
            case .rejected(let failure):
                return .rejected(failure.message ?? "Enter a URL, search, or Terminal command to open in Drawer.")
            case .openTutorial:
                return .rejected("Tutorials require a Board.")
            case .selectZmxSession:
                return .rejected("Enter a named zmx session to open in Drawer.")
            }
            notify(.keptInDrawer)
            return .accepted
        }
        notify(.willOpenBoard)
        return creation.open(
            .init(input: input, width: context.width, target: context.target, configuration: context.configuration),
            notify: { notify(.board($0)) })
    }

    public func openClipboard(_ text: String?, context: Context, inDrawer: Bool, notify: (Notice) -> Void)
        -> BoardOpenResult
    {
        guard let input = text?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else {
            return .rejected("Clipboard is empty.")
        }
        let result = open(input, context: context, inDrawer: inDrawer, notify: notify)
        if case .rejected(nil) = result { return .rejected("Could not open board from clipboard.") }
        return result
    }

    public func launch(_ essential: Essential, context: Context, inDrawer: Bool, notify: (Notice) -> Void)
        -> BoardOpenResult
    {
        let result = open(essential.input, context: context, inDrawer: inDrawer, notify: notify)
        if case .rejected(nil) = result { return .rejected("Could not open Essential '\(essential.name)'.") }
        return result
    }

    @discardableResult
    public func openExternalURL(
        _ url: URL, destination: ExternalLinkDestination, context: Context, notify: (Notice) -> Void
    ) -> Bool {
        switch destination {
        case .drawerPeek:
            guard drawer.keep(url, notify: { notify(.drawer($0)) }) != nil else { return false }
            notify(.keptInDrawer)
            return true
        case .focusedBoard:
            return creation.createWeb(
                urlString: url.absoluteString, width: context.width, searchEngine: context.configuration.searchEngine,
                target: context.target, recentItem: .url(WebURLPolicy.canonicalSheetURL(url)),
                notify: { notify(.board($0)) }) != nil
        }
    }
}
