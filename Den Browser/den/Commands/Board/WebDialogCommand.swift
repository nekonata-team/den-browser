import ArgumentParser
import DenIPCProtocol
import Foundation

struct WebDialogCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dialog",
        abstract: "Inspect and respond to pending download save dialogs",
        subcommands: [WebDialogListCommand.self, WebDialogSaveCommand.self, WebDialogCancelCommand.self])
}

struct WebDialogListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List pending save dialogs")
    @OptionGroup var target: BoardTargetOptions

    func run() throws {
        try DenIPCClient.execute(
            operation: .sheet(command: .dialog(.list), target: try DenIPCClient.boardTarget(target.boardID)),
            options: target.common)
    }
}

struct WebDialogSaveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "save", abstract: "Choose a download destination")
    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Save dialog UUID") var id: String
    @Option(name: .long, help: "Destination file path, resolved relative to the CLI working directory") var path: String
    @Flag(name: .long, help: "Allow replacing an existing destination file") var overwrite = false

    func run() throws {
        guard !path.isEmpty else { throw ValidationError("Destination path must not be empty") }
        try DenIPCClient.execute(
            operation: .sheet(
                command: .dialog(
                    .save(
                        id: try dialogID(id), path: URL(fileURLWithPath: path).standardizedFileURL.path,
                        overwrite: overwrite)),
                target: try DenIPCClient.boardTarget(target.boardID)),
            options: target.common)
    }
}

struct WebDialogCancelCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "cancel", abstract: "Cancel a pending download")
    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Save dialog UUID") var id: String

    func run() throws {
        try DenIPCClient.execute(
            operation: .sheet(
                command: .dialog(.cancel(id: try dialogID(id))),
                target: try DenIPCClient.boardTarget(target.boardID)),
            options: target.common)
    }
}

private func dialogID(_ raw: String) throws -> UUID {
    guard let id = UUID(uuidString: raw) else { throw ValidationError("Invalid save dialog UUID: \(raw)") }
    return id
}
