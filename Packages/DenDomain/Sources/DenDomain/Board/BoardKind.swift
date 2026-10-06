import Foundation

public enum BoardKind: Codable, Equatable {
    case web(WebBoardState)
    case inspection
    case terminal(TerminalBoardState)
    case tutorial(TutorialBoardState)

    private enum CodingKeys: String, CodingKey {
        case kind, session, currentSheetURL, firstSheetURL, sheetNavigationPaused
    }
    private enum Kind: String, Codable { case web, inspection, terminal, tutorial }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .web:
            self = .web(
                WebBoardState(
                    currentSheetURL: try container.decodeIfPresent(URL.self, forKey: .currentSheetURL),
                    firstSheetURL: try container.decodeIfPresent(URL.self, forKey: .firstSheetURL),
                    sheetNavigationPaused: try container.decodeIfPresent(
                        Bool.self,
                        forKey: .sheetNavigationPaused) ?? false))
        case .inspection:
            self = .inspection
        case .terminal:
            self = .terminal(try container.decode(TerminalBoardState.self, forKey: .session))
        case .tutorial:
            self = .tutorial(TutorialBoardState())
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .web(let web):
            try container.encode(Kind.web, forKey: .kind)
            try container.encodeIfPresent(web.currentSheetURL, forKey: .currentSheetURL)
            try container.encodeIfPresent(web.firstSheetURL, forKey: .firstSheetURL)
            if web.sheetNavigationPaused {
                try container.encode(true, forKey: .sheetNavigationPaused)
            }
        case .inspection:
            try container.encode(Kind.inspection, forKey: .kind)
        case .terminal(let terminal):
            try container.encode(Kind.terminal, forKey: .kind)
            try container.encode(terminal, forKey: .session)
        case .tutorial:
            try container.encode(Kind.tutorial, forKey: .kind)
        }
    }
}
