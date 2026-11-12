import ArgumentParser
import DenIPCProtocol

struct WebBackgroundCommand: ParsableCommand {
    enum State: String, ExpressibleByArgument {
        case enabled = "on"
        case disabled = "off"
    }

    static let configuration = CommandConfiguration(
        commandName: "background",
        abstract: "Read or set Run in Background for a Web Board",
        discussion:
            "Without on or off, print the current setting. Changes apply immediately without reloading or focusing the Board. Enabling uses more energy."
    )

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Enable (on) or disable (off) background execution; omit to read the setting")
    var state: State?

    func run() throws {
        try DenIPCClient.execute(
            operation: .boardBackgroundExecution(
                enabled: state.map { $0 == .enabled },
                target: try DenIPCClient.boardTarget(target.boardID)
            ),
            options: target.common
        )
    }
}
