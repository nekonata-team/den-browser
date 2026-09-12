import ArgumentParser
import Foundation

struct ProfileCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "profile",
        abstract: "Inspect and manage profiles in Den Browser",
        subcommands: [
            ProfileListCommand.self,
            ProfileOpenCommand.self,
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

struct ProfileOpenCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "open",
        abstract: "Open or activate a window for a profile"
    )

    @Argument(help: "Profile UUID to open")
    var profileID: String?

    @OptionGroup var options: CLIOptions

    func run() throws {
        let args = [profileID].compactMap { $0 }
        try DenIPCClient.execute(command: .profile(.open), args: args, options: options)
    }
}
