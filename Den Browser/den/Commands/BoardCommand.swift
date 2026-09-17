import ArgumentParser
import Foundation

struct BoardCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "board",
        abstract: "Inspect and manage Boards on the active Desk",
        subcommands: [
            BoardListCommand.self,
            BoardFocusedCommand.self,
            BoardWebCommand.self,
            BoardTerminalCommand.self,
            BoardCloseCommand.self,
        ]
    )
}

struct BoardListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all Boards on the active Desk")

    @OptionGroup var options: BoardListOptions

    func run() throws {
        try DenIPCClient.execute(
            command: .board(.list),
            args: [],
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
            args: [],
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
        abstract: "Manage Web Boards",
        subcommands: [
            BoardWebNewCommand.self
        ]
    )
}

struct BoardWebNewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Open a new Web Board with a URL or search query")

    @OptionGroup var options: CLIOptions
    @Argument(help: "URL or search query for the new board") var url: String
    @Flag(name: .long, help: "Focus the newly created Board")
    var focus: Bool = false

    func run() throws {
        var args = [url]
        if focus {
            args.append("--focus")
        }
        try DenIPCClient.execute(command: .board(.web(.new)), args: args, options: options)
    }
}

struct BoardTerminalCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "terminal",
        abstract: "Manage Terminal Boards",
        subcommands: [
            BoardTerminalNewCommand.self
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
    @Flag(name: .long, help: "Focus the new terminal board") var focus = false

    func run() throws {
        var args: [String] = []
        if let path {
            let resolved = URL(fileURLWithPath: path).standardizedFileURL.path
            args.append(resolved)
        }
        if let runCommand {
            args.append(contentsOf: ["--run", runCommand])
        }
        if focus {
            args.append("--focus")
        }
        try DenIPCClient.execute(command: .board(.terminal(.new)), args: args, options: options)
    }
}

struct BoardCloseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "close",
        abstract: "Close the specified Board or target Web Board")

    @OptionGroup var options: BoardTargetOptions

    func run() throws {
        try DenIPCClient.execute(command: .board(.close), args: [], options: options)
    }
}
