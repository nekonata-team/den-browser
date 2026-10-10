import DenDomain
import Foundation

public struct DenFeedback: Equatable, Identifiable {
    public let id = UUID()
    public let title: String?
    public let body: String
    public let severity: Severity
    public let target: Target?

    public var message: String {
        [title, body.isEmpty ? nil : body]
            .compactMap { $0 }
            .joined(separator: ": ")
    }

    public init(
        title: String? = nil,
        body: String,
        severity: Severity = .info,
        target: Target? = nil
    ) {
        self.title = title?.isEmpty == false ? title : nil
        self.body = body
        self.severity = severity
        self.target = target
    }

    public enum Severity: Equatable {
        case success
        case info
        case warning
        case error
    }

    public enum Target: Equatable {
        case board(BoardID)
        case drawerItem(UUID)
        case notification(UUID)
    }
}
