import ArgumentParser

struct DenCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "den",
        abstract: "Control Den Browser Web Boards from terminal",
        subcommands: [
            SheetCommand.self,
            BoardCommand.self,
            DeskCommand.self,
            DrawerCommand.self,
        ]
    )
}

DenCLI.main()
