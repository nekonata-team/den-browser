import ArgumentParser
import DenIPCProtocol

struct HealthCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "health",
        abstract: "Check whether Den Browser is ready"
    )

    @OptionGroup var options: CLIOptions

    func run() throws {
        try DenIPCClient.execute(operation: .health, options: options)
    }
}
