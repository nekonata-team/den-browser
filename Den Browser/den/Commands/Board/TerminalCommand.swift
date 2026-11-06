import ArgumentParser
import DenIPCProtocol

struct TerminalTextCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "text",
        abstract: "Print visible screen text or recent history from the target Terminal Board")

    @OptionGroup var target: BoardTargetOptions
    @Option(help: "Read the last N lines of retained history, including the screen (must be positive)")
    var lines: Int?

    func validate() throws {
        if let lines, lines <= 0 {
            throw ValidationError("--lines must be a positive integer")
        }
    }

    func run() throws {
        try DenIPCClient.execute(
            operation: .terminal(command: .text(lines: lines), target: try DenIPCClient.boardTarget(target.boardID)),
            options: target.common
        )
    }
}

struct TerminalSendCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "send",
        abstract: "Send text to the target Terminal Board")

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Text to send to the terminal") var text: String

    func run() throws {
        try DenIPCClient.execute(
            operation: .terminal(command: .send(text: text), target: try DenIPCClient.boardTarget(target.boardID)),
            options: target.common
        )
    }
}

struct TerminalRunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run a shell command in the target Terminal Board")

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Shell command to run") var command: String

    func run() throws {
        try DenIPCClient.execute(
            operation: .terminal(
                command: .run(command: command), target: try DenIPCClient.boardTarget(target.boardID)),
            options: target.common
        )
    }
}

struct TerminalKillCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "kill",
        abstract: "Send a signal to the foreground process group of the target Terminal Board")

    @OptionGroup var target: BoardTargetOptions
    @Option(name: [.short, .customLong("signal")], help: "Signal name or number to send (default: TERM)")
    var signal: String = "TERM"

    func run() throws {
        try DenIPCClient.execute(
            operation: .terminal(
                command: .kill(signal: signal), target: try DenIPCClient.boardTarget(target.boardID)),
            options: target.common
        )
    }
}
