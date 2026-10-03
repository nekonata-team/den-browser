import ArgumentParser
import Foundation

private func validateBoardWidth(_ width: Double?) throws {
    guard let width else { return }
    guard width.isFinite, width > 0 else {
        throw ValidationError("Board width must be a finite positive number of points")
    }
}

struct BoardCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "board",
        abstract: "Inspect and manage Boards on the active Desk",
        subcommands: [
            BoardListCommand.self,
            BoardFocusedCommand.self,
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
            command: .board(.inspection(.new(DenBoardInspectionNewPayload(focus: focus)))),
            options: common,
            boardID: targetBoardID)
    }
}

struct BoardListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all Boards on the active Desk")

    @OptionGroup var options: BoardListOptions

    func run() throws {
        try DenIPCClient.execute(
            command: .board(.list),
            options: options.common,
            showBoardIDs: options.showBoardIDs)
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
            command: .board(.focused),
            options: options.common,
            showBoardIDs: options.showBoardIDs)
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
            SheetNavigateCommand.self,
            SheetURLCommand.self,
            SheetReloadCommand.self,
            SheetBackCommand.self,
            SheetForwardCommand.self,
            SheetPressCommand.self,
            SheetScrollCommand.self,
            SheetWaitCommand.self,
            SheetEvalCommand.self,
            SheetTextCommand.self,
            SheetSnapshotCommand.self,
            SheetQueryCommand.self,
            SheetGetCommand.self,
            SheetIsCommand.self,
            SheetClickCommand.self,
            SheetDblclickCommand.self,
            SheetFocusCommand.self,
            SheetFillCommand.self,
            SheetTypeCommand.self,
            SheetDragCommand.self,
            SheetMouseCommand.self,
            SheetInteractCommand.self,
            SheetScreenshotCommand.self,
        ]
    )
}

struct BoardWebNewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Open a new Web Board with a URL or search query")

    @OptionGroup var options: CLIOptions
    @Argument(help: "URL or search query for the new board") var url: String
    @Option(name: .long, help: "Initial Board width in points") var width: Double?
    @Flag(name: .long, help: "Focus the newly created Board")
    var focus: Bool = false

    func validate() throws {
        try validateBoardWidth(width)
    }

    func run() throws {
        try DenIPCClient.execute(
            command: .board(.web(.new(DenBoardWebNewPayload(url: url, focus: focus, width: width)))),
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
        abstract: "Open a new Terminal Board")

    @OptionGroup var options: CLIOptions
    @Argument(help: "Working directory for the terminal board") var path: String?
    @Option(name: .customLong("run"), help: "Initial command to run in the terminal") var runCommand: String?
    @Option(name: .long, help: "Initial Board width in points") var width: Double?
    @Flag(name: .long, help: "Focus the new terminal board") var focus = false

    func validate() throws {
        try validateBoardWidth(width)
    }

    func run() throws {
        let resolvedPath = path.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        try DenIPCClient.execute(
            command: .board(
                .terminal(
                    .new(
                        DenBoardTerminalNewPayload(
                            path: resolvedPath,
                            runCommand: runCommand,
                            focus: focus,
                            width: width
                        ))
                )
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
        try DenIPCClient.execute(command: .board(.close), options: options)
    }
}
