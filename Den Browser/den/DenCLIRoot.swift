import ArgumentParser

@main
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct DenCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "den",
        abstract: "Control and inspect Den Browser from terminal or external shell",
        subcommands: [
            HealthCommand.self,
            SheetCommand.self,
            BoardCommand.self,
            DeskCommand.self,
            DrawerCommand.self,
            TerminalCommand.self,
            ProfileCommand.self,
            MCPCommand.self,
        ]
    )
}
