import ArgumentParser
import Foundation

struct DeskCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "desk",
        abstract: "Inspect and manage Desks in the Den",
        subcommands: [
            DeskListCommand.self
        ]
    )
}

struct DeskListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all Desks in the Den")

    @OptionGroup var options: CLIOptions

    func run() throws {
        try DenIPCClient.execute(command: .desk(.list), options: options)
    }
}
