import ArgumentParser
import Foundation

struct TerminalCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "terminal",
        abstract: "Inspect and control Terminal Boards on the active Desk",
        subcommands: [
            TerminalListCommand.self,
            TerminalNewCommand.self,
            TerminalTextCommand.self,
            TerminalSendCommand.self,
            TerminalKillCommand.self,
        ]
    )
}

struct TerminalListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all Terminal Boards on the active Desk")

    @OptionGroup var target: TargetOptions

    func run() throws {
        try DenIPCClient.execute(command: .terminal(.list), args: [], target: target)
    }
}

struct TerminalNewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Open a new Terminal Board")

    @OptionGroup var target: TargetOptions
    @Argument(help: "Working directory for the terminal board") var path: String?
    @Option(name: .customLong("run"), help: "Initial command to run in the terminal") var runCommand: String?
    @Flag(name: .long, help: "Focus the new terminal board") var focus = false

    func run() throws {
        var args: [String] = []
        if let path {
            let resolved = URL(fileURLWithPath: path).standardizedFileURL.path
            args.append(resolved)
        }
        if let runCommand {
            args.append(contentsOf: ["--run", runCommand])
        }
        if focus {
            args.append("--focus")
        }
        try DenIPCClient.execute(command: .terminal(.new), args: args, target: target)
    }
}

struct TerminalTextCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "text",
        abstract: "Print visible screen text from the target Terminal Board")

    @OptionGroup var target: TargetOptions

    func run() throws {
        try DenIPCClient.execute(command: .terminal(.text), args: [], target: target)
    }
}

struct TerminalSendCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "send",
        abstract: "Send text to the target Terminal Board")

    @OptionGroup var target: TargetOptions
    @Argument(help: "Text to send to the terminal") var text: String

    func run() throws {
        try DenIPCClient.execute(command: .terminal(.send), args: [text], target: target)
    }
}

struct TerminalKillCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "kill",
        abstract: "Send a signal to the foreground process group of the target Terminal Board")

    @OptionGroup var target: TargetOptions
    @Option(name: [.short, .customLong("signal")], help: "Signal name or number to send (default: TERM)")
    var signal: String = "TERM"

    func run() throws {
        try DenIPCClient.execute(command: .terminal(.kill), args: [signal], target: target)
    }
}
