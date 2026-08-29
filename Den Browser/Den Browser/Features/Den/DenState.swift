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
    var scrollOffsetX: Double?

    init(
        id: UUID = UUID(),
        label: String,
        boards: [BoardState],
        focusedBoardID: UUID? = nil,
        scrollOffsetX: Double? = nil
    ) {
        self.id = id
        self.label = label
        self.boards = boards
        self.focusedBoardID = focusedBoardID ?? boards.first?.id
        self.scrollOffsetX = scrollOffsetX
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

enum DeskPresetBoardContent: Codable, Equatable {
    case web(URL?)
    case terminal(String)
    case zellij(String?)
    case zmx(String)

    private enum CodingKeys: String, CodingKey { case kind, initialSheetURL, workingDirectory, sessionName }
    private enum Kind: String, Codable { case web, terminal, zellij, zmx }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .web:
            self = .web(try container.decodeIfPresent(URL.self, forKey: .initialSheetURL))
        case .terminal:
            self = .terminal(try container.decode(String.self, forKey: .workingDirectory))
        case .zellij:
            self = .zellij(try container.decodeIfPresent(String.self, forKey: .sessionName))
        case .zmx:
            self = .zmx(try container.decode(String.self, forKey: .sessionName))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .web(let url):
            try container.encode(Kind.web, forKey: .kind)
            try container.encodeIfPresent(url, forKey: .initialSheetURL)
        case .terminal(let workingDirectory):
            try container.encode(Kind.terminal, forKey: .kind)
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

struct DeskPresetBoard: Codable, Equatable {
    var label: String
    var width: Double
    var content: DeskPresetBoardContent
    var customLabel: String?

    var initialSheetURL: URL? {
        guard case .web(let url) = content else { return nil }
        return url
    }

    var terminalWorkingDirectory: String? {
        guard case .terminal(let path) = content else { return nil }
        return path
    }

    var zellijSessionName: String? {
        guard case .zellij(let sessionName) = content else { return nil }
        return sessionName
    }

    var zmxSessionName: String? {
        guard case .zmx(let sessionName) = content else { return nil }
        return sessionName
    }

    nonisolated init(label: String, width: Double, initialSheetURL: URL?, customLabel: String? = nil) {
        self.label = label
        self.width = width
        content = .web(initialSheetURL)
        self.customLabel = customLabel
    }

    nonisolated init(label: String, width: Double, workingDirectory: String, customLabel: String? = nil) {
        self.label = label
        self.width = width
        content = .terminal(workingDirectory)
        self.customLabel = customLabel
    }

    nonisolated init(label: String, width: Double, zellijSessionName: String?, customLabel: String? = nil) {
        self.label = label
        self.width = width
        content = .zellij(zellijSessionName)
        self.customLabel = customLabel
    }

    nonisolated init(label: String, width: Double, zmxSessionName: String, customLabel: String? = nil) {
        self.label = label
        self.width = width
        content = .zmx(zmxSessionName)
        self.customLabel = customLabel
    }

    nonisolated init(board: BoardState) {
        switch board.content {
        case .web(let web):
            self.init(
                label: board.label,
                width: board.width,
                initialSheetURL: web.currentSheetURL,
                customLabel: board.customLabel)
        case .terminal(let terminal):
            self.init(
                label: board.label,
                width: board.width,
                workingDirectory: terminal.workingDirectory,
                customLabel: board.customLabel)
        case .zellij(let zellij):
            self.init(
                label: board.label,
                width: board.width,
                zellijSessionName: zellij.sessionName,
                customLabel: board.customLabel)
        case .zmx(let zmx):
            self.init(
                label: board.label,
                width: board.width,
                zmxSessionName: zmx.sessionName,
                customLabel: board.customLabel)
        }
    }

    func makeBoard() -> BoardState {
        switch content {
        case .web(let initialSheetURL):
            BoardState(
                label: label,
                width: width,
                currentSheetURL: initialSheetURL,
                firstSheetURL: initialSheetURL,
                customLabel: customLabel)
        case .terminal(let workingDirectory):
            BoardState(
                label: label,
                width: width,
                workingDirectory: workingDirectory,
                customLabel: customLabel)
        case .zellij(let sessionName):
            BoardState(
                label: label,
                width: width,
                zellijSessionName: sessionName,
                customLabel: customLabel)
        case .zmx(let sessionName):
            BoardState(
                label: label,
                width: width,
                zmxSessionName: sessionName,
                customLabel: customLabel)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case label, width, content, customLabel, initialSheetURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        width = try container.decode(Double.self, forKey: .width)
        customLabel = try container.decodeIfPresent(String.self, forKey: .customLabel)
        if let content = try container.decodeIfPresent(DeskPresetBoardContent.self, forKey: .content) {
            self.content = content
        } else {
            content = .web(try container.decodeIfPresent(URL.self, forKey: .initialSheetURL))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        try container.encode(width, forKey: .width)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(customLabel, forKey: .customLabel)
    }
}

struct WebBoardState: Codable, Equatable {
    var currentSheetURL: URL?
    var firstSheetURL: URL?
}

struct TerminalBoardState: Codable, Equatable {
    var workingDirectory: String
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

enum BoardContentState: Codable, Equatable {
    case web(WebBoardState)
    case terminal(TerminalBoardState)
    case zellij(ZellijBoardState)
    case zmx(ZmxBoardState)

    private enum CodingKeys: String, CodingKey {
        case kind, currentSheetURL, firstSheetURL, workingDirectory, sessionName, rootSessionName
    }
    private enum Kind: String, Codable { case web, terminal, zellij, zmx }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .web:
            self = .web(
                WebBoardState(
                    currentSheetURL: try container.decodeIfPresent(URL.self, forKey: .currentSheetURL),
                    firstSheetURL: try container.decodeIfPresent(URL.self, forKey: .firstSheetURL)))
        case .terminal:
            self = .terminal(
                TerminalBoardState(
                    workingDirectory: try container.decode(String.self, forKey: .workingDirectory)))
        case .zellij:
            self = .zellij(
                ZellijBoardState(
                    sessionName: try container.decodeIfPresent(String.self, forKey: .sessionName)))
        case .zmx:
            self = .zmx(
                ZmxBoardState(
                    sessionName: try container.decode(String.self, forKey: .sessionName),
                    workingDirectory: try container.decode(String.self, forKey: .workingDirectory),
                    rootSessionName: try container.decodeIfPresent(
                        String.self,
                        forKey: .rootSessionName)))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .web(let web):
            try container.encode(Kind.web, forKey: .kind)
            try container.encodeIfPresent(web.currentSheetURL, forKey: .currentSheetURL)
            try container.encodeIfPresent(web.firstSheetURL, forKey: .firstSheetURL)
        case .terminal(let terminal):
            try container.encode(Kind.terminal, forKey: .kind)
            try container.encode(terminal.workingDirectory, forKey: .workingDirectory)
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

struct BoardState: Codable, Equatable, Identifiable {
    static let minimumWidth = 280.0
    static let maximumWidth = 1_400.0

    var id: UUID
    var label: String
    var width: Double
    var content: BoardContentState
    var customLabel: String?
    var sheetNavigationPaused: Bool

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
            switch content {
            case .terminal(let terminal): terminal.workingDirectory
            case .zmx(let zmx): zmx.workingDirectory
            case .web, .zellij: nil
            }
        }
        set {
            guard let newValue else { return }
            switch content {
            case .terminal:
                content = .terminal(TerminalBoardState(workingDirectory: newValue))
            case .zmx(var zmx):
                zmx.workingDirectory = newValue
                content = .zmx(zmx)
            case .web, .zellij:
                return
            }
        }
    }

    var zellijSessionName: String? {
        guard case .zellij(let zellij) = content else { return nil }
        return zellij.sessionName
    }

    var zmxSessionName: String? {
        guard case .zmx(let zmx) = content else { return nil }
        return zmx.sessionName
    }

    var zmxRootSessionName: String? {
        guard case .zmx(let zmx) = content else { return nil }
        return zmx.rootSessionName
    }

    var isTerminal: Bool {
        switch content {
        case .terminal, .zellij, .zmx: true
        case .web: false
        }
    }

    var isZellij: Bool {
        guard case .zellij = content else { return false }
        return true
    }

    var isZmx: Bool {
        guard case .zmx = content else { return false }
        return true
    }

    var displayName: String {
        customLabel ?? label
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
        let canonicalCurrentSheetURL = currentSheetURL.map(SheetURLPolicy.canonicalSheetURL)
        self.id = id
        self.label = label
        self.width = width
        content = .web(
            WebBoardState(
                currentSheetURL: canonicalCurrentSheetURL,
                firstSheetURL: firstSheetURL.map(SheetURLPolicy.canonicalSheetURL) ?? canonicalCurrentSheetURL))
        self.customLabel = customLabel
        self.sheetNavigationPaused = sheetNavigationPaused
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
        content = .terminal(TerminalBoardState(workingDirectory: workingDirectory))
        self.customLabel = customLabel
        sheetNavigationPaused = false
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
        content = .zellij(ZellijBoardState(sessionName: zellijSessionName))
        self.customLabel = customLabel
        sheetNavigationPaused = false
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
        content = .zmx(
            ZmxBoardState(
                sessionName: zmxSessionName,
                workingDirectory: workingDirectory,
                rootSessionName: rootSessionName))
        self.customLabel = customLabel
        sheetNavigationPaused = false
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, width, content, customLabel, sheetNavigationPaused, currentSheetURL, firstSheetURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        width = try container.decode(Double.self, forKey: .width)
        customLabel = try container.decodeIfPresent(String.self, forKey: .customLabel)
        sheetNavigationPaused = try container.decodeIfPresent(Bool.self, forKey: .sheetNavigationPaused) ?? false
        if let content = try container.decodeIfPresent(BoardContentState.self, forKey: .content) {
            self.content = content
        } else {
            let current = try container.decodeIfPresent(URL.self, forKey: .currentSheetURL)
                .map(SheetURLPolicy.canonicalSheetURL)
            let first = try container.decodeIfPresent(URL.self, forKey: .firstSheetURL)
                .map(SheetURLPolicy.canonicalSheetURL)
            content = .web(WebBoardState(currentSheetURL: current, firstSheetURL: first))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(width, forKey: .width)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(customLabel, forKey: .customLabel)
        if sheetNavigationPaused {
            try container.encode(true, forKey: .sheetNavigationPaused)
        }
    }
}
