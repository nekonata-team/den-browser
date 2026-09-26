import ArgumentParser
import Foundation

struct InspectionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspection",
        abstract: "Read an Inspection Board",
        subcommands: [InspectionReadCommand.self])
}

struct InspectionReadCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read",
        abstract: "Read the selected element and recent page events")

    @OptionGroup var options: CLIOptions

    @Option(name: .customLong("board"), help: "Inspection Board ID")
    var boardID: String

    func run() throws {
        try DenIPCClient.execute(command: .inspection(.read), options: options, boardID: boardID)
    }
}
