import Foundation
import SFSafeSymbols

struct DenState: Codable, Equatable {
    var desks: [DeskState]
    var focusedDeskID: UUID
    var drawerItems: [DrawerItem]

    init(
        desks: [DeskState],
        focusedDeskID: UUID,
        drawerItems: [DrawerItem] = []
    ) {
        self.desks = desks
        self.focusedDeskID = focusedDeskID
        self.drawerItems = drawerItems
    }

    private enum CodingKeys: String, CodingKey {
        case desks, focusedDeskID, drawerItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        desks = try container.decode([DeskState].self, forKey: .desks)
        focusedDeskID = try container.decode(UUID.self, forKey: .focusedDeskID)
        drawerItems = try container.decodeIfPresent([DrawerItem].self, forKey: .drawerItems) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(desks, forKey: .desks)
        try container.encode(focusedDeskID, forKey: .focusedDeskID)
        if !drawerItems.isEmpty {
            try container.encode(drawerItems, forKey: .drawerItems)
        }
    }

    static var sample: DenState {
        makeInitial()
    }

    static func makeInitial() -> DenState {
        let desk = DeskState(
            label: "Main",
            boards: []
        )
        return DenState(
            desks: [desk],
            focusedDeskID: desk.id
        )
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
    var focusedBoardID: UUID? {
        didSet {
            if focusedBoardID != oldValue {
                scrollOffsetX = nil
            }
        }
    }
    var scrollOffsetX: Double?
    var anchorBoardID: UUID?

    init(
        id: UUID = UUID(),
        label: String,
        boards: [BoardState],
        focusedBoardID: UUID? = nil,
        scrollOffsetX: Double? = nil,
        anchorBoardID: UUID? = nil
    ) {
        self.id = id
        self.label = label
        self.boards = boards
        self.focusedBoardID = focusedBoardID ?? boards.first?.id
        self.scrollOffsetX = scrollOffsetX
        self.anchorBoardID = anchorBoardID
    }
}

struct WebBoardState: Equatable {
    var currentSheetURL: URL?
    var firstSheetURL: URL?
    var sheetNavigationPaused: Bool

    init(
        currentSheetURL: URL? = nil,
        firstSheetURL: URL? = nil,
        sheetNavigationPaused: Bool = false
    ) {
        self.currentSheetURL = currentSheetURL.map(SheetURLPolicy.canonicalSheetURL)
        self.firstSheetURL = firstSheetURL.map(SheetURLPolicy.canonicalSheetURL)
        self.sheetNavigationPaused = sheetNavigationPaused
    }
}

enum TerminalBoardState: Codable, Equatable {
    case shell(workingDirectory: String)
    case zellij(ZellijBoardState)
    case zmx(ZmxBoardState)

    var workingDirectory: String? {
        switch self {
        case .shell(let workingDirectory): workingDirectory
        case .zmx(let zmx): zmx.workingDirectory
        case .zellij: nil
        }
    }

    var zellijSessionName: String? {
        guard case .zellij(let zellij) = self else { return nil }
        return zellij.sessionName
    }

    var zmxSessionName: String? {
        guard case .zmx(let zmx) = self else { return nil }
        return zmx.sessionName
    }

    var zmxRootSessionName: String? {
        guard case .zmx(let zmx) = self else { return nil }
        return zmx.rootSessionName
    }

    private enum CodingKeys: String, CodingKey {
        case kind, workingDirectory, sessionName, rootSessionName
    }
    private enum Kind: String, Codable { case shell, zellij, zmx }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .shell:
            self = .shell(workingDirectory: try container.decode(String.self, forKey: .workingDirectory))
        case .zellij:
            self = .zellij(
                ZellijBoardState(
                    sessionName: try container.decodeIfPresent(String.self, forKey: .sessionName)))
        case .zmx:
            self = .zmx(
                ZmxBoardState(
                    sessionName: try container.decode(String.self, forKey: .sessionName),
                    workingDirectory: try container.decode(String.self, forKey: .workingDirectory),
                    rootSessionName: try container.decodeIfPresent(String.self, forKey: .rootSessionName)))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .shell(let workingDirectory):
            try container.encode(Kind.shell, forKey: .kind)
            try container.encode(workingDirectory, forKey: .workingDirectory)
        case .zellij(let zellij):
            try container.encode(Kind.zellij, forKey: .kind)
            try container.encodeIfPresent(zellij.sessionName, forKey: .sessionName)
        case .zmx(let zmx):
            try container.encode(Kind.zmx, forKey: .kind)
            try container.encode(zmx.sessionName, forKey: .sessionName)
            try container.encode(zmx.workingDirectory, forKey: .workingDirectory)
            try container.encodeIfPresent(zmx.rootSessionName, forKey: .rootSessionName)
        }
    }
}

struct ZellijBoardState: Codable, Equatable {
    var sessionName: String?
}

struct ZmxBoardState: Codable, Equatable {
    var sessionName: String
    var workingDirectory: String
    var rootSessionName: String?

    init(sessionName: String, workingDirectory: String, rootSessionName: String? = nil) {
        self.sessionName = sessionName
        self.workingDirectory = workingDirectory
        self.rootSessionName = rootSessionName
    }
}

enum BoardRole: Codable, Equatable {
    case primary
    case sideBoard(targetBoardID: UUID)

    private enum CodingKeys: String, CodingKey {
        case kind, targetBoardID
    }

    private enum Kind: String, Codable {
        case primary, sideBoard
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .primary:
            self = .primary
        case .sideBoard:
            self = .sideBoard(targetBoardID: try container.decode(UUID.self, forKey: .targetBoardID))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .primary:
            try container.encode(Kind.primary, forKey: .kind)
        case .sideBoard(let targetBoardID):
            try container.encode(Kind.sideBoard, forKey: .kind)
            try container.encode(targetBoardID, forKey: .targetBoardID)
        }
    }
}

enum BoardContentState: Codable, Equatable {
    case web(WebBoardState)
    case inspection
    case terminal(TerminalBoardState)

    private enum CodingKeys: String, CodingKey {
        case kind, session, currentSheetURL, firstSheetURL, sheetNavigationPaused
    }
    private enum Kind: String, Codable { case web, inspection, terminal }

    init(from decoder: Decoder) throws {
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
        }
    }

    func encode(to encoder: Encoder) throws {
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
        }
    }
}

struct BoardState: Codable, Equatable, Identifiable {
    static let minimumWidth = 280.0
    static let maximumWidth = 1_400.0

    var id: UUID
    var label: String
    var width: Double
    var content: BoardContentState
    var role: BoardRole
    var customLabel: String?

    var sheetNavigationPaused: Bool {
        get {
            guard case .web(let web) = content else { return false }
            return web.sheetNavigationPaused
        }
        set {
            guard case .web(var web) = content else { return }
            web.sheetNavigationPaused = newValue
            content = .web(web)
        }
    }

    var currentSheetURL: URL? {
        get {
            guard case .web(let web) = content else { return nil }
            return web.currentSheetURL
        }
        set {
            guard case .web(var web) = content else { return }
            web.currentSheetURL = newValue.map(SheetURLPolicy.canonicalSheetURL)
            content = .web(web)
        }
    }

    var firstSheetURL: URL? {
        get {
            guard case .web(let web) = content else { return nil }
            return web.firstSheetURL
        }
        set {
            guard case .web(var web) = content else { return }
            web.firstSheetURL = newValue.map(SheetURLPolicy.canonicalSheetURL)
            content = .web(web)
        }
    }

    var terminalWorkingDirectory: String? {
        get {
            guard case .terminal(let terminal) = content else { return nil }
            return terminal.workingDirectory
        }
        set {
            guard let newValue else { return }
            guard case .terminal(let terminal) = content else { return }
            switch terminal {
            case .shell:
                content = .terminal(.shell(workingDirectory: newValue))
            case .zmx(var zmx):
                zmx.workingDirectory = newValue
                content = .terminal(.zmx(zmx))
            case .zellij:
                return
            }
        }
    }

    var zellijSessionName: String? {
        guard case .terminal(let terminal) = content else { return nil }
        return terminal.zellijSessionName
    }

    var zmxSessionName: String? {
        guard case .terminal(let terminal) = content else { return nil }
        return terminal.zmxSessionName
    }

    var zmxRootSessionName: String? {
        guard case .terminal(let terminal) = content else { return nil }
        return terminal.zmxRootSessionName
    }

    var isTerminal: Bool {
        switch content {
        case .terminal: true
        case .web, .inspection: false
        }
    }

    var isWeb: Bool {
        if case .web = content { return true }
        return false
    }

    var isInspection: Bool {
        if case .inspection = content { return true }
        return false
    }

    var isSideBoard: Bool {
        if case .sideBoard = role { return true }
        return false
    }

    var sideBoardTargetBoardID: UUID? {
        guard case .sideBoard(let targetBoardID) = role else { return nil }
        return targetBoardID
    }

    var isZellij: Bool {
        guard case .terminal(.zellij) = content else { return false }
        return true
    }

    var isZmx: Bool {
        guard case .terminal(.zmx) = content else { return false }
        return true
    }

    var systemSymbol: SFSymbol {
        switch content {
        case .web: .globe
        case .inspection: .magnifyingglass
        case .terminal(.shell): .appleTerminal
        case .terminal(.zellij): .rectangle3Group
        case .terminal(.zmx): .appleTerminalOnRectangle
        }
    }

    var displayName: String {
        customLabel ?? label
    }

    var defaultEssentialName: String {
        displayName
    }

    var essentialInput: String? {
        switch content {
        case .web(let web):
            return (web.currentSheetURL ?? web.firstSheetURL)?.absoluteString
        case .inspection:
            return nil
        case .terminal(.shell(let workingDirectory)):
            let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
            return workingDirectory == homeDirectory ? ":terminal" : ":terminal \(workingDirectory)"
        case .terminal(.zellij(let zellij)):
            return zellij.sessionName.map { ":zellij \($0)" } ?? ":zellij"
        case .terminal(.zmx(let zmx)):
            return zmx.sessionName.isEmpty ? ":zmx" : ":zmx \(zmx.sessionName)"
        }
    }

    static func constrainedWidth(_ width: Double) -> Double {
        min(max(width, minimumWidth), maximumWidth)
    }

    init(
        id: UUID = UUID(),
        label: String,
        width: Double,
        currentSheetURL: URL?,
        firstSheetURL: URL? = nil,
        customLabel: String? = nil,
        sheetNavigationPaused: Bool = false
    ) {
        self.id = id
        self.label = label
        self.width = width
        content = .web(
            WebBoardState(
                currentSheetURL: currentSheetURL,
                firstSheetURL: firstSheetURL ?? currentSheetURL,
                sheetNavigationPaused: sheetNavigationPaused))
        role = .primary
        self.customLabel = customLabel
    }

    init(
        id: UUID = UUID(),
        label: String = "Terminal",
        width: Double,
        workingDirectory: String,
        customLabel: String? = nil
    ) {
        self.id = id
        self.label = label
        self.width = width
        content = .terminal(.shell(workingDirectory: workingDirectory))
        role = .primary
        self.customLabel = customLabel
    }

    init(
        id: UUID = UUID(),
        label: String = "Zellij",
        width: Double,
        zellijSessionName: String?,
        customLabel: String? = nil
    ) {
        self.id = id
        self.label = label
        self.width = width
        content = .terminal(.zellij(ZellijBoardState(sessionName: zellijSessionName)))
        role = .primary
        self.customLabel = customLabel
    }

    init(
        id: UUID = UUID(),
        label: String = "zmx",
        width: Double,
        zmxSessionName: String,
        workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
        rootSessionName: String? = nil,
        customLabel: String? = nil
    ) {
        self.id = id
        self.label = label
        self.width = width
        content = .terminal(
            .zmx(
                ZmxBoardState(
                    sessionName: zmxSessionName,
                    workingDirectory: workingDirectory,
                    rootSessionName: rootSessionName)))
        role = .primary
        self.customLabel = customLabel
    }

    init(id: UUID = UUID(), label: String = "Inspection Board", width: Double, targetBoardID: UUID) {
        self.id = id
        self.label = label
        self.width = width
        content = .inspection
        role = .sideBoard(targetBoardID: targetBoardID)
        customLabel = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, width, content, role, customLabel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        width = try container.decode(Double.self, forKey: .width)
        customLabel = try container.decodeIfPresent(String.self, forKey: .customLabel)
        if let role = try container.decodeIfPresent(BoardRole.self, forKey: .role) {
            self.role = role
        } else {
            role = .primary
        }
        content = try container.decode(BoardContentState.self, forKey: .content)
        if case .inspection = content, !isSideBoard {
            throw DecodingError.dataCorruptedError(
                forKey: .role,
                in: container,
                debugDescription: "An Inspection Board must belong to a Board Group as its Side Board.")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(width, forKey: .width)
        try container.encode(content, forKey: .content)
        try container.encode(role, forKey: .role)
        try container.encodeIfPresent(customLabel, forKey: .customLabel)
    }
}

struct BoardGroup: Equatable, Identifiable {
    var primaryBoard: BoardState
    var sideBoard: BoardState?

    var id: UUID { primaryBoard.id }

    var boards: [BoardState] {
        if let sideBoard { [primaryBoard, sideBoard] } else { [primaryBoard] }
    }

    static func containing(_ boardID: UUID, in boards: [BoardState]) -> BoardGroup? {
        guard let selectedBoard = boards.first(where: { $0.id == boardID }) else { return nil }
        let primaryID = selectedBoard.sideBoardTargetBoardID ?? selectedBoard.id
        guard let primaryBoard = boards.first(where: { $0.id == primaryID }) else {
            return BoardGroup(primaryBoard: selectedBoard, sideBoard: nil)
        }
        let sideBoards = boards.filter {
            $0.id != primaryBoard.id && $0.sideBoardTargetBoardID == primaryBoard.id
        }
        guard sideBoards.count <= 1 else { return nil }
        return BoardGroup(primaryBoard: primaryBoard, sideBoard: sideBoards.first)
    }
}
