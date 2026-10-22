import Foundation
import Observation

@MainActor
@Observable
public final class FeedbackModel {
    public private(set) var latest: DenFeedback?

    public init() {}

    @discardableResult
    public func publish(
        title: String?, body: String, severity: DenFeedback.Severity = .info, target: DenFeedback.Target? = nil
    ) -> DenFeedback? {
        guard title?.isEmpty == false || !body.isEmpty else { return nil }
        let feedback = DenFeedback(title: title, body: body, severity: severity, target: target)
        latest = feedback
        return feedback
    }

    @discardableResult
    public func clearNotification() -> Bool {
        guard case .notification? = latest?.target else { return false }
        latest = nil
        return true
    }
}
