import Foundation

public struct BoardState: Codable, Equatable, Identifiable {
    public static let minimumWidth = 280.0
    public static let maximumWidth = 1_400.0

    public var id: UUID
    public var label: String
    public var width: Double
    public var kind: BoardKind
    public var role: BoardRole
    public var customLabel: String?

    public var sheetNavigationPaused: Bool {
        get {
            guard case .web(let web) = kind else { return false }
            return web.sheetNavigationPaused
        }
        set {
            guard case .web(var web) = kind else { return }
            web.sheetNavigationPaused = newValue
            kind = .web(web)
        }
    }

    public var currentSheetURL: URL? {
        get {
            guard case .web(let web) = kind else { return nil }
            return web.currentSheetURL
        }
        set {
            guard case .web(var web) = kind else { return }
            web.currentSheetURL = newValue.map(WebURLPolicy.canonicalSheetURL)
            kind = .web(web)
        }
    }

    public var firstSheetURL: URL? {
        get {
            guard case .web(let web) = kind else { return nil }
            return web.firstSheetURL
        }
        set {
            guard case .web(var web) = kind else { return }
            web.firstSheetURL = newValue.map(WebURLPolicy.canonicalSheetURL)
            kind = .web(web)
        }
    }

    public var terminalWorkingDirectory: String? {
        get {
            guard case .terminal(let terminal) = kind else { return nil }
            return terminal.workingDirectory
        }
        set {
            guard let newValue else { return }
            guard case .terminal(let terminal) = kind else { return }
            switch terminal {
            case .shell:
                kind = .terminal(.shell(workingDirectory: newValue))
            case .zmx(var zmx):
                zmx.workingDirectory = newValue
                kind = .terminal(.zmx(zmx))
            case .zellij:
                return
            }
        }
    }

    public var zellijSessionName: String? {
        guard case .terminal(let terminal) = kind else { return nil }
        return terminal.zellijSessionName
    }

    public var zmxSessionName: String? {
        guard case .terminal(let terminal) = kind else { return nil }
        return terminal.zmxSessionName
    }

    public var zmxRootSessionName: String? {
        get {
            guard case .terminal(let terminal) = kind else { return nil }
            return terminal.zmxRootSessionName
        }
        set {
            guard case .terminal(.zmx(var zmx)) = kind else { return }
            zmx.rootSessionName = newValue
            kind = .terminal(.zmx(zmx))
        }
    }

    public var isTerminal: Bool {
        switch kind {
        case .terminal: true
        case .web, .inspection, .tutorial: false
        }
    }

    public var isWeb: Bool {
        if case .web = kind { return true }
        return false
    }

    public var isInspection: Bool {
        if case .inspection = kind { return true }
        return false
    }

    public var isTutorial: Bool {
        if case .tutorial = kind { return true }
        return false
    }

    public var tutorialCompletedSteps: Set<TutorialBoardStep>? {
        guard case .tutorial(let tutorial) = kind else { return nil }
        return tutorial.completedSteps
    }

    public var isSideBoard: Bool {
        if case .sideBoard = role { return true }
        return false
    }

    public var sideBoardTargetBoardID: UUID? {
        guard case .sideBoard(let targetBoardID) = role else { return nil }
        return targetBoardID
    }

    public var isZellij: Bool {
        guard case .terminal(.zellij) = kind else { return false }
        return true
    }

    public var isZmx: Bool {
        guard case .terminal(.zmx) = kind else { return false }
        return true
    }

    public var displayName: String {
        customLabel ?? label
    }

    public var defaultEssentialName: String {
        displayName
    }

    public var essentialInput: String? {
        switch kind {
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
        case .tutorial:
            return nil
        }
    }

    public static func constrainedWidth(_ width: Double) -> Double {
        min(max(width, minimumWidth), maximumWidth)
    }

    public init(
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
        kind = .web(
            WebBoardState(
                currentSheetURL: currentSheetURL,
                firstSheetURL: firstSheetURL ?? currentSheetURL,
                sheetNavigationPaused: sheetNavigationPaused))
        role = .primary
        self.customLabel = customLabel
    }

    public init(
        id: UUID = UUID(),
        label: String = "Terminal",
        width: Double,
        workingDirectory: String,
        customLabel: String? = nil
    ) {
        self.id = id
        self.label = label
        self.width = width
        kind = .terminal(.shell(workingDirectory: workingDirectory))
        role = .primary
        self.customLabel = customLabel
    }

    public init(
        id: UUID = UUID(),
        label: String = "Zellij",
        width: Double,
        zellijSessionName: String?,
        customLabel: String? = nil
    ) {
        self.id = id
        self.label = label
        self.width = width
        kind = .terminal(.zellij(ZellijBoardState(sessionName: zellijSessionName)))
        role = .primary
        self.customLabel = customLabel
    }

    public init(
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
        kind = .terminal(
            .zmx(
                ZmxBoardState(
                    sessionName: zmxSessionName,
                    workingDirectory: workingDirectory,
                    rootSessionName: rootSessionName)))
        role = .primary
        self.customLabel = customLabel
    }

    public init(id: UUID = UUID(), label: String = "Inspection Board", width: Double, targetBoardID: UUID) {
        self.id = id
        self.label = label
        self.width = width
        kind = .inspection
        role = .sideBoard(targetBoardID: targetBoardID)
        customLabel = nil
    }

    public init(
        id: UUID = UUID(),
        label: String = "Tutorial",
        width: Double,
        tutorial: TutorialBoardState = TutorialBoardState()
    ) {
        self.id = id
        self.label = label
        self.width = width
        kind = .tutorial(tutorial)
        role = .primary
        customLabel = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, width, role, customLabel
        case kind = "content"
    }

    public init(from decoder: Decoder) throws {
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
        kind = try container.decode(BoardKind.self, forKey: .kind)
        if case .inspection = kind, !isSideBoard {
            throw DecodingError.dataCorruptedError(
                forKey: .role,
                in: container,
                debugDescription: "An Inspection Board must belong to a Board Group as its Side Board.")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(width, forKey: .width)
        try container.encode(kind, forKey: .kind)
        try container.encode(role, forKey: .role)
        try container.encodeIfPresent(customLabel, forKey: .customLabel)
    }
}
