import ArgumentParser
import DenIPCProtocol
import Foundation

struct DeskCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "desk",
        abstract: "Inspect and manage Desks in the Den",
        subcommands: [
            DeskListCommand.self,
            DeskNewCommand.self,
            DeskRemoveCommand.self,
        ]
    )
}

struct DeskNewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "new", abstract: "Create an empty Desk")

    @OptionGroup var options: CLIOptions
    @Argument(help: "Label for the new Desk") var label: String
    @Flag(name: .long, help: "Focus the new Desk") var focus = false

    func run() throws {
        try DenIPCClient.execute(operation: .createDesk(label: label, focus: focus), options: options)
    }
}

struct DeskRemoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "remove", abstract: "Remove a Desk")

    @OptionGroup var options: CLIOptions
    @Option(name: .customLong("desk"), help: "UUID of the Desk to remove") var deskID: String
    @Flag(name: .long, help: "Remove the Desk even if it contains Boards") var force = false

    func run() throws {
        try DenIPCClient.execute(
            operation: .removeDesk(deskID: try DenIPCClient.requiredDeskID(deskID), force: force), options: options)
    }
}

struct DeskListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all Desks in the Den")

    @OptionGroup var options: CLIOptions

    func run() throws {
        try DenIPCClient.execute(operation: .deskList(target: .automatic), options: options)
    }
}
