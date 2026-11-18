import Foundation

public nonisolated enum DenMCPCommand: Codable, Equatable, Sendable {
    case search(query: String, limit: Int)
    case act(ref: UUID, name: String?, deleteBoards: Bool)
    case openPages(pages: [String], desk: String?, newDesk: String?)
    case readPage(boardID: UUID?, url: String?)
    case readSelection(boardID: UUID?)
}

public nonisolated struct DenMCPResult: Codable, Sendable {
    public struct Action: Codable, Sendable {
        public let effect: String
        public let ref: UUID

        public init(effect: String, ref: UUID) {
            self.effect = effect
            self.ref = ref
        }
    }

    public struct Match: Codable, Sendable {
        public let kind: String
        public let id: UUID?
        public let name: String
        public let location: String
        public let detail: String?
        public let actions: [Action]

        public init(
            kind: String,
            id: UUID? = nil,
            name: String,
            location: String,
            detail: String? = nil,
            actions: [Action]
        ) {
            self.kind = kind
            self.id = id
            self.name = name
            self.location = location
            self.detail = detail
            self.actions = actions
        }
    }

    public struct InspectionChoice: Codable, Sendable {
        public let id: UUID
        public let name: String
        public let location: String
        public let url: String?

        public init(id: UUID, name: String, location: String, url: String?) {
            self.id = id
            self.name = name
            self.location = location
            self.url = url
        }
    }

    public var matches: [Match]?
    public var choices: [DenDeskInfo]?
    public var destinations: [Action]?
    public var desk: DenDeskInfo?
    public var pages: [DenMCPPage]?
    public var required: [String]?
    public var message: String?
    public var confirmation: Action?
    public var inspections: [InspectionChoice]?

    public init(
        matches: [Match]? = nil,
        choices: [DenDeskInfo]? = nil,
        destinations: [Action]? = nil,
        desk: DenDeskInfo? = nil,
        pages: [DenMCPPage]? = nil,
        required: [String]? = nil,
        message: String? = nil,
        confirmation: Action? = nil,
        inspections: [InspectionChoice]? = nil
    ) {
        self.matches = matches
        self.choices = choices
        self.destinations = destinations
        self.desk = desk
        self.pages = pages
        self.required = required
        self.message = message
        self.confirmation = confirmation
        self.inspections = inspections
    }
}

public nonisolated struct DenMCPPage: Codable, Sendable {
    public let index: Int
    public let input: String
    public let url: String?
    public let boardID: String?
    public let error: String?

    public init(index: Int, input: String, url: String? = nil, boardID: String? = nil, error: String? = nil) {
        self.index = index
        self.input = input
        self.url = url
        self.boardID = boardID
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case index, input, url, error
        case boardID = "board_id"
    }
}
