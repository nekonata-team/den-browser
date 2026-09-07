import ArgumentParser
import Foundation

struct SheetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sheet",
        abstract: "Inspect and control web screens in Web Boards",
        subcommands: [
            SheetOpenCommand.self,
            SheetURLCommand.self,
            SheetReloadCommand.self,
            SheetEvalCommand.self,
            SheetTextCommand.self,
        ]
    )
}

struct SheetOpenCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "open",
        abstract: "Navigate current sheet in target Web Board to a URL")

    @OptionGroup var target: TargetOptions
    @Argument(help: "URL or search query to open") var url: String

    func run() throws {
        try DenIPCClient.execute(command: "sheet.open", args: [url], target: target)
    }
}

struct SheetURLCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "url",
        abstract: "Print current URL of target Web Board")

    @OptionGroup var target: TargetOptions

    func run() throws {
        try DenIPCClient.execute(command: "sheet.url", args: [], target: target)
    }
}

struct SheetReloadCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reload",
        abstract: "Reload current sheet in target Web Board")

    @OptionGroup var target: TargetOptions

    func run() throws {
        try DenIPCClient.execute(command: "sheet.reload", args: [], target: target)
    }
}

struct SheetEvalCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "eval",
        abstract: "Evaluate JavaScript in target Web Board")

    @OptionGroup var target: TargetOptions
    @Argument(parsing: .remaining, help: "JavaScript code to evaluate") var scriptParts: [String]

    func run() throws {
        let script = scriptParts.joined(separator: " ")
        guard !script.isEmpty else {
            throw ValidationError("Please provide JavaScript code to evaluate")
        }
        try DenIPCClient.execute(command: "sheet.eval", args: [script], target: target)
    }
}

struct SheetTextCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "text",
        abstract: "Print visible text of target Web Board")

    @OptionGroup var target: TargetOptions

    func run() throws {
        try DenIPCClient.execute(command: "sheet.text", args: [], target: target)
    }
}
