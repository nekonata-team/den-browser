import DenDomain
import Foundation

struct DenFeedback: Equatable, Identifiable {
    let id = UUID()
    let title: String?
    let body: String
    let severity: Severity
    let target: Target?

    var message: String {
        [title, body.isEmpty ? nil : body]
            .compactMap { $0 }
            .joined(separator: ": ")
    }

    init(
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

    enum Severity: Equatable {
        case success
        case info
        case warning
        case error
    }

    enum Target: Equatable {
        case board(BoardID)
        case drawerItem(UUID)
        case notification(UUID)
    }
}
