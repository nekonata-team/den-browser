import ArgumentParser
import Foundation

struct BoardCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "board",
        abstract: "Inspect and manage boards on the active Desk",
        subcommands: [
            BoardListCommand.self,
            BoardNewCommand.self,
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

    func run() throws {
        try DenIPCClient.execute(command: "board.new", args: [url], target: target)
    }
}
