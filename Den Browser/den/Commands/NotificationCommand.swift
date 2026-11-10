import ArgumentParser
import DenIPCProtocol
import Foundation

struct NotificationCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "notification",
        abstract: "Inspect Notifications and manage their read status",
        subcommands: [NotificationListCommand.self, NotificationReadCommand.self, NotificationUnreadCommand.self])
}

struct NotificationListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list", abstract: "List Notifications, newest first, without marking them as read")

    @OptionGroup var options: CLIOptions
    @Flag(name: .long, help: "List only unread Notifications") var unread = false
    @Option(name: .long, help: "Filter by the source Board UUID") var board: String?
    @Option(name: .long, help: "Return at most N matching Notifications (positive integer)") var limit: Int?

    func run() throws {
        if let limit, limit <= 0 { throw ValidationError("--limit must be a positive integer") }
        try DenIPCClient.execute(
            operation: .listNotifications(
                unreadOnly: unread, boardID: try board.map { try DenIPCClient.requiredBoardID($0) }, limit: limit),
            options: options)
    }
}

struct NotificationReadCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read", abstract: "Mark a Notification as read without opening its Board")

    @OptionGroup var options: CLIOptions
    @Argument(help: "UUID of the Notification to mark as read") var id: String

    func run() throws {
        try DenIPCClient.execute(operation: try notificationReadOperation(id: id, isRead: true), options: options)
    }
}

struct NotificationUnreadCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unread", abstract: "Mark a Notification as unread without opening its Board")

    @OptionGroup var options: CLIOptions
    @Argument(help: "UUID of the Notification to mark as unread") var id: String

    func run() throws {
        try DenIPCClient.execute(operation: try notificationReadOperation(id: id, isRead: false), options: options)
    }
}

private func notificationReadOperation(id: String, isRead: Bool) throws -> DenIPCOperation {
    guard let notificationID = UUID(uuidString: id) else {
        throw ValidationError("Invalid Notification ID: \(id). Expected a UUID; run 'den notification list'.")
    }
    return .setNotificationRead(id: notificationID, isRead: isRead)
}
