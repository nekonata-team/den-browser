import ArgumentParser
import Foundation

struct BoardInspectionReadCommand: ParsableCommand {
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
