import ArgumentParser
import Foundation

struct DrawerCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "drawer",
        abstract: "Inspect and manage Drawer Items in the Drawer",
        subcommands: [
            DrawerListCommand.self,
            DrawerKeepCommand.self,
            DrawerPlaceCommand.self,
            DrawerDiscardCommand.self,
        ]
    )
}

struct DrawerListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all Drawer Items in the Drawer")

    @OptionGroup var options: CLIOptions

    func run() throws {
        try DenIPCClient.execute(command: .drawer(.list), args: [], options: options)
    }
}

struct DrawerKeepCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keep",
        abstract: "Keep a URL in the Drawer as a Drawer Item")

    @OptionGroup var options: CLIOptions
    @Argument(help: "URL to keep in the Drawer") var url: String
    @Option(name: .long, help: "Optional title for the Drawer Item") var title: String?

    func run() throws {
        var args = [url]
        if let title {
            args.append(contentsOf: ["--title", title])
        }
        try DenIPCClient.execute(command: .drawer(.keep), args: args, options: options)
    }
}

struct DrawerPlaceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "place",
        abstract: "Place a Drawer Item into the active Desk as a Web Board")

    @OptionGroup var options: CLIOptions
    @Argument(help: "ID of the Drawer Item to place") var itemID: String

    func run() throws {
        try DenIPCClient.execute(command: .drawer(.place), args: [itemID], options: options)
    }
}

struct DrawerDiscardCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "discard",
        abstract: "Discard a Drawer Item without placing it into a Desk")

    @OptionGroup var options: CLIOptions
    @Argument(help: "ID of the Drawer Item to discard") var itemID: String

    func run() throws {
        try DenIPCClient.execute(command: .drawer(.discard), args: [itemID], options: options)
    }
}
