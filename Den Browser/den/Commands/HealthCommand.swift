import ArgumentParser

struct HealthCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "health",
        abstract: "Check whether Den Browser is ready"
    )

    @OptionGroup var target: TargetOptions

    func run() throws {
        try DenIPCClient.execute(command: .health, args: [], target: target)
    }
}
