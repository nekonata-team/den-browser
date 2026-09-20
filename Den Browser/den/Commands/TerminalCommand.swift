import ArgumentParser

struct TerminalCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "terminal",
        abstract: "Inspect and control Terminal Sessions",
        subcommands: [
            TerminalTextCommand.self,
            TerminalSendCommand.self,
            TerminalRunCommand.self,
            TerminalKillCommand.self,
        ]
    )
}

struct TerminalTextCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "text",
        abstract: "Print visible screen text from the target Terminal Board")

    @OptionGroup var target: BoardTargetOptions

    func run() throws {
        try DenIPCClient.execute(command: .terminal(.text), options: target)
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
            command: .terminal(.send(text: text)),
            options: target
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
            command: .terminal(.run(command: command)),
            options: target
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
            command: .terminal(.kill(signal: signal)),
            options: target
        )
    }
}
