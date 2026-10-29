import ArgumentParser
import DenIPCProtocol
import Foundation

private func validateBoardWidth(_ width: Double?) throws {
    guard let width else { return }
    guard width.isFinite, width > 0 else {
        throw ValidationError("Board width must be a finite positive number of points")
    }
}

struct BoardCreationOptions: ParsableArguments {
    static let discussion =
        "Specify at most one placement option: --left-of, --right-of, or --end-of. Without one, create after the caller's Board Group, otherwise the destination Desk's Focused Board Group."
    @Option(name: .customLong("end-of"), help: ArgumentHelp("Create at the end of this Desk", valueName: "desk-id"))
    var endOfDeskID: String?
    @Option(name: .customLong("left-of"), help: ArgumentHelp("Create left of this Board Group", valueName: "board-id"))
    var leftOf: String?
    @Option(
        name: .customLong("right-of"), help: ArgumentHelp("Create right of this Board Group", valueName: "board-id"))
    var rightOf: String?

    func destination() throws -> DenBoardCreationDestination {
        guard [endOfDeskID, leftOf, rightOf].compactMap({ $0 }).count <= 1 else {
            throw ValidationError("Specify at most one of --left-of, --right-of, or --end-of")
        }
        if let leftOf { return .leftOf(try DenIPCClient.requiredBoardID(leftOf)) }
        if let rightOf { return .rightOf(try DenIPCClient.requiredBoardID(rightOf)) }
        if let endOfDeskID { return .endOfDesk(try DenIPCClient.requiredDeskID(endOfDeskID)) }
        return .automatic
    }
}

struct BoardCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "board",
        abstract: "Inspect and manage Boards on the active Desk",
        subcommands: [
            BoardListCommand.self,
            BoardFocusedCommand.self,
            BoardExistsCommand.self,
            BoardFocusCommand.self,
            BoardMoveCommand.self,
            BoardWebCommand.self,
            BoardTerminalCommand.self,
            BoardInspectionCommand.self,
            BoardCloseCommand.self,
        ]
    )
}

struct BoardInspectionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspection",
        abstract: "Create Inspection Boards and read their selected elements",
        subcommands: [BoardInspectionNewCommand.self, BoardInspectionReadCommand.self])
}

struct BoardInspectionNewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Create or reuse an Inspection Board for a Web Board")

    @OptionGroup var common: CLIOptions

    @Option(name: .customLong("target"), help: "Target Web Board ID")
    var targetBoardID: String

    @Flag(name: .customLong("focus"), help: "Focus the Inspection Board")
    var focus = false

    func run() throws {
        try DenIPCClient.execute(
            operation: .createInspectionBoard(
                targetBoardID: try DenIPCClient.requiredBoardID(
                    targetBoardID,
                    invalidMessage: "Usage: den board inspection new --target <web-board-id>"
                ),
                payload: DenBoardInspectionNewPayload(focus: focus)
            ),
            options: common,
        )
    }
}

struct BoardListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all Boards on the selected Desk")

    @OptionGroup var options: BoardListOptions
    @Option(name: .customLong("desk"), help: "Target Desk UUID (defaults to the ambient Desk)") var deskID: String?

    func run() throws {
        try DenIPCClient.execute(
            operation: .boardList(target: try DenIPCClient.deskTarget(deskID)),
            options: options.common,
            showBoardIDs: options.showBoardIDs)
    }
}

struct BoardExistsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "exists",
        abstract: "Check whether a Board exists across open Profiles, optionally limited by --profile",
        discussion:
            "Ignores DEN_PROFILE and DEN_BOARD_ID. Closed Profiles do not match."
    )

    @OptionGroup var common: CLIOptions
    @Option(name: .customLong("board"), help: "Board UUID to look up") var boardID: String

    func run() throws {
        try DenIPCClient.execute(
            operation: .boardExists(boardID: try DenIPCClient.requiredBoardID(boardID)),
            options: common)
    }
}

struct BoardListOptions: ParsableArguments {
    @OptionGroup var common: CLIOptions

    @Flag(
        name: [.customShort("l"), .customLong("long")],
        help: "Show full Board IDs in human-readable output")
    var showBoardIDs = false
}

struct BoardFocusedCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "focused",
        abstract: "Show the currently focused Board on the active Desk")

    @OptionGroup var options: BoardFocusedOptions

    func run() throws {
        try DenIPCClient.execute(
            operation: .boardFocused(target: .automatic),
            options: options.common,
            showBoardIDs: options.showBoardIDs)
    }
}

struct BoardFocusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "focus",
        abstract: "Focus an existing Board and bring it into view without activating the window")

    @OptionGroup var common: CLIOptions

    @Option(name: .customLong("board"), help: "Board ID to focus")
    var boardID: String

    func run() throws {
        try DenIPCClient.execute(
            operation: .focusBoard(boardID: try DenIPCClient.requiredBoardID(boardID)),
            options: common
        )
    }
}

struct BoardFocusedOptions: ParsableArguments {
    @OptionGroup var common: CLIOptions

    @Flag(
        name: [.customShort("l"), .customLong("long")],
        help: "Show full Board ID in human-readable output")
    var showBoardIDs = false
}

struct BoardWebCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "web",
        abstract: "Create Web Boards and control their Current Sheets",
        subcommands: [
            BoardWebNewCommand.self,
            WebNavigateCommand.self,
            WebURLCommand.self,
            WebStatusCommand.self,
            WebDialogCommand.self,
            WebReloadCommand.self,
            WebBackCommand.self,
            WebForwardCommand.self,
            WebPressCommand.self,
            WebScrollCommand.self,
            WebWaitCommand.self,
            WebEvalCommand.self,
            WebTextCommand.self,
            WebSnapshotCommand.self,
            WebQueryCommand.self,
            WebGetCommand.self,
            WebIsCommand.self,
            WebClickCommand.self,
            WebDblclickCommand.self,
            WebFocusCommand.self,
            WebFillCommand.self,
            WebTypeCommand.self,
            WebDragCommand.self,
            WebMouseCommand.self,
            WebInteractCommand.self,
            WebScreenshotCommand.self,
        ]
    )
}

struct BoardWebNewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Open a new Web Board with a URL or search query",
        discussion: BoardCreationOptions.discussion)

    @OptionGroup var options: CLIOptions
    @Argument(help: "URL or search query for the new board") var url: String
    @OptionGroup(title: "Placement (mutually exclusive; optional)") var placement: BoardCreationOptions
    @Option(name: .long, help: "Initial Board width in points") var width: Double?
    @Flag(name: .long, help: "Focus the newly created Board")
    var focus: Bool = false

    func validate() throws {
        try validateBoardWidth(width)
    }

    func run() throws {
        try DenIPCClient.execute(
            operation: .createWebBoard(
                payload: DenBoardWebNewPayload(url: url, focus: focus, width: width),
                destination: try placement.destination()
            ),
            options: options
        )
    }
}

struct BoardTerminalCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "terminal",
        abstract: "Create Terminal Boards and control their Terminal Sessions",
        subcommands: [
            BoardTerminalNewCommand.self,
            TerminalTextCommand.self,
            TerminalSendCommand.self,
            TerminalRunCommand.self,
            TerminalKillCommand.self,
        ]
    )
}

struct BoardTerminalNewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Open a new Terminal Board",
        discussion: BoardCreationOptions.discussion)

    @OptionGroup var options: CLIOptions
    @Argument(help: "Working directory for the terminal board") var path: String?
    @OptionGroup(title: "Placement (mutually exclusive; optional)") var placement: BoardCreationOptions
    @Option(name: .customLong("run"), help: "Initial command to run in the terminal") var runCommand: String?
    @Option(name: .long, help: "Initial Board width in points") var width: Double?
    @Flag(name: .long, help: "Focus the new terminal board") var focus = false

    func validate() throws {
        try validateBoardWidth(width)
    }

    func run() throws {
        let resolvedPath = path.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        try DenIPCClient.execute(
            operation: .createTerminalBoard(
                payload: DenBoardTerminalNewPayload(
                    path: resolvedPath,
                    runCommand: runCommand,
                    focus: focus,
                    width: width
                ),
                destination: try placement.destination()
            ),
            options: options
        )
    }
}

struct BoardCloseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "close",
        abstract: "Close the specified Board or target Web Board")

    @OptionGroup var options: BoardTargetOptions

    func run() throws {
        try DenIPCClient.execute(
            operation: .boardClose(target: try DenIPCClient.boardTarget(options.boardID)),
            options: options.common
        )
    }
}

struct BoardMoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "move", abstract: "Move a Board Group beside another Board or to the end of a Desk",
        discussion:
            "Placement options are mutually exclusive: specify exactly one of --left-of, --right-of, or --end-of."
    )

    @OptionGroup var common: CLIOptions
    @Option(name: .customLong("board"), help: "Board ID to move") var boardID: String
    @Option(name: .customLong("left-of"), help: ArgumentHelp("Place left of this Board Group", valueName: "board-id"))
    var leftOf: String?
    @Option(name: .customLong("right-of"), help: ArgumentHelp("Place right of this Board Group", valueName: "board-id"))
    var rightOf: String?
    @Option(name: .customLong("end-of"), help: ArgumentHelp("Place at the end of this Desk", valueName: "desk-id"))
    var endOfDeskID: String?

    private func destination() throws -> DenBoardMoveDestination {
        guard [leftOf, rightOf, endOfDeskID].compactMap({ $0 }).count == 1 else {
            throw ValidationError("Specify exactly one of --left-of, --right-of, or --end-of")
        }
        if let leftOf { return .leftOf(try DenIPCClient.requiredBoardID(leftOf)) }
        if let rightOf { return .rightOf(try DenIPCClient.requiredBoardID(rightOf)) }
        if let endOfDeskID { return .endOfDesk(try DenIPCClient.requiredDeskID(endOfDeskID)) }
        throw ValidationError("Missing move destination")
    }

    func validate() throws {
        do {
            _ = try DenIPCClient.requiredBoardID(boardID)
            _ = try destination()
        } catch {
            throw ValidationError((error as? ValidationError)?.message ?? error.localizedDescription)
        }
    }

    func run() throws {
        try DenIPCClient.execute(
            operation: .moveBoard(boardID: try DenIPCClient.requiredBoardID(boardID), destination: try destination()),
            options: common)
    }
}
