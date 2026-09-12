import ArgumentParser
import Foundation

struct ProfileCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "profile",
        abstract: "Inspect profiles in Den Browser",
        subcommands: [
            ProfileListCommand.self
        ]
    )
}

struct ProfileListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all profiles in Den Browser"
    )

    @OptionGroup var options: CLIOptions

    func run() throws {
        try DenIPCClient.execute(command: .profile(.list), args: [], options: options)
    }
}
