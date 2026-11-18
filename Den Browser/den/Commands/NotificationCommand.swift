import ArgumentParser
import DenIPCProtocol
import Foundation

struct NotificationCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "notification",
        abstract: "Send and manage Notifications",
        subcommands: [
            NotificationListCommand.self, NotificationReadCommand.self, NotificationUnreadCommand.self,
            NotificationSendCommand.self,
        ]
    )
}

struct NotificationListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List Notifications, newest first, without marking them as read"
    )

    @OptionGroup var options: CLIOptions
    @Flag(name: .long, help: "List only unread Notifications") var unread = false
    @Option(name: .long, help: "Filter by the source Board UUID") var board: String?
    @Option(name: .long, help: "Return at most N matching Notifications (positive integer)") var limit: Int?

    func run() throws {
        if let limit, limit <= 0 { throw ValidationError("--limit must be a positive integer") }
        try DenIPCClient.execute(
            operation: .listNotifications(
                unreadOnly: unread,
                boardID: try board.map { try DenIPCClient.requiredBoardID($0) },
                limit: limit
            ),
            options: options
        )
    }
}

struct NotificationReadCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read",
        abstract: "Mark a Notification as read without opening its Board"
    )

    @OptionGroup var options: CLIOptions
    @Argument(help: "UUID of the Notification to mark as read") var id: String

    func run() throws {
        try DenIPCClient.execute(operation: try notificationReadOperation(id: id, isRead: true), options: options)
    }
}

struct NotificationUnreadCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unread",
        abstract: "Mark a Notification as unread without opening its Board"
    )

    @OptionGroup var options: CLIOptions
    @Argument(help: "UUID of the Notification to mark as unread") var id: String

    func run() throws {
        try DenIPCClient.execute(operation: try notificationReadOperation(id: id, isRead: false), options: options)
    }
}

struct NotificationSendCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "send",
        abstract: "Send a Notification with a UTF-8 body read from standard input"
    )

    @OptionGroup var options: CLIOptions
    @Option(name: .long, help: "Source Terminal Board UUID (defaults to DEN_BOARD_ID)") var board: String?
    @Option(name: .long, help: "Notification title") var title: String?

    func run() throws {
        try DenIPCClient.execute(operation: makeOperation(), options: options)
    }

    private func makeOperation() throws -> DenIPCOperation {
        let boardID = try board.map { try DenIPCClient.requiredBoardID($0) }
        guard isatty(STDIN_FILENO) == 0 else {
            throw ValidationError("Pipe or redirect a UTF-8 Notification body to standard input.")
        }
        guard let data = try FileHandle.standardInput.readToEnd(),
            let body = String(data: data, encoding: .utf8), !body.isEmpty
        else {
            throw ValidationError("Notification body must be non-empty UTF-8 text.")
        }
        return .sendNotification(title: title, body: body, boardID: boardID)
    }
}

private func notificationReadOperation(id: String, isRead: Bool) throws -> DenIPCOperation {
    guard let notificationID = UUID(uuidString: id) else {
        throw ValidationError("Invalid Notification ID: \(id). Expected a UUID; run 'den notification list'.")
    }
    return .setNotificationRead(id: notificationID, isRead: isRead)
}
