import ArgumentParser
import Foundation

struct BoardCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "board",
        abstract: "Inspect and manage boards on the active Desk",
        subcommands: [
            BoardListCommand.self,
            BoardNewCommand.self,
            BoardCloseCommand.self,
        ]
    )
}

struct BoardListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all boards on the active Desk")

    @OptionGroup var target: TargetOptions

    func run() throws {
        try DenIPCClient.execute(command: "board.list", args: [], target: target)
    }
}

struct BoardNewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Open a new Web Board with a URL")

    @OptionGroup var target: TargetOptions
    @Argument(help: "URL or search query for the new board") var url: String
    @Flag(name: .long, help: "Focus the newly created Board")
    var focus: Bool = false

    func run() throws {
        var args = [url]
        if focus {
            args.append("--focus")
        }
        try DenIPCClient.execute(command: "board.new", args: args, target: target)
    }
}

struct BoardCloseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "close",
        abstract: "Close the specified Board or target Web Board")

    @OptionGroup var target: TargetOptions
    @Argument(help: "UUID of the Board to close (optional, defaults to target Web Board)")
    var boardID: String?

    func run() throws {
        let args = boardID.map { [$0] } ?? []
        try DenIPCClient.execute(command: "board.close", args: args, target: target)
    }
}
