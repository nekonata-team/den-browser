import ArgumentParser

struct DenCLI: ParsableCommand {
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
        ]
    )
}

DenCLI.main()
